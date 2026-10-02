--!strict
-- Robux shop catalog: coin packs, timed boosts and the Exotic Egg (Developer
-- Products, so they can be bought again and again).
--
-- SETUP: create one Developer Product per entry on the Creator Dashboard
-- (your experience > Monetization > Developer Products) and paste its ID into
-- `id`. The price players pay is the one set on the dashboard; `robux` here is
-- only shown until the real price loads, so keep them in sync. Entries with
-- id 0 show as "Coming soon" and can't be bought.

export type Product = {
	key: string,
	id: number,
	kind: string, -- "cash", "boost" or "egg"
	name: string,
	icon: string,
	robux: number,
	color: string, -- Theme color for the card
	tag: string?, -- ribbon like "POPULAR"
	cash: number?, -- coins at 0 rebirths (scaled up by rebirths so packs stay useful)
	boost: string?, -- Products.BOOSTS key
	minutes: number?,
}

export type Boost = { id: string, name: string, icon: string, mult: number, text: string, color: string }

local Products = {}

-- Timed boosts. Time only counts down while you're in the game.
Products.BOOSTS = {
	sell = { id = "sell", name = "2× Sell", icon = "💸", mult = 2, text = "Double cash from selling goods you made", color = "green" },
	gather = { id = "gather", name = "2× Gather", icon = "⚡", mult = 2, text = "Double goods from every gather", color = "blue" },
	luck = { id = "luck", name = "3× Luck", icon = "🍀", mult = 3, text = "Triple the chance of Golden and Rainbow finds", color = "purple" },
} :: { [string]: Boost }
Products.BOOST_ORDER = { "sell", "gather", "luck" }

-- Buying more of a boost adds time, up to this much banked.
Products.MAX_BOOST_SECONDS = 4 * 3600

Products.list = {
	{ key = "cash_1", id = 0, kind = "cash", name = "Pouch of Coins", icon = "💰", robux = 25, color = "gold", cash = 1000 },
	{ key = "cash_2", id = 0, kind = "cash", name = "Sack of Coins", icon = "💰", robux = 99, color = "gold", cash = 6000, tag = "POPULAR" },
	{ key = "cash_3", id = 0, kind = "cash", name = "Chest of Coins", icon = "🧰", robux = 399, color = "orange", cash = 30000 },
	{ key = "cash_4", id = 0, kind = "cash", name = "Vault of Coins", icon = "🏦", robux = 999, color = "orange", cash = 100000, tag = "BEST VALUE" },
	{ key = "egg_exotic", id = 0, kind = "egg", name = "Exotic Egg", icon = "🥚", robux = 199, color = "purple", tag = "BEST PETS" },
	{ key = "boost_sell", id = 0, kind = "boost", name = "2× Sell Boost", icon = "💸", robux = 49, color = "green", boost = "sell", minutes = 15 },
	{ key = "boost_gather", id = 0, kind = "boost", name = "2× Gather Boost", icon = "⚡", robux = 49, color = "blue", boost = "gather", minutes = 15 },
	{ key = "boost_luck", id = 0, kind = "boost", name = "3× Luck Boost", icon = "🍀", robux = 39, color = "purple", boost = "luck", minutes = 15 },
} :: { Product }

Products.byKey = {} :: { [string]: Product }
Products.byId = {} :: { [number]: Product }
for _, product in Products.list do
	Products.byKey[product.key] = product
	if product.id ~= 0 then
		Products.byId[product.id] = product
	end
end

return Products
