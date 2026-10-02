--!strict
-- Banners under the fast-travel bar for timed happenings, with live
-- countdowns: the current market event (price up = orange, price down = teal)
-- and the Travelling Merchant (purple, with a GO button that takes you there).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Goods = require(ReplicatedStorage.Shared.Goods)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Sounds = require(script.Parent.Sounds)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Travel = require(script.Parent.Travel)
local Ui = require(script.Parent.Ui)

local NewsBar = {}

local goodsById: { [string]: Goods.Good } = {}
for _, g in Goods do
	goodsById[g.id] = g
end

type Banner = {
	frame: Frame,
	scale: UIScale,
	gradient: UIGradient,
	icon: TextLabel,
	title: TextLabel,
	text: TextLabel,
	timer: TextLabel,
}

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function banner(parent: Instance, order: number, withButton: boolean): Banner
	local frame = Ui.new("Frame", {
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.fromOffset(560, 54),
		BackgroundColor3 = Theme.white,
		Visible = false,
	}, { Ui.corner(16), Ui.stroke(Theme.ink, 3) })
	local gradient = Ui.new("UIGradient", { Parent = frame, Rotation = 90 })
	local scale = Ui.new("UIScale", { Parent = frame })
	local icon = Ui.text({ Parent = frame, Position = UDim2.fromOffset(8, 5), Size = UDim2.fromOffset(44, 44), TextScaled = true })
	local title = Ui.text({ Parent = frame, Position = UDim2.fromOffset(60, 4), Size = UDim2.new(1, -180, 0, 24), TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left, Outline = 2 })
	local text = Ui.text({ Parent = frame, Position = UDim2.fromOffset(60, 28), Size = UDim2.new(1, -180, 0, 20), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Outline = 1.5, TextTruncate = Enum.TextTruncate.AtEnd })
	local timerChip = Ui.new("Frame", {
		Parent = frame,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, if withButton then -78 else -10, 0.5, 0),
		Size = UDim2.fromOffset(62, 30),
		BackgroundColor3 = Theme.ink,
		BackgroundTransparency = 0.35,
	}, { Ui.round() })
	local timer = Ui.text({ Parent = timerChip, Size = UDim2.fromScale(1, 1), TextSize = 17 })
	return { frame = frame, scale = scale, gradient = gradient, icon = icon, title = title, text = text, timer = timer }
end

local function paint(b: Banner, color: string)
	local pair = Theme.colors[color]
	b.gradient.Color = ColorSequence.new(pair.top, pair.bottom)
end

local function popIn(b: Banner)
	b.frame.Visible = true
	b.scale.Scale = 0.3
	Ui.tween(b.scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
end

function NewsBar.init(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "News",
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(560, 130),
		BackgroundTransparency = 1,
	}, { Ui.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })
	Ui.autoScale(holder)

	local eventBanner = banner(holder, 1, false)
	local merchantBanner = banner(holder, 2, true)
	paint(merchantBanner, "purple")
	merchantBanner.icon.Text = "🧳"
	Ui.button({
		text = "GO!",
		color = "green",
		parent = merchantBanner.frame,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -10, 0.5, -2),
		size = UDim2.fromOffset(60, 38),
		textSize = 20,
		onClick = function()
			Travel.toMerchant()
		end,
	})

	local shownEvent: string? = nil
	local shownMerchant: number? = nil

	local function refresh()
		local news = Store.news
		local e = news.event
		if e then
			eventBanner.icon.Text = e.icon
			eventBanner.title.Text = e.title:upper()
			eventBanner.text.Text = e.text
			paint(eventBanner, if e.boost >= 1 then "orange" else "teal")
			if shownEvent ~= e.id then
				shownEvent = e.id
				popIn(eventBanner)
				Sounds.play("success", 1.15)
				-- Point out when the event is good news for what you're carrying
				local p = Store.profile
				local have = p and p.inventory[e.good] or 0
				local good = goodsById[e.good]
				if e.boost > 1 and have >= 5 then
					Toasts.show({ kind = "ok", text = `🔥 You have {have} {good.icon} {good.name}. Sell while it's hot!` })
				end
			end
		else
			shownEvent = nil
			eventBanner.frame.Visible = false
		end

		local m = news.merchant
		if m then
			local good = goodsById[m.good]
			merchantBanner.title.Text = "TRAVELLING MERCHANT!"
			merchantBanner.text.Text = `Buying {good.icon} {good.name} for {Ui.cash(m.price)} each (2× price)`
			if shownMerchant ~= m.endsAt then
				shownMerchant = m.endsAt
				popIn(merchantBanner)
				Sounds.play("goal", 1.1)
				local p = Store.profile
				local mine = if p then Rules.ownMade(p, m.good) else 0
				if mine >= 3 then
					Toasts.show({ kind = "ok", text = `🧳 The merchant wants your {mine} {good.icon} {good.name}! Press GO` })
				end
			end
		else
			shownMerchant = nil
			merchantBanner.frame.Visible = false
		end
	end

	Store.subscribe(function(what)
		if what == "news" then
			refresh()
		end
	end)
	refresh()

	task.spawn(function()
		while true do
			local t = workspace:GetServerTimeNow()
			local news = Store.news
			if news.event then
				eventBanner.timer.Text = clock(news.event.endsAt - t)
			end
			if news.merchant then
				merchantBanner.timer.Text = clock(news.merchant.endsAt - t)
			end
			task.wait(0.5)
		end
	end)
end

return NewsBar
