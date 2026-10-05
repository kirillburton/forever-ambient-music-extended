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
    -- Probe built-in fileDataIDs at runtime as well as local files (see
    -- FAME:Playable).  Off by default: the built-in list was already checked
    -- against this client's own file list when Tracks.lua was generated.
    verifyBuiltin = false,
    debug = false,
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

local function innSetFor(prof)
    local key = prof.inn
    if not key then
        key = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "horde" or "alliance"
    end
    return ns.tavernSets[key]
end

-- The music context for where the player stands, or nil plus the reason
-- FAME should stay out of it.  `key` identifies the music the game would be
-- playing: two places with the same key sound the same, so moving between
-- them does not restart anything -- exactly as the game behaves.
local function resolveContext()
    if not db.enabled then return nil, "off" end
    if not soundAvailable() then return nil, "muted" end
    if IsInInstance() then return nil, "instance" end

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local zm = mapID and ns.zoneMusic[mapID]
    local prof = mapID and ns.zones[mapID]
    if not (zm and prof) then return nil, "unmapped" end

    local ctx = { mapID = mapID, prof = prof, setID = zm.set, area = zm.area, introID = zm.intro }
    local sub = subzoneEntry(mapID, GetSubZoneText())
    if sub then
        ctx.area, ctx.introID = sub.area, sub.intro
        if sub.set ~= 0 then ctx.setID = sub.set end
        -- A town inside the zone -- Ratchet in the Barrens -- draws its
        -- extended tracks from its own profile.
        if prof.towns and prof.towns[sub.area] then ctx.prof = prof.towns[sub.area] end
    end

    if IsResting() and prof.resting then
        ctx.setID = innSetFor(prof) or ctx.setID
        ctx.prof = prof.resting
        ctx.area = "inn:" .. tostring(ctx.area)
        ctx.introID = 0
        ctx.key = "inn:" .. ctx.setID
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
-- Local files always get this check, because nothing verified them offline.
-- Built-in fileDataIDs skip it unless asked: Tracks.lua was generated from
-- this client's own file list, so they are already known to be present.
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
    if track.id and not db.verifyBuiltin then return true end
    local cached = playableCache[key]
    if cached ~= nil then return cached end
    local ok = probe(key)
    playableCache[key] = ok
    if not ok then debugf("not in client, dropping: %s", tostring(key)) end
    return ok
end

-- An extended track for this profile, never the one just played.
function FAME:Pick(prof)
    local pool = self:Pool(prof)
    if #pool == 0 then return nil end
    for _ = 1, 15 do
        local track = pool[math.random(#pool)]
        if track ~= self.previous and self:Playable(track) then return track end
    end
    return nil
end

-- One of the game's own tracks for this music set, the way the game picks:
-- the night list after dark when the set has one.
function FAME:PickOriginal(musicSet)
    local list = isNight() and musicSet.night or musicSet.day
    if not list or #list == 0 then list = musicSet.day or musicSet.night end
    if not list or #list == 0 then return nil end
    for _ = 1, 10 do
        local track = list[math.random(#list)]
        if track.id ~= (self.previous and self.previous.id) or #list == 1 then return track end
    end
    return list[math.random(#list)]
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

function FAME:StopRamps()
    if self.rampTicker then self.rampTicker:Cancel(); self.rampTicker = nil end
    if self.restoreTimer then self.restoreTimer:Cancel(); self.restoreTimer = nil end
end

function FAME:RestoreVolume()
    self:StopRamps()
    if self.savedVolume then
        cvarSet("Sound_MusicVolume", self.savedVolume)
        self.savedVolume = nil
    end
end

-- Hold the volume down through the client's crossfade, then bring it back
-- up gently to the player's own level.
function FAME:FadeBackIn()
    self:StopRamps()
    local target = self.savedVolume
    if not target then return end
    self.restoreTimer = C_Timer.NewTimer(SWAP_HOLD, function()
        FAME.restoreTimer = nil
        local step = 0
        FAME.rampTicker = C_Timer.NewTicker(FADE_IN / FADE_STEPS, function()
            step = step + 1
            if step >= FADE_STEPS then
                FAME.rampTicker = nil
                FAME:RestoreVolume()
            else
                cvarSet("Sound_MusicVolume", target * step / FADE_STEPS)
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
-- the player's original level as the one to return to.  Starting over from
-- the saved level would jump the volume up first.
function FAME:RampDown(seconds, andThen, quietAfter)
    self:StopRamps()
    local current = tonumber(cvarGet("Sound_MusicVolume"))
    self.savedVolume = self.savedVolume or current
    if not current or not self.savedVolume or self.savedVolume <= 0 or seconds <= 0 then
        andThen()
        self:RestoreVolume()
        return
    end
    local step = 0
    self.rampTicker = C_Timer.NewTicker(seconds / FADE_STEPS, function()
        step = step + 1
        cvarSet("Sound_MusicVolume", current * math.max(0, 1 - step / FADE_STEPS))
        if step < FADE_STEPS then return end
        FAME.rampTicker = nil
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

-- Fade out whatever of ours is audible, then run `andThen`.  Silence we are
-- holding has nothing to fade, so that case runs straight through.
function FAME:FadeOut(seconds, andThen, quietAfter)
    if self.playing then
        self.previous = self.playing
        self.playing, self.kind = nil, nil
        self:RampDown(seconds, andThen, quietAfter)
    else
        self:RestoreVolume()
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
    self.holding = false
    self.playing, self.kind = track, kind
    self.startedAt = GetTime()
    self:SetState(kind)
    debugf("%s %s, %ds%s", kind, tostring(track.id or track.file), track.len,
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
    self.holding = true
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
    local original
    if ctx.first and not db.displaceFirst then
        original = true
    else
        original = math.random() < db.originalChance
    end
    ctx.first = false

    local track, kind
    if not original then
        track, kind = self:Pick(ctx.prof), "extended"
    end
    if not track then
        track, kind = self:PickOriginal(ctx.set), "original"
    end
    if not track then return self:HoldSilence(silenceFor(ctx.set)) end
    self:PlayTrack(track, kind)
end

-- Intros play on arriving in their area, at most once per cooldown -- the
-- game's MinDelayMinutes, kept in Originals.lua.
local introPlayedAt = {}

function FAME:DueIntro(ctx)
    local intro = ctx.introID ~= 0 and ns.intros[ctx.introID]
    if not intro or #intro.tracks == 0 then return nil end
    local last = introPlayedAt[ctx.introID]
    if last and GetTime() - last < intro.delay then return nil end
    return intro, ctx.introID
end

function FAME:PlayIntro(intro, introID)
    introPlayedAt[introID] = GetTime()
    if self.ctx then self.ctx.first = false end   -- the intro is the game's own
    self:PlayTrack(intro.tracks[math.random(#intro.tracks)], "intro")
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

-- Hand the music channel back to the game.
function FAME:Release(state)
    self:CancelTimer()
    self.ctx, self.area = nil, nil
    local wasOurs = self.playing or self.holding
    self.holding = false
    if wasOurs then
        self:FadeOut(FADE_CUT, function() StopMusic() end, false)
    else
        self:RestoreVolume()
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
    if self.state == "silence" and loopMusic() then self:NextTrack() end
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
-- A fade in progress has the player's music volume turned part way down.
-- These two make sure it always gets put back.
FAME:RegisterEvent("PLAYER_LEAVING_WORLD")
FAME:RegisterEvent("PLAYER_LOGOUT")

FAME:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
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
        -- Arriving is always a fresh start.
        self.ctx = nil
        self:Evaluate()
        if not self.poll then
            -- Catches what has no event: the sound options, Loop Music, a
            -- missed subzone change.
            self.poll = C_Timer.NewTicker(10, function() FAME:Evaluate() end)
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

local function trackName(track)
    return tostring(track.id or track.file)
end

local function describe(track)
    if track.tags then
        return ("%s [%s], %ds"):format(trackName(track), table.concat(track.tags, " "), track.len)
    end
    return ("%s, %ds"):format(trackName(track), track.len)
end

local commands = {}

commands.help = function()
    say("commands:")
    local rows = {
        { "on | off | toggle", "run the music schedule, or leave it to the game" },
        { "status", "what is playing, and what comes next" },
        { "skip", "end this track the way it would end anyway" },
        { "next", "end this track and play an extended one now" },
        { "where", "uiMapID, subzone, music set, silences, loop music" },
        { "pool [n]", "list extended tracks eligible here" },
        { "play <fileDataID>", "play one track now, for testing" },
        { "scan <id> [id ...]", "report which fileDataIDs this client has" },
        { "chance <0-100>", "percent of tracks kept as the game's own" },
        { "first", "toggle: may the first track in a new place be extended" },
        { "verify", "also probe built-in tracks for presence" },
        { "debug", "toggle verbose output" },
    }
    for _, row in ipairs(rows) do
        print(("  %-25s %s"):format("/fame " .. row[1], row[2]))
    end
end

commands.on = function()
    save("enabled", true)
    say("on")
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

commands.status = function()
    local ctx = FAME.ctx
    say("%s", FAME:StateText())
    if FAME.playing then
        local left = FAME.playing.len - (GetTime() - FAME.startedAt)
        print(("  track: %s -- %ds left"):format(describe(FAME.playing), math.max(0, math.floor(left))))
    elseif FAME.state == "silence" and FAME.nextAt then
        print(("  next track in %ds"):format(math.max(0, math.floor(FAME.nextAt - GetTime()))))
    end
    if FAME:Fading() then print("  (fading)") end
    if ctx then
        local s = ctx.set.silence
        local looping = loopMusic()
        print(("  music here: %s -- silences %d-%ds by day, %d-%ds by night%s"):format(
            ctx.set.name, s[1], s[2], s[3], s[4], looping and " (skipped: Loop Music is on)" or ""))
        print(("  extended pool here: %d (%s)"):format(#FAME:Pool(ctx.prof), isNight() and "night" or "day"))
        print(("  mix: %d%% the game's own, first track in a new place %s"):format(
            math.floor(db.originalChance * 100 + 0.5),
            db.displaceFirst and "may be extended" or "always the game's own"))
    end
    if FAME.silenceWorks == false then
        print("  |cffff8080silent file did not load: silences are not held|r")
    end
end

-- `skip` ends the track the way it would have ended anyway: into the
-- game's silence, or straight into the next one with Loop Music on.
commands.skip = function()
    if not FAME.playing then
        return say("nothing is playing to skip")
    end
    say("skipping %s", trackName(FAME.playing))
    FAME:CancelTimer()
    FAME:AfterTrack(FADE_CUT)
end

commands.next = function()
    local ctx = FAME.ctx
    if not ctx then return say("not running here: %s", FAME:StateText()) end
    local track = FAME:Pick(ctx.prof)
    if not track then return say("no extended track fits here") end
    FAME:CancelTimer()
    say("%s", describe(track))
    FAME:FadeOut(0.8, function() FAME:PlayTrack(track, "extended") end, false)
end

commands.play = function(rest)
    local id = tonumber(rest)
    if not id then return say("usage: /fame play <fileDataID>") end
    local found
    for _, track in ipairs(ns.allTracks) do
        if track.id == id then found = track break end
    end
    if found then
        say("%s", describe(found))
    else
        found = { id = id, len = 60 }
        say("%d is not in Tracks.lua; playing it raw for 60s", id)
    end
    FAME:CancelTimer()
    FAME:FadeOut(0.4, function() FAME:PlayTrack(found, "test") end, false)
end

commands.where = function()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local hour, minute = GetGameTime()
    say("location")
    print(("  uiMapID: %s%s"):format(tostring(mapID),
        (mapID and ns.zones[mapID]) and "" or "  |cffff8080(no Zones.lua entry)|r"))
    print(("  zone: %s / subzone: %s"):format(tostring(GetZoneText()), tostring(GetSubZoneText())))
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        print(("  instance: %s (type %s, instanceID %s)"):format(
            tostring(name), tostring(instanceType), tostring(instanceID)))
    end
    print(("  resting: %s / server time %02d:%02d -> %s"):format(
        tostring(IsResting()), hour or 0, minute or 0, isNight() and "night" or "day"))
    local ctx, why = resolveContext()
    if ctx then
        local s = ctx.set.silence
        print(("  music set: %d %s -- silences %d-%ds day, %d-%ds night"):format(
            ctx.setID, ctx.set.name, s[1], s[2], s[3], s[4]))
        print(("  area: %s%s"):format(tostring(ctx.area),
            ctx.introID ~= 0 and (", intro " .. tostring(ns.intros[ctx.introID] and ns.intros[ctx.introID].name)) or ""))
    else
        print(("  music set: none -- %s"):format(STATE[why] or why))
    end
    local looping, loopCVar = loopMusic()
    if looping == nil then
        print("  loop music: could not read it -- assuming off (the CVar name differs on this client)")
    else
        print(("  loop music: %s (%s)"):format(tostring(looping), loopCVar))
    end
    print(("  music volume: %s"):format(tostring(cvarGet("Sound_MusicVolume"))))
    print(("  state: %s"):format(FAME:StateText()))
end

commands.pool = function(rest)
    local limit = tonumber(rest) or 15
    local ctx = FAME.ctx
    if not ctx then return say("not running here: %s", FAME:StateText()) end
    local pool = FAME:Pool(ctx.prof)
    say("%d extended tracks eligible (%s); showing up to %d",
        #pool, isNight() and "night" or "day", limit)
    for i = 1, math.min(limit, #pool) do
        print(("  %s  %4ds  %s"):format(trackName(pool[i]), pool[i].len,
            table.concat(pool[i].tags, " ")))
    end
end

commands.scan = function(rest)
    if not rest or rest == "" then
        return say("usage: /fame scan 53492 53493 ...")
    end
    local hits, misses = 0, 0
    for word in rest:gmatch("[%d]+") do
        local id = tonumber(word)
        local willPlay, handle = PlaySoundFile(id, "Music")
        if handle and handle > 0 then
            StopSound(handle, 0)
            hits = hits + 1
            print(("  |cff80ff80HIT |r %d"):format(id))
        else
            misses = misses + 1
            print(("  |cffff8080MISS|r %d (willPlay=%s handle=%s)"):format(
                id, tostring(willPlay), tostring(handle)))
        end
    end
    say("%d present, %d absent", hits, misses)
end

commands.chance = function(rest)
    local pct = tonumber(rest)
    if not pct or pct < 0 or pct > 100 then
        return say("usage: /fame chance <0-100>  (currently %d%% of tracks are the game's own)",
            math.floor(db.originalChance * 100 + 0.5))
    end
    save("originalChance", pct / 100)
    say("%d%% of tracks will be the game's own", pct)
end

commands.first = function()
    save("displaceFirst", not db.displaceFirst)
    say("first track in a new place: %s",
        db.displaceFirst and "may be extended" or "always the game's own")
end

commands.verify = function()
    save("verifyBuiltin", not db.verifyBuiltin)
    say("runtime presence probe for built-in tracks %s (local files are always probed)",
        db.verifyBuiltin and "on" or "off")
end

commands.debug = function()
    save("debug", not db.debug)
    say("debug %s", db.debug and "on" or "off")
end

SLASH_FOREVERAMBIENTMUSICEXTENDED1 = "/fame"
SLASH_FOREVERAMBIENTMUSICEXTENDED2 = "/foreverambient"
SlashCmdList.FOREVERAMBIENTMUSICEXTENDED = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[(cmd or ""):lower()]
    if fn then fn(rest) else commands.help() end
end

-- --------------------------------------------------------------------------
-- Load
-- --------------------------------------------------------------------------

ns.localTracks = ns.localTracks or {}
ns.allTracks = {}
for _, track in ipairs(ns.builtinTracks) do ns.allTracks[#ns.allTracks + 1] = track end
for _, track in ipairs(ns.localTracks) do ns.allTracks[#ns.allTracks + 1] = track end
