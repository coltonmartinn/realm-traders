--!strict
-- Worlds you reach through portals in the hub. Each has its own goods, market
-- prices, coin, upgrades and goal chain, saved separately from the hub, and
-- opens after enough Rebirths (like the worlds in Pet Simulator).
-- Pure data, no Roblox APIs.

export type Realm = {
	id: string,
	name: string,
	icon: string,
	coin: string, -- prefix for amounts of this world's money
	coinName: string,
	rebirths: number, -- needed to walk through the portal
	costScale: number, -- upgrade costs and prices are this many times the hub's
	startCash: number,
	color: string, -- Theme color name
}

local list: { Realm } = {
	{ id = "main", name = "Market Town", icon = "🏠", coin = "$", coinName = "Cash", rebirths = 0, costScale = 1, startCash = 100, color = "green" },
	{ id = "frost", name = "Frostpeak", icon = "❄️", coin = "❄️", coinName = "Frost Coins", rebirths = 2, costScale = 4, startCash = 400, color = "blue" },
	{ id = "ember", name = "Emberfall", icon = "🔥", coin = "🔥", coinName = "Ember Coins", rebirths = 5, costScale = 16, startCash = 1600, color = "red" },
}

local byId: { [string]: Realm } = {}
for _, realm in list do
	byId[realm.id] = realm
end

local Realms = {}

Realms.list = list
Realms.byId = byId
Realms.MAIN = "main"

-- "1234567" -> "1,234,567"
function Realms.commas(n: number): string
	local s = tostring(math.floor(n))
	local k
	repeat
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

-- An amount of a world's money, e.g. "$1,250" or "❄️1,250".
function Realms.money(n: number, realmId: string?): string
	local realm = byId[realmId or "main"] or byId.main
	return realm.coin .. Realms.commas(n)
end

return Realms
