-- Options.lua -- FAME's page in the game's own Settings panel
-- (Settings > AddOns > FAME).
--
-- Ordered from what most players want to what few do: on or off, which eras
-- to hear, the minimap button, then the mix, and last a button into the music
-- window for choosing tracks zone by zone.  Everything is a standard Settings
-- control, so it looks like the rest of the panel and the game's gamepad
-- navigation reaches it like any other page.
--
-- Every value is a proxy onto Core's own settings, so a change made here, by
-- a slash command or in the music window shows up in all three.

local ADDON, ns = ...
local FAME = ns.core

ns.ui = ns.ui or {}

-- The Settings API is the modern one (Blizzard_Settings_Shared).  Without it
-- the slash commands still cover everything.
if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
    return
end

local category, layout = Settings.RegisterVerticalLayoutCategory("FAME")

local function checkbox(variable, name, tooltip, get, set, default)
    local setting = Settings.RegisterProxySetting(category, "FAME_" .. variable,
        Settings.VarType.Boolean, name, default, get, set)
    local initializer = Settings.CreateCheckbox(category, setting, tooltip)
    return setting, initializer
end

-- A grey note to the right of a row's checkbox, in the game's own disabled-
-- text font, in the space the panel leaves empty there.
--
-- Added with hooksecurefunc, never by replacing the row's own functions:
-- Blizzard's code has to keep running untainted, because the rows are pooled
-- and shared with every other page of the panel, and the gamepad navigation
-- refuses tainted buttons.  (Wrapping InitFrame instead broke gamepad
-- navigation across the whole Settings panel.)  So Blizzard draws and
-- recycles the row exactly as before; FAME only adds its note afterwards and
-- hides it again when the row is recycled, so a row reused on another page
-- never carries it.  Notes live in FAME's own table, not on Blizzard's frames.
local notes = setmetatable({}, { __mode = "k" })

local function withNote(initializer, text)
    if not (hooksecurefunc and initializer and initializer.InitFrame) then return end
    hooksecurefunc(initializer, "InitFrame", function(_, frame)
        local note = notes[frame]
        if not note then
            note = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
            notes[frame] = note
        end
        note:ClearAllPoints()
        note:SetPoint("LEFT", frame.Checkbox or frame, "RIGHT", 14, 0)
        note:SetText(text)
        note:Show()
    end)
    if initializer.Resetter then
        hooksecurefunc(initializer, "Resetter", function(_, frame)
            if notes[frame] then notes[frame]:Hide() end
        end)
    end
end

local function header(name)
    if CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
    end
end

-- How many built-in tracks each era contributes, for its tooltip.
local eraCount = {}
for _, track in ipairs(ns.allTracks) do
    if track.era then eraCount[track.era] = (eraCount[track.era] or 0) + 1 end
end

-- 1. On or off
checkbox("Enabled", "Extend the zone music",
    "Mix tracks from across WoW into the zone music, keeping the game's own silences, intros and share of its own tracks.\n\nOff: the game plays its own music as normal.",
    function() return ns.db.enabled end,
    function(value) FAME:SetEnabled(value) end,
    true)

-- 2. Eras
header("Music from")
for _, era in ipairs(ns.ERAS) do
    local count = eraCount[era.key] or 0
    local _, initializer = checkbox("Era_" .. era.key, era.label,
        ("%d tracks from %s.\n\nThe game's own music for each place always plays, whatever is chosen here."):format(
            eraCount[era.key] or 0, era.label),
        function() return FAME:EraOn(era.key) end,
        function(value) FAME:SetEra(era.key, value) end,
        true)
    withNote(initializer, count == 1 and "1 track" or (count .. " tracks"))
end

-- 3. Minimap entry, opt-in
checkbox("Minimap", "Minimap button",
    "A round FAME button on the minimap's edge. Left-click opens these settings, right-click the music window. Drag it with the mouse to move it around the edge.",
    function() return ns.db.minimap end,
    function(value)
        FAME:Save("minimap", value)
        if ns.ui.UpdateMinimap then ns.ui:UpdateMinimap() end
    end,
    false)

-- 4. The mix
header("More options")

do
    local setting = Settings.RegisterProxySetting(category, "FAME_OriginalChance",
        Settings.VarType.Number, "Game's own tracks", 40,
        function() return math.floor(ns.db.originalChance * 100 + 0.5) end,
        function(value) FAME:SetOriginalChance(value / 100) end)
    local options = Settings.CreateSliderOptions(0, 100, 5)
    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
            function(value) return ("%d%%"):format(value) end)
    end
    Settings.CreateSlider(category, setting, options,
        "Share of tracks that are the game's own picks for the place. The rest come from the extended pool.\n\nWhere only a few extended tracks fit, the game's own play more often, so the same few don't come round again and again.")
end

checkbox("FirstOriginal", "Game's track on arrival",
    "When you arrive somewhere new, the first track is the game's own, as you'd hear it without FAME.\n\nOff: the first track can be an extended one too.",
    function() return not ns.db.displaceFirst end,
    function(value) FAME:SetDisplaceFirst(not value) end,
    true)

-- 5. Full customisation, out of the way at the bottom.  Both open the music
-- window above the Settings panel; closing it comes back here.  Settings is
-- left alone: closing it from addon code is a protected action.
if CreateSettingsButtonInitializer then
    layout:AddInitializer(CreateSettingsButtonInitializer("Tracklists", "Edit tracklists",
        function() if ns.ui.Show then ns.ui:Show(ns.ui.TAB_ZONES) end end,
        "Choose which extended tracks play in each zone, and preview them.",
        true))
    layout:AddInitializer(CreateSettingsButtonInitializer("Banned tracks", "Show banned tracks",
        function() if ns.ui.Show then ns.ui:Show(ns.ui.TAB_BANNED) end end,
        "Tracks you've banned with Never play again, to unban them.",
        true))
end

Settings.RegisterAddOnCategory(category)

function ns.ui:OpenSettings()
    if not Settings.OpenToCategory then return false end
    Settings.OpenToCategory(category:GetID())
    return true
end
