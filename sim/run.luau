-- Offline economy simulation. Runs the real PriceModel / MarketState / Npc
-- modules outside Studio. From the repo root:  luau sim/run.luau
--
-- 1. Baseline: NPCs + 8 fake players (gather-and-sell, random buys) for many ticks.
-- 2. Shock recovery: push stock far from target, check the price returns
--    without overshooting or oscillating.
-- 3. Free money: round-trip strategies (buy/sell, wait, reverse) must not profit.
--    Includes a naive-pricing control to show the check can catch a loop.
-- 4. Elasticity comparison.

local Goods = require("../src/shared/Goods")
local PriceModel = require("../src/server/PriceModel")
local MarketState = require("../src/server/MarketState")
local Npc = require("../src/server/Npc")

local TICKS = 20000
local RAW = {}
local BASE = {}
for _, g in Goods do
	BASE[g.id] = g.basePrice
	if g.raw then
		table.insert(RAW, g.id)
	end
end

local function params(overrides: { [string]: number }?)
	local p = table.clone(PriceModel.defaults)
	for k, v in overrides or {} do
		(p :: any)[k] = v
	end
	return p
end

local function mean(xs, from: number?, to: number?)
	local a, b, s = from or 1, to or #xs, 0
	for i = a, b do
		s += xs[i]
	end
	return s / (b - a + 1)
end

local function sd(xs)
	local m, s = mean(xs), 0
	for _, x in xs do
		s += (x - m) ^ 2
	end
	return math.sqrt(s / (#xs - 1))
end

local function logReturns(prices)
	local r = {}
	for i = 2, #prices do
		table.insert(r, math.log(prices[i] / prices[i - 1]))
	end
	return r
end

-- Lag-1 autocorrelation. Strongly negative = prices zig-zag (oscillation).
local function autocorr1(xs)
	local m, num, den = mean(xs), 0, 0
	for i = 1, #xs do
		den += (xs[i] - m) ^ 2
		if i > 1 then
			num += (xs[i] - m) * (xs[i - 1] - m)
		end
	end
	return if den > 0 then num / den else 0
end

local function tickMarket(m, n, npcs)
	for _ = 1, n do
		if npcs then
			Npc.step(m)
		end
		MarketState.tick(m)
	end
end

---------------------------------------------------------------------------
-- 1. Baseline
---------------------------------------------------------------------------

local function runBaseline(p, seed)
	math.randomseed(seed)
	local m = MarketState.new(Goods, p)
	local players = {}
	for i = 1, 8 do
		players[i] = { cash = 1000, inventory = {} }
	end
	local prices, trades = {}, 0
	for _, id in m.order do
		prices[id] = {}
	end

	for _ = 1, TICKS do
		trades += #Npc.step(m)
		for _, pl in players do
			if math.random() < 0.2 then -- gathered a few raw goods, sell them
				local id = RAW[math.random(#RAW)]
				local n = math.random(1, 3)
				pl.inventory[id] = (pl.inventory[id] or 0) + n
				if MarketState.trade(m, pl, id, "sell", n) then
					trades += 1
				end
			end
			if math.random() < 0.2 then
				local id = m.order[math.random(#m.order)]
				if MarketState.trade(m, pl, id, "buy", math.random(1, 3)) then
					trades += 1
				end
			end
		end
		MarketState.tick(m)
		for id, e in m.entries do
			assert(e.stock >= 0, "negative stock")
			assert(e.price == e.price and e.price > 0, "bad price")
			table.insert(prices[id], e.price)
		end
	end
	return prices, trades
end

local function stats(id, series)
	local base = BASE[id]
	local r = logReturns(series)
	local half = #series // 2
	local lo, hi = math.huge, -math.huge
	for _, x in series do
		lo, hi = math.min(lo, x), math.max(hi, x)
	end
	return {
		meanRatio = mean(series) / base,
		lo = lo / base,
		hi = hi / base,
		vol = sd(r) * 100,
		ac1 = autocorr1(r),
		trend = mean(series, half + 1) / mean(series, 1, half),
	}
end

local function printBaseline(title, p)
	local prices, trades = runBaseline(p, 42)
	print(string.format("\n== %s (%d ticks, %d trades) ==", title, TICKS, trades))
	print("good    mean/base  min/base  max/base  vol%/tick  ret-ac1  2nd/1st half")
	for _, id in Goods do
		local s = stats(id.id, prices[id.id])
		print(
			string.format(
				"%-7s %9.2f %9.2f %9.2f %10.3f %8.2f %13.3f",
				id.id,
				s.meanRatio,
				s.lo,
				s.hi,
				s.vol,
				s.ac1,
				s.trend
			)
		)
	end
end

---------------------------------------------------------------------------
-- 2. Shock recovery (no noise)
---------------------------------------------------------------------------

local function shock(good, startStock, p)
	local m = MarketState.new({ good }, p)
	local e = m.entries[good.id]
	e.stock = startStock
	e.price = PriceModel.spotPrice(good, startStock, p)
	local startSide = math.sign(e.price - good.basePrice)
	local settledAt, reversals, overshoot, lastDelta = nil, 0, 0, 0
	for t = 1, 5000 do
		local before = e.price
		MarketState.tick(m)
		local d = e.price - before
		if d * lastDelta < 0 then
			reversals += 1
		end
		if d ~= 0 then
			lastDelta = d
		end
		if math.sign(e.price - good.basePrice) == -startSide then
			overshoot = math.max(overshoot, math.abs(e.price - good.basePrice) / good.basePrice)
		end
		if not settledAt and math.abs(e.price - good.basePrice) / good.basePrice < 0.01 then
			settledAt = t
		end
	end
	return settledAt, reversals, overshoot
end

local function printShocks(p)
	print("\n== Shock recovery (no noise): ticks to within 1% of base ==")
	print("good    stock=10%  reversals  overshoot | stock=300%  reversals  overshoot")
	for _, g in Goods do
		local t1, r1, o1 = shock(g, math.floor(g.targetStock * 0.1), p)
		local t2, r2, o2 = shock(g, g.targetStock * 3, p)
		print(
			string.format(
				"%-7s %9s %10d %9.2f%% | %10s %10d %9.2f%%",
				g.id,
				tostring(t1),
				r1,
				o1 * 100,
				tostring(t2),
				r2,
				o2 * 100
			)
		)
	end
end

---------------------------------------------------------------------------
-- 3. Free money loops
---------------------------------------------------------------------------

-- Control: executes at the smoothed displayed price, ignoring spot.
-- This is the obvious-but-wrong design; the check should flag it.
local function naiveTrade(m, w, id, side, qty)
	local e, p = m.entries[id], m.params
	if side == "buy" then
		if qty > e.stock then
			return nil
		end
		local cost = math.ceil(e.price * qty * (1 + p.spread))
		if w.cash < cost then
			return nil
		end
		w.cash -= cost
		w.inventory[id] = (w.inventory[id] or 0) + qty
		e.stock -= qty
		return cost
	else
		if (w.inventory[id] or 0) < qty then
			return nil
		end
		local value = math.floor(e.price * qty * (1 - p.spread))
		w.cash += value
		w.inventory[id] -= qty
		e.stock += qty
		return value
	end
end

-- Repeats: first trade, wait `wait` ticks, reverse trade, let market settle.
-- Profit = change in cash + inventory valued at basePrice.
local function roundTrip(trade, p, id, first, qty, wait, cycles, npcs)
	local m = MarketState.new(Goods, p)
	local w = { cash = 1e7, inventory = { [id] = 1000 } }
	local worth = function()
		return w.cash + (w.inventory[id] or 0) * BASE[id]
	end
	local start = worth()
	local second = if first == "buy" then "sell" else "buy"
	for _ = 1, cycles do
		if trade(m, w, id, first, qty) then
			tickMarket(m, wait, npcs)
			trade(m, w, id, second, qty)
		end
		tickMarket(m, 100, npcs)
	end
	return worth() - start
end

local QTYS = { 1, 10, 50, 100 }
local WAITS = { 0, 1, 5, 20, 100, 500 }

local function sweep(trade, p)
	local best, bestDesc, profitable, total = -math.huge, "", 0, 0
	for _, g in Goods do
		for _, first in { "buy", "sell" } do
			for _, qty in QTYS do
				for _, wait in WAITS do
					local profit = roundTrip(trade, p, g.id, first, qty, wait, 20, false)
					total += 1
					if profit > 0 then
						profitable += 1
					end
					if profit > best then
						best = profit
						bestDesc = string.format("%s %s x%d, wait %d", g.id, first, qty, wait)
					end
				end
			end
		end
	end
	return best, bestDesc, profitable, total
end

local function printFreeMoney(p)
	print("\n== Free-money check: round trips in a quiet market (20 cycles each) ==")
	local best, desc, n, total = sweep(MarketState.trade, p)
	print(string.format("real model:    %d/%d strategies profitable, best = %+.0f (%s)", n, total, best, desc))
	best, desc, n, total = sweep(naiveTrade, p)
	print(string.format("naive control: %d/%d strategies profitable, best = %+.0f (%s)", n, total, best, desc))

	print("\n== Speculation in a noisy market (NPCs on): buy, wait 50, sell; 500 trials ==")
	print("good    mean profit  sd      % profitable")
	for _, g in Goods do
		math.randomseed(7)
		local results, wins = {}, 0
		for _ = 1, 500 do
			local r = roundTrip(MarketState.trade, p, g.id, "buy", 10, 50, 1, true)
			table.insert(results, r)
			if r > 0 then
				wins += 1
			end
		end
		print(string.format("%-7s %11.1f %7.1f %8.1f%%", g.id, mean(results), sd(results), wins / 5))
	end
end

---------------------------------------------------------------------------

local t0 = os.clock()
local p = params()
print("Params: " .. string.format(
	"elasticity=%.2f floor=%.2f ceiling=%.2f smoothing=%.2f drift=%.3f spread=%.2f",
	p.elasticity,
	p.floor,
	p.ceiling,
	p.smoothing,
	p.drift,
	p.spread
))
printBaseline("Baseline", p)
printShocks(p)
printFreeMoney(p)
for _, e in { 0.5, 1.2 } do
	printBaseline(string.format("Elasticity %.1f", e), params({ elasticity = e }))
end
print(string.format("\nDone in %.1fs", os.clock() - t0))
