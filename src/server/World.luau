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
local Rules = require(ReplicatedStorage.Shared.Rules)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Layout = require(script.Parent.Layout)
local Scenery = require(script.Parent.Scenery)
local Backdrop = require(script.Parent.Backdrop)

local K = Scenery.kit

local RESPAWN_SECONDS = 10
local HOLD_SECONDS = 0.4

-- `depth` is set on Deep Mine veins (the mine level): the server rolls which
-- ore each swing turns up. Elsewhere `goodId` is what's gathered.
export type Node = { goodId: string, prompt: ProximityPrompt, depth: number? }
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
	grass = Color3.fromRGB(104, 198, 74),
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

-- Ground layers. The ground is smooth flat colour (no busy texture to
-- shimmer), and every flat floor laid on it has its own height, well clear of
-- the others. Two surfaces at (nearly) the same height flicker, worse the
-- further away they are, so the gaps are at least 0.1 studs.
local PATH_COLORS: { [string]: Color3 } = {
	frost = Color3.fromRGB(190, 206, 224),
	ember = Color3.fromRGB(150, 110, 90),
}

local LAYER = {
	zone = 0.2, -- gathering zone floors
	path = 0.35,
	curb = 0.5, -- the stone edging beside paths
	street = 0.5,
	plazaEdge = 0.6,
	plaza = 0.7,
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

-- A cobblestone path between two points, with a darker stone curb each side.
local function strip(parent: Instance, from: Vector3, to: Vector3, width: number, color: Color3)
	local a, b = Vector3.new(from.X, 0, from.Z), Vector3.new(to.X, 0, to.Z)
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	slab({ Name = "Path", Parent = parent, Size = Vector3.new(width, 1, length), CFrame = cf, Color = color, Material = Enum.Material.Cobblestone }, LAYER.path)
	for _, side in { -1, 1 } do
		slab({ Name = "Curb", Parent = parent, Size = Vector3.new(0.8, 1, length), CFrame = cf * CFrame.new(side * (width / 2 + 0.4), 0, 0), Color = color:Lerp(Color3.fromRGB(60, 50, 50), 0.35), Material = Enum.Material.Cobblestone }, LAYER.curb)
	end
end

-- A world's ground inside its walls: one smooth disc with its top at 0. The
-- backdrop (Backdrop.luau) tiles the ring outside it.
local function groundDisc(parent: Instance, center: Vector3, color: Color3)
	local diameter = (Places.REALM_RADIUS - 4) * 2
	part({ Name = "Ground", Parent = parent, Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, diameter, diameter), CFrame = CFrame.new(center.X, -2, center.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = Enum.Material.SmoothPlastic })
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

-- Centerpiece ---------------------------------------------------------------------------

-- The hub's centerpiece: a giant gold coin spinning on a marble column above a
-- stepped plinth heaped with coins, with three crystals (one per world)
-- circling it. The spinning is done on each client (Main.client), which turns
-- every Model with a "Spin" attribute (radians per second) about its pivot.
-- The coin sits high enough to keep the Market and portals in view from spawn.
local function buildCenterpiece(hub: Instance)
	local center = Vector3.zero
	local m = group(hub, "Centerpiece")
	Layout.claim(center, 7)
	local marble = Color3.fromRGB(246, 242, 234)
	local gold = Color3.fromRGB(255, 196, 50)
	local function disc(name: string, diameter: number, bottom: number, height: number, color: Color3, material: Enum.Material): Part
		return part({ Name = name, Parent = m, Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, diameter, diameter), CFrame = CFrame.new(center.X, bottom + height / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = material })
	end

	-- Stepped plinth with gold bands (each layer sits on the one below)
	disc("Plinth", 13, 0.4, 1, marble, Enum.Material.Marble)
	disc("PlinthBand", 11, 1.4, 0.3, gold, Enum.Material.Metal)
	disc("Plinth", 9.4, 1.7, 1, marble, Enum.Material.Marble)
	disc("PlinthBand", 7.6, 2.7, 0.3, gold, Enum.Material.Metal)
	disc("Plinth", 6, 3, 0.8, marble, Enum.Material.Marble)

	-- Heaps of coins on the lower ledge, and gems on the upper one
	local rng = Random.new(7)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local at = center + Vector3.new(math.cos(a) * 5.6, 0, math.sin(a) * 5.6)
		local stack = group(m, "CoinStack")
		for k = 0, rng:NextInteger(2, 5) do
			local jitter = Vector3.new(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12))
			part({ Name = "Coin", Parent = stack, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.24, 1.2, 1.2), CFrame = CFrame.new(at + jitter + Vector3.new(0, 1.52 + k * 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = gold, Material = Enum.Material.Metal, CanCollide = false })
		end
	end
	local gems = { Color3.fromRGB(110, 210, 110), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 110, 50), Color3.fromRGB(200, 130, 255) }
	for i, color in gems do
		local a = i / #gems * math.pi * 2
		local at = center + Vector3.new(math.cos(a) * 3.9, 2.0 + 0.55, math.sin(a) * 3.9)
		local gem = part({ Name = "Gem", Parent = m, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = CFrame.new(at) * CFrame.Angles(math.rad(45), math.rad(i * 30), math.rad(35)), Color = color, Material = Enum.Material.Neon, CanCollide = false })
		gem.CastShadow = false
	end

	-- Fluted column with a gold capital
	disc("Column", 2.2, 3.8, 9.4, marble, Enum.Material.Marble)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		part({ Name = "Flute", Parent = m, Size = Vector3.new(0.3, 9.4, 0.3), CFrame = CFrame.new(center + Vector3.new(math.cos(a) * 1.08, 8.5, math.sin(a) * 1.08)), Color = marble:Lerp(Color3.fromRGB(200, 196, 190), 0.4), Material = Enum.Material.Marble })
	end
	disc("ColumnRing", 3, 4.2, 0.4, gold, Enum.Material.Metal)
	disc("Capital", 3.6, 13.2, 0.6, gold, Enum.Material.Metal)
	disc("Capital", 2.8, 13.8, 0.5, gold, Enum.Material.Metal)

	-- The giant coin: an engraved gold face, a raised rim, a ridged edge
	local coinY = 18
	local coin = group(m, "Coin")
	local coinCf = CFrame.new(center.X, coinY, center.Z) -- the cylinder's flat faces point along X
	local face = part({ Name = "CoinFace", Parent = coin, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 7, 7), CFrame = coinCf, Color = gold, Material = Enum.Material.Metal, Reflectance = 0.15, CanCollide = false })
	local rimGold = Color3.fromRGB(226, 156, 34)
	-- Raised rim: a ring standing a little proud of both faces (cut from a
	-- solid cylinder; skipped if that's unavailable)
	local outer = part({ Name = "CoinRim", Parent = coin, Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.15, 7.6, 7.6), CFrame = coinCf, Color = rimGold, Material = Enum.Material.Metal, CanCollide = false })
	local hole = part({ Name = "Hole", Parent = coin, Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 6.7, 6.7), CFrame = coinCf, Color = rimGold })
	local ok, rim = pcall(function()
		return outer:SubtractAsync({ hole })
	end)
	hole:Destroy()
	if ok and rim then
		rim.Name = "CoinRim"
		rim.Anchored = true
		rim.CanCollide = false
		rim.UsePartColor = true
		rim.Color = rimGold
		rim.Material = Enum.Material.Metal
		rim.CFrame = outer.CFrame
		rim.Parent = coin
	end
	outer:Destroy()
	-- Ridged edge, like a real coin
	local ridges = 56
	for i = 0, ridges - 1 do
		local a = i / ridges * math.pi * 2
		part({ Name = "Ridge", Parent = coin, Size = Vector3.new(1.05, 0.22, 0.3), CFrame = coinCf * CFrame.Angles(a, 0, 0) * CFrame.new(0, 3.82, 0), Color = rimGold:Lerp(Color3.fromRGB(150, 90, 10), 0.3), Material = Enum.Material.Metal, CanCollide = false, CastShadow = false })
	end

	-- Engraving on each face: a beaded border, the game's name round the top,
	-- stars round the bottom, a big $ in the middle and a shine across it
	local engrave = Color3.fromRGB(170, 100, 20)
	local shiny = Color3.fromRGB(255, 238, 160)
	local function circle(parent: Instance, size: number, color: Color3, transparency: number, stroke: number?): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(size, size)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = transparency
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		if stroke then
			local s = Instance.new("UIStroke")
			s.Color = engrave
			s.Thickness = stroke
			s.Parent = f
		end
		f.Parent = parent
		return f
	end
	local function glyph(parent: Instance, text: string, x: number, y: number, size: number, rotation: number)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(x, y)
		label.Size = UDim2.fromScale(size, size)
		label.Rotation = rotation
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.LuckiestGuy
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = shiny
		local s = Instance.new("UIStroke")
		s.Color = engrave
		s.Thickness = 2
		s.Parent = label
		label.Parent = parent
	end
	-- Places items evenly round an arc of the face (angles in degrees, 0 = top, clockwise)
	local function around(radius: number, from: number, to: number, count: number, each: (x: number, y: number, rotation: number, index: number) -> ())
		for i = 1, count do
			local deg = if count == 1 then from else from + (to - from) * (i - 1) / (count - 1)
			local r = math.rad(deg)
			each(0.5 + math.sin(r) * radius, 0.5 - math.cos(r) * radius, deg, i)
		end
	end
	for _, faceId in { Enum.NormalId.Right, Enum.NormalId.Left } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = faceId
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 60
		gui.LightInfluence = 0.5
		gui.Parent = face
		local canvas = circle(gui, 1, gold, 1)
		-- Engraved rings with a beaded band between them
		circle(canvas, 0.92, gold, 1, 3)
		circle(canvas, 0.62, gold, 1, 4)
		around(0.42, 0, 360 - 360 / 44, 44, function(x, y)
			local bead = circle(canvas, 0.022, shiny, 0)
			bead.Position = UDim2.fromScale(x, y)
		end)
		-- REALM TRADERS round the top, stars round the bottom
		local name = "REALM TRADERS"
		around(0.36, -78, 78, #name, function(x, y, rotation, i)
			glyph(canvas, name:sub(i, i), x, y, 0.085, rotation)
		end)
		around(0.36, 145, 215, 3, function(x, y, rotation)
			glyph(canvas, "★", x, y, 0.08, rotation - 180)
		end)
		-- The $ with a shadow, and a star each side
		local shadow = Instance.new("TextLabel")
		shadow.AnchorPoint = Vector2.new(0.5, 0.5)
		shadow.Position = UDim2.fromScale(0.515, 0.515)
		shadow.Size = UDim2.fromScale(0.5, 0.5)
		shadow.BackgroundTransparency = 1
		shadow.Font = Enum.Font.LuckiestGuy
		shadow.TextScaled = true
		shadow.Text = "$"
		shadow.TextColor3 = engrave
		shadow.TextTransparency = 0.3
		shadow.Parent = canvas
		local dollar = shadow:Clone()
		dollar.Position = UDim2.fromScale(0.5, 0.5)
		dollar.TextColor3 = shiny
		dollar.TextTransparency = 0
		local stroke = Instance.new("UIStroke")
		stroke.Color = engrave
		stroke.Thickness = 5
		stroke.Parent = dollar
		dollar.Parent = canvas
		glyph(canvas, "★", 0.27, 0.5, 0.07, 0)
		glyph(canvas, "★", 0.73, 0.5, 0.07, 0)
		-- A soft diagonal shine
		local shine = circle(canvas, 1, Color3.new(1, 1, 1), 0)
		shine.ZIndex = 5
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 35
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 1),
			NumberSequenceKeypoint.new(0.4, 0.65),
			NumberSequenceKeypoint.new(0.47, 1),
			NumberSequenceKeypoint.new(0.55, 0.8),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = shine
	end
	sparkle(face, gold)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 210, 120)
	glow.Range = 22
	glow.Brightness = 1.4
	glow.Parent = face
	coin.WorldPivot = CFrame.new(center.X, coinY, center.Z)
	coin:SetAttribute("Spin", 1.2)

	-- Three crystals circling the coin, one for each world
	local orbit = group(m, "Orbit")
	local worlds = { Color3.fromRGB(110, 210, 110), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 110, 50) }
	for i, color in worlds do
		local a = i / #worlds * math.pi * 2
		local at = center + Vector3.new(math.cos(a) * 6, coinY - 2.5, math.sin(a) * 6)
		local crystal = part({ Name = "WorldCrystal", Parent = orbit, Size = Vector3.new(1, 2.6, 1), CFrame = CFrame.new(at) * CFrame.Angles(0, math.rad(45), 0), Color = color, Material = Enum.Material.Neon, CanCollide = false })
		crystal.CastShadow = false
		sparkle(crystal, color)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 10
		light.Brightness = 1
		light.Parent = crystal
	end
	orbit.WorldPivot = CFrame.new(center.X, coinY - 2.5, center.Z)
	orbit:SetAttribute("Spin", -0.5)
end

-- Hub -------------------------------------------------------------------------------

local function buildLighting()
	Lighting.ClockTime = 13.5
	Lighting.Brightness = 2.6
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.Ambient = Color3.fromRGB(96, 92, 104) -- indoors and underground (the mine)
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

	groundDisc(hub, Vector3.zero, C.grass)

	-- Plaza: a circle around the fountain plus the shop street behind it
	floorDisc(hub, "PlazaEdge", Vector3.new(0, 0, 4), 52, LAYER.plazaEdge, C.pavingEdge, Enum.Material.Pavement)
	floorDisc(hub, "Plaza", Vector3.new(0, 0, 4), 48, LAYER.plaza, C.paving, Enum.Material.Pavement)
	slab({ Name = "ShopStreet", Parent = hub, Size = Vector3.new(100, 1, 30), Position = Vector3.new(0, 0, -28), Color = C.paving, Material = Enum.Material.Pavement }, LAYER.street)

	buildCenterpiece(hub)

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

-- The three shops in each world, each built for its trade on a raised stone
-- base: a striped bazaar tent for the Market, a timber-framed workshop with a
-- forge for the Workshop, and an explorer's canvas tent full of gear for the
-- Outfitter. Front (-Z) faces the plaza.
local FLOOR = 1.2 -- top of the plank deck (well above the street, so they never share a plane)
local STONE = Color3.fromRGB(176, 166, 150)
local GOLD = Color3.fromRGB(255, 200, 60)
local SNOW = Color3.fromRGB(248, 252, 255)

local function shop(place: Places.Place, roof: Color3, keeper: string, crates: { string }, style: string?)
	local model = Instance.new("Model")
	model.Name = place.name
	model.Parent = root

	local cf = CFrame.lookAt(place.center, Places.centerOf(place) + Vector3.new(0, 0, 4))
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function add(name: string, size: Vector3, where: CFrame, color: Color3, material: Enum.Material?): Part
		return part({ Name = name, Parent = model, Size = size, CFrame = where, Color = color, Material = material or Enum.Material.SmoothPlastic })
	end
	-- A board running between two local points (roof slopes, braces)
	local function span(name: string, from: Vector3, to: Vector3, width: number, thickness: number, color: Color3, material: Enum.Material?): Part
		local a, b = at(from.X, from.Y, from.Z).Position, at(to.X, to.Y, to.Z).Position
		return add(name, Vector3.new(width, thickness, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, material)
	end
	local function lantern(x: number, y: number, z: number)
		add("LanternCap", Vector3.new(1.1, 0.3, 1.1), at(x, y + 0.65, z), C.ink, Enum.Material.Metal)
		local glass = add("Lantern", Vector3.new(0.8, 1, 0.8), at(x, y, z), if place.realm == "ember" then Color3.fromRGB(255, 150, 70) else Color3.fromRGB(255, 220, 140), Enum.Material.Neon)
		glass.CanCollide = false
		K.glow(glass, Color3.fromRGB(255, 200, 130), 12, 1)
	end
	local frost = place.realm == "frost"

	Layout.claim(at(0, 0, 1.5).Position, 12)

	-- Stone base, plank deck and a front step
	add("Plinth", Vector3.new(20, 1, 15), at(0, 0.5, 1.5), STONE, Enum.Material.Cobblestone)
	add("Deck", Vector3.new(19, 0.2, 14), at(0, 1.1, 1.5), C.wood, Enum.Material.WoodPlanks)
	add("Step", Vector3.new(8, 0.7, 1.4), at(0, 0.35, -6.7), STONE, Enum.Material.Cobblestone)

	-- Counter, with a stripe in the shop's colour
	local counter = add("Counter", Vector3.new(13, 3.4, 2.6), at(0, FLOOR + 1.7, -2), C.wood, Enum.Material.WoodPlanks)
	add("CounterTop", Vector3.new(13.6, 0.4, 3.2), at(0, FLOOR + 3.6, -2), roof)
	add("CounterStripe", Vector3.new(13.2, 0.6, 0.2), at(0, FLOOR + 2.3, -3.35), roof)

	-- Crates of the shop's goods along the back (the Workshop's forge takes the left side)
	local left, right = -6, 6
	if place.panel == "craft" then
		left = -1
	end
	for i, goodId in crates do
		local x = left + (i - 1) * ((right - left) / math.max(#crates - 1, 1))
		add("Crate", Vector3.new(2.4, 2, 2), at(x, FLOOR + 1, 6), C.woodDark, Enum.Material.WoodPlanks)
		add("Goods", Vector3.new(2, 0.6, 1.6), at(x, FLOOR + 2.2, 6), goodColor[goodId] or roof)
	end

	local signAt: CFrame
	if place.panel == "market" then
		-- Bazaar tent: striped poles, a draped back, a striped peaked roof
		-- with a scalloped trim, flags and lanterns
		for _, x in { -9, 9 } do
			for _, z in { -5.6, 8.4 } do
				local pole = add("Pole", Vector3.new(10.6, 0.8, 0.8), at(x, FLOOR + 5.3, z) * CFrame.Angles(0, 0, math.rad(90)), C.white)
				pole.Shape = Enum.PartType.Cylinder
				add("PoleBand", Vector3.new(0.9, 0.5, 0.9), at(x, FLOOR + 3, z), roof)
				add("PoleBand", Vector3.new(0.9, 0.5, 0.9), at(x, FLOOR + 7, z), roof)
			end
		end
		add("Drape", Vector3.new(17.4, 9.6, 0.3), at(0, FLOOR + 4.8, 8.6), Color3.fromRGB(250, 238, 210), Enum.Material.Fabric)
		local eave, ridge, front, back, ridgeZ = FLOOR + 10.4, FLOOR + 15, -6.4, 9.4, 1.5
		for i = 0, 8 do
			local x = -8.2 + i * 2.05
			local color = if i % 2 == 0 then roof else C.white
			span("Roof", Vector3.new(x, eave, front), Vector3.new(x, ridge, ridgeZ), 2.05, 0.35, color, Enum.Material.Fabric)
			span("Roof", Vector3.new(x, ridge, ridgeZ), Vector3.new(x, eave, back), 2.05, 0.35, color, Enum.Material.Fabric)
			local scallop = part({ Name = "Scallop", Parent = model, Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, CFrame = at(x, eave - 0.2, front), Color = if i % 2 == 0 then C.white else roof, Material = Enum.Material.Fabric, CanCollide = false })
			scallop.CastShadow = false
		end
		add("Ridge", Vector3.new(19, 0.5, 0.5), at(0, ridge + 0.15, ridgeZ), GOLD, Enum.Material.Metal)
		if frost then
			span("Snow", Vector3.new(0, ridge - 1.4, ridgeZ - 2.6), Vector3.new(0, ridge + 0.3, ridgeZ), 18.6, 0.5, SNOW, Enum.Material.Snow)
			span("Snow", Vector3.new(0, ridge + 0.3, ridgeZ), Vector3.new(0, ridge - 1.4, ridgeZ + 2.6), 18.6, 0.5, SNOW, Enum.Material.Snow)
		end
		for _, x in { -8.5, 0, 8.5 } do
			local h = if x == 0 then 3.4 else 2.6
			add("FlagPole", Vector3.new(0.25, h, 0.25), at(x, ridge + h / 2, ridgeZ), C.woodDark)
			local knob = part({ Name = "Finial", Parent = model, Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7, CFrame = at(x, ridge + h + 0.2, ridgeZ), Color = GOLD, Material = Enum.Material.Metal })
			knob.CastShadow = false
			add("Flag", Vector3.new(2, 1.1, 0.1), at(x + 1.1, ridge + h - 0.6, ridgeZ), if x == 0 then GOLD else roof, Enum.Material.Fabric)
		end
		lantern(-9, FLOOR + 8.4, -6.3)
		lantern(9, FLOOR + 8.4, -6.3)
		-- Baskets of goods on the front corners of the deck
		for i, x in { -7.6, 7.6 } do
			K.barrel(model, at(x, FLOOR, -4.7), Color3.fromRGB(196, 150, 96))
			local goods = part({ Name = "Goods", Parent = model, Shape = Enum.PartType.Ball, Size = Vector3.one * 1.7, CFrame = at(x, FLOOR + 2.5, -4.7), Color = goodColor[crates[i] or crates[1]] or roof })
			goods.CastShadow = false
		end
		signAt = at(0, eave + 2.1, front - 0.5)
	elseif place.panel == "craft" then
		-- Timber-framed workshop: brick below, plaster above, dark beams, a
		-- slate roof, a chimney and a glowing forge
		local plaster, brick = Color3.fromRGB(246, 236, 214), Color3.fromRGB(176, 92, 70)
		local top = FLOOR + 9.6
		for _, x in { -9.5, 9.5 } do
			add("WallBrick", Vector3.new(0.8, 3, 14), at(x, FLOOR + 1.5, 1.5), brick, Enum.Material.Brick)
			add("WallPlaster", Vector3.new(0.8, 6.6, 14), at(x, FLOOR + 6.3, 1.5), plaster, Enum.Material.Plaster)
			for _, z in { -5.4, 1.5, 8.4 } do
				add("Beam", Vector3.new(1, 9.6, 1), at(x, FLOOR + 4.8, z), C.woodDark, Enum.Material.Wood)
			end
			add("Beam", Vector3.new(1, 0.7, 14.4), at(x, FLOOR + 3.2, 1.5), C.woodDark, Enum.Material.Wood)
			add("Beam", Vector3.new(1, 0.7, 14.4), at(x, top, 1.5), C.woodDark, Enum.Material.Wood)
			span("Brace", Vector3.new(x * 1.06, FLOOR + 3.5, -5), Vector3.new(x * 1.06, top - 0.4, 1.2), 0.6, 0.6, C.woodDark, Enum.Material.Wood)
		end
		add("BackBrick", Vector3.new(18.2, 3, 0.8), at(0, FLOOR + 1.5, 8.6), brick, Enum.Material.Brick)
		add("BackPlaster", Vector3.new(18.2, 6.6, 0.8), at(0, FLOOR + 6.3, 8.6), plaster, Enum.Material.Plaster)
		for _, x in { -4.5, 4.5 } do
			add("Beam", Vector3.new(1, 9.6, 1), at(x, FLOOR + 4.8, 8.8), C.woodDark, Enum.Material.Wood)
		end
		add("Beam", Vector3.new(19.6, 0.7, 1), at(0, top, 8.8), C.woodDark, Enum.Material.Wood)
		K.roof(model, at(0, FLOOR + 0.3, 1.5), 19.6, 14.4, 9.6, roof:Lerp(C.ink, 0.25), Enum.Material.Slate)
		if frost then
			for _, s in { -1, 1 } do
				span("Snow", Vector3.new(0, top + 1.3, 1.5 + s * 7.4), Vector3.new(0, top + 5.9, 1.5), 21, 0.5, SNOW, Enum.Material.Snow)
			end
		end
		local chimney = add("Chimney", Vector3.new(2.2, 8, 2.2), at(6, top + 4, 5.5), brick, Enum.Material.Brick)
		add("ChimneyCap", Vector3.new(2.8, 0.5, 2.8), at(6, top + 8.2, 5.5), C.ink)
		K.smoke(chimney, Color3.fromRGB(220, 220, 225), 3)
		-- Forge in the back left, glowing
		add("Forge", Vector3.new(4.4, 4, 3), at(-5.8, FLOOR + 2, 6.4), brick, Enum.Material.Brick)
		add("ForgeTop", Vector3.new(4.8, 0.5, 3.4), at(-5.8, FLOOR + 4.2, 6.4), C.ink, Enum.Material.Metal)
		local fire = add("ForgeFire", Vector3.new(2.4, 1.6, 0.3), at(-5.8, FLOOR + 1.8, 4.85), Color3.fromRGB(255, 130, 40), Enum.Material.Neon)
		K.glow(fire, Color3.fromRGB(255, 140, 60), 14, 2)
		-- Anvil and workbench at the front of the deck
		local metal = Color3.fromRGB(70, 72, 82)
		add("AnvilBase", Vector3.new(1, 1.4, 1), at(6.8, FLOOR + 0.7, -4.7), metal, Enum.Material.Metal)
		add("Anvil", Vector3.new(2.4, 0.8, 1.1), at(6.8, FLOOR + 1.8, -4.7), metal, Enum.Material.Metal)
		add("Hammer", Vector3.new(0.3, 0.3, 1.6), at(6.6, FLOOR + 2.35, -4.7) * CFrame.Angles(0, math.rad(30), 0), C.woodDark)
		add("Bench", Vector3.new(3.4, 0.3, 1.6), at(-6.8, FLOOR + 2.2, -4.7), C.wood, Enum.Material.WoodPlanks)
		for _, x in { -8.2, -5.4 } do
			add("BenchLeg", Vector3.new(0.3, 2.1, 1.3), at(x, FLOOR + 1.05, -4.7), C.woodDark)
		end
		add("Saw", Vector3.new(1.8, 0.1, 0.6), at(-7, FLOOR + 2.4, -4.6), Color3.fromRGB(190, 194, 204), Enum.Material.Metal)
		lantern(-9.5, FLOOR + 7.4, -6.2)
		lantern(9.5, FLOOR + 7.4, -6.2)
		signAt = at(0, top + 1.6, -6.9)
	else
		-- Explorer's outfitter: a canvas A-frame tent with a rack of
		-- pickaxes (stone, iron, gold, crystal), backpacks and banners
		local canvas = Color3.fromRGB(218, 198, 150)
		local low, high = FLOOR + 5.6, FLOOR + 13
		for _, s in { -1, 1 } do
			span("Canvas", Vector3.new(s * 9.8, low, 1.5), Vector3.new(0, high, 1.5), 15, 0.3, canvas, Enum.Material.Fabric)
			span("CanvasStripe", Vector3.new(s * 9.9, low + 0.15, 1.5), Vector3.new(s * 8.1, low + 1.45, 1.5), 15.1, 0.34, roof, Enum.Material.Fabric)
			add("SideWall", Vector3.new(0.3, 5.6, 14), at(s * 9.6, FLOOR + 2.8, 1.5), canvas:Lerp(C.ink, 0.08), Enum.Material.Fabric)
			if frost then
				span("Snow", Vector3.new(s * 6, low + 3.3, 1.5), Vector3.new(0, high + 0.3, 1.5), 15.2, 0.5, SNOW, Enum.Material.Snow)
			end
		end
		-- Back gable, stepped to fill the triangle
		for i = 1, 5 do
			local frac = 1 - (i - 0.5) / 5
			add("BackCanvas", Vector3.new(19.2 * frac, (high - low) / 5, 0.3), at(0, low + (i - 0.5) * (high - low) / 5, 8.6), canvas:Lerp(C.ink, 0.08), Enum.Material.Fabric)
		end
		add("BackCanvas", Vector3.new(19.2, low - FLOOR, 0.3), at(0, (low + FLOOR) / 2, 8.6), canvas:Lerp(C.ink, 0.08), Enum.Material.Fabric)
		add("RidgePole", Vector3.new(0.6, 0.6, 16.4), at(0, high + 0.2, 1.5), C.woodDark, Enum.Material.Wood)
		for _, z in { -6.2, 9 } do
			add("TentPole", Vector3.new(0.6, high - FLOOR, 0.6), at(0, (high + FLOOR) / 2, z), C.woodDark, Enum.Material.Wood)
		end
		-- Pickaxe rack on the back wall: one head per gear tier
		add("Rack", Vector3.new(12, 4.2, 0.3), at(0, FLOOR + 6, 8.2), C.wood, Enum.Material.WoodPlanks)
		local heads = { Color3.fromRGB(150, 146, 140), Color3.fromRGB(196, 200, 214), GOLD, Color3.fromRGB(120, 230, 255) }
		for i, color in heads do
			local x = -4.5 + (i - 1) * 3
			add("Handle", Vector3.new(0.3, 3.4, 0.3), at(x, FLOOR + 5.8, 7.9), C.woodDark)
			local head = add("PickHead", Vector3.new(2.4, 0.5, 0.4), at(x, FLOOR + 7.4, 7.9), color, if i == 4 then Enum.Material.Neon else Enum.Material.Metal)
			head.CanCollide = false
		end
		-- Backpacks hanging on the side walls
		local packs = { Color3.fromRGB(200, 70, 60), Color3.fromRGB(70, 130, 210), Color3.fromRGB(90, 170, 80) }
		for i, color in packs do
			local x, z = if i == 2 then 9.1 else -9.1, if i == 3 then 4.5 else 2
			add("Backpack", Vector3.new(1, 2.4, 1.8), at(x, FLOOR + 4.2, z), color, Enum.Material.Fabric)
			add("BackpackFlap", Vector3.new(1.1, 0.9, 1.9), at(x, FLOOR + 5, z), color:Lerp(C.ink, 0.25), Enum.Material.Fabric)
		end
		-- Banner poles at the front corners, with the sign hung between them
		for _, x in { -9.8, 9.8 } do
			add("BannerPole", Vector3.new(0.5, 15, 0.5), at(x, FLOOR + 7.5, -6.6), C.woodDark, Enum.Material.Wood)
			add("Banner", Vector3.new(0.15, 3.6, 2), at(x, FLOOR + 12.6, -5.5), roof, Enum.Material.Fabric)
			local knob = part({ Name = "Finial", Parent = model, Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, CFrame = at(x, FLOOR + 15.2, -6.6), Color = GOLD, Material = Enum.Material.Metal })
			knob.CastShadow = false
		end
		add("SignBar", Vector3.new(19.6, 0.4, 0.4), at(0, FLOOR + 14.4, -6.6), C.woodDark, Enum.Material.Wood)
		lantern(0, FLOOR + 10.6, -5.6)
		K.barrel(model, at(-7.6, FLOOR, -4.7))
		K.barrel(model, at(7.6, FLOOR, -4.7))
		signAt = at(0, FLOOR + 12.6, -6.9)
	end

	local board = add("SignBoard", Vector3.new(13, 2.8, 0.5), signAt, roof)
	add("SignTrim", Vector3.new(13.6, 3.4, 0.3), signAt * CFrame.new(0, 0, 0.3), GOLD, Enum.Material.Metal)
	boardText(board, `{place.icon} {place.name:upper()}`, Color3.new(1, 1, 1))
	model.PrimaryPart = counter

	shopkeeper(model, at(0, FLOOR + 3.9, 1.6), roof, keeper, style)
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

-- A gathering spot: hold its prompt to gather. After `charges` gathers it
-- disappears for a while, then grows back.
type NodeStyle = { object: string, action: string, charges: number, build: NodeBuilder, hold: number?, respawn: number?, label: string?, depth: number? }
local function gatherNode(parent: Instance, goodId: string, at: CFrame, style: NodeStyle, rng: Random, onGather: GatherHandler)
	local model = Instance.new("Model")
	model.Name = style.object
	model.Parent = parent
	local main = style.build(model, at, rng)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("Collide", d.CanCollide)
		end
	end
	sparkle(main, goodColor[goodId])

	local good = goodsById[goodId]
	local p = prompt(main, style.action, style.label or `{good.icon} {style.object}`, style.hold or HOLD_SECONDS, 10)
	p:SetAttribute("Good", goodId)
	local node: Node = { goodId = goodId, prompt = p, depth = style.depth }
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
			task.delay(style.respawn or RESPAWN_SECONDS, function()
				charges = style.charges
				setVisible(model, true, saved)
				p.Enabled = true
			end)
		end
	end)
end

local function buildZone(place: Places.Place, onGather: GatherHandler)
	local style = styles[place.id]
	local zoneFolder = folder(place.name:upper())
	local goodId = place.good :: string

	floorDisc(zoneFolder, "ZoneGround", place.center, place.radius * 2 + 6, LAYER.zone, style.ground, style.groundMaterial)
	fence(zoneFolder, place, style.fence)
	gateArch(zoneFolder, place, ZONE_SIGN_COLORS[place.id])

	-- Path from the plaza to the gate, with lamps along it
	local gate = Places.gate(place)
	local center = Places.centerOf(place)
	local start = center + (gate - center).Unit * 23
	local pathEnd = gate - Places.towardHub(place) * 4
	strip(zoneFolder, start, pathEnd, 9, PATH_COLORS[place.realm] or C.path)
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
			gatherNode(zoneFolder, goodId, CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), style, rng, onGather)
		end
	end
end

-- Deep Mine -----------------------------------------------------------------------------
-- Every world has a mine lift on the surface and five cavern levels below it.
-- The lift's prompt opens the Mine panel (pick a level); the server checks
-- you're equipped for that depth (Rules.depthBlock) and moves you down.

type MineLook = { rock: Color3, rockMaterial: Enum.Material, floor: Color3, timber: Color3, accent: Color3, snow: boolean, lava: boolean }
local MINE_LOOKS: { [string]: MineLook } = {
	main = { rock = Color3.fromRGB(132, 112, 96), rockMaterial = Enum.Material.Slate, floor = Color3.fromRGB(112, 92, 78), timber = C.woodDark, accent = Color3.fromRGB(255, 200, 90), snow = false, lava = false },
	frost = { rock = Color3.fromRGB(150, 176, 204), rockMaterial = Enum.Material.Glacier, floor = Color3.fromRGB(120, 144, 172), timber = Color3.fromRGB(96, 74, 60), accent = Color3.fromRGB(150, 220, 255), snow = true, lava = false },
	ember = { rock = Color3.fromRGB(70, 50, 50), rockMaterial = Enum.Material.Basalt, floor = Color3.fromRGB(56, 40, 40), timber = Color3.fromRGB(70, 46, 36), accent = Color3.fromRGB(255, 120, 40), snow = false, lava = true },
}

local function mineLantern(parent: Instance, cf: CFrame, look: MineLook, range: number)
	part({ Name = "LanternCap", Parent = parent, Size = Vector3.new(1.1, 0.3, 1.1), CFrame = cf * CFrame.new(0, 0.65, 0), Color = C.ink, Material = Enum.Material.Metal })
	local glass = part({ Name = "Lantern", Parent = parent, Size = Vector3.new(0.8, 1, 0.8), CFrame = cf, Color = look.accent, Material = Enum.Material.Neon, CanCollide = false })
	K.glow(glass, look.accent, range, 1.4)
end

-- A lump of rock studded with chunks of the ores this level turns up, picked
-- at random with the level's odds (rarer ores glow).
local function oreVein(rock: Color3, realmId: string, depth: number): NodeBuilder
	return function(model: Model, at: CFrame, rng: Random): BasePart
		local s = rng:NextNumber(3.8, 4.8)
		local main = part({ Name = "Rock", Parent = model, Size = Vector3.new(s, s * 0.8, s), CFrame = at * CFrame.new(0, s * 0.3, 0) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25)), Color = rock, Material = Enum.Material.Slate })
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local r = s * rng:NextNumber(0.32, 0.45)
			local size = rng:NextNumber(0.8, 1.4)
			local ore = Rules.rollOre(realmId, depth, rng:NextNumber())
			part({ Name = "Ore", Parent = model, Size = Vector3.new(size, size * 1.3, size), CFrame = at * CFrame.new(math.cos(a) * r, s * rng:NextNumber(0.35, 0.75), math.sin(a) * r) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), rng:NextNumber(0, 3)), Color = Color3.fromHex(ore.color), Material = if (ore.tier or 1) >= 3 then Enum.Material.Neon else Enum.Material.Metal, CanCollide = false })
		end
		return main
	end
end

-- The mine lift on the surface: a timber headframe with a pulley over a lift
-- cage, built into a rocky hill, with rails, a loaded cart and a cobble path
-- from the plaza.
local function buildMineEntrance(realmId: string)
	local look = MINE_LOOKS[realmId] or MINE_LOOKS.main
	local center = Places.CENTERS[realmId]
	local at = Places.mineEntrance(realmId)
	local m = group(root, "DeepMine")
	local cf = CFrame.lookAt(at, Vector3.new(center.X, 0, center.Z)) -- front (-Z) faces the plaza
	local function rel(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local toward = (Vector3.new(center.X, 0, center.Z) - at).Unit
	Layout.claim(at - toward * 4, 15)

	-- Path from the plaza
	local start = center + (at - center).Unit * 23
	local pathEnd = at + toward * 7
	strip(m, start, pathEnd, 7, PATH_COLORS[realmId] or C.path)
	Layout.claimLine(start, pathEnd, 4)

	-- Rocky hill behind
	local rng = Random.new(#realmId * 31)
	for i = 0, 8 do
		local a = (i / 8) * math.pi
		local s = rng:NextNumber(9, 14)
		local rock = part({ Name = "Hill", Parent = m, Size = Vector3.one * s, CFrame = rel(math.cos(a) * 9, s / 2 - 1.5 + math.sin(a) * 3, 6 + math.sin(a) * 4) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, math.pi), rng:NextNumber(-0.2, 0.2)), Color = look.rock:Lerp(C.ink, rng:NextNumber(0, 0.12)), Material = look.rockMaterial })
		if look.snow then
			part({ Name = "Snow", Parent = m, Size = Vector3.new(s * 0.8, 0.8, s * 0.8), CFrame = rock.CFrame * CFrame.new(0, s / 2, 0), Color = Color3.fromRGB(248, 252, 255), Material = Enum.Material.Snow })
		end
	end
	if look.lava then
		for _, x in { -6, 7 } do
			local crack = part({ Name = "LavaCrack", Parent = m, Size = Vector3.new(0.6, 9, 0.6), CFrame = rel(x, 5, 1.2) * CFrame.Angles(0, 0, math.rad(x * 2)), Color = look.accent, Material = Enum.Material.Neon, CanCollide = false })
			K.glow(crack, look.accent, 12, 1)
		end
	end
	-- Dark tunnel behind the lift
	part({ Name = "Tunnel", Parent = m, Size = Vector3.new(8, 9, 2), CFrame = rel(0, 4.5, 2.4), Color = Color3.fromRGB(14, 12, 16) })

	-- Headframe: two tall legs with braces, a crossbeam and a pulley wheel
	for _, x in { -4.5, 4.5 } do
		part({ Name = "Leg", Parent = m, Size = Vector3.new(1, 19, 1), CFrame = rel(x, 9.5, 0), Color = look.timber, Material = Enum.Material.Wood })
		part({ Name = "Brace", Parent = m, Size = Vector3.new(0.6, 12, 0.6), CFrame = rel(x, 6, -2.6) * CFrame.Angles(math.rad(-25), 0, 0), Color = look.timber, Material = Enum.Material.Wood })
	end
	part({ Name = "Crossbeam", Parent = m, Size = Vector3.new(11, 1, 1.2), CFrame = rel(0, 19, 0), Color = look.timber, Material = Enum.Material.Wood })
	local wheel = part({ Name = "Pulley", Parent = m, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 4, 4), CFrame = rel(0, 20.4, 0), Color = Color3.fromRGB(80, 84, 96), Material = Enum.Material.Metal })
	wheel.CanCollide = false
	for _, x in { -1.6, 1.6 } do
		part({ Name = "Cable", Parent = m, Size = Vector3.new(0.15, 12, 0.15), CFrame = rel(x, 14, 0), Color = C.ink, CanCollide = false })
	end

	-- Lift cage: platform, bars on three sides, a roof and the control lever
	local metal = Color3.fromRGB(96, 100, 112)
	part({ Name = "LiftFloor", Parent = m, Size = Vector3.new(7, 0.6, 6), CFrame = rel(0, 0.3, 0), Color = metal, Material = Enum.Material.DiamondPlate })
	part({ Name = "LiftRoof", Parent = m, Size = Vector3.new(7.4, 0.5, 6.4), CFrame = rel(0, 8, 0), Color = metal, Material = Enum.Material.Metal })
	for _, x in { -3.4, -1.7, 0, 1.7, 3.4 } do
		part({ Name = "Bar", Parent = m, Size = Vector3.new(0.25, 7.4, 0.25), CFrame = rel(x, 4.2, 2.9), Color = metal, Material = Enum.Material.Metal })
	end
	for _, side in { -1, 1 } do
		for _, z in { -2.8, -0.9, 0.9 } do
			part({ Name = "Bar", Parent = m, Size = Vector3.new(0.25, 7.4, 0.25), CFrame = rel(side * 3.4, 4.2, z), Color = metal, Material = Enum.Material.Metal })
		end
	end
	local lever = part({ Name = "LiftControls", Parent = m, Size = Vector3.new(1.4, 3.2, 1), CFrame = rel(-6.4, 1.6, -3.6), Color = look.accent:Lerp(C.ink, 0.3), Material = Enum.Material.Metal })
	part({ Name = "Lever", Parent = m, Size = Vector3.new(0.25, 1.6, 0.25), CFrame = rel(-6.4, 3.6, -3.6) * CFrame.Angles(math.rad(-30), 0, 0), Color = C.ink })
	part({ Name = "LeverKnob", Parent = m, Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, CFrame = rel(-6.4, 4.3, -4), Color = Color3.fromRGB(220, 50, 50) })
	local p = prompt(lever, "Ride the Lift", "⛏️ Deep Mine", 0, 14)
	p:SetAttribute("OpenPanel", "mine")
	p.KeyboardKeyCode = Enum.KeyCode.E

	-- Sign, lanterns, rails and a loaded cart out front
	local board = part({ Name = "SignBoard", Parent = m, Size = Vector3.new(12, 2.8, 0.5), CFrame = rel(0, 16.6, -0.9), Color = look.timber:Lerp(Color3.new(1, 1, 1), 0.1), Material = Enum.Material.WoodPlanks })
	boardText(board, "⛏️ DEEP MINE", Color3.new(1, 1, 1))
	local tip = part({ Name = "TipBoard", Parent = m, Size = Vector3.new(9, 1.4, 0.3), CFrame = rel(0, 12.4, -0.8), Color = look.accent:Lerp(C.ink, 0.35) })
	local upgrade = Upgrades.byId[Upgrades.DEPTH[realmId] or "gear"]
	boardText(tip, `Better {upgrade.name} = deeper!`, Color3.new(1, 1, 1))
	mineLantern(m, rel(-4.5, 10, -0.9), look, 16)
	mineLantern(m, rel(4.5, 10, -0.9), look, 16)
	K.rails(m, rel(4.8, 0, -3.5), 9)
	local ore = Rules.oreAt(realmId, 1)
	K.minecart(m, rel(4.8, 0, -6.5), if ore then Color3.fromHex(ore.color) else look.accent, false)
end

-- One cavern level of a world's mine: rock walls and ceiling, timber
-- supports with lanterns, the lift back up, and veins of this level's ore.
local function buildMineLevel(realmId: string, depth: number, onGather: GatherHandler)
	local look = MINE_LOOKS[realmId] or MINE_LOOKS.main
	local center = Places.mineLevel(realmId, depth)
	local half = Places.MINE_HALF
	local height = 24
	local signature = Rules.oreAt(realmId, depth) :: Goods.Good -- the ore this level is best for, which tints it
	local oreColor = Color3.fromHex(signature.color)
	local dark = (depth - 1) / 4 -- deeper levels are darker and stranger
	local rockColor = look.rock:Lerp(C.ink, 0.25 + dark * 0.35):Lerp(oreColor, 0.08 * depth)
	local m = folder(`{realmId:upper()}_MINE_{depth}`)
	local rng = Random.new(depth * 101 + #realmId)
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(center + Vector3.new(x, y, z))
	end

	-- Floor, ceiling and walls (thick, so nothing shows through)
	local span = half * 2 + 8
	part({ Name = "Floor", Parent = m, Size = Vector3.new(span, 4, span), CFrame = at(0, -2, 0), Color = look.floor:Lerp(C.ink, 0.2 + dark * 0.3), Material = look.rockMaterial })
	part({ Name = "Ceiling", Parent = m, Size = Vector3.new(span, 4, span), CFrame = at(0, height + 2, 0), Color = rockColor, Material = look.rockMaterial })
	for _, side in { -1, 1 } do
		part({ Name = "Wall", Parent = m, Size = Vector3.new(4, height + 8, span), CFrame = at(side * (half + 2), height / 2, 0), Color = rockColor, Material = look.rockMaterial })
		part({ Name = "Wall", Parent = m, Size = Vector3.new(span, height + 8, 4), CFrame = at(0, height / 2, side * (half + 2)), Color = rockColor, Material = look.rockMaterial })
	end
	-- Lumpy rock along the walls, and stalactites
	for _, side in { -1, 1 } do
		for i = -3, 3 do
			for _, alongX in { true, false } do
				local s = rng:NextNumber(6, 10)
				local along = i * 9.5 + rng:NextNumber(-2, 2)
				if alongX and side == -1 and math.abs(along) < 10 then
					continue -- the lift stands here
				end
				local pos = if alongX then Vector3.new(along, s * 0.3, side * (half - 0.5)) else Vector3.new(side * (half - 0.5), s * 0.3, along)
				part({ Name = "WallRock", Parent = m, Size = Vector3.one * s, CFrame = at(pos.X, pos.Y, pos.Z) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 3), rng:NextNumber(0, 1)), Color = rockColor:Lerp(C.ink, rng:NextNumber(0, 0.15)), Material = look.rockMaterial })
			end
		end
	end
	for _ = 1, 14 do
		local x, z = rng:NextNumber(-half + 6, half - 6), rng:NextNumber(-half + 6, half - 6)
		local h = rng:NextNumber(3, 7)
		for k = 0, 2 do
			local w = (3 - k) * 0.8
			part({ Name = "Stalactite", Parent = m, Size = Vector3.new(w, h / 3, w), CFrame = at(x, height - k * h / 3 - h / 6, z) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = rockColor, Material = look.rockMaterial, CanCollide = false })
		end
	end

	-- Timber supports with lanterns
	for _, x in { -14, 14 } do
		for _, z in { -14, 14 } do
			part({ Name = "Post", Parent = m, Size = Vector3.new(1, height, 1), CFrame = at(x, height / 2, z), Color = look.timber, Material = Enum.Material.Wood })
			part({ Name = "Beam", Parent = m, Size = Vector3.new(1, 1, 8), CFrame = at(x, height - 1.5, z), Color = look.timber, Material = Enum.Material.Wood })
			mineLantern(m, at(x, height - 3.2, z + 2.5), look, 28)
		end
	end

	-- The lift back up (and further down), by the north wall
	local liftZ = -half + 5
	local metal = Color3.fromRGB(96, 100, 112)
	part({ Name = "LiftFloor", Parent = m, Size = Vector3.new(7, 0.6, 6), CFrame = at(0, 0.3, liftZ), Color = metal, Material = Enum.Material.DiamondPlate })
	part({ Name = "LiftRoof", Parent = m, Size = Vector3.new(7.4, 0.5, 6.4), CFrame = at(0, 8, liftZ), Color = metal, Material = Enum.Material.Metal })
	for _, x in { -3.4, 3.4 } do
		for _, z in { -2.8, 0, 2.8 } do
			part({ Name = "Bar", Parent = m, Size = Vector3.new(0.25, 7.4, 0.25), CFrame = at(x, 4.2, liftZ + z), Color = metal, Material = Enum.Material.Metal })
		end
		part({ Name = "Rail", Parent = m, Size = Vector3.new(0.6, height, 0.6), CFrame = at(x * 1.15, height / 2, liftZ - 2.6), Color = look.timber, Material = Enum.Material.Wood })
	end
	local controls = part({ Name = "LiftControls", Parent = m, Size = Vector3.new(1.4, 3.2, 1), CFrame = at(-4.8, 1.6, liftZ + 3.4), Color = look.accent:Lerp(C.ink, 0.3), Material = Enum.Material.Metal })
	local p = prompt(controls, "Ride the Lift", "⛏️ Deep Mine", 0, 14)
	p:SetAttribute("OpenPanel", "mine")
	p.KeyboardKeyCode = Enum.KeyCode.E
	local board = part({ Name = "DepthSign", Parent = m, Size = Vector3.new(16, 3, 0.5), CFrame = at(0, 12, -half + 0.6) * CFrame.Angles(0, math.pi, 0), Color = look.timber:Lerp(Color3.new(1, 1, 1), 0.1), Material = Enum.Material.WoodPlanks })
	local icons = {}
	for _, o in Rules.oreOdds(realmId, depth) do
		table.insert(icons, o.good.icon)
	end
	boardText(board, `LEVEL {depth}  {table.concat(icons, " ")}`, Color3.new(1, 1, 1))

	-- Rails and a cart across the floor, and the world's own touches
	K.rails(m, at(-22, 0, 20) * CFrame.Angles(0, math.rad(-90), 0), 24)
	K.minecart(m, at(-12, 0, 20) * CFrame.Angles(0, math.rad(90), 0), oreColor, depth >= 3)
	local reserved: { { at: Vector3, r: number } } = {
		{ at = Vector3.new(0, 0, liftZ), r = 9 },
		{ at = Vector3.new(-12, 0, 20), r = 14 },
	}
	for _, x in { -14, 14 } do
		for _, z in { -14, 14 } do
			table.insert(reserved, { at = Vector3.new(x, 0, z), r = 2 })
		end
	end
	local function extra(x: number, z: number, r: number, build: (CFrame) -> ())
		table.insert(reserved, { at = Vector3.new(x, 0, z), r = r })
		build(at(x, 0, z))
	end
	if look.lava then
		for _, spot in { { half - 8, half - 8 }, { -half + 8, -half + 12 } } do
			extra(spot[1], spot[2], 5, function(cf)
				local pool = part({ Name = "LavaPool", Parent = m, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 8, 8), CFrame = cf * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = look.accent, Material = Enum.Material.Neon, CanCollide = false })
				K.glow(pool, look.accent, 20, 1.5)
			end)
		end
	elseif look.snow then
		for _, spot in { { half - 8, half - 8 }, { -half + 8, -half + 12 } } do
			extra(spot[1], spot[2], 4, function(cf)
				K.crystalCluster(m, cf, Color3.fromRGB(170, 230, 255), 1.6, rng)
			end)
		end
	else
		extra(half - 8, half - 8, 4, function(cf)
			K.barrel(m, cf)
			K.barrel(m, cf * CFrame.new(2.2, 0, 0.6))
		end)
	end

	-- Ore veins
	local style: NodeStyle = { object = "Ore Vein", label = "⛏️ Ore Vein", action = "Mine", charges = 3, build = oreVein(rockColor:Lerp(Color3.new(1, 1, 1), 0.08), realmId, depth), hold = 0.8, respawn = 25, depth = depth }
	local placed: { Vector3 } = {}
	local attempts = 0
	while #placed < 10 and attempts < 800 do
		attempts += 1
		local pos = Vector3.new(rng:NextNumber(-half + 7, half - 7), 0, rng:NextNumber(-half + 7, half - 7))
		local ok = true
		for _, other in placed do
			if (other - pos).Magnitude < 9 then
				ok = false
				break
			end
		end
		for _, spot in reserved do
			if (spot.at - pos).Magnitude < spot.r + 4 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(placed, pos)
			gatherNode(m, (Rules.oreAt(realmId, 1) :: Goods.Good).id, at(pos.X, 0, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), style, rng, onGather)
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

-- The wall round each world's play area, in the world's style: a stone town
-- wall with battlements, lanterns and banners in Market Town; a glowing ice
-- wall with snow and icicles in Frostpeak; an obsidian wall with lava seams,
-- spikes and fire braziers in Emberfall. Pillars stand at every corner so the
-- straight wall sections meet cleanly. An invisible guard just behind it
-- stops anyone climbing over.
local BARRIER_SIDES = 56
local BARRIER_HEIGHT = 8
local BARRIER_THICK = 1.6
local BANNER_COLORS = { Color3.fromRGB(220, 60, 60), Color3.fromRGB(60, 120, 220), Color3.fromRGB(240, 180, 40), Color3.fromRGB(150, 80, 210) }

local function buildBarrier(realmId: string, parent: Instance)
	local center = Places.CENTERS[realmId]
	local radius = Places.BARRIER_RADIUS
	local m = group(parent, "Barrier")
	local step = math.pi * 2 / BARRIER_SIDES
	local chord = 2 * radius * math.sin(step / 2)
	local pillarSize = 3.4
	local length = chord - pillarSize + 0.4 -- tucked a little into the pillars at each end
	local h, t = BARRIER_HEIGHT, BARRIER_THICK

	for i = 0, BARRIER_SIDES - 1 do
		local a = i * step
		local corner = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		local pcf = CFrame.lookAt(corner, Vector3.new(center.X, 0, center.Z))
		Layout.claim(corner, pillarSize * 0.75)
		local mid = a + step / 2
		local midAt = center + Vector3.new(math.cos(mid), 0, math.sin(mid)) * radius * math.cos(step / 2)
		local wcf = CFrame.lookAt(midAt, Vector3.new(center.X, 0, center.Z)) -- front (-Z) faces into the world
		Layout.claim(midAt, t)
		local lit = i % 4 == 0

		-- Invisible guard, just outside: the wall is the barrier you see, this one can't be jumped
		part({ Name = "Guard", Parent = m, Size = Vector3.new(chord + 1, 60, 1), CFrame = wcf * CFrame.new(0, 30, 2), Transparency = 1, CastShadow = false, CanQuery = false })

		if realmId == "frost" then
			local pillar = part({ Name = "Pillar", Parent = m, Size = Vector3.new(pillarSize, h + 3, pillarSize), CFrame = pcf * CFrame.new(0, (h + 3) / 2, 0), Color = Color3.fromRGB(170, 214, 245), Material = Enum.Material.Glacier })
			pillar.Transparency = 0.05
			part({ Name = "SnowCap", Parent = m, Size = Vector3.new(pillarSize + 0.6, 0.8, pillarSize + 0.6), CFrame = pcf * CFrame.new(0, h + 3.4, 0), Color = Color3.fromRGB(248, 252, 255), Material = Enum.Material.Snow })
			local crystal = part({ Name = "Crystal", Parent = m, Size = Vector3.one * 1.6, CFrame = pcf * CFrame.new(0, h + 5, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0), Color = Color3.fromRGB(140, 230, 255), Material = Enum.Material.Neon, CanCollide = false })
			if lit then
				K.glow(crystal, Color3.fromRGB(140, 220, 255), 18, 1.2)
			end
			local wall = part({ Name = "IceWall", Parent = m, Size = Vector3.new(length, h, t), CFrame = wcf * CFrame.new(0, h / 2, 0), Color = Color3.fromRGB(190, 230, 255), Material = Enum.Material.Ice })
			wall.Transparency = 0.2
			part({ Name = "Snow", Parent = m, Size = Vector3.new(length, 0.9, t + 0.6), CFrame = wcf * CFrame.new(0, h + 0.45, 0), Color = Color3.fromRGB(248, 252, 255), Material = Enum.Material.Snow })
			for k = 1, 5 do
				local x = -length / 2 + k * length / 6
				for _, side in { -1, 1 } do
					local drip = 1 + ((i + k) % 3) * 0.6
					local icicle = part({ Name = "Icicle", Parent = m, Size = Vector3.new(0.35, drip, 0.35), CFrame = wcf * CFrame.new(x + side * 0.6, h - drip / 2, side * (t / 2 + 0.35)), Color = Color3.fromRGB(215, 240, 255), Material = Enum.Material.Glass, CanCollide = false })
					icicle.Transparency = 0.15
				end
			end
		elseif realmId == "ember" then
			local basalt = Color3.fromRGB(52, 40, 42)
			part({ Name = "Pillar", Parent = m, Size = Vector3.new(pillarSize, h + 2, pillarSize), CFrame = pcf * CFrame.new(0, (h + 2) / 2, 0), Color = basalt, Material = Enum.Material.Basalt })
			local bowl = part({ Name = "Brazier", Parent = m, Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 3.4, 3.4), CFrame = pcf * CFrame.new(0, h + 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(40, 36, 40), Material = Enum.Material.Metal })
			local coals = part({ Name = "Coals", Parent = m, Size = Vector3.new(2.2, 0.6, 2.2), CFrame = pcf * CFrame.new(0, h + 3.3, 0), Color = Color3.fromRGB(255, 110, 40), Material = Enum.Material.Neon, CanCollide = false })
			if lit then
				local fire = Instance.new("Fire")
				fire.Size = 4
				fire.Heat = 8
				fire.Color = Color3.fromRGB(255, 140, 40)
				fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
				fire.Parent = coals
				K.glow(bowl, Color3.fromRGB(255, 120, 40), 20, 1.5)
			end
			part({ Name = "ObsidianWall", Parent = m, Size = Vector3.new(length, h, t), CFrame = wcf * CFrame.new(0, h / 2, 0), Color = Color3.fromRGB(44, 32, 38), Material = Enum.Material.Basalt })
			-- Glowing lava seams on both faces
			for _, side in { -1, 1 } do
				part({ Name = "LavaSeam", Parent = m, Size = Vector3.new(length - 0.6, 0.45, 0.2), CFrame = wcf * CFrame.new(0, h * 0.42, side * (t / 2 + 0.05)), Color = Color3.fromRGB(255, 100, 30), Material = Enum.Material.Neon, CanCollide = false })
			end
			part({ Name = "Coping", Parent = m, Size = Vector3.new(length, 0.5, t + 0.4), CFrame = wcf * CFrame.new(0, h + 0.25, 0), Color = basalt, Material = Enum.Material.Basalt })
			for k = 1, 4 do
				local x = -length / 2 + k * length / 5
				part({ Name = "Spike", Parent = m, Size = Vector3.new(0.7, 2.4, 0.7), CFrame = wcf * CFrame.new(x, h + 1.6, 0) * CFrame.Angles(0, math.rad(45), 0), Color = Color3.fromRGB(30, 26, 30), Material = Enum.Material.Metal })
			end
		else
			-- Market Town: a stone town wall with battlements, lanterns and banners
			local stone = Color3.fromRGB(196, 186, 168)
			part({ Name = "Pillar", Parent = m, Size = Vector3.new(pillarSize, h + 2.6, pillarSize), CFrame = pcf * CFrame.new(0, (h + 2.6) / 2, 0), Color = stone:Lerp(C.ink, 0.08), Material = Enum.Material.Cobblestone })
			part({ Name = "PillarCap", Parent = m, Size = Vector3.new(pillarSize + 0.8, 0.8, pillarSize + 0.8), CFrame = pcf * CFrame.new(0, h + 3, 0), Color = Color3.fromRGB(150, 140, 130), Material = Enum.Material.Slate })
			part({ Name = "LanternPost", Parent = m, Size = Vector3.new(0.3, 1.6, 0.3), CFrame = pcf * CFrame.new(0, h + 4.2, 0), Color = C.ink, Material = Enum.Material.Metal })
			local lantern = part({ Name = "Lantern", Parent = m, Size = Vector3.new(1, 1.2, 1), CFrame = pcf * CFrame.new(0, h + 5.4, 0), Color = Color3.fromRGB(255, 220, 140), Material = Enum.Material.Neon, CanCollide = false })
			part({ Name = "LanternCap", Parent = m, Size = Vector3.new(1.4, 0.35, 1.4), CFrame = pcf * CFrame.new(0, h + 6.15, 0), Color = C.ink, Material = Enum.Material.Metal })
			if lit then
				K.glow(lantern, Color3.fromRGB(255, 210, 140), 18, 1)
			end
			part({ Name = "TownWall", Parent = m, Size = Vector3.new(length, h, t), CFrame = wcf * CFrame.new(0, h / 2, 0), Color = stone, Material = Enum.Material.Cobblestone })
			part({ Name = "Coping", Parent = m, Size = Vector3.new(length, 0.5, t + 0.4), CFrame = wcf * CFrame.new(0, h + 0.25, 0), Color = Color3.fromRGB(160, 150, 138), Material = Enum.Material.Slate })
			for k = -1, 1 do
				part({ Name = "Merlon", Parent = m, Size = Vector3.new(2.4, 1.4, t + 0.2), CFrame = wcf * CFrame.new(k * length / 3, h + 1.2, 0), Color = stone, Material = Enum.Material.Cobblestone })
			end
			if i % 2 == 1 then
				-- A banner hanging on the inside face, under a gold rod
				local color = BANNER_COLORS[(i // 2) % #BANNER_COLORS + 1]
				local face = wcf * CFrame.new(0, 0, -(t / 2 + 0.12))
				part({ Name = "BannerRod", Parent = m, Size = Vector3.new(3.8, 0.25, 0.25), CFrame = face * CFrame.new(0, h - 0.6, -0.1), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Metal, CanCollide = false })
				part({ Name = "Banner", Parent = m, Size = Vector3.new(3.2, 4.6, 0.12), CFrame = face * CFrame.new(0, h - 3.1, 0), Color = color, Material = Enum.Material.Fabric, CanCollide = false })
				part({ Name = "BannerTip", Parent = m, Size = Vector3.new(1.6, 1.6, 0.12), CFrame = face * CFrame.new(0, h - 5.4, 0) * CFrame.Angles(0, 0, math.rad(45)), Color = color, Material = Enum.Material.Fabric, CanCollide = false })
				part({ Name = "BannerStripe", Parent = m, Size = Vector3.new(3.2, 0.4, 0.14), CFrame = face * CFrame.new(0, h - 1.6, -0.02), Color = Color3.fromRGB(255, 220, 90), Material = Enum.Material.Fabric, CanCollide = false })
			end
		end
	end
end

-- The world's wall, big scenery in a ring just outside it, and smaller bits
-- in the open ground between zones.
local function buildBorder(realmId: string, rng: Random)
	local theme = THEMES[realmId]
	local center = Places.CENTERS[realmId]
	local border = folder(if realmId == "main" then "Border" else realmId:upper() .. "_BORDER")
	buildBarrier(realmId, border)
	-- A ring of big scenery round the edge, each with room of its own
	local n = 72
	for i = 1, n do
		local a = i / n * math.pi * 2 + rng:NextNumber(-0.03, 0.03)
		local r = rng:NextNumber(Places.BARRIER_RADIUS + 10, Places.BARRIER_RADIUS + 22) -- just outside the wall
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
		local r = rng:NextNumber(34, Places.BARRIER_RADIUS - 10)
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
	groundDisc(base, center, theme.ground)
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

	-- The Deep Mine in every world: the lift up top and five levels below
	for _, realmId in { "main", "frost", "ember" } do
		buildMineEntrance(realmId)
		for depth = 1, Rules.MINE_DEPTHS do
			buildMineLevel(realmId, depth, onGather)
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
		Backdrop.build(root, realmId, sectors, THEMES[realmId].ground, rng)
	end
end

return World
