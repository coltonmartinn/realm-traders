--!strict
-- Where everything is on the map. The server builds the world from this, the
-- client uses it for fast travel and the guide arrow, so they always agree.
-- Uses Vector3, so it is Roblox-only (not loaded by the offline tests).
--
-- Every world (Realms) is laid out the same way around its own center: a
-- plaza, three shops in a row in front of it, a pet shop and a portal on the
-- plaza edge, and gathering zones a short walk away.

export type Place = {
	id: string,
	realm: string, -- Realms id
	name: string,
	icon: string,
	color: string, -- Theme color name for buttons
	kind: "shop" | "zone",
	center: Vector3, -- shop: counter position; zone: middle of the zone
	radius: number, -- zone: fence radius; shop: unused
	good: string?, -- zone: what is gathered there
	gearLevel: number?, -- zone: gear (in its world) needed to enter
	rebirths: number?, -- zone: rebirths needed to enter
	panel: string?, -- shop: UI panel its counter opens
}

local CENTERS: { [string]: Vector3 } = {
	main = Vector3.new(0, 0, 0),
	frost = Vector3.new(1600, 0, 0),
	ember = Vector3.new(3200, 0, 0),
}
local REALM_RADIUS = 200 -- each world's extent (the backdrop starts here); worlds are far apart
local BARRIER_RADIUS = 168 -- the wall round each world's play area (everything playable is inside ~155)

local function at(realm: string, x: number, z: number): Vector3
	return CENTERS[realm] + Vector3.new(x, 0, z)
end

-- The three shops, laid out the same in every world.
local function shops(realm: string, prefix: string): { Place }
	return {
		{ id = prefix .. "market", realm = realm, name = "Market", icon = "🛒", color = "blue", kind = "shop", center = at(realm, 0, -34), radius = 0, panel = "market" },
		{ id = prefix .. "workshop", realm = realm, name = "Workshop", icon = "⚒️", color = "purple", kind = "shop", center = at(realm, -34, -25), radius = 0, panel = "craft" },
		{ id = prefix .. "outfitter", realm = realm, name = "Outfitter", icon = "⛏️", color = "gold", kind = "shop", center = at(realm, 34, -25), radius = 0, panel = "upgrades" },
	}
end

local list: { Place } = {}
local function add(places: { Place })
	for _, place in places do
		table.insert(list, place)
	end
end

-- Market Town (the hub)
add(shops("main", ""))
add({
	{ id = "forest", realm = "main", name = "Forest", icon = "🌲", color = "green", kind = "zone", center = at("main", -100, 10), radius = 26, good = "wood" },
	{ id = "farm", realm = "main", name = "Farm", icon = "🌾", color = "orange", kind = "zone", center = at("main", 0, 100), radius = 24, good = "wheat" },
	{ id = "quarry", realm = "main", name = "Quarry", icon = "⛰️", color = "teal", kind = "zone", center = at("main", 100, 10), radius = 24, good = "stone" },
	{ id = "mine", realm = "main", name = "Mine", icon = "🔩", color = "red", kind = "zone", center = at("main", 80, 84), radius = 22, good = "iron", gearLevel = 2 },
	{ id = "cave", realm = "main", name = "Cave", icon = "💎", color = "purple", kind = "zone", center = at("main", -80, 84), radius = 22, good = "gems", gearLevel = 3, rebirths = 1 },
})

-- Frostpeak
add(shops("frost", "frost_"))
add({
	{ id = "frost_woods", realm = "frost", name = "Pine Woods", icon = "🌲", color = "green", kind = "zone", center = at("frost", -100, 10), radius = 26, good = "pine" },
	{ id = "frost_lake", realm = "frost", name = "Frozen Lake", icon = "🐟", color = "blue", kind = "zone", center = at("frost", 100, 10), radius = 24, good = "fish", gearLevel = 2 },
	{ id = "frost_cave", realm = "frost", name = "Ice Cave", icon = "💠", color = "teal", kind = "zone", center = at("frost", 0, 100), radius = 24, good = "icecrystal", gearLevel = 3 },
})

-- Emberfall
add(shops("ember", "ember_"))
add({
	{ id = "ember_fields", realm = "ember", name = "Ash Fields", icon = "⚫", color = "grey", kind = "zone", center = at("ember", -100, 10), radius = 26, good = "charcoal" },
	{ id = "ember_pits", realm = "ember", name = "Magma Pits", icon = "🌋", color = "orange", kind = "zone", center = at("ember", 100, 10), radius = 24, good = "magma", gearLevel = 2 },
	{ id = "ember_lair", realm = "ember", name = "Dragon's Lair", icon = "🐉", color = "red", kind = "zone", center = at("ember", 0, 100), radius = 24, good = "dragonscale", gearLevel = 3 },
})

local byId: { [string]: Place } = {}
for _, place in list do
	byId[place.id] = place
end

local Places = {}

Places.HUB = CENTERS.main
Places.CENTERS = CENTERS
Places.REALM_RADIUS = REALM_RADIUS
Places.BARRIER_RADIUS = BARRIER_RADIUS
Places.list = list
Places.byId = byId
Places.SPAWN = Vector3.new(0, 0, 14)
Places.MERCHANT = Vector3.new(-17, 0, 42) -- open grass between the Farm and Cave paths
-- Off the plaza on open grass, between zone paths, so nothing is in the way:
-- the board between the Forest and Cave paths, the pet shop between the
-- Quarry and Mine paths.
Places.LEADERBOARD = Vector3.new(-49, 0, 24)
local HUB_PET_SHOP = Vector3.new(49, 0, 24)

-- Portals in the hub to each world: in the gaps either side of the Market,
-- straight ahead of where you spawn, so they're the first thing you see.
Places.PORTALS = {
	frost = Vector3.new(-22, 0, -46),
	ember = Vector3.new(22, 0, -46),
} :: { [string]: Vector3 }

-- Where you arrive in a world (just in front of its plaza).
function Places.spawn(realm: string): Vector3
	return (CENTERS[realm] or CENTERS.main) + Vector3.new(0, 0, 14)
end

-- The pet shop: on open grass beside the plaza, clear of the zone paths.
function Places.petShop(realm: string): Vector3
	if realm == "main" or not CENTERS[realm] then
		return HUB_PET_SHOP
	end
	return CENTERS[realm] + Vector3.new(-36, 0, 38)
end

-- The portal home: beside the Market, in view from where you arrive.
function Places.homePortal(realm: string): Vector3
	return (CENTERS[realm] or CENTERS.main) + Vector3.new(22, 0, -46)
end

-- The Deep Mine: an entrance (a mine lift) in every world, on open grass
-- between the paths, and five cavern levels straight below it.
local MINE_ENTRANCE = Vector3.new(44, 0, 104)
local MINE_LEVEL_GAP = 70 -- studs between levels
local MINE_TOP = -60 -- floor of level 1
Places.MINE_HALF = 34 -- each cavern's floor runs this far from its middle

function Places.mineEntrance(realm: string): Vector3
	return (CENTERS[realm] or CENTERS.main) + MINE_ENTRANCE
end

-- The middle of a mine level's floor.
function Places.mineLevel(realm: string, depth: number): Vector3
	return (CENTERS[realm] or CENTERS.main) + MINE_ENTRANCE + Vector3.new(0, MINE_TOP - (depth - 1) * MINE_LEVEL_GAP, 0)
end

-- Which mine level a position is on (nil above ground).
function Places.mineDepthAt(position: Vector3): number?
	if position.Y > MINE_TOP + 40 then
		return nil
	end
	local depth = math.floor((MINE_TOP + 30 - position.Y) / MINE_LEVEL_GAP) + 1
	return math.clamp(depth, 1, 5)
end

-- Which world a position is in.
function Places.realmAt(position: Vector3): string
	for realm, center in CENTERS do
		if ((position - center) * Vector3.new(1, 0, 1)).Magnitude <= REALM_RADIUS + 60 then
			return realm
		end
	end
	return "main"
end

-- Places in one world, in list order.
function Places.inRealm(realm: string): { Place }
	local out = {}
	for _, place in list do
		if place.realm == realm then
			table.insert(out, place)
		end
	end
	return out
end

-- A world's market (the guide points here when your backpack is full).
function Places.marketOf(realm: string): Place
	return byId[if realm == "main" then "market" else realm .. "_market"]
end

-- The plaza center of a place's world.
function Places.centerOf(place: Place): Vector3
	return CENTERS[place.realm] or CENTERS.main
end

-- Unit vector from a zone's center toward its world's plaza (its gate faces it).
function Places.towardHub(place: Place): Vector3
	local d = (Places.centerOf(place) - place.center) * Vector3.new(1, 0, 1)
	return d.Unit
end

-- Where a zone's gate arch stands.
function Places.gate(place: Place): Vector3
	return place.center + Places.towardHub(place) * (place.radius + 3)
end

-- Where fast travel drops you, and which way you face.
function Places.arrival(place: Place): CFrame
	if place.kind == "shop" then
		local center = Places.centerOf(place)
		local front = place.center + (center - place.center).Unit * 9
		return CFrame.lookAt(front, Vector3.new(place.center.X, front.Y, place.center.Z))
	end
	local inside = place.center + Places.towardHub(place) * (place.radius - 5)
	return CFrame.lookAt(inside, Vector3.new(place.center.X, inside.Y, place.center.Z))
end

-- The good's zone, for "where do I get X" hints.
function Places.zoneFor(goodId: string): Place?
	for _, place in list do
		if place.good == goodId then
			return place
		end
	end
	return nil
end

return Places
