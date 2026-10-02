-- Trade validation tests. From the repo root:  luau tests/market.test.luau

local Goods = require("../src/shared/Goods")
local MarketState = require("../src/server/MarketState")

local failures = 0
local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
		print("FAIL: " .. name)
	end
end

local function fresh()
	return MarketState.new(Goods), { cash = 1000, inventory = { wood = 5 } }
end

-- Every bad request must return nil and leave wallet and market untouched.
local badRequests = {
	{ "unknown good", "gold", "buy", 1 },
	{ "numeric good", 1, "buy", 1 },
	{ "nil good", nil, "buy", 1 },
	{ "table good", {}, "buy", 1 },
	{ "bad side", "wood", "BUY", 1 },
	{ "nil side", "wood", nil, 1 },
	{ "zero qty", "wood", "buy", 0 },
	{ "negative qty", "wood", "sell", -1 },
	{ "fractional qty", "wood", "buy", 1.5 },
	{ "NaN qty", "wood", "buy", 0 / 0 },
	{ "inf qty", "wood", "buy", math.huge },
	{ "too large qty", "wood", "buy", MarketState.MAX_QTY + 1 },
	{ "string qty", "wood", "buy", "5" },
	{ "nil qty", "wood", "buy", nil },
	{ "sell more than owned", "wood", "sell", 6 },
	{ "sell unowned good", "iron", "sell", 1 },
	{ "buy unaffordable", "tools", "buy", 10 },
	{ "buy more than stock", "tools", "buy", 61 },
}

for _, case in badRequests do
	local market, wallet = fresh()
	local stockBefore = market.entries.wood.stock
	local result = MarketState.trade(market, wallet, case[2], case[3], case[4])
	check(case[1] .. ": rejected", result == nil)
	check(case[1] .. ": cash untouched", wallet.cash == 1000)
	check(case[1] .. ": inventory untouched", wallet.inventory.wood == 5 and wallet.inventory.iron == nil)
	check(case[1] .. ": stock untouched", market.entries.wood.stock == stockBefore)
end

do
	local market, wallet = fresh()
	local ask = MarketState.snapshot(market).wood.ask
	local cost = MarketState.trade(market, wallet, "wood", "buy", 1)
	check("buy 1 costs the quoted ask", cost == ask)
	check("buy takes cash", wallet.cash == 1000 - (cost :: number))
	check("buy adds inventory", wallet.inventory.wood == 6)
	check("buy removes stock", market.entries.wood.stock == 499)
end

do
	local market, wallet = fresh()
	local value = MarketState.trade(market, wallet, "wood", "sell", 5)
	check("sell pays cash", value ~= nil and value > 0 and wallet.cash == 1000 + value)
	check("sell removes inventory entry", wallet.inventory.wood == nil)
	check("sell adds stock", market.entries.wood.stock == 505)
end

do
	local market = MarketState.new(Goods)
	for id, q in MarketState.snapshot(market) do
		check(id .. ": ask above bid", q.ask > q.bid)
	end
	local e = market.entries.wood
	local before = MarketState.snapshot(market).wood.ask
	e.stock -= 100
	for _ = 1, 50 do
		MarketState.tick(market)
	end
	check("lower stock raises price", MarketState.snapshot(market).wood.ask > before)
end

-- Event boosts
do
	local market = MarketState.new(Goods)
	local base = MarketState.snapshot(market).bread
	MarketState.setBoost(market, "bread", 1.6)
	local boosted = MarketState.snapshot(market).bread
	check("boost raises the ask immediately", boosted.ask > base.ask * 1.5)
	check("bid does not jump until the price catches up", boosted.bid < base.bid * 1.05)
	for _ = 1, 60 do
		MarketState.tick(market)
	end
	local later = MarketState.snapshot(market).bread
	check("price catches up to the boost", later.price > base.price * 1.5 and later.bid > base.bid * 1.4)
	MarketState.setBoost(market, "bread", 1)
	for _ = 1, 60 do
		MarketState.tick(market)
	end
	check("price returns after the event", math.abs(MarketState.snapshot(market).bread.price - base.price) < base.price * 0.05)
	check("snapshot reports boost", later.boost == 1.6 and MarketState.snapshot(market).bread.boost == 1)

	-- No free money: buying at the start of a boost and selling at its peak
	-- is fine (that's trading), but buy-then-immediately-sell must still lose.
	local wallet = { cash = 100000, inventory = {} }
	MarketState.setBoost(market, "tools", 1.5)
	local cost = MarketState.trade(market, wallet, "tools", "buy", 10) :: number
	local value = MarketState.trade(market, wallet, "tools", "sell", 10) :: number
	check("round trip during a boost loses money", value < cost)
end

if failures > 0 then
	error(failures .. " check(s) failed")
end
print("All market tests passed")
