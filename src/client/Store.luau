--!strict
-- Client-side copy of what the server sent: the player's profile, the latest
-- market snapshot, and a short price history per good for the trend charts.
-- UI modules subscribe with Store.subscribe and re-read what they need.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Rules)

export type Quote = { price: number, stock: number, ask: number, bid: number, boost: number }
export type EventNews = { id: string, icon: string, title: string, text: string, good: string, boost: number, endsAt: number }
export type MerchantNews = { good: string, price: number, limit: number, endsAt: number }
export type News = { event: EventNews?, merchant: MerchantNews? }

local HISTORY = 40

local Store = {
	profile = nil :: Rules.Profile?,
	profileAt = 0, -- os.clock() when the profile arrived (for boost countdowns)
	realm = "main", -- the world the local player is standing in
	market = nil :: { [string]: Quote }?,
	history = {} :: { [string]: { number } },
	news = {} :: News,
}

local listeners: { (what: string) -> () } = {}

function Store.subscribe(fn: (what: string) -> ())
	table.insert(listeners, fn)
end

local function emit(what: string)
	for _, fn in listeners do
		task.spawn(fn, what)
	end
end

function Store.setProfile(profile: Rules.Profile)
	Store.profile = profile
	Store.profileAt = os.clock()
	emit("profile")
end

function Store.setMarket(market: { [string]: Quote })
	Store.market = market
	for id, quote in market do
		local h = Store.history[id]
		if not h then
			h = {}
			Store.history[id] = h
		end
		table.insert(h, quote.price)
		if #h > HISTORY then
			table.remove(h, 1)
		end
	end
	emit("market")
end

-- Called when the player moves into another world.
function Store.setRealm(realm: string)
	if Store.realm ~= realm then
		Store.realm = realm
		emit("realm")
		emit("profile") -- everything that shows world progress redraws
	end
end

-- Progress in the current world (the profile itself in the hub).
function Store.wallet(): Rules.Wallet?
	local p = Store.profile
	return if p then Rules.wallet(p, Store.realm) else nil
end

function Store.setNews(news: News)
	Store.news = news
	emit("news")
end

-- Price change over the stored history, as a fraction (0.05 = +5%).
function Store.trend(id: string): number
	local h = Store.history[id]
	if not h or #h < 2 then
		return 0
	end
	return h[#h] / h[1] - 1
end

return Store
