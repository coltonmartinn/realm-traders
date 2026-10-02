--!strict
-- Robux shop: coin packs (scaled by rebirths) and timed boosts. Buttons open
-- Roblox's purchase prompt; the server grants the item when the receipt
-- arrives (see ProcessReceipt in Main.server).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pets = require(ReplicatedStorage.Shared.Pets)
local Products = require(ReplicatedStorage.Shared.Products)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Ui = require(script.Parent.Ui)

local ShopPanel = {}

-- Seconds left on a boost, counting down locally between profile updates.
function ShopPanel.boostLeft(boostId: string): number
	local p = Store.profile
	if not p then
		return 0
	end
	return math.max(0, (p.boosts[boostId] or 0) - (os.clock() - Store.profileAt))
end

function ShopPanel.clock(seconds: number): string
	local s = math.ceil(seconds)
	if s >= 3600 then
		return string.format("%d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

local function buy(product: Products.Product)
	if product.id == 0 then
		Toasts.error("Coming soon! This item isn't on sale yet.")
		return
	end
	local ok = pcall(function()
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.id)
	end)
	if not ok then
		Toasts.error("The shop isn't available right now. Try again soon!")
	end
end

-- Show the real Robux price from the dashboard once it loads.
local function loadPrice(product: Products.Product, button: Ui.Button)
	if product.id == 0 then
		button:setText("SOON")
		button:setColor("grey")
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(product.id, Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			button:setText(`R$ {info.PriceInRobux}`)
		end
	end)
end

local function ribbon(parent: GuiObject, text: string)
	local tag = Ui.new("Frame", {
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(112, 24),
		BackgroundColor3 = Theme.white,
		ZIndex = 3,
	}, { Ui.round(), Ui.stroke(), Ui.gradient(Theme.colors.red) })
	Ui.text({ Parent = tag, Size = UDim2.fromScale(1, 1), Text = text, TextSize = 14, Outline = 1.5, ZIndex = 4 })
end

local function section(parent: Instance, order: number, text: string)
	Ui.text({ Parent = parent, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 26), Text = text, TextSize = 22, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
end

function ShopPanel.new()
	local content = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.ink,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, { Ui.list(Enum.FillDirection.Vertical, 10), Ui.padding(4, 2) })

	-- Coins
	section(content, 1, "💰 Coins")
	local cashRow = Ui.new("Frame", { Parent = content, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 176), BackgroundTransparency = 1 }, {
		Ui.list(Enum.FillDirection.Horizontal, 12),
	})
	local cashLabels: { { product: Products.Product, label: TextLabel } } = {}
	local order = 0
	for _, product in Products.list do
		if product.kind == "cash" then
			order += 1
			local card = Ui.card({ Parent = cashRow, LayoutOrder = order, Size = UDim2.fromOffset(176, 170) }, true)
			if product.tag then
				ribbon(card, product.tag)
			end
			local tile = Ui.iconTile(product.icon, product.color, 58)
			tile.AnchorPoint = Vector2.new(0.5, 0)
			tile.Position = UDim2.new(0.5, 0, 0, 14)
			tile.Parent = card
			local amount = Ui.text({ Parent = card, Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 28), TextSize = 26, TextColor3 = Theme.up })
			Ui.body({ Parent = card, Position = UDim2.fromOffset(0, 102), Size = UDim2.new(1, 0, 0, 18), Text = product.name, TextSize = 15, TextColor3 = Theme.muted, TextXAlignment = Enum.TextXAlignment.Center })
			local button = Ui.button({
				text = `R$ {product.robux}`,
				color = "green",
				parent = card,
				anchor = Vector2.new(0.5, 1),
				position = UDim2.new(0.5, 0, 1, -10),
				size = UDim2.fromOffset(140, 40),
				textSize = 20,
				onClick = function()
					buy(product)
				end,
			})
			loadPrice(product, button)
			table.insert(cashLabels, { product = product, label = amount })
		end
	end

	-- Exotic Egg: the strongest pets. Paid random item, so the odds are shown
	-- up front (and they're this player's real odds: owned pets can't hatch).
	section(content, 5, "🥚 Exotic Egg")
	local egg = Products.byKey.egg_exotic
	local eggCard = Ui.card({ Parent = content, LayoutOrder = 6, Size = UDim2.new(1, -12, 0, 150) }, true)
	ribbon(eggCard, egg.tag or "BEST PETS")
	local eggTile = Ui.iconTile(egg.icon, egg.color, 96)
	eggTile.Position = UDim2.fromOffset(16, 26)
	eggTile.Parent = eggCard
	Ui.text({ Parent = eggCard, Position = UDim2.fromOffset(128, 16), Size = UDim2.fromOffset(360, 30), Text = "Hatch an exotic pet!", TextSize = 26, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
	local oddsLabel = Ui.body({ Parent = eggCard, Position = UDim2.fromOffset(128, 50), Size = UDim2.fromOffset(400, 86), TextSize = 16, TextColor3 = Theme.text, TextWrapped = true, RichText = true, TextYAlignment = Enum.TextYAlignment.Top })
	local eggButton = Ui.button({
		text = `R$ {egg.robux}`,
		color = "purple",
		parent = eggCard,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -16, 0.5, 0),
		size = UDim2.fromOffset(170, 56),
		textSize = 22,
		onClick = function(enabled)
			if not enabled then
				Toasts.error("You've hatched every exotic pet!")
				return
			end
			buy(egg)
		end,
	})
	loadPrice(egg, eggButton)
	local eggText = eggButton.label.Text

	-- Boosts
	section(content, 7, "⚡ Boosts  ·  15 minutes each, time only runs while you play")
	local boostRow = Ui.new("Frame", { Parent = content, LayoutOrder = 8, Size = UDim2.new(1, 0, 0, 160), BackgroundTransparency = 1 }, {
		Ui.list(Enum.FillDirection.Horizontal, 12),
	})
	local boostStatus: { { id: string, label: TextLabel } } = {}
	for _, product in Products.list do
		if product.kind == "boost" and product.boost then
			local boost = Products.BOOSTS[product.boost]
			order += 1
			local card = Ui.card({ Parent = boostRow, LayoutOrder = order, Size = UDim2.fromOffset(238, 156) }, true)
			local tile = Ui.iconTile(product.icon, product.color, 58)
			tile.Position = UDim2.fromOffset(12, 12)
			tile.Parent = card
			Ui.text({ Parent = card, Position = UDim2.fromOffset(80, 12), Size = UDim2.new(1, -90, 0, 26), Text = boost.name, TextSize = 23, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
			Ui.body({ Parent = card, Position = UDim2.fromOffset(80, 38), Size = UDim2.new(1, -90, 0, 36), Text = boost.text, TextSize = 14, TextColor3 = Theme.muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
			local status = Ui.text({ Parent = card, Position = UDim2.fromOffset(12, 80), Size = UDim2.new(1, -24, 0, 22), TextSize = 17, TextColor3 = Theme.muted })
			local button = Ui.button({
				text = `R$ {product.robux}`,
				color = product.color,
				parent = card,
				anchor = Vector2.new(0.5, 1),
				position = UDim2.new(0.5, 0, 1, -10),
				size = UDim2.fromOffset(150, 40),
				textSize = 20,
				onClick = function()
					buy(product)
				end,
			})
			loadPrice(product, button)
			table.insert(boostStatus, { id = boost.id, label = status })
		end
	end

	local function tick()
		for _, entry in boostStatus do
			local left = ShopPanel.boostLeft(entry.id)
			entry.label.Text = if left > 0 then `✅ Active · {ShopPanel.clock(left)} left` else "Not active"
			entry.label.TextColor3 = if left > 0 then Theme.up else Theme.muted
		end
	end
	task.spawn(function()
		while true do
			if content.Parent and content.Visible then
				tick()
			end
			task.wait(0.5)
		end
	end)

	local function refresh()
		local p = Store.profile
		if not p then
			return
		end
		for _, entry in cashLabels do
			entry.label.Text = `+{Ui.cash(Rules.packCash(p, entry.product))}`
		end
		local lines = {}
		for _, o in Pets.exoticOdds(p.pets.owned) do
			table.insert(lines, string.format("%s %s <font color=\"#2EB454\">+%d%%</font> · <b>%.0f%%</b>", o.pet.icon, o.pet.name, math.floor(o.pet.bonus * 100 + 0.5), o.chance * 100))
		end
		oddsLabel.Text = if #lines > 0
			then "Odds: " .. table.concat(lines, "   ") .. "<br/><font color=\"#8C7E92\">Never a pet you already own.</font>"
			else "You own every exotic pet! 🏆"
		eggButton:setEnabled(#lines > 0 and egg.id ~= 0)
		if #lines == 0 then
			eggButton:setText("ALL HATCHED")
		elseif egg.id ~= 0 then
			eggButton:setText(eggText)
		end
		tick()
	end

	return {
		title = "Shop",
		icon = "🛍️",
		color = "green",
		subtitle = "Coin packs grow with every Rebirth. Exotic pets are the strongest. Boosts stack up to 4 hours.",
		content = content,
		refresh = refresh,
	}
end

return ShopPanel
