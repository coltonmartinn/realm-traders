--!strict
-- Goal chains, one per world (Realms id -> list). One goal is active at a time
-- in each world; finishing it pays the reward (in that world's coin) and moves
-- to the next. Pure data and functions.

export type Stats = {
	gathered: { [string]: number },
	crafted: { [string]: number },
	sold: number, -- units sold to the market
	earned: number, -- cash received from sales
}

-- A world's progress (the hub's lives on the profile itself).
export type ProfileLike = {
	upgrades: { [string]: number },
	stats: Stats,
	rebirths: number?,
}

export type Goal = {
	text: string,
	hint: string, -- where to go or what to press
	where: string, -- Places id the guide arrow points to
	target: number,
	reward: number,
	progress: (ProfileLike) -> number,
	tutorial: boolean?, -- part of the beginner tutorial at the start of the chain
	ui: string?, -- HUD control to point at: "sell", or a menu panel ("craft", "upgrades")
}

local function gathered(id: string)
	return function(p: ProfileLike): number
		return p.stats.gathered[id] or 0
	end
end

local function crafted(id: string)
	return function(p: ProfileLike): number
		return p.stats.crafted[id] or 0
	end
end

local function upgrade(id: string)
	return function(p: ProfileLike): number
		return p.upgrades[id] or 1
	end
end

local main: { Goal } = {
	-- Tutorial: one small action per step, each teaching one part of the loop
	-- (gather, gather elsewhere, craft, sell, upgrade). The HUD points at the
	-- control to use and the guide arrow points at the place.
	{ tutorial = true, text = "Chop 5 Wood", where = "forest", hint = "Hold E at a tree. Follow the arrow!", target = 5, reward = 25, progress = gathered("wood") },
	{ tutorial = true, text = "Harvest 6 Wheat", where = "farm", hint = "Tap 🌾 Farm at the top to travel there", target = 6, reward = 25, progress = gathered("wheat") },
	{ tutorial = true, ui = "craft", text = "Bake your first Bread", where = "workshop", hint = "Open ⚒️ Craft: 3 Wheat + 1 Wood", target = 1, reward = 50, progress = crafted("bread") },
	{
		tutorial = true,
		ui = "sell",
		text = "Sell 5 goods",
		where = "market",
		hint = "Tap SELL by your backpack, or use the Market",
		target = 5,
		reward = 50,
		progress = function(p)
			return p.stats.sold
		end,
	},
	{ tutorial = true, ui = "upgrades", text = "Upgrade your Backpack", where = "outfitter", hint = "Open ⛏️ Gear: more room, fewer trips", target = 2, reward = 100, progress = upgrade("backpack") },

	{ text = "Bake 3 Bread", where = "workshop", hint = "Bake it at the Workshop", target = 3, reward = 100, progress = crafted("bread") },
	{ text = "Upgrade Gear to level 2", where = "outfitter", hint = "Level 2 unlocks the Mine", target = 2, reward = 100, progress = upgrade("gear") },
	{ text = "Mine 10 Iron", where = "mine", hint = "The Mine is open now!", target = 10, reward = 150, progress = gathered("iron") },
	{ text = "Forge 3 Tools", where = "workshop", hint = "Tools sell for the most", target = 3, reward = 250, progress = crafted("tools") },
	{
		text = "Earn $10,000 from sales",
		where = "market",
		hint = "Sell when prices are high",
		target = 10000,
		reward = 1000,
		progress = function(p)
			return p.stats.earned
		end,
	},
	{ text = "Max out your Gear", where = "outfitter", hint = "Level 5 gathers 5 per hold", target = 5, reward = 2500, progress = upgrade("gear") },
	{
		text = "Expand your Business",
		where = "outfitter",
		hint = "Rebirth for a permanent sell bonus",
		target = 1,
		reward = 5000,
		progress = function(p)
			return p.rebirths or 0
		end,
	},
	{ text = "Mine 20 Gems", where = "cave", hint = "Gear 3 opens the Crystal Cave", target = 20, reward = 3000, progress = gathered("gems") },
	{ text = "Craft 5 Jewelry", where = "workshop", hint = "2 Gems + 1 Iron each", target = 5, reward = 5000, progress = crafted("jewelry") },
}

local function earned(p: ProfileLike): number
	return p.stats.earned
end

local frost: { Goal } = {
	{ text = "Chop 10 Pine", where = "frost_woods", hint = "Hold E at a pine tree", target = 10, reward = 400, progress = gathered("pine") },
	{ text = "Upgrade your Backpack", where = "frost_outfitter", hint = "Each world has its own gear", target = 2, reward = 400, progress = upgrade("backpack") },
	{ text = "Upgrade Gear to level 2", where = "frost_outfitter", hint = "Level 2 opens the Frozen Lake", target = 2, reward = 800, progress = upgrade("gear") },
	{ text = "Catch 15 Fish", where = "frost_lake", hint = "Fish bite at the Frozen Lake", target = 15, reward = 1200, progress = gathered("fish") },
	{ text = "Cook 5 Fish Stew", where = "frost_workshop", hint = "2 Fish + 1 Pine each", target = 5, reward = 2000, progress = crafted("stew") },
	{ text = "Upgrade Gear to level 3", where = "frost_outfitter", hint = "Level 3 opens the Ice Cave", target = 3, reward = 4000, progress = upgrade("gear") },
	{ text = "Mine 20 Ice Crystals", where = "frost_cave", hint = "Deep in the Ice Cave", target = 20, reward = 6000, progress = gathered("icecrystal") },
	{ text = "Enchant 5 Frost Orbs", where = "frost_workshop", hint = "2 Ice Crystals + 1 Fish each", target = 5, reward = 10000, progress = crafted("frostorb") },
	{ text = "Earn ❄️200,000 from sales", where = "frost_market", hint = "Frost prices move like the hub's", target = 200000, reward = 20000, progress = earned },
	{ text = "Max out your Gear", where = "frost_outfitter", hint = "Level 5 gathers 5 per hold", target = 5, reward = 40000, progress = upgrade("gear") },
}

local ember: { Goal } = {
	{ text = "Collect 10 Charcoal", where = "ember_fields", hint = "Hold E at a charcoal pile", target = 10, reward = 1600, progress = gathered("charcoal") },
	{ text = "Upgrade your Backpack", where = "ember_outfitter", hint = "Each world has its own gear", target = 2, reward = 1600, progress = upgrade("backpack") },
	{ text = "Upgrade Gear to level 2", where = "ember_outfitter", hint = "Level 2 opens the Magma Pits", target = 2, reward = 3200, progress = upgrade("gear") },
	{ text = "Mine 15 Magma Rock", where = "ember_pits", hint = "Careful, it's hot!", target = 15, reward = 5000, progress = gathered("magma") },
	{ text = "Smelt 5 Steel", where = "ember_workshop", hint = "2 Magma Rock + 1 Charcoal each", target = 5, reward = 8000, progress = crafted("steel") },
	{ text = "Upgrade Gear to level 3", where = "ember_outfitter", hint = "Level 3 opens the Dragon's Lair", target = 3, reward = 16000, progress = upgrade("gear") },
	{ text = "Collect 20 Dragon Scales", where = "ember_lair", hint = "Shed by the dragons in the Lair", target = 20, reward = 24000, progress = gathered("dragonscale") },
	{ text = "Forge 5 Dragon Armor", where = "ember_workshop", hint = "2 Dragon Scales + 1 Magma Rock each", target = 5, reward = 40000, progress = crafted("armor") },
	{ text = "Earn 🔥800,000 from sales", where = "ember_market", hint = "The hottest market around", target = 800000, reward = 80000, progress = earned },
	{ text = "Max out your Gear", where = "ember_outfitter", hint = "Level 5 gathers 5 per hold", target = 5, reward = 160000, progress = upgrade("gear") },
}

return { main = main, frost = frost, ember = ember } :: { [string]: { Goal } }
