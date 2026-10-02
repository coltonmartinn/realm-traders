--!strict
-- Session locking for saved profiles (the idea behind ProfileService).
-- A saved record is { data = <profile>, lock = { job, at }? }. A server only
-- loads a profile it can lock, and only writes while it still holds the lock,
-- so two servers can never overwrite each other's progress (e.g. when a
-- player hops servers before the old one finished saving).
-- Pure functions over the stored value; no Roblox APIs (tested offline).

export type Lock = { job: string, at: number }
export type Record = { data: any, lock: Lock? }

local SessionLock = {}

-- A lock older than this is from a server that died without releasing it.
SessionLock.TTL = 300

-- The profile inside a stored value (old saves are the bare profile).
function SessionLock.unwrap(stored: any): any
	if type(stored) == "table" and stored.data ~= nil then
		return stored.data
	end
	return stored
end

local function lockOf(stored: any): Lock?
	if type(stored) == "table" and type(stored.lock) == "table" and type(stored.lock.job) == "string" and type(stored.lock.at) == "number" then
		return stored.lock
	end
	return nil
end

-- Try to take the lock for `job` at time `now`. Returns the record to store,
-- or nil plus "locked" if another live server holds it.
function SessionLock.claim(stored: any, job: string, now: number): (Record?, string?)
	local lock = lockOf(stored)
	if lock and lock.job ~= job and now - lock.at < SessionLock.TTL then
		return nil, "locked"
	end
	return { data = SessionLock.unwrap(stored), lock = { job = job, at = now } }, nil
end

-- Write `data` if `job` still holds the lock. `release` drops the lock (the
-- player left). Returns nil when the lock was lost (don't overwrite).
function SessionLock.write(stored: any, job: string, now: number, data: any, release: boolean): Record?
	local lock = lockOf(stored)
	if not lock or lock.job ~= job then
		return nil
	end
	return { data = data, lock = if release then nil else { job = job, at = now } }
end

return SessionLock
