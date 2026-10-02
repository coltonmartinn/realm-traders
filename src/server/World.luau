--!strict
-- Builds the map at runtime from Places, so the whole game lives in this repo.
--
-- Layout follows the "compact hub" pattern of top Roblox simulators: spawn on
-- a plaza with a fountain, the three shops in a row right in front of you,
-- and fenced gathering zones a few seconds' walk away along lamp-lit paths,
-- each behind a big gate arch with a sign. Trees ring the edge of the map.
--
-- Prompts that open a UI panel carry an "OpenPanel" attribute (the client
-- handles those). Gather prompts call onGather on the server. The Mine's gate
-- is a "LockedGate" the client opens locally once the player has the gear.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Goods = require(ReplicatedStorage.Shared.Goods)
local Places = require(ReplicatedStorage.Shared.Places)
local Realms = require(ReplicatedStorage.Shared.Realms)
local Layout = require(script.Parent.Layout)
local Scenery = require(script.Parent.Scenery)
local Backdrop = require(script.Parent.Backdrop)

local RESPAWN_SECONDS = 10
local HOLD_SECONDS = 0.4

export type Node = { goodId: string, prompt: ProximityPrompt }
export type GatherHandler = (player: Player, node: Node) -> boolean
export type PortalHandler = (player: Player, realmId: string) -> ()

local World = {}

local goodsById: { [string]: Goods.Good } = {}
local goodColor: { [string]: Color3 } = {}
for _, g in Goods do
	goodsById[g.id] = g
	goodColor[g.id] = Color3.fromHex(g.color)
end

local C = {
	grass = Color3.fromRGB(110, 190, 84),
	grassDark = Color3.fromRGB(86, 160, 70),
	paving = Color3.fromRGB(236, 222, 194),
	pavingEdge = Color3.fromRGB(184, 168, 140),
	path = Color3.fromRGB(226, 196, 148),
	wood = Color3.fromRGB(150, 104, 66),
	woodDark = Color3.fromRGB(110, 74, 48),
	white = Color3.fromRGB(250, 246, 236),
	ink = Color3.fromRGB(30, 34, 64),
	leaf = Color3.fromRGB(76, 168, 72),
	water = Color3.fromRGB(80, 180, 255),
	stone = Color3.fromRGB(180, 178, 172),
}

local root: Folder

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = true
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent or root
	return p
end

local function folder(name: string, parent: Instance?): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or root
	return f
end

-- Ground layers. The ground itself is Terrain (it can't flicker), and every
-- flat floor laid on it has its own height, well clear of the others, so no
-- two surfaces ever share a plane (that's what makes ground textures flicker).
local LAYER = {
	zone = 0.2, -- gathering zone floors
	path = 0.3,
	street = 0.4,
	plazaEdge = 0.45,
	plaza = 0.5,
}

-- A flat floor whose top is at `top`, sunk into the ground below it.
local function slab(props: { [string]: any }, top: number): Part
	local t = 0.6
	local p = part(props)
	p.Size = Vector3.new(p.Size.X, t, p.Size.Z)
	p.CFrame = p.CFrame + Vector3.new(0, top - t / 2 - p.Position.Y, 0)
	p.CastShadow = false
	return p
end

-- A flat disc (a cylinder lying on its side) with its top at `top`.
local function floorDisc(parent: Instance, name: string, center: Vector3, diameter: number, top: number, color: Color3, material: Enum.Material): Part
	local t = 0.6
	return part({ Name = name, Parent = parent, Shape = Enum.PartType.Cylinder, Size = Vector3.new(t, diameter, diameter), CFrame = CFrame.new(center.X, top - t / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = material, CastShadow = false })
end

-- Terrain grass grows blades that poke up through thin floors, so under each
-- floor in a grassy world the terrain is bare earth (a little smaller than
-- the floor, so it never shows round the edge).
local function bareBlock(cf: CFrame, size: Vector3)
	workspace.Terrain:FillBlock(cf - Vector3.new(0, cf.Position.Y + 4, 0), Vector3.new(size.X, 8, size.Z), Enum.Material.Ground)
end
local function bareDisc(center: Vector3, radius: number)
	workspace.Terrain:FillCylinder(CFrame.new(center.X, -4, center.Z), 8, radius, Enum.Material.Ground)
end

-- A flat slab between two points on the ground (paths).
local function strip(parent: Instance, from: Vector3, to: Vector3, width: number, color: Color3, material: Enum.Material, top: number, bare: boolean)
	local a, b = Vector3.new(from.X, 0, from.Z), Vector3.new(to.X, 0, to.Z)
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	slab({ Name = "Path", Parent = parent, Size = Vector3.new(width, 1, length), CFrame = cf, Color = color, Material = material }, top)
	if bare then
		bareBlock(cf, Vector3.new(width - 3, 0, length))
	end
end

-- Terrain colours. A Terrain material has one colour everywhere, so each
-- material is used for one look only. Bright and saturated, like the top
-- simulators.
local TERRAIN_COLORS: { [Enum.Material]: Color3 } = {
	[Enum.Material.Grass] = Color3.fromRGB(104, 198, 74),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(64, 160, 62),
	[Enum.Material.Ground] = Color3.fromRGB(150, 110, 72),
	[Enum.Material.Mud] = Color3.fromRGB(116, 82, 54),
	[Enum.Material.Slate] = Color3.fromRGB(186, 180, 166),
	[Enum.Material.Limestone] = Color3.fromRGB(88, 72, 116),
	[Enum.Material.Snow] = Color3.fromRGB(242, 248, 255),
	[Enum.Material.Ice] = Color3.fromRGB(150, 210, 250),
	[Enum.Material.Glacier] = Color3.fromRGB(160, 214, 246),
	[Enum.Material.Basalt] = Color3.fromRGB(70, 56, 56),
	[Enum.Material.CrackedLava] = Color3.fromRGB(240, 96, 36),
	[Enum.Material.Asphalt] = Color3.fromRGB(100, 92, 92),
	[Enum.Material.Rock] = Color3.fromRGB(84, 42, 48),
}

-- Each world's ground: one big slab of terrain, 8 studs deep with its top at 0.
local function buildTerrain()
	local terrain = workspace.Terrain
	for material, color in TERRAIN_COLORS do
		terrain:SetMaterialColor(material, color)
	end
	-- Swaying grass blades. Scripts can't set this today (it's the Decoration
	-- box on Workspace.Terrain in Studio), so this only helps if that changes.
	pcall(function()
		(terrain :: any).Decoration = true
	end)
	local grounds = { main = Enum.Material.Grass, frost = Enum.Material.Snow, ember = Enum.Material.Basalt }
	for realmId, material in grounds do
		terrain:FillBlock(CFrame.new(Places.CENTERS[realmId] + Vector3.new(0, -4, 0)), Vector3.new(1024, 8, 1024), material)
	end
end

-- Big text on the front face of a board (sign boards, arches).
local function boardText(board: BasePart, text: string, color: Color3, face: Enum.NormalId?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.ink
	stroke.Thickness = 4
	stroke.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = board
end

local function billboard(adornee: BasePart, title: string, color: Color3, height: number, size: number)
	local gui = Instance.new("BillboardGui")
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(size, size * 0.28)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = title
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.ink
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = adornee
end

local function prompt(parent: BasePart, action: string, object: string, hold: number, distance: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local function sparkle(parent: BasePart, color: Color3)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 1.2
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(1, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 0) })
	e.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.5))
	e.LightEmission = 1
	e.Parent = parent
end

-- Scenery ------------------------------------------------------------------------

local function group(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function decorTree(parent: Instance, at: Vector3, scale: number, rng: Random)
	parent = group(parent, "Tree")
	local h = 8 * scale
	part({ Name = "Trunk", Parent = parent, Size = Vector3.new(1.6, h, 1.6) * Vector3.new(scale, 1, scale), Position = at + Vector3.new(0, h / 2, 0), Color = C.woodDark, Material = Enum.Material.Wood })
	local green = C.leaf:Lerp(Color3.fromRGB(40, 120, 60), rng:NextNumber(0, 0.6))
	part({ Name = "Leaves", Parent = parent, Shape = Enum.PartType.Ball, Size = Vector3.one * 8 * scale, Position = at + Vector3.new(0, h + 2 * scale, 0), Color = green, Material = Enum.Material.Grass, CanCollide = false })
	part({ Name = "Leaves", Parent = parent, Shape = Enum.PartType.Ball, Size = Vector3.one * 5.5 * scale, Position = at + Vector3.new(1.8 * scale, h + 4.6 * scale, 0.8 * scale), Color = green:Lerp(Color3.new(1, 1, 1), 0.08), Material = Enum.Material.Grass, CanCollide = false })
end

local function bush(parent: Instance, at: Vector3, rng: Random)
	parent = group(parent, "Bush")
	local s = rng:NextNumber(2.2, 3.4)
	part({ Name = "Bush", Parent = parent, Shape = Enum.PartType.Ball, Size = Vector3.one * s, Position = at + Vector3.new(0, s * 0.3, 0), Color = C.leaf:Lerp(Color3.fromRGB(50, 130, 60), rng:NextNumber()), Material = Enum.Material.Grass, CanCollide = false })
end

local FLOWER_COLORS = { Color3.fromRGB(255, 110, 140), Color3.fromRGB(255, 220, 80), Color3.fromRGB(170, 120, 255), Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 150, 60) }

local function flowers(parent: Instance, at: Vector3, rng: Random)
	parent = group(parent, "Flowers")
	for _ = 1, 5 do
		local offset = Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
		part({ Name = "Stem", Parent = parent, Size = Vector3.new(0.15, 0.8, 0.15), Position = at + offset + Vector3.new(0, 0.4, 0), Color = C.leaf, CanCollide = false, CastShadow = false })
		part({ Name = "Flower", Parent = parent, Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, Position = at + offset + Vector3.new(0, 0.9, 0), Color = FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)], CanCollide = false, CastShadow = false })
	end
end

local function lamp(parent: Instance, at: Vector3)
	parent = group(parent, "Lamp")
	part({ Name = "LampPost", Parent = parent, Size = Vector3.new(0.5, 7, 0.5), Position = at + Vector3.new(0, 3.5, 0), Color = C.ink, Material = Enum.Material.Metal })
	local head = part({ Name = "LampHead", Parent = parent, Size = Vector3.new(1.4, 1.4, 1.4), Position = at + Vector3.new(0, 7.4, 0), Color = Color3.fromRGB(255, 226, 150), Material = Enum.Material.Neon, CanCollide = false })
	part({ Name = "LampCap", Parent = parent, Size = Vector3.new(2, 0.4, 2), Position = at + Vector3.new(0, 8.3, 0), Color = C.ink, Material = Enum.Material.Metal })
	local light = Instance.new("PointLight")
	light.Range = 16
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Parent = head
end

-- Hub -------------------------------------------------------------------------------

local function buildLighting()
	Lighting.ClockTime = 13.5
	Lighting.Brightness = 2.6
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true
	local function ensure(className: string, props: { [string]: any })
		local inst = Lighting:FindFirstChildOfClass(className) or Instance.new(className)
		for k, v in props do
			(inst :: any)[k] = v
		end
		inst.Parent = Lighting
	end
	ensure("Atmosphere", { Density = 0.25, Offset = 0.1, Haze = 0.8, Color = Color3.fromRGB(205, 225, 245), Decay = Color3.fromRGB(150, 180, 210) })
	ensure("ColorCorrectionEffect", { Saturation = 0.18, Contrast = 0.06, Brightness = 0.02 })
	ensure("BloomEffect", { Intensity = 0.35, Size = 20, Threshold = 1.4 })
	ensure("SunRaysEffect", { Intensity = 0.04, Spread = 0.6 })
end

local function buildHub(rng: Random)
	local hub = folder("Hub")

	-- Plaza: a circle around the fountain plus the shop street behind it
	-- (the ground under them is terrain, see buildTerrain)
	floorDisc(hub, "PlazaEdge", Vector3.new(0, 0, 4), 52, LAYER.plazaEdge, C.pavingEdge, Enum.Material.Pavement)
	floorDisc(hub, "Plaza", Vector3.new(0, 0, 4), 48, LAYER.plaza, C.paving, Enum.Material.Pavement)
	slab({ Name = "ShopStreet", Parent = hub, Size = Vector3.new(100, 1, 30), Position = Vector3.new(0, 0, -28), Color = C.paving, Material = Enum.Material.Pavement }, LAYER.street)
	bareDisc(Vector3.new(0, 0, 4), 23)
	bareBlock(CFrame.new(0, 0, -28), Vector3.new(96, 0, 26))

	-- Fountain landmark
	local fountain = group(hub, "Fountain")
	Layout.claim(Vector3.new(0, 0, -2), 7)
	part({ Name = "FountainRim", Parent = fountain, Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 14, 14), CFrame = CFrame.new(0, 0.8, -2) * CFrame.Angles(0, 0, math.rad(90)), Color = C.white, Material = Enum.Material.Marble })
	part({ Name = "FountainWater", Parent = fountain, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 12, 12), CFrame = CFrame.new(0, 1.5, -2) * CFrame.Angles(0, 0, math.rad(90)), Color = C.water, Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false })
	part({ Name = "FountainPillar", Parent = fountain, Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 2, 2), CFrame = CFrame.new(0, 3, -2) * CFrame.Angles(0, 0, math.rad(90)), Color = C.white, Material = Enum.Material.Marble })
	local bowl = part({ Name = "FountainBowl", Parent = fountain, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 6, 6), CFrame = CFrame.new(0, 5.6, -2) * CFrame.Angles(0, 0, math.rad(90)), Color = C.white, Material = Enum.Material.Marble })
	local spray = Instance.new("ParticleEmitter")
	spray.Rate = 40
	spray.Lifetime = NumberRange.new(0.8, 1.1)
	spray.Speed = NumberRange.new(8, 10)
	spray.SpreadAngle = Vector2.new(12, 12)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.Size = NumberSequence.new(0.35, 0.1)
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	spray.Transparency = NumberSequence.new(0.2, 0.8)
	spray.EmissionDirection = Enum.NormalId.Right -- cylinder's X axis points up after the rotation
	spray.Parent = bowl

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.3, 8)
	spawn.CFrame = CFrame.new(Places.SPAWN + Vector3.new(0, 0.15, 0))
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = hub
	Layout.claim(Places.SPAWN, 4)
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end

	-- Signpost next to spawn: one board per zone, pointing at it.
	local postAt = Vector3.new(-10, 0, 7) -- inside the plaza, clear of the paths
	local signpost = group(hub, "Signpost")
	Layout.claim(postAt, 5.6)
	part({ Name = "SignPost", Parent = signpost, Size = Vector3.new(0.7, 9, 0.7), Position = postAt + Vector3.new(0, 4.5, 0), Color = C.woodDark, Material = Enum.Material.Wood })
	local y = 8
	for _, place in Places.inRealm("main") do
		if place.kind == "zone" then
			local dir = ((place.center - postAt) * Vector3.new(1, 0, 1)).Unit
			local base = postAt + Vector3.new(0, y, 0)
			-- Long axis (Z) points at the zone; text goes on both sides
			local board = part({
				Name = "Arrow",
				Parent = signpost,
				Size = Vector3.new(0.25, 1.1, 5.5),
				CFrame = CFrame.lookAt(base, base + dir) * CFrame.new(0, 0, -2.9),
				Color = C.wood,
				Material = Enum.Material.WoodPlanks,
			})
			boardText(board, `{place.icon} {place.name:upper()}`, Color3.new(1, 1, 1), Enum.NormalId.Left)
			boardText(board, `{place.icon} {place.name:upper()}`, Color3.new(1, 1, 1), Enum.NormalId.Right)
			y -= 1.4
		end
	end

	-- Plaza dressing
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local at = Vector3.new(math.cos(a) * 25, 0, 4 + math.sin(a) * 25)
		if at.Z > -10 and Layout.take(at, 1.2) then
			lamp(hub, at)
			if Layout.take(at + Vector3.new(2.6, 0, 0), 1.6, 0) then
				flowers(hub, at + Vector3.new(2.6, 0, 0), rng)
			end
		end
	end
end

-- Shops ---------------------------------------------------------------------------------

-- Each vendor dresses for the job: body colours plus costume pieces built from
-- parts (no catalog items, so nothing can fail to load).
type Outfit = { shirt: Color3, pants: Color3, sleeves: boolean, skin: Color3, dress: (Model, Color3) -> () }

local function piece(model: Model, name: string, cf: CFrame, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = part({ Name = name, Parent = model, CFrame = cf, Size = size, Color = color, CanCollide = false, CanQuery = false, CastShadow = false })
	if shape then
		p.Shape = shape
	end
	return p
end

-- A vertical cylinder (Roblox cylinders run along X).
local function disc(model: Model, name: string, cf: CFrame, diameter: number, height: number, color: Color3): Part
	return piece(model, name, cf * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(height, diameter, diameter), color, Enum.PartType.Cylinder)
end

local function bodyParts(model: Model): (BasePart, BasePart, BasePart)
	return model:FindFirstChild("Head") :: BasePart, model:FindFirstChild("UpperTorso") :: BasePart, model:FindFirstChild("LowerTorso") :: BasePart
end

-- Front of a rig is -Z.
local function apron(model: Model, color: Color3)
	local _, upper, lower = bodyParts(model)
	local front = -(upper.Size.Z / 2 + 0.06)
	piece(model, "Apron", upper.CFrame * CFrame.new(0, -0.15, front), Vector3.new(upper.Size.X * 0.7, upper.Size.Y * 0.8, 0.1), color)
	piece(model, "Apron", lower.CFrame * CFrame.new(0, -0.5, front), Vector3.new(upper.Size.X * 0.8, 1.4, 0.1), color)
end

local OUTFITS: { [string]: Outfit } = {
	-- Market trader: striped shirt, apron, flat cap, bow tie, moustache
	["Merchant Mo"] = {
		shirt = Color3.fromRGB(250, 246, 236),
		pants = Color3.fromRGB(60, 70, 110),
		sleeves = true,
		skin = Color3.fromRGB(234, 184, 146),
		dress = function(model, accent)
			local head, upper = bodyParts(model)
			apron(model, accent)
			local top = head.Size.Y / 2
			disc(model, "Cap", head.CFrame * CFrame.new(0, top - 0.05, 0.05), head.Size.X * 1.12, 0.38, accent)
			piece(model, "CapBrim", head.CFrame * CFrame.new(0, top - 0.2, -head.Size.Z * 0.6), Vector3.new(head.Size.X * 0.85, 0.1, 0.55), accent)
			piece(model, "BowTie", upper.CFrame * CFrame.new(0, upper.Size.Y / 2 - 0.15, -(upper.Size.Z / 2 + 0.1)), Vector3.new(0.6, 0.28, 0.12), Color3.fromRGB(230, 60, 70))
			piece(model, "Moustache", head.CFrame * CFrame.new(0, -0.22, -(head.Size.Z / 2 + 0.02)), Vector3.new(0.55, 0.13, 0.1), Color3.fromRGB(90, 56, 36))
		end,
	},
	-- Baker: chef's hat, white jacket, red neckerchief, purple apron
	["Baker Bea"] = {
		shirt = Color3.fromRGB(250, 248, 244),
		pants = Color3.fromRGB(70, 60, 80),
		sleeves = true,
		skin = Color3.fromRGB(196, 140, 104),
		dress = function(model, accent)
			local head, upper = bodyParts(model)
			apron(model, accent)
			local top = head.Size.Y / 2
			disc(model, "HatBand", head.CFrame * CFrame.new(0, top + 0.05, 0), head.Size.X * 1.05, 0.5, Color3.fromRGB(255, 255, 255))
			piece(model, "HatPuff", head.CFrame * CFrame.new(0, top + 0.6, 0), Vector3.new(1.6, 1.6, 1.6), Color3.fromRGB(255, 255, 255), Enum.PartType.Ball)
			piece(model, "Neckerchief", upper.CFrame * CFrame.new(0, upper.Size.Y / 2 - 0.12, -(upper.Size.Z / 2 + 0.08)), Vector3.new(0.9, 0.3, 0.12), Color3.fromRGB(230, 60, 70))
		end,
	},
	-- Gear seller: hard hat, hi-vis vest stripes, tool belt with a hammer
	["Outfitter Oz"] = {
		shirt = Color3.fromRGB(240, 120, 40),
		pants = Color3.fromRGB(70, 90, 140),
		sleeves = false,
		skin = Color3.fromRGB(150, 100, 70),
		dress = function(model, accent)
			local head, upper, lower = bodyParts(model)
			local top = head.Size.Y / 2
			local helmet = piece(model, "HardHat", head.CFrame * CFrame.new(0, top + 0.05, 0), Vector3.new(head.Size.X * 1.15, 0.8, head.Size.Z * 1.15), accent)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = helmet
			disc(model, "HatBrim", head.CFrame * CFrame.new(0, top - 0.12, -0.08), head.Size.X * 1.5, 0.1, accent)
			local front = -(upper.Size.Z / 2 + 0.04)
			for _, y in { 0.25, -0.25 } do
				piece(model, "VestStripe", upper.CFrame * CFrame.new(0, y, front), Vector3.new(upper.Size.X + 0.04, 0.16, 0.08), Color3.fromRGB(235, 240, 245))
			end
			piece(model, "Belt", lower.CFrame, Vector3.new(lower.Size.X + 0.15, 0.35, lower.Size.Z + 0.15), C.woodDark)
			piece(model, "HammerHandle", lower.CFrame * CFrame.new(lower.Size.X / 2 + 0.12, -0.45, 0), Vector3.new(0.14, 0.9, 0.14), C.wood)
			piece(model, "HammerHead", lower.CFrame * CFrame.new(lower.Size.X / 2 + 0.12, -0.05, 0), Vector3.new(0.22, 0.25, 0.55), Color3.fromRGB(150, 156, 170))
		end,
	},
	-- Travelling merchant: wide hat with a feather, cape, big backpack
	["Merchant Max"] = {
		shirt = Color3.fromRGB(255, 214, 70),
		pants = Color3.fromRGB(90, 60, 40),
		sleeves = true,
		skin = Color3.fromRGB(234, 184, 146),
		dress = function(model, accent)
			local head, upper = bodyParts(model)
			local top = head.Size.Y / 2
			disc(model, "HatBrim", head.CFrame * CFrame.new(0, top - 0.05, 0), head.Size.X * 2.1, 0.12, accent)
			disc(model, "HatCrown", head.CFrame * CFrame.new(0, top + 0.3, 0), head.Size.X * 0.95, 0.7, accent)
			piece(model, "Feather", head.CFrame * CFrame.new(0.45, top + 0.6, 0.15) * CFrame.Angles(0, 0, math.rad(-25)), Vector3.new(0.12, 1, 0.3), Color3.fromRGB(230, 60, 70))
			local back = upper.Size.Z / 2
			piece(model, "Cape", upper.CFrame * CFrame.new(0, -0.6, back + 0.06), Vector3.new(upper.Size.X + 0.2, upper.Size.Y + 1.6, 0.1), accent)
			piece(model, "Backpack", upper.CFrame * CFrame.new(0, 0.1, back + 0.55), Vector3.new(1.5, 1.7, 0.9), C.wood)
			piece(model, "BedRoll", upper.CFrame * CFrame.new(0, 1.05, back + 0.55) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.6, 1.8, 0.6), Color3.fromRGB(70, 150, 90), Enum.PartType.Cylinder)
		end,
	},
}

-- `style` picks an outfit from OUTFITS (defaults to the vendor's own name).
local function shopkeeper(parent: Instance, cf: CFrame, accent: Color3, name: string, style: string?)
	local outfit = OUTFITS[style or name]
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		local skin = if outfit then outfit.skin else Color3.fromRGB(234, 184, 146)
		local shirt = if outfit then outfit.shirt else accent
		local pants = if outfit then outfit.pants else C.ink
		local arms = if outfit and outfit.sleeves then shirt else skin
		desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, arms, arms
		desc.TorsoColor, desc.LeftLegColor, desc.RightLegColor = shirt, pants, pants
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return
	end
	model.Name = name
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	model:PivotTo(cf)
	if outfit then
		-- Costume pieces are anchored in place, so dress after posing
		local dressed = pcall(outfit.dress, model, accent)
		if not dressed then
			warn(`[World] couldn't dress {name}`)
		end
	end
	model.Parent = parent
end

local function shop(place: Places.Place, roof: Color3, keeper: string, crates: { string }, style: string?)
	local model = Instance.new("Model")
	model.Name = place.name
	model.Parent = root

	-- Front (-Z) faces the plaza
	local cf = CFrame.lookAt(place.center, Places.centerOf(place) + Vector3.new(0, 0, 4))
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	Layout.claim(at(0, 0, 2).Position, 11)
	part({ Name = "Floor", Parent = model, Size = Vector3.new(18, 0.5, 12), CFrame = at(0, 0.25, 2), Color = C.wood, Material = Enum.Material.WoodPlanks })
	local counter = part({ Name = "Counter", Parent = model, Size = Vector3.new(13, 3.4, 2.6), CFrame = at(0, 2.2, -2), Color = C.wood, Material = Enum.Material.WoodPlanks })
	part({ Name = "CounterTop", Parent = model, Size = Vector3.new(13.6, 0.4, 3.2), CFrame = at(0, 4.1, -2), Color = roof, Material = Enum.Material.SmoothPlastic })
	part({ Name = "BackWall", Parent = model, Size = Vector3.new(18, 11, 0.8), CFrame = at(0, 5.75, 7.6), Color = C.white, Material = Enum.Material.WoodPlanks })
	for _, x in { -8.6, 8.6 } do
		part({ Name = "Post", Parent = model, Size = Vector3.new(0.9, 11, 0.9), CFrame = at(x, 5.75, -3.2), Color = C.woodDark, Material = Enum.Material.Wood })
	end
	-- Shelves with crates of the shop's goods
	for i, goodId in crates do
		local x = -6 + (i - 1) * (12 / math.max(#crates - 1, 1))
		part({ Name = "Crate", Parent = model, Size = Vector3.new(2.6, 2, 2), CFrame = at(x, 1.5, 6), Color = C.woodDark, Material = Enum.Material.WoodPlanks })
		part({ Name = "Goods", Parent = model, Size = Vector3.new(2.2, 0.6, 1.6), CFrame = at(x, 2.7, 6), Color = goodColor[goodId] or roof, Material = Enum.Material.SmoothPlastic })
	end
	-- Striped awning
	for i = 0, 8 do
		local stripe = if i % 2 == 0 then roof else C.white
		part({ Name = "Awning", Parent = model, Size = Vector3.new(2.05, 0.35, 8), CFrame = at(-8.2 + i * 2.05, 11.4, 0.6) * CFrame.Angles(math.rad(14), 0, 0), Color = stripe, Material = Enum.Material.Fabric })
	end
	local board = part({ Name = "SignBoard", Parent = model, Size = Vector3.new(14, 3.2, 0.5), CFrame = at(0, 13.6, -3.4), Color = roof, Material = Enum.Material.SmoothPlastic })
	boardText(board, `{place.icon} {place.name:upper()}`, Color3.new(1, 1, 1))
	model.PrimaryPart = counter

	shopkeeper(model, at(0, 4.4, 1.6), roof, keeper, style)
	billboard(counter, keeper, Color3.new(1, 1, 1), 5.6, 7)

	local p = prompt(counter, `Open {place.name}`, keeper, 0, 14)
	p:SetAttribute("OpenPanel", place.panel)
	p.KeyboardKeyCode = Enum.KeyCode.E
end

-- Gathering zones ---------------------------------------------------------------------------

type NodeBuilder = (model: Model, at: CFrame, rng: Random) -> BasePart

local function buildTree(model: Model, at: CFrame, rng: Random): BasePart
	local h = rng:NextNumber(6.5, 8.5)
	local trunk = part({ Name = "Trunk", Parent = model, Size = Vector3.new(1.8, h, 1.8), CFrame = at * CFrame.new(0, h / 2, 0), Color = goodColor.wood, Material = Enum.Material.Wood })
	local green = Color3.fromRGB(70, 150 + rng:NextInteger(0, 30), 64)
	part({ Name = "Leaves", Parent = model, Shape = Enum.PartType.Ball, Size = Vector3.one * 7, CFrame = at * CFrame.new(0, h + 1.5, 0), Color = green, Material = Enum.Material.Grass, CanCollide = false })
	part({ Name = "Leaves", Parent = model, Shape = Enum.PartType.Ball, Size = Vector3.one * 4.8, CFrame = at * CFrame.new(1.2, h + 4, 0.6), Color = green:Lerp(Color3.new(1, 1, 1), 0.1), Material = Enum.Material.Grass, CanCollide = false })
	return trunk
end

local function buildWheat(model: Model, at: CFrame, rng: Random): BasePart
	local bed = part({ Name = "Bed", Parent = model, Size = Vector3.new(5, 0.6, 5), CFrame = at * CFrame.new(0, 0.3, 0), Color = Color3.fromRGB(120, 84, 56), Material = Enum.Material.Ground })
	for x = -1, 1 do
		for z = -1, 1 do
			local h = rng:NextNumber(2.4, 3.2)
			local tilt = CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12))
			part({ Name = "Stalk", Parent = model, Size = Vector3.new(0.25, h, 0.25), CFrame = at * CFrame.new(x * 1.5, 0.6 + h / 2, z * 1.5) * tilt, Color = Color3.fromRGB(170, 190, 80), CanCollide = false, CastShadow = false })
			part({ Name = "Head", Parent = model, Size = Vector3.new(0.6, 1.1, 0.6), CFrame = at * CFrame.new(x * 1.5, 0.6 + h, z * 1.5) * tilt, Color = goodColor.wheat, Material = Enum.Material.Grass, CanCollide = false, CastShadow = false })
		end
	end
	return bed
end

local function buildRock(color: Color3, veins: Color3?): NodeBuilder
	return function(model: Model, at: CFrame, rng: Random): BasePart
		local s = rng:NextNumber(3.6, 4.6)
		local rock = part({ Name = "Rock", Parent = model, Size = Vector3.new(s, s * 0.8, s), CFrame = at * CFrame.new(0, s * 0.32, 0) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25)), Color = color, Material = Enum.Material.Slate })
		part({ Name = "Chunk", Parent = model, Size = Vector3.new(s * 0.5, s * 0.45, s * 0.5), CFrame = at * CFrame.new(s * 0.45, s * 0.2, s * 0.2) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0.3), Color = color, Material = Enum.Material.Slate })
		if veins then
			for _ = 1, 5 do
				local offset = Vector3.new(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0.1, 0.45), rng:NextNumber(-0.45, 0.45)) * s
				part({ Name = "Vein", Parent = model, Size = Vector3.one * rng:NextNumber(0.8, 1.2), CFrame = rock.CFrame * CFrame.new(offset), Color = veins, Material = Enum.Material.Neon, CanCollide = false })
			end
		end
		return rock
	end
end

local function crystalBuilder(color: Color3, baseColor: Color3): NodeBuilder
	return function(model: Model, at: CFrame, rng: Random): BasePart
		local base = part({ Name = "Rock", Parent = model, Size = Vector3.new(4, 1.6, 4), CFrame = at * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Color = baseColor, Material = Enum.Material.Slate })
		for i = 1, 4 do
			local h = rng:NextNumber(2.5, 4.5)
			local tilt = CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4))
			local offset = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
			part({ Name = "Crystal", Parent = model, Size = Vector3.new(0.9, h, 0.9), CFrame = at * CFrame.new(offset + Vector3.new(0, 1.5 + h / 2 - 0.5, 0)) * tilt, Color = color:Lerp(Color3.new(1, 1, 1), (i % 2) * 0.25), Material = Enum.Material.Neon, CanCollide = false })
		end
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = base
		return base
	end
end

local buildCrystal = crystalBuilder(goodColor.gems, Color3.fromRGB(70, 60, 90))

-- A snowy pine: stacked cones (wedge rings) with white tips.
local function buildPine(model: Model, at: CFrame, rng: Random): BasePart
	local h = rng:NextNumber(5, 6.5)
	local trunk = part({ Name = "Trunk", Parent = model, Size = Vector3.new(1.4, h, 1.4), CFrame = at * CFrame.new(0, h / 2, 0), Color = Color3.fromRGB(96, 66, 46), Material = Enum.Material.Wood })
	local green = goodColor.pine:Lerp(Color3.fromRGB(30, 80, 60), rng:NextNumber(0, 0.4))
	for i, size in { 7, 5.4, 3.8 } do
		local y = h - 1.5 + i * 2.1
		part({ Name = "Needles", Parent = model, Shape = Enum.PartType.Ball, Size = Vector3.new(size, 2.6, size), CFrame = at * CFrame.new(0, y, 0), Color = green, Material = Enum.Material.Grass, CanCollide = false })
		part({ Name = "Snow", Parent = model, Shape = Enum.PartType.Ball, Size = Vector3.new(size * 0.75, 1.2, size * 0.75), CFrame = at * CFrame.new(0, y + 1, 0), Color = Color3.fromRGB(248, 252, 255), Material = Enum.Material.Snow, CanCollide = false })
	end
	return trunk
end

-- An ice-fishing hole: a ring of ice, dark water and a little flag.
local function buildIceHole(model: Model, at: CFrame, rng: Random): BasePart
	local rim = part({ Name = "IceRim", Parent = model, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 5, 5), CFrame = at * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(210, 236, 250), Material = Enum.Material.Ice })
	part({ Name = "Water", Parent = model, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.55, 3, 3), CFrame = at * CFrame.new(0, 0.27, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(30, 70, 120), Material = Enum.Material.Glass, CanCollide = false })
	part({ Name = "FlagPole", Parent = model, Size = Vector3.new(0.2, 3, 0.2), CFrame = at * CFrame.new(2, 1.5, 0), Color = C.woodDark })
	part({ Name = "Flag", Parent = model, Size = Vector3.new(0.1, 0.8, 1.2), CFrame = at * CFrame.new(2, 2.6, 0.6) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0), Color = Color3.fromRGB(230, 60, 70), CanCollide = false })
	return rim
end

type ZoneStyle = {
	ground: Color3,
	groundMaterial: Enum.Material,
	fence: Color3,
	nodes: number,
	charges: number,
	action: string,
	object: string,
	build: NodeBuilder,
	decorate: ((parent: Instance, place: Places.Place, rng: Random) -> ())?,
}

local styles: { [string]: ZoneStyle } = {
	frost_woods = {
		ground = Color3.fromRGB(232, 240, 248),
		groundMaterial = Enum.Material.Snow,
		fence = Color3.fromRGB(120, 90, 70),
		nodes = 11,
		charges = 4,
		action = "Chop",
		object = "Pine",
		build = buildPine,
	},
	frost_lake = {
		ground = Color3.fromRGB(170, 225, 255),
		groundMaterial = Enum.Material.Ice,
		fence = Color3.fromRGB(150, 180, 210),
		nodes = 9,
		charges = 4,
		action = "Fish",
		object = "Fishing Hole",
		build = buildIceHole,
	},
	frost_cave = {
		ground = Color3.fromRGB(150, 200, 240),
		groundMaterial = Enum.Material.Glacier,
		fence = Color3.fromRGB(110, 140, 180),
		nodes = 8,
		charges = 3,
		action = "Mine",
		object = "Ice Crystal",
		build = crystalBuilder(goodColor.icecrystal, Color3.fromRGB(110, 140, 170)),
	},
	ember_fields = {
		ground = Color3.fromRGB(86, 78, 80),
		groundMaterial = Enum.Material.Ground,
		fence = Color3.fromRGB(50, 44, 46),
		nodes = 10,
		charges = 4,
		action = "Collect",
		object = "Charcoal Pile",
		build = buildRock(goodColor.charcoal, Color3.fromRGB(255, 120, 40)),
	},
	ember_pits = {
		ground = Color3.fromRGB(60, 40, 36),
		groundMaterial = Enum.Material.CrackedLava,
		fence = Color3.fromRGB(40, 32, 30),
		nodes = 9,
		charges = 4,
		action = "Mine",
		object = "Magma Rock",
		build = buildRock(Color3.fromRGB(80, 50, 44), goodColor.magma),
	},
	ember_lair = {
		ground = Color3.fromRGB(100, 42, 48),
		groundMaterial = Enum.Material.Basalt,
		fence = Color3.fromRGB(90, 30, 36),
		nodes = 8,
		charges = 3,
		action = "Collect",
		object = "Dragon Scales",
		build = crystalBuilder(goodColor.dragonscale, Color3.fromRGB(60, 30, 34)),
	},
	forest = {
		ground = Color3.fromRGB(86, 186, 70),
		groundMaterial = Enum.Material.Grass,
		fence = C.wood,
		nodes = 11,
		charges = 4,
		action = "Chop",
		object = "Tree",
		build = buildTree,
	},
	farm = {
		ground = Color3.fromRGB(176, 122, 70),
		groundMaterial = Enum.Material.Ground,
		fence = C.white,
		nodes = 12,
		charges = 3,
		action = "Harvest",
		object = "Wheat",
		build = buildWheat,
	},
	quarry = {
		ground = Color3.fromRGB(192, 186, 170),
		groundMaterial = Enum.Material.Slate,
		fence = C.woodDark,
		nodes = 9,
		charges = 4,
		action = "Mine",
		object = "Stone",
		build = buildRock(goodColor.stone),
	},
	cave = {
		ground = Color3.fromRGB(86, 66, 124),
		groundMaterial = Enum.Material.Basalt,
		fence = Color3.fromRGB(90, 70, 120),
		nodes = 8,
		charges = 3,
		action = "Mine",
		object = "Crystal",
		build = buildCrystal,
	},
	mine = {
		ground = Color3.fromRGB(124, 104, 92),
		groundMaterial = Enum.Material.Basalt,
		fence = Color3.fromRGB(70, 64, 62),
		nodes = 8,
		charges = 3,
		action = "Mine",
		object = "Iron Ore",
		build = buildRock(Color3.fromRGB(96, 90, 92), goodColor.iron),
	},
}

local function setVisible(model: Model, visible: boolean, saved: { [BasePart]: number })
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if visible then
				d.CanCollide = d:GetAttribute("Collide") == true
				TweenService:Create(d, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Transparency = saved[d] or 0 }):Play()
			else
				saved[d] = d.Transparency
				d.CanCollide = false
				TweenService:Create(d, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			end
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = visible
		end
	end
end

local GATE_HALF_WIDTH = 5

local function fence(parent: Instance, place: Places.Place, color: Color3)
	local gateDir = Places.towardHub(place)
	local gateAngle = math.atan2(gateDir.Z, gateDir.X)
	local r = place.radius + 3
	local count = math.floor(2 * math.pi * r / 5)
	local skip = GATE_HALF_WIDTH / r + 0.02
	local prev: Vector3? = nil
	for i = 0, count do
		local a = gateAngle + skip + (i / count) * (2 * math.pi - 2 * skip)
		local at = place.center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		part({ Name = "FencePost", Parent = parent, Size = Vector3.new(0.6, 3.2, 0.6), Position = at + Vector3.new(0, 1.6, 0), Color = color, Material = Enum.Material.Wood })
		if prev then
			for _, h in { 1.1, 2.4 } do
				local a2, b2 = prev + Vector3.new(0, h, 0), at + Vector3.new(0, h, 0)
				part({ Name = "FenceRail", Parent = parent, Size = Vector3.new(0.3, 0.35, (b2 - a2).Magnitude), CFrame = CFrame.lookAt((a2 + b2) / 2, b2), Color = color, Material = Enum.Material.Wood })
			end
		end
		prev = at
	end
end

local function gateArch(parent: Instance, place: Places.Place, color: Color3): BasePart
	local dir = Places.towardHub(place)
	local at = Places.gate(place)
	local cf = CFrame.lookAt(at, at + dir) -- front faces the hub
	local pillarColor = color:Lerp(C.ink, 0.25)
	for _, x in { -GATE_HALF_WIDTH, GATE_HALF_WIDTH } do
		part({ Name = "GatePillar", Parent = parent, Size = Vector3.new(1.4, 11, 1.4), CFrame = cf * CFrame.new(x, 5.5, 0), Color = pillarColor, Material = Enum.Material.WoodPlanks })
	end
	local board = part({ Name = "GateSign", Parent = parent, Size = Vector3.new(GATE_HALF_WIDTH * 2 + 3, 3.2, 0.6), CFrame = cf * CFrame.new(0, 10.4, 0), Color = color, Material = Enum.Material.SmoothPlastic })
	boardText(board, `{place.icon} {place.name:upper()}`, Color3.new(1, 1, 1), Enum.NormalId.Front)
	boardText(board, `{place.icon} {place.name:upper()}`, Color3.new(1, 1, 1), Enum.NormalId.Back)
	return board
end

local ZONE_SIGN_COLORS: { [string]: Color3 } = {
	forest = Color3.fromRGB(70, 160, 70),
	farm = Color3.fromRGB(236, 150, 50),
	quarry = Color3.fromRGB(70, 150, 170),
	mine = Color3.fromRGB(200, 70, 70),
	cave = Color3.fromRGB(150, 90, 220),
	frost_woods = Color3.fromRGB(60, 130, 90),
	frost_lake = Color3.fromRGB(70, 150, 220),
	frost_cave = Color3.fromRGB(80, 170, 200),
	ember_fields = Color3.fromRGB(90, 84, 90),
	ember_pits = Color3.fromRGB(230, 110, 40),
	ember_lair = Color3.fromRGB(200, 50, 60),
}

local function buildZone(place: Places.Place, onGather: GatherHandler)
	local style = styles[place.id]
	local zoneFolder = folder(place.name:upper())
	local goodId = place.good :: string

	floorDisc(zoneFolder, "ZoneGround", place.center, place.radius * 2 + 6, LAYER.zone, style.ground, style.groundMaterial)
	local grassy = place.realm == "main"
	if grassy then
		bareDisc(place.center, place.radius + 1)
	end
	fence(zoneFolder, place, style.fence)
	gateArch(zoneFolder, place, ZONE_SIGN_COLORS[place.id])

	-- Path from the plaza to the gate, with lamps along it
	local gate = Places.gate(place)
	local center = Places.centerOf(place)
	local start = center + (gate - center).Unit * 23
	local pathEnd = gate - Places.towardHub(place) * 4
	strip(zoneFolder, start, pathEnd, 9, C.path, Enum.Material.Pavement, LAYER.path, grassy)
	local along = gate - start
	local steps = math.floor(along.Magnitude / 16)
	local side = Vector3.new(-along.Unit.Z, 0, along.Unit.X)
	for i = 1, steps do
		local p = start + along * (i / (steps + 1))
		local at = p + side * 6.5 * (if i % 2 == 0 then 1 else -1)
		if Layout.take(at, 1, 0) then
			lamp(zoneFolder, at)
		end
	end
	Layout.claimLine(start, pathEnd, 4.5)

	if place.gearLevel or place.rebirths then
		-- Locked gate: bars across the opening, opened client-side when geared
		local dir = Places.towardHub(place)
		local cf = CFrame.lookAt(gate, gate + dir)
		local gateModel = Instance.new("Model")
		gateModel.Name = "LockedGate"
		gateModel:SetAttribute("GearLevel", place.gearLevel)
		gateModel:SetAttribute("Rebirths", place.rebirths)
		gateModel:SetAttribute("Realm", place.realm)
		gateModel.Parent = zoneFolder
		for x = -4, 4, 2 do
			part({ Name = "Bar", Parent = gateModel, Size = Vector3.new(0.5, 8, 0.5), CFrame = cf * CFrame.new(x, 4, 0), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal })
		end
		local lockSign = part({ Name = "LockSign", Parent = gateModel, Size = Vector3.new(7, 2, 0.3), CFrame = cf * CFrame.new(0, 5, -0.5), Color = Color3.fromRGB(220, 60, 60) })
		boardText(lockSign, if place.rebirths then `🔒 Rebirth {place.rebirths}` else `🔒 Gear Lv {place.gearLevel}`, Color3.new(1, 1, 1))
		part({ Name = "Blocker", Parent = gateModel, Size = Vector3.new(GATE_HALF_WIDTH * 2, 10, 1), CFrame = cf * CFrame.new(0, 5, 0), Transparency = 1 })
	end

	-- Themed set dressing. Props inside the fence take their own spot (and
	-- nodes are placed around them); buildings outside claim map ground.
	local reserved: { { at: Vector3, r: number } } = {}
	local function insideFree(at: Vector3, r: number): boolean
		local flat = (at - place.center) * Vector3.new(1, 0, 1)
		if flat.Magnitude + r > place.radius + 1 or (at - gate).Magnitude < r + 7 then
			return false
		end
		for _, other in reserved do
			if ((other.at - at) * Vector3.new(1, 0, 1)).Magnitude < other.r + r + 1 then
				return false
			end
		end
		table.insert(reserved, { at = at, r = r })
		return true
	end
	local decorate = Scenery.decorator(place.id)
	if decorate then
		decorate(zoneFolder, place, Random.new(#place.id * 53), {
			inside = insideFree,
			outside = function(at: Vector3, r: number): boolean
				return Layout.take(at, r)
			end,
		})
	end
	-- Now the fenced area (with its gate) is this zone's ground
	Layout.claim(place.center, place.radius + 4)

	-- Gathering nodes
	local rng = Random.new(#place.id * 7919)
	local placed: { Vector3 } = {}
	local attempts = 0
	while #placed < style.nodes and attempts < 600 do
		attempts += 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = math.sqrt(rng:NextNumber(0.02, 1)) * (place.radius - 3)
		local pos = place.center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local ok = (pos - gate).Magnitude > 9 -- keep the entrance clear
		for _, other in placed do
			if (other - pos).Magnitude < 8.5 then
				ok = false
				break
			end
		end
		for _, spot in reserved do
			if ((spot.at - pos) * Vector3.new(1, 0, 1)).Magnitude < spot.r + 3 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(placed, pos)
			local model = Instance.new("Model")
			model.Name = style.object
			model.Parent = zoneFolder
			local main = style.build(model, CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng)
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d:SetAttribute("Collide", d.CanCollide)
				end
			end
			sparkle(main, goodColor[goodId])

			local good = goodsById[goodId]
			local p = prompt(main, style.action, `{good.icon} {style.object}`, HOLD_SECONDS, 10)
			p:SetAttribute("Good", goodId)
			local node: Node = { goodId = goodId, prompt = p }
			local charges = style.charges
			local saved: { [BasePart]: number } = {}

			p.Triggered:Connect(function(player)
				if charges <= 0 or not onGather(player, node) then
					return
				end
				charges -= 1
				if charges <= 0 then
					p.Enabled = false
					setVisible(model, false, saved)
					task.delay(RESPAWN_SECONDS, function()
						charges = style.charges
						setVisible(model, true, saved)
						p.Enabled = true
					end)
				end
			end)
		end
	end
end

-- How each world dresses its edge and the gaps between zones.
type Theme = {
	ground: Color3,
	groundMaterial: Enum.Material,
	paving: Color3,
	pavingEdge: Color3,
	path: Color3,
	bigScenery: (parent: Instance, at: Vector3, scale: number, rng: Random) -> (),
	smallScenery: (parent: Instance, at: Vector3, rng: Random) -> (),
}

local function snowyPine(parent: Instance, at: Vector3, scale: number, rng: Random)
	local h = 7 * scale
	part({ Name = "Trunk", Parent = parent, Size = Vector3.new(1.4 * scale, h, 1.4 * scale), Position = at + Vector3.new(0, h / 2, 0), Color = Color3.fromRGB(96, 66, 46), Material = Enum.Material.Wood })
	for i, size in { 8, 6, 4 } do
		local y = h - 1 + i * 2.6 * scale
		part({ Name = "Needles", Parent = parent, Shape = Enum.PartType.Ball, Size = Vector3.new(size, 3, size) * scale, Position = at + Vector3.new(0, y, 0), Color = Color3.fromRGB(46, 110, 80):Lerp(Color3.fromRGB(30, 80, 60), rng:NextNumber()), Material = Enum.Material.Grass, CanCollide = false })
		part({ Name = "Snow", Parent = parent, Shape = Enum.PartType.Ball, Size = Vector3.new(size * 0.75, 1.3, size * 0.75) * scale, Position = at + Vector3.new(0, y + 1.2 * scale, 0), Color = Color3.fromRGB(248, 252, 255), Material = Enum.Material.Snow, CanCollide = false })
	end
end

local function snowMound(parent: Instance, at: Vector3, rng: Random)
	local s = rng:NextNumber(3, 5)
	part({ Name = "SnowMound", Parent = parent, Shape = Enum.PartType.Ball, Size = Vector3.new(s * 1.4, s * 0.6, s), Position = at, Color = Color3.fromRGB(245, 250, 255), Material = Enum.Material.Snow, CanCollide = false })
end

local function obsidianSpire(parent: Instance, at: Vector3, scale: number, rng: Random)
	local h = rng:NextNumber(10, 18) * scale
	part({ Name = "Spire", Parent = parent, Size = Vector3.new(4 * scale, h, 4 * scale), CFrame = CFrame.new(at + Vector3.new(0, h / 2 - 1, 0)) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, math.pi), rng:NextNumber(-0.15, 0.15)), Color = Color3.fromRGB(40, 32, 40), Material = Enum.Material.Basalt })
	part({ Name = "Glow", Parent = parent, Size = Vector3.new(1.2, h * 0.6, 1.2) * Vector3.new(scale, 1, scale), CFrame = CFrame.new(at + Vector3.new(0, h * 0.3, 0)), Color = Color3.fromRGB(255, 110, 40), Material = Enum.Material.Neon, CanCollide = false })
end

local function lavaPool(parent: Instance, at: Vector3, rng: Random)
	local s = rng:NextNumber(4, 7)
	part({ Name = "LavaPool", Parent = parent, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, s, s), CFrame = CFrame.new(at + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 100, 30), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
end

local THEMES: { [string]: Theme } = {
	main = {
		ground = C.grass,
		groundMaterial = Enum.Material.Grass,
		paving = C.paving,
		pavingEdge = C.pavingEdge,
		path = C.path,
		bigScenery = decorTree,
		smallScenery = function(parent, at, rng)
			if rng:NextNumber() < 0.5 then
				bush(parent, at, rng)
			else
				flowers(parent, at, rng)
			end
		end,
	},
	frost = {
		ground = Color3.fromRGB(236, 244, 250),
		groundMaterial = Enum.Material.Snow,
		paving = Color3.fromRGB(206, 224, 238),
		pavingEdge = Color3.fromRGB(160, 186, 210),
		path = Color3.fromRGB(196, 214, 230),
		bigScenery = snowyPine,
		smallScenery = snowMound,
	},
	ember = {
		ground = Color3.fromRGB(64, 52, 52),
		groundMaterial = Enum.Material.Basalt,
		paving = Color3.fromRGB(120, 100, 92),
		pavingEdge = Color3.fromRGB(84, 70, 66),
		path = Color3.fromRGB(110, 86, 74),
		bigScenery = obsidianSpire,
		smallScenery = lavaPool,
	},
}

-- Big scenery around a world's edge, smaller bits between zones (kept off
-- paths and away from `avoid`), and invisible walls.
local function buildBorder(realmId: string, rng: Random)
	local theme = THEMES[realmId]
	local center = Places.CENTERS[realmId]
	local border = folder(if realmId == "main" then "Border" else realmId:upper() .. "_BORDER")
	-- A ring of big scenery round the edge, each with room of its own
	local n = 72
	for i = 1, n do
		local a = i / n * math.pi * 2 + rng:NextNumber(-0.03, 0.03)
		local r = rng:NextNumber(172, 186)
		local scale = rng:NextNumber(1.3, 1.7)
		local at = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if Layout.take(at, 4 * scale, 0) then
			theme.bigScenery(border, at, scale, rng)
		end
	end
	-- Scattered scenery in whatever open ground is left
	local placed = 0
	for _ = 1, 900 do
		if placed >= 80 then
			break
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(34, 164)
		local at = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local big = rng:NextNumber() < 0.45
		local scale = rng:NextNumber(0.9, 1.3)
		if Layout.take(at, if big then 4 * scale else 2.2) then
			placed += 1
			if big then
				theme.bigScenery(border, at, scale, rng)
			else
				theme.smallScenery(border, at, rng)
			end
		end
	end
	local walls = 48
	for i = 1, walls do
		local a = i / walls * math.pi * 2
		local at = center + Vector3.new(math.cos(a) * (Places.REALM_RADIUS - 6), 25, math.sin(a) * (Places.REALM_RADIUS - 6))
		part({ Name = "Wall", Parent = border, Size = Vector3.new(28, 50, 2), CFrame = CFrame.lookAt(at, center + Vector3.new(0, 25, 0)), Transparency = 1, CastShadow = false })
	end
end

-- Portals and pet shops --------------------------------------------------------------

local REALM_COLORS: { [string]: Color3 } = {
	main = Color3.fromRGB(110, 210, 110),
	frost = Color3.fromRGB(120, 200, 255),
	ember = Color3.fromRGB(255, 110, 50),
}

-- A glowing ring standing on a stone base. Walking into it calls onPortal.
local function portal(at: Vector3, facing: Vector3, toRealm: string, label: string, onPortal: PortalHandler)
	local realm = Realms.byId[toRealm]
	local color = REALM_COLORS[toRealm]
	local model = Instance.new("Model")
	model.Name = `Portal_{toRealm}`
	model:SetAttribute("Realm", toRealm)
	model.Parent = root
	local cf = CFrame.lookAt(at, Vector3.new(facing.X, at.Y, facing.Z))
	Layout.claim(at, 8)
	part({ Name = "Base", Parent = model, Size = Vector3.new(14, 1.2, 6), CFrame = cf * CFrame.new(0, 0.6, 0), Color = Color3.fromRGB(120, 116, 130), Material = Enum.Material.Slate })
	-- Ring of blocks around an oval
	local segments = 20
	for i = 0, segments - 1 do
		local a = i / segments * math.pi * 2
		local pos = cf * CFrame.new(math.cos(a) * 5.5, 8 + math.sin(a) * 6.5, 0)
		part({ Name = "Ring", Parent = model, Size = Vector3.new(1.6, 2.4, 1.6), CFrame = pos * CFrame.Angles(0, 0, a), Color = color:Lerp(C.ink, 0.15), Material = Enum.Material.Slate })
	end
	local swirl = part({ Name = "Swirl", Parent = model, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 12, 10), CFrame = cf * CFrame.new(0, 8, 0) * CFrame.Angles(0, math.rad(90), 0), Color = color, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false })
	local fx = Instance.new("ParticleEmitter")
	fx.Rate = 18
	fx.Lifetime = NumberRange.new(1, 1.6)
	fx.Speed = NumberRange.new(1, 3)
	fx.SpreadAngle = Vector2.new(180, 180)
	fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.6), NumberSequenceKeypoint.new(1, 0) })
	fx.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4))
	fx.LightEmission = 0.8
	fx.Parent = swirl
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 2
	light.Parent = swirl
	local board = part({ Name = "Sign", Parent = model, Size = Vector3.new(13, 2.6, 0.5), CFrame = cf * CFrame.new(0, 16.4, 0), Color = color:Lerp(C.ink, 0.3) })
	boardText(board, label, Color3.new(1, 1, 1), Enum.NormalId.Front)
	boardText(board, label, Color3.new(1, 1, 1), Enum.NormalId.Back)
	if realm and realm.rebirths > 0 then
		billboard(swirl, `🔒 {realm.rebirths} Rebirths`, Color3.fromRGB(255, 226, 96), -3.5, 9)
	end
	-- Touching the swirl travels; a short cooldown per player stops repeats
	local recent: { [Player]: number } = {}
	swirl.CanTouch = true
	swirl.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and os.clock() - (recent[player] or 0) > 2 then
			recent[player] = os.clock()
			onPortal(player, toRealm)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		recent[player] = nil
	end)
end

-- A small stall with pet eggs on the counter; its prompt opens the Pets panel.
local function petShop(realmId: string)
	local at = Places.petShop(realmId)
	local center = Places.CENTERS[realmId]
	local model = Instance.new("Model")
	model.Name = "PetShop"
	model.Parent = root
	local cf = CFrame.lookAt(at, Vector3.new(center.X, 0, center.Z))
	Layout.claim(at, 7.5)
	local function rel(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local pink = Color3.fromRGB(255, 120, 180)
	part({ Name = "Floor", Parent = model, Size = Vector3.new(12, 0.5, 8), CFrame = rel(0, 0.25, 1), Color = C.wood, Material = Enum.Material.WoodPlanks })
	local counter = part({ Name = "Counter", Parent = model, Size = Vector3.new(10, 3.4, 2.4), CFrame = rel(0, 2.2, -1.5), Color = C.white, Material = Enum.Material.WoodPlanks })
	part({ Name = "CounterTop", Parent = model, Size = Vector3.new(10.6, 0.4, 3), CFrame = rel(0, 4.1, -1.5), Color = pink })
	for _, x in { -5.6, 5.6 } do
		part({ Name = "Post", Parent = model, Size = Vector3.new(0.8, 9, 0.8), CFrame = rel(x, 4.5, -2.6), Color = C.woodDark, Material = Enum.Material.Wood })
	end
	for i = 0, 5 do
		part({ Name = "Awning", Parent = model, Size = Vector3.new(2.05, 0.35, 6), CFrame = rel(-5.1 + i * 2.05, 9.2, 0.2) * CFrame.Angles(math.rad(14), 0, 0), Color = if i % 2 == 0 then pink else C.white, Material = Enum.Material.Fabric })
	end
	-- Eggs on display, in this world's colors
	local eggColors = { REALM_COLORS[realmId], Color3.fromRGB(255, 226, 96), Color3.fromRGB(200, 140, 255) }
	for i, x in { -3, 0, 3 } do
		local egg = part({ Name = "Egg", Parent = model, Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 2.1, 1.6), CFrame = rel(x, 5.4, -1.5), Color = eggColors[i], Material = Enum.Material.SmoothPlastic })
		sparkle(egg, eggColors[i])
	end
	local board = part({ Name = "SignBoard", Parent = model, Size = Vector3.new(10, 2.4, 0.4), CFrame = rel(0, 11, -2.8), Color = pink })
	boardText(board, "🐾 PET SHOP", Color3.new(1, 1, 1))
	local p = prompt(counter, "Open Pet Shop", "🐾 Pets", 0, 14)
	p:SetAttribute("OpenPanel", "pets")
	p.KeyboardKeyCode = Enum.KeyCode.E
end

-- A portal world's ground, plaza and lamps.
local function buildRealmBase(realmId: string)
	local theme = THEMES[realmId]
	local center = Places.CENTERS[realmId]
	local base = folder(realmId:upper())
	floorDisc(base, "PlazaEdge", center + Vector3.new(0, 0, 4), 52, LAYER.plazaEdge, theme.pavingEdge, Enum.Material.Pavement)
	floorDisc(base, "Plaza", center + Vector3.new(0, 0, 4), 48, LAYER.plaza, theme.paving, Enum.Material.Pavement)
	slab({ Name = "ShopStreet", Parent = base, Size = Vector3.new(100, 1, 30), Position = center + Vector3.new(0, 0, -28), Color = theme.paving, Material = Enum.Material.Pavement }, LAYER.street)
	-- A big world crystal in the middle of the plaza (instead of the hub's fountain)
	local color = REALM_COLORS[realmId]
	Layout.claim(center + Vector3.new(0, 0, -2), 6.5)
	part({ Name = "Pedestal", Parent = base, Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 12, 12), CFrame = CFrame.new(center + Vector3.new(0, 0.8, -2)) * CFrame.Angles(0, 0, math.rad(90)), Color = theme.pavingEdge, Material = Enum.Material.Marble })
	local crystal = part({ Name = "WorldCrystal", Parent = base, Size = Vector3.new(3, 9, 3), CFrame = CFrame.new(center + Vector3.new(0, 6.5, -2)) * CFrame.Angles(0, math.rad(45), math.rad(8)), Color = color, Material = Enum.Material.Neon, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 24
	light.Brightness = 1.5
	light.Parent = crystal
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local at = center + Vector3.new(math.cos(a) * 25, 0, 4 + math.sin(a) * 25)
		if at.Z - center.Z > -10 and Layout.take(at, 1.2) then
			lamp(base, at)
		end
	end
end

-- The Travelling Merchant's cart, set up in the plaza for a visit. Returns
-- the model (destroy it when the visit ends) and its sell prompt.
function World.merchant(goodId: string, price: number): (Model, ProximityPrompt)
	local good = goodsById[goodId]
	local model = Instance.new("Model")
	model.Name = "TravellingMerchant"
	local cf = CFrame.lookAt(Places.MERCHANT, Vector3.new(0, 0, 4))
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local purple = Color3.fromRGB(150, 80, 220)
	local cart = part({ Name = "Cart", Parent = model, Size = Vector3.new(9, 2.6, 4.5), CFrame = at(0, 2.3, 0), Color = C.wood, Material = Enum.Material.WoodPlanks })
	for _, x in { -3.4, 3.4 } do
		part({ Name = "Wheel", Parent = model, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 2.6, 2.6), CFrame = at(x, 1.3, -2.5) * CFrame.Angles(0, math.rad(90), 0), Color = C.woodDark, Material = Enum.Material.Wood })
		part({ Name = "Pole", Parent = model, Size = Vector3.new(0.4, 6, 0.4), CFrame = at(x, 6.6, 1.6), Color = C.woodDark })
	end
	for i = 0, 4 do
		part({ Name = "Canopy", Parent = model, Size = Vector3.new(2, 0.3, 5.5), CFrame = at(-4 + i * 2, 9.8, 0.4) * CFrame.Angles(math.rad(12), 0, 0), Color = if i % 2 == 0 then purple else Color3.fromRGB(255, 214, 70), Material = Enum.Material.Fabric })
	end
	part({ Name = "Goods", Parent = model, Size = Vector3.new(2.4, 1.2, 2), CFrame = at(-2.5, 4.2, 0.5), Color = goodColor[goodId] or purple })
	part({ Name = "Goods", Parent = model, Size = Vector3.new(2, 1.6, 2), CFrame = at(2.4, 4.4, 0.3), Color = purple })
	local board = part({ Name = "Sign", Parent = model, Size = Vector3.new(10, 2.2, 0.4), CFrame = at(0, 11.6, -1.6), Color = purple })
	boardText(board, "🧳 TRAVELLING MERCHANT", Color3.new(1, 1, 1))
	model.PrimaryPart = cart
	shopkeeper(model, at(0, 4.4, 2.6), purple, "Merchant Max")
	billboard(cart, `Buying {good.icon} {good.name} · ${price} each!`, Color3.fromRGB(255, 226, 96), 8.2, 12)

	local puff = Instance.new("ParticleEmitter")
	puff.Rate = 0
	puff.Lifetime = NumberRange.new(0.6, 1.2)
	puff.Speed = NumberRange.new(6, 12)
	puff.SpreadAngle = Vector2.new(180, 180)
	puff.Size = NumberSequence.new(2.5, 0)
	puff.Color = ColorSequence.new(Color3.fromRGB(240, 220, 255))
	puff.Transparency = NumberSequence.new(0.2, 1)
	puff.Parent = cart

	local p = prompt(cart, `Sell {good.name}`, `🧳 ${price} each`, 0, 14)
	p:SetAttribute("Merchant", goodId)
	model.Parent = root
	puff:Emit(40)
	return model, p
end

function World.build(onGather: GatherHandler, onPortal: PortalHandler)
	root = Instance.new("Folder")
	root.Name = "World"
	root.Parent = workspace

	local rng = Random.new(2026)
	local p = Places.byId
	buildLighting()
	buildTerrain()

	-- Landmarks first: everything placed later keeps clear of them
	Layout.claim(Places.LEADERBOARD, 8) -- built by Leaderboard.luau
	Layout.claim(Places.MERCHANT, 7) -- the Travelling Merchant's cart parks here
	for realmId, at in Places.PORTALS do
		local realm = Realms.byId[realmId]
		portal(at, Places.HUB, realmId, `{realm.icon} {realm.name:upper()}`, onPortal)
	end
	for _, realmId in { "main", "frost", "ember" } do
		petShop(realmId)
		Layout.claim(Places.spawn(realmId), 4)
		if realmId ~= "main" then
			portal(Places.homePortal(realmId), Places.CENTERS[realmId], "main", "🏠 MARKET TOWN", onPortal)
		end
	end
	shop(p.market, Color3.fromRGB(60, 140, 235), "Merchant Mo", { "wood", "wheat", "stone", "iron", "bread", "tools" })
	shop(p.workshop, Color3.fromRGB(150, 90, 220), "Baker Bea", { "bread", "tools", "wheat" })
	shop(p.outfitter, Color3.fromRGB(240, 170, 40), "Outfitter Oz", { "iron", "stone", "wood" })
	shop(p.frost_market, Color3.fromRGB(70, 160, 230), "Frosty Flo", { "pine", "fish", "icecrystal", "stew", "frostorb" }, "Merchant Mo")
	shop(p.frost_workshop, Color3.fromRGB(110, 120, 230), "Chef Cora", { "stew", "frostorb", "fish" }, "Baker Bea")
	shop(p.frost_outfitter, Color3.fromRGB(80, 190, 200), "Sherpa Sam", { "pine", "icecrystal", "fish" }, "Outfitter Oz")
	shop(p.ember_market, Color3.fromRGB(230, 90, 50), "Blaze", { "charcoal", "magma", "dragonscale", "steel", "armor" }, "Merchant Mo")
	shop(p.ember_workshop, Color3.fromRGB(180, 60, 60), "Smith Sol", { "steel", "armor", "magma" }, "Baker Bea")
	shop(p.ember_outfitter, Color3.fromRGB(240, 150, 40), "Cinder", { "charcoal", "magma", "dragonscale" }, "Outfitter Oz")
	buildHub(rng)
	buildRealmBase("frost")
	buildRealmBase("ember")

	-- Zones with their paths, props and buildings
	for _, place in Places.list do
		if place.kind == "zone" then
			buildZone(place, onGather)
		end
	end

	-- Plaza props, then the plazas and shop streets themselves are taken
	local accents = { main = Color3.fromRGB(150, 90, 220), frost = Color3.fromRGB(120, 200, 255), ember = Color3.fromRGB(255, 110, 50) }
	for _, realmId in { "main", "frost", "ember" } do
		local center = Places.CENTERS[realmId]
		Scenery.plaza(root, center, accents[realmId])
		Layout.claim(center + Vector3.new(0, 0, 4), 25)
		Layout.claimLine(center + Vector3.new(-48, 0, -28), center + Vector3.new(48, 0, -28), 15)
	end

	-- Trees and rocks last, in whatever ground is left
	for _, realmId in { "main", "frost", "ember" } do
		buildBorder(realmId, rng)
	end

	-- Past the walls, each direction dressed for the zone (or shops) in front
	-- of it, so the edge of the map is never in sight
	local function angleTo(realmId: string, at: Vector3): number
		local d = at - Places.CENTERS[realmId]
		return math.atan2(d.Z, d.X)
	end
	for _, realmId in { "main", "frost", "ember" } do
		local sectors: { Backdrop.Sector } = { { angle = -math.pi / 2, kind = "town" } }
		for _, place in Places.inRealm(realmId) do
			if place.kind == "zone" then
				table.insert(sectors, { angle = angleTo(realmId, place.center), kind = place.id })
			end
		end
		if realmId == "main" then
			table.insert(sectors, { angle = angleTo("main", Places.PORTALS.frost), kind = "frostpeaks" })
			table.insert(sectors, { angle = angleTo("main", Places.PORTALS.ember), kind = "volcano" })
		end
		Backdrop.build(root, realmId, sectors, rng)
	end
end

return World
