--!strict
-- Daily rewards: a 7-day streak calendar (day 7 is the big one, shown from
-- day 1 so it is something to come back for). Missing a day restarts the
-- streak. Opens by itself when today's reward is waiting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Rules)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local DailyRequest = ReplicatedStorage.Remotes.DailyRequest :: RemoteEvent
local CodeRequest = ReplicatedStorage.Remotes.CodeRequest :: RemoteEvent

local DailyPanel = {}

function DailyPanel.today(): number
	return math.floor(workspace:GetServerTimeNow() / 86400)
end

-- Whether today's reward is waiting.
function DailyPanel.ready(): boolean
	local p = Store.profile
	return p ~= nil and (Rules.dailyStatus(p, DailyPanel.today()))
end

function DailyPanel.new()
	local content = Ui.new("Frame", { BackgroundTransparency = 1 })
	local days = #Rules.DAILY_REWARDS

	local row = Ui.new("Frame", {
		Parent = content,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 190),
		BackgroundTransparency = 1,
	}, { Ui.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })

	type Tile = { frame: Frame, gradient: UIGradient, amount: TextLabel, mark: TextLabel, scale: UIScale }
	local tiles: { Tile } = {}
	for i = 1, days do
		local big = i == days
		local frame = Ui.new("Frame", {
			Parent = row,
			LayoutOrder = i,
			Size = UDim2.fromOffset(if big then 130 else 86, if big then 180 else 150),
			BackgroundColor3 = Theme.white,
		}, { Ui.corner(16), Ui.stroke(Theme.ink, 3) })
		local gradient = Ui.new("UIGradient", { Parent = frame, Rotation = 90 })
		local scale = Ui.new("UIScale", { Parent = frame })
		Ui.text({ Parent = frame, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 22), Text = `DAY {i}`, TextSize = 19, Outline = 2 })
		Ui.text({ Parent = frame, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, if big then 70 else 48), Text = if big then "💎" else "💰", TextScaled = true })
		local amount = Ui.text({ Parent = frame, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -10), Size = UDim2.new(1, 0, 0, 24), TextSize = if big then 24 else 18, Outline = 2 })
		local mark = Ui.text({ Parent = frame, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -8), Size = UDim2.fromOffset(32, 32), TextSize = 26, Outline = 2, ZIndex = 3 })
		table.insert(tiles, { frame = frame, gradient = gradient, amount = amount, mark = mark, scale = scale })
	end

	local info = Ui.body({
		Parent = content,
		Position = UDim2.fromOffset(0, 214),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.muted,
	})

	local claim: Ui.Button
	claim = Ui.button({
		text = "🎁 CLAIM",
		color = "green",
		parent = content,
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 252),
		size = UDim2.fromOffset(300, 70),
		textSize = 32,
		sound = "coins",
		onClick = function(enabled)
			if enabled then
				DailyRequest:FireServer()
			end
		end,
	})

	-- Promo codes
	local codeRow = Ui.new("Frame", {
		Parent = content,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 348),
		Size = UDim2.fromOffset(560, 56),
		BackgroundTransparency = 1,
	})
	Ui.text({ Parent = codeRow, Size = UDim2.fromOffset(150, 52), Text = "🎟️ Have a code?", TextSize = 20, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
	local boxCard = Ui.card({ Parent = codeRow, Position = UDim2.fromOffset(158, 4), Size = UDim2.fromOffset(250, 46), Radius = 12 })
	local box = Ui.new("TextBox", {
		Parent = boxCard,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		PlaceholderText = "Enter code",
		PlaceholderColor3 = Theme.muted,
		Text = "",
		FontFace = Theme.display,
		TextSize = 22,
		TextColor3 = Theme.text,
	})
	local function redeem()
		if box.Text ~= "" then
			CodeRequest:FireServer(box.Text)
			box.Text = ""
		end
	end
	box.FocusLost:Connect(function(enter)
		if enter then
			redeem()
		end
	end)
	Ui.button({
		text = "REDEEM",
		color = "blue",
		parent = codeRow,
		position = UDim2.fromOffset(420, 4),
		size = UDim2.fromOffset(136, 46),
		textSize = 20,
		onClick = function()
			redeem()
		end,
	})

	local function refresh()
		local p = Store.profile
		if not p then
			return
		end
		local can, streak = Rules.dailyStatus(p, DailyPanel.today())
		-- `current` is the day the next claim lands on (or the last claimed day)
		local claimedThrough = if can then streak - 1 else streak
		for i, tile in tiles do
			local reward = Rules.DAILY_REWARDS[i] * (1 + p.rebirths)
			tile.amount.Text = Ui.cash(reward)
			local pairName
			if i <= claimedThrough then
				pairName = "grey"
				tile.mark.Text = "✓"
				tile.mark.TextColor3 = Theme.up
			elseif can and i == streak then
				pairName = "gold"
				tile.mark.Text = ""
				tile.scale.Scale = 1.08
			else
				pairName = if i == #tiles then "purple" else "blue"
				tile.mark.Text = ""
				tile.scale.Scale = 1
			end
			local pair = Theme.colors[pairName]
			tile.gradient.Color = ColorSequence.new(pair.top, pair.bottom)
		end
		claim:setEnabled(can)
		if can then
			claim:setText(`🎁 CLAIM DAY {streak}`)
			info.Text = if streak == 1 then "Log in every day to build your streak. Day 7 is huge!" else `{streak - 1} day streak! Don't break it!`
		else
			claim:setText("✓ CLAIMED")
			info.Text = "Come back tomorrow for the next reward. Miss a day and the streak resets!"
		end
	end

	return {
		title = "Rewards",
		icon = "🎁",
		color = "gold",
		subtitle = "A free reward every day you play. Keep your streak going!",
		content = content,
		refresh = refresh,
	}
end

return DailyPanel
