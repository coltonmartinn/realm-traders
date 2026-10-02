-- How long does progression take? Simulates a reasonable player against the
-- real rules and market: gather the current goal's good (or whatever earns
-- most), craft when it helps, sell when the backpack is full, buy upgrades as
-- soon as they're affordable, rebirth when possible. Prints minutes to each
-- goal and to each rebirth.   luau sim/progression.luau
--
-- Timing assumptions (seconds): one gather = hold 0.4 + walk/aim ~1.2;
-- a node gives `charges` gathers then you walk to the next (~3s);
-- a trip to the market and back ~12s (fast travel makes it shorter).

local Goals = require("../src/shared/Goals")
local Goods = require("../src/shared/Goods")
local Rules = require("../src/shared/Rules")
local MarketState = require("../src/server/MarketState")
local Npc = require("../src/server/Npc")
local Upgrades = require("../src/shared/Upgrades")

local GATHER_SECONDS = 1.6
local NODE_WALK = 3
local CHARGES = { wood = 4, wheat = 3, stone = 4, iron = 3, gems = 3 }
local SELL_TRIP = 12

math.randomseed(1)
local market = MarketState.new(Goods)
local p = Rules.newProfile()
local t = 0
local nextTick = 1

local function advance(seconds: number)
	t += seconds
	while nextTick <= t do
		Npc.step(market)
		MarketState.tick(market)
		nextTick += 1
	end
end

local function bid(id: string): number
	return MarketState.snapshot(market)[id].bid
end

local function sellAll()
	advance(SELL_TRIP)
	for _, id in market.order do
		local owned = p.inventory[id]
		while owned and owned > 0 do
			local n = math.min(owned, MarketState.MAX_QTY)
			local v = MarketState.trade(market, p, id, "sell", n)
			if not v then
				break
			end
			Rules.recordSale(p, p, id, n, v)
			owned = p.inventory[id]
		end
	end
end

local function buyUpgrades()
	for _, u in Upgrades.list do
		local bought = true
		repeat
			bought = Rules.upgrade(p, u.id)
		until not bought
	end
end

-- What to gather now: the current goal's needs, else the best value per second.
local function pickGood(): string
	local goal = Rules.currentGoal(p)
	if goal then
		if goal.where == "forest" then return "wood" end
		if goal.where == "farm" then return "wheat" end
		if goal.where == "mine" and p.upgrades.gear >= 2 then return "iron" end
		if goal.where == "cave" and Rules.lockReason(p, p, 3, 1) == nil then return "gems" end
		if goal.where == "workshop" then
			if goal.text:find("Bread") then
				return if (p.inventory.wheat or 0) < 3 * ((p.inventory.wood or 0)) then "wheat" else "wood"
			end
			if p.upgrades.gear >= 2 then
				local iron, stone, wood = p.inventory.iron or 0, p.inventory.stone or 0, p.inventory.wood or 0
				if iron < 2 * math.max(stone, wood) then return "iron" end
				if stone <= wood then return "stone" end
				return "wood"
			end
		end
	end
	local best, bestValue = "wood", 0
	for _, g in Goods do
		if g.realm == "main" and g.raw and not g.tier and not g.legendary and Rules.lockReason(p, p, g.gearLevel, g.rebirths) == nil then
			local v = bid(g.id) / (GATHER_SECONDS + NODE_WALK / CHARGES[g.id])
			if v > bestValue then
				best, bestValue = g.id, v
			end
		end
	end
	return best
end

local helperAcc = 0
local reached: { string } = {}
local lastGoal = p.goal
local rebirthTimes: { number } = {}

while t < 6 * 3600 and #rebirthTimes < 3 do
	local id = pickGood()
	local gained = Rules.gather(p, p, id)
	if gained then
		local dt = GATHER_SECONDS + NODE_WALK / CHARGES[id]
		advance(dt)
		-- The Helper Bee gathers the same good alongside you
		helperAcc += dt * Rules.helperRate(p) / 60
		while helperAcc >= 1 do
			helperAcc -= 1
			Rules.gather(p, p, id)
		end
	end
	-- craft whatever can be crafted (crafted goods are worth more than parts)
	for _, r in { "jewelry", "tools", "bread" } do
		local n = Rules.craftable(p, r)
		if n > 0 then
			Rules.craft(p, r, n)
		end
	end
	if not gained or Rules.space(p) == 0 then
		sellAll()
		buyUpgrades()
	end
	Rules.advanceGoals(p)
	while lastGoal < p.goal do
		table.insert(reached, string.format("%5.1f min  goal %2d done: %s", t / 60, lastGoal, Goals.main[lastGoal].text))
		lastGoal += 1
	end
	if Rules.rebirthBlock(p) == nil and p.upgrades.gear >= 4 then
		Rules.rebirth(p)
		table.insert(rebirthTimes, t)
		table.insert(reached, string.format("%5.1f min  REBIRTH %d (sell bonus now +%d%%)", t / 60, p.rebirths, (Rules.saleMultiplier(p) - 1) * 100))
	end
end

for _, line in reached do
	print(line)
end
print(string.format("\nAfter %.0f min: cash $%d, earned $%d, gear %d, backpack %d, rebirths %d",
	t / 60, p.cash, p.stats.earned, p.upgrades.gear, p.upgrades.backpack, p.rebirths))
