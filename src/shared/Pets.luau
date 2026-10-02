--!strict
-- Pets: each adds to the multiplier on everything you sell (goods you made,
-- like the rebirth bonus). Every world sells its own pets for its own coin,
-- and later worlds' pets are stronger. Exotic pets only come from the Exotic
-- Egg in the Robux shop and are the strongest of all.
-- Up to SLOTS pets can be equipped; owned pets are kept forever (rebirths too).
-- Pure data, no Roblox APIs.

export type Pet = {
	id: string,
	name: string,
	icon: string,
	bonus: number, -- added to the sale multiplier (0.1 = +10%)
	color: string, -- hex, for the pet's body
	realm: string?, -- world whose coin buys it (nil for exotics)
	cost: number?, -- in that world's coin
	exotic: boolean?,
	weight: number?, -- exotic hatch weight
}

local list: { Pet } = {
	-- Market Town
	{ id = "puppy", name = "Puppy", icon = "🐶", bonus = 0.1, color = "#C8925A", realm = "main", cost = 1500 },
	{ id = "kitten", name = "Kitten", icon = "🐱", bonus = 0.2, color = "#F2A65A", realm = "main", cost = 8000 },
	{ id = "bunny", name = "Bunny", icon = "🐰", bonus = 0.35, color = "#F4F0EC", realm = "main", cost = 40000 },
	{ id = "fox", name = "Fox", icon = "🦊", bonus = 0.5, color = "#F07A2A", realm = "main", cost = 150000 },
	-- Frostpeak
	{ id = "penguin", name = "Penguin", icon = "🐧", bonus = 0.75, color = "#2E3440", realm = "frost", cost = 30000 },
	{ id = "owl", name = "Snow Owl", icon = "🦉", bonus = 1, color = "#EDE6DA", realm = "frost", cost = 150000 },
	{ id = "reindeer", name = "Reindeer", icon = "🦌", bonus = 1.5, color = "#9A6A44", realm = "frost", cost = 600000 },
	-- Emberfall
	{ id = "salamander", name = "Salamander", icon = "🦎", bonus = 2, color = "#FF7A3A", realm = "ember", cost = 500000 },
	{ id = "dragon", name = "Dragon", icon = "🐲", bonus = 3, color = "#D63C3C", realm = "ember", cost = 2500000 },
	{ id = "phoenix", name = "Phoenix", icon = "🦅", bonus = 5, color = "#FFB02E", realm = "ember", cost = 10000000 },
	-- Exotic (Exotic Egg only)
	{ id = "unicorn", name = "Unicorn", icon = "🦄", bonus = 6, color = "#F7C6F0", exotic = true, weight = 55 },
	{ id = "shark", name = "Mega Shark", icon = "🦈", bonus = 8, color = "#5A8FC8", exotic = true, weight = 30 },
	{ id = "kraken", name = "Kraken", icon = "🐙", bonus = 10, color = "#B04AE0", exotic = true, weight = 12 },
	{ id = "lion", name = "King Lion", icon = "🦁", bonus = 15, color = "#F2C12E", exotic = true, weight = 3 },
}

local byId: { [string]: Pet } = {}
for _, pet in list do
	byId[pet.id] = pet
end

local Pets = {}

Pets.list = list
Pets.byId = byId
Pets.SLOTS = 3

-- Exotic pets this player can still hatch, with each one's chance (0-1).
-- Pets they already own are left out, so an egg never gives a duplicate.
function Pets.exoticOdds(owned: { [string]: boolean }): { { pet: Pet, chance: number } }
	local total = 0
	for _, pet in list do
		if pet.exotic and not owned[pet.id] then
			total += pet.weight or 0
		end
	end
	local out = {}
	for _, pet in list do
		if pet.exotic and not owned[pet.id] then
			table.insert(out, { pet = pet, chance = (pet.weight or 0) / total })
		end
	end
	return out
end

-- Which exotic a roll in [0, 1) hatches, or nil if they own them all.
function Pets.rollExotic(owned: { [string]: boolean }, roll: number): Pet?
	local edge = 0
	local odds = Pets.exoticOdds(owned)
	for _, entry in odds do
		edge += entry.chance
		if roll < edge then
			return entry.pet
		end
	end
	return if #odds > 0 then odds[#odds].pet else nil
end

return Pets
