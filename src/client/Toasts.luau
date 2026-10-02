--!strict
-- Feedback for everything the server tells us, each with its own sound:
--   gain / craft -> "+2 🌳" pops in the middle, then flies into the backpack
--   sale         -> "+$230" flies into the cash counter
--   goal         -> a gold banner with confetti (tutorial steps get their own header)
--   other        -> a chunky message pill at the bottom of the screen

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TextChatService = game:GetService("TextChatService")

local Goods = require(ReplicatedStorage.Shared.Goods)
local Sounds = require(script.Parent.Sounds)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

-- `realm` says which world's coin `amount` is in (the hub's when missing).
export type Notice = { kind: string, text: string, good: string?, amount: number?, rarity: string?, header: string?, realm: string?, pet: string? }
export type Targets = { bag: GuiObject, cash: GuiObject, onBag: () -> (), onCash: () -> () }

local MAX_MESSAGES = 3

local Toasts = {}

local goodsById: { [string]: Goods.Good } = {}
for _, g in Goods do
	goodsById[g.id] = g
end

local gui: ScreenGui
local stack: Frame
local targets: Targets? = nil
local bannerQueue: { Notice } = {}
local bannerBusy = false
local order = 0

function Toasts.init(screenGui: ScreenGui)
	gui = screenGui
	stack = Ui.new("Frame", {
		Name = "Messages",
		Parent = gui,
		ZIndex = 10,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(560, 170),
		BackgroundTransparency = 1,
	}, { Ui.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })
	Ui.autoScale(stack)
end

function Toasts.setTargets(t: Targets)
	targets = t
end

local MESSAGE_COLORS: { [string]: string } = { error = "red", warn = "orange", sale = "green", buy = "blue", upgrade = "gold", ok = "green", rebirth = "purple", daily = "gold" }

local function message(notice: Notice)
	order += 1
	local life = if notice.kind == "warn" then 7 else 2.8
	local holder = Ui.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	})
	local pill = Ui.new("Frame", {
		Parent = holder,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.white,
	}, { Ui.round(), Ui.stroke(), Ui.gradient(Theme.colors[MESSAGE_COLORS[notice.kind] or "green"]), Ui.padding(0, 22) })
	Ui.text({
		Parent = pill,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = notice.text,
		TextSize = 20,
		Outline = 2,
	})
	local scale = Ui.new("UIScale", { Parent = pill, Scale = 0.4 })
	holder.Parent = stack

	local items = {}
	for _, c in stack:GetChildren() do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #items - MAX_MESSAGES do
		items[i]:Destroy()
	end

	Ui.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(life, function()
		if holder.Parent then
			Ui.tween(scale, 0.18, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed:Wait()
			holder:Destroy()
		end
	end)
end

-- Text pops in the middle of the screen, then flies into a HUD element.
local function fly(text: string, target: GuiObject?, onArrive: (() -> ())?, delay: number)
	local label = Ui.text({
		Parent = gui,
		ZIndex = 20,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.05, 0.55),
		Size = UDim2.fromOffset(260, 56),
		Text = text,
		TextSize = 40,
		Outline = 3,
	})
	local scale = Ui.new("UIScale", { Parent = label, Scale = 0.3 })
	Ui.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	Ui.tween(label, 0.5, { Position = label.Position - UDim2.fromOffset(0, 40) })
	task.delay(delay, function()
		if target and target.Parent then
			-- Same ScreenGui, so AbsolutePosition and offsets share an origin
			local goal = target.AbsolutePosition + target.AbsoluteSize / 2
			Ui.tween(label, 0.4, { Position = UDim2.fromOffset(goal.X, goal.Y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Ui.tween(scale, 0.4, { Scale = 0.35 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
			if onArrive then
				onArrive()
			end
		else
			Ui.tween(label, 0.3, { TextTransparency = 1 }).Completed:Wait()
		end
		label:Destroy()
	end)
end

local CONFETTI = { "gold", "red", "blue", "green", "purple", "orange" }

local function confetti()
	for _ = 1, 36 do
		local pair = Theme.colors[CONFETTI[math.random(#CONFETTI)]]
		local piece = Ui.new("Frame", {
			Parent = gui,
			ZIndex = 30,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(math.random(), 0, 0, -20),
			Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22)),
			Rotation = math.random(0, 360),
			BackgroundColor3 = pair.top,
			BorderSizePixel = 0,
		}, { Ui.corner(3) })
		local t = math.random() * 1.2 + 1.6
		Ui.tween(piece, t, { Position = piece.Position + UDim2.fromScale((math.random() - 0.5) * 0.2, 1.1), Rotation = piece.Rotation + math.random(-400, 400) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(t, function()
			piece:Destroy()
		end)
	end
end

local function showBanner(notice: Notice)
	bannerBusy = true
	Sounds.play("goal")
	confetti()
	local banner = Ui.new("Frame", {
		Parent = gui,
		ZIndex = 25,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(480, 130),
		BackgroundTransparency = 1,
	})
	Ui.autoScale(banner)
	local card = Ui.new("Frame", {
		Parent = banner,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.white,
	}, { Ui.corner(22), Ui.stroke(Theme.ink, 4) })
	local gradient = Ui.gradient(Theme.colors.gold)
	gradient.Parent = card
	local header = notice.header or "⭐ GOAL COMPLETE! ⭐"
	if notice.kind == "lucky" then
		header = notice.header or "LUCKY FIND!"
		Sounds.play("coins")
		if notice.rarity == "Rainbow" then
			gradient.Rotation = 0
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 60)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 220, 110)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 110, 255)),
			})
		end
	end
	local pop = Ui.new("UIScale", { Parent = card, Scale = 0.2 })
	Ui.text({ Parent = card, Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 34), Text = header, TextSize = 32, Outline = 3 })
	Ui.text({ Parent = card, Position = UDim2.fromOffset(16, 48), Size = UDim2.new(1, -32, 0, 30), Text = notice.text, TextSize = 26, Outline = 2.5 })
	if notice.amount then
		local reward = Ui.new("Frame", {
			Parent = card,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 84),
			Size = UDim2.fromOffset(170, 36),
			BackgroundColor3 = Theme.white,
		}, { Ui.round(), Ui.stroke(), Ui.gradient(Theme.colors.green) })
		Ui.text({ Parent = reward, Size = UDim2.fromScale(1, 1), Text = `+{Ui.money(notice.amount, notice.realm or "main")}`, TextSize = 22, Outline = 2 })
	end

	Ui.tween(pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.8, function()
		Ui.tween(pop, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed:Wait()
		banner:Destroy()
		bannerBusy = false
		local nextNotice = table.remove(bannerQueue, 1)
		if nextNotice then
			showBanner(nextNotice)
		end
	end)
end

function Toasts.show(notice: Notice)
	local kind = notice.kind
	if kind == "gain" or kind == "craft" then
		local good = notice.good and goodsById[notice.good]
		Sounds.play(if kind == "craft" then "success" else "gather", 0.95 + math.random() * 0.15)
		local text = if good then `+{notice.amount or 1} {good.icon}` else notice.text
		fly(text, targets and targets.bag, targets and targets.onBag, 0.45)
	elseif kind == "social" then
		-- Server-wide news goes into the chat window
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral") :: TextChannel?
		if general then
			pcall(function()
				general:DisplaySystemMessage(`<font color="#FFD646">{notice.text}</font>`)
			end)
		end
	elseif kind == "auto" then
		-- Helper Bee gathers: just a soft tick and a backpack bounce
		Sounds.play("gather", 1.35)
		if targets then
			targets.onBag()
		end
	elseif kind == "rebirth" then
		Sounds.play("goal")
		confetti()
		message(notice)
	elseif kind == "daily" then
		Sounds.play("coins")
		fly(`+{Ui.money(notice.amount or 0, notice.realm or "main")}`, targets and targets.cash, targets and targets.onCash, 0.35)
		message(notice)
	elseif kind == "goal" or kind == "lucky" then
		if bannerBusy then
			table.insert(bannerQueue, notice)
		else
			showBanner(notice)
		end
	else
		if kind == "sale" then
			Sounds.play("coins")
			fly(`+{Ui.money(notice.amount or 0, notice.realm or "main")}`, targets and targets.cash, targets and targets.onCash, 0.35)
		elseif kind == "buy" then
			Sounds.play("coins", 0.8)
		elseif kind == "upgrade" then
			Sounds.play("success")
		elseif kind == "error" then
			Sounds.play("error")
		end
		message(notice)
	end
end

-- Client-side messages (e.g. explaining a disabled button). The click that
-- caused it already played the error sound.
function Toasts.error(text: string)
	message({ kind = "error", text = text })
end

return Toasts
