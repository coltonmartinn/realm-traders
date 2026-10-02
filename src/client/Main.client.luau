--!strict
-- Client entry point: builds the UI, feeds server updates into the Store,
-- and handles hotkeys, station prompts, gather feedback and the Mine gate.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CollectionPanel = require(script.Parent.CollectionPanel)
local CraftPanel = require(script.Parent.CraftPanel)
local DailyPanel = require(script.Parent.DailyPanel)
local Guide = require(script.Parent.Guide)
local Helpers = require(script.Parent.Helpers)
local Hud = require(script.Parent.Hud)
local MarketPanel = require(script.Parent.MarketPanel)
local QuestPanel = require(script.Parent.QuestPanel)
local NewsBar = require(script.Parent.NewsBar)
local PetPanel = require(script.Parent.PetPanel)
local MinePanel = require(script.Parent.MinePanel)
local ShopPanel = require(script.Parent.ShopPanel)
local Sounds = require(script.Parent.Sounds)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Travel = require(script.Parent.Travel)
local Ui = require(script.Parent.Ui)
local UpgradePanel = require(script.Parent.UpgradePanel)
local Window = require(script.Parent.Window)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local gui = Ui.new("ScreenGui", {
	Name = "MarketSimUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
})

Toasts.init(gui)
Window.init(gui)
Window.register("market", MarketPanel.new())
Window.register("craft", CraftPanel.new())
Window.register("upgrades", UpgradePanel.new())
Window.register("daily", DailyPanel.new())
Window.register("quests", QuestPanel.new())
Window.register("collection", CollectionPanel.new())
Window.register("shop", ShopPanel.new())
Window.register("pets", PetPanel.new())
Window.register("mine", MinePanel.new())
Travel.init(gui)
Guide.init()
Helpers.init()
Hud.init(gui)
NewsBar.init(gui)
Sounds.startMusic()

Store.subscribe(function()
	Window.refresh()
end)

-- Chat in the game's font too
task.spawn(function()
	local TextChatService = game:GetService("TextChatService")
	for _, className in { "ChatWindowConfiguration", "ChatInputBarConfiguration", "BubbleChatConfiguration" } do
		local config = TextChatService:FindFirstChildOfClass(className) or TextChatService:WaitForChild(className, 5)
		if config then
			pcall(function()
				(config :: any).FontFace = Theme.body
			end)
		end
	end
end)

Remotes.PlayerUpdate.OnClientEvent:Connect(Store.setProfile)
Remotes.MarketUpdate.OnClientEvent:Connect(Store.setMarket)
Remotes.Notify.OnClientEvent:Connect(Toasts.show)
Remotes.News.OnClientEvent:Connect(Store.setNews)

-- Studio-only: set the DebugPanel attribute on the local player to open a panel
-- from a test script ("" closes it).
if game:GetService("RunService"):IsStudio() then
	Players.LocalPlayer:GetAttributeChangedSignal("DebugPanel"):Connect(function()
		local name = Players.LocalPlayer:GetAttribute("DebugPanel")
		if type(name) == "string" and name ~= "" then
			Window.open(name)
		else
			Window.close()
		end
	end)
end

-- Show the daily reward the first time we learn it's waiting
task.spawn(function()
	while not Store.profile do
		task.wait(0.2)
	end
	task.wait(1.5)
	if DailyPanel.ready() and not Window.isOpen() then
		Window.open("daily")
	end
end)

local hotkeys: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.M] = "market",
	[Enum.KeyCode.C] = "craft",
	[Enum.KeyCode.U] = "upgrades",
	[Enum.KeyCode.Q] = "quests",
	[Enum.KeyCode.B] = "shop",
	[Enum.KeyCode.P] = "pets",
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local panel = hotkeys[input.KeyCode]
	if panel then
		Sounds.play("click")
		Window.toggle(panel)
	elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
		Window.close()
	end
end)

-- Gather feedback in the world: a "+2 🌳" that floats up from the node and a
-- burst of chips in the good's color, once the server confirms the gather.
local lastGatherPart: BasePart? = nil
local Goods = require(ReplicatedStorage.Shared.Goods)
local Rules = require(ReplicatedStorage.Shared.Rules)
local goodsById = {}
for _, g in Goods do
	goodsById[g.id] = g
end

local function gatherBurst(part: BasePart, goodId: string, amount: number)
	local good = goodsById[goodId]
	if not good then
		return
	end
	local color = Color3.fromHex(good.color)
	local anchor = Ui.new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one,
		CFrame = CFrame.new(part.Position + Vector3.new(0, 2.5, 0)),
		Parent = workspace,
	})
	local chips = Ui.new("ParticleEmitter", {
		Parent = anchor,
		Rate = 0,
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(10, 16),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -40, 0),
		Size = NumberSequence.new(0.45, 0.1),
		Color = ColorSequence.new(color),
		EmissionDirection = Enum.NormalId.Top,
	})
	chips:Emit(14)
	local bb = Ui.new("BillboardGui", {
		Parent = anchor,
		Size = UDim2.fromOffset(160, 50),
		StudsOffsetWorldSpace = Vector3.new(0, 1, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
	})
	local label = Ui.text({ Parent = bb, Size = UDim2.fromScale(1, 1), Text = `+{amount} {good.icon}`, TextSize = 34, Outline = 3 })
	Ui.tween(bb, 0.9, { StudsOffsetWorldSpace = Vector3.new(0, 5, 0) })
	task.delay(0.5, function()
		Ui.tween(label, 0.4, { TextTransparency = 1 })
	end)
	task.delay(1, function()
		anchor:Destroy()
	end)
end

Remotes.Notify.OnClientEvent:Connect(function(notice)
	local part = lastGatherPart
	if notice.kind == "gain" and notice.good and part and part.Parent then
		gatherBurst(part, notice.good, notice.amount or 1)
	end
end)

-- Shop counters open their panel; gather prompts make the node wobble.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local panel = prompt:GetAttribute("OpenPanel")
	if type(panel) == "string" then
		Sounds.play("click")
		Window.open(panel)
		return
	end
	local model = prompt.Parent and prompt.Parent.Parent
	if prompt:GetAttribute("Good") and model and model:IsA("Model") then
		lastGatherPart = prompt.Parent :: BasePart
		local pivot = model:GetPivot()
		for _, angle in { 0.07, -0.06, 0.035, 0 } do
			model:PivotTo(pivot * CFrame.Angles(angle, 0, angle * 0.5))
			task.wait(0.035)
		end
	end
end)

-- Walking away from a shop closes its panel.
task.spawn(function()
	local Places = require(ReplicatedStorage.Shared.Places)
	local openedNear: string? = nil
	Window.onChanged(function(name)
		openedNear = nil
		local character = Players.LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if name and rootPart then
			for _, place in Places.list do
				if place.panel == name and (rootPart.Position - place.center).Magnitude < 20 then
					openedNear = place.id
				end
			end
		end
	end)
	while true do
		task.wait(0.5)
		local character = Players.LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if openedNear and rootPart and (rootPart.Position - Places.byId[openedNear].center).Magnitude > 30 then
			Window.close()
		end
	end
end)

-- The Mine gate opens (for this player only) once their gear is good enough.
task.spawn(function()
	local world = workspace:WaitForChild("World")
	local opened: { [Instance]: boolean } = {}
	local announced = false -- don't announce a gate that was already open on join
	local function update()
		local p = Store.profile
		if not p then
			return
		end
		for _, gate in world:GetDescendants() do
			local isGate = gate.Name == "LockedGate"
			local gear, rebirths = gate:GetAttribute("GearLevel"), gate:GetAttribute("Rebirths")
			local realm = gate:GetAttribute("Realm")
			local w = Rules.wallet(p, if type(realm) == "string" then realm else "main")
			if isGate and not opened[gate] and Rules.lockReason(p, w, gear :: number?, rebirths :: number?) == nil then
				opened[gate] = true
				for _, d in gate:GetDescendants() do
					if d:IsA("BasePart") then
						d.CanCollide = false
						TweenService:Create(d, TweenInfo.new(0.8), { Transparency = 1 }):Play()
					elseif d:IsA("SurfaceGui") then
						d.Enabled = false
					end
				end
				if announced then
					local name = gate.Parent and gate.Parent.Name or "zone"
					Toasts.show({ kind = "upgrade", text = `🔓 The {name:sub(1, 1)}{name:sub(2):lower()} is open!` })
				end
			end
		end
		announced = true
	end
	Store.subscribe(function(what)
		if what == "profile" then
			update()
		end
	end)
	update()
end)

-- Which world we're in: drives the HUD, panels and money shown, plus each
-- world's own sky and light (Lighting changes on the client are local).
task.spawn(function()
	local Lighting = game:GetService("Lighting")
	local Places = require(ReplicatedStorage.Shared.Places)
	local Realms = require(ReplicatedStorage.Shared.Realms)
	type Look = { clock: number, atmosphere: Color3, decay: Color3, density: number, tint: Color3 }
	local LOOKS: { [string]: Look } = {
		main = { clock = 13.5, atmosphere = Color3.fromRGB(205, 225, 245), decay = Color3.fromRGB(150, 180, 210), density = 0.25, tint = Color3.new(1, 1, 1) },
		frost = { clock = 11, atmosphere = Color3.fromRGB(225, 238, 255), decay = Color3.fromRGB(170, 200, 235), density = 0.32, tint = Color3.fromRGB(232, 242, 255) },
		ember = { clock = 17.6, atmosphere = Color3.fromRGB(255, 170, 120), decay = Color3.fromRGB(150, 60, 40), density = 0.36, tint = Color3.fromRGB(255, 228, 212) },
	}
	local function applyLook(realm: string)
		local look = LOOKS[realm] or LOOKS.main
		local info = TweenInfo.new(1.2)
		TweenService:Create(Lighting, info, { ClockTime = look.clock }):Play()
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			TweenService:Create(atmosphere, info, { Color = look.atmosphere, Decay = look.decay, Density = look.density }):Play()
		end
		local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		if cc then
			TweenService:Create(cc, info, { TintColor = look.tint }):Play()
		end
	end
	while true do
		local character = Players.LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			local realm = Places.realmAt(rootPart.Position)
			if realm ~= Store.realm then
				Ui.realm = realm
				Window.close()
				applyLook(realm)
				Store.setRealm(realm)
				if realm ~= Realms.MAIN then
					Sounds.play("goal")
				end
			end
		end
		task.wait(0.25)
	end
end)

-- The hub centerpiece's coin and crystals turn here, on each client: smooth,
-- and nothing to send over the network. Any Model under it with a "Spin"
-- attribute (radians per second) turns about its pivot.
task.spawn(function()
	local piece = workspace:WaitForChild("World"):WaitForChild("Hub"):WaitForChild("Centerpiece")
	local spinning: { Model } = {}
	for _, d in piece:GetDescendants() do
		if d:IsA("Model") and type(d:GetAttribute("Spin")) == "number" then
			table.insert(spinning, d)
		end
	end
	game:GetService("RunService").RenderStepped:Connect(function(dt)
		for _, m in spinning do
			m:PivotTo(m:GetPivot() * CFrame.Angles(0, (m:GetAttribute("Spin") :: number) * dt, 0))
		end
	end)
end)
