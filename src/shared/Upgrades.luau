--!strict
-- Player upgrades. levels[i] is the state at level i; cost is what it takes
-- to reach that level (level 1 is where everyone starts).

export type Upgrade = {
	id: string,
	name: string,
	icon: string,
	description: string,
	unit: string, -- what value measures, for the UI
	levels: { { cost: number, value: number } },
	realms: { string }?, -- only sold in these worlds (all worlds when missing)
}

local Upgrades = {}

local list: { Upgrade } = {
	{
		id = "gear",
		name = "Gathering Gear",
		icon = "⛏️",
		description = "More per gather. Each level opens new zones and a deeper level of the mine.",
		unit = "per gather",
		levels = {
			{ cost = 0, value = 1 },
			{ cost = 200, value = 2 },
			{ cost = 1500, value = 3 },
			{ cost = 6000, value = 4 },
			{ cost = 20000, value = 5 },
		},
	},
	{
		id = "backpack",
		name = "Backpack",
		icon = "🎒",
		description = "Carry more goods before you have to sell or craft.",
		unit = "slots",
		levels = {
			{ cost = 0, value = 25 },
			{ cost = 100, value = 50 },
			{ cost = 800, value = 100 },
			{ cost = 3000, value = 200 },
			{ cost = 10000, value = 400 },
		},
	},
}

table.insert(list, {
	id = "helper",
	name = "Helper Bee",
	icon = "🐝",
	description = "A bee that gathers for you while you stand in a zone.",
	unit = "gathers/min",
	levels = {
		{ cost = 0, value = 0 },
		{ cost = 2500, value = 10 },
		{ cost = 8000, value = 15 },
		{ cost = 20000, value = 20 },
		{ cost = 50000, value = 30 },
	},
})

-- Protective gear for the Deep Mine in the cold and fire worlds: each level
-- lets you go one mine level deeper there (in Market Town, your Gear does that).
table.insert(list, {
	id = "thermal",
	name = "Thermal Gear",
	icon = "🧥",
	description = "Cold-proof clothing. Each level lets you mine one level deeper.",
	unit = "mine depth",
	realms = { "frost" },
	levels = {
		{ cost = 0, value = 1 },
		{ cost = 300, value = 2 },
		{ cost = 2000, value = 3 },
		{ cost = 8000, value = 4 },
		{ cost = 25000, value = 5 },
	},
})
table.insert(list, {
	id = "fireproof",
	name = "Fireproof Armor",
	icon = "🛡️",
	description = "Heat-proof armor. Each level lets you mine one level deeper.",
	unit = "mine depth",
	realms = { "ember" },
	levels = {
		{ cost = 0, value = 1 },
		{ cost = 300, value = 2 },
		{ cost = 2000, value = 3 },
		{ cost = 8000, value = 4 },
		{ cost = 25000, value = 5 },
	},
})

-- Which upgrade sets how deep you can mine in each world (its level = the deepest level).
Upgrades.DEPTH = { main = "gear", frost = "thermal", ember = "fireproof" } :: { [string]: string }

local byId: { [string]: Upgrade } = {}
for _, u in list do
	byId[u.id] = u
end

Upgrades.list = list
Upgrades.byId = byId

function Upgrades.value(id: string, level: number): number
	local u = byId[id]
	return u.levels[math.clamp(level, 1, #u.levels)].value
end

-- Cost of the next level, or nil when maxed. `scale` is the world's
-- costScale (each world prices upgrades in its own coin).
function Upgrades.nextCost(id: string, level: number, scale: number?): number?
	local nextLevel = byId[id].levels[level + 1]
	return nextLevel and nextLevel.cost * (scale or 1)
end

-- Upgrades that belong to the player rather than a world (bought in the hub).
Upgrades.GLOBAL = { helper = true } :: { [string]: boolean }

-- Whether upgradeId is sold in a world.
function Upgrades.availableIn(id: string, realmId: string): boolean
	local realms = byId[id].realms
	return realms == nil or table.find(realms, realmId) ~= nil
end

function Upgrades.maxLevel(id: string): number
	return #byId[id].levels
end

return Upgrades
