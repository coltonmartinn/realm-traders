-- Session lock tests. From the repo root:  luau tests/lock.test.luau

local SessionLock = require("../src/server/SessionLock")

local failures = 0
local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
		print("FAIL: " .. name)
	end
end

local profile = { cash = 500 }

-- First ever load
local rec = SessionLock.claim(nil, "A", 1000)
check("claim empty slot", rec ~= nil and rec.lock.job == "A" and rec.data == nil)

-- Old save without a wrapper
rec = SessionLock.claim(profile, "A", 1000)
check("claim bare old save keeps data", rec ~= nil and rec.data == profile)
check("unwrap old save", SessionLock.unwrap(profile) == profile)

-- Another live server holds it
local held = { data = profile, lock = { job = "B", at = 1000 } }
local none, why = SessionLock.claim(held, "A", 1100)
check("can't claim a fresh lock", none == nil and why == "locked")

-- Same server reclaiming is fine
check("same job can reclaim", SessionLock.claim(held, "B", 1100) ~= nil)

-- Dead server: lock expired
check("expired lock can be taken", SessionLock.claim(held, "A", 1000 + SessionLock.TTL + 1) ~= nil)

-- Writes
local mine = { data = profile, lock = { job = "A", at = 1000 } }
local newData = { cash = 900 }
local w = SessionLock.write(mine, "A", 1060, newData, false)
check("owner can write and refresh lock", w ~= nil and w.data == newData and w.lock.at == 1060)
w = SessionLock.write(mine, "A", 1070, newData, true)
check("release drops the lock", w ~= nil and w.lock == nil)
check("non-owner can't write", SessionLock.write(held, "A", 1100, newData, false) == nil)
check("can't write unlocked record", SessionLock.write({ data = profile }, "A", 1100, newData, false) == nil)

-- Hop: server A releases, server B claims, then A's late save must be refused
local afterRelease = SessionLock.write(mine, "A", 1100, newData, true)
local claimedByB = SessionLock.claim(afterRelease, "B", 1101)
check("B claims after release", claimedByB ~= nil and (claimedByB :: any).data == newData)
check("A's late write is refused", SessionLock.write(claimedByB, "A", 1102, { cash = 1 }, true) == nil)

if failures > 0 then
	error(`{failures} lock test(s) failed`)
end
print("All lock tests passed")
