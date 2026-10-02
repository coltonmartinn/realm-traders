--!strict
-- Crafting recipes. Pure data. Inputs are consumed, one output unit is made.

export type Recipe = {
	id: string, -- also the id of the good it produces
	realm: string, -- the world it's crafted in (same as its inputs)
	verb: string, -- shown on the craft button
	inputs: { { id: string, qty: number } },
}

local Recipes: { Recipe } = {
	{ id = "bread", realm = "main", verb = "Bake", inputs = { { id = "wheat", qty = 3 }, { id = "wood", qty = 1 } } },
	{ id = "tools", realm = "main", verb = "Forge", inputs = { { id = "iron", qty = 2 }, { id = "stone", qty = 1 }, { id = "wood", qty = 1 } } },
	{ id = "jewelry", realm = "main", verb = "Craft", inputs = { { id = "gems", qty = 2 }, { id = "iron", qty = 1 } } },
	{ id = "stew", realm = "frost", verb = "Cook", inputs = { { id = "fish", qty = 2 }, { id = "pine", qty = 1 } } },
	{ id = "frostorb", realm = "frost", verb = "Enchant", inputs = { { id = "icecrystal", qty = 2 }, { id = "fish", qty = 1 } } },
	{ id = "steel", realm = "ember", verb = "Smelt", inputs = { { id = "magma", qty = 2 }, { id = "charcoal", qty = 1 } } },
	{ id = "armor", realm = "ember", verb = "Forge", inputs = { { id = "dragonscale", qty = 2 }, { id = "magma", qty = 1 } } },
}

return Recipes
