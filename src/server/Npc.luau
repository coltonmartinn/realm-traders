--!strict
-- Background NPC traders: small random buys and sells on every good so prices
-- move even with one player. They go through MarketState.trade like players,
-- with a bottomless wallet. No Roblox APIs (used by the simulation too).

local MarketState = require("./MarketState")

local ACTIVITY = 0.3 -- chance per good per step that an NPC trades it
local SIZE = 0.02 -- max trade size as a fraction of targetStock

export type NpcTrade = { goodId: string, side: string, qty: number, total: number }

local Npc = {}

function Npc.step(state: MarketState.State): { NpcTrade }
	local trades = {}
	for _, id in state.order do
		if math.random() < ACTIVITY then
			local entry = state.entries[id]
			local side = if math.random() < 0.5 then "buy" else "sell"
			local qty = math.random(1, math.max(1, math.ceil(entry.good.targetStock * SIZE)))
			local wallet = { cash = math.huge, inventory = { [id] = math.huge } }
			local total = MarketState.trade(state, wallet, id, side, qty)
			if total then
				table.insert(trades, { goodId = id, side = side, qty = qty, total = total })
			end
		end
	end
	return trades
end

return Npc
