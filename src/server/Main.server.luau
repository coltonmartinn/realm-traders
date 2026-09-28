--!strict
-- Server entry point: owns the one market, handles trade requests, runs the
-- market tick and broadcasts state. Clients only display what they receive.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Goods = require(ReplicatedStorage.Shared.Goods)
local MarketState = require(script.Parent.MarketState)
local Npc = require(script.Parent.Npc)
local PlayerData = require(script.Parent.PlayerData)

local Remotes = ReplicatedStorage.Remotes
local TradeRequest = Remotes.TradeRequest :: RemoteEvent
local MarketUpdate = Remotes.MarketUpdate :: RemoteEvent
local PlayerUpdate = Remotes.PlayerUpdate :: RemoteEvent

local TICK_SECONDS = 1
local MIN_REQUEST_GAP = 0.2 -- seconds between accepted trade requests per player

local market = MarketState.new(Goods)
local lastRequest: { [Player]: number } = {}

-- Arguments come from the client and are untrusted; MarketState.trade checks
-- the good, side, quantity, cash and stock. Bad requests are silently ignored.
TradeRequest.OnServerEvent:Connect(function(player: Player, goodId: unknown, side: unknown, qty: unknown)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < MIN_REQUEST_GAP then
		return
	end
	lastRequest[player] = now

	local data = PlayerData.get(player)
	if not data then
		return
	end
	if MarketState.trade(market, data, goodId, side, qty) then
		PlayerUpdate:FireClient(player, data)
	end
end)

local function onPlayerAdded(player: Player)
	local data = PlayerData.load(player)
	PlayerUpdate:FireClient(player, data)
	MarketUpdate:FireClient(player, MarketState.snapshot(market))
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	PlayerData.unload(player)
	lastRequest[player] = nil
end)

while true do
	task.wait(TICK_SECONDS)
	Npc.step(market)
	MarketState.tick(market)
	MarketUpdate:FireAllClients(MarketState.snapshot(market))
end
