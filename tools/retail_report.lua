-- retail_report.lua -- what the retail music pack would play in each zone,
-- as if every track of it were imported.
--
--   lua tools/retail_report.lua          one line per zone
--   lua tools/retail_report.lua 1442     Stonetalon Mountains in full
--
-- Runs the real Core.lua placement (RetailFor) on a stubbed WoW API, with a
-- fake Pack.lua listing every track in RetailTracks.lua.  For tuning
-- ns.retailFit in Zones.lua and the cap in Core.lua.

local ADDON = "ForeverAmbientMusicExtended"
local ROOT = (arg[0]:match("^(.*)/tools/[^/]+$") or ".") .. "/" .. ADDON

-- --- minimal WoW API ------------------------------------------------------

local stubFrame = {}
function stubFrame:RegisterEvent() end
function stubFrame:SetScript() end
function CreateFrame() return setmetatable({}, { __index = stubFrame }) end

C_Timer = { NewTimer = function() return { Cancel = function() end } end }
C_Map = { GetBestMapForUnit = function() return nil end }
C_CVar = { GetCVarBool = function() return true end }
GetCVarBool = function() return true end
GetTime = os.clock
GetGameTime = function() return 12, 0 end
IsInInstance = function() return false end
GetInstanceInfo = function() return nil end
GetSubZoneText = function() return "" end
GetZoneText = function() return "" end
GetMinimapZoneText = function() return "" end
IsResting = function() return false end
IsIndoors = function() return false end
UnitAffectingCombat = function() return false end
PlayMusic = function() end
StopMusic = function() end
PlaySoundFile = function() return true, 1 end
StopSound = function() end
SlashCmdList = {}
UnitFactionGroup = function() return "Alliance" end

-- Every track of the pack, imported.
local ids = {}
for line in io.lines(ROOT .. "/RetailTracks.lua") do
    local rid, era = line:match('rid = (%d+), len = %d+, era = "(%w+)"')
    if rid then ids[tonumber(rid)] = era end
end
FAMERetailPack = { format = 1, tracks = ids }

local ns = {}
for _, file in ipairs({ "Tracks.lua", "ForeverPlaces.lua", "LocalTracks.lua", "RetailTracks.lua", "Loudness.lua", "Originals.lua", "Zones.lua", "Core.lua" }) do
    assert(loadfile(ROOT .. "/" .. file))(ADDON, ns)
end
local FAME = ns.core

local names = {}
for mapID, zm in pairs(ns.zoneMusic) do names[mapID] = zm.name end

local function own(mapID)
    local n = 0
    for _, track in ipairs(FAME:TracksFor({ ns.zones[mapID] })) do n = n + 1 end
    return n
end

local only = tonumber(arg[1])
if not only then
    local rows = {}
    for mapID in pairs(ns.zones) do
        local all = FAME:RetailFor(mapID, true)
        local zoneWide = FAME:RetailFor(mapID, nil)
        rows[#rows + 1] = { mapID, names[mapID] or "?", own(mapID), #zoneWide, #all - #zoneWide }
    end
    table.sort(rows, function(a, b) return a[2] < b[2] end)
    print(("%-6s %-34s %5s %10s %10s"):format("map", "zone", "FAME", "whole zone", "subzones"))
    for _, r in ipairs(rows) do
        print(("%-6d %-34s %5d %10d %10d"):format(r[1], r[2]:sub(1, 34), r[3], r[4], r[5]))
    end
    print("\nFAME: its own tracks.  whole zone: pack tracks anywhere in it (retail's own")
    print("plus the fitted ones).  subzones: more, only in subzones retail gives them to.")
    return
end

-- One zone in full.
print(("%s (%d)"):format(names[only] or "?", only))
local zoneWide = {}
for _, track in ipairs(FAME:RetailFor(only, nil)) do zoneWide[track] = true end
local placed = {}
for _, track in ipairs(ns.retailTracks) do
    for _, area in ipairs(track.at or {}) do
        if area == ns.zoneMusic[only].area then placed[track] = "retail plays it here" end
    end
end
local function line(track, why)
    print(("  %-8s %-9d %-40s %-44s %s"):format(track.era, track.rid, track.name:sub(1, 40),
        table.concat(track.tags, " "):sub(1, 44), why))
end
print("\nwhole zone")
for _, track in ipairs(FAME:RetailFor(only, nil)) do line(track, placed[track] or "fits") end
local areas = {}
for area, entry in pairs(ns.retailAreas) do
    if entry[1] == only then areas[#areas + 1] = area end
end
table.sort(areas, function(a, b) return ns.retailAreas[a][2] < ns.retailAreas[b][2] end)
for _, area in ipairs(areas) do
    print(("\n%s (%d)"):format(ns.retailAreas[area][2], area))
    for _, track in ipairs(FAME:RetailFor(only, area)) do
        if not zoneWide[track] then line(track, "retail plays it here") end
    end
end
