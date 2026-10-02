--!strict
-- Daily quests: three objectives that reset every day (gather, craft, earn),
-- each with a progress bar and a claim button, plus a countdown to new ones.

local AvatarEditorService = game:GetService("AvatarEditorService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Rules = require(ReplicatedStorage.Shared.Rules)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Ui = require(script.Parent.Ui)

local QuestRequest = ReplicatedStorage.Remotes.QuestRequest :: RemoteEvent

local QuestPanel = {}

local KIND_COLORS: { [string]: string } = { gathered = "green", crafted = "purple", earned = "gold" }

-- How many quests are finished but not claimed (for the menu badge).
function QuestPanel.ready(): number
	local p = Store.profile
	if not p then
		return 0
	end
	local n = 0
	for i, q in p.quests.list do
		if not q.claimed and Rules.questProgress(p, i) >= q.target then
			n += 1
		end
	end
	return n
end

function QuestPanel.new()
	local content = Ui.new("Frame", { BackgroundTransparency = 1 }, { Ui.list(Enum.FillDirection.Vertical, 12) })

	type Card = { frame: Frame, tile: TextLabel, tileGradient: UIGradient, text: TextLabel, setBar: (number) -> (), count: TextLabel, reward: TextLabel, claim: Ui.Button }
	local cards: { Card } = {}
	for i = 1, 3 do
		local frame = Ui.card({ Parent = content, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 100) }, true)
		local tileFrame = Ui.new("Frame", {
			Parent = frame,
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(76, 76),
			BackgroundColor3 = Theme.white,
		}, { Ui.corner(22), Ui.stroke() })
		local tileGradient = Ui.gradient(Theme.colors.green)
		tileGradient.Parent = tileFrame
		local tile = Ui.text({ Parent = tileFrame, Size = UDim2.fromScale(1, 1), TextScaled = true })
		Ui.new("UIPadding", { Parent = tile, PaddingTop = UDim.new(0.15, 0), PaddingBottom = UDim.new(0.15, 0), PaddingLeft = UDim.new(0.15, 0), PaddingRight = UDim.new(0.15, 0) })
		local text = Ui.text({ Parent = frame, Position = UDim2.fromOffset(104, 12), Size = UDim2.fromOffset(380, 30), TextSize = 25, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
		local bar, setBar = Ui.bar({ Parent = frame, Position = UDim2.fromOffset(104, 50), Size = UDim2.fromOffset(300, 26) }, "green")
		local count = Ui.text({ Parent = bar, Size = UDim2.fromScale(1, 1), TextSize = 16, Outline = 2, ZIndex = 2 })
		local reward = Ui.text({ Parent = frame, Position = UDim2.fromOffset(414, 50), Size = UDim2.fromOffset(100, 26), TextSize = 19, TextColor3 = Theme.up, TextXAlignment = Enum.TextXAlignment.Left })
		local claim = Ui.button({
			text = "CLAIM",
			color = "green",
			parent = frame,
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -16, 0.5, -2),
			size = UDim2.fromOffset(160, 64),
			textSize = 22,
			sound = "coins",
			onClick = function(enabled)
				local p = Store.profile
				local q = p and p.quests.list[i]
				if not q then
					return
				end
				if q.claimed then
					Toasts.error("Already claimed. New quests tomorrow!")
				elseif not enabled then
					Toasts.error("Not finished yet. Keep going!")
				else
					QuestRequest:FireServer(i)
				end
			end,
		})
		table.insert(cards, { frame = frame, tile = tile, tileGradient = tileGradient, text = text, setBar = setBar, count = count, reward = reward, claim = claim })
	end

	local footer = Ui.body({
		Parent = content,
		LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 16,
		TextColor3 = Theme.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- Friends make everything better (and players with friends stick around)
	local social = Ui.new("Frame", {
		Parent = content,
		LayoutOrder = 11,
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
	}, { Ui.list(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center) })
	Ui.button({
		text = "👥 Invite Friends",
		color = "blue",
		parent = social,
		layoutOrder = 1,
		size = UDim2.fromOffset(220, 44),
		textSize = 19,
		onClick = function()
			pcall(function()
				SocialService:PromptGameInvite(Players.LocalPlayer)
			end)
		end,
	})
	Ui.button({
		text = "⭐ Favorite Game",
		color = "gold",
		parent = social,
		layoutOrder = 2,
		size = UDim2.fromOffset(220, 44),
		textSize = 19,
		onClick = function()
			pcall(function()
				AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
			end)
		end,
	})

	local function refresh()
		local p = Store.profile
		if not p then
			return
		end
		for i, card in cards do
			local q = p.quests.list[i]
			card.frame.Visible = q ~= nil
			if q then
				local pair = Theme.colors[KIND_COLORS[q.kind] or "green"]
				card.tileGradient.Color = ColorSequence.new(pair.top, pair.bottom)
				card.tile.Text = if q.kind == "earned" then "💰" else Rules.goodsById[q.good :: string].icon
				card.text.Text = Rules.questText(q)
				local progress = Rules.questProgress(p, i)
				card.setBar(progress / q.target)
				card.count.Text = if q.kind == "earned" then `{Ui.cash(progress)} / {Ui.cash(q.target)}` else `{progress} / {q.target}`
				card.reward.Text = `+{Ui.cash(q.reward)}`
				if q.claimed then
					card.claim:setText("✓ DONE")
					card.claim:setEnabled(false)
				else
					card.claim:setText("CLAIM")
					card.claim:setEnabled(progress >= q.target)
				end
			end
		end
		local left = 86400 - workspace:GetServerTimeNow() % 86400
		footer.Text = string.format("New quests in %dh %02dm", left // 3600, (left % 3600) // 60)
	end

	return {
		title = "Daily Quests",
		icon = "📜",
		color = "teal",
		subtitle = "Three new quests every day. Finish them for big rewards!",
		content = content,
		refresh = refresh,
	}
end

return QuestPanel
