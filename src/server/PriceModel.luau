--!strict
-- The price formula. Pure functions, no state, no Roblox APIs.
-- Swap this module out to try a different pricing model.
--
--   spot = basePrice * (targetStock / max(stock, 1)) ^ elasticity, clamped
--
-- The displayed price follows spot with smoothing. Trades are priced unit by
-- unit at the WORSE of the smoothed and spot price, plus a spread. Without the
-- "worse of" rule a player could buy while the smoothed price lags below spot,
-- wait for it to catch up, and sell for a profit (the simulation checks this).

export type Params = {
	elasticity: number,
	floor: number, -- min price as a multiple of basePrice
	ceiling: number, -- max price as a multiple of basePrice
	smoothing: number, -- fraction of the gap to spot closed per tick (0..1)
	drift: number, -- fraction of the gap to targetStock closed per tick (0..1)
	spread: number, -- buyers pay (1 + spread), sellers receive (1 - spread)
}

type GoodLike = { basePrice: number, targetStock: number }

local PriceModel = {}

PriceModel.defaults = {
	elasticity = 0.8,
	floor = 0.25,
	ceiling = 4,
	smoothing = 0.2,
	drift = 0.005,
	spread = 0.03,
} :: Params

function PriceModel.spotPrice(good: GoodLike, stock: number, p: Params): number
	local price = good.basePrice * (good.targetStock / math.max(stock, 1)) ^ p.elasticity
	return math.clamp(price, good.basePrice * p.floor, good.basePrice * p.ceiling)
end

function PriceModel.smooth(current: number, spot: number, p: Params): number
	return current + (spot - current) * p.smoothing
end

-- Total cash to buy qty units, rounded up. Each unit is priced at the stock
-- level after it is removed. Caller must ensure qty <= stock.
function PriceModel.buyCost(good: GoodLike, stock: number, smoothed: number, qty: number, p: Params): number
	local total = 0
	for i = 1, qty do
		total += math.max(smoothed, PriceModel.spotPrice(good, stock - i, p))
	end
	return math.ceil(total * (1 + p.spread))
end

-- Total cash received for selling qty units, rounded down. Each unit is priced
-- at the stock level after it is added.
function PriceModel.sellValue(good: GoodLike, stock: number, smoothed: number, qty: number, p: Params): number
	local total = 0
	for i = 1, qty do
		total += math.min(smoothed, PriceModel.spotPrice(good, stock + i, p))
	end
	return math.floor(total * (1 - p.spread))
end

-- Moves stock toward targetStock (off-screen production and consumption),
-- which pulls the price back toward basePrice. Always moves at least 1 and
-- never overshoots.
function PriceModel.driftStock(good: GoodLike, stock: number, p: Params): number
	local gap = good.targetStock - stock
	if gap == 0 then
		return stock
	end
	local step = math.round(gap * p.drift)
	if step == 0 then
		step = math.sign(gap)
	end
	return stock + step
end

return PriceModel
