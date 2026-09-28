--!strict
-- Static definitions for every tradeable good. Pure data, no Roblox APIs,
-- so the offline simulation can require it too.

export type Good = {
	id: string,
	name: string,
	basePrice: number, -- price when stock == targetStock
	targetStock: number, -- stock level the market drifts back toward
	raw: boolean, -- raw goods are gathered, the rest are crafted
}

local Goods: { Good } = {
	{ id = "wood", name = "Wood", basePrice = 20, targetStock = 500, raw = true },
	{ id = "stone", name = "Stone", basePrice = 30, targetStock = 400, raw = true },
	{ id = "iron", name = "Iron", basePrice = 80, targetStock = 200, raw = true },
	{ id = "bread", name = "Bread", basePrice = 120, targetStock = 150, raw = false },
	{ id = "tools", name = "Tools", basePrice = 300, targetStock = 60, raw = false },
}

return Goods
