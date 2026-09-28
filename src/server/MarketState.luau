--!strict
-- All market state (stock and displayed price per good) and the only code that
-- changes it. No Roblox APIs, so the offline simulation runs this exact module.

local PriceModel = require("./PriceModel")

export type Wallet = { cash: number, inventory: { [string]: number } }

type GoodLike = { id: string, basePrice: number, targetStock: number }

export type Entry = { good: GoodLike, stock: number, price: number }

export type State = {
	params: PriceModel.Params,
	entries: { [string]: Entry },
	order: { string },
}

export type Quote = { price: number, stock: number, ask: number, bid: number }

local MAX_QTY = 100

local MarketState = {}

MarketState.MAX_QTY = MAX_QTY

function MarketState.new(goods: { GoodLike }, params: PriceModel.Params?): State
	local state: State = { params = params or PriceModel.defaults, entries = {}, order = {} }
	for _, good in goods do
		state.entries[good.id] = { good = good, stock = good.targetStock, price = good.basePrice }
		table.insert(state.order, good.id)
	end
	return state
end

-- Validates and executes a trade against wallet. Arguments may come straight
-- from a client, so nothing is trusted. Returns the cash moved, or nil if the
-- request is invalid or unaffordable (the wallet is left untouched).
function MarketState.trade(state: State, wallet: Wallet, goodId: unknown, side: unknown, qty: unknown): number?
	if type(goodId) ~= "string" or (side ~= "buy" and side ~= "sell") then
		return nil
	end
	if type(qty) ~= "number" or qty ~= math.floor(qty) or qty < 1 or qty > MAX_QTY then
		return nil
	end
	local entry = state.entries[goodId]
	if not entry then
		return nil
	end

	local owned = wallet.inventory[goodId] or 0
	if side == "buy" then
		if qty > entry.stock then
			return nil
		end
		local cost = PriceModel.buyCost(entry.good, entry.stock, entry.price, qty, state.params)
		if wallet.cash < cost then
			return nil
		end
		wallet.cash -= cost
		wallet.inventory[goodId] = owned + qty
		entry.stock -= qty
		return cost
	else
		if owned < qty then
			return nil
		end
		local value = PriceModel.sellValue(entry.good, entry.stock, entry.price, qty, state.params)
		wallet.cash += value
		wallet.inventory[goodId] = owned - qty
		entry.stock += qty
		return value
	end
end

-- One market tick: stock drifts toward target, displayed price eases toward spot.
function MarketState.tick(state: State)
	local p = state.params
	for _, entry in state.entries do
		entry.stock = PriceModel.driftStock(entry.good, entry.stock, p)
		entry.price = PriceModel.smooth(entry.price, PriceModel.spotPrice(entry.good, entry.stock, p), p)
	end
end

-- What clients see: displayed price, stock, and the 1-unit ask (buy) and bid (sell).
function MarketState.snapshot(state: State): { [string]: Quote }
	local p = state.params
	local out = {}
	for id, e in state.entries do
		out[id] = {
			price = e.price,
			stock = e.stock,
			ask = if e.stock > 0 then PriceModel.buyCost(e.good, e.stock, e.price, 1, p) else 0,
			bid = PriceModel.sellValue(e.good, e.stock, e.price, 1, p),
		}
	end
	return out
end

return MarketState
