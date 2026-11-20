-- Import.lua -- the "Music from modern WoW" window: what the retail music
-- pack is, whether it is installed, and where to get it.
--
-- The pack is music FAME can't ship (it is Blizzard's), so a script on the
-- project page builds it on the player's own computer, as a separate addon:
-- ForeverAmbientMusicExtended_RetailPack.  That addon is only a Pack.lua
-- setting the global FAMERetailPack -- what is in it -- and the music files.
-- The game can't open a web page, so this window shows the page's address in
-- a box that is focused and selected as soon as the window opens, so Ctrl+C
-- copies it straight away, with a mouse or a controller.  Anything typed over
-- it puts the address back (Spoken's link boxes work the same way, so
-- players have seen it before), and Escape closes the window.
--
-- Built like the music window: a plain frame above Settings, closed by
-- Escape, telling Forever's gamepad layer when it opens and closes, and kept
-- out of combat.  Never the shared StaticPopup frames.

local ADDON, ns = ...
local FAME = ns.core

ns.ui = ns.ui or {}
local ui = ns.ui

local PAGE = "https://kirillburton.github.io/forever-ambient-music-extended/import/"
local PACK_ADDON = ns.PACK_ADDON
local PACK_FORMAT = ns.PACK_FORMAT     -- the Pack.lua layout this FAME reads
local WIDTH, HEIGHT = 500, 340
local PORTRAIT = "Interface\\AddOns\\" .. ADDON .. "\\Media\\portrait"

ui.IMPORT_PAGE = PAGE

local function eraLabel(key)
    return ns.ERA_LABEL[key] or key
end

-- ---------------------------------------------------------------------------
-- The pack
-- ---------------------------------------------------------------------------

local function addonState()
    local get = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
    if not get then return nil end
    local ok, name, _, _, loadable, reason = pcall(get, PACK_ADDON)
    if not ok or not name then return "missing" end
    if reason == "MISSING" then return "missing" end
    local enabled = C_AddOns and C_AddOns.GetAddOnEnableState
    if enabled then
        local character = UnitName and UnitName("player")
        local okState, state = pcall(enabled, PACK_ADDON, character)
        if okState and state == 0 then return "disabled" end
    end
    if reason == "DISABLED" then return "disabled" end
    return loadable and "present" or "disabled"
end

-- What is installed, as the window describes it.
--   { state = "none" | "disabled" | "outdated" | "installed",
--     tracks, bytes, imported, eras = { key, ... } }
function FAME:RetailPack()
    local pack = FAMERetailPack
    if type(pack) ~= "table" then
        return { state = addonState() == "disabled" and "disabled" or "none" }
    end
    if pack.format ~= PACK_FORMAT or type(pack.tracks) ~= "table" then
        return { state = "outdated" }
    end
    local count, byEra = 0, {}
    for _, era in pairs(pack.tracks) do
        count = count + 1
        byEra[era] = true
    end
    local eras = {}
    for _, era in ipairs(ns.ERAS) do
        if byEra[era.key] then eras[#eras + 1] = era.key end
    end
    return { state = count > 0 and "installed" or "none", tracks = count,
             bytes = tonumber(pack.bytes) or 0, imported = pack.imported, eras = eras }
end

local function size(bytes)
    if bytes >= 1024 ^ 3 then return ("%.1f GB"):format(bytes / 1024 ^ 3) end
    return ("%d MB"):format(math.floor(bytes / 1024 ^ 2 + 0.5))
end

local function thousands(n)
    local s = tostring(n)
    while true do
        local done
        s, done = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if done == 0 then return s end
    end
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local frame

local function create()
    frame = CreateFrame("Frame", "FAMEImportFrame", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 40)
    frame:Hide()
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    table.insert(UISpecialFrames, "FAMEImportFrame")
    if frame.SetTitle then frame:SetTitle("Music from modern WoW") end
    if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset(PORTRAIT)
    elseif ButtonFrameTemplate_HidePortrait then
        ButtonFrameTemplate_HidePortrait(frame)
    end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(frame) end

    local inset = frame.Inset or frame
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 4, -60)
    inset:SetPoint("BOTTOMRIGHT", -6, 40)

    -- What is installed, beside the portrait.
    frame.status = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.status:SetPoint("TOPLEFT", 66, -34)
    frame.status:SetPoint("RIGHT", -14, 0)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(false)

    frame.body = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.body:SetPoint("TOPLEFT", 16, -14)
    frame.body:SetPoint("RIGHT", -16, 0)
    frame.body:SetJustifyH("LEFT")
    frame.body:SetSpacing(3)

    frame.step = inset:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.step:SetPoint("TOPLEFT", frame.body, "BOTTOMLEFT", 0, -16)
    frame.step:SetPoint("RIGHT", -16, 0)
    frame.step:SetJustifyH("LEFT")

    -- The address, in a box that selects itself.
    local box = CreateFrame("EditBox", nil, inset, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetHeight(24)
    box:SetPoint("TOPLEFT", frame.step, "BOTTOMLEFT", 6, -8)
    box:SetPoint("RIGHT", -20, 0)
    box:SetFontObject("ChatFontNormal")
    local function fill()
        box:SetText(PAGE)
        box:SetCursorPosition(0)
    end
    box:SetScript("OnShow", fill)
    box:SetScript("OnEditFocusGained", function() box:HighlightText() end)
    box:SetScript("OnMouseUp", function() box:SetFocus(); box:HighlightText() end)
    -- Typing over it, or pasting, can't change it: the address comes back.
    box:SetScript("OnTextChanged", function(_, userInput)
        if box:GetText() ~= PAGE then
            box:SetText(PAGE)
            if userInput then box:HighlightText() end
        end
    end)
    box:SetScript("OnEscapePressed", function() frame:Hide() end)
    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
    -- The gamepad cursor has nothing to do in a text box.
    if SmartNavigation_MarkFrameIgnored then SmartNavigation_MarkFrameIgnored(box) end
    frame.box = box

    frame.hint = inset:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -6)
    frame.hint:SetPoint("RIGHT", -16, 0)
    frame.hint:SetJustifyH("LEFT")
    frame.hint:SetText("Press Ctrl+C to copy the address. If it isn't highlighted, click it first.")

    frame.after = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.after:SetPoint("TOPLEFT", frame.hint, "BOTTOMLEFT", 0, -14)
    frame.after:SetPoint("RIGHT", -16, 0)
    frame.after:SetJustifyH("LEFT")
    frame.after:SetSpacing(3)

    -- One button, so the D-pad has somewhere to be and A closes.
    frame.close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.close:SetSize(110, 24)
    frame.close:SetPoint("BOTTOM", 0, 10)
    frame.close:SetText(CLOSE or "Close")
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    local function gamepad() return GamepadMode and GamepadMode.FrameControlsManager end
    frame:SetScript("OnShow", function()
        ui:RefreshImport()
        local manager = gamepad()
        if manager and manager.FrameShown then manager:FrameShown(frame) end
        -- Selected and ready: Ctrl+C is all it takes.
        frame.box:SetFocus()
        frame.box:HighlightText()
    end)
    frame:SetScript("OnHide", function()
        frame.box:ClearFocus()
        local manager = gamepad()
        if manager and manager.FrameHidden then manager:FrameHidden(frame) end
    end)
end

local WHAT = "FAME can add over 3,000 zone music tracks from every era of WoW. Blizzard's music "
    .. "can't be shipped with an addon, so a small script fetches it onto your own computer: from "
    .. "your installed retail game, or from Blizzard's servers."

function ui:RefreshImport()
    if not frame then return end
    local pack = FAME:RetailPack()

    if pack.state == "installed" then
        frame.status:SetText(("|cff80ff80Installed:|r %s tracks · %s%s"):format(
            thousands(pack.tracks), size(pack.bytes),
            pack.imported and (" · imported " .. pack.imported) or ""))
        local labels = {}
        for _, key in ipairs(pack.eras) do labels[#labels + 1] = eraLabel(key) end
        frame.body:SetText("Music from " .. table.concat(labels, ", ") .. ".")
        frame.step:SetText("To add or remove expansions, run the script again. The steps are on this page:")
        frame.after:SetText("")
    elseif pack.state == "disabled" then
        frame.status:SetText("|cffffd100Installed, but turned off|r")
        frame.body:SetText("Turn on \"FAME Retail Music Pack\" in the AddOns list on the character "
            .. "screen, then log back in.")
        frame.step:SetText("How it was made, and how to change it:")
        frame.after:SetText("")
    elseif pack.state == "outdated" then
        frame.status:SetText("|cffffd100Made by an older script|r")
        frame.body:SetText("This version of FAME can't read the music pack you have. Run the "
            .. "import script again to bring it up to date: your music stays, and only what "
            .. "changed is fetched.")
        frame.step:SetText("Get the latest script from this page:")
        frame.after:SetText("")
    else
        frame.status:SetText("Not installed")
        frame.body:SetText(WHAT)
        frame.step:SetText("1.  On your computer, open this page:")
        frame.after:SetText("2.  Follow the steps there, then restart the game.\n"
            .. "|cff9d9d9dA /reload isn't enough: the game only finds new files when it starts.|r")
    end

    -- Text given to an edit box before it is first on screen isn't drawn,
    -- so it is given again on every refresh as well as on show.
    frame.box:SetText(PAGE)
end

function ui:ShowImport()
    if InCombatLockdown() then
        print("|cff7fd5ffFAME|r: the import window opens after combat")
        return
    end
    if not frame then create() end
    if frame:IsShown() then self:RefreshImport() else frame:Show() end
    frame:Raise()
end

-- Same rule as the music window: out of the way in combat.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:SetScript("OnEvent", function()
    if frame and frame:IsShown() then frame:Hide() end
end)
