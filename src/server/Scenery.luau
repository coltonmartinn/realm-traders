--!strict
-- Set dressing for each gathering zone, themed on what you gather there: a
-- barn and tractor at the Farm, a mine entrance and ore cart at the Mine, a
-- dragon's bones in the Dragon's Lair... Big buildings stand just outside the
-- back of the fence and claim their ground on the map (Layout); props inside
-- the fence take a spot in the zone, so nothing overlaps anything else and
-- gathering nodes are placed around them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)
local Layout = require(script.Parent.Layout)

-- How a decorator places things. `inside` takes a free spot inside the zone
-- (false if something is already there); `outside` claims ground on the map
-- for a building past the fence (false if it's taken).
export type Context = {
	inside: (position: Vector3, radius: number) -> boolean,
	outside: (position: Vector3, radius: number) -> boolean,
}
export type Decorator = (parent: Instance, place: Places.Place, rng: Random, ctx: Context) -> ()

local Scenery = {}

local INK = Color3.fromRGB(30, 34, 64)
local WOOD = Color3.fromRGB(150, 104, 66)
local WOOD_DARK = Color3.fromRGB(110, 74, 48)
local WHITE = Color3.fromRGB(250, 246, 236)
local SNOW = Color3.fromRGB(248, 252, 255)
local METAL = Color3.fromRGB(120, 124, 136)
local GOLD = Color3.fromRGB(255, 200, 60)

local function block(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = cf
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function ball(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = block(parent, cf, size, color, material, props)
	p.Shape = Enum.PartType.Ball
	p.Size = size
	return p
end

-- A cylinder standing upright.
local function post(parent: Instance, cf: CFrame, diameter: number, height: number, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = block(parent, cf * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(height, diameter, diameter), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A cylinder lying along the local X axis.
local function log(parent: Instance, cf: CFrame, diameter: number, length: number, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = block(parent, cf, Vector3.new(length, diameter, diameter), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function sign(board: BasePart, text: string, color: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = board
end

local function glow(parent: BasePart, color: Color3, range: number, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 1.5
	light.Parent = parent
end

local function smoke(parent: BasePart, color: Color3, rate: number?)
	local e = Instance.new("ParticleEmitter")
	e.Rate = rate or 4
	e.Lifetime = NumberRange.new(2.5, 4)
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(color)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
end

-- A spot `dist` studs from the zone center, away from the plaza, shifted
-- `lateral` studs sideways, facing the zone's center (front is -Z).
local function spot(place: Places.Place, dist: number, lateral: number): CFrame
	local away = -Places.towardHub(place)
	local side = Vector3.new(-away.Z, 0, away.X)
	local pos = place.center + away * dist + side * lateral
	return CFrame.lookAt(pos, Vector3.new(place.center.X, pos.Y, place.center.Z))
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Buildings and props ------------------------------------------------------------------

-- Gable roof over a w x d footprint with its eaves at height h.
local function roof(m: Model, cf: CFrame, w: number, d: number, h: number, color: Color3, material: Enum.Material?)
	local half = d / 2 + 0.8
	local slope = math.rad(32)
	local length = half / math.cos(slope)
	for _, s in { -1, 1 } do
		block(m, cf * CFrame.new(0, h + math.tan(slope) * half / 2, s * half / 2) * CFrame.Angles(s * slope, 0, 0), Vector3.new(w + 1.6, 0.6, length + 0.4), color, material)
	end
	-- Gable ends (the ridge runs along X), stepped to fill the triangle
	local rise = math.tan(slope) * d / 2
	for i = 1, 4 do
		local frac = 1 - (i - 0.5) / 4
		for _, x in { -w / 2, w / 2 } do
			block(m, cf * CFrame.new(x, h + (i - 0.5) * rise / 4, 0), Vector3.new(0.5, rise / 4, d * frac), color:Lerp(INK, 0.15), material)
		end
	end
end

local function barn(parent: Instance, cf: CFrame)
	local m = model(parent, "Barn")
	local red = Color3.fromRGB(196, 52, 46)
	local w, d, h = 16, 12, 9
	block(m, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), red, Enum.Material.WoodPlanks)
	-- White corner trim
	for _, x in { -w / 2, w / 2 } do
		for _, z in { -d / 2, d / 2 } do
			block(m, cf * CFrame.new(x, h / 2, z), Vector3.new(0.7, h, 0.7), WHITE)
		end
	end
	roof(m, cf, w, d, h, Color3.fromRGB(90, 70, 70), Enum.Material.Slate)
	-- Big doors with white X braces, facing the field
	local front = cf * CFrame.new(0, 0, -d / 2 - 0.15)
	block(m, front * CFrame.new(0, 3.6, 0), Vector3.new(7.4, 7.2, 0.3), WHITE)
	for _, x in { -1.8, 1.8 } do
		local door = front * CFrame.new(x, 3.5, -0.1)
		block(m, door, Vector3.new(3.4, 6.6, 0.3), Color3.fromRGB(160, 40, 36), Enum.Material.WoodPlanks)
		for _, a in { 1, -1 } do
			block(m, door * CFrame.new(0, 0, -0.2) * CFrame.Angles(0, 0, a * math.atan2(6.6, 3.4)), Vector3.new(0.4, 7.2, 0.15), WHITE)
		end
	end
	-- Hay loft window
	block(m, front * CFrame.new(0, h + 0.8, 0), Vector3.new(3, 2.6, 0.3), WHITE)
	block(m, front * CFrame.new(0, h + 0.8, -0.1), Vector3.new(2.2, 1.8, 0.3), Color3.fromRGB(240, 210, 110), Enum.Material.Grass)
	-- Weathervane
	local top = cf * CFrame.new(0, h + 4.6, 0)
	block(m, top, Vector3.new(0.2, 2.4, 0.2), INK)
	block(m, top * CFrame.new(0, 1, 0), Vector3.new(1.6, 0.5, 0.1), INK)
end

local function silo(parent: Instance, cf: CFrame)
	local m = model(parent, "Silo")
	post(m, cf * CFrame.new(0, 8, 0), 6, 16, Color3.fromRGB(176, 186, 200), Enum.Material.Metal)
	for y = 2, 14, 4 do
		post(m, cf * CFrame.new(0, y, 0), 6.2, 0.3, METAL, Enum.Material.Metal)
	end
	ball(m, cf * CFrame.new(0, 16, 0), Vector3.new(6, 4, 6), Color3.fromRGB(196, 52, 46), Enum.Material.Metal)
end

local function scarecrow(parent: Instance, cf: CFrame)
	local m = model(parent, "Scarecrow")
	block(m, cf * CFrame.new(0, 3, 0), Vector3.new(0.4, 6, 0.4), WOOD_DARK, Enum.Material.Wood)
	block(m, cf * CFrame.new(0, 4.4, 0), Vector3.new(4.6, 0.35, 0.35), WOOD_DARK, Enum.Material.Wood)
	block(m, cf * CFrame.new(0, 4, 0), Vector3.new(1.8, 2, 0.9), Color3.fromRGB(90, 130, 200), Enum.Material.Fabric)
	ball(m, cf * CFrame.new(0, 5.8, 0), Vector3.new(1.5, 1.5, 1.5), Color3.fromRGB(220, 190, 130), Enum.Material.Fabric)
	post(m, cf * CFrame.new(0, 6.6, 0), 2.6, 0.2, Color3.fromRGB(200, 160, 70), Enum.Material.Grass)
	post(m, cf * CFrame.new(0, 7, 0), 1.3, 0.8, Color3.fromRGB(200, 160, 70), Enum.Material.Grass)
	for _, x in { -2.4, 2.4 } do
		block(m, cf * CFrame.new(x, 4.2, 0), Vector3.new(0.3, 0.8, 0.3), Color3.fromRGB(230, 200, 90), Enum.Material.Grass)
	end
end

local function tractor(parent: Instance, cf: CFrame)
	local m = model(parent, "Tractor")
	local green = Color3.fromRGB(60, 150, 70)
	block(m, cf * CFrame.new(0, 2.2, -1), Vector3.new(2.4, 1.8, 4), green)
	block(m, cf * CFrame.new(0, 2.6, 1.6), Vector3.new(2.6, 2.6, 1.6), green)
	block(m, cf * CFrame.new(0, 4.4, 1.6), Vector3.new(2.4, 0.2, 2), Color3.fromRGB(240, 220, 80))
	for _, x in { -1.1, 1.1 } do
		block(m, cf * CFrame.new(x, 3.4, 1.6), Vector3.new(0.2, 2, 0.2), INK)
	end
	post(m, cf * CFrame.new(0.6, 3.6, -2.4), 0.3, 1.6, INK, Enum.Material.Metal)
	for _, x in { -1.6, 1.6 } do
		log(m, cf * CFrame.new(x, 1.6, 1.6), 3.2, 0.9, INK)
		log(m, cf * CFrame.new(x, 1.6, 1.6), 1.6, 1, Color3.fromRGB(240, 220, 80))
		log(m, cf * CFrame.new(x * 0.8, 0.9, -2.4), 1.8, 0.6, INK)
	end
end

local function trough(parent: Instance, cf: CFrame)
	local m = model(parent, "Trough")
	block(m, cf * CFrame.new(0, 0.7, 0), Vector3.new(4, 1.4, 1.6), WOOD, Enum.Material.WoodPlanks)
	block(m, cf * CFrame.new(0, 1.35, 0), Vector3.new(3.6, 0.1, 1.2), Color3.fromRGB(80, 170, 240), Enum.Material.Glass, { Transparency = 0.2 })
end

local function logCabin(parent: Instance, cf: CFrame, roofColor: Color3, logColor: Color3, snowy: boolean)
	local m = model(parent, "Cabin")
	local w, d = 12, 10
	for i = 0, 6 do
		local y = 0.6 + i * 1.1
		log(m, cf * CFrame.new(0, y, -d / 2), 1.2, w + 1, logColor, Enum.Material.Wood)
		log(m, cf * CFrame.new(0, y, d / 2), 1.2, w + 1, logColor, Enum.Material.Wood)
		log(m, cf * CFrame.new(-w / 2, y + 0.55, 0) * CFrame.Angles(0, math.rad(90), 0), 1.2, d + 1, logColor:Lerp(INK, 0.08), Enum.Material.Wood)
		log(m, cf * CFrame.new(w / 2, y + 0.55, 0) * CFrame.Angles(0, math.rad(90), 0), 1.2, d + 1, logColor:Lerp(INK, 0.08), Enum.Material.Wood)
	end
	block(m, cf * CFrame.new(0, 4, 0), Vector3.new(w - 1, 8, d - 1), logColor:Lerp(INK, 0.3), Enum.Material.Wood)
	roof(m, cf, w, d, 8, roofColor, Enum.Material.WoodPlanks)
	if snowy then
		for _, s in { -1, 1 } do
			block(m, cf * CFrame.new(0, 8 + 2.35, s * 3.3) * CFrame.Angles(s * math.rad(32), 0, 0), Vector3.new(w + 1.8, 0.5, 7.4), SNOW, Enum.Material.Snow)
		end
	end
	-- Door, window with warm light, chimney with smoke
	local front = cf * CFrame.new(0, 0, -d / 2 - 0.7)
	block(m, front * CFrame.new(-2, 2.6, 0), Vector3.new(2.6, 5, 0.3), WOOD_DARK, Enum.Material.WoodPlanks)
	local window = block(m, front * CFrame.new(2.8, 4, 0), Vector3.new(2.4, 2, 0.3), Color3.fromRGB(255, 210, 120), Enum.Material.Neon)
	glow(window, Color3.fromRGB(255, 200, 120), 12, 1)
	block(m, front * CFrame.new(2.8, 4, -0.1), Vector3.new(0.2, 2.2, 0.2), WOOD_DARK)
	local chimney = block(m, cf * CFrame.new(w / 2 - 2, 11, 1.5), Vector3.new(1.8, 5, 1.8), Color3.fromRGB(140, 130, 130), Enum.Material.Brick)
	smoke(chimney, Color3.fromRGB(220, 220, 225), 3)
end

local function logPile(parent: Instance, cf: CFrame, color: Color3)
	local m = model(parent, "LogPile")
	for row = 0, 2 do
		for i = 0, 2 - row do
			log(m, cf * CFrame.new(0, 0.8 + row * 1.35, (i - (2 - row) / 2) * 1.55) , 1.5, 6, color, Enum.Material.Wood)
		end
	end
end

local function chopStump(parent: Instance, cf: CFrame)
	local m = model(parent, "ChoppingStump")
	post(m, cf * CFrame.new(0, 0.8, 0), 2.4, 1.6, WOOD, Enum.Material.Wood)
	post(m, cf * CFrame.new(0, 1.62, 0), 2.1, 0.05, Color3.fromRGB(220, 180, 120), Enum.Material.Wood)
	local axe = cf * CFrame.new(0.3, 2.6, 0) * CFrame.Angles(0, 0, math.rad(-25))
	block(m, axe, Vector3.new(0.25, 2.2, 0.25), WOOD_DARK)
	block(m, axe * CFrame.new(0.4, -0.9, 0), Vector3.new(0.9, 0.7, 0.15), METAL, Enum.Material.Metal)
end

local function sawhorse(parent: Instance, cf: CFrame)
	local m = model(parent, "Sawhorse")
	block(m, cf * CFrame.new(0, 2, 0), Vector3.new(4, 0.4, 0.4), WOOD)
	for _, x in { -1.6, 1.6 } do
		for _, a in { 1, -1 } do
			block(m, cf * CFrame.new(x, 1, a * 0.4) * CFrame.Angles(a * math.rad(20), 0, 0), Vector3.new(0.3, 2.2, 0.3), WOOD_DARK)
		end
	end
	log(m, cf * CFrame.new(0, 2.8, 0), 1.2, 5, WOOD, Enum.Material.Wood)
end

local function rails(parent: Instance, from: CFrame, length: number)
	local m = model(parent, "Rails")
	for _, x in { -1, 1 } do
		block(m, from * CFrame.new(x, 0.25, -length / 2), Vector3.new(0.25, 0.25, length), METAL, Enum.Material.Metal)
	end
	for z = 1, length - 1, 2 do
		block(m, from * CFrame.new(0, 0.1, -z), Vector3.new(3, 0.2, 0.6), WOOD_DARK, Enum.Material.Wood)
	end
end

local function minecart(parent: Instance, cf: CFrame, load: Color3, shiny: boolean)
	local m = model(parent, "Minecart")
	block(m, cf * CFrame.new(0, 1.6, 0), Vector3.new(2.6, 1.6, 3.4), Color3.fromRGB(90, 90, 100), Enum.Material.Metal)
	for i = 1, 5 do
		local chunk = block(m, cf * CFrame.new((i % 3 - 1) * 0.7, 2.5, (i - 3) * 0.55), Vector3.new(0.9, 0.8, 0.9), load, if shiny then Enum.Material.Neon else Enum.Material.Slate)
		chunk.Orientation = Vector3.new(i * 20, i * 33, 0)
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			log(m, cf * CFrame.new(x * 1.3, 0.6, z * 1.1), 1, 0.3, INK, Enum.Material.Metal)
		end
	end
end

local function barrel(parent: Instance, cf: CFrame, color: Color3?)
	local m = model(parent, "Barrel")
	post(m, cf * CFrame.new(0, 1.2, 0), 1.8, 2.4, color or WOOD, Enum.Material.WoodPlanks)
	for _, y in { 0.5, 1.9 } do
		post(m, cf * CFrame.new(0, y, 0), 1.9, 0.2, INK, Enum.Material.Metal)
	end
end

local function tntCrate(parent: Instance, cf: CFrame)
	local box = block(parent, cf * CFrame.new(0, 1, 0), Vector3.new(2, 2, 2), Color3.fromRGB(210, 50, 50), Enum.Material.WoodPlanks)
	box.Name = "TNT"
	sign(box, "TNT")
end

local function mineEntrance(parent: Instance, cf: CFrame, rock: Color3, rng: Random)
	local m = model(parent, "MineEntrance")
	-- Rocky hill
	for i = 1, 9 do
		local a = (i / 9) * math.pi
		local s = rng:NextNumber(8, 12)
		block(m, cf * CFrame.new(math.cos(a) * 10, s / 2 - 1 + math.sin(a) * 4, 4 + rng:NextNumber(-1, 2)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, math.pi), rng:NextNumber(-0.2, 0.2)), Vector3.new(s, s, s), rock, Enum.Material.Slate)
	end
	-- Timber frame and dark tunnel
	block(m, cf * CFrame.new(0, 3.5, 0.6), Vector3.new(6, 7, 2), Color3.fromRGB(12, 10, 14), Enum.Material.SmoothPlastic)
	for _, x in { -3.4, 3.4 } do
		block(m, cf * CFrame.new(x, 3.8, -0.4), Vector3.new(0.9, 7.6, 0.9), WOOD_DARK, Enum.Material.Wood)
	end
	block(m, cf * CFrame.new(0, 7.8, -0.4), Vector3.new(8, 0.9, 1), WOOD_DARK, Enum.Material.Wood)
	local board = block(m, cf * CFrame.new(0, 9.2, -0.6), Vector3.new(6, 1.6, 0.3), WOOD)
	sign(board, "⛏️ MINE")
	local lantern = block(m, cf * CFrame.new(3.4, 6.4, -1.1), Vector3.new(0.6, 0.8, 0.6), Color3.fromRGB(255, 200, 100), Enum.Material.Neon)
	glow(lantern, Color3.fromRGB(255, 190, 110), 14, 1.2)
end

local function crane(parent: Instance, cf: CFrame)
	local m = model(parent, "Crane")
	for _, x in { -2.5, 2.5 } do
		block(m, cf * CFrame.new(x, 6, 0) * CFrame.Angles(0, 0, x > 0 and math.rad(10) or math.rad(-10)), Vector3.new(0.7, 12, 0.7), WOOD_DARK, Enum.Material.Wood)
	end
	block(m, cf * CFrame.new(0, 11.8, 0), Vector3.new(6, 0.7, 0.7), WOOD_DARK, Enum.Material.Wood)
	block(m, cf * CFrame.new(0, 11.8, -3), Vector3.new(0.7, 0.7, 7), WOOD, Enum.Material.Wood)
	block(m, cf * CFrame.new(0, 9, -6), Vector3.new(0.15, 5.6, 0.15), Color3.fromRGB(200, 180, 140), Enum.Material.Fabric)
	block(m, cf * CFrame.new(0, 5.6, -6), Vector3.new(2, 1.6, 2), Color3.fromRGB(190, 186, 176), Enum.Material.Slate)
end

local function stoneBlocks(parent: Instance, cf: CFrame, rng: Random)
	local m = model(parent, "CutStone")
	for i = 0, 2 do
		for j = 0, 1 - (i // 2) do
			block(m, cf * CFrame.new(i * 2.2 - 2.2, 0.9 + j * 1.8, 0) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0), Vector3.new(2, 1.7, 2), Color3.fromRGB(205, 200, 190), Enum.Material.Slate)
		end
	end
end

-- A wall of rocks around the back of a zone (one model; its rocks are meant
-- to touch). Rocks whose ground is already taken are left out.
local function cliffs(parent: Instance, place: Places.Place, color: Color3, material: Enum.Material, rng: Random, from: number, to: number, height: NumberRange, extra: ((Part) -> ())?)
	local away = -Places.towardHub(place)
	local wall = model(parent, "Cliffs")
	for i = from, to do
		local a = math.atan2(away.Z, away.X) + i * 0.28
		local at = place.center + Vector3.new(math.cos(a), 0, math.sin(a)) * (place.radius + 7)
		if not Layout.free(at, 4.5, 0) then
			continue
		end
		local h = rng:NextNumber(height.Min, height.Max)
		local rock = block(wall, CFrame.new(at + Vector3.new(0, h / 2 - 1, 0)) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, math.pi), rng:NextNumber(-0.15, 0.15)), Vector3.new(rng:NextNumber(7, 10), h, rng:NextNumber(6, 9)), color, material)
		rock.Name = "Cliff"
		if extra then
			extra(rock)
		end
	end
	-- Claimed after placing them all, so neighbouring rocks can touch
	for _, rock in wall:GetChildren() do
		if rock.Name == "Cliff" then
			Layout.claim((rock :: BasePart).Position, 4.5)
		end
	end
end

local function crystalCluster(parent: Instance, cf: CFrame, color: Color3, scale: number, rng: Random)
	local m = model(parent, "CrystalCluster")
	for i = 1, 5 do
		local h = rng:NextNumber(2, 5) * scale
		block(m, cf * CFrame.new(rng:NextNumber(-1, 1) * scale, h / 2, rng:NextNumber(-1, 1) * scale) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, math.pi), rng:NextNumber(-0.5, 0.5)), Vector3.new(0.9, h, 0.9) * Vector3.new(scale, 1, scale), color:Lerp(Color3.new(1, 1, 1), (i % 2) * 0.3), Enum.Material.Neon, { CanCollide = false })
	end
	glow(m:FindFirstChildWhichIsA("BasePart") :: BasePart, color, 12, 1.2)
end

local function stalagmite(parent: Instance, cf: CFrame, color: Color3, rng: Random)
	local h = rng:NextNumber(3, 6)
	for i = 0, 2 do
		local s = (3 - i) * 0.7
		block(parent, cf * CFrame.new(0, i * h / 3 + h / 6, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Vector3.new(s, h / 3, s), color, Enum.Material.Slate)
	end
end

local function chest(parent: Instance, cf: CFrame)
	local m = model(parent, "TreasureChest")
	block(m, cf * CFrame.new(0, 0.9, 0), Vector3.new(3, 1.8, 2), WOOD, Enum.Material.WoodPlanks)
	block(m, cf * CFrame.new(0, 2.2, 0.9) * CFrame.Angles(math.rad(-60), 0, 0), Vector3.new(3, 0.4, 2), WOOD_DARK, Enum.Material.WoodPlanks)
	for i = 1, 6 do
		ball(m, cf * CFrame.new((i % 3 - 1) * 0.8, 1.9, (i // 3 - 0.5) * 0.6), Vector3.new(0.7, 0.4, 0.7), GOLD, Enum.Material.Neon)
	end
	for _, x in { -1.2, 1.2 } do
		block(m, cf * CFrame.new(x, 0.9, 0), Vector3.new(0.2, 1.9, 2.1), GOLD, Enum.Material.Metal)
	end
end

local function snowman(parent: Instance, cf: CFrame)
	local m = model(parent, "Snowman")
	ball(m, cf * CFrame.new(0, 1.3, 0), Vector3.new(2.8, 2.6, 2.8), SNOW, Enum.Material.Snow)
	ball(m, cf * CFrame.new(0, 3.2, 0), Vector3.new(2, 1.9, 2), SNOW, Enum.Material.Snow)
	ball(m, cf * CFrame.new(0, 4.6, 0), Vector3.new(1.4, 1.4, 1.4), SNOW, Enum.Material.Snow)
	local nose = block(m, cf * CFrame.new(0, 4.6, -0.95) * CFrame.Angles(math.rad(90), 0, 0), Vector3.new(0.25, 0.7, 0.25), Color3.fromRGB(250, 140, 40))
	nose.Shape = Enum.PartType.Cylinder
	for _, x in { -0.25, 0.25 } do
		ball(m, cf * CFrame.new(x, 4.85, -0.62), Vector3.new(0.18, 0.18, 0.18), INK)
	end
	post(m, cf * CFrame.new(0, 5.3, 0), 1.4, 0.15, INK)
	post(m, cf * CFrame.new(0, 5.8, 0), 0.95, 1, INK)
	block(m, cf * CFrame.new(0, 3.9, 0), Vector3.new(1.6, 0.35, 1.6), Color3.fromRGB(220, 60, 70), Enum.Material.Fabric)
	for _, x in { -1, 1 } do
		block(m, cf * CFrame.new(x * 1.6, 3.6, 0) * CFrame.Angles(0, 0, x * math.rad(-35)), Vector3.new(1.8, 0.15, 0.15), WOOD_DARK)
	end
end

local function sled(parent: Instance, cf: CFrame)
	local m = model(parent, "Sled")
	block(m, cf * CFrame.new(0, 0.9, 0), Vector3.new(2.4, 0.3, 4.4), Color3.fromRGB(196, 52, 46), Enum.Material.WoodPlanks)
	for _, x in { -1.1, 1.1 } do
		block(m, cf * CFrame.new(x, 0.35, 0), Vector3.new(0.2, 0.2, 4.8), METAL, Enum.Material.Metal)
		block(m, cf * CFrame.new(x, 0.6, -2.3) * CFrame.Angles(math.rad(-40), 0, 0), Vector3.new(0.2, 0.2, 0.8), METAL, Enum.Material.Metal)
	end
	for i = 0, 1 do
		log(m, cf * CFrame.new(0, 1.6 + i * 0.9, (i - 0.5) * 0.6) * CFrame.Angles(0, math.rad(90), 0), 0.9, 3.6, Color3.fromRGB(96, 66, 46), Enum.Material.Wood)
	end
end

local function iceShanty(parent: Instance, cf: CFrame)
	local m = model(parent, "IceShanty")
	block(m, cf * CFrame.new(0, 2.5, 0), Vector3.new(6, 5, 5), Color3.fromRGB(70, 120, 190), Enum.Material.WoodPlanks)
	roof(m, cf, 6, 5, 5, Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
	block(m, cf * CFrame.new(-1, 2, -2.6), Vector3.new(1.8, 3.6, 0.2), WOOD_DARK, Enum.Material.WoodPlanks)
	local window = block(m, cf * CFrame.new(1.5, 3, -2.6), Vector3.new(1.4, 1.2, 0.2), Color3.fromRGB(255, 220, 140), Enum.Material.Neon)
	glow(window, Color3.fromRGB(255, 210, 140), 10, 0.8)
	local pipe = post(m, cf * CFrame.new(2, 6.6, 1), 0.6, 2.6, METAL, Enum.Material.Metal)
	smoke(pipe, Color3.fromRGB(230, 230, 235), 2)
end

local function igloo(parent: Instance, cf: CFrame)
	local m = model(parent, "Igloo")
	ball(m, cf * CFrame.new(0, 0, 0), Vector3.new(9, 8, 9), SNOW, Enum.Material.Ice)
	block(m, cf * CFrame.new(0, 1.4, -4.6), Vector3.new(3, 2.8, 3), SNOW, Enum.Material.Ice)
	block(m, cf * CFrame.new(0, 1.2, -6.15), Vector3.new(2, 2.2, 0.2), Color3.fromRGB(40, 60, 90))
	for i = 1, 3 do
		block(m, cf * CFrame.new(0, i * 1.1, 0), Vector3.new(9.1 - i * 1.5, 0.08, 9.1 - i * 1.5) * Vector3.new(1, 1, 1), Color3.fromRGB(205, 225, 240), Enum.Material.Ice, { CanCollide = false, Transparency = 0.4 })
	end
end

local function pier(parent: Instance, cf: CFrame)
	local m = model(parent, "Pier")
	block(m, cf * CFrame.new(0, 0.6, 0), Vector3.new(4, 0.4, 12), WOOD, Enum.Material.WoodPlanks)
	for _, x in { -1.8, 1.8 } do
		for z = -5, 5, 5 do
			post(m, cf * CFrame.new(x, 0.4, z), 0.6, 1.6, WOOD_DARK, Enum.Material.Wood)
		end
	end
	barrel(m, cf * CFrame.new(1, 0.8, 4.2), Color3.fromRGB(110, 150, 200))
	for i = 1, 3 do
		local fish = ball(m, cf * CFrame.new(1 + (i - 2) * 0.5, 3.3, 4.2), Vector3.new(0.5, 0.4, 1.1), Color3.fromRGB(110, 180, 230))
		fish.Orientation = Vector3.new(0, i * 50, 0)
	end
end

local function icicleArch(parent: Instance, cf: CFrame)
	local m = model(parent, "IceArch")
	local ice = Color3.fromRGB(170, 220, 250)
	for i = 0, 8 do
		local a = i / 8 * math.pi
		block(m, cf * CFrame.new(math.cos(a) * 7, math.sin(a) * 9 + 1, 0) * CFrame.Angles(0, 0, a), Vector3.new(2.4, 2.6, 2.4), ice, Enum.Material.Ice, { Transparency = 0.15 })
		if i > 0 and i < 8 then
			block(m, cf * CFrame.new(math.cos(a) * 6.4, math.sin(a) * 9 - 0.8, 0), Vector3.new(0.4, 2, 0.4), Color3.fromRGB(220, 245, 255), Enum.Material.Glass, { CanCollide = false, Transparency = 0.2 })
		end
	end
end

local function kiln(parent: Instance, cf: CFrame)
	local m = model(parent, "Kiln")
	ball(m, cf * CFrame.new(0, 1, 0), Vector3.new(7, 7, 7), Color3.fromRGB(120, 86, 70), Enum.Material.Brick)
	local mouth = block(m, cf * CFrame.new(0, 1.3, -3.2), Vector3.new(2.4, 2, 0.6), Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
	glow(mouth, Color3.fromRGB(255, 120, 40), 14, 2)
	local vent = post(m, cf * CFrame.new(0, 5, 0), 1.2, 1.4, Color3.fromRGB(80, 60, 52), Enum.Material.Brick)
	smoke(vent, Color3.fromRGB(70, 66, 70), 5)
end

local function burntStump(parent: Instance, cf: CFrame, rng: Random)
	local h = rng:NextNumber(1.5, 4)
	post(parent, cf * CFrame.new(0, h / 2, 0), rng:NextNumber(1.4, 2.2), h, Color3.fromRGB(40, 34, 34), Enum.Material.Wood)
	local ember = ball(parent, cf * CFrame.new(0.3, h, 0), Vector3.new(0.6, 0.4, 0.6), Color3.fromRGB(255, 110, 40), Enum.Material.Neon)
	ember.CanCollide = false
end

local function lavaRiver(parent: Instance, from: CFrame, length: number)
	local lava = block(parent, from * CFrame.new(0, 0.2, 0), Vector3.new(5, 0.3, length), Color3.fromRGB(255, 100, 30), Enum.Material.Neon, { CanCollide = false, CastShadow = false })
	lava.Name = "LavaRiver"
	glow(lava, Color3.fromRGB(255, 110, 40), 20, 1.5)
	for _, x in { -3, 3 } do
		block(parent, from * CFrame.new(x, 0.5, 0), Vector3.new(1.4, 1, length), Color3.fromRGB(50, 36, 34), Enum.Material.Basalt)
	end
end

local function lavaFall(parent: Instance, cf: CFrame)
	local fall = block(parent, cf * CFrame.new(0, 7, 0), Vector3.new(3, 14, 1), Color3.fromRGB(255, 120, 30), Enum.Material.Neon, { CanCollide = false })
	glow(fall, Color3.fromRGB(255, 120, 40), 24, 2)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 12
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(4, 8)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Size = NumberSequence.new(0.4, 0)
	e.Color = ColorSequence.new(Color3.fromRGB(255, 180, 60))
	e.LightEmission = 1
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = block(parent, cf * CFrame.new(0, 0.2, -1), Vector3.new(4, 0.3, 3), Color3.fromRGB(255, 100, 30), Enum.Material.Neon, { CanCollide = false })
end

local function dragonBones(parent: Instance, cf: CFrame)
	local m = model(parent, "DragonBones")
	local bone = Color3.fromRGB(235, 225, 200)
	-- Spine
	for i = 0, 10 do
		block(m, cf * CFrame.new(0, 1 + math.sin(i / 10 * math.pi) * 2, -10 + i * 2), Vector3.new(1.2, 1.2, 1.6), bone, Enum.Material.Marble)
	end
	-- Ribs: arches over the spine
	for i = 1, 6 do
		local z = -7 + i * 2.2
		local r = 5.5 - math.abs(i - 3.5) * 0.6
		for _, s in { -1, 1 } do
			for k = 0, 4 do
				local a = k / 4 * math.pi / 2
				block(m, cf * CFrame.new(s * math.cos(a) * r, 1 + math.sin(a) * r * 1.2, z) * CFrame.Angles(0, 0, s * a), Vector3.new(0.6, 1.8, 0.6), bone, Enum.Material.Marble)
			end
		end
	end
	-- Skull with glowing eyes
	local skull = cf * CFrame.new(0, 2.6, -13)
	block(m, skull, Vector3.new(4, 3, 4.6), bone, Enum.Material.Marble)
	block(m, skull * CFrame.new(0, -0.6, -3.4), Vector3.new(2.6, 1.6, 3), bone, Enum.Material.Marble)
	for _, x in { -1.1, 1.1 } do
		local eye = block(m, skull * CFrame.new(x, 0.5, -2.31), Vector3.new(0.9, 0.7, 0.1), Color3.fromRGB(255, 80, 60), Enum.Material.Neon)
		glow(eye, Color3.fromRGB(255, 80, 60), 8, 1)
		block(m, skull * CFrame.new(x, 2, 1) * CFrame.Angles(math.rad(-40), 0, x * 0.3), Vector3.new(0.6, 3.4, 0.6), bone, Enum.Material.Marble)
	end
end

local function goldHoard(parent: Instance, cf: CFrame, rng: Random)
	local m = model(parent, "GoldHoard")
	ball(m, cf * CFrame.new(0, 0, 0), Vector3.new(10, 4, 8), GOLD, Enum.Material.Metal)
	for _ = 1, 14 do
		local coin = block(m, cf * CFrame.new(rng:NextNumber(-4, 4), rng:NextNumber(0.8, 2), rng:NextNumber(-3, 3)) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), Vector3.new(0.15, 0.9, 0.9), GOLD, Enum.Material.Neon)
		coin.Shape = Enum.PartType.Cylinder
	end
	chest(m, cf * CFrame.new(3, 1, -2))
	local gem = block(m, cf * CFrame.new(-2, 2.6, 0) * CFrame.Angles(0.5, 0.6, 0), Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(220, 40, 60), Enum.Material.Neon)
	glow(gem, Color3.fromRGB(255, 60, 80), 10, 1)
end

local function nest(parent: Instance, cf: CFrame)
	local m = model(parent, "DragonNest")
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		log(m, cf * CFrame.new(math.cos(a) * 3, 0.6, math.sin(a) * 3) * CFrame.Angles(0, -a + math.rad(90), 0.3), 0.8, 3.6, Color3.fromRGB(70, 50, 40), Enum.Material.Wood)
	end
	local colors = { Color3.fromRGB(200, 50, 60), Color3.fromRGB(240, 150, 50), Color3.fromRGB(150, 60, 200) }
	for i = 1, 3 do
		local egg = ball(m, cf * CFrame.new((i - 2) * 1.3, 1.4, (i % 2) * 0.6), Vector3.new(1.4, 1.9, 1.4), colors[i], Enum.Material.SmoothPlastic)
		egg.Orientation = Vector3.new(0, 0, (i - 2) * 12)
	end
end

-- Zone decorators ----------------------------------------------------------------------

local decorators: { [string]: Decorator } = {}

-- Places an inside prop if its spot is free.
local function inside(ctx: Context, cf: CFrame, r: number, build: (CFrame) -> ())
	if ctx.inside(cf.Position, r) then
		build(cf)
	end
end

-- Places an outside building if its ground is free.
local function outside(ctx: Context, cf: CFrame, r: number, build: (CFrame) -> ())
	if ctx.outside(cf.Position, r) then
		build(cf)
	end
end

-- A few small props at random free spots inside the zone.
local function scatter(ctx: Context, place: Places.Place, rng: Random, count: number, r: number, build: (CFrame) -> ())
	local left = count
	for _ = 1, count * 8 do
		if left <= 0 then
			break
		end
		local cf = spot(place, rng:NextNumber(-place.radius + 6, place.radius - 4), rng:NextNumber(-place.radius + 6, place.radius - 6))
		if ((cf.Position - place.center) * Vector3.new(1, 0, 1)).Magnitude < place.radius - 3 and ctx.inside(cf.Position, r) then
			build(cf)
			left -= 1
		end
	end
end

decorators.forest = function(parent, place, rng, ctx)
	outside(ctx, spot(place, place.radius + 14, 0), 9, function(cf)
		logCabin(parent, cf, Color3.fromRGB(150, 60, 50), Color3.fromRGB(150, 104, 66), false)
	end)
	inside(ctx, spot(place, place.radius - 5, 9), 4.5, function(cf)
		logPile(parent, cf, Color3.fromRGB(150, 104, 66))
	end)
	inside(ctx, spot(place, place.radius - 6, -8), 2, function(cf)
		chopStump(parent, cf)
	end)
	inside(ctx, spot(place, 4, -place.radius + 7), 3, function(cf)
		sawhorse(parent, cf)
	end)
	scatter(ctx, place, rng, 8, 1.8, function(cf)
		local size = rng:NextNumber(2.2, 3.4)
		local bush = model(parent, "Bush")
		ball(bush, cf * CFrame.new(0, size * 0.3, 0), Vector3.one * size, Color3.fromRGB(76, 168, 72):Lerp(Color3.fromRGB(50, 130, 60), rng:NextNumber()), Enum.Material.Grass, { CanCollide = false })
	end)
end

decorators.farm = function(parent, place, rng, ctx)
	outside(ctx, spot(place, place.radius + 15.5, -5), 10.5, function(cf)
		barn(parent, cf)
	end)
	outside(ctx, spot(place, place.radius + 12, 10), 3.5, function(cf)
		silo(parent, cf)
	end)
	inside(ctx, spot(place, 0, 0), 2.5, function(cf)
		scarecrow(parent, cf)
	end)
	inside(ctx, spot(place, place.radius - 6, -10), 4, function(cf)
		tractor(parent, cf * CFrame.Angles(0, math.rad(60), 0))
	end)
	inside(ctx, spot(place, -place.radius + 9, place.radius - 7), 2.5, function(cf)
		trough(parent, cf)
	end)
	scatter(ctx, place, rng, 3, 2, function(cf)
		local bale = model(parent, "HayBale")
		block(bale, cf * CFrame.new(0, 1.1, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Vector3.new(3, 2.2, 2.2), Color3.fromRGB(226, 196, 96), Enum.Material.Fabric)
	end)
end

decorators.quarry = function(parent, place, rng, ctx)
	inside(ctx, spot(place, place.radius - 5, -8), 3.5, function(cf)
		crane(parent, cf)
	end)
	inside(ctx, spot(place, place.radius - 5, 8), 3.5, function(cf)
		stoneBlocks(parent, cf, rng)
	end)
	local start = spot(place, place.radius - 2, 0)
	if ctx.inside((start * CFrame.new(0, 0, 5)).Position, 3.5) then
		rails(parent, start * CFrame.Angles(0, math.rad(180), 0), 10)
		minecart(parent, start * CFrame.new(0, 0, 5), Color3.fromRGB(190, 186, 176), false)
	end
	cliffs(parent, place, Color3.fromRGB(196, 190, 178), Enum.Material.Slate, rng, -4, 4, NumberRange.new(9, 16))
end

decorators.mine = function(parent, place, rng, ctx)
	outside(ctx, spot(place, place.radius + 14, 0), 9, function(cf)
		mineEntrance(parent, cf, Color3.fromRGB(110, 100, 96), rng)
	end)
	local start = spot(place, place.radius - 1, 0)
	if ctx.inside((start * CFrame.new(0, 0, 4)).Position, 4) then
		rails(parent, start * CFrame.Angles(0, math.rad(180), 0), 10)
		minecart(parent, start * CFrame.new(0, 0, 4), Color3.fromRGB(200, 113, 78), false)
	end
	inside(ctx, spot(place, place.radius - 5, -9), 2, function(cf)
		barrel(parent, cf)
	end)
	inside(ctx, spot(place, place.radius - 5, 9), 3, function(cf)
		barrel(parent, cf)
		tntCrate(parent, cf * CFrame.new(2.2, 0, 0))
	end)
end

decorators.cave = function(parent, place, rng, ctx)
	inside(ctx, spot(place, place.radius - 5, 6), 2.5, function(cf)
		chest(parent, cf)
	end)
	scatter(ctx, place, rng, 4, 1.6, function(cf)
		stalagmite(model(parent, "Stalagmite"), cf, Color3.fromRGB(96, 86, 112), rng)
	end)
	cliffs(parent, place, Color3.fromRGB(80, 72, 96), Enum.Material.Slate, rng, -3, 3, NumberRange.new(4, 8), function(rock)
		crystalCluster(rock.Parent :: Instance, CFrame.new(rock.Position + Vector3.new(0, rock.Size.Y / 2, 0)), Color3.fromRGB(181, 123, 255), 0.8, rng)
	end)
end

decorators.frost_woods = function(parent, place, rng, ctx)
	outside(ctx, spot(place, place.radius + 14, 0), 9, function(cf)
		logCabin(parent, cf, Color3.fromRGB(110, 60, 50), Color3.fromRGB(120, 84, 60), true)
	end)
	inside(ctx, spot(place, place.radius - 5, 8), 2.5, function(cf)
		snowman(parent, cf)
	end)
	inside(ctx, spot(place, place.radius - 5, -8), 3, function(cf)
		sled(parent, cf * CFrame.Angles(0, math.rad(30), 0))
	end)
	inside(ctx, spot(place, 3, place.radius - 7), 2, function(cf)
		chopStump(parent, cf)
	end)
	scatter(ctx, place, rng, 4, 2.2, function(cf)
		ball(model(parent, "SnowMound"), cf, Vector3.new(4, 1.4, 3), SNOW, Enum.Material.Snow, { CanCollide = false })
	end)
end

decorators.frost_lake = function(parent, place, _rng, ctx)
	-- The frozen lake: a glassy ice disc lying on the ground
	local lake = block(parent, CFrame.new(place.center + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.3, place.radius * 1.5, place.radius * 1.5), Color3.fromRGB(150, 205, 240), Enum.Material.Ice, { CanCollide = false, CastShadow = false })
	lake.Shape = Enum.PartType.Cylinder
	lake.Name = "LakeIce"
	outside(ctx, spot(place, place.radius + 10, -8), 4.5, function(cf)
		iceShanty(parent, cf)
	end)
	outside(ctx, spot(place, place.radius + 11, 8), 6, function(cf)
		igloo(parent, cf)
	end)
	local p = spot(place, place.radius - 4, 0)
	if ctx.inside(p.Position, 3) and ctx.inside((p * CFrame.new(0, 0, 5)).Position, 3) then
		pier(parent, p)
	end
end

decorators.frost_cave = function(parent, place, rng, ctx)
	if ctx.inside(spot(place, place.radius - 3, -7).Position, 2.5) and ctx.inside(spot(place, place.radius - 3, 7).Position, 2.5) then
		icicleArch(parent, spot(place, place.radius - 3, 0))
	end
	scatter(ctx, place, rng, 3, 1.6, function(cf)
		stalagmite(model(parent, "IceSpike"), cf, Color3.fromRGB(190, 225, 245), rng)
	end)
	cliffs(parent, place, Color3.fromRGB(150, 200, 235), Enum.Material.Glacier, rng, -4, 4, NumberRange.new(8, 14), function(rock)
		rock.Transparency = 0.1
		crystalCluster(rock.Parent :: Instance, CFrame.new(rock.Position + Vector3.new(0, rock.Size.Y / 2, 0)), Color3.fromRGB(158, 230, 255), 0.7, rng)
	end)
end

decorators.ember_fields = function(parent, place, rng, ctx)
	outside(ctx, spot(place, place.radius + 9, -8), 4, function(cf)
		kiln(parent, cf)
	end)
	outside(ctx, spot(place, place.radius + 9, 8), 4, function(cf)
		kiln(parent, cf)
	end)
	inside(ctx, spot(place, place.radius - 5, 0), 1.5, function(cf)
		barrel(parent, cf, Color3.fromRGB(60, 50, 50))
	end)
	scatter(ctx, place, rng, 5, 1.5, function(cf)
		burntStump(model(parent, "BurntStump"), cf, rng)
	end)
end

decorators.ember_pits = function(parent, place, rng, ctx)
	outside(ctx, spot(place, place.radius + 9, 0), 3, function(cf)
		lavaFall(model(parent, "LavaFall"), cf)
	end)
	local river = spot(place, place.radius - 6, 0) * CFrame.Angles(0, math.rad(90), 0)
	local length = place.radius * 1.4
	local clear = true
	for z = -length / 2, length / 2, 4 do
		clear = clear and ctx.inside((river * CFrame.new(0, 0, z)).Position, 3.5)
	end
	if clear then
		lavaRiver(model(parent, "LavaRiver"), river, length)
	end
	inside(ctx, spot(place, place.radius - 13, -8), 3, function(cf)
		minecart(parent, cf, Color3.fromRGB(255, 106, 42), true)
	end)
	cliffs(parent, place, Color3.fromRGB(56, 40, 38), Enum.Material.Basalt, rng, -4, 4, NumberRange.new(10, 18))
end

decorators.ember_lair = function(parent, place, rng, ctx)
	outside(ctx, spot(place, place.radius + 11, 0), 6, function(cf)
		goldHoard(parent, cf, rng)
	end)
	local bones = spot(place, 2, 0) * CFrame.Angles(0, math.rad(90), 0)
	local clear = true
	for z = -13, 9, 4 do
		clear = clear and ctx.inside((bones * CFrame.new(0, 0, z)).Position, 4.5)
	end
	if clear then
		dragonBones(parent, bones)
	end
	inside(ctx, spot(place, place.radius - 5, -10), 4, function(cf)
		nest(parent, cf)
	end)
	cliffs(parent, place, Color3.fromRGB(70, 36, 40), Enum.Material.Basalt, rng, -4, 4, NumberRange.new(10, 18))
end

-- Plaza dressing for a world's center: benches facing the middle, bunting
-- over the shop street, and crates and barrels beside each shop. `avoid`
-- keeps benches clear of other things on the plaza edge.
function Scenery.plaza(parent: Instance, center: Vector3, accent: Color3)
	local m = model(parent, "PlazaDetails")
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local at = center + Vector3.new(math.cos(a) * 20, 0, 4 + math.sin(a) * 20)
		if at.Z - center.Z > -8 and Layout.take(at, 3) then
			local bench = model(m, "Bench")
			local cf = CFrame.lookAt(at, Vector3.new(center.X, 0, center.Z + 4))
			block(bench, cf * CFrame.new(0, 1.3, 0), Vector3.new(5, 0.35, 1.6), WOOD, Enum.Material.WoodPlanks)
			block(bench, cf * CFrame.new(0, 2.2, 0.75), Vector3.new(5, 1.4, 0.3), WOOD, Enum.Material.WoodPlanks)
			for _, x in { -2.1, 2.1 } do
				block(bench, cf * CFrame.new(x, 0.65, 0), Vector3.new(0.35, 1.3, 1.4), INK, Enum.Material.Metal)
			end
		end
	end
	-- Bunting across the front of the shop street (high overhead, so it only
	-- claims the ground under its two poles)
	local bunting = model(m, "Bunting")
	local colors = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 210, 70), Color3.fromRGB(90, 190, 255), Color3.fromRGB(120, 220, 120), accent }
	for _, z in { -13 } do
		for _, x in { -48, 48 } do
			Layout.claim(center + Vector3.new(x, 0, z), 0.5)
			block(bunting, CFrame.new(center + Vector3.new(x, 6.5, z)), Vector3.new(0.6, 13, 0.6), WOOD_DARK, Enum.Material.Wood)
		end
		local n = 32
		for i = 0, n - 1 do
			local x = -47 + i * 94 / (n - 1)
			local sag = 12.6 - math.sin(i / (n - 1) * math.pi) * 2
			block(bunting, CFrame.new(center + Vector3.new(x, sag - 0.5, z)) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(0.9, 0.9, 0.08), colors[i % #colors + 1], Enum.Material.Fabric, { CanCollide = false, CastShadow = false })
		end
		local rope = block(bunting, CFrame.new(center + Vector3.new(0, 11.8, z)), Vector3.new(96, 0.08, 0.08), INK, nil, { CanCollide = false })
		rope.Name = "Rope"
	end
	-- Crates and barrels in the gaps between the shops, where there's room
	for _, x in { -52, -17, 17, 52 } do
		local at = CFrame.new(center + Vector3.new(x, 0, -14))
		if Layout.take(at.Position + Vector3.new(1, 0, 0), 3) then
			local stack = model(m, "Crates")
			block(stack, at * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0.3, 0), Vector3.new(2, 2, 2), WOOD, Enum.Material.WoodPlanks)
			block(stack, at * CFrame.new(0.3, 2.8, 0) * CFrame.Angles(0, 0.9, 0), Vector3.new(1.6, 1.6, 1.6), WOOD_DARK, Enum.Material.WoodPlanks)
			barrel(stack, at * CFrame.new(2.4, 0, 0.5))
		end
	end
end

-- Building blocks and props, reused by the backdrop past the world's walls.
Scenery.kit = {
	block = block,
	ball = ball,
	post = post,
	log = log,
	model = model,
	roof = roof,
	glow = glow,
	smoke = smoke,
	barn = barn,
	silo = silo,
	tractor = tractor,
	scarecrow = scarecrow,
	logCabin = logCabin,
	logPile = logPile,
	crane = crane,
	stoneBlocks = stoneBlocks,
	rails = rails,
	minecart = minecart,
	barrel = barrel,
	mineEntrance = mineEntrance,
	crystalCluster = crystalCluster,
	stalagmite = stalagmite,
	snowman = snowman,
	iceShanty = iceShanty,
	igloo = igloo,
	kiln = kiln,
	burntStump = burntStump,
	lavaFall = lavaFall,
	dragonBones = dragonBones,
	goldHoard = goldHoard,
	nest = nest,
}

-- The decorator for a zone, if it has one.
function Scenery.decorator(placeId: string): Decorator?
	return decorators[placeId]
end

return Scenery
