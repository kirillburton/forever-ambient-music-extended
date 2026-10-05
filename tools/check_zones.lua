-- check_zones.lua -- load the addon outside the game and report what each
-- zone would actually draw from.
--
--   lua tools/check_zones.lua            summary, flagging thin pools
--   lua tools/check_zones.lua 1431       everything eligible in Duskwood
--
-- This runs the real Core.lua matcher against the real data files on a
-- stubbed-out WoW API, so it catches three things before the game does:
-- a Lua syntax error, a tag that is not in the vocabulary (a typo would
-- silently exclude a track everywhere), and a zone whose pool came out empty.

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

-- --- load the addon ------------------------------------------------------

local ns = {}
for _, file in ipairs({ "Tracks.lua", "LocalTracks.lua", "Originals.lua", "Zones.lua", "Core.lua" }) do
    local chunk, err = loadfile(ROOT .. "/" .. file)
    if not chunk then
        io.stderr:write("SYNTAX ERROR in " .. file .. ": " .. tostring(err) .. "\n")
        os.exit(1)
    end
    chunk(ADDON, ns)
end
local FAME = ns.core

-- --- tag vocabulary check ------------------------------------------------

local problems = 0
local function complain(fmt, ...)
    problems = problems + 1
    io.write("PROBLEM  " .. string.format(fmt, ...) .. "\n")
end

local KNOWN = {}
for _, axis in ipairs({ ns.BIOME, ns.CULTURE, ns.MOOD }) do
    for tag in pairs(axis) do KNOWN[tag] = true end
end
KNOWN.day, KNOWN.night = true, true

local tagUse = {}
for _, track in ipairs(ns.allTracks) do
    local hasBiome = false
    for _, tag in ipairs(track.tags) do if ns.BIOME[tag] then hasBiome = true end end
    if not hasBiome then
        complain("track %s has no biome tag, so it can play nowhere", tostring(track.id or track.file))
    end
    if not track.len or track.len < 1 then
        complain("track %s has no usable len", tostring(track.id or track.file))
    end
    for _, tag in ipairs(track.tags) do
        if not KNOWN[tag] then
            complain("track %s uses unknown tag %q", tostring(track.id or track.file), tag)
        end
        tagUse[tag] = (tagUse[tag] or 0) + 1
    end
end

local function checkList(zoneID, field, list, axis, axisName)
    if not list then return end
    for _, tag in ipairs(list) do
        if not axis[tag] then
            complain("zone %s .%s lists %q, which is not a %s tag", zoneID, field, tag, axisName)
        end
    end
end

local function checkProfile(zoneID, prof, seen)
    if not prof or seen[prof] then return end
    seen[prof] = true
    if prof.require then
        for _, tag in ipairs(prof.require) do
            if not KNOWN[tag] then
                complain("zone %s .require lists %q, which is not a known tag", zoneID, tag)
            end
        end
    end
    checkList(zoneID, "biomes", prof.biomes, ns.BIOME, "biome")
    checkList(zoneID, "cultures", prof.cultures, ns.CULTURE, "culture")
    checkList(zoneID, "moods", prof.moods, ns.MOOD, "mood")
    checkProfile(zoneID, prof.resting, seen)
    checkProfile(zoneID, prof.indoors, seen)
end

for zoneID, prof in pairs(ns.zones) do
    checkProfile(zoneID, prof, {})
    if prof.inn and not ns.tavernSets[prof.inn] then
        complain("zone %s .inn = %q, which is not a key of ns.tavernSets", zoneID, prof.inn)
    end
    local zm = ns.zoneMusic[zoneID]
    if not zm then
        complain("zone %s has no entry in Originals.lua -- FAME will leave it to the game", zoneID)
    elseif not ns.musicSets[zm.set] then
        complain("zone %s points at music set %d, which Originals.lua does not define", zoneID, zm.set)
    end
end
for zoneID, prof in pairs(ns.zones) do
    for areaID, townProf in pairs(prof.towns or {}) do
        checkProfile(zoneID .. "/town " .. areaID, townProf, {})
        local listed = false
        for _, row in ipairs((ns.zoneMusic[zoneID] or {}).sub or {}) do
            if row[1] == areaID then listed = true end
        end
        if not listed then
            complain("zone %s town %d is not in Originals.lua -- re-run tools/make_originals.py", zoneID, areaID)
        end
    end
end
for _, zm in pairs(ns.zoneMusic) do
    for _, row in ipairs(zm.sub) do
        if row[3] ~= 0 and not ns.musicSets[row[3]] then
            complain("subzone %s points at undefined music set %d", row[2], row[3])
        end
        if row[4] ~= 0 and not ns.intros[row[4]] then
            complain("subzone %s points at undefined intro %d", row[2], row[4])
        end
    end
end
for setID, musicSet in pairs(ns.musicSets) do
    if #musicSet.day + #musicSet.night == 0 then
        io.write(("note     music set %d %s has no tracks (silence only)\n"):format(setID, musicSet.name))
    end
end

-- --- per-zone pools ------------------------------------------------------

local function poolFor(prof, night)
    FAME.pool, FAME.poolProf = nil, nil
    return FAME:Pool(prof, night)
end

local only = tonumber(arg[1])

if only then
    local prof = ns.zones[only]
    if not prof then
        io.write(("no Zones.lua entry for uiMapID %d\n"):format(only))
        os.exit(1)
    end
    for _, phase in ipairs({ { "day", false }, { "night", true } }) do
        local pool = poolFor(prof, phase[2])
        io.write(("\n=== uiMapID %d, %s: %d eligible\n"):format(only, phase[1], #pool))
        table.sort(pool, function(a, b)
            return table.concat(a.tags, " ") < table.concat(b.tags, " ")
        end)
        for _, t in ipairs(pool) do
            io.write(("  %-9s %4ds  %s\n"):format(tostring(t.id or t.file), t.len,
                table.concat(t.tags, " ")))
        end
    end
    if prof.resting then
        local pool = poolFor(prof.resting, false)
        io.write(("\n=== uiMapID %d, resting: %d eligible\n"):format(only, #pool))
        for _, t in ipairs(pool) do
            io.write(("  %-9s %4ds  %s\n"):format(tostring(t.id or t.file), t.len,
                table.concat(t.tags, " ")))
        end
    end
    os.exit(0)
end

local ids = {}
for zoneID in pairs(ns.zones) do ids[#ids + 1] = zoneID end
table.sort(ids)

io.write(("%d tracks loaded (%d built-in, %d local), %d zones\n\n")
    :format(#ns.allTracks, #ns.builtinTracks, #(ns.localTracks or {}), #ids))
io.write("uiMapID   day  night  resting\n")
local thin = {}
for _, zoneID in ipairs(ids) do
    local prof = ns.zones[zoneID]
    local d = #poolFor(prof, false)
    local n = #poolFor(prof, true)
    local r = prof.resting and #poolFor(prof.resting, false) or 0
    io.write(("%-9d %4d  %5d  %7s\n"):format(zoneID, d, n,
        prof.resting and tostring(r) or "-"))
    if d < 8 or n < 8 then thin[#thin + 1] = { zoneID, d, n } end
    if prof.resting and r < 4 then
        complain("zone %d resting pool is only %d tracks", zoneID, r)
    end
end

if #thin > 0 then
    io.write("\nthin pools (under 8 eligible tracks):\n")
    for _, row in ipairs(thin) do
        io.write(("  uiMapID %d: %d day, %d night\n"):format(row[1], row[2], row[3]))
    end
end

local unused = {}
for tag in pairs(KNOWN) do
    if not tagUse[tag] then unused[#unused + 1] = tag end
end
table.sort(unused)
if #unused > 0 then
    io.write("\ntags no built-in track carries (still usable for local files): "
        .. table.concat(unused, " ") .. "\n")
end

io.write(("\n%d problems\n"):format(problems))
os.exit(problems > 0 and 1 or 0)
