--!strict
-- Cash and inventory per player, held in memory while they are in the server.

local MarketState = require(script.Parent.MarketState)

local START_CASH = 500

local PlayerData = {}

local profiles: { [Player]: MarketState.Wallet } = {}

function PlayerData.load(player: Player): MarketState.Wallet
	local data = { cash = START_CASH, inventory = {} }
	profiles[player] = data
	return data
end

function PlayerData.get(player: Player): MarketState.Wallet?
	return profiles[player]
end

function PlayerData.unload(player: Player)
	profiles[player] = nil
end

return PlayerData
