--!strict
-- Market panel: one card per good with live price, trend, a mini chart and
-- what you hold, plus Buy / Sell buttons showing the exact total for the
-- chosen amount, and a big SELL ALL button. Totals use the same PriceModel as
-- the server, so what you see is what you get (unless the price ticks first).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Goods = require(ReplicatedStorage.Shared.Goods)
local Places = require(ReplicatedStorage.Shared.Places)
local PriceModel = require(ReplicatedStorage.Shared.PriceModel)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Ui = require(script.Parent.Ui)

local Remotes = ReplicatedStorage.Remotes
local TradeRequest = Remotes.TradeRequest :: RemoteEvent
local SellAllRequest = Remotes.SellAllRequest :: RemoteEvent

local MAX_QTY = 100 -- matches MarketState.MAX_QTY
local SEND_GAP = 0.25
local BARS = 30
local AMOUNTS: { number | string } = { 1, 5, 10, "Max" }
local TILE_COLORS: { [string]: string } = {
	wood = "orange", wheat = "gold", stone = "teal", iron = "red", gems = "purple", bread = "orange", tools = "blue", jewelry = "red",
	pine = "green", fish = "blue", icecrystal = "teal", stew = "orange", frostorb = "purple",
	charcoal = "grey", magma = "orange", dragonscale = "red", steel = "teal", armor = "gold",
}

local params = PriceModel.defaults

local MarketPanel = {}

type Plan = { qty: number, total: number, why: string? } -- why ~= nil means blocked

-- The good as the price model sees it during a market event (matches the server).
local function priced(good: Goods.Good, quote: Store.Quote): any
	local boost = quote.boost or 1
	if boost == 1 then
		return good
	end
	return { id = good.id, basePrice = good.basePrice * boost, targetStock = good.targetStock }
end

local function planBuy(good: Goods.Good, quote: Store.Quote, p: Rules.Wallet, amount: number | string): Plan
	local space = Rules.space(p)
	if quote.stock <= 0 then
		return { qty = 0, total = 0, why = `The market is out of {good.name}` }
	end
	if space <= 0 then
		return { qty = 0, total = 0, why = "Backpack full! Sell or craft to make room" }
	end
	local function cost(n: number): number
		return PriceModel.buyCost(priced(good, quote), quote.stock, quote.price, n, params)
	end
	if amount == "Max" then
		-- Largest affordable amount (cost grows with n, so binary search).
		local lo, hi = 0, math.min(MAX_QTY, quote.stock, space)
		while lo < hi do
			local mid = (lo + hi + 1) // 2
			if cost(mid) <= p.cash then
				lo = mid
			else
				hi = mid - 1
			end
		end
		if lo == 0 then
			return { qty = 0, total = 0, why = `Need {Ui.money(cost(1) - p.cash)} more` }
		end
		return { qty = lo, total = cost(lo) }
	end
	local n = amount :: number
	if n > quote.stock then
		return { qty = n, total = 0, why = `Only {quote.stock} {good.name} for sale` }
	end
	local total = cost(n)
	if n > space then
		return { qty = n, total = total, why = `Your backpack only has room for {space} more` }
	end
	if total > p.cash then
		return { qty = n, total = total, why = `Need {Ui.money(total - p.cash)} more` }
	end
	return { qty = n, total = total }
end

local function planSell(good: Goods.Good, quote: Store.Quote, profile: Rules.Profile, p: Rules.Wallet, amount: number | string): Plan
	local owned = p.inventory[good.id] or 0
	if owned <= 0 then
		local zone = Places.zoneFor(good.id)
		local where = if zone then `Gather it at the {zone.name}` elseif not good.raw then "Craft it at the Workshop" else ""
		return { qty = 0, total = 0, why = `You don't have any {good.name}. {where}` }
	end
	local n = if amount == "Max" then math.min(owned, MAX_QTY) else amount :: number
	local base = PriceModel.sellValue(priced(good, quote), quote.stock, quote.price, n, params)
	local total = base + Rules.saleBonus(profile, p, good.id, n, base) -- rebirth/pet bonus, as on the server
	if n > owned then
		return { qty = n, total = total, why = `You only have {owned} {good.name}` }
	end
	return { qty = n, total = total }
end

function MarketPanel.new()
	local content = Ui.new("Frame", { BackgroundTransparency = 1 })
	local amount: number | string = 1
	local lastSend = 0
	local refresh: () -> ()

	local function canSend(): boolean
		local now = os.clock()
		if now - lastSend < SEND_GAP then
			return false
		end
		lastSend = now
		return true
	end

	-- Top bar: amount chips + SELL ALL -------------------------------------------------
	local top = Ui.new("Frame", { Parent = content, Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1 })
	Ui.body({ Parent = top, Size = UDim2.fromOffset(74, 46), Text = "Amount", TextColor3 = Theme.muted, TextSize = 17 })
	local amountButtons: { [number | string]: Ui.Button } = {}
	for i, a in AMOUNTS do
		amountButtons[a] = Ui.button({
			text = tostring(a),
			color = "paper",
			parent = top,
			position = UDim2.fromOffset(74 + (i - 1) * 66, 2),
			size = UDim2.fromOffset(58, 40),
			textSize = 19,
			onClick = function()
				amount = a
				refresh()
			end,
		})
	end
	local sellAll = Ui.button({
		text = "💰 SELL ALL",
		color = "green",
		parent = top,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -6, 0, 0),
		size = UDim2.fromOffset(250, 44),
		textSize = 21,
		onClick = function(enabled)
			if not enabled then
				Toasts.error("Your backpack is empty. Go gather something!")
			elseif canSend() then
				SellAllRequest:FireServer()
			end
		end,
	})

	local list = Ui.new("ScrollingFrame", {
		Parent = content,
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 1, -60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.ink,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, { Ui.list(Enum.FillDirection.Vertical, 10), Ui.padding(4, 2) })

	type Row = {
		good: Goods.Good,
		card: Frame,
		price: TextLabel,
		trendChip: Frame,
		trendGradient: UIGradient,
		trendLabel: TextLabel,
		bars: { Frame },
		owned: TextLabel,
		buy: Ui.Button,
		sell: Ui.Button,
		buyPlan: Plan?,
		sellPlan: Plan?,
		eventChip: Frame,
		eventGradient: UIGradient,
		eventLabel: TextLabel,
	}
	local rows: { Row } = {}

	local function send(row: Row, side: string, plan: Plan?, enabled: boolean)
		if not plan then
			return
		end
		if not enabled or plan.why then
			Toasts.error(plan.why or "Can't trade right now")
			return
		end
		if canSend() then
			TradeRequest:FireServer(row.good.id, side, plan.qty)
		end
	end

	for i, good in Goods do
		local card = Ui.card({ Parent = list, LayoutOrder = i, Size = UDim2.new(1, -12, 0, 74) }, true)
		local tile = Ui.iconTile(good.icon, TILE_COLORS[good.id] or "paper", 56)
		tile.Position = UDim2.fromOffset(9, 9)
		tile.Parent = card
		local eventChip = Ui.new("Frame", {
			Parent = card,
			Position = UDim2.fromOffset(2, 52),
			Size = UDim2.fromOffset(70, 20),
			BackgroundColor3 = Theme.white,
			Visible = false,
			ZIndex = 3,
		}, { Ui.round(), Ui.stroke(Theme.ink, 2) })
		local eventGradient = Ui.gradient(Theme.colors.orange)
		eventGradient.Parent = eventChip
		local eventLabel = Ui.text({ Parent = eventChip, Size = UDim2.fromScale(1, 1), TextSize = 13, Outline = 1.5, ZIndex = 4 })

		Ui.text({ Parent = card, Position = UDim2.fromOffset(76, 10), Size = UDim2.fromOffset(150, 28), Text = good.name, TextSize = 25, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
		local zone = Places.zoneFor(good.id)
		Ui.body({
			Parent = card,
			Position = UDim2.fromOffset(76, 40),
			Size = UDim2.fromOffset(150, 20),
			Text = if zone then `Raw · {zone.icon} {zone.name}` else "Crafted · ⚒️ Workshop",
			TextColor3 = Theme.muted,
			TextSize = 14,
		})

		local price = Ui.text({ Parent = card, Position = UDim2.fromOffset(232, 8), Size = UDim2.fromOffset(110, 30), TextSize = 26, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
		local trendChip = Ui.new("Frame", {
			Parent = card,
			Position = UDim2.fromOffset(232, 42),
			Size = UDim2.fromOffset(80, 22),
			BackgroundColor3 = Theme.white,
		}, { Ui.round(), Ui.stroke(Theme.ink, 2) })
		local trendGradient = Ui.gradient(Theme.colors.grey)
		trendGradient.Parent = trendChip
		local trendLabel = Ui.text({ Parent = trendChip, Size = UDim2.fromScale(1, 1), TextSize = 14, Outline = 1.5 })

		local chart = Ui.new("Frame", { Parent = card, Position = UDim2.fromOffset(342, 14), Size = UDim2.fromOffset(110, 46), BackgroundTransparency = 1 })
		local bars = {}
		for b = 1, BARS do
			table.insert(bars, Ui.new("Frame", {
				Parent = chart,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale((b - 1) / BARS, 1),
				Size = UDim2.new(1 / BARS, -1, 0, 0),
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.muted,
			}, { Ui.corner(1) }))
		end

		Ui.body({ Parent = card, Position = UDim2.fromOffset(462, 12), Size = UDim2.fromOffset(64, 16), Text = "YOU HAVE", TextColor3 = Theme.muted, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center })
		local owned = Ui.text({ Parent = card, Position = UDim2.fromOffset(462, 30), Size = UDim2.fromOffset(64, 30), TextSize = 28, TextColor3 = Theme.text })

		local row: Row
		local buy = Ui.button({
			text = "Buy",
			color = "blue",
			parent = card,
			position = UDim2.fromOffset(534, 9),
			size = UDim2.fromOffset(88, 52),
			textSize = 18,
			onClick = function(enabled)
				send(row, "buy", row.buyPlan, enabled)
			end,
		})
		local sell = Ui.button({
			text = "Sell",
			color = "green",
			parent = card,
			position = UDim2.fromOffset(630, 9),
			size = UDim2.fromOffset(88, 52),
			textSize = 18,
			onClick = function(enabled)
				send(row, "sell", row.sellPlan, enabled)
			end,
		})
		row = { good = good, card = card, price = price, trendChip = trendChip, trendGradient = trendGradient, trendLabel = trendLabel, bars = bars, owned = owned, buy = buy, sell = sell, eventChip = eventChip, eventGradient = eventGradient, eventLabel = eventLabel }
		table.insert(rows, row)
	end

	local function buttonText(verb: string, plan: Plan): string
		if plan.qty == 0 then
			return verb
		end
		return `{verb} {plan.qty}<br/><font size="15">{Ui.money(plan.total)}</font>`
	end

	refresh = function()
		for a, b in amountButtons do
			b:setColor(if a == amount then "blue" else "paper")
		end
		local profile, p, market = Store.profile, Store.wallet(), Store.market
		if not (profile and p and market) then
			return
		end
		local sellAllTotal = 0
		for _, row in rows do
			-- Each world's market only trades its own goods
			row.card.Visible = row.good.realm == p.realm
			local quote = market[row.good.id]
			if not quote or not row.card.Visible then
				continue
			end
			row.price.Text = Ui.price(quote.price)
			local boost = quote.boost or 1
			row.eventChip.Visible = boost ~= 1
			if boost ~= 1 then
				local hot = boost > 1
				local chipPair = if hot then Theme.colors.orange else Theme.colors.teal
				row.eventGradient.Color = ColorSequence.new(chipPair.top, chipPair.bottom)
				row.eventLabel.Text = if hot then "🔥 HOT" else "❄️ CHEAP"
			end

			local trend = Store.trend(row.good.id)
			local flat = math.abs(trend) < 0.001
			local pairName = if flat then "grey" elseif trend > 0 then "green" else "red"
			local pair = Theme.colors[pairName]
			row.trendGradient.Color = ColorSequence.new(pair.top, pair.bottom)
			row.trendLabel.Text = if flat then "— 0.0%" else string.format("%s %.1f%%", if trend > 0 then "▲" else "▼", math.abs(trend) * 100)

			local history = Store.history[row.good.id] or {}
			local lo, hi = math.huge, -math.huge
			local start = math.max(1, #history - BARS + 1)
			for k = start, #history do
				lo, hi = math.min(lo, history[k]), math.max(hi, history[k])
			end
			local range = math.max(hi - lo, row.good.basePrice * 0.01)
			local count = #history - start + 1
			local offset = BARS - count
			for b, bar in row.bars do
				local v = history[start + b - offset - 1]
				if b > offset and v then
					bar.Size = UDim2.new(1 / BARS, -1, 0.12 + 0.88 * (v - lo) / range, 0)
					bar.BackgroundColor3 = pair.bottom
					bar.BackgroundTransparency = 0.55 * (1 - b / BARS)
				else
					bar.Size = UDim2.new(1 / BARS, -1, 0, 0)
				end
			end

			local have = p.inventory[row.good.id] or 0
			row.owned.Text = tostring(have)
			row.owned.TextColor3 = if have > 0 then Theme.text else Theme.paperLine
			if have > 0 then
				local base = PriceModel.sellValue(priced(row.good, quote), quote.stock, quote.price, math.min(have, MAX_QTY), params)
				sellAllTotal += base + Rules.saleBonus(profile, p, row.good.id, math.min(have, MAX_QTY), base)
			end

			row.buyPlan = planBuy(row.good, quote, p, amount)
			row.sellPlan = planSell(row.good, quote, profile, p, amount)
			local bp, sp = row.buyPlan :: Plan, row.sellPlan :: Plan
			row.buy:setText(buttonText("Buy", bp))
			row.sell:setText(buttonText("Sell", sp))
			row.buy:setEnabled(bp.why == nil)
			row.sell:setEnabled(sp.why == nil)
		end
		sellAll:setEnabled(sellAllTotal > 0)
		sellAll:setText(if sellAllTotal > 0 then `💰 SELL ALL · {Ui.money(sellAllTotal)}` else "💰 SELL ALL")
	end

	return {
		title = "Market",
		icon = "🛒",
		color = "blue",
		subtitle = "Prices drop when everyone sells and rise when everyone buys. Sell high!",
		content = content,
		refresh = refresh,
	}
end

return MarketPanel
