--!strict
-- Runs the timed happenings: market news events (a temporary price boost on
-- one good) and visits from the Travelling Merchant. Clients get the current
-- state through the News remote: { event = {...}?, merchant = {...}? }, with
-- end times in workspace:GetServerTimeNow() seconds for countdowns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Events = require(ReplicatedStorage.Shared.Events)
local Goods = require(ReplicatedStorage.Shared.Goods)
local Rules = require(ReplicatedStorage.Shared.Rules)
local MarketState = require(script.Parent.MarketState)
local World = require(script.Parent.World)

local News = ReplicatedStorage.Remotes.News :: RemoteEvent

export type Deps = {
	getProfile: (Player) -> Rules.Profile?,
	notify: (Player, { [string]: any }) -> (),
	commit: (Player, Rules.Profile) -> (),
	money: (number) -> string,
}

export type EventNews = { id: string, icon: string, title: string, text: string, good: string, boost: number, endsAt: number }
export type MerchantNews = { good: string, price: number, limit: number, endsAt: number }

local Happenings = {}

local state: { event: EventNews?, merchant: MerchantNews? } = {}
local merchantSold: { [Player]: number } = {}

local goodsById: { [string]: Goods.Good } = {}
for _, g in Goods do
	goodsById[g.id] = g
end

-- In Studio, set the attribute FastEvents = true on ServerScriptService.Server
-- to make happenings start a few seconds apart (for testing).
local function gap(range: { number }): number
	if RunService:IsStudio() and script.Parent:GetAttribute("FastEvents") then
		return 4
	end
	return math.random(range[1], range[2])
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function broadcast()
	News:FireAllClients(state)
end

function Happenings.sendTo(player: Player)
	News:FireClient(player, state)
end

function Happenings.playerLeft(player: Player)
	merchantSold[player] = nil
end

local function runEvents(market: MarketState.State)
	local last: string? = nil
	while true do
		task.wait(gap(Events.EVENT_GAP))
		local choices = {}
		for _, e in Events.list do
			if e.id ~= last then
				table.insert(choices, e)
			end
		end
		local e = choices[math.random(#choices)]
		last = e.id
		MarketState.setBoost(market, e.good, e.boost)
		state.event = { id = e.id, icon = e.icon, title = e.title, text = e.text, good = e.good, boost = e.boost, endsAt = now() + Events.EVENT_SECONDS }
		broadcast()
		task.wait(Events.EVENT_SECONDS)
		MarketState.setBoost(market, e.good, 1)
		state.event = nil
		broadcast()
	end
end

local function runMerchant(deps: Deps)
	while true do
		task.wait(gap(Events.MERCHANT_GAP))
		local goodId = Events.MERCHANT_GOODS[math.random(#Events.MERCHANT_GOODS)]
		local price = math.floor(goodsById[goodId].basePrice * Events.MERCHANT_PREMIUM)
		table.clear(merchantSold)
		local model, prompt = World.merchant(goodId, price)

		prompt.Triggered:Connect(function(player)
			local profile = deps.getProfile(player)
			if not profile then
				return
			end
			local left = Events.MERCHANT_LIMIT - (merchantSold[player] or 0)
			if left <= 0 then
				deps.notify(player, { kind = "error", text = `The merchant won't buy more from you this visit` })
				return
			end
			local n, value = Rules.merchantSell(profile, goodId, price, left)
			if n == 0 then
				local good = goodsById[goodId]
				local bought = (profile.inventory[goodId] or 0) > 0
				deps.notify(player, { kind = "error", text = if bought then `The merchant only buys {good.name} you gathered or crafted yourself` else `You don't have any {good.icon} {good.name} to sell` })
				return
			end
			merchantSold[player] = (merchantSold[player] or 0) + n
			deps.notify(player, { kind = "sale", text = `The merchant paid {deps.money(value)} for {n} {goodsById[goodId].name}!`, amount = value })
			deps.commit(player, profile)
		end)

		state.merchant = { good = goodId, price = price, limit = Events.MERCHANT_LIMIT, endsAt = now() + Events.MERCHANT_SECONDS }
		broadcast()
		task.wait(Events.MERCHANT_SECONDS)
		model:Destroy()
		state.merchant = nil
		broadcast()
	end
end

function Happenings.start(market: MarketState.State, deps: Deps)
	task.spawn(runEvents, market)
	task.spawn(runMerchant, deps)
	Players.PlayerRemoving:Connect(Happenings.playerLeft)
end

return Happenings
