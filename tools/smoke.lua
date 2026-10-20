-- smoke.lua -- drive the music schedule and every slash command outside the
-- game, on a stubbed API, and check it keeps the game's own rules.
--
--   lua tools/smoke.lua
--
-- What it holds FAME to: the first track in a new place is the game's own;
-- the gap after every track falls inside the game's own silence interval for
-- that place (or is absent with Loop Music on); about the configured share
-- of tracks stay original; instances and unmapped places are handed back to
-- the game; and the player's music volume is always put back after a fade.

local ADDON = "ForeverAmbientMusicExtended"
local ROOT = (arg[0]:match("^(.*)/tools/[^/]+$") or ".") .. "/" .. ADDON
local SILENCE = "Interface\\AddOns\\" .. ADDON .. "\\Media\\silence.mp3"

local now, pending, log = 0, {}, {}

local stubFrame = {}
function stubFrame:RegisterEvent() end
function stubFrame:SetScript(_, fn) self.onEvent = fn end
function CreateFrame() return setmetatable({}, { __index = stubFrame }) end

local function schedule(delay, fn, iterations)
    local t = { at = now + delay, fn = fn, dead = false }
    if iterations then t.interval, t.left = delay, iterations end
    t.Cancel = function(self) self.dead = true end
    pending[#pending + 1] = t
    return t
end
C_Timer = {
    NewTimer = function(delay, fn) return schedule(delay, fn) end,
    NewTicker = function(delay, fn, iterations) return schedule(delay, fn, iterations or 1e9) end,
}

local function advance(seconds)
    local target, guard = now + seconds, 0
    while true do
        local soonest
        for _, t in ipairs(pending) do
            if not t.dead and t.at <= target and (not soonest or t.at < soonest.at) then soonest = t end
        end
        if not soonest then break end
        guard = guard + 1
        if guard > 2000000 then error("timer storm -- something reschedules instantly") end
        now = soonest.at
        if soonest.interval then
            soonest.left = soonest.left - 1
            if soonest.left <= 0 then soonest.dead = true else soonest.at = now + soonest.interval end
        else
            soonest.dead = true
        end
        soonest.fn()
    end
    now = target
    local keep = {}
    for _, t in ipairs(pending) do if not t.dead then keep[#keep + 1] = t end end
    pending = keep
end

local state = { map = 1431, sub = "", resting = false, hour = 12, instance = false, faction = "Alliance",
                dead = false, zoneText = nil, locale = "enUS", areaNames = true }

local START_VOLUME = "0.4"
local cvars = {
    Sound_EnableAllSound = "1", Sound_EnableMusic = "1",
    Sound_MusicVolume = START_VOLUME, Sound_ZoneMusicNoDelay = "0",
}
local volumeWrites = 0

-- The client's own names for areas: English, from Originals.lua, unless a
-- test switches them off to stand in for a client that cannot name them.
local ns
local function areaName(areaID)
    if not state.areaNames then return nil end
    for _, zm in pairs(ns.zoneMusic) do
        if zm.area == areaID then return zm.name end
        for _, row in ipairs(zm.sub) do if row[1] == areaID then return row[2] end end
    end
    return nil
end
C_Map = {
    GetBestMapForUnit = function() return state.map end,
    GetAreaInfo = function(areaID) return areaName(areaID) end,
}
GetCVar = function(name) return cvars[name] end
local volumeLog = {}
local fameRef          -- set once Core.lua is loaded; the client tells it about every write
SetCVar = function(name, value)
    if name == "Sound_MusicVolume" then
        volumeWrites = volumeWrites + 1
        volumeLog[#volumeLog + 1] = tonumber(value)
    end
    cvars[name] = tostring(value)
    if name == "Sound_MusicVolume" and fameRef and fameRef.onEvent then
        fameRef.onEvent(fameRef, "CVAR_UPDATE", name)
    end
end
-- FAME's mid-fade values carry an odd offset: six decimals ending 537.
local function isMarked(v) return v ~= nil and string.format("%.6f", v):sub(-3) == "537" end
GetCVarBool = function(name)
    if cvars[name] == nil then return nil end
    return cvars[name] ~= "0"
end
C_CVar = { GetCVar = GetCVar, SetCVar = SetCVar, GetCVarBool = GetCVarBool }
GetTime = function() return now end
GetGameTime = function() return state.hour, 0 end
IsInInstance = function() return state.instance, state.instance and "party" or "none" end
GetInstanceInfo = function() return "Test", "party", 1, "", 5, 0, false, 999 end
GetSubZoneText = function() return state.sub end
-- The game's own zone name: the mapped zone's, unless a test puts the
-- player somewhere else (out at sea).
GetZoneText = function()
    if state.zoneText then return state.zoneText end
    local zm = ns.zoneMusic[state.map]
    return zm and zm.name or "Nowhere"
end
GetLocale = function() return state.locale end
UnitIsDeadOrGhost = function() return state.dead end
time = os.time
IsResting = function() return state.resting end
IsIndoors = function() return state.indoors end
-- Inside a building the minimap names the building; otherwise the subzone.
GetMinimapZoneText = function() return state.building or state.sub end
UnitFactionGroup = function() return state.faction end
PlayMusic = function(src) log[#log + 1] = { t = now, play = src, vol = cvars.Sound_MusicVolume } end
StopMusic = function() log[#log + 1] = { t = now, stop = true } end
local probeWorks = true
PlaySoundFile = function() if probeWorks then return true, 7 end return true, 0 end
StopSound = function() end
SlashCmdList = {}
local realPrint, quiet = print, false
local chat = {}
print = function(...)
    chat[#chat + 1] = table.concat({ ... }, " ")
    if not quiet then realPrint(...) end
end

ns = {}
for _, file in ipairs({ "Tracks.lua", "LocalTracks.lua", "Originals.lua", "Zones.lua", "Core.lua" }) do
    assert(loadfile(ROOT .. "/" .. file))(ADDON, ns)
end
local FAME = ns.core
fameRef = FAME
-- Sample the volume slider at a moment in time (for the swap checks).
local function volumeAt(seconds)
    quiet = true; advance(seconds); quiet = false
    return tonumber(cvars.Sound_MusicVolume)
end
local function fire(event, arg1) quiet = true; FAME.onEvent(FAME, event, arg1); quiet = false end
local function run(input) quiet = true; local ok, err = pcall(SlashCmdList.FOREVERAMBIENTMUSICEXTENDED, input); quiet = false; return ok, err end
local function go(seconds) quiet = true; advance(seconds); quiet = false end

local failures = 0
local function check(cond, what)
    if cond then realPrint("  ok    " .. what) else failures = failures + 1; realPrint("  FAIL  " .. what) end
end

-- Which originals belong to which set, so a PlayMusic can be classified.
local originalIDs = {}
for _, musicSet in pairs(ns.musicSets) do
    for _, list in ipairs({ musicSet.day, musicSet.night }) do
        for _, tr in ipairs(list) do originalIDs[tr.id] = true end
    end
end
for _, intro in pairs(ns.intros) do for _, tr in ipairs(intro.tracks) do originalIDs[tr.id] = true end end

-- Replay the log into a list of track plays: { t, src, endsAt }, where a play
-- ends at the next PlayMusic/StopMusic of anything.
local function plays(from, to)
    local out, open = {}, nil
    for _, e in ipairs(log) do
        if e.t >= from and e.t <= to then
            if open then open.endsAt = e.t; open = nil end
            if e.play and e.play ~= SILENCE then
                open = { t = e.t, src = e.play }
                out[#out + 1] = open
            end
        end
    end
    return out
end

local function silences(from, to)
    -- gap = from a track's end to the next track's start
    local p, gaps = plays(from, to), {}
    for i = 2, #p do gaps[#gaps + 1] = p[i].t - (p[i - 1].endsAt or p[i].t) end
    return gaps
end

------------------------------------------------------------------------------
realPrint("arriving")
fire("ADDON_LOADED", ADDON)
fire("PLAYER_ENTERING_WORLD")
local first = log[#log] and log[#log].play
check(first ~= nil, "music starts on arrival, as the game's does")
check(first and originalIDs[first], "the first track in a new place is the game's own")
check(FAME.state == "original", "and reports it as the game's own")
check(FAME.silenceWorks == true, "silent file probe succeeds")

------------------------------------------------------------------------------
realPrint("\nthe game's silences, Loop Music off (Duskwood)")
math.randomseed(7)
local t0 = now
go(6 * 3600)
local set = ns.musicSets[ns.zoneMusic[1431].set]
local lo, hi = set.silence[1], set.silence[2]
local gaps = silences(t0, now)
local within, minGap, maxGap = 0, 1e9, 0
for _, g in ipairs(gaps) do
    if g >= lo and g <= hi + 3 then within = within + 1 end      -- +3: QUIET_AFTER tail
    minGap, maxGap = math.min(minGap, g), math.max(maxGap, g)
end
check(#gaps > 20, ("tracks over six hours: %d"):format(#gaps + 1))
check(within == #gaps, ("every gap inside the game's %d-%ds: %d of %d (range %.0f-%.0fs)")
    :format(lo, hi, within, #gaps, minGap, maxGap))
local holds = 0
for _, e in ipairs(log) do if e.t >= t0 and e.play == SILENCE then holds = holds + 1 end end
check(holds >= #gaps, ("every silence is held with the silent file: %d holds"):format(holds))

-- "Original" means original *to this place*: Forever's new zone music is
-- the game's own in its zone and an extended track everywhere else.
local here = {}
for _, list in ipairs({ set.day, set.night }) do for _, tr in ipairs(list) do here[tr.id] = true end end
local orig, ext = 0, 0
for _, p in ipairs(plays(t0, now)) do
    if here[p.src] then orig = orig + 1 else ext = ext + 1 end
end
local share = orig / (orig + ext)
check(share > 0.25 and share < 0.55, ("about 40%% of tracks stay the game's own: %.0f%% (%d of %d)")
    :format(share * 100, orig, orig + ext))
check(ext > 0, "and the rest come from the extended pool")

------------------------------------------------------------------------------
realPrint("\nLoop Music on")
cvars.Sound_ZoneMusicNoDelay = "1"
go(400)                                   -- let the current silence end
local t1 = now
go(2 * 3600)
local loopGaps = silences(t1, now)
local longest = 0
for _, g in ipairs(loopGaps) do longest = math.max(longest, g) end
check(#loopGaps > 20, ("tracks back to back over two hours: %d"):format(#loopGaps + 1))
check(longest < 5, ("no silence between tracks: longest gap %.1fs"):format(longest))
local loopHolds = 0
for _, e in ipairs(log) do if e.t > t1 and e.play == SILENCE then loopHolds = loopHolds + 1 end end
check(loopHolds == 0, "no silence held at all")

cvars.Sound_ZoneMusicNoDelay = "0"
go(600)
check(FAME.state == "silence" or FAME.playing ~= nil, "switching it back off resumes gaps")
-- switching it on mid-silence starts music within one poll
while FAME.state ~= "silence" do go(5) end
cvars.Sound_ZoneMusicNoDelay = "1"
go(11)
check(FAME.playing ~= nil, "turning Loop Music on mid-silence starts a track at the next poll")
cvars.Sound_ZoneMusicNoDelay = "0"

------------------------------------------------------------------------------
realPrint("\nfading and the volume slider")
check(volumeWrites > 30, ("the volume ramps rather than cutting: %d writes"):format(volumeWrites))
go(30)
while not FAME.playing do go(10) end
local track = FAME.playing
go(FAME.startedAt + track.len - 1.2 - now)          -- inside the end-of-track ramp
check(FAME:Fading(), "a fade is in progress mid-ramp")
check(cvars.Sound_MusicVolume ~= START_VOLUME, "volume is down mid-fade")
state.map = 1429
fire("ZONE_CHANGED_NEW_AREA")
go(5)
check(cvars.Sound_MusicVolume == START_VOLUME, "a zone change mid-fade puts it back")
while not FAME.playing do go(10) end
go(FAME.startedAt + FAME.playing.len - 1.2 - now)
check(cvars.Sound_MusicVolume ~= START_VOLUME, "down again")
fire("PLAYER_LOGOUT")
check(cvars.Sound_MusicVolume == START_VOLUME, "logging out mid-fade puts it back")
fire("PLAYER_ENTERING_WORLD")
go(5)

------------------------------------------------------------------------------
realPrint("\nswapping one track for another")
-- The client crossfades between PlayMusic calls, so whatever was playing is
-- still audible for a moment after the swap.  The volume has to be down when
-- the new track starts and stay down past that crossfade.
local function swapCheck(label, trigger, fadeLen)
    while not FAME.playing do go(10) end
    go(5)
    local n = #log
    trigger()
    go((fadeLen or 1.2) + 0.1)               -- just past the fade-out
    local swap
    for i = n + 1, #log do if log[i].play and log[i].play ~= SILENCE then swap = log[i] break end end
    check(swap ~= nil, label .. ": a new track starts")
    if not swap then return end
    -- "Silent" is the marked floor, 0.0005: inaudible, and still recognisably FAME's.
    check(tonumber(swap.vol) < 0.001, ("%s: volume is silent at the moment of the swap (was %s)"):format(label, tostring(swap.vol)))
    local during = volumeAt(0.5)
    check(during < 0.001, ("%s: still silent half a second later, under the client's crossfade (%s)"):format(label, tostring(during)))
    local rising = volumeAt(1.0)
    check(rising > 0 and rising < tonumber(START_VOLUME), ("%s: then fades back in (%s)"):format(label, tostring(rising)))
    go(3)
    check(cvars.Sound_MusicVolume == START_VOLUME, ("%s: and ends at the player's own level"):format(label))
end
swapCheck("zone change", function()
    state.map = (state.map == 1429) and 1431 or 1429
    fire("ZONE_CHANGED_NEW_AREA")
end)
swapCheck("/fame next", function() run("next") end, 0.8)
cvars.Sound_ZoneMusicNoDelay = "1"
swapCheck("Loop Music, track to track", function()
    local fade = math.min(2.5, FAME.playing.len * 0.25)
    go(FAME.startedAt + FAME.playing.len - fade - now)   -- the end-of-track fade begins
end, 2.5)
cvars.Sound_ZoneMusicNoDelay = "0"

-- A new fade starting while the last one is still fading back in must start
-- from where the volume actually is, never jump up to full first.
while not FAME.playing do go(10) end
state.map = (state.map == 1429) and 1431 or 1429
fire("ZONE_CHANGED_NEW_AREA")
go(1.3 + 1.0 + 0.5)                          -- mid fade-in
local partial = tonumber(cvars.Sound_MusicVolume)
local peak = partial
state.map = (state.map == 1429) and 1431 or 1429
fire("ZONE_CHANGED_NEW_AREA")
for _ = 1, 20 do peak = math.max(peak, volumeAt(0.05)) end
check(partial > 0 and partial < tonumber(START_VOLUME) and peak <= partial + 1e-6,
    ("a fade interrupting a fade-in never jumps up (from %.2f, peak %.2f)"):format(partial, peak))
go(10)
check(cvars.Sound_MusicVolume == START_VOLUME, "and the player's level still comes back")

------------------------------------------------------------------------------
realPrint("\nfirst track setting")
local function firstAfterEntering(map)
    state.map = 1431
    fire("ZONE_CHANGED_NEW_AREA"); go(3)
    state.map = map
    fire("ZONE_CHANGED_NEW_AREA"); go(3)
    return FAME.kind
end
local allOriginal = true
for _ = 1, 20 do if firstAfterEntering(1429) ~= "original" then allOriginal = false end end
check(allOriginal, "default: 20 of 20 arrivals open with the game's own track")
run("first")
local sawExtended = false
for _ = 1, 30 do if firstAfterEntering(1429) == "extended" then sawExtended = true end end
check(sawExtended, "/fame first: an arrival can open with an extended track")
run("first")

------------------------------------------------------------------------------
realPrint("\nsame music, different zone")
local shared
do
    local bySet = {}
    for mapID, zm in pairs(ns.zoneMusic) do
        if zm.intro == 0 and ns.zones[mapID] then
            bySet[zm.set] = bySet[zm.set] or {}
            table.insert(bySet[zm.set], mapID)
        end
    end
    for _, maps in pairs(bySet) do if #maps >= 2 then shared = maps break end end
end
check(shared ~= nil, "found two zones sharing a music set")
if shared then
    state.map = shared[1]; fire("ZONE_CHANGED_NEW_AREA"); go(3)
    local playingBefore, n = FAME.playing, #log
    state.map = shared[2]; fire("ZONE_CHANGED_NEW_AREA"); go(1)
    check(FAME.playing == playingBefore and #log == n,
        ("crossing %d -> %d keeps the track going, as the game does"):format(shared[1], shared[2]))
    check(FAME.ctx.prof == ns.zones[shared[2]], "but future extended picks come from the new zone")
end

------------------------------------------------------------------------------
realPrint("\nintros")
state.map = 1413; fire("ZONE_CHANGED_NEW_AREA"); go(3)
state.map = 1454; fire("ZONE_CHANGED_NEW_AREA"); go(3)
check(FAME.kind == "intro", ("entering Orgrimmar plays %s"):format(ns.intros[ns.zoneMusic[1454].intro].name))
-- Orgrimmar and the Barrens share a music set, so stepping out and back in
-- rightly leaves that intro playing; count intro starts instead.
local introTrack = {}
for _, tr in ipairs(ns.intros[ns.zoneMusic[1454].intro].tracks) do introTrack[tr.id] = true end
local function introStarts()
    local c = 0
    for _, e in ipairs(log) do if e.play and introTrack[e.play] then c = c + 1 end end
    return c
end
local startsBefore = introStarts()
go(600)
state.map = 1413; fire("ZONE_CHANGED_NEW_AREA"); go(3)
state.map = 1454; fire("ZONE_CHANGED_NEW_AREA"); go(3)
check(introStarts() == startsBefore, "re-entering inside the cooldown does not replay it")

------------------------------------------------------------------------------
realPrint("\ninns play their own race, or the game's music")
local function enterInn(map, sub, building)
    state.map, state.sub = map, sub
    state.building, state.resting, state.indoors = nil, false, false
    fire("ZONE_CHANGED_NEW_AREA"); go(3)
    state.building, state.resting, state.indoors = building, true, true
    fire("PLAYER_UPDATE_RESTING"); go(3)
end
local function leaveInn()
    state.building, state.resting, state.indoors, state.sub = nil, false, false, ""
    fire("PLAYER_UPDATE_RESTING"); go(3)
end
local function allTavernOf(pool, race)
    local strays = 0
    for _, tr in ipairs(pool) do
        local tavern, culture = false, nil
        for _, tag in ipairs(tr.tags) do
            if tag == "tavern" then tavern = true end
            if ns.CULTURE[tag] then culture = culture or tag; if tag ~= race then strays = strays + 1 end end
        end
        if not tavern then strays = strays + 1 end
    end
    return strays == 0
end

for _, case in ipairs({
    { 1429, "Goldshire", "Lion's Pride Inn", "human" },
    { 1426, "Kharanos", "Thunderbrew Distillery", "dwarf" },
    { 1420, "Brill", "Gallows' End Tavern", "undead" },
    { 1434, "Booty Bay", "The Salty Sailor Tavern", "pirate" },
}) do
    local map, sub, building, race = case[1], case[2], case[3], case[4]
    enterInn(map, sub, building)
    local ctx = FAME.ctx
    check(ctx and ctx.setID == ns.tavernSets[race], ("%s plays the game's %s tavern set"):format(building, race))
    local pool = ctx and FAME:Pool(ctx.prof, false) or {}
    check(#pool > 0 and allTavernOf(pool, race),
        ("and only %s tavern tracks from the extended pool (%d)"):format(race, #pool))
    if FAME.kind == "original" then
        local inSet = false
        for _, tr in ipairs(ctx.set.day) do if tr.id == FAME.playing.id then inSet = true end end
        check(inSet, "its first track comes from that set")
    end
    leaveInn()
end

-- An inn FAME has no race for: the game's own music, untouched.
enterInn(1413, "The Crossroads", "The Crossroads")
local n6 = #log
check(FAME.state == "inn", "the Crossroads inn (no race known) is left to the game")
go(600)
check(#log == n6, "and FAME plays nothing there")
leaveInn()
check(FAME.ctx ~= nil, "stepping outside picks the zone back up")

-- Capitals: resting is true on every street, so it means nothing there.
state.map, state.sub = 1453, ""; fire("ZONE_CHANGED_NEW_AREA"); go(3)
state.resting, state.indoors = true, true; fire("PLAYER_UPDATE_RESTING"); go(3)
check(FAME.ctx and FAME.ctx.key:sub(1, 4) == "set:", "indoors and resting in Stormwind is still Stormwind")
leaveInn()

-- Resting outdoors near an inn is just the zone.
state.map, state.sub = 1429, "Goldshire"; fire("ZONE_CHANGED_NEW_AREA"); go(3)
state.resting = true; fire("PLAYER_UPDATE_RESTING"); go(3)
check(FAME.ctx and FAME.ctx.key:sub(1, 4) == "set:", "resting outdoors in Goldshire is still Elwynn")
leaveInn()

-- Pirate music belongs to pirate places.
local function poolHas(prof, tag)
    for _, tr in ipairs(FAME:Pool(prof, false)) do
        for _, t in ipairs(tr.tags) do if t == tag then return true end end
    end
    return false
end
check(not poolHas(ns.zones[1434], "pirate"), "no pirate music on open Stranglethorn coast")
for _, place in ipairs({ { 1434, 35, "Booty Bay" }, { 1434, 43, "Wild Shore" }, { 1413, 391, "The Merchant Coast" },
                         { 1446, 1336, "Lost Rigger Cove" } }) do
    local prof = ns.zones[place[1]].towns[place[2]]
    local has = false
    for _, tr in ipairs(FAME:Pool(prof, false)) do if tr.id == 1061177 then has = true end end
    check(has, ("\"Ts Have It\" can play at %s"):format(place[3]))
end

------------------------------------------------------------------------------
realPrint("\ngoblin music stays in goblin towns")
local function hasTag(pool, tag)
    for _, tr in ipairs(pool) do for _, t in ipairs(tr.tags) do if t == tag then return true end end end
    return false
end
local leaks = {}
for zoneID, prof in pairs(ns.zones) do
    for _, night in ipairs({ false, true }) do
        if hasTag(FAME:Pool(prof, night), "goblin") then leaks[#leaks + 1] = zoneID end
    end
end
check(#leaks == 0, ("no open zone plays goblin music%s"):format(
    #leaks > 0 and (" -- leaks in " .. table.concat(leaks, " ")) or ""))
check(hasTag(FAME:Pool(ns.zones[1413].towns[392], false), "goblin"), "Ratchet does")
check(hasTag(FAME:Pool(ns.zones[1446].towns[976], false), "goblin"), "Gadgetzan does")

-- And the profile actually switches when you walk in.
state.map = 1413; state.sub = ""; fire("ZONE_CHANGED_NEW_AREA"); go(3)
check(FAME.ctx.prof == ns.zones[1413], "the open Barrens use the Barrens profile")
state.sub = "Ratchet"; fire("ZONE_CHANGED"); go(3)
check(FAME.ctx.prof == ns.zones[1413].towns[392], "walking into Ratchet switches to the Ratchet profile")
state.sub = ""; fire("ZONE_CHANGED"); go(3)
check(FAME.ctx.prof == ns.zones[1413], "and walking out switches back")

local biomeless = 0
for _, prof in pairs(ns.zones) do
    for _, tr in ipairs(FAME:Pool(prof, false)) do
        local placed = false
        for _, t in ipairs(tr.tags) do if ns.BIOME[t] then placed = true end end
        if not placed then biomeless = biomeless + 1 end
    end
end
check(biomeless == 0, "no track without a biome is eligible anywhere")

------------------------------------------------------------------------------
realPrint("\nhanding the channel back")
state.map = 1431; fire("ZONE_CHANGED_NEW_AREA"); go(5)
state.instance = true; fire("ZONE_CHANGED_NEW_AREA")
go(5)
local n = #log
check(FAME.state == "instance", "an instance releases the music to the game")
check(log[n] and log[n].stop, "with a StopMusic, so the game's own music resumes")
go(3600)
check(#log == n, "and FAME stays silent for an hour inside")
state.instance = false; fire("ZONE_CHANGED_NEW_AREA"); go(3)
check(FAME.playing ~= nil, "leaving it picks the schedule back up")

state.map = 999999; fire("ZONE_CHANGED_NEW_AREA"); go(5)
n = #log
go(3600)
check(FAME.state == "unmapped" and #log == n, "an unmapped place is left to the game")

state.map = 1431; fire("ZONE_CHANGED_NEW_AREA"); go(5)
cvars.Sound_EnableMusic = "0"
go(11)
check(FAME.state == "muted", "turning music off is noticed at the next poll")
cvars.Sound_EnableMusic = "1"
go(11)
check(FAME.playing ~= nil, "and turning it back on resumes")

------------------------------------------------------------------------------
realPrint("\nskip and next")
while not FAME.playing do go(10) end
run("skip"); go(4)
check(FAME.state == "silence", "skip ends the track into the game's silence")
run("next"); go(2)
check(FAME.kind == "extended", "next plays an extended track, even from a silence")
cvars.Sound_ZoneMusicNoDelay = "1"
run("skip"); go(4)
check(FAME.playing ~= nil and FAME.state ~= "silence", "with Loop Music on, skip goes straight to the next track")
cvars.Sound_ZoneMusicNoDelay = "0"

------------------------------------------------------------------------------
realPrint("\nno silent file")
FAME.silenceWorks = false
while FAME.state ~= "original" and FAME.state ~= "extended" do go(10) end
local before = #log
run("skip"); go(4)
check(log[#log].stop and #log > before, "without it, silences fall back to StopMusic")
FAME.silenceWorks = true

------------------------------------------------------------------------------
realPrint("\ndeath follows the game's rules")
state.map = 1431; fire("ZONE_CHANGED_NEW_AREA"); go(5)
while not FAME.playing do go(10) end
state.dead = true; fire("PLAYER_DEAD"); go(5)
local n0 = #log
check(FAME.state == "dead", "dying hands the music to the game")
check(log[#log].stop, "with a StopMusic, so the game's own death music runs")
go(1800)                                  -- a long corpse run, still a spirit
check(#log == n0, "nothing of FAME's plays during a half-hour corpse run")
local chatBefore = #chat
run("ban")
check(chat[#chat]:find("the game is choosing", 1, true), "/fame ban as a spirit explains it cannot ban the game's music")
state.dead = false; fire("PLAYER_UNGHOST"); go(3)
check(FAME.playing ~= nil and FAME.kind == "original", "resurrecting starts over like arriving: the game's own track first")

------------------------------------------------------------------------------
realPrint("\nships follow the game's rules")
state.map = 1437; fire("ZONE_CHANGED_NEW_AREA"); go(5)
check(FAME.ctx ~= nil, "on the Menethil docks, FAME runs Wetlands music")
state.zoneText = "The Great Sea"; fire("ZONE_CHANGED_NEW_AREA"); go(5)
n0 = #log
check(FAME.state == "elsewhere", "out on The Great Sea -- still on the Wetlands map -- the game takes over")
go(1200)
check(#log == n0, "and plays its own sea music for the whole crossing")
state.zoneText = nil; state.map = 1445; fire("ZONE_CHANGED_NEW_AREA"); go(3)
check(FAME.ctx ~= nil and FAME.kind == "original", "docking at Theramore starts Dustwallow with the game's own track")

-- A client that cannot name areas, in another language: skip the check
-- rather than mistake every zone for open sea.  FAME caches a zone's name
-- the first time it reads it, and a real client never changes language mid-
-- session, so this uses a zone no earlier test has visited.
state.areaNames, state.locale, state.zoneText = false, "deDE", "Shen'dralas (deDE)"
state.map = 2652
fire("PLAYER_ENTERING_WORLD"); go(3)
check(FAME.ctx ~= nil, "a German client without area names still runs normally")
state.areaNames, state.locale, state.zoneText = true, "enUS", nil
fire("PLAYER_ENTERING_WORLD"); go(3)

------------------------------------------------------------------------------
realPrint("\nbans")
local banned = ns.db.banned
for k in pairs(banned) do banned[k] = nil end
state.map = 1412; fire("ZONE_CHANGED_NEW_AREA"); go(3)    -- Mulgore: the smallest pool
while not FAME.playing do go(10) end
local victim, victimKind = FAME.playing, FAME.kind
run("ban"); go(4)
check(banned[victim.id] ~= nil, ("/fame ban records the current %s track"):format(victimKind))
check(banned[victim.id].zone == "Mulgore", "with the zone it was banned in")
check(FAME.playing == nil, "and stops it")
local t2 = now
go(6 * 3600)
local replays = 0
for _, e in ipairs(log) do if e.t > t2 and e.play == victim.id then replays = replays + 1 end end
check(replays == 0, "a banned track never plays again (six hours)")

-- An original and an extended one both count.
while not FAME.playing or FAME.kind == victimKind do go(10) end
local other = FAME.playing
run("ban"); go(4)
check(banned[other.id] ~= nil, ("banning an %s track works too"):format(victimKind == "original" and "extended" or "original"))

chatBefore = #chat
run("banlist")
local listed = table.concat(chat, "\n", chatBefore + 1)
check(listed:find(tostring(victim.id), 1, true) and listed:find("Mulgore", 1, true), "/fame banlist shows ids and zones")

run("unban " .. victim.id)
check(banned[victim.id] == nil and banned[other.id] ~= nil, "/fame unban <id> removes just that one")
run("unban 123456789")
check(chat[#chat]:find("is not banned", 1, true), "unbanning something not banned says so")

-- Ban everything Mulgore could play.
local function banAllHere()
    local ctx = FAME.ctx
    for _, list in ipairs({ ctx.set.day, ctx.set.night, FAME:Pool(ctx.prof, false), FAME:Pool(ctx.prof, true) }) do
        for _, tr in ipairs(list) do banned[tr.id or tr.file] = { zone = "Mulgore", kind = "test" } end
    end
end
while not FAME.playing do go(10) end
banAllHere()
local t3 = now
run("skip"); go(4)                              -- end the current track; the next decision finds nothing
chatBefore = #chat
go(400)
local msgs = 0
for i = chatBefore + 1, #chat do
    if chat[i]:find("All music for the zone was banned, playing nothing. Unban songs with /fame unban command", 1, true) then
        msgs = msgs + 1
    end
end
local played = 0
for _, e in ipairs(log) do if e.t > t3 + 5 and e.play and e.play ~= SILENCE then played = played + 1 end end
check(msgs >= 1, "with everything banned, the decision says so in chat")
check(played == 0, "and plays nothing")
cvars.Sound_ZoneMusicNoDelay = "1"
chatBefore = #chat
go(300)
msgs = 0
for i = chatBefore + 1, #chat do if chat[i]:find("All music for the zone was banned", 1, true) then msgs = msgs + 1 end end
check(msgs <= 5, ("with Loop Music on it does not spam: %d messages in five minutes"):format(msgs))
cvars.Sound_ZoneMusicNoDelay = "0"
run("unban all")
go(2)
check(next(banned) == nil, "/fame unban all clears the list")
check(FAME.playing ~= nil, "and music resumes straight away")

-- With every original banned, the first track on arrival is extended
-- rather than nothing.
local ctx = FAME.ctx
for _, list in ipairs({ ctx.set.day, ctx.set.night }) do for _, tr in ipairs(list) do banned[tr.id] = { zone = "Mulgore", kind = "original" } end end
state.map = 1413; fire("ZONE_CHANGED_NEW_AREA"); go(3)
state.map = 1412; fire("ZONE_CHANGED_NEW_AREA"); go(3)
check(FAME.kind == "extended", "originals all banned: the first track falls back to an extended one")
run("unban all")

-- A banned intro is skipped, not played.
for _, tr in ipairs(ns.intros[ns.zoneMusic[1454].intro].tracks) do banned[tr.id] = { zone = "Orgrimmar", kind = "intro" } end
state.map = 1416; fire("ZONE_CHANGED_NEW_AREA"); go(3)
state.map = 1454; fire("ZONE_CHANGED_NEW_AREA"); go(3)
check(FAME.kind ~= "intro", "a banned intro does not play on arrival")
run("unban all")

------------------------------------------------------------------------------
realPrint("\nthe volume slider stays the player's")
state.map = 1431; fire("ZONE_CHANGED_NEW_AREA"); go(5)
cvars.Sound_MusicVolume = START_VOLUME
fire("CVAR_UPDATE", "Sound_MusicVolume")
local unmarked = 0
for _, v in ipairs(volumeLog) do
    if not isMarked(v) and math.abs(v - tonumber(START_VOLUME)) > 1e-9 then unmarked = unmarked + 1 end
end
check(unmarked == 0, ("every value written mid-fade so far is marked as FAME's (%d of %d writes unmarked)")
    :format(unmarked, #volumeLog))

-- Something (the Settings panel, another addon) captures a mid-fade value and
-- writes it back after the fade is over.
local function midFadeValue()
    while not FAME.playing do go(10) end
    go(FAME.startedAt + FAME.playing.len - 1.2 - now)          -- inside the end-of-track ramp
    return cvars.Sound_MusicVolume
end
local stale = midFadeValue()

check(isMarked(tonumber(stale)), ("a mid-fade value is marked: %s"):format(stale))
go(10)
check(cvars.Sound_MusicVolume == START_VOLUME, "the fade itself puts the level back")
cvars.Sound_MusicVolume = stale                              -- replayed, no event
go(11)
check(cvars.Sound_MusicVolume == START_VOLUME, ("a stale value replayed later is healed at the next poll (%s)")
    :format(cvars.Sound_MusicVolume))
cvars.Sound_MusicVolume = stale
fire("CVAR_UPDATE", "Sound_MusicVolume")
check(cvars.Sound_MusicVolume == START_VOLUME, "and immediately, when the change fires CVAR_UPDATE")

-- The player moves the slider in the middle of a fade: that is their new level.
midFadeValue()
cvars.Sound_MusicVolume = "0.25"
go(10)
check(cvars.Sound_MusicVolume == "0.25", ("moving the slider mid-fade sets the level the fade returns to (%s)")
    :format(cvars.Sound_MusicVolume))
midFadeValue()
go(10)
check(cvars.Sound_MusicVolume == "0.25", "and later fades return there too")

-- ...or while nothing is fading.
cvars.Sound_MusicVolume = "0.3"
fire("CVAR_UPDATE", "Sound_MusicVolume")
midFadeValue()
go(10)
check(cvars.Sound_MusicVolume == "0.3", "a change made between fades is kept, not overwritten")
cvars.Sound_MusicVolume = START_VOLUME
fire("CVAR_UPDATE", "Sound_MusicVolume")

-- Handing music back to the game partway through a fade-out.
midFadeValue()
local fadingTrack = FAME.previous
state.instance = true; fire("ZONE_CHANGED_NEW_AREA")
go(3)
local stoppedAt
for i = #log, 1, -1 do if log[i].stop then stoppedAt = log[i].t break end end
check(stoppedAt and stoppedAt > now - 3, "releasing mid-fade stops the track (it would otherwise loop for ever)")
local n5 = #log
go(120)
check(#log == n5, "and nothing of FAME's plays afterwards")
check(cvars.Sound_MusicVolume == START_VOLUME, "with the level back where it was")
state.instance = false; fire("ZONE_CHANGED_NEW_AREA"); go(3)

------------------------------------------------------------------------------
realPrint("\nsharing the slider with Spoken Quests")
-- A line-for-line stand-in for Spoken's OtherSounds (addons/Spoken/OtherSounds.lua,
-- github.com/rusty-key/spoken-wow): on a line it notes the music level, fades to
-- 30% of it in 0.05s steps over 0.8s, and fades back 1.2s after the line.  On
-- every step it checks the slider still holds what it last set; if not, it takes
-- the player to have moved it and gives the channel up -- never restoring it.
local Spoken = { original = {}, applied = {}, gaveUp = 0 }
SpokenEnv = setmetatable({ OtherSounds = Spoken }, { __index = _G })
local function sRead() return tonumber(cvars.Sound_MusicVolume) or 1 end
local function sRelease()
    if Spoken.applied.Music and math.abs(sRead() - Spoken.applied.Music) > 0.005 then
        Spoken.original.Music, Spoken.applied.Music = nil, nil
        Spoken.gaveUp = Spoken.gaveUp + 1
    end
end
function Spoken:FadeTo(target, done)
    if self.fadeTimer then self.fadeTimer:Cancel(); self.fadeTimer = nil end
    sRelease()
    local start, progress = sRead(), 0
    local function step()
        progress = math.min(1, progress + 0.05 / 0.8)
        sRelease()
        if self.original.Music then
            SetCVar("Sound_MusicVolume", start + (target - start) * progress)
            self.applied.Music = sRead()
        end
        if progress >= 1 then
            if self.fadeTimer then self.fadeTimer:Cancel(); self.fadeTimer = nil end
            if done then done() end
        end
    end
    self.fadeTimer = C_Timer.NewTicker(0.05, step)
    step()
end
function Spoken:Lower()
    if not self.lowered then
        self.lowered = true
        self.original, self.applied = { Music = sRead() }, {}
    end
    self.restoring = false
    self:FadeTo(self.original.Music * 0.3)
end
function Spoken:Restore()
    if not self.lowered then return end
    self.restoring = true
    local function finished()
        self.lowered, self.restoring = false, false
        self.original, self.applied = {}, {}
    end
    if not self.original.Music then return finished() end
    self:FadeTo(self.original.Music, finished)
end
local function speak(seconds)
    Spoken:Lower()
    C_Timer.NewTimer(seconds + 1.2, function() Spoken:Restore() end)
end
local function range(seconds)
    local lo, hi = 9, -9
    for _ = 1, math.floor(seconds / 0.1) do
        local v = volumeAt(0.1)
        lo, hi = math.min(lo, v), math.max(hi, v)
    end
    return lo, hi
end

cvars.Sound_MusicVolume = START_VOLUME
fire("CVAR_UPDATE", "Sound_MusicVolume")
state.map = 1431; state.instance = false; fire("ZONE_CHANGED_NEW_AREA")
while not FAME.playing or FAME:Fading() do go(5) end
go(FAME.startedAt + 10 - now)
-- 1. A line while FAME is just playing: the common case.
Spoken.gaveUp = 0
speak(6)
go(1.0)
local ducked = tonumber(cvars.Sound_MusicVolume)
check(math.abs(ducked - 0.12) < 0.002, ("a line ducks the music to 30%% of 40%%: %.3f"):format(ducked))
local lo, hi = range(5)
check(lo > 0.115 and hi < 0.125, ("FAME leaves it there for the whole line (%.3f-%.3f)"):format(lo, hi))
go(4)
check(cvars.Sound_MusicVolume == START_VOLUME, ("and after the line it is back at 40%% (%s)"):format(cvars.Sound_MusicVolume))
check(Spoken.gaveUp == 0, "Spoken never mistook FAME for the player")

-- 2. A track ends in the middle of a line: FAME changes tracks without fading.
while not FAME.playing do go(5) end
go(FAME.startedAt + FAME.playing.len - 4 - now)          -- the end-of-track fade starts in ~1.5s
local before = FAME.playing
Spoken.gaveUp = 0
speak(12)
go(1.0)
lo, hi = range(10)
check(FAME.playing ~= before or FAME.state == "silence", "the track still ends on time, mid-line")
check(lo > 0.115 and hi < 0.125, ("with the music held at Spoken's level throughout (%.3f-%.3f)"):format(lo, hi))
go(10)
check(cvars.Sound_MusicVolume == START_VOLUME, ("then back at 40%% (%s)"):format(cvars.Sound_MusicVolume))
check(Spoken.gaveUp == 0, "and Spoken never gave the channel up")

-- 3. A line starts in the middle of a FAME fade.
while not FAME.playing do go(5) end
go(FAME.startedAt + FAME.playing.len - 1.2 - now)        -- mid end-of-track fade
local midValue = tonumber(cvars.Sound_MusicVolume)
Spoken.gaveUp = 0
speak(6)
go(1.0)
check(tonumber(cvars.Sound_MusicVolume) < midValue,
    ("Spoken ducks from FAME's half-faded level (%.3f -> %s)"):format(midValue, cvars.Sound_MusicVolume))
go(25)
check(cvars.Sound_MusicVolume == START_VOLUME,
    ("once both are done the level is 40%% again, not FAME's half-faded one (%s)"):format(cvars.Sound_MusicVolume))
check(Spoken.gaveUp == 0, "Spoken never gave the channel up")

-- 4. Many lines over a long session, at random moments.
Spoken.gaveUp = 0
local stuck = 0
for _ = 1, 40 do
    go(math.random(20, 200))
    speak(math.random(3, 15))
    go(30)
    -- An ordinary FAME fade may be running at this instant; let it finish.
    for _ = 1, 20 do if not FAME:Fading() then break end go(1) end
    if cvars.Sound_MusicVolume ~= START_VOLUME then stuck = stuck + 1 end
end
go(30)
check(stuck == 0, ("40 lines at random moments: the level is 40%% after every one (%d not)"):format(stuck))
check(Spoken.gaveUp == 0, ("Spoken never gave the channel up (%d times)"):format(Spoken.gaveUp))

-- 5. An addon that ducks the same way but exposes nothing: FAME still gives way.
SpokenEnv = nil
while not FAME.playing do go(5) end
go(FAME.startedAt + FAME.playing.len - 1.2 - now)        -- mid FAME fade
SetCVar("Sound_MusicVolume", 0.12)                       -- someone ducks, abruptly
go(3)
check(cvars.Sound_MusicVolume == "0.12", ("FAME stops fading and leaves another addon's level alone (%s)"):format(cvars.Sound_MusicVolume))
go(20)
SetCVar("Sound_MusicVolume", 0.4)                        -- and puts it back
go(30)
check(cvars.Sound_MusicVolume == START_VOLUME, "and when that addon puts it back, it stays back")

------------------------------------------------------------------------------
realPrint("\nslash commands")
for _, input in ipairs({ "", "help", "status", "where", "pool 3", "skip", "next", "chance 25",
                          "chance", "first", "first", "debug", "status", "where", "debug",
                          "verify", "verify", "scan 53492 53493 1", "play 53519", "status",
                          "off", "status", "where", "on", "toggle", "toggle", "bogus",
                          "ban", "banlist", "unban", "unban all", "banlist" }) do
    local ok, err = run(input)
    check(ok, ("/fame %s"):format(input == "" and "(no args)" or input))
    if not ok then realPrint("        " .. tostring(err)) end
end
go(3)                        -- toggling off starts a 1.2s fade-out; on waits for it
check(FAME.state ~= "off", "back on after toggling twice")
go(30)
check(cvars.Sound_MusicVolume == START_VOLUME, "volume intact after every command")

------------------------------------------------------------------------------
realPrint("\na new session after quitting mid-fade")
-- Quitting can leave the client holding a mid-fade value.  A fresh load of
-- the addon should recognise the mark and put the saved level back.
local function freshSession()
    FAME:CancelTimer()
    if FAME.poll then FAME.poll:Cancel() end
    FAME:StopRamps()
    for _, t in ipairs(pending) do t.dead = true end
    local ns2 = {}
    ns = ns2
    for _, file in ipairs({ "Tracks.lua", "LocalTracks.lua", "Originals.lua", "Zones.lua", "Core.lua" }) do
        assert(loadfile(ROOT .. "/" .. file))(ADDON, ns2)
    end
    FAME = ns2.core
    fameRef = FAME
    fire("ADDON_LOADED", ADDON)
    fire("PLAYER_ENTERING_WORLD")
end
ForeverAmbientMusicExtendedDB.userVolume = 0.4
cvars.Sound_MusicVolume = "0.200537"
freshSession()
check(cvars.Sound_MusicVolume == "0.4", ("with the level saved, it is restored at login (%s)"):format(cvars.Sound_MusicVolume))

ForeverAmbientMusicExtendedDB.userVolume = nil
ForeverAmbientMusicExtendedDB.fadeGuard = { user = 0.4, last = "0.300537" }
cvars.Sound_MusicVolume = "0.300537"
freshSession()
check(cvars.Sound_MusicVolume == "0.4", ("the note of a fade in progress also restores it (%s)"):format(cvars.Sound_MusicVolume))

ForeverAmbientMusicExtendedDB.userVolume = nil
ForeverAmbientMusicExtendedDB.fadeGuard = nil
cvars.Sound_MusicVolume = "0.200537"
local chatMark = #chat
freshSession()
local warned = false
for i = chatMark + 1, #chat do if chat[i]:find("left part-way through a fade", 1, true) then warned = true end end
check(cvars.Sound_MusicVolume == "0.200537" and warned,
    "without a saved level (beta saved variables), it is left alone and the player is told once")
cvars.Sound_MusicVolume = "0.35"
fire("CVAR_UPDATE", "Sound_MusicVolume")
check(FAME.userVolume == 0.35 and ForeverAmbientMusicExtendedDB.userVolume == 0.35,
    "setting it once is remembered")

realPrint(("\n%d failures"):format(failures))
os.exit(failures > 0 and 1 or 0)
