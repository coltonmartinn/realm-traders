--!strict
-- Workshop panel: one card per recipe, drawn as an equation
-- ("🌾 3 + 🌳 1 → 🍞"), with have/need on each input, the profit per craft at
-- current prices, and craft buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)
local Recipes = require(ReplicatedStorage.Shared.Recipes)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Ui = require(script.Parent.Ui)

local CraftRequest = ReplicatedStorage.Remotes.CraftRequest :: RemoteEvent

local SEND_GAP = 0.25
local TILE_COLORS: { [string]: string } = { bread = "orange", tools = "blue", jewelry = "purple", stew = "orange", frostorb = "purple", steel = "teal", armor = "gold" }

local CraftPanel = {}

function CraftPanel.new()
	local content = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.ink,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, { Ui.list(Enum.FillDirection.Vertical, 14), Ui.padding(4, 2) })
	local lastSend = 0

	type Card = {
		recipe: Recipes.Recipe,
		frame: Frame,
		haves: { TextLabel },
		profitLabel: TextLabel,
		profitGradient: UIGradient,
		one: Ui.Button,
		all: Ui.Button,
		maxQty: number,
	}
	local cards: { Card } = {}

	local function send(card: Card, qty: number, enabled: boolean)
		if not enabled then
			local missing = {}
			local p = Store.wallet()
			for _, input in card.recipe.inputs do
				local have = if p then p.inventory[input.id] or 0 else 0
				if have < input.qty then
					local good = Rules.goodsById[input.id]
					local zone = Places.zoneFor(input.id)
					table.insert(missing, `{input.qty - have} {good.icon} {good.name}` .. (if zone then ` ({zone.name})` else ""))
				end
			end
			Toasts.error(`You need {table.concat(missing, " and ")} more`)
			return
		end
		local now = os.clock()
		if now - lastSend < SEND_GAP then
			return
		end
		lastSend = now
		CraftRequest:FireServer(card.recipe.id, qty)
	end

	for i, recipe in Recipes do
		local good = Rules.goodsById[recipe.id]
		local frame = Ui.card({ Parent = content, LayoutOrder = i, Size = UDim2.new(1, -12, 0, 168) }, true)

		local tile = Ui.iconTile(good.icon, TILE_COLORS[recipe.id] or "gold", 92)
		tile.Position = UDim2.fromOffset(16, 16)
		tile.Parent = frame
		Ui.text({ Parent = frame, Position = UDim2.fromOffset(124, 14), Size = UDim2.fromOffset(240, 34), Text = good.name, TextSize = 32, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })

		local profitChip = Ui.new("Frame", {
			Parent = frame,
			Position = UDim2.fromOffset(124, 54),
			Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Theme.white,
		}, { Ui.round(), Ui.stroke(Theme.ink, 2), Ui.padding(0, 12) })
		local profitGradient = Ui.gradient(Theme.colors.green)
		profitGradient.Parent = profitChip
		local profitLabel = Ui.text({ Parent = profitChip, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, TextSize = 16, Outline = 1.5 })

		-- The equation
		local equation = Ui.new("Frame", {
			Parent = frame,
			Position = UDim2.fromOffset(16, 116),
			Size = UDim2.fromOffset(500, 40),
			BackgroundTransparency = 1,
		}, { Ui.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
		local haves = {}
		local order = 0
		local function chip(icon: string, qty: string): TextLabel
			order += 1
			local c = Ui.card({
				Parent = equation,
				LayoutOrder = order,
				Size = UDim2.fromOffset(0, 38),
				AutomaticSize = Enum.AutomaticSize.X,
				Radius = 19,
			})
			Ui.new("UIPadding", { Parent = c, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12) })
			Ui.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent = c
			Ui.text({ Parent = c, LayoutOrder = 1, Size = UDim2.fromOffset(26, 26), Text = icon, TextScaled = true })
			Ui.text({ Parent = c, LayoutOrder = 2, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = qty, TextSize = 21, TextColor3 = Theme.text })
			return Ui.body({ Parent = c, LayoutOrder = 3, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, TextSize = 14, RichText = true, TextTruncate = Enum.TextTruncate.None })
		end
		local function symbol(s: string)
			order += 1
			Ui.text({ Parent = equation, LayoutOrder = order, Size = UDim2.fromOffset(20, 38), Text = s, TextSize = 26, TextColor3 = Theme.text })
		end
		for j, input in recipe.inputs do
			if j > 1 then
				symbol("+")
			end
			table.insert(haves, chip(Rules.goodsById[input.id].icon, `×{input.qty}`))
		end
		symbol("→")
		chip(good.icon, "×1")

		local card: Card
		local one = Ui.button({
			text = `{recipe.verb} 1`,
			color = "purple",
			parent = frame,
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, -18, 0, 20),
			size = UDim2.fromOffset(180, 56),
			textSize = 22,
			onClick = function(enabled)
				send(card, 1, enabled)
			end,
		})
		local all = Ui.button({
			text = `{recipe.verb} All`,
			color = "purple",
			parent = frame,
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, -18, 0, 90),
			size = UDim2.fromOffset(180, 56),
			textSize = 22,
			onClick = function(enabled)
				send(card, card.maxQty, enabled)
			end,
		})
		card = { recipe = recipe, frame = frame, haves = haves, profitLabel = profitLabel, profitGradient = profitGradient, one = one, all = all, maxQty = 0 }
		table.insert(cards, card)
	end

	Ui.body({
		Parent = content,
		LayoutOrder = 100,
		Size = UDim2.new(1, 0, 0, 22),
		Text = "💡 Crafted goods sell for more than their parts. Watch the Market for good prices!",
		TextColor3 = Theme.muted,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local function refresh()
		local p = Store.wallet()
		if not p then
			return
		end
		local market = Store.market
		for _, card in cards do
			-- Only this world's recipes
			card.frame.Visible = card.recipe.realm == p.realm
			if not card.frame.Visible then
				continue
			end
			for j, input in card.recipe.inputs do
				local have = p.inventory[input.id] or 0
				local color = if have >= input.qty then "#2EB454" else "#E84848"
				card.haves[j].Text = `<font color="{color}">have {have}</font>`
			end

			if market and market[card.recipe.id] then
				local sells = market[card.recipe.id].bid
				local cost = 0
				for _, input in card.recipe.inputs do
					local q = market[input.id]
					cost += (if q then q.bid else 0) * input.qty
				end
				local profit = sells - cost
				local pair = if profit >= 0 then Theme.colors.green else Theme.colors.red
				card.profitGradient.Color = ColorSequence.new(pair.top, pair.bottom)
				card.profitLabel.Text = `Sells {Ui.money(sells)} · {if profit >= 0 then "+" else "−"}{Ui.money(math.abs(profit))} profit`
			end

			local n = Rules.craftable(p, card.recipe.id)
			card.maxQty = n
			card.one:setEnabled(n >= 1)
			card.all:setEnabled(n >= 1)
			card.all:setText(if n >= 1 then `{card.recipe.verb} All ({n})` else `{card.recipe.verb} All`)
		end
	end

	return {
		title = "Workshop",
		icon = "⚒️",
		color = "purple",
		subtitle = "Turn raw goods into products that sell for more.",
		content = content,
		refresh = refresh,
	}
end

return CraftPanel
