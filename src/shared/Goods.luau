--!strict
-- Static definitions for every tradeable good. Pure data, no Roblox APIs,
-- so the offline simulation can require it too.

export type Good = {
	id: string,
	name: string,
	realm: string, -- Realms id: the world this good is gathered, crafted and traded in
	basePrice: number, -- price when stock == targetStock
	targetStock: number, -- stock level the market drifts back toward
	raw: boolean, -- raw goods are gathered, the rest are crafted
	color: string, -- hex, used by the UI and world
	icon: string, -- emoji shown in the UI
	gearLevel: number?, -- gear level (in its world) needed to gather this (raw only)
	rebirths: number?, -- rebirths needed before this can be gathered (raw only)
}

local Goods: { Good } = {
	-- Market Town (the hub)
	{ id = "wood", name = "Wood", realm = "main", basePrice = 10, targetStock = 500, raw = true, color = "#A86F3C", icon = "🌳" },
	{ id = "wheat", name = "Wheat", realm = "main", basePrice = 8, targetStock = 600, raw = true, color = "#E8C547", icon = "🌾" },
	{ id = "stone", name = "Stone", realm = "main", basePrice = 15, targetStock = 400, raw = true, color = "#9AA0A8", icon = "⛰️" },
	{ id = "iron", name = "Iron", realm = "main", basePrice = 32, targetStock = 200, raw = true, color = "#C8714E", icon = "🔩", gearLevel = 2 },
	{ id = "gems", name = "Gems", realm = "main", basePrice = 60, targetStock = 150, raw = true, color = "#B57BFF", icon = "💎", gearLevel = 3, rebirths = 1 },
	{ id = "bread", name = "Bread", realm = "main", basePrice = 40, targetStock = 150, raw = false, color = "#D9944A", icon = "🍞" },
	{ id = "tools", name = "Tools", realm = "main", basePrice = 105, targetStock = 60, raw = false, color = "#6FA8DC", icon = "🔨" },
	{ id = "jewelry", name = "Jewelry", realm = "main", basePrice = 175, targetStock = 50, raw = false, color = "#FF7EB6", icon = "💍" },

	-- Frostpeak (prices in Frost Coins, about 4x the hub's numbers)
	{ id = "pine", name = "Pine", realm = "frost", basePrice = 40, targetStock = 500, raw = true, color = "#3E7D5A", icon = "🌲" },
	{ id = "fish", name = "Fish", realm = "frost", basePrice = 128, targetStock = 200, raw = true, color = "#6FB7E8", icon = "🐟", gearLevel = 2 },
	{ id = "icecrystal", name = "Ice Crystal", realm = "frost", basePrice = 240, targetStock = 150, raw = true, color = "#9EE6FF", icon = "💠", gearLevel = 3 },
	{ id = "stew", name = "Fish Stew", realm = "frost", basePrice = 340, targetStock = 80, raw = false, color = "#E89B5A", icon = "🍲" },
	{ id = "frostorb", name = "Frost Orb", realm = "frost", basePrice = 700, targetStock = 50, raw = false, color = "#8FA8FF", icon = "🔮" },

	-- Emberfall (prices in Ember Coins, about 16x the hub's numbers)
	{ id = "charcoal", name = "Charcoal", realm = "ember", basePrice = 160, targetStock = 500, raw = true, color = "#4A4448", icon = "⚫" },
	{ id = "magma", name = "Magma Rock", realm = "ember", basePrice = 512, targetStock = 200, raw = true, color = "#FF6A2A", icon = "🌋", gearLevel = 2 },
	{ id = "dragonscale", name = "Dragon Scale", realm = "ember", basePrice = 960, targetStock = 150, raw = true, color = "#C8323C", icon = "🐉", gearLevel = 3 },
	{ id = "steel", name = "Steel", realm = "ember", basePrice = 1360, targetStock = 80, raw = false, color = "#A8B4C0", icon = "⚙️" },
	{ id = "armor", name = "Dragon Armor", realm = "ember", basePrice = 2800, targetStock = 50, raw = false, color = "#E0A030", icon = "🛡️" },
}

return Goods
