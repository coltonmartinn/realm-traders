-- Deep Mine income vs gathering on the surface, through the real market
-- (prices fall as you sell and recover over time).
-- From the repo root:  luau sim/mine_income.luau
--
-- A "round" is 30 swings: 10 veins x 3 charges. In the mine every swing
-- rolls a random ore with the level's odds (Rules.rollOre); on the surface a
-- swing gives your gear level of one good. Mining holds are 0.8s vs 0.4s, so
-- mining should pay roughly 2x per swing to be worth the trip, not 10x.

local Goods = require("../src/shared/Goods")
local Rules = require("../src/shared/Rules")
local MarketState = require("../src/server/MarketState")

local SWINGS = 30
local ROUNDS = 24 -- with 25 market ticks between rounds

-- Sells everything in `bag` (good -> units), 100 at a time. Returns the cash.
local function sellAll(m: any, bag: { [string]: number }): number
	local paid = 0
	for id, units in bag do
		local w = { cash = 0, inventory = { [id] = units } }
		while units > 0 do
			local qty = math.min(units, 100)
			paid += MarketState.trade(m, w, id, "sell", qty) or 0
			units -= qty
		end
	end
	return paid
end

local function run(fill: (bag: { [string]: number }) -> ()): (number, number)
	local m = MarketState.new(Goods)
	local first, total = 0, 0
	for round = 1, ROUNDS do
		local bag = {}
		fill(bag)
		local paid = sellAll(m, bag)
		if round == 1 then
			first = paid
		end
		total += paid
		for _ = 1, 25 do
			MarketState.tick(m)
		end
	end
	return first, total
end

math.randomseed(1)
print("source               per swing   24 rounds   (best find in 24 rounds)")
for depth = 1, Rules.MINE_DEPTHS do
	local best = Rules.oreAt("main", 1) :: any
	local first, total = run(function(bag)
		for _ = 1, SWINGS do
			local ore = Rules.rollOre("main", depth, math.random())
			bag[ore.id] = (bag[ore.id] or 0) + 1
			if ore.basePrice > best.basePrice then
				best = ore
			end
		end
	end)
	print(string.format("mine level %d (gear %d)  $%7.0f   $%9d   %s", depth, depth, first / SWINGS, total, best.name))
end
for _, row in { { "stone", 1 }, { "iron", 3 }, { "gems", 3 }, { "gems", 5 } } do
	local id, gear = row[1] :: string, row[2] :: number
	local first, total = run(function(bag)
		bag[id] = SWINGS * gear
	end)
	print(string.format("%-6s at gear %d       $%7.0f   $%9d", id, gear, first / SWINGS, total))
end
