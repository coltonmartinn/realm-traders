--!strict
-- The scenery past each world's walls, so you never see the edge of the map.
-- Each direction is dressed for what's in front of it: fields and barns
-- behind the Farm, quarry terraces behind the Quarry, a town behind the
-- shops, a lava lake behind the Magma Pits... Behind that are rolling hills,
-- and a ring of mountains closes off the horizon. None of it can be reached
-- or touched, and props still claim their own ground (Layout) so nothing
-- stands inside anything else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)
local Layout = require(script.Parent.Layout)
local Scenery = require(script.Parent.Scenery)

local K = Scenery.kit

local Backdrop = {}

-- A direction to dress: `angle` (radians, atan2(z, x) from the world center)
-- and which backdrop goes there.
export type Sector = { angle: number, kind: string }

type Ctx = {
	parent: Instance,
	center: Vector3,
	from: number,
	to: number,
	rng: Random,
	realm: string,
}

local NEAR = Places.REALM_RADIUS -- props start just past the walls
local FAR = NEAR + 100 -- and end here; hills and mountains are further out

local SNOW = Color3.fromRGB(248, 252, 255)
local TRUNK = Color3.fromRGB(110, 74, 48)
local INK = Color3.fromRGB(30, 34, 64)
local LAVA = Color3.fromRGB(255, 104, 34)

local function polar(center: Vector3, angle: number, dist: number): Vector3
	return center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

-- Standing at `at`, front (-Z) toward the world center.
local function facing(center: Vector3, at: Vector3): CFrame
	return CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
end

-- How many of something for this sector, given how many a 90-degree sector gets.
local function per(ctx: Ctx, n: number): number
	return math.max(1, math.round(n * (ctx.to - ctx.from) / (math.pi / 2)))
end

-- Up to `count` free spots of radius r in the sector between two distances.
local function scatter(ctx: Ctx, near: number, far: number, count: number, r: number | () -> number, build: (cf: CFrame, radius: number) -> ())
	local placed = 0
	for _ = 1, count * 12 do
		if placed >= count then
			break
		end
		local radius = if type(r) == "function" then r() else r
		local at = polar(ctx.center, ctx.rng:NextNumber(ctx.from, ctx.to), ctx.rng:NextNumber(near, far))
		if Layout.take(at, radius, 0.5) then
			placed += 1
			build(facing(ctx.center, at), radius)
		end
	end
end

-- Rows of square cells (fields, houses) filling the sector between two distances.
local function grid(ctx: Ctx, near: number, far: number, cell: number, build: (cf: CFrame, row: number, col: number) -> ())
	local row = 0
	for dist = near + cell / 2, far - cell / 2, cell do
		row += 1
		local step = cell / dist
		local n = math.floor((ctx.to - ctx.from) / step)
		local first = ctx.from + ((ctx.to - ctx.from) - n * step) / 2 + step / 2
		for col = 0, n - 1 do
			local at = polar(ctx.center, first + col * step, dist)
			if Layout.take(at, cell * 0.45, 0) then
				build(facing(ctx.center, at), row, col)
			end
		end
	end
end

-- Shapes ---------------------------------------------------------------------------------

-- A cube stood on one corner: a low-poly mountain peak whose tip is at `height`.
local CORNER_UP = CFrame.fromAxisAngle(Vector3.new(-1, 0, 1).Unit, math.acos(1 / math.sqrt(3)))

local function peak(parent: Instance, at: Vector3, size: number, height: number, color: Color3, material: Enum.Material, cap: Color3?, rng: Random): Part
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local rock = K.block(parent, CFrame.new(at.X, height - size * 0.866, at.Z) * yaw * CORNER_UP, Vector3.one * size, color, material)
	rock.Name = "Peak"
	if cap then
		local k = 0.34
		local tip = K.block(parent, CFrame.new(at.X, height - k * size * 0.866 + size * 0.035, at.Z) * yaw * CORNER_UP, Vector3.one * size * k, cap, if cap == SNOW then Enum.Material.Snow else Enum.Material.Neon)
		tip.Name = "PeakCap"
	end
	return rock
end

-- A rounded hill `height` tall and about `width` across (the top of a big sunken ball).
local function hill(parent: Instance, at: Vector3, width: number, height: number, color: Color3, material: Enum.Material)
	local r = ((width / 2) ^ 2 + height ^ 2) / (2 * height)
	local p = K.ball(parent, CFrame.new(at.X, height - r, at.Z), Vector3.one * r * 2, color, material)
	p.Name = "Hill"
end

local function disc(parent: Instance, at: Vector3, diameter: number, y: number, color: Color3, material: Enum.Material): Part
	local p = K.block(parent, CFrame.new(at + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.2, diameter, diameter), color, material, { CastShadow = false })
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Trees and plants ----------------------------------------------------------------------------

local function leafyTree(parent: Instance, at: Vector3, scale: number, rng: Random, leaf: Color3)
	local m = K.model(parent, "Tree")
	local h = 8 * scale
	K.block(m, CFrame.new(at + Vector3.new(0, h / 2, 0)), Vector3.new(1.6 * scale, h, 1.6 * scale), TRUNK, Enum.Material.Wood)
	local green = leaf:Lerp(Color3.fromRGB(40, 110, 55), rng:NextNumber(0, 0.6))
	K.ball(m, CFrame.new(at + Vector3.new(0, h + 2 * scale, 0)), Vector3.one * 8 * scale, green, Enum.Material.Grass)
	K.ball(m, CFrame.new(at + Vector3.new(1.8 * scale, h + 4.6 * scale, 0.8 * scale)), Vector3.one * 5.5 * scale, green:Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.Grass)
end

-- A stepped pine, optionally with snow on each tier.
local function pine(parent: Instance, at: Vector3, scale: number, rng: Random, snowy: boolean)
	local m = K.model(parent, "Pine")
	local green = Color3.fromRGB(46, 110, 80):Lerp(Color3.fromRGB(30, 80, 60), rng:NextNumber())
	K.post(m, CFrame.new(at + Vector3.new(0, 2 * scale, 0)), 1.4 * scale, 4 * scale, TRUNK, Enum.Material.Wood)
	for i = 0, 3 do
		local d = (8 - i * 1.8) * scale
		local y = (3.6 + i * 2.6) * scale
		K.post(m, CFrame.new(at + Vector3.new(0, y, 0)), d, 2.8 * scale, green, Enum.Material.Grass)
		if snowy then
			K.post(m, CFrame.new(at + Vector3.new(0, y + 1.5 * scale, 0)), d * 0.8, 0.4 * scale, SNOW, Enum.Material.Snow)
		end
	end
end

local function spire(parent: Instance, at: Vector3, scale: number, rng: Random)
	local m = K.model(parent, "Spire")
	local h = rng:NextNumber(14, 26) * scale
	K.block(m, CFrame.new(at + Vector3.new(0, h / 2 - 1, 0)) * CFrame.Angles(rng:NextNumber(-0.12, 0.12), rng:NextNumber(0, math.pi), rng:NextNumber(-0.12, 0.12)), Vector3.new(5 * scale, h, 5 * scale), Color3.fromRGB(40, 32, 40), Enum.Material.Basalt)
	K.block(m, CFrame.new(at + Vector3.new(0, h * 0.35, 0)), Vector3.new(1.4 * scale, h * 0.6, 5.2 * scale), LAVA, Enum.Material.Neon)
end

-- Buildings ------------------------------------------------------------------------------

type TownLook = {
	walls: { Color3 },
	roofs: { Color3 },
	wallMaterial: Enum.Material,
	window: Color3,
	windowMaterial: Enum.Material,
	leaf: Color3?,
	snowy: boolean,
}

local TOWNS: { [string]: TownLook } = {
	main = {
		walls = { Color3.fromRGB(250, 240, 220), Color3.fromRGB(255, 214, 170), Color3.fromRGB(200, 226, 250), Color3.fromRGB(255, 200, 200), Color3.fromRGB(220, 240, 200) },
		roofs = { Color3.fromRGB(200, 70, 60), Color3.fromRGB(70, 110, 190), Color3.fromRGB(90, 160, 90), Color3.fromRGB(150, 90, 200), Color3.fromRGB(230, 150, 50) },
		wallMaterial = Enum.Material.SmoothPlastic,
		window = Color3.fromRGB(170, 215, 245),
		windowMaterial = Enum.Material.Glass,
		leaf = Color3.fromRGB(80, 170, 70),
		snowy = false,
	},
	frost = {
		walls = { Color3.fromRGB(150, 90, 70), Color3.fromRGB(120, 84, 60), Color3.fromRGB(110, 140, 180), Color3.fromRGB(170, 70, 70) },
		roofs = { SNOW },
		wallMaterial = Enum.Material.WoodPlanks,
		window = Color3.fromRGB(255, 210, 130),
		windowMaterial = Enum.Material.Neon,
		snowy = true,
	},
	ember = {
		walls = { Color3.fromRGB(90, 76, 74), Color3.fromRGB(70, 60, 60), Color3.fromRGB(110, 90, 80) },
		roofs = { Color3.fromRGB(150, 40, 36), Color3.fromRGB(50, 40, 44), Color3.fromRGB(120, 60, 30) },
		wallMaterial = Enum.Material.Cobblestone,
		window = Color3.fromRGB(255, 140, 50),
		windowMaterial = Enum.Material.Neon,
		snowy = false,
	},
}

local function house(parent: Instance, cf: CFrame, rng: Random, look: TownLook)
	local m = K.model(parent, "House")
	local w, d, h = rng:NextNumber(9, 12), rng:NextNumber(8, 10), rng:NextNumber(6, 8.5)
	K.block(m, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), look.walls[rng:NextInteger(1, #look.walls)], look.wallMaterial)
	K.roof(m, cf, w, d, h, look.roofs[rng:NextInteger(1, #look.roofs)], if look.snowy then Enum.Material.Snow else Enum.Material.Slate)
	local front = cf * CFrame.new(0, 0, -d / 2 - 0.1)
	K.block(m, front * CFrame.new(0, 2.2, 0), Vector3.new(2.2, 4.4, 0.3), Color3.fromRGB(110, 74, 48), Enum.Material.WoodPlanks)
	for _, x in { -1, 1 } do
		K.block(m, front * CFrame.new(x * (w / 4 + 0.6), h * 0.6, 0), Vector3.new(1.8, 1.8, 0.3), look.window, look.windowMaterial)
	end
	local chimney = K.block(m, cf * CFrame.new(w / 2 - 1.8, h + 3, d / 4), Vector3.new(1.4, 4, 1.4), Color3.fromRGB(150, 110, 100), Enum.Material.Brick)
	if rng:NextNumber() < 0.3 then
		K.smoke(chimney, Color3.fromRGB(220, 220, 225), 1.5)
	end
end

local function clockTower(parent: Instance, cf: CFrame, look: TownLook, rng: Random)
	local m = K.model(parent, "ClockTower")
	K.block(m, cf * CFrame.new(0, 12, 0), Vector3.new(8, 24, 8), look.walls[1], look.wallMaterial)
	K.block(m, cf * CFrame.new(0, 24.4, 0), Vector3.new(9, 0.8, 9), INK)
	peak(m, cf.Position, 7.5, 33, look.roofs[1], Enum.Material.Slate, nil, rng)
	local face = cf * CFrame.new(0, 18, -4.1)
	K.log(m, face * CFrame.Angles(0, math.rad(90), 0), 5, 0.3, Color3.fromRGB(250, 246, 236))
	K.block(m, face * CFrame.new(0, 0.8, -0.2), Vector3.new(0.3, 1.8, 0.1), INK)
	K.block(m, face * CFrame.new(0.6, 0, -0.2) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.3, 1.3, 0.1), INK)
end

local function windmill(parent: Instance, cf: CFrame)
	local m = K.model(parent, "Windmill")
	local stone = Color3.fromRGB(236, 226, 206)
	K.post(m, cf * CFrame.new(0, 5, 0), 8, 10, stone, Enum.Material.Brick)
	K.post(m, cf * CFrame.new(0, 13, 0), 6.4, 6, stone, Enum.Material.Brick)
	K.ball(m, cf * CFrame.new(0, 16.2, 0), Vector3.one * 6.6, Color3.fromRGB(196, 52, 46), Enum.Material.WoodPlanks)
	K.block(m, cf * CFrame.new(0, 2.2, -4), Vector3.new(2.2, 4.4, 0.4), Color3.fromRGB(110, 74, 48), Enum.Material.WoodPlanks)
	local hub = cf * CFrame.new(0, 14, -3.8)
	K.block(m, hub, Vector3.new(1.2, 1.2, 1.4), INK)
	for i = 0, 3 do
		local arm = hub * CFrame.Angles(0, 0, i * math.pi / 2 + 0.4)
		K.block(m, arm * CFrame.new(0, 5.6, -0.5), Vector3.new(0.4, 10, 0.3), Color3.fromRGB(110, 74, 48), Enum.Material.Wood)
		K.block(m, arm * CFrame.new(1.3, 6, -0.5), Vector3.new(2.2, 8, 0.15), Color3.fromRGB(250, 246, 236), Enum.Material.Fabric)
	end
end

type Crop = { color: Color3, height: number, material: Enum.Material }
local CROPS: { Crop } = {
	{ color = Color3.fromRGB(230, 196, 90), height = 1.8, material = Enum.Material.Grass }, -- wheat
	{ color = Color3.fromRGB(110, 170, 70), height = 3.2, material = Enum.Material.Grass }, -- corn
	{ color = Color3.fromRGB(130, 200, 110), height = 0.9, material = Enum.Material.Grass }, -- cabbage
	{ color = Color3.fromRGB(170, 130, 220), height = 1.2, material = Enum.Material.Grass }, -- lavender
	{ color = Color3.fromRGB(128, 92, 64), height = 0.5, material = Enum.Material.Ground }, -- freshly ploughed
}

local function field(parent: Instance, cf: CFrame, size: number, rng: Random)
	local m = K.model(parent, "Field")
	K.block(m, cf * CFrame.new(0, 0.25, 0), Vector3.new(size, 0.5, size), Color3.fromRGB(116, 82, 54), Enum.Material.SmoothPlastic)
	local crop = CROPS[rng:NextInteger(1, #CROPS)]
	local rows = 6
	for i = 0, rows - 1 do
		local z = (i - (rows - 1) / 2) * (size / rows)
		K.block(m, cf * CFrame.new(0, 0.5 + crop.height / 2, z), Vector3.new(size - 2, crop.height, size / rows * 0.55), crop.color, crop.material)
	end
end

local function volcano(parent: Instance, at: Vector3, scale: number)
	local m = K.model(parent, "Volcano")
	local cf = CFrame.new(at)
	local tiers = 8
	local tier = 9 * scale
	for i = 0, tiers - 1 do
		K.post(m, cf * CFrame.new(0, i * tier + tier / 2, 0), (110 - i * 11) * scale, tier, Color3.fromRGB(56, 44, 44):Lerp(Color3.fromRGB(80, 60, 56), i / tiers), Enum.Material.Basalt)
	end
	local top = tiers * tier
	local crater = K.post(m, cf * CFrame.new(0, top + 0.2, 0), 26 * scale, 0.6, LAVA, Enum.Material.Neon)
	K.glow(crater, LAVA, 60, 3)
	local plume = Instance.new("ParticleEmitter")
	plume.Rate = 5
	plume.Lifetime = NumberRange.new(7, 10)
	plume.Speed = NumberRange.new(10, 16)
	plume.SpreadAngle = Vector2.new(15, 15)
	plume.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8 * scale), NumberSequenceKeypoint.new(1, 30 * scale) })
	plume.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	plume.Color = ColorSequence.new(Color3.fromRGB(70, 60, 64))
	plume.EmissionDirection = Enum.NormalId.Right -- the cylinder's X axis points up
	plume.Parent = crater
	-- Lava running down the front, over each tier's wall and ledge
	for i = 0, tiers - 1 do
		local outer = (110 - i * 11) * scale / 2
		K.block(m, cf * CFrame.new(0, i * tier + tier / 2, -outer - 0.1), Vector3.new(4 * scale, tier + 0.4, 0.6), LAVA, Enum.Material.Neon)
		if i < tiers - 1 then
			local inner = (110 - (i + 1) * 11) * scale / 2
			K.block(m, cf * CFrame.new(0, (i + 1) * tier + 0.1, -(outer + inner) / 2), Vector3.new(4 * scale, 0.4, outer - inner + 0.4), LAVA, Enum.Material.Neon)
		end
	end
end

local function smokeColumn(parent: Instance, at: Vector3, color: Color3)
	local p = K.block(parent, CFrame.new(at + Vector3.new(0, 1, 0)), Vector3.new(4, 1, 4), color, nil, { Transparency = 1 })
	p.Name = "Smoke"
	local e = Instance.new("ParticleEmitter")
	e.Rate = 3
	e.Lifetime = NumberRange.new(6, 9)
	e.Speed = NumberRange.new(6, 9)
	e.SpreadAngle = Vector2.new(10, 10)
	e.Acceleration = Vector3.new(1.5, 0, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 20) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(color)
	e.Parent = p
end

-- Crags: a cluster of rock peaks in the sector, with `extra` called on some.
local function crags(ctx: Ctx, count: number, size: NumberRange, color: Color3, material: Enum.Material, cap: Color3?, extra: ((rock: Part) -> ())?)
	scatter(ctx, NEAR + 18, FAR, count, function()
		return ctx.rng:NextNumber(size.Min, size.Max) * 0.5
	end, function(cf, radius)
		local s = radius * 2
		local rock = peak(ctx.parent, cf.Position, s, s * ctx.rng:NextNumber(0.9, 1.3), color:Lerp(INK, ctx.rng:NextNumber(0, 0.15)), material, cap, ctx.rng)
		if extra then
			extra(rock)
		end
	end)
end

-- Lakes: overlapping circles of terrain (ice, lava) across the sector.
-- Returns them, so things can be put on them before their ground is claimed.
local function lake(ctx: Ctx, color: Color3, material: Enum.Material): { { at: Vector3, d: number } }
	local discs = {}
	local dist = NEAR + 62
	local d = 92
	local step = (d + 6) / dist -- far enough apart that discs never overlap
	local a = ctx.from + step / 2
	while a + step / 2 <= ctx.to + 0.001 do
		local at = polar(ctx.center, a, dist)
		disc(ctx.parent, at, d, 0.3, color, material).Name = "Lake" -- top at 0.4
		table.insert(discs, { at = at, d = d })
		a += step
	end
	return discs
end

-- What each direction looks like ---------------------------------------------------------------

type Kind = {
	ground: Color3?, -- the sector's ground, if it differs from the world's
	hills: Color3?, -- hills behind the props (none if the sector's props are tall)
	hillMaterial: Enum.Material?,
	fill: (ctx: Ctx) -> (),
}

local KINDS: { [string]: Kind } = {}

KINDS.forest = {
	ground = Color3.fromRGB(64, 160, 62),
	hills = Color3.fromRGB(58, 124, 60),
	fill = function(ctx)
		scatter(ctx, NEAR - 2, FAR, per(ctx, 110), function()
			return ctx.rng:NextNumber(1.8, 3) * 3
		end, function(cf, radius)
			leafyTree(ctx.parent, cf.Position, radius / 3, ctx.rng, Color3.fromRGB(70, 150, 64))
		end)
		scatter(ctx, NEAR, NEAR + 30, per(ctx, 4), 7, function(cf)
			K.logPile(ctx.parent, cf, Color3.fromRGB(150, 104, 66))
		end)
	end,
}

KINDS.farm = {
	hills = Color3.fromRGB(124, 184, 84),
	fill = function(ctx)
		grid(ctx, NEAR, FAR, 24, function(cf, row, col)
			local pick = (row * 5 + col * 3) % 11
			if pick == 4 and row <= 3 then
				K.barn(ctx.parent, cf)
				K.silo(ctx.parent, cf * CFrame.new(5, 0, 9.5))
			elseif pick == 8 then
				windmill(ctx.parent, cf)
			elseif pick == 1 then
				leafyTree(ctx.parent, cf.Position, 1.8, ctx.rng, Color3.fromRGB(90, 170, 70))
			else
				field(ctx.parent, cf, 22, ctx.rng)
			end
		end)
	end,
}

KINDS.quarry = {
	ground = Color3.fromRGB(190, 184, 170),
	fill = function(ctx)
		-- Cranes and cut stone at the foot of the terraces
		local props = 0
		scatter(ctx, NEAR - 2, NEAR + 6, per(ctx, 5), 4, function(cf)
			props += 1
			if props % 2 == 1 then
				K.crane(ctx.parent, cf)
			else
				K.stoneBlocks(ctx.parent, cf, ctx.rng)
			end
		end)
		-- Stepped quarry walls rising away from the world
		local tiers = { { 22, 6 }, { 42, 13 }, { 62, 21 }, { 84, 30 }, { 108, 40 } }
		local step = 18 / (NEAR + 40)
		local a = ctx.from + step / 2
		while a < ctx.to do
			for i, tier in tiers do
				local dist = NEAR + tier[1]
				local h = tier[2] + ctx.rng:NextNumber(-1, 2)
				local at = polar(ctx.center, a, dist)
				local cf = facing(ctx.center, at)
				K.block(ctx.parent, cf * CFrame.new(0, h / 2, 0), Vector3.new(dist * step + 1.5, h, 22), if i % 2 == 0 then Color3.fromRGB(200, 194, 182) else Color3.fromRGB(178, 172, 160), Enum.Material.Slate).Name = "Terrace"
				if i < #tiers and ctx.rng:NextNumber() < 0.12 then
					K.stoneBlocks(ctx.parent, cf * CFrame.new(0, h, 0), ctx.rng)
				end
				Layout.claim(at, 10)
			end
			a += step
		end
	end,
}

KINDS.mine = {
	ground = Color3.fromRGB(156, 116, 76),
	hills = Color3.fromRGB(130, 104, 84),
	hillMaterial = Enum.Material.Slate,
	fill = function(ctx)
		scatter(ctx, NEAR + 4, NEAR + 12, per(ctx, 3), 12, function(cf)
			K.mineEntrance(ctx.parent, cf, Color3.fromRGB(120, 100, 90), ctx.rng)
			K.rails(ctx.parent, cf * CFrame.new(0, 0, -1), 12)
			K.minecart(ctx.parent, cf * CFrame.new(0, 0, -8), Color3.fromRGB(200, 113, 78), false)
		end)
		crags(ctx, per(ctx, 14), NumberRange.new(26, 48), Color3.fromRGB(128, 102, 84), Enum.Material.Slate, nil)
		scatter(ctx, NEAR - 2, NEAR + 20, per(ctx, 6), 2, function(cf)
			K.barrel(ctx.parent, cf)
		end)
	end,
}

KINDS.cave = {
	ground = Color3.fromRGB(88, 72, 116),
	hills = Color3.fromRGB(70, 60, 86),
	hillMaterial = Enum.Material.Slate,
	fill = function(ctx)
		local lit = 0
		crags(ctx, per(ctx, 16), NumberRange.new(20, 44), Color3.fromRGB(88, 76, 110), Enum.Material.Slate, nil, function(rock)
			if lit < per(ctx, 5) then
				lit += 1
				local top = rock.Position.Y + rock.Size.X * 0.866
				K.crystalCluster(ctx.parent, CFrame.new(rock.Position.X, top - 3, rock.Position.Z), Color3.fromRGB(181, 123, 255), 3, ctx.rng)
			end
		end)
		scatter(ctx, NEAR - 2, NEAR + 16, per(ctx, 6), 3, function(cf)
			K.crystalCluster(ctx.parent, cf, Color3.fromRGB(200, 140, 255), 2, ctx.rng)
		end)
		scatter(ctx, NEAR - 2, NEAR + 30, per(ctx, 14), 1.6, function(cf)
			K.stalagmite(K.model(ctx.parent, "Stalagmite"), cf, Color3.fromRGB(96, 86, 112), ctx.rng)
		end)
	end,
}

KINDS.town = {
	fill = function(ctx)
		local look = TOWNS[ctx.realm] or TOWNS.main
		local middle = (ctx.from + ctx.to) / 2
		local towerAt = polar(ctx.center, middle, NEAR + 40)
		if Layout.take(towerAt, 9, 0) then
			clockTower(ctx.parent, facing(ctx.center, towerAt), look, ctx.rng)
		end
		grid(ctx, NEAR, FAR - 10, 20, function(cf)
			if ctx.rng:NextNumber() < 0.22 then
				if look.leaf then
					leafyTree(ctx.parent, cf.Position, 1.6, ctx.rng, look.leaf)
				elseif look.snowy then
					pine(ctx.parent, cf.Position, 1.5, ctx.rng, true)
				else
					spire(ctx.parent, cf.Position, 1, ctx.rng)
				end
			else
				house(ctx.parent, cf * CFrame.Angles(0, ctx.rng:NextNumber(-0.15, 0.15), 0), ctx.rng, look)
			end
		end)
	end,
}

-- The hub, toward the Frostpeak portal: snowy pines and white peaks
KINDS.frostpeaks = {
	ground = Color3.fromRGB(240, 246, 252),
	fill = function(ctx)
		crags(ctx, per(ctx, 10), NumberRange.new(40, 64), Color3.fromRGB(205, 220, 236), Enum.Material.Glacier, SNOW)
		scatter(ctx, NEAR - 2, FAR, per(ctx, 60), 4.5, function(cf)
			pine(ctx.parent, cf.Position, ctx.rng:NextNumber(1.4, 2.2), ctx.rng, true)
		end)
	end,
}

-- The hub, toward the Emberfall portal: a smoking volcano
KINDS.volcano = {
	ground = Color3.fromRGB(62, 48, 48),
	fill = function(ctx)
		local at = polar(ctx.center, (ctx.from + ctx.to) / 2, FAR + 10)
		Layout.claim(at, 55)
		volcano(ctx.parent, at, 1)
		scatter(ctx, NEAR - 2, FAR, per(ctx, 30), 3.5, function(cf)
			spire(ctx.parent, cf.Position, ctx.rng:NextNumber(0.7, 1.1), ctx.rng)
		end)
		scatter(ctx, NEAR, FAR, per(ctx, 4), 2, function(cf)
			smokeColumn(ctx.parent, cf.Position, Color3.fromRGB(80, 70, 72))
		end)
	end,
}

local SNOW_HILLS = Color3.fromRGB(232, 240, 248)

KINDS.frost_woods = {
	hills = SNOW_HILLS,
	hillMaterial = Enum.Material.Snow,
	fill = function(ctx)
		scatter(ctx, NEAR - 2, FAR, per(ctx, 120), function()
			return ctx.rng:NextNumber(1.4, 2.4) * 4
		end, function(cf, radius)
			pine(ctx.parent, cf.Position, radius / 4, ctx.rng, true)
		end)
		scatter(ctx, NEAR, NEAR + 30, per(ctx, 3), 7, function(cf)
			K.logCabin(ctx.parent, cf, Color3.fromRGB(110, 60, 50), Color3.fromRGB(120, 84, 60), true)
		end)
	end,
}

KINDS.frost_lake = {
	hills = SNOW_HILLS,
	hillMaterial = Enum.Material.Snow,
	fill = function(ctx)
		local discs = lake(ctx, Color3.fromRGB(150, 210, 250), Enum.Material.SmoothPlastic)
		-- Fishing huts, igloos and fishing holes out on the ice
		for i, d in discs do
			local hut = d.at + Vector3.new(ctx.rng:NextNumber(-15, 15), 0, ctx.rng:NextNumber(-15, 15))
			if Layout.take(hut, 6, 1) then
				if i % 2 == 0 then
					K.iceShanty(ctx.parent, facing(ctx.center, hut) * CFrame.new(0, 0.25, 0))
				else
					K.igloo(ctx.parent, facing(ctx.center, hut))
				end
			end
			for _ = 1, 2 do
				local hole = d.at + Vector3.new(ctx.rng:NextNumber(-28, 28), 0, ctx.rng:NextNumber(-28, 28))
				if Layout.take(hole, 2, 1) then
					disc(ctx.parent, hole, 3, 0.6, Color3.fromRGB(30, 70, 120), Enum.Material.SmoothPlastic).Name = "FishingHole"
				end
			end
		end
		for _, d in discs do
			Layout.claim(d.at, d.d / 2 - 6)
		end
		scatter(ctx, NEAR - 2, FAR, per(ctx, 30), 4.5, function(cf)
			pine(ctx.parent, cf.Position, ctx.rng:NextNumber(1.4, 2.2), ctx.rng, true)
		end)
	end,
}

KINDS.frost_cave = {
	hills = SNOW_HILLS,
	hillMaterial = Enum.Material.Snow,
	fill = function(ctx)
		local lit = 0
		crags(ctx, per(ctx, 16), NumberRange.new(22, 46), Color3.fromRGB(160, 210, 240), Enum.Material.Glacier, nil, function(rock)
			if lit < per(ctx, 5) then
				lit += 1
				local top = rock.Position.Y + rock.Size.X * 0.866
				K.crystalCluster(ctx.parent, CFrame.new(rock.Position.X, top - 3, rock.Position.Z), Color3.fromRGB(158, 230, 255), 3, ctx.rng)
			end
		end)
		scatter(ctx, NEAR - 2, NEAR + 20, per(ctx, 6), 3, function(cf)
			K.crystalCluster(ctx.parent, cf, Color3.fromRGB(158, 230, 255), 2, ctx.rng)
		end)
		scatter(ctx, NEAR - 2, NEAR + 30, per(ctx, 12), 1.6, function(cf)
			K.stalagmite(K.model(ctx.parent, "IceSpike"), cf, Color3.fromRGB(190, 225, 245), ctx.rng)
		end)
	end,
}

local ASH = Color3.fromRGB(96, 88, 88)

KINDS.ember_fields = {
	ground = Color3.fromRGB(100, 92, 92),
	hills = Color3.fromRGB(84, 76, 76),
	hillMaterial = Enum.Material.Slate,
	fill = function(ctx)
		scatter(ctx, NEAR, NEAR + 40, per(ctx, 5), 4.5, function(cf)
			K.kiln(ctx.parent, cf)
		end)
		scatter(ctx, NEAR, FAR, per(ctx, 4), 2, function(cf)
			smokeColumn(ctx.parent, cf.Position, Color3.fromRGB(70, 66, 70))
		end)
		scatter(ctx, NEAR + 10, FAR, per(ctx, 10), function()
			return ctx.rng:NextNumber(8, 14)
		end, function(cf, radius)
			hill(ctx.parent, cf.Position, radius * 2, radius * 0.5, ASH:Lerp(INK, 0.1), Enum.Material.Slate)
		end)
		scatter(ctx, NEAR - 2, FAR, per(ctx, 70), 1.5, function(cf)
			K.burntStump(K.model(ctx.parent, "BurntStump"), cf, ctx.rng)
		end)
	end,
}

KINDS.ember_pits = {
	ground = Color3.fromRGB(62, 48, 48),
	fill = function(ctx)
		local discs = lake(ctx, LAVA, Enum.Material.Neon)
		for i, d in discs do
			if i % 2 == 1 then
				local light = K.block(ctx.parent, CFrame.new(d.at + Vector3.new(0, 3, 0)), Vector3.one, LAVA, nil, { Transparency = 1 })
				light.Name = "LavaGlow"
				K.glow(light, LAVA, 40, 2)
			end
			local rock = d.at + Vector3.new(ctx.rng:NextNumber(-20, 20), 0, ctx.rng:NextNumber(-20, 20))
			if Layout.take(rock, 7, 1) then
				peak(ctx.parent, rock, 14, ctx.rng:NextNumber(9, 16), Color3.fromRGB(46, 36, 36), Enum.Material.Basalt, nil, ctx.rng)
			end
		end
		for _, d in discs do
			Layout.claim(d.at, d.d / 2 - 6)
		end
		-- Lavafalls pouring down the cliffs behind the lake
		local falls = per(ctx, 4)
		for i = 1, falls do
			local a = ctx.from + (ctx.to - ctx.from) * (i - 0.5) / falls
			local at = polar(ctx.center, a, FAR + 8)
			peak(ctx.parent, at + (at - ctx.center).Unit * 24, 40, 34, Color3.fromRGB(56, 40, 38), Enum.Material.Basalt, nil, ctx.rng)
			K.lavaFall(K.model(ctx.parent, "LavaFall"), facing(ctx.center, at))
		end
		scatter(ctx, NEAR - 2, NEAR + 14, per(ctx, 10), 3.5, function(cf)
			spire(ctx.parent, cf.Position, ctx.rng:NextNumber(0.6, 0.9), ctx.rng)
		end)
	end,
}

KINDS.ember_lair = {
	ground = Color3.fromRGB(88, 42, 48),
	hills = Color3.fromRGB(70, 36, 40),
	hillMaterial = Enum.Material.Basalt,
	fill = function(ctx)
		scatter(ctx, NEAR + 6, NEAR + 30, per(ctx, 2), 17, function(cf)
			K.dragonBones(ctx.parent, cf * CFrame.Angles(0, math.rad(90), 0))
		end)
		scatter(ctx, NEAR, NEAR + 40, per(ctx, 4), 6, function(cf)
			K.goldHoard(ctx.parent, cf, ctx.rng)
		end)
		scatter(ctx, NEAR, NEAR + 40, per(ctx, 3), 4, function(cf)
			K.nest(ctx.parent, cf)
		end)
		crags(ctx, per(ctx, 10), NumberRange.new(24, 44), Color3.fromRGB(72, 38, 42), Enum.Material.Basalt, nil)
		scatter(ctx, NEAR - 2, FAR, per(ctx, 26), 4, function(cf)
			spire(ctx.parent, cf.Position, ctx.rng:NextNumber(0.9, 1.4), ctx.rng)
		end)
	end,
}

-- The far ring of mountains for each world.
type Range = { color: Color3, material: Enum.Material, cap: Color3?, lavaCaps: boolean }
local RANGES: { [string]: Range } = {
	main = { color = Color3.fromRGB(118, 132, 122), material = Enum.Material.Slate, cap = SNOW, lavaCaps = false },
	frost = { color = Color3.fromRGB(196, 212, 232), material = Enum.Material.Glacier, cap = SNOW, lavaCaps = false },
	ember = { color = Color3.fromRGB(58, 42, 42), material = Enum.Material.Basalt, cap = nil, lavaCaps = true },
}

local TOWN_HILLS: { [string]: { color: Color3, material: Enum.Material } } = {
	main = { color = Color3.fromRGB(104, 172, 80), material = Enum.Material.Grass },
	frost = { color = SNOW_HILLS, material = Enum.Material.Snow },
	ember = { color = Color3.fromRGB(70, 56, 56), material = Enum.Material.Basalt },
}

-- One slice of the ground ring: the exact shape between two angles and two
-- distances (a rectangle plus a wedge each side), so neighbouring slices meet
-- edge to edge and never overlap (overlapping floors flicker).
local function groundSlice(parent: Instance, center: Vector3, a0: number, a1: number, r0: number, r1: number, color: Color3)
	local half = (a1 - a0) / 2
	local mid = a0 + half
	local out = Vector3.new(math.cos(mid), 0, math.sin(mid))
	local right = Vector3.new(-out.Z, 0, out.X)
	local w0, d0 = r0 * math.sin(half), r0 * math.cos(half)
	local w1, d1 = r1 * math.sin(half), r1 * math.cos(half)
	local t = 4
	local base = center + out * (d0 + d1) / 2 - Vector3.new(0, t / 2, 0)
	local rect = K.block(parent, CFrame.fromMatrix(base, right, Vector3.yAxis), Vector3.new(w0 * 2, t, d1 - d0), color, Enum.Material.SmoothPlastic, { CastShadow = false })
	rect.Name = "Ground"
	for _, side in { -1, 1 } do
		local y = right * side
		local x = y:Cross(out)
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Ground"
		wedge.Anchored = true
		wedge.Size = Vector3.new(t, w1 - w0, d1 - d0)
		wedge.CFrame = CFrame.fromMatrix(base + y * (w0 + w1) / 2, x, y, out)
		wedge.Color = color
		wedge.Material = Enum.Material.SmoothPlastic
		wedge.CastShadow = false
		wedge.TopSurface = Enum.SurfaceType.Smooth
		wedge.BottomSurface = Enum.SurfaceType.Smooth
		wedge.Parent = parent
	end
end

-- The sector's ground, from the world's ground disc out under the mountains.
local function ground(ctx: Ctx, color: Color3)
	local n = math.ceil((ctx.to - ctx.from) / math.rad(4))
	local step = (ctx.to - ctx.from) / n
	for i = 0, n - 1 do
		local a = ctx.from + i * step
		groundSlice(ctx.parent, ctx.center, a, a + step, NEAR - 4, NEAR + 130, color)
		groundSlice(ctx.parent, ctx.center, a, a + step, NEAR + 130, NEAR + 400, color)
	end
end

-- Builds the backdrop round one world. `sectors` are the directions to dress
-- (each gets the arc of directions closer to it than to any other).
function Backdrop.build(parent: Instance, realmId: string, sectors: { Sector }, worldGround: Color3, rng: Random)
	local center = Places.CENTERS[realmId]
	local folder = Instance.new("Folder")
	folder.Name = if realmId == "main" then "Backdrop" else realmId:upper() .. "_BACKDROP"
	folder.Parent = parent

	local sorted = table.clone(sectors)
	table.sort(sorted, function(a, b)
		return a.angle < b.angle
	end)
	for i, sector in sorted do
		local prev = sorted[if i == 1 then #sorted else i - 1].angle
		local nextAngle = sorted[if i == #sorted then 1 else i + 1].angle
		if i == 1 then
			prev -= math.pi * 2
		end
		if i == #sorted then
			nextAngle += math.pi * 2
		end
		local ctx: Ctx = {
			parent = K.model(folder, sector.kind),
			center = center,
			from = (prev + sector.angle) / 2,
			to = (sector.angle + nextAngle) / 2,
			rng = rng,
			realm = realmId,
		}
		local kind = KINDS[sector.kind]
		ground(ctx, kind.ground or worldGround)
		kind.fill(ctx)
		-- Rolling hills behind the props
		local hills: { color: Color3, material: Enum.Material }? = kind.hills and { color = kind.hills, material = kind.hillMaterial or Enum.Material.Grass } or (sector.kind == "town" and TOWN_HILLS[realmId]) or nil
		if hills then
			local step = 50 / (FAR + 45)
			local a = ctx.from + step / 2
			while a < ctx.to do
				local at = polar(center, a, FAR + rng:NextNumber(30, 60))
				hill(ctx.parent, at, rng:NextNumber(70, 110), rng:NextNumber(16, 34), hills.color:Lerp(INK, rng:NextNumber(0, 0.08)), hills.material)
				a += step
			end
		end
	end

	-- Mountains all the way round close off the horizon
	local range = RANGES[realmId] or RANGES.main
	local mountains = K.model(folder, "Mountains")
	for row, ring in { { dist = FAR + 120, n = 30, size = NumberRange.new(110, 150), height = NumberRange.new(110, 170) }, { dist = FAR + 175, n = 30, size = NumberRange.new(130, 170), height = NumberRange.new(160, 230) } } do
		for i = 1, ring.n do
			local a = (i + (row - 1) * 0.5) / ring.n * math.pi * 2 + rng:NextNumber(-0.04, 0.04)
			local at = polar(center, a, ring.dist + rng:NextNumber(-15, 15))
			local cap = range.cap
			if range.lavaCaps then
				cap = if i % 4 == 0 then LAVA else nil
			end
			peak(mountains, at, rng:NextNumber(ring.size.Min, ring.size.Max), rng:NextNumber(ring.height.Min, ring.height.Max), range.color:Lerp(INK, rng:NextNumber(0, 0.12)), range.material, cap, rng)
		end
	end

	-- Scenery only: nothing past the walls collides or gets in the way, and
	-- the distant pieces don't cast shadows.
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			if ((d.Position - center) * Vector3.new(1, 0, 1)).Magnitude > FAR + 20 then
				d.CastShadow = false
			end
		end
	end
end

return Backdrop
