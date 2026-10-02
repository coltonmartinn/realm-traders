--!strict
-- Draws each player's Helper Bee (a bobbing 🐝 over the shoulder) and their
-- equipped pets (hopping along behind them). Purely visual; driven by the
-- player's "Helper" and "Pets" attributes so everyone sees everyone's.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pets = require(ReplicatedStorage.Shared.Pets)
local Ui = require(script.Parent.Ui)

local Helpers = {}

type Bee = { anchor: Part, gui: BillboardGui, label: TextLabel, phase: number }

local bees: { [Player]: Bee } = {}

type PetVisual = { anchor: Part, label: TextLabel, phase: number, slot: number }
local pets: { [Player]: { PetVisual } } = {}

local function makePet(player: Player, petId: string, slot: number): PetVisual?
	local pet = Pets.byId[petId]
	if not pet then
		return nil
	end
	local anchor = Ui.new("Part", {
		Name = `{player.Name}_Pet_{petId}`,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one,
		Parent = workspace,
	})
	-- A soft colored glow under the pet, then the pet itself
	local gui = Ui.new("BillboardGui", { Parent = anchor, Size = UDim2.fromScale(3, 3), LightInfluence = 0, MaxDistance = 150 })
	Ui.new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.85, 0.85),
		BackgroundColor3 = Color3.fromHex(pet.color),
		BackgroundTransparency = if pet.exotic then 0.35 else 0.6,
	}, { Ui.round() })
	local label = Ui.text({ Parent = gui, Size = UDim2.fromScale(1, 1), Text = pet.icon, TextScaled = true })
	if pet.exotic then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromHex(pet.color)
		sparkles.Parent = anchor
	end
	return { anchor = anchor, label = label, phase = math.random() * 10, slot = slot }
end

local function syncPets(player: Player)
	for _, v in pets[player] or {} do
		v.anchor:Destroy()
	end
	local list = {}
	local equipped = player:GetAttribute("Pets")
	if type(equipped) == "string" and equipped ~= "" then
		for slot, id in string.split(equipped, ",") do
			local v = makePet(player, id, slot)
			if v then
				table.insert(list, v)
			end
		end
	end
	pets[player] = list
end

local function makeBee(player: Player): Bee
	local anchor = Ui.new("Part", {
		Name = player.Name .. "_HelperBee",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one,
		Parent = workspace,
	})
	local gui = Ui.new("BillboardGui", {
		Parent = anchor,
		Size = UDim2.fromScale(2.6, 2.6),
		LightInfluence = 0,
		MaxDistance = 150,
	})
	local label = Ui.text({ Parent = gui, Size = UDim2.fromScale(1, 1), Text = "🐝", TextScaled = true })
	return { anchor = anchor, gui = gui, label = label, phase = math.random() * 10 }
end

local function sync(player: Player)
	local level = player:GetAttribute("Helper")
	local has = type(level) == "number" and level > 1
	local bee = bees[player]
	if has and not bee then
		bees[player] = makeBee(player)
	elseif not has and bee then
		bee.anchor:Destroy()
		bees[player] = nil
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("Helper"):Connect(function()
		sync(player)
	end)
	player:GetAttributeChangedSignal("Pets"):Connect(function()
		syncPets(player)
	end)
	sync(player)
	syncPets(player)
end

function Helpers.init()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local bee = bees[player]
		if bee then
			bee.anchor:Destroy()
			bees[player] = nil
		end
		for _, v in pets[player] or {} do
			v.anchor:Destroy()
		end
		pets[player] = nil
	end)

	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		for player, bee in bees do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart then
				-- Hover behind the right shoulder, bobbing and drifting a little
				local p = bee.phase + t
				local goal = (rootPart.CFrame * CFrame.new(2.4 + math.sin(p * 0.9) * 0.6, 2.2 + math.sin(p * 3) * 0.35, 1.8)).Position
				local from = bee.anchor.Position
				bee.anchor.Position = if (goal - from).Magnitude > 40 then goal else from:Lerp(goal, math.min(1, dt * 6))
				bee.label.Rotation = math.sin(p * 6) * 8
			end
		end
		-- Pets trail behind in a little fan, hopping as they go
		for player, list in pets do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart then
				for _, v in list do
					local side = (v.slot - (#list + 1) / 2) * 3
					local back = 4.5 + math.abs(side) * 0.3
					local hop = math.abs(math.sin((t + v.phase) * 5)) * 0.8
					local goal = (rootPart.CFrame * CFrame.new(side, -1.2 + hop, back)).Position
					local from = v.anchor.Position
					v.anchor.Position = if (goal - from).Magnitude > 40 then goal else from:Lerp(goal, math.min(1, dt * 8))
					v.label.Rotation = math.sin((t + v.phase) * 5) * 6
				end
			end
		end
	end)
end

return Helpers
