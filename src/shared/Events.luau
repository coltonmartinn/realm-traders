--!strict
-- Timed things that make the market feel alive (like Grow a Garden's weather
-- events and its Travelling Merchant): news events that push one good's price
-- up or down for a while, and a merchant who visits the plaza and pays a
-- premium for one good, for a limited time and amount. Pure data.

export type MarketEvent = {
	id: string,
	icon: string,
	title: string,
	text: string,
	good: string,
	boost: number, -- multiplies the good's base price while active
}

local Events = {}

Events.EVENT_SECONDS = 120
Events.EVENT_GAP = { 120, 200 } -- seconds between events (random in range)
Events.MERCHANT_SECONDS = 150
Events.MERCHANT_GAP = { 300, 420 }
Events.MERCHANT_LIMIT = 25 -- units each player may sell to one visit
Events.MERCHANT_PREMIUM = 2 -- times the good's base price
Events.MERCHANT_GOODS = { "stone", "iron", "bread", "tools" }

Events.list = {
	{ id = "bread_festival", icon = "🍞", title = "Bread Festival!", text = "The town is starving. Bread prices are climbing!", good = "bread", boost = 1.6 },
	{ id = "building_boom", icon = "🏗️", title = "Building Boom!", text = "Builders need Stone. Stone prices are climbing!", good = "stone", boost = 1.6 },
	{ id = "lumber_rush", icon = "🌳", title = "Lumber Rush!", text = "Everyone wants Wood. Wood prices are climbing!", good = "wood", boost = 1.7 },
	{ id = "tool_shortage", icon = "🔨", title = "Tool Shortage!", text = "Tools are scarce. Tool prices are climbing!", good = "tools", boost = 1.5 },
	{ id = "iron_fever", icon = "🔩", title = "Iron Fever!", text = "The forges are hungry. Iron prices are climbing!", good = "iron", boost = 1.6 },
	{ id = "royal_wedding", icon = "💍", title = "Royal Wedding!", text = "Everyone wants Jewelry. Jewelry prices are climbing!", good = "jewelry", boost = 1.5 },
	{ id = "bumper_harvest", icon = "🌾", title = "Bumper Harvest", text = "Too much Wheat! Prices are falling. Bake it into Bread?", good = "wheat", boost = 0.6 },
	{ id = "timber_glut", icon = "🪓", title = "Timber Glut", text = "The mills are full. Wood is cheap right now!", good = "wood", boost = 0.6 },
} :: { MarketEvent }

return Events
