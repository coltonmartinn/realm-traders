--!strict
-- Loads, holds and saves each player's profile. Profiles are saved with
-- UpdateAsync on leave, on shutdown and every AUTOSAVE_SECONDS, under a
-- session lock (see SessionLock) so two servers can't overwrite each other.
-- If a load fails (outage, or Studio without API access) the player still
-- plays on a fresh profile, but it is never saved, so it can't overwrite a
-- real save.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Rules)
local SessionLock = require(script.Parent.SessionLock)

local STORE_NAME = "MarketSim_v1"
local RETRIES = 3
local LOCK_ATTEMPTS = 8 -- x LOCK_WAIT seconds: time for the last server to finish saving
local LOCK_WAIT = 2

-- Identifies this server in session locks (JobId is empty in Studio)
local JOB = if game.JobId ~= "" then game.JobId else "studio-" .. game:GetService("HttpService"):GenerateGUID(false)

local PlayerData = {}

local profiles: { [Player]: Rules.Profile } = {}
local savable: { [Player]: boolean } = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStore unavailable, progress won't be saved:", result)
	end
end

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T?)
	for attempt = 1, RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[PlayerData] {label} failed (attempt {attempt}/{RETRIES}):`, result)
		local message = tostring(result)
		if message:find("Studio access to APIs is not allowed", 1, true) or message:find("API access is not enabled", 1, true) then
			break -- retrying can't help; enable API access in Game Settings > Security
		end
		if attempt < RETRIES then
			task.wait(attempt)
		end
	end
	return false, nil
end

-- Returns the profile, whether it will be saved, and why not ("offline":
-- DataStores unreachable; "locked": another server still has it).
function PlayerData.load(player: Player): (Rules.Profile, boolean, string?)
	local loaded: any = nil
	local ok, reason = false, "offline"
	if store then
		local s = store
		for _ = 1, LOCK_ATTEMPTS do
			local locked = false
			local reached = withRetries("load " .. player.Name, function()
				s:UpdateAsync(key(player), function(old)
					local record = SessionLock.claim(old, JOB, os.time())
					if not record then
						locked = true
						return nil -- leave it alone; the other server is still saving
					end
					locked = false
					loaded = record.data
					return record
				end)
				return true
			end)
			if not reached then
				break
			end
			if not locked then
				ok, reason = true, nil
				break
			end
			reason = "locked"
			task.wait(LOCK_WAIT)
			if player.Parent == nil then
				break
			end
		end
	end
	local profile = Rules.reconcile(if ok then loaded else nil)
	profiles[player] = profile
	savable[player] = ok
	return profile, ok, reason
end

function PlayerData.get(player: Player): Rules.Profile?
	return profiles[player]
end

-- Saves while we still hold the lock; `release` lets the next server in.
-- Returns whether the profile is now safely stored.
function PlayerData.save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not (store and profile and savable[player]) then
		return false
	end
	local s = store
	local lost = false
	local ok = withRetries("save " .. player.Name, function()
		s:UpdateAsync(key(player), function(old)
			local record = SessionLock.write(old, JOB, os.time(), profile, release == true)
			lost = record == nil
			return record
		end)
		return true
	end)
	if lost then
		-- Another server took over this profile; never overwrite it again
		savable[player] = false
		warn(`[PlayerData] lost the session lock for {player.Name}; not saving`)
	end
	return ok and not lost
end

-- Whether this player's progress is being saved at all (false in Studio
-- without API access, or when the data store couldn't be reached on join).
function PlayerData.isSaving(player: Player): boolean
	return store ~= nil and savable[player] == true
end

function PlayerData.unload(player: Player)
	PlayerData.save(player, true)
	profiles[player] = nil
	savable[player] = nil
end

function PlayerData.saveAll()
	local threads = {}
	for player in profiles do
		table.insert(threads, task.spawn(PlayerData.save, player, true))
	end
	-- Wait for every save to finish (BindToClose gives us ~30 seconds).
	for _, thread in threads do
		while coroutine.status(thread) ~= "dead" do
			task.wait()
		end
	end
end

return PlayerData
