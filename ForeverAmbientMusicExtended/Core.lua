-- Core.lua -- the music schedule and location detection.
--
-- Shape of the thing: in a mapped zone, FAME runs the music schedule the game
-- would have run -- same tracks to choose from, same silences between them,
-- same intros on arrival -- and swaps a share of those tracks for ones from
-- the extended pool.  Everywhere else (instances, unmapped places, music
-- turned off) it lets go and the game plays its own music as normal.
--
-- Why it has to run the schedule rather than slip tracks into the game's:
-- nothing in the API says when the game's zone music starts or stops, so
-- there is no moment to slip into.  What the API does offer:
--   * PlayMusic() suppresses the game's zone music for as long as it runs.
--   * PlayMusic() loops forever and fires no "finished" event, so every track
--     carries its measured duration and a timer moves things on.
--   * The game's own rules -- each area's tracks, the silence interval
--     between them, intros and their cooldowns -- are client data, shipped
--     here as Originals.lua.
-- Silences are held by playing a silent file (Media/silence.mp3) through
-- PlayMusic(), so the game cannot start a track of its own in the middle of
-- one.

local ADDON, ns = ...

local PREFIX = "|cff7fd5ffFAME|r: "
local SILENCE = "Interface\\AddOns\\" .. ADDON .. "\\Media\\silence.mp3"

local FAME = CreateFrame("Frame", "ForeverAmbientMusicExtendedFrame")
ns.core = FAME

-- --------------------------------------------------------------------------
-- Settings
-- --------------------------------------------------------------------------

-- Beta note: some Forever builds write SavedVariables but never load them
-- back, so nothing here may depend on a saved value surviving a logout.
-- These defaults are what the addon is tuned for; the saved table only ever
-- overlays them.
local defaults = {
    enabled = true,
    -- Share of tracks left as the game's own.  The rest come from the
    -- extended pool.
    originalChance = 0.40,
    -- false: the first track in a new place is always the game's own, the
    -- way you would hear it arriving without the addon.  true: the extended
    -- pool can take that first slot too.
    displaceFirst = false,
    debug = false,
    -- Tracks the player has banned with /fame ban, keyed by fileDataID (or
    -- file path, for a local track): { zone = "...", kind = "...", at = time }.
    banned = {},
}

local db = {}
for k, v in pairs(defaults) do db[k] = v end

-- --------------------------------------------------------------------------
-- Tag vocabulary
-- --------------------------------------------------------------------------

-- Tags are sorted into axes so Zones.lua can allow-list each axis separately.
-- A tag that is in none of these sets is ignored by the matcher, which keeps
-- an experimental tag from silently excluding a track everywhere.
local function set(...)
    local t = {}
    for _, v in ipairs({ ... }) do t[v] = true end
    return t
end

local BIOME = set("forest", "darkforest", "enchanted", "jungle", "swamp",
    "plains", "barrens", "desert", "mountain", "snow", "volcanic", "coast",
    "sea", "cave", "underground", "ruins", "blighted", "void", "arcane",
    "elemental", "sky", "city", "town", "tavern")

local CULTURE = set("human", "dwarf", "gnome", "nightelf", "highelf", "orc",
    "tauren", "troll", "undead", "goblin", "naga", "draenei", "pandaren",
    "dragon", "demon", "centaur", "tuskarr", "earthen", "arathi", "kultiran",
    "drust", "vrykul", "nerubian", "pirate", "wild")

local MOOD = set("calm", "melancholy", "mysterious", "eerie", "ominous",
    "heroic", "sacred", "festive", "somber", "tense", "grand", "playful")

ns.BIOME, ns.CULTURE, ns.MOOD = BIOME, CULTURE, MOOD

-- --------------------------------------------------------------------------
-- Small helpers
-- --------------------------------------------------------------------------

local function say(fmt, ...)
    print(PREFIX .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end

local function debugf(fmt, ...)
    if db.debug then say("|cff888888" .. fmt .. "|r", ...) end
end

local function rand(lo, hi)
    if hi < lo then lo, hi = hi, lo end
    return lo + math.random() * (hi - lo)
end

-- GetCVarBool moved under C_CVar in later retail builds while the global
-- stayed around.  Try both rather than assume which one this client has.
local function cvarBool(name)
    local fn = GetCVarBool or (C_CVar and C_CVar.GetCVarBool)
    if not fn then return nil end
    local ok, value = pcall(fn, name)
    if ok then return value end
    return nil
end

local function cvarGet(name)
    local fn = GetCVar or (C_CVar and C_CVar.GetCVar)
    if not fn then return nil end
    local ok, value = pcall(fn, name)
    if ok then return value end
    return nil
end

local function cvarSet(name, value)
    local fn = SetCVar or (C_CVar and C_CVar.SetCVar)
    if not fn then return end
    pcall(fn, name, value)
end

local function soundAvailable()
    if cvarBool("Sound_EnableAllSound") == false then return false end
    if cvarBool("Sound_EnableMusic") == false then return false end
    return true
end

-- The Audio options' "Loop Music" toggle.  Off, the game leaves its silence
-- interval between tracks; on, it plays them back to back.  FAME follows it
-- the same way.  The CVar name is not certain on this client, hence the list;
-- if none can be read, FAME assumes off, which is the game's default.
local LOOP_MUSIC_CVARS = { "Sound_ZoneMusicNoDelay", "Sound_LoopMusic" }

local function loopMusic()
    for _, name in ipairs(LOOP_MUSIC_CVARS) do
        local value = cvarBool(name)
        if value ~= nil then return value, name end
    end
    return nil, nil
end

-- Server hour drives the in-game day/night cycle, so it also picks between
-- a set's day and night tracks and silences, and gates day/night-tagged
-- extended tracks.
local function isNight()
    local hour = GetGameTime()
    if not hour then return false end
    return hour >= 21 or hour < 6
end

local function contains(list, value)
    if not list then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

-- --------------------------------------------------------------------------
-- Where are we, musically
-- --------------------------------------------------------------------------

-- Subzones whose music differs from their zone's, indexed by the name
-- GetSubZoneText() returns.  Built lazily per zone, asking the client for
-- each area's name so the match holds in any locale; the English name from
-- Originals.lua is only a fallback.
local subzoneIndex = {}

local function subzoneEntry(mapID, subName)
    if not subName or subName == "" then return nil end
    local index = subzoneIndex[mapID]
    if not index then
        index = {}
        local zm = ns.zoneMusic[mapID]
        for _, row in ipairs(zm and zm.sub or {}) do
            local areaID, english, setID, introID = row[1], row[2], row[3], row[4]
            local entry = { area = areaID, set = setID, intro = introID }
            local localName = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
            index[localName or english] = entry
            index[english] = index[english] or entry
        end
        subzoneIndex[mapID] = index
    end
    return index[subName]
end

-- Which inn, if any, the player is standing in.  Inside an inn the minimap
-- shows the building's own name ("Lion's Pride Inn"); ns.inns in Zones.lua
-- says which of those FAME knows the race of.
--   returns race, name   -- a known inn
--   returns false        -- some other inn: leave it to the game
--   returns nil          -- not in an inn
local function currentInn(prof)
    local name = GetMinimapZoneText and GetMinimapZoneText()
    local race = name and ns.inns[name]
    if race then return race, name end
    -- Resting indoors outside a capital, but not a building on the list: an
    -- inn whose race FAME does not know.  (In a capital IsResting() is true
    -- on every street, so it means nothing there.)
    if IsResting() and IsIndoors and IsIndoors() and not prof.capital then return false end
    return nil
end

-- Is the game's own idea of the current zone the one FAME mapped?  Out at
-- sea on a ship, the map can still place you in the nearest coastal zone
-- while the game has you in The Great Sea -- an area of its own, with music
-- of its own.  GetZoneText() is the game's answer, so FAME compares against
-- that, using the client's own name for the mapped area (C_Map.GetAreaInfo)
-- and the English one only on an English client.  If neither is available
-- the check is skipped rather than guessed.
local zoneNames = {}

local function gameAgreesOnZone(zm)
    local expected = zoneNames[zm.area]
    if expected == nil then
        expected = (C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(zm.area))
            or (GetLocale and GetLocale():sub(1, 2) == "en" and zm.name)
            or false
        zoneNames[zm.area] = expected
    end
    if not expected then return true end
    local actual = GetZoneText()
    if not actual or actual == "" then return true end
    return actual == expected
end

-- The music context for where the player stands, or nil plus the reason
-- FAME should stay out of it.  `key` identifies the music the game would be
-- playing: two places with the same key sound the same, so moving between
-- them does not restart anything -- exactly as the game behaves.
local function resolveContext()
    if not db.enabled then return nil, "off" end
    if not soundAvailable() then return nil, "muted" end
    -- Dead, or walking back as a spirit: the game has music rules of its own
    -- for that, and FAME stays out of them entirely.
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil, "dead" end
    if IsInInstance() then return nil, "instance" end

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local zm = mapID and ns.zoneMusic[mapID]
    local prof = mapID and ns.zones[mapID]
    if not (zm and prof) then return nil, "unmapped" end
    if not gameAgreesOnZone(zm) then return nil, "elsewhere" end

    local ctx = { mapID = mapID, prof = prof, setID = zm.set, area = zm.area, introID = zm.intro }
    local sub = subzoneEntry(mapID, GetSubZoneText())
    if sub then
        ctx.area, ctx.introID = sub.area, sub.intro
        if sub.set ~= 0 then ctx.setID = sub.set end
        -- A town inside the zone -- Ratchet in the Barrens -- draws its
        -- extended tracks from its own profile.
        if prof.towns and prof.towns[sub.area] then ctx.prof = prof.towns[sub.area] end
    end

    local race, innName = currentInn(prof)
    if race == false then return nil, "inn" end
    if race then
        -- The tavern's own race only: the game's tavern set for that race,
        -- and that race's tavern tracks from the extended pool.
        ctx.setID = ns.tavernSets[race]
        ctx.prof = ns.innProfiles[race]
        ctx.area = "inn:" .. innName
        ctx.introID = 0
        ctx.inn = innName
        ctx.key = "inn:" .. innName
    else
        ctx.key = "set:" .. ctx.setID
    end

    ctx.set = ns.musicSets[ctx.setID]
    if not ctx.set then return nil, "unmapped" end
    return ctx
end

-- --------------------------------------------------------------------------
-- Track selection
-- --------------------------------------------------------------------------

local function carries(track, tag)
    for i = 1, #track.tags do
        if track.tags[i] == tag then return true end
    end
    return false
end

-- Every tag a track carries has to be allowed by the zone on its own axis,
-- and the track has to carry at least one biome.  That last rule matters: a
-- track with no biome used to pass the biome check everywhere, which is how
-- goblin bazaar music ended up across the open Barrens.  Culture and mood
-- tags the track does not carry are still not checked, so a track that
-- names only its place travels to every zone with that kind of place.
local function eligible(track, prof, night)
    -- `require` is checked first and is the only positive test: the three
    -- allow-lists below can reject a tag but cannot demand one.
    if prof.require then
        for _, tag in ipairs(prof.require) do
            if not carries(track, tag) then return false end
        end
    end
    local placed = false
    for _, tag in ipairs(track.tags) do
        if tag == "day" then
            if night then return false end
        elseif tag == "night" then
            if not night then return false end
        elseif BIOME[tag] then
            if not contains(prof.biomes, tag) then return false end
            placed = true
        elseif CULTURE[tag] then
            if not contains(prof.cultures, tag) then return false end
        elseif MOOD[tag] then
            if not contains(prof.moods, tag) then return false end
        end
    end
    return placed
end

function FAME:Pool(prof, night)
    if not prof then return {} end
    if night == nil then night = isNight() end
    if self.poolProf == prof and self.poolNight == night and self.pool then
        return self.pool
    end
    local pool = {}
    for _, track in ipairs(ns.allTracks) do
        if eligible(track, prof, night) then pool[#pool + 1] = track end
    end
    self.pool, self.poolProf, self.poolNight = pool, prof, night
    return pool
end

-- A file this client does not have plays silently and still reports success
-- from PlayMusic, which would hand us a dead slot.  PlaySoundFile is the only
-- thing that tells the truth: it returns a zero handle for a missing file.
-- So the first time such a track comes up, start it on the Music channel and
-- stop it in the same frame -- long enough to read the handle, short enough
-- not to hear.  The answer is cached for the session.
--
-- Local files get this check, because nothing verified them offline.
local playableCache = {}

local function probe(key)
    local willPlay, handle = PlaySoundFile(key, "Music")
    if handle and handle > 0 then
        StopSound(handle, 0)
        return willPlay and true or false
    end
    return false
end

function FAME:Playable(track)
    local key = track.id or track.file
    if not key then return false end
    -- Only local files get the probe.  Built-in tracks are checked before
    -- every release instead, against the client's own file manifest
    -- (tools/casc_scan.py --check-addon).
    if track.id then return true end
    local cached = playableCache[key]
    if cached ~= nil then return cached end
    local ok = probe(key)
    playableCache[key] = ok
    if not ok then debugf("not in client, dropping: %s", tostring(key)) end
    return ok
end

-- Bans apply to everything FAME chooses -- the game's own tracks, extended
-- ones, intros -- and they apply before the choice, not after: each list is
-- filtered first, so a decision only ever lands on something playable.
local function trackKey(track) return track.id or track.file end

local function isBanned(track)
    return db.banned[trackKey(track)] ~= nil
end

local function unbanned(list)
    local out = {}
    for _, track in ipairs(list or {}) do
        if not isBanned(track) then out[#out + 1] = track end
    end
    return out
end

-- A random entry, avoiding the track just played when there is a choice.
-- `ok` filters further (the presence probe for local files).
local function pickFrom(list, previous, ok)
    if #list == 0 then return nil end
    local prevKey = previous and trackKey(previous)
    for _ = 1, 15 do
        local track = list[math.random(#list)]
        if (#list == 1 or trackKey(track) ~= prevKey) and (not ok or ok(track)) then
            return track
        end
    end
    return nil
end

-- Extended tracks for this profile that are not banned.
function FAME:ExtendedChoices(prof)
    return unbanned(self:Pool(prof))
end

-- The game's own tracks for this set that are not banned, the way the game
-- picks: the night list after dark when the set has one.
function FAME:OriginalChoices(musicSet)
    local list = isNight() and musicSet.night or musicSet.day
    if not list or #list == 0 then list = musicSet.day or musicSet.night end
    return unbanned(list)
end

function FAME:Pick(prof)
    return pickFrom(self:ExtendedChoices(prof), self.previous,
        function(track) return FAME:Playable(track) end)
end

function FAME:PickOriginal(musicSet)
    return pickFrom(self:OriginalChoices(musicSet), self.previous)
end

local function silenceFor(musicSet)
    local s = musicSet.silence
    if isNight() then return rand(s[3], s[4]) end
    return rand(s[1], s[2])
end

-- --------------------------------------------------------------------------
-- Timers
-- --------------------------------------------------------------------------

function FAME:CancelTimer()
    if self.timer then
        self.timer:Cancel()
        self.timer = nil
    end
end

function FAME:In(seconds, fn)
    self:CancelTimer()
    self.nextAt = GetTime() + seconds
    self.timer = C_Timer.NewTimer(seconds, function()
        FAME.timer = nil
        fn()
    end)
end

-- --------------------------------------------------------------------------
-- Volume: the only way to fade
-- --------------------------------------------------------------------------

-- Nothing in the API fades music out: StopMusic() is instant and takes no
-- arguments.  So a fade ramps the Music channel's volume down, does whatever
-- comes next while it is down, and puts the slider back.
--
-- The slider's own value is saved before the first step and restored on
-- every path out -- ramp finished, zone change, release, logout -- so an
-- interrupted fade cannot leave the player's music volume turned down.
local FADE_STEPS = 12
local FADE_OUT = 2.5        -- into the natural end of a track
local FADE_CUT = 1.2        -- when something interrupts one
-- The client crossfades between PlayMusic calls: for a moment after a swap,
-- the old track is still sounding.  So after a fade the volume stays down
-- through that crossfade -- QUIET_AFTER when silence follows, SWAP_HOLD when
-- another track does, which then fades in over FADE_IN.  Restoring at once
-- is what let the old track blip back at full volume before the new one.
local QUIET_AFTER = 2.5
local SWAP_HOLD = 1.0
local FADE_IN = 1.0

-- The slider is shared.  The player moves it; the Settings panel can read it
-- mid-fade and write that value back on close; and some addons fade it
-- themselves -- Spoken Quests turns music down to 30% while a line is spoken.
-- Spoken guards the slider the same way FAME does: if it finds a value it
-- didn't set, it decides the player moved it and gives the channel up for
-- good, never putting it back.  Two addons each taking the other for the
-- player is how a volume ends up stuck quiet.  So FAME's rule is to give way:
--
--   * FAME knows exactly what it wrote: after every write it notes the value
--     the client reports back.  Its mid-fade values also carry an odd offset
--     (0.2 becomes 0.200537), so no other addon's arithmetic lands on them.
--   * Mid-fade, the moment the slider holds anything else, someone else is
--     working it.  FAME yields: it stops fading, finishes whatever the fade
--     was for, and puts nothing back.  For a few seconds after any outside
--     change it swaps tracks with a hard cut rather than a fade.
--   * While Spoken is ducking or fading, FAME doesn't touch the slider at
--     all, and takes the level Spoken noted before ducking as the player's.
--   * A FAME mid-fade value turning up later, with nothing else moving the
--     slider, is a stale replay: FAME puts the player's level back.
--   * Any other outside change is the player's choice and becomes the level
--     fades return to.  It is saved, along with a note of any fade in
--     progress, so a quit mid-fade is healed at the next login.
local MUSIC_VOLUME = "Sound_MusicVolume"
local YIELD_SECONDS = 5
local MARK = 0.000537

local function marked(v)
    v = math.max(0, math.min(0.998, v))
    return math.floor(v * 1000) / 1000 + MARK
end

local function key(v) return v and string.format("%.6f", v) end

-- Values FAME has written mid-fade this session, as the client reported them.
local ours = {}

local function isOurs(v) return v ~= nil and ours[key(v)] == true end

-- Across sessions there is no record, only the offset: six decimals ending 537.
local function looksLikeOurs(v)
    if not v then return false end
    local s = key(v)
    return s:sub(-3) == "537"
end

local function readRaw() return cvarGet(MUSIC_VOLUME) end
local function readVolume() return tonumber(readRaw()) end

-- Spoken publishes no API for its ducking, so this reads its state directly,
-- defensively: a missing field means "not ducking", and the general rule
-- above still keeps the two from fighting.  Returns busy, and the music level
-- Spoken noted before it ducked.
local function spokenDucking()
    local env = rawget(_G, "SpokenEnv")
    local sounds = type(env) == "table" and rawget(env, "OtherSounds")
    if type(sounds) ~= "table" then return false end
    if not (sounds.lowered or sounds.fadeTimer) then return false end
    local original = type(sounds.original) == "table" and tonumber(sounds.original.Music)
    return true, original
end

function FAME:SetUserVolume(v)
    self.userVolume = v
    ForeverAmbientMusicExtendedDB = ForeverAmbientMusicExtendedDB or {}
    ForeverAmbientMusicExtendedDB.userVolume = v
end

local function saveGuard(user, last)
    ForeverAmbientMusicExtendedDB = ForeverAmbientMusicExtendedDB or {}
    ForeverAmbientMusicExtendedDB.fadeGuard = { user = user, last = last }
end

local function clearGuard()
    if ForeverAmbientMusicExtendedDB then ForeverAmbientMusicExtendedDB.fadeGuard = nil end
end

-- Every write FAME makes goes through here.  `mid` marks a mid-fade value.
function FAME:Write(v, mid)
    self.writing = true
    cvarSet(MUSIC_VOLUME, mid and marked(v) or v)
    self.writing = false
    local back = readRaw()
    self.lastWritten = back
    if mid and back then
        ours[key(tonumber(back))] = true
        if self.savedVolume then saveGuard(self.savedVolume, back) end
    end
end

-- Has someone else moved the slider since FAME last wrote it?
function FAME:Foreign()
    return self.lastWritten ~= nil and readRaw() ~= self.lastWritten
end

-- Is someone else working the slider right now?
function FAME:Yielding()
    if spokenDucking() then return true end
    return self.foreignAt ~= nil and GetTime() - self.foreignAt < YIELD_SECONDS
end

function FAME:StopRamps()
    if self.rampTicker then self.rampTicker:Cancel(); self.rampTicker = nil end
    if self.restoreTimer then self.restoreTimer:Cancel(); self.restoreTimer = nil end
end

-- Give the slider up mid-fade: stop, write nothing more, put nothing back,
-- and do now whatever the fade was leading up to.
function FAME:Yield(why)
    debugf("music volume is being moved by something else (%s) -- leaving it alone", why)
    self.foreignAt = GetTime()
    self:StopRamps()
    self.savedVolume, self.lastWritten = nil, nil
    clearGuard()
    local pending = self.pendingAction
    self.pendingAction = nil
    if pending then pending() end
end

-- One step of a fade.  False when FAME has had to yield instead.
function FAME:WriteStep(v)
    if spokenDucking() then self:Yield("Spoken is ducking"); return false end
    if self:Foreign() then self:Yield("mid-fade"); return false end
    self:Write(v, true)
    return true
end

-- End of a fade: the player's level back -- unless someone else has moved
-- the slider meanwhile, in which case it is theirs and stays as they left it.
function FAME:RestoreVolume()
    self:StopRamps()
    self.pendingAction = nil
    if not self.savedVolume then return end
    if self:Foreign() or spokenDucking() then return self:Yield("at the end of a fade") end
    local v = self.savedVolume
    self:SetUserVolume(v)
    self.savedVolume = nil
    self:Write(v, false)
    self.lastWritten = nil
    clearGuard()
end

-- Outside a fade: track the player's level, and heal a stale FAME value.
function FAME:CheckVolume()
    if self.writing then return end
    if self.savedVolume then
        -- Mid-fade: catch an outside change straight away, not at the next step.
        if self:Foreign() then self:Yield("mid-fade") end
        return
    end
    local now = readVolume()
    if not now then return end

    local busy, spokenLevel = spokenDucking()
    if busy then
        -- Spoken's noted level is the player's -- unless it noted one of FAME's
        -- own mid-fade values, having started in the middle of a FAME fade.
        if spokenLevel and not isOurs(spokenLevel) and not looksLikeOurs(spokenLevel) then
            if spokenLevel ~= self.userVolume then self:SetUserVolume(spokenLevel) end
        end
        self.foreignAt = GetTime()
        return
    end

    if isOurs(now) or looksLikeOurs(now) then
        -- One of FAME's mid-fade values, replayed.  Wait until nothing else
        -- has moved the slider for a few seconds -- Spoken restoring a level it
        -- noted mid-fade lands here too -- then put the player's level back.
        if self:Yielding() then return end
        if self.userVolume and not looksLikeOurs(self.userVolume) then
            debugf("music volume was left at %s, a value from an old fade -- putting back %.2f",
                key(now), self.userVolume)
            self:Write(self.userVolume, false)
            self.lastWritten = nil
        elseif not self.warnedVolume then
            self.warnedVolume = true
            say("your music volume (%d%%) looks like it was left part-way through a fade, and FAME doesn't know your usual level. Set it once in the Sound options and FAME will keep it there.", math.floor(now * 100 + 0.5))
        end
    elseif now ~= self.userVolume then
        -- The player, or another addon: either way, theirs.
        self.foreignAt = GetTime()
        self:SetUserVolume(now)
    end
end

-- At login: a fade the last session never finished leaves the slider on a
-- value FAME noted; put back the level FAME noted with it.
function FAME:RecoverGuard()
    local guard = ForeverAmbientMusicExtendedDB and ForeverAmbientMusicExtendedDB.fadeGuard
    clearGuard()
    if type(guard) ~= "table" then return end
    local user = tonumber(guard.user)
    if user and guard.last and readRaw() == guard.last then
        debugf("music volume left mid-fade last session -- putting back %.2f", user)
        self:SetUserVolume(user)
        self:Write(user, false)
        self.lastWritten = nil
    end
end

-- Hold the volume down through the client's crossfade, then bring it back
-- up gently to the player's own level.
function FAME:FadeBackIn()
    self:StopRamps()
    if not self.savedVolume then return end
    self.restoreTimer = C_Timer.NewTimer(SWAP_HOLD, function()
        FAME.restoreTimer = nil
        local step = 0
        FAME.rampTicker = C_Timer.NewTicker(FADE_IN / FADE_STEPS, function()
            step = step + 1
            if not FAME.savedVolume then FAME:StopRamps(); return end
            if step >= FADE_STEPS then
                FAME.rampTicker = nil
                FAME:RestoreVolume()
            else
                FAME:WriteStep(FAME.savedVolume * step / FADE_STEPS)
            end
        end, FADE_STEPS)
    end)
end

function FAME:Fading()
    return self.savedVolume ~= nil
end

-- Ramp to silence over `seconds`, then run `andThen` with the volume still
-- down.  After that, `quietAfter` (silence follows) restores the level once
-- the crossfade is over; otherwise (a track follows) it fades back in.
--
-- If a fade is already under way -- say a fade-in, cut short by walking into
-- the next zone -- this ramps down from wherever the volume is now, and keeps
-- the player's original level as the one to return to.
function FAME:RampDown(seconds, andThen, quietAfter)
    self:StopRamps()
    self:CheckVolume()
    if self:Yielding() then
        -- Someone else is working the slider: no fade, just do it.
        self.savedVolume, self.lastWritten = nil, nil
        return andThen()
    end
    local current = readVolume()
    if not self.savedVolume then
        -- Starting fresh: come back to the slider as found, unless it holds a
        -- stale FAME value.  And note it, to tell later whether anyone else
        -- has touched it.
        self.savedVolume = (current and not isOurs(current) and not looksLikeOurs(current))
            and current or self.userVolume
        self.lastWritten = readRaw()
        saveGuard(self.savedVolume, self.lastWritten)
    end
    if not current or not self.savedVolume or self.savedVolume <= 0 or seconds <= 0 then
        andThen()
        self:RestoreVolume()
        return
    end
    self.pendingAction = andThen
    local step = 0
    self.rampTicker = C_Timer.NewTicker(seconds / FADE_STEPS, function()
        step = step + 1
        if not FAME:WriteStep(current * math.max(0, 1 - step / FADE_STEPS)) then return end
        if step < FADE_STEPS then return end
        FAME.rampTicker, FAME.pendingAction = nil, nil
        andThen()
        if quietAfter then
            FAME.restoreTimer = C_Timer.NewTimer(QUIET_AFTER, function()
                FAME.restoreTimer = nil
                FAME:RestoreVolume()
            end)
        else
            FAME:FadeBackIn()
        end
    end, FADE_STEPS)
end

-- Fade out whatever of ours is audible, then run `andThen`.
--
-- `self.audible` is true from the moment one of our tracks starts until it
-- has been replaced (by the silent file, or StopMusic).  That includes the
-- second or so while it fades out, when `self.playing` is already cleared --
-- so a second fade that cuts into the first picks up from wherever the
-- volume has got to, rather than snapping it back up or losing the track.
function FAME:FadeOut(seconds, andThen, quietAfter)
    if self.playing then
        self.previous = self.playing
        self.playing, self.kind = nil, nil
    end
    if self.audible then
        self:RampDown(seconds, andThen, quietAfter)
    elseif self.savedVolume then
        -- Already quiet -- the silence just after a fade -- so there is
        -- nothing to ramp, but the volume is still down and comes back the
        -- usual way once whatever follows has started.
        self:StopRamps()
        andThen()
        if quietAfter then
            self.restoreTimer = C_Timer.NewTimer(QUIET_AFTER, function()
                FAME.restoreTimer = nil
                FAME:RestoreVolume()
            end)
        else
            self:FadeBackIn()
        end
    else
        andThen()
    end
end

-- --------------------------------------------------------------------------
-- The schedule
-- --------------------------------------------------------------------------

-- What FAME is doing.  The quiet states are the interesting ones: they all
-- sound the same from the speakers.
local STATE = {
    off      = "off -- the game plays its own music",
    muted    = "music is off in the sound options",
    instance = "in an instance -- the game plays its own music",
    unmapped = "no data for this place -- the game plays its own music",
    dead     = "dead or a spirit -- the game plays its own music",
    elsewhere = "the game has you outside this zone (at sea?) -- it plays its own music",
    inn      = "in an inn FAME doesn't know the race of -- the game plays its own music",
    original = "playing the game's own track",
    extended = "playing an extended track",
    intro    = "playing the game's intro for this place",
    test     = "playing a track by request",
    silence  = "holding the game's silence between tracks",
}

function FAME:SetState(state)
    if self.state ~= state then debugf("-> %s", STATE[state] or state) end
    self.state = state
end

function FAME:StateText()
    return STATE[self.state or "off"] or tostring(self.state)
end

function FAME:PlayTrack(track, kind)
    self:CancelTimer()
    -- No volume handling here: when a fade hands over to this track the volume
    -- is down on purpose, and the fade brings it back once the swap is done.
    PlayMusic(track.id or track.file)
    self.holding, self.audible = false, true
    self.playing, self.kind = track, kind
    self.startedAt = GetTime()
    self:SetState(kind)
    debugf("%s %s, %ds%s", kind, track.name or tostring(track.id or track.file), track.len,
        track.tags and (" [" .. table.concat(track.tags, " ") .. "]") or "")
    -- Start the fade early enough that it lands on the track's own ending.
    -- PlayMusic loops, so overrunning means hearing it restart from the top.
    local fade = math.min(FADE_OUT, track.len * 0.25)
    self:In(math.max(1, track.len - fade), function() FAME:AfterTrack(fade) end)
end

-- A track has ended (or been skipped).  What happens next is what the game
-- would do: the next track straight away with Loop Music on, otherwise the
-- set's own silence interval first.
function FAME:AfterTrack(fade)
    if not self.ctx then return end
    if loopMusic() then
        self:FadeOut(fade, function() FAME:NextTrack() end, false)
    else
        local seconds = silenceFor(self.ctx.set)
        self:FadeOut(fade, function() FAME:HoldSilence(seconds) end, true)
    end
end

function FAME:HoldSilence(seconds)
    self:CancelTimer()
    if seconds < 1 then return self:NextTrack() end
    if self.silenceWorks ~= false then
        PlayMusic(SILENCE)
    else
        -- No silent file to hold the channel with: let go, and accept the
        -- game may start a track of its own during the gap.
        StopMusic()
    end
    self.holding, self.audible = true, false
    self:SetState("silence")
    debugf("silence for %ds", seconds)
    self:In(seconds, function() FAME:NextTrack() end)
end

function FAME:NextTrack()
    local ctx = self.ctx
    if not ctx then return end
    -- A set with no tracks is the game deliberately keeping a place quiet.
    -- There is nothing to displace, so FAME keeps it quiet too.
    if #ctx.set.day + #ctx.set.night == 0 then
        ctx.first = false
        return self:HoldSilence(silenceFor(ctx.set))
    end

    local originals = self:OriginalChoices(ctx.set)
    local extended = self:ExtendedChoices(ctx.prof)
    if #originals == 0 and #extended == 0 then
        -- Everything this place could play has been banned.  Play nothing,
        -- say why, and check again after the game's usual silence -- at
        -- least a minute, so Loop Music cannot turn this into a busy loop.
        say("All music for the zone was banned, playing nothing. Unban songs with /fame unban command")
        ctx.first, ctx.allBanned = false, true
        return self:HoldSilence(math.max(60, silenceFor(ctx.set)))
    end
    ctx.allBanned = false

    local wantOriginal
    if ctx.first and not db.displaceFirst then
        wantOriginal = true
    else
        wantOriginal = math.random() < db.originalChance
    end
    ctx.first = false

    -- Whichever kind the roll asked for, unless bans have emptied it; then
    -- the other kind.  Either way the pick comes from unbanned tracks.
    local order = wantOriginal and { "original", "extended" } or { "extended", "original" }
    for _, kind in ipairs(order) do
        local track
        if kind == "original" then
            track = pickFrom(originals, self.previous)
        else
            track = pickFrom(extended, self.previous, function(t) return FAME:Playable(t) end)
        end
        if track then return self:PlayTrack(track, kind) end
    end
    -- Only reachable when every unbanned extended track is a local file that
    -- turned out to be missing and there are no originals left.
    self:HoldSilence(silenceFor(ctx.set))
end

-- Intros play on arriving in their area, at most once per cooldown -- the
-- game's MinDelayMinutes, kept in Originals.lua.
local introPlayedAt = {}

function FAME:DueIntro(ctx)
    local intro = ctx.introID ~= 0 and ns.intros[ctx.introID]
    if not intro or #unbanned(intro.tracks) == 0 then return nil end
    local last = introPlayedAt[ctx.introID]
    if last and GetTime() - last < intro.delay then return nil end
    return intro, ctx.introID
end

function FAME:PlayIntro(intro, introID)
    introPlayedAt[introID] = GetTime()
    if self.ctx then self.ctx.first = false end   -- the intro is the game's own
    local tracks = unbanned(intro.tracks)
    self:PlayTrack(tracks[math.random(#tracks)], "intro")
end

-- Arriving somewhere whose music differs from where we were: the game starts
-- that place's music on arrival, so FAME does too.
function FAME:Enter(ctx)
    self:CancelTimer()
    self.ctx, self.area = ctx, ctx.area
    ctx.first = true
    local intro, introID = self:DueIntro(ctx)
    self:FadeOut(FADE_CUT, function()
        if intro then FAME:PlayIntro(intro, introID) else FAME:NextTrack() end
    end, false)
end

-- Hand the music channel back to the game.  Anything of ours still in the
-- channel -- a track, one mid-fade, or the silent file -- gets stopped:
-- PlayMusic loops forever, so a track left there would never end.
function FAME:Release(state)
    self:CancelTimer()
    self.ctx, self.area = nil, nil
    if self.audible or self.holding or self.savedVolume then
        self.holding = false
        self:FadeOut(FADE_CUT, function()
            StopMusic()
            FAME.audible = false
        end, false)
    end
    self:SetState(state)
end

-- Work out where we are and react.  Runs on every location event and on a
-- slow poll, so it has to be cheap and idempotent.
function FAME:Evaluate()
    local ctx, why = resolveContext()
    if not ctx then
        if self.ctx or self.state ~= why then self:Release(why) end
        return
    end

    if not self.ctx or self.ctx.key ~= ctx.key then
        debugf("music changes here: %s", ctx.set.name)
        return self:Enter(ctx)
    end

    -- Same music, possibly a different zone (Orgrimmar and the Barrens share
    -- a set): keep playing, but draw future extended tracks from here.
    self.ctx.prof, self.ctx.mapID = ctx.prof, ctx.mapID

    if ctx.area ~= self.area then
        self.area = ctx.area
        self.ctx.area, self.ctx.introID = ctx.area, ctx.introID
        local intro, introID = self:DueIntro(ctx)
        if intro then
            self:CancelTimer()
            self:FadeOut(FADE_CUT, function() FAME:PlayIntro(intro, introID) end, false)
            return
        end
    end

    -- Loop Music switched on in the middle of a silence: the game would be
    -- playing by now.
    if self.state == "silence" and loopMusic() and not self.ctx.allBanned then self:NextTrack() end
end

-- --------------------------------------------------------------------------
-- Events
-- --------------------------------------------------------------------------

FAME:RegisterEvent("ADDON_LOADED")
FAME:RegisterEvent("PLAYER_ENTERING_WORLD")
FAME:RegisterEvent("ZONE_CHANGED_NEW_AREA")
FAME:RegisterEvent("ZONE_CHANGED")
FAME:RegisterEvent("ZONE_CHANGED_INDOORS")
FAME:RegisterEvent("PLAYER_UPDATE_RESTING")
FAME:RegisterEvent("PLAYER_DEAD")
FAME:RegisterEvent("PLAYER_ALIVE")
FAME:RegisterEvent("PLAYER_UNGHOST")
-- A fade in progress has the player's music volume turned part way down.
-- These two make sure it always gets put back.
FAME:RegisterEvent("PLAYER_LEAVING_WORLD")
FAME:RegisterEvent("PLAYER_LOGOUT")
-- Any change to the music slider -- the player's, the Settings panel's,
-- another addon's -- gets checked straight away.  Guarded: an unknown event
-- name is an error, and this one is not documented for this client.
pcall(FAME.RegisterEvent, FAME, "CVAR_UPDATE")

FAME:SetScript("OnEvent", function(self, event, arg1)
    if event == "CVAR_UPDATE" then
        if type(arg1) == "string" and arg1:lower() == MUSIC_VOLUME:lower() then
            self:CheckVolume()
        end
    elseif event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ForeverAmbientMusicExtendedDB = ForeverAmbientMusicExtendedDB or {}
        for k, v in pairs(ForeverAmbientMusicExtendedDB) do
            if defaults[k] ~= nil then db[k] = v end
        end
        ns.db = db
    elseif event == "PLAYER_ENTERING_WORLD" then
        if self.silenceWorks == nil then
            -- Confirm the silent file is loadable before relying on it.  It is
            -- silent, so the probe is inaudible.
            self.silenceWorks = probe(SILENCE)
            if not self.silenceWorks then
                say("could not load Media/silence.mp3 -- silences will not be held, so the game may start its own music during them. Restart the client if the addon was just installed.")
            end
        end
        if self.userVolume == nil then
            -- The player's level from last session, if saved variables loaded
            -- back.  CheckVolume uses it to heal a slider left mid-fade by a
            -- quit or a crash; without it, FAME learns the level from the
            -- slider itself.
            local saved = ForeverAmbientMusicExtendedDB and tonumber(ForeverAmbientMusicExtendedDB.userVolume)
            if saved and not looksLikeOurs(saved) then self.userVolume = saved end
            self:RecoverGuard()
        end
        self:CheckVolume()
        -- Arriving is always a fresh start.
        self.ctx = nil
        self:Evaluate()
        if not self.poll then
            -- Catches what has no event: the sound options, Loop Music, a
            -- missed subzone change, a music volume left stuck by something.
            self.poll = C_Timer.NewTicker(10, function()
                FAME:CheckVolume()
                FAME:Evaluate()
            end)
        end
    elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
        self:CancelTimer()
        self:RestoreVolume()
    else
        self:Evaluate()
    end
end)

-- --------------------------------------------------------------------------
-- Slash commands
-- --------------------------------------------------------------------------

local function save(key, value)
    db[key] = value
    ForeverAmbientMusicExtendedDB = ForeverAmbientMusicExtendedDB or {}
    ForeverAmbientMusicExtendedDB[key] = value
end

-- Output.  Every command prints a one-line headline with the FAME prefix,
-- then detail rows with an aligned grey label.  Tracks are named by their
-- file name with the ID beside it, and lengths read as minutes:seconds.
local GREY, RED = "|cff9d9d9d", "|cffff8080"

local function row(label, text)
    print(("  %s%-9s|r %s"):format(GREY, label, text))
end

local function clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function trackName(track)
    return track.name or tostring(track.id or track.file)
end

-- "mus_80_drustvar_h (1780914)", or just the name for a local file.
local function describe(track)
    if track.id and track.name then return ("%s (%d)"):format(track.name, track.id) end
    return trackName(track)
end

local function pct(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end

local function onOff(v) return v and "on" or "off" end

local function silenceText(musicSet)
    local s = musicSet.silence
    local function span(lo, hi)
        if lo == hi then return clock(lo) end
        return clock(lo) .. "-" .. clock(hi)
    end
    if s[1] == s[3] and s[2] == s[4] then return span(s[1], s[2]) end
    return span(s[1], s[2]) .. " by day, " .. span(s[3], s[4]) .. " by night"
end

-- How a new place opens, as a phrase: "new places open with ...".
local function firstText()
    return db.displaceFirst and "may open with an extended track" or "open with the game's own track"
end

local commands = {}

commands.help = function()
    say("commands")
    local function cmd(c, what) print(("  %-25s %s"):format("/fame " .. c, what)) end
    cmd("status", "what's playing, and what comes next")
    cmd("skip", "end this track as it would end anyway")
    cmd("next", "play an extended track now")
    cmd("ban", "never play this track again")
    cmd("banlist", "banned tracks, and where")
    cmd("unban <id> | all", "allow banned tracks again")
    cmd("chance <0-100>", ("share of the game's own tracks (now %s)"):format(pct(db.originalChance)))
    cmd("first", ("let a new place open with an extended track (now %s)"):format(onOff(db.displaceFirst)))
    cmd("on | off | toggle", ("run FAME, or leave music to the game (now %s)"):format(onOff(db.enabled)))
    print("  " .. GREY .. "troubleshooting|r")
    cmd("where", "location, music set and volume details")
    cmd("pool [n]", "extended tracks that fit here")
    cmd("play <id>", "play a track by its file ID")
    cmd("scan <id> ...", "check file IDs exist in this client")
    cmd("debug", ("narrate every decision (now %s)"):format(onOff(db.debug)))
end

commands.on = function()
    save("enabled", true)
    say("on -- running the music")
    FAME:Evaluate()
end

commands.off = function()
    save("enabled", false)
    FAME:Release("off")
    say("off -- the game plays its own music")
end

commands.toggle = function()
    if db.enabled then commands.off() else commands.on() end
end

-- What you are hearing, and what comes next.
commands.status = function()
    local ctx = FAME.ctx
    say("%s", FAME:StateText())
    if FAME.playing then
        local track = FAME.playing
        row("track", describe(track))
        if track.tags then row("tags", table.concat(track.tags, " ")) end
        row("time", ("%s of %s"):format(clock(GetTime() - FAME.startedAt), clock(track.len)))
        if ctx then
            row("next", loopMusic() and "the next track straight after (Loop Music is on)"
                or ("the game's silence, %s"):format(silenceText(ctx.set)))
        end
    elseif FAME.state == "silence" and FAME.nextAt then
        row("next", ("a track in %s"):format(clock(FAME.nextAt - GetTime())))
    end
    if ctx then
        row("here", ctx.inn and ("%s (%s)"):format(ctx.inn, ctx.set.name) or ctx.set.name)
        row("pool", ("%d of the game's own, %d extended (%s)"):format(#FAME:OriginalChoices(ctx.set),
            #FAME:ExtendedChoices(ctx.prof), isNight() and "night" or "day"))
        row("mix", ("%s the game's own; new places %s"):format(pct(db.originalChance), firstText()))
    end
    if FAME.silenceWorks == false then
        row("warning", RED .. "the silent file did not load, so silences are not held|r")
    end
end

-- Where you are, and what FAME makes of it: for reporting a problem.
commands.where = function()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local minimap = GetMinimapZoneText and GetMinimapZoneText()
    say("where you are")
    row("map", ("%s %s%s"):format(tostring(mapID), tostring(GetZoneText()),
        (mapID and ns.zones[mapID]) and "" or (" " .. RED .. "(not in Zones.lua)|r")))
    local subzone = GetSubZoneText()
    if not subzone or subzone == "" then subzone = "none" end
    if minimap and minimap ~= "" and minimap ~= subzone and minimap ~= GetZoneText() then
        subzone = ("%s (minimap: %s)"):format(subzone, minimap)
    end
    row("subzone", subzone)
    if minimap and ns.inns[minimap] then
        row("inn", ("%s: %s tavern music only"):format(minimap, ns.inns[minimap]))
    end
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        row("instance", ("%s (%s, id %s)"):format(tostring(name), tostring(instanceType), tostring(instanceID)))
    end
    local ctx, why = resolveContext()
    if ctx then
        local intro = ctx.introID ~= 0 and ns.intros[ctx.introID]
        row("music", ("set %d %s, area %s%s"):format(ctx.setID, ctx.set.name, tostring(ctx.area),
            intro and (", intro " .. intro.name) or ""))
        row("silence", silenceText(ctx.set))
    else
        row("music", STATE[why] or why)
    end
    local hour, minute = GetGameTime()
    row("time", ("%02d:%02d server, %s; resting %s"):format(hour or 0, minute or 0,
        isNight() and "night" or "day", IsResting() and "yes" or "no"))
    local looping, loopCVar = loopMusic()
    row("loop", looping == nil and "Loop Music unreadable here, assuming off"
        or ("Loop Music %s (%s)"):format(onOff(looping), loopCVar))
    local vol, raw = readVolume(), readRaw()
    local note = FAME:Fading() and "mid-fade"
        or ((isOurs(vol) or looksLikeOurs(vol)) and (RED .. "left over from a fade|r"))
        or (FAME:Yielding() and "another addon is moving it; FAME is leaving it alone")
    row("volume", ("%s, your level %s%s%s"):format(tostring(raw), tostring(FAME.userVolume),
        note and ", " or "", note or ""))
    row("state", FAME:StateText())
end

commands.pool = function(rest)
    local limit = tonumber(rest) or 15
    local ctx = FAME.ctx
    if not ctx then return say("%s", FAME:StateText()) end
    local pool = FAME:ExtendedChoices(ctx.prof)
    say("%d extended tracks fit here (%s)%s", #pool, isNight() and "night" or "day",
        #pool > limit and (", first %d -- /fame pool %d for all"):format(limit, #pool) or "")
    for i = 1, math.min(limit, #pool) do
        local t = pool[i]
        print(("  %s%-8s %5s|r  %s  %s%s|r"):format(GREY, tostring(t.id or ""), clock(t.len),
            trackName(t), GREY, table.concat(t.tags, " ")))
    end
end

-- `skip` ends the track the way it would have ended anyway: into the
-- game's silence, or straight into the next one with Loop Music on.
commands.skip = function()
    if not FAME.playing then return say("nothing is playing to skip") end
    say("skipping %s", describe(FAME.playing))
    FAME:CancelTimer()
    FAME:AfterTrack(FADE_CUT)
end

commands.next = function()
    local ctx = FAME.ctx
    if not ctx then return say("%s", FAME:StateText()) end
    local track = FAME:Pick(ctx.prof)
    if not track then return say("no extended track fits here") end
    FAME:CancelTimer()
    say("playing %s, %s", describe(track), clock(track.len))
    FAME:FadeOut(0.8, function() FAME:PlayTrack(track, "extended") end, false)
end

commands.play = function(rest)
    local id = tonumber(rest)
    if not id then return say("usage: /fame play <file ID>") end
    local found
    for _, track in ipairs(ns.allTracks) do
        if track.id == id then found = track break end
    end
    if not found then
        for _, musicSet in pairs(ns.musicSets) do
            for _, list in ipairs({ musicSet.day, musicSet.night }) do
                for _, track in ipairs(list) do
                    if track.id == id then found = track end
                end
            end
        end
    end
    if found then
        say("playing %s, %s", describe(found), clock(found.len))
    else
        found = { id = id, len = 60 }
        say("playing %d for a minute -- it isn't one of FAME's tracks, so its length is unknown", id)
    end
    FAME:CancelTimer()
    FAME:FadeOut(0.4, function() FAME:PlayTrack(found, "test") end, false)
end

commands.scan = function(rest)
    if not rest or rest == "" then return say("usage: /fame scan <id> [id ...]") end
    local results, present = {}, 0
    for word in rest:gmatch("%d+") do
        local id = tonumber(word)
        local _, handle = PlaySoundFile(id, "Music")
        local found = handle and handle > 0
        if found then StopSound(handle, 0); present = present + 1 end
        results[#results + 1] = { id, found }
    end
    say("%d of %d in this client", present, #results)
    for _, r in ipairs(results) do
        print(("  %s%-8s|r %d"):format(r[2] and "|cff80ff80" or RED, r[2] and "present" or "absent", r[1]))
    end
end

local function persistBans()
    ForeverAmbientMusicExtendedDB = ForeverAmbientMusicExtendedDB or {}
    ForeverAmbientMusicExtendedDB.banned = db.banned
end

-- Ban whatever is playing -- the game's own track or an extended one -- and
-- end it the way it would have ended anyway.
commands.ban = function()
    local track = FAME.playing
    if not FAME.ctx then
        -- Dead, in an instance, at sea...: whatever is playing is the game's,
        -- and FAME does not choose it, so it cannot ban it.
        return say("the game chooses the music here, so there's nothing for FAME to ban")
    end
    if not track then return say("nothing is playing to ban") end
    local key = trackKey(track)
    local zone, sub = GetZoneText() or "?", GetSubZoneText() or ""
    local where = (sub ~= "" and sub ~= zone) and (zone .. ", " .. sub) or zone
    local kind = FAME.kind == "test" and "by request" or (FAME.kind or "?")
    db.banned[key] = { zone = where, kind = kind, name = track.name, at = time and time() or 0 }
    persistBans()
    say("banned %s -- /fame unban %s to undo", describe(track), tostring(key))
    FAME:CancelTimer()
    FAME:AfterTrack(FADE_CUT)
end

commands.banlist = function()
    local keys = {}
    for key in pairs(db.banned) do keys[#keys + 1] = key end
    if #keys == 0 then return say("nothing is banned") end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    say("%d banned -- /fame unban <id> or /fame unban all", #keys)
    for _, key in ipairs(keys) do
        local b = db.banned[key]
        print(("  %s%-8s|r %s  %s%s, %s|r"):format(GREY, tostring(key), b.name or "?",
            GREY, b.zone or "?", b.kind or "?"))
    end
end

commands.unban = function(rest)
    if not rest or rest == "" then
        return say("usage: /fame unban <id> or /fame unban all -- /fame banlist shows the ids")
    end
    if rest:lower() == "all" then
        local n = 0
        for k in pairs(db.banned) do db.banned[k] = nil; n = n + 1 end
        persistBans()
        say("unbanned all %d", n)
    else
        local key = tonumber(rest) or rest
        local b = db.banned[key]
        if not b then return say("%s is not banned -- /fame banlist shows what is", tostring(key)) end
        db.banned[key] = nil
        persistBans()
        say("unbanned %s", b.name and ("%s (%s)"):format(b.name, tostring(key)) or tostring(key))
    end
    -- If everything here had been banned, there is something to play again.
    if FAME.ctx and FAME.ctx.allBanned and FAME.state == "silence" then
        FAME:NextTrack()
    end
end

commands.chance = function(rest)
    local value = tonumber(rest)
    if not value or value < 0 or value > 100 then
        return say("%s of tracks are the game's own -- /fame chance <0-100> to change it",
            pct(db.originalChance))
    end
    save("originalChance", value / 100)
    say("%s of tracks will be the game's own", pct(db.originalChance))
end

commands.first = function()
    save("displaceFirst", not db.displaceFirst)
    say("new places now %s", firstText())
end

commands.debug = function()
    save("debug", not db.debug)
    say("debug %s", onOff(db.debug))
end

SLASH_FOREVERAMBIENTMUSICEXTENDED1 = "/fame"
SLASH_FOREVERAMBIENTMUSICEXTENDED2 = "/foreverambient"
SlashCmdList.FOREVERAMBIENTMUSICEXTENDED = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local fn = commands[cmd]
    if fn then return fn(rest) end
    if cmd ~= "" then say("no command \"%s\"", cmd) end
    commands.help()
end

-- --------------------------------------------------------------------------
-- Load
-- --------------------------------------------------------------------------

ns.localTracks = ns.localTracks or {}
ns.allTracks = {}
for _, track in ipairs(ns.builtinTracks) do ns.allTracks[#ns.allTracks + 1] = track end
for _, track in ipairs(ns.localTracks) do ns.allTracks[#ns.allTracks + 1] = track end
