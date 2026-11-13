-- Window.lua -- the music window: what's playing, which extended tracks play
-- in each zone, and the ban list.
--
-- Built only from the game's own templates (ButtonFrameTemplate, tabs,
-- checkboxes, buttons), so it looks like a game window.
--
-- It does NOT go through the game's panel manager (ShowUIPanel): that code
-- is protected, and an addon driving it -- or closing the Settings panel to
-- make room -- gets "blocked from an action only available to the Blizzard
-- UI".  Instead it is a plain frame above the Settings panel, closed by
-- Escape through UISpecialFrames, and it tells Forever's gamepad layer about
-- itself when shown and hidden (GamepadMode.FrameControlsManager -- Blizzard
-- wraps both calls so addon frames may make them).  That layer then gives it
-- the same D-pad navigation as Blizzard's own windows.  Nothing here needs
-- the mouse: no hover-only information, no right-click, no typing.
--
-- Two things that look natural and are not used, both found in game:
--   * The game's gamepad tab indicators (LB/RB).  They take LB/RB over with
--     override bindings, which is a protected action from addon code.  The
--     tabs are plain buttons the D-pad reaches.
--   * A ScrollBox list.  The gamepad navigation does not walk into it.  The
--     list is a fixed page of rows with Previous and Next buttons instead,
--     and the navigation is told to look again whenever the page changes.

local ADDON, ns = ...
local FAME = ns.core

ns.ui = ns.ui or {}
local ui = ns.ui

local WIDTH, HEIGHT = 600, 560
local ROW_HEIGHT = 34
local ROWS_PER_PAGE = 10
local GREY = { 0.62, 0.62, 0.62 }
local LOGO = "Interface\\AddOns\\" .. ADDON .. "\\Media\\logo"
local PORTRAIT = "Interface\\AddOns\\" .. ADDON .. "\\Media\\portrait"

local TAB_HERE, TAB_ZONES, TAB_BANNED = 1, 2, 3
ui.TAB_HERE, ui.TAB_ZONES, ui.TAB_BANNED = TAB_HERE, TAB_ZONES, TAB_BANNED

local frame              -- created on first open
local state = { tab = TAB_HERE, zone = nil, page = 1, data = {} }

local function clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function trackName(track)
    return track.name or tostring(track.id or track.file)
end

-- What the Here tab is showing: the music set, and the profile within it --
-- walking into Ratchet keeps the Barrens' music but changes what fits.
local function hereKey()
    local ctx = FAME.ctx
    return ctx and (ctx.key .. ":" .. tostring(ctx.prof)) or nil
end

local function zoneName(mapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or ("map " .. tostring(mapID))
end

-- Every zone FAME covers, by name.
local zoneList
local function zones()
    if not zoneList then
        zoneList = {}
        for mapID in pairs(ns.zones) do zoneList[#zoneList + 1] = mapID end
        table.sort(zoneList, function(a, b) return zoneName(a) < zoneName(b) end)
    end
    return zoneList
end

-- ---------------------------------------------------------------------------
-- Track rows
-- ---------------------------------------------------------------------------

-- Rows are plain frames built on first use: a checkbox for "plays in this
-- zone" carrying the track's name, then the era, length and any note as text,
-- then a Preview button.  Checkbox and button are the row's two focus stops.
local function buildTrackRow(row)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(28, 28)
    row.check:SetPoint("LEFT", 2, 0)
    row.check:SetScript("OnClick", function(self)
        local data = row.data
        if data then FAME:SetZoneOff(data.mapID, data.track, not self:GetChecked()) end
    end)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.name:SetWidth(210)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.preview = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.preview:SetSize(82, 24)
    row.preview:SetPoint("RIGHT", -4, 0)
    row.preview:SetScript("OnClick", function()
        local data = row.data
        if not data then return end
        if FAME.state == "preview" and FAME.playing == data.track then
            FAME:EndPreview()
        else
            FAME:Preview(data.track)
        end
    end)

    row.info = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.info:SetPoint("RIGHT", row.preview, "LEFT", -8, 0)
    row.info:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.info:SetJustifyH("RIGHT")
    row.info:SetWordWrap(false)

    row.unban = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.unban:SetSize(82, 24)
    row.unban:SetPoint("RIGHT", -4, 0)
    row.unban:SetText("Unban")
    row.unban:SetScript("OnClick", function()
        if row.banKey ~= nil then FAME:Unban(row.banKey) end
    end)
    row.unban:Hide()

    row.built = true
end

local function initTrackRow(row, data)
    if not row.built then buildTrackRow(row) end
    row.unban:Hide()
    row.check:Show(); row.preview:Show()
    row.data = data
    local track = data.track

    local inZone = not FAME:ZoneOff(data.mapID, track)
    local eraOn = FAME:EraOn(track.era)
    local banned = FAME:IsBanned(track)
    row.check:SetChecked(inZone)
    row.name:SetText(trackName(track))

    local notes = { track.era and ns.ERA_LABEL[track.era] or "your file", clock(track.len) }
    if data.day and not data.night then notes[#notes + 1] = "day only" end
    if data.night and not data.day then notes[#notes + 1] = "night only" end
    if banned then notes[#notes + 1] = "|cffff8080banned|r" end
    if not eraOn then notes[#notes + 1] = "|cffff8080era off|r" end
    row.info:SetText(table.concat(notes, "  ·  "))

    -- Anything that keeps a track from playing greys its name out.
    if inZone and eraOn and not banned then
        row.name:SetTextColor(1, 1, 1)
    else
        row.name:SetTextColor(GREY[1], GREY[2], GREY[3])
    end

    local previewing = FAME.state == "preview" and FAME.playing == track
    row.preview:SetText(previewing and "Stop" or "Preview")
end

-- Ban rows reuse the same frame: the name and where it was banned, and an
-- Unban button in the Preview button's place.
local function initBanRow(row, data)
    if not row.built then buildTrackRow(row) end
    row.data = nil
    row.check:Hide(); row.preview:Hide()
    row.unban:Show()
    row.banKey = data.key
    row.name:SetText(data.name)
    row.name:SetTextColor(1, 1, 1)
    row.info:SetText(("%s · %s"):format(data.zone or "?", tostring(data.key)))
end

local function initRow(row, data)
    if data.ban then initBanRow(row, data.ban) else initTrackRow(row, data) end
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local function button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function create()
    frame = CreateFrame("Frame", "FAMEMusicFrame", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 20)
    frame:Hide()
    -- Above the Settings panel (HIGH), so opening it from there works.
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    -- Movable by its title bar, for the mouse; nothing depends on it.
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    -- Escape closes it, like any game window.
    table.insert(UISpecialFrames, "FAMEMusicFrame")
    if frame.SetTitle then frame:SetTitle("Forever Ambient Music Extended") end
    if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset(PORTRAIT)
    elseif ButtonFrameTemplate_HidePortrait then
        ButtonFrameTemplate_HidePortrait(frame)
    end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(frame) end

    local inset = frame.Inset or frame

    -- Now playing ----------------------------------------------------------
    local now = CreateFrame("Frame", nil, frame)
    now:SetPoint("TOPLEFT", 66, -30)
    now:SetPoint("TOPRIGHT", -14, -30)
    now:SetHeight(64)
    frame.now = now

    now.label = now:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    now.label:SetPoint("TOPLEFT", 0, -2)
    now.label:SetText("NOW PLAYING")

    now.track = now:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    now.track:SetPoint("TOPLEFT", now.label, "BOTTOMLEFT", 0, -3)
    now.track:SetPoint("RIGHT", 0, 0)
    now.track:SetJustifyH("LEFT")
    now.track:SetWordWrap(false)

    now.skip = button(now, "Skip", 90, function() FAME:Skip() end)
    now.skip:SetPoint("BOTTOMLEFT", 0, 0)
    now.extended = button(now, "Play extended now", 150, function() FAME:PlayExtendedNow() end)
    now.extended:SetPoint("LEFT", now.skip, "RIGHT", 6, 0)
    now.ban = button(now, "Never play again", 150, function()
        if FAME.playing and FAME.ctx then FAME:Ban(FAME.playing) end
    end)
    now.ban:SetPoint("LEFT", now.extended, "RIGHT", 6, 0)

    -- The band: what the list below is for, and on the Zones tab the zone
    -- switcher, kept together in the middle so the D-pad goes straight from
    -- < to >.  Its own strip, apart from the list, so moving through one
    -- never wanders into the other.
    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT", 10, -98)
    head:SetPoint("TOPRIGHT", -10, -98)
    head:SetHeight(46)
    frame.head = head
    local shade = head:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.35)
    for _, edge in ipairs({ "TOP", "BOTTOM" }) do
        local line = head:CreateTexture(nil, "BORDER")
        line:SetHeight(1)
        line:SetPoint(edge .. "LEFT")
        line:SetPoint(edge .. "RIGHT")
        line:SetColorTexture(0.8, 0.65, 0.3, 0.45)
    end

    -- Name above the band's middle, count below it: one block, centred.
    head.title = head:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    head.title:SetPoint("BOTTOM", head, "CENTER", 0, 1)
    head.title:SetWidth(300)
    head.title:SetJustifyH("CENTER")
    head.title:SetWordWrap(false)
    head.count = head:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    head.count:SetPoint("TOP", head, "CENTER", 0, -2)

    -- The arrows on the band's middle line, either side of that block.
    head.prev = button(head, "<", 36, function() ui:StepZone(-1) end)
    head.prev:SetPoint("RIGHT", head, "CENTER", -156, 0)
    head.next = button(head, ">", 36, function() ui:StepZone(1) end)
    head.next:SetPoint("LEFT", head, "CENTER", 156, 0)
    head.unbanAll = button(head, "Unban all", 100, function() FAME:UnbanAll() end)
    head.unbanAll:SetPoint("RIGHT", -8, 0)

    -- The inset holds the list and its pager ---------------------------------
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 4, -148)
    inset:SetPoint("BOTTOMRIGHT", -6, 26)

    frame.empty = inset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    frame.empty:SetPoint("TOPLEFT", 20, -24)
    frame.empty:SetPoint("TOPRIGHT", -20, -24)
    frame.empty:SetJustifyH("CENTER")

    -- A fixed page of rows.  Rows are plain frames holding a checkbox and a
    -- button each, so the gamepad navigation treats them like any buttons.
    frame.rows = {}
    for i = 1, ROWS_PER_PAGE do
        local row = CreateFrame("Frame", nil, inset)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 8, -6 - (i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -8, -6 - (i - 1) * ROW_HEIGHT)
        buildTrackRow(row)
        row:Hide()
        frame.rows[i] = row
    end

    local pager = CreateFrame("Frame", nil, inset)
    pager:SetPoint("BOTTOMLEFT", 8, 6)
    pager:SetPoint("BOTTOMRIGHT", -8, 6)
    pager:SetHeight(26)
    frame.pager = pager
    pager.prev = button(pager, "Previous page", 130, function() ui:StepPage(-1) end)
    pager.prev:SetPoint("LEFT", 0, 0)
    pager.next = button(pager, "Next page", 130, function() ui:StepPage(1) end)
    pager.next:SetPoint("RIGHT", 0, 0)
    pager.label = pager:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    pager.label:SetPoint("CENTER", 0, 0)

    -- Tabs -----------------------------------------------------------------
    frame.Tabs = {}
    local labels = { "Here", "Zones", "Banned" }
    for i, label in ipairs(labels) do
        local tab = CreateFrame("Button", "FAMEMusicFrameTab" .. i, frame, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(label)
        tab:SetScript("OnClick", function() ui:SelectTab(i) end)
        frame.Tabs[i] = tab
    end
    frame.Tabs[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
    PanelTemplates_SetNumTabs(frame, #labels)

    local function gamepad() return GamepadMode and GamepadMode.FrameControlsManager end

    frame:SetScript("OnShow", function()
        state.zone = state.zone or (FAME.ctx and FAME.ctx.mapID) or zones()[1]
        ui:WireNavigation()
        ui:SelectTab(state.tab)
        local manager = gamepad()
        if manager and manager.FrameShown then manager:FrameShown(frame) end
    end)
    frame:SetScript("OnHide", function()
        -- Closing the window ends a preview, as stopping the preview would.
        if FAME.state == "preview" then FAME:EndPreview() end
        local manager = gamepad()
        if manager and manager.FrameHidden then manager:FrameHidden(frame) end
    end)

    -- The clock in the now-playing line.
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            ui:RefreshNowPlaying()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Contents
-- ---------------------------------------------------------------------------

function ui:RefreshNowPlaying()
    local now = frame.now
    local track = FAME.playing
    if track then
        local era = track.era and ns.ERA_LABEL[track.era]
        local kind = ({ original = "the game's own", intro = "intro", extended = "extended",
            preview = "preview", test = "by request" })[FAME.kind] or ""
        now.track:SetFormattedText("%s  |cff9d9d9d%s%s · %s / %s|r", trackName(track),
            era and (era .. " · ") or "", kind, clock(GetTime() - (FAME.startedAt or GetTime())),
            clock(track.len))
    else
        now.track:SetText("|cff9d9d9d" .. FAME:StateText() .. "|r")
    end
    now.skip:SetEnabled(track ~= nil)
    now.extended:SetEnabled(FAME.ctx ~= nil)
    now.ban:SetEnabled(track ~= nil and FAME.ctx ~= nil)
end

-- The rows for the current tab, and its header.
local function rows()
    local head = frame.head
    head.prev:Hide(); head.next:Hide(); head.unbanAll:Hide()
    local data = {}
    local empty

    if state.tab == TAB_BANNED then
        local bans = FAME:BanList()
        for _, b in ipairs(bans) do data[#data + 1] = { ban = b } end
        head.title:SetText("Banned tracks")
        head.count:SetText(#bans == 0 and "none" or ("%d banned, everywhere"):format(#bans))
        if #bans > 0 then head.unbanAll:Show() end
        empty = "Nothing is banned. \"Never play again\" bans the track that's playing."
    else
        local mapID, profs, where
        if state.tab == TAB_HERE then
            local ctx = FAME.ctx
            if ctx then
                mapID, profs = ctx.mapID, { ctx.prof }
                where = ctx.inn or zoneName(ctx.mapID)
            else
                head.title:SetText("Here")
                head.count:SetText("")
                frame.empty:SetText(FAME:StateText())
                return data
            end
        else
            mapID = state.zone
            profs = nil
            where = zoneName(mapID)
            head.prev:Show(); head.next:Show()
        end
        local list = profs and FAME:TracksFor(profs) or FAME:ZoneTracks(mapID)
        local on = 0
        for _, item in ipairs(list) do
            data[#data + 1] = { track = item.track, day = item.day, night = item.night, mapID = mapID }
            if FAME:Allowed(item.track, mapID) then on = on + 1 end
        end
        head.title:SetText(where)
        head.count:SetFormattedText("%d of %d extended tracks play here", on, #list)
        empty = "No extended tracks fit here. The game's own music plays as usual."
    end
    frame.empty:SetText(#data == 0 and empty or "")
    return data
end

-- Tell the gamepad navigation the window's buttons changed (rows shown or
-- hidden, a page turned).  Blizzard wraps this so addon frames may call it.
local function renavigate()
    if SmartNavigation and SmartNavigation.RefreshButtonGroups and frame:IsShown() then
        SmartNavigation:RefreshButtonGroups(frame)
    end
end

local function drawPage()
    local pages = math.max(1, math.ceil(#state.data / ROWS_PER_PAGE))
    state.page = math.min(math.max(1, state.page), pages)
    local first = (state.page - 1) * ROWS_PER_PAGE
    for i, row in ipairs(frame.rows) do
        local data = state.data[first + i]
        if data then
            initRow(row, data)
            row:Show()
        else
            row:Hide()
        end
    end
    frame.pager:SetShown(pages > 1)
    frame.pager.label:SetFormattedText("Page %d of %d", state.page, pages)
    frame.pager.prev:SetEnabled(state.page > 1)
    frame.pager.next:SetEnabled(state.page < pages)
end

function ui:Rebuild(keepPage)
    if not (frame and frame:IsShown()) then return end
    state.data = rows()
    if not keepPage then state.page = 1 end
    drawPage()
    self:RefreshNowPlaying()
    renavigate()
end

-- Called by Core whenever what the window shows may have changed.  The rows
-- are redrawn where they are, so ticking a box never moves the page or the
-- gamepad's place on it.
function ui:Refresh()
    if not (frame and frame:IsShown()) then return end
    local key = hereKey()
    if state.tab == TAB_HERE and key ~= state.ctxKey then
        state.ctxKey = key
        return self:Rebuild(false)
    end
    self:Rebuild(true)
end

function ui:StepPage(step)
    state.page = state.page + step
    drawPage()
    renavigate()
end

function ui:SelectTab(tab)
    state.tab = tab
    PanelTemplates_SetTab(frame, tab)
    state.ctxKey = hereKey()
    self:Rebuild(false)
end

-- ---------------------------------------------------------------------------
-- Gamepad paths
-- ---------------------------------------------------------------------------

-- Where each D-pad direction goes, set explicitly so the cursor moves the
-- way the window reads: left and right within a row of controls, up and
-- down within a column.  Left alone, the navigation picks the nearest
-- button in roughly that direction, which cut diagonally into the list.
-- Targets are functions, so they follow what is on screen (which rows are
-- shown, whether there is a pager, which tab).  Blizzard allows addons to
-- set these out of combat; the window never opens in combat (see below).
function ui:WireNavigation()
    if frame.wired or InCombatLockdown() then return end
    if not (SmartNavigation_AddJumpNavigationOverride and SMART_NAV_INPUT_DIRECTION) then return end
    frame.wired = true
    local DIR = SMART_NAV_INPUT_DIRECTION
    local function set(b, dir, target) SmartNavigation_AddJumpNavigationOverride(b, DIR[dir], target) end
    local function visible(b) return b and b:IsVisible() and b or nil end
    local function usable(b) return b and b:IsVisible() and b:IsEnabled() and b or nil end

    local now, head, pager, tabs = frame.now, frame.head, frame.pager, frame.Tabs
    local function shownRows()
        local out = {}
        for _, row in ipairs(frame.rows) do if row:IsShown() then out[#out + 1] = row end end
        return out
    end
    local function side(row, left)
        if left then return visible(row.check) or visible(row.unban) end
        return visible(row.preview) or visible(row.unban)
    end
    local function headSide(left)
        if left then return visible(head.prev) or visible(head.unbanAll) end
        return visible(head.next) or visible(head.unbanAll)
    end
    local function nowSide(left)
        if left then return usable(now.skip) or now.extended end
        return usable(now.ban) or now.extended
    end
    local function pagerSide(left)
        if not pager:IsVisible() then return nil end
        if left then return usable(pager.prev) or usable(pager.next) end
        return usable(pager.next) or usable(pager.prev)
    end
    local function rowEnd(first, left)
        local rows = shownRows()
        local row = rows[first and 1 or #rows]
        return row and side(row, left)
    end
    local function tabSide(left) return tabs[left and 1 or #tabs] end

    -- Now playing: one row of three.
    set(now.skip, "RIGHT", now.extended); set(now.extended, "LEFT", now.skip)
    set(now.extended, "RIGHT", now.ban);  set(now.ban, "LEFT", now.extended)
    for b, left in pairs({ [now.skip] = true, [now.extended] = true, [now.ban] = false }) do
        set(b, "DOWN", function()
            return headSide(left) or rowEnd(true, left) or pagerSide(left) or tabSide(left)
        end)
    end

    -- The band: < and > straight to each other.
    set(head.prev, "RIGHT", head.next); set(head.next, "LEFT", head.prev)
    for b, left in pairs({ [head.prev] = true, [head.next] = false, [head.unbanAll] = false }) do
        set(b, "UP", function() return nowSide(left) end)
        set(b, "DOWN", function() return rowEnd(true, left) or pagerSide(left) or tabSide(left) end)
    end

    -- Rows: checkbox and Preview side by side; up and down keep the column.
    for _, row in ipairs(frame.rows) do
        set(row.check, "RIGHT", row.preview); set(row.preview, "LEFT", row.check)
        for b, left in pairs({ [row.check] = true, [row.preview] = false, [row.unban] = false }) do
            set(b, "UP", function()
                local rows = shownRows()
                for i, r in ipairs(rows) do
                    if r == row and i > 1 then return side(rows[i - 1], left) end
                end
                return headSide(left) or nowSide(left)
            end)
            set(b, "DOWN", function()
                local rows = shownRows()
                for i, r in ipairs(rows) do
                    if r == row and i < #rows then return side(rows[i + 1], left) end
                end
                return pagerSide(left) or tabSide(left)
            end)
        end
    end

    -- Pager: Previous and Next straight to each other.
    set(pager.prev, "RIGHT", pager.next); set(pager.next, "LEFT", pager.prev)
    for b, left in pairs({ [pager.prev] = true, [pager.next] = false }) do
        set(b, "UP", function() return rowEnd(false, left) or headSide(left) or nowSide(left) end)
        set(b, "DOWN", function() return tabSide(left) end)
    end

    -- Tabs: along the bottom; up goes back into the page.
    for i, tab in ipairs(tabs) do
        if tabs[i - 1] then set(tab, "LEFT", tabs[i - 1]) end
        if tabs[i + 1] then set(tab, "RIGHT", tabs[i + 1]) end
        local left = i == 1
        set(tab, "UP", function()
            return pagerSide(left) or rowEnd(false, left) or headSide(left) or nowSide(left)
        end)
    end
end

function ui:StepZone(step)
    local list = zones()
    local index = 1
    for i, mapID in ipairs(list) do
        if mapID == state.zone then index = i end
    end
    index = (index - 1 + step) % #list + 1
    state.zone = list[index]
    self:Rebuild(false)
end

-- The gamepad paths above are refused in combat (the game shows "interface
-- action failed"), and a music window has no business there anyway: it
-- closes when combat starts and waits until it ends.
local function sayCombat()
    print("|cff7fd5ffFAME|r: the music window opens after combat")
end

-- Optionally on a given tab (the Settings buttons open Zones or Banned).
function ui:Show(tab)
    if InCombatLockdown() then return sayCombat() end
    if not frame then create() end
    if tab then state.tab = tab end
    if frame:IsShown() then
        if tab then self:SelectTab(tab) end
    else
        frame:Show()
    end
    frame:Raise()
end

function ui:Toggle()
    if frame and frame:IsShown() then frame:Hide() else self:Show() end
end

-- ---------------------------------------------------------------------------
-- Ways in: key binding, minimap button
-- ---------------------------------------------------------------------------

BINDING_HEADER_FAME = "FAME"
BINDING_NAME_FAME_TOGGLE_WINDOW = "Open the music window"
function FAME_ToggleWindow() ui:Toggle() end

-- A round button on the minimap's edge, built the way minimap buttons
-- always have been: the tracking border, a dark disc, the logo.  Left-click
-- opens FAME's Settings, right-click the music window; drag with the mouse
-- to move it around the edge.  Off unless the player turns it on.
--
-- Until the player drags it, it finds itself a free spot: other addons'
-- buttons sit on the same ring, so it looks at what is already there and
-- takes the first angle clear of all of them.
local minimapButton
local atan2 = math.atan2 or math.atan     -- the client's Lua 5.1 has atan2
local START = 225              -- where the search starts: lower left, as LibDBIcon's default
local GAP = 2                  -- pixels between neighbouring buttons

local function radius() return Minimap:GetWidth() / 2 + 6 end

-- Centre and size of every button already on the ring.
local function taken()
    local found = {}
    local cx, cy = Minimap:GetCenter()
    if not cx then return found end
    for _, parent in ipairs({ Minimap, MinimapCluster }) do
        if parent and parent.GetChildren then
            for _, child in ipairs({ parent:GetChildren() }) do
                if child ~= minimapButton and child:IsShown() then
                    local x, y = child:GetCenter()
                    if x then
                        -- Centres are in each frame's own scale; bring the other one to the map's.
                        local scale = (child:GetEffectiveScale() or 1) / (Minimap:GetEffectiveScale() or 1)
                        local dx, dy = x * scale - cx, y * scale - cy
                        -- Only things on the ring count, not the map's own pins.
                        if math.sqrt(dx * dx + dy * dy) >= Minimap:GetWidth() / 2 - 12 then
                            found[#found + 1] = { angle = math.deg(atan2(dy, dx)) % 360,
                                                  size = (child:GetWidth() or 31) * scale }
                        end
                    end
                end
            end
        end
    end
    return found
end

-- The angle, in degrees, two buttons of these sizes need between their
-- centres to sit side by side on the ring with a small gap: what a player
-- lining buttons up by hand ends up with.
local function room(sizeA, sizeB)
    local chord = (sizeA + sizeB) / 2 + GAP
    return math.deg(2 * math.asin(math.min(1, chord / (2 * radius()))))
end

-- The nearest clear angle to START, searched a degree at a time either way,
-- so FAME lands right beside its neighbours rather than a step away.
local function freeAngle()
    local used, size = taken(), (minimapButton and minimapButton:GetWidth()) or 31
    for step = 0, 180 do
        for _, candidate in ipairs({ START + step, START - step }) do
            candidate = candidate % 360
            local clear = true
            for _, other in ipairs(used) do
                if math.abs((candidate - other.angle + 180) % 360 - 180) < room(size, other.size) then
                    clear = false
                    break
                end
            end
            if clear then return candidate end
        end
    end
    return START
end

local function placeMinimapButton()
    local angle = math.rad(ns.db.minimapAngle or freeAngle())
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius(), math.sin(angle) * radius())
end

-- Built like the standard Classic minimap button (and like Pulse Haptics',
-- which sits right next to it): a 32 px button, the dark disc and the icon
-- centred on it, the tracking border from its top-left corner.
local function createMinimapButton()
    local b = CreateFrame("Button", "FAMEMinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel((Minimap:GetFrameLevel() or 8) + 5)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    -- Clicks stop here rather than pinging the map underneath.
    if b.SetPropagateMouseClicks then b:SetPropagateMouseClicks(false) end
    if b.SetPropagateMouseMotion then b:SetPropagateMouseMotion(false) end
    -- The gamepad cursor has no business on the minimap; the key binding is
    -- the gamepad's way in.
    if SmartNavigation_MarkFrameIgnored then SmartNavigation_MarkFrameIgnored(b) end

    local background = b:CreateTexture(nil, "BACKGROUND")
    -- Tuned in game against the ring, half a pixel at a time: centred on the
    -- button, the logo sat a little low and left of the ring's own centre
    -- (Pulse's does too), so it and its disc are nudged back.
    background:SetSize(20, 20)
    background:SetPoint("CENTER", 0.5, 0.5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetVertexColor(0, 0, 0, 0.85)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0.5, 0.5)
    icon:SetTexture(LOGO)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local highlight = b:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(22, 22)
    highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    b:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ui:Toggle()
        elseif ui.OpenSettings then
            ui:OpenSettings()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("FAME")
        GameTooltip:AddDoubleLine("Left-click", "Settings", 0.4, 1, 0.4, 1, 1, 1)
        GameTooltip:AddDoubleLine("Right-click", "Tracks by zone", 0.4, 1, 0.4, 1, 1, 1)
        GameTooltip:AddDoubleLine("Drag", "Move", 0.6, 0.6, 0.6, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local cx, cy = Minimap:GetCenter()
            local x, y = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimapAngle = math.deg(atan2(y / scale - cy, x / scale - cx)) % 360
            placeMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        FAME:Save("minimapAngle", ns.db.minimapAngle)
    end)
    return b
end

function ui:UpdateMinimap()
    if not Minimap then return end
    if ns.db.minimap and not minimapButton then minimapButton = createMinimapButton() end
    if minimapButton then
        placeMinimapButton()
        minimapButton:SetShown(ns.db.minimap)
    end
end

-- Saved settings are in by PLAYER_LOGIN, but other addons may put their
-- minimap buttons up a little later, so the free spot is looked for again
-- once the world is up.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_REGEN_DISABLED")
loader:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if frame and frame:IsShown() then
            frame:Hide()
            print("|cff7fd5ffFAME|r: the music window closed for combat")
        end
        return
    end
    ui:UpdateMinimap()
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.After(2, function() ui:UpdateMinimap() end)
    end
end)
