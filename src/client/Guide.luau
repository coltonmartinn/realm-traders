--!strict
-- Points the player at what to do next: a glowing line along the ground from
-- their feet to the target and a bouncing arrow above it (arrows and trails
-- are Roblox's recommended onboarding cues). The target comes from the current
-- goal's `where`; a full backpack overrides it with the Market. Inside a zone
-- it points at the nearest node that can be gathered.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Places = require(ReplicatedStorage.Shared.Places)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local HIDE_WITHIN = 7 -- studs: close enough, stop drawing the line
local GOLD = Color3.fromRGB(255, 214, 70)

local Guide = {}

Guide.distance = nil :: number?
Guide.placeId = nil :: string?

local anchor: Part
local targetAttachment: Attachment
local beam: Beam
local arrow: BillboardGui
local arrowLabel: TextLabel
local footAttachment: Attachment? = nil

local function targetFor(profile: Rules.Profile, p: Rules.Wallet, rootPos: Vector3): (string?, Vector3?)
	local placeId: string? = nil
	if Rules.space(p) <= 0 then
		placeId = Places.marketOf(p.realm).id
	else
		local goal = Rules.currentGoal(p)
		placeId = if goal then goal.where else nil
	end
	if not placeId then
		return nil, nil
	end
	local place = Places.byId[placeId]
	if place.kind == "shop" then
		return placeId, place.center
	end
	-- Locked zone: send them to the Outfitter first
	if Rules.lockReason(profile, p, place.gearLevel, place.rebirths) then
		local outfitter = Places.byId[if p.realm == "main" then "outfitter" else p.realm .. "_outfitter"]
		return outfitter.id, outfitter.center
	end
	-- Outside the zone: head for the gate. Inside: nearest gatherable node.
	local flat = (rootPos - place.center) * Vector3.new(1, 0, 1)
	if flat.Magnitude > place.radius + 2 then
		return placeId, Places.gate(place)
	end
	local zone = workspace:FindFirstChild("World") and (workspace :: any).World:FindFirstChild(place.name:upper())
	local best, bestDist = nil, math.huge
	if zone then
		for _, model in zone:GetChildren() do
			local prompt = model:IsA("Model") and model:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt and prompt.Enabled and prompt:GetAttribute("Good") == place.good then
				local pos = (prompt.Parent :: BasePart).Position
				local d = (pos - rootPos).Magnitude
				if d < bestDist then
					best, bestDist = pos, d
				end
			end
		end
	end
	return placeId, best or place.center
end

local function attachToCharacter(character: Model)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not rootPart then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = "GuideFoot"
	a.Position = Vector3.new(0, -2.6, 0)
	a.Parent = rootPart
	footAttachment = a
	beam.Attachment0 = a
end

function Guide.init()
	anchor = Ui.new("Part", {
		Name = "GuideTarget",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one,
		Parent = workspace,
	})
	targetAttachment = Ui.new("Attachment", { Parent = anchor })

	beam = Ui.new("Beam", {
		Parent = anchor,
		Attachment1 = targetAttachment,
		Color = ColorSequence.new(GOLD),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.85, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Width0 = 1.1,
		Width1 = 1.1,
		FaceCamera = true,
		LightEmission = 0.6,
		LightInfluence = 0,
		Segments = 1,
	})

	arrow = Ui.new("BillboardGui", {
		Parent = anchor,
		Adornee = anchor,
		Size = UDim2.fromOffset(120, 110),
		StudsOffsetWorldSpace = Vector3.new(0, 9, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 1000,
	})
	arrowLabel = Ui.text({
		Parent = arrow,
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		TextSize = 22,
		Outline = 2.5,
	})
	Ui.text({
		Parent = arrow,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 80),
		Text = "▼",
		TextSize = 72,
		TextColor3 = GOLD,
		Outline = 3,
	})

	local player = Players.LocalPlayer
	if player.Character then
		task.spawn(attachToCharacter, player.Character)
	end
	player.CharacterAdded:Connect(attachToCharacter)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		arrow.StudsOffsetWorldSpace = Vector3.new(0, 8.5 + math.abs(math.sin(elapsed * 4)) * 1.6, 0)
	end)

	task.spawn(function()
		while true do
			Guide.update()
			task.wait(0.25)
		end
	end)
end

local LABELS: { [string]: string } = {
	Market = "Sell here!",
	Workshop = "Craft here!",
	Outfitter = "Upgrade here!",
}

function Guide.update()
	local profile, p = Store.profile, Store.wallet()
	local foot = footAttachment
	if not (profile and p and foot and foot.Parent) then
		beam.Enabled = false
		arrow.Enabled = false
		return
	end
	local rootPos = (foot.Parent :: BasePart).Position
	local placeId, target = targetFor(profile, p, rootPos)
	Guide.placeId = placeId
	if not (placeId and target) then
		Guide.distance = nil
		beam.Enabled = false
		arrow.Enabled = false
		return
	end
	anchor.Position = Vector3.new(target.X, 0.3, target.Z)
	local dist = ((rootPos - target) * Vector3.new(1, 0, 1)).Magnitude
	Guide.distance = dist
	beam.Enabled = dist > HIDE_WITHIN
	arrow.Enabled = true
	local place = Places.byId[placeId]
	if place.kind == "shop" then
		arrowLabel.Text = if Rules.space(p) <= 0 and place.panel == "market" then "Backpack full! Sell here" else LABELS[place.name]
	else
		local inside = ((rootPos - place.center) * Vector3.new(1, 0, 1)).Magnitude <= place.radius + 2
		arrowLabel.Text = if inside then Ui.controls("Hold E here!") else `{place.icon} {place.name}`
	end
	arrowLabel.TextColor3 = Theme.white
end

return Guide
