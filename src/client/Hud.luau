--!strict
-- Always-on HUD, laid out like top Roblox simulators:
--   top center : fast-travel buttons (Shops, Forest, Farm, Quarry, Mine)
--   left column: goal card, cash, backpack (+ SELL shortcut), menu tiles with
--                notification badges, music toggle

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Goods = require(ReplicatedStorage.Shared.Goods)
local Places = require(ReplicatedStorage.Shared.Places)
local Products = require(ReplicatedStorage.Shared.Products)
local Realms = require(ReplicatedStorage.Shared.Realms)
local Recipes = require(ReplicatedStorage.Shared.Recipes)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local DailyPanel = require(script.Parent.DailyPanel)
local Guide = require(script.Parent.Guide)
local PetPanel = require(script.Parent.PetPanel)
local QuestPanel = require(script.Parent.QuestPanel)
local ShopPanel = require(script.Parent.ShopPanel)
local Sounds = require(script.Parent.Sounds)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Travel = require(script.Parent.Travel)
local Ui = require(script.Parent.Ui)
local Window = require(script.Parent.Window)

local COLUMN_WIDTH = 300

local Hud = {}

local function bounce(inst: GuiObject)
	local s = inst:FindFirstChild("Bounce") :: UIScale?
	if not s then
		s = Ui.new("UIScale", { Name = "Bounce", Parent = inst })
	end
	local scale = s :: UIScale
	scale.Scale = 1.12
	Ui.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

function Hud.init(gui: ScreenGui)
	-- Fast travel -------------------------------------------------------------------
	local travel = Ui.new("Frame", {
		Name = "Travel",
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(900, 52),
		BackgroundTransparency = 1,
	}, { Ui.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	Ui.autoScale(travel)

	-- One row of buttons per world; only the current world's row shows.
	local travelButtons: { [string]: Ui.Button } = {}
	local travelRealm: { [Ui.Button]: string } = {}
	local travelCount = 0
	for _, realm in Realms.list do
		for _, place in Places.inRealm(realm.id) do
			if place.kind == "zone" or place.panel == "market" then
				travelCount += 1
				local id = place.id
				local b = Ui.button({
					text = `{place.icon} {if place.panel == "market" then "Shops" else place.name}`,
					color = place.color,
					parent = travel,
					layoutOrder = travelCount,
					size = UDim2.fromOffset(if #place.name > 9 then 128 else 100, 44),
					textSize = 17,
					onClick = function()
						Travel.go(id)
					end,
				})
				travelButtons[id] = b
				travelRealm[b] = realm.id
			end
		end
		travelCount += 1
		local mine = Ui.button({
			text = "⛏️ Deep Mine",
			color = "orange",
			parent = travel,
			layoutOrder = travelCount,
			size = UDim2.fromOffset(128, 44),
			textSize = 17,
			onClick = function()
				Travel.toMine()
			end,
		})
		travelRealm[mine] = realm.id
		travelCount += 1
		-- Last button: the portals (in the hub) or the way home (in a world)
		local extra = Ui.button({
			text = if realm.id == Realms.MAIN then "🌀 Worlds" else "🏠 Town",
			color = if realm.id == Realms.MAIN then "purple" else "green",
			parent = travel,
			layoutOrder = travelCount,
			size = UDim2.fromOffset(100, 44),
			textSize = 17,
			onClick = function()
				if realm.id == Realms.MAIN then
					Travel.toPortals()
				else
					Travel.home()
				end
			end,
		})
		travelRealm[extra] = realm.id
	end
	local function showTravel()
		for b, realmId in travelRealm do
			b.root.Visible = realmId == Store.realm
		end
	end
	showTravel()

	-- Left column ----------------------------------------------------------------------
	local column = Ui.new("Frame", {
		Name = "Left",
		Parent = gui,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 520),
		BackgroundTransparency = 1,
	}, { Ui.list(Enum.FillDirection.Vertical, 12) })
	Ui.autoScale(column)

	-- Goal card
	local goalCard = Ui.card({ Parent = column, LayoutOrder = 1, Size = UDim2.fromOffset(COLUMN_WIDTH, 132) })
	local goalStrip = Ui.new("Frame", {
		Parent = goalCard,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Theme.white,
	}, { Ui.corner(), Ui.gradient(Theme.colors.gold) })
	Ui.new("Frame", { Parent = goalStrip, Position = UDim2.new(0, 0, 1, -12), Size = UDim2.new(1, 0, 0, 12), BackgroundColor3 = Theme.colors.gold.bottom, BorderSizePixel = 0 })
	Ui.new("Frame", { Parent = goalStrip, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 2.5), BackgroundColor3 = Theme.ink, BorderSizePixel = 0 })
	local goalHeader = Ui.text({ Parent = goalStrip, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, Outline = 2 })
	local goalReward = Ui.text({ Parent = goalStrip, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, Outline = 2 })
	local goalText = Ui.text({ Parent = goalCard, Position = UDim2.fromOffset(14, 40), Size = UDim2.new(1, -28, 0, 26), TextSize = 23, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
	local goalHint = Ui.body({ Parent = goalCard, Position = UDim2.fromOffset(14, 66), Size = UDim2.new(1, -28, 0, 18), TextSize = 15, TextColor3 = Theme.muted })
	local goalBar, setGoalBar = Ui.bar({ Parent = goalCard, Position = UDim2.fromOffset(14, 94), Size = UDim2.new(1, -28, 0, 24) }, "gold")
	local goalCount = Ui.text({ Parent = goalBar, Size = UDim2.fromScale(1, 1), TextSize = 16, Outline = 2, ZIndex = 2 })

	-- Cash
	local cashPill = Ui.card({ Parent = column, LayoutOrder = 2, Size = UDim2.fromOffset(COLUMN_WIDTH, 58), Radius = 29 })
	local cashTile = Ui.iconTile("💰", "gold", 46)
	cashTile.Position = UDim2.fromOffset(6, 6)
	cashTile.Parent = cashPill
	local cashLabel = Ui.text({ Parent = cashPill, Position = UDim2.fromOffset(62, 0), Size = UDim2.new(1, -74, 1, 0), Text = "$0", TextSize = 32, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
	local bonusChip = Ui.new("Frame", {
		Parent = cashPill,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(78, 30),
		BackgroundColor3 = Theme.white,
		Visible = false,
	}, { Ui.round(), Ui.stroke(Theme.ink, 2), Ui.gradient(Theme.colors.purple) })
	local bonusLabel = Ui.text({ Parent = bonusChip, Size = UDim2.fromScale(1, 1), TextSize = 16, Outline = 1.5 })

	-- Backpack
	local bagPill = Ui.card({ Parent = column, LayoutOrder = 3, Size = UDim2.fromOffset(COLUMN_WIDTH, 58), Radius = 29 })
	local bagTile = Ui.iconTile("🎒", "blue", 46)
	bagTile.Position = UDim2.fromOffset(6, 6)
	bagTile.Parent = bagPill
	local bagLabel = Ui.text({ Parent = bagPill, Position = UDim2.fromOffset(62, 4), Size = UDim2.fromOffset(120, 24), Text = "0 / 25", TextSize = 21, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
	local _, setBagBar = Ui.bar({ Parent = bagPill, Position = UDim2.fromOffset(62, 31), Size = UDim2.fromOffset(122, 16) }, "green")
	local sellButton = Ui.button({
		text = "💰 SELL",
		color = "green",
		parent = bagPill,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -8, 0.5, -2),
		size = UDim2.fromOffset(100, 40),
		textSize = 19,
		radius = 20,
		onClick = function(enabled)
			if not enabled then
				Toasts.error("Your backpack is empty. Go gather something!")
				return
			end
			task.spawn(Travel.go, Places.marketOf(Store.realm).id)
			task.delay(0.35, Window.open, "market")
		end,
	})

	-- What's in the backpack: a chip per good you carry
	local contents = Ui.new("Frame", {
		Parent = column,
		LayoutOrder = 4,
		Size = UDim2.fromOffset(COLUMN_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Ui.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(92, 30),
			CellPadding = UDim2.fromOffset(12, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local contentChips: { [string]: { frame: Frame, label: TextLabel } } = {}
	for i, good in Goods do
		local chip = Ui.card({ Parent = contents, LayoutOrder = i, Visible = false, Radius = 15 })
		local label = Ui.text({ Parent = chip, Size = UDim2.fromScale(1, 1), TextSize = 17, TextColor3 = Theme.text })
		contentChips[good.id] = { frame = chip, label = label }
	end

	-- Menu tiles
	local menu = Ui.new("Frame", {
		Parent = column,
		LayoutOrder = 5,
		Size = UDim2.fromOffset(COLUMN_WIDTH, 92),
		BackgroundTransparency = 1,
	}, { Ui.list(Enum.FillDirection.Horizontal, 12) })
	local menuButtons: { [string]: Ui.Button } = {}
	local badges: { [string]: (string?) -> () } = {}
	local function tile(order: number, panel: string, icon: string, label: string, key: string, color: string)
		local b = Ui.button({
			text = `<font size="32">{icon}</font><br/>{label}`,
			color = color,
			parent = menu,
			layoutOrder = order,
			size = UDim2.fromOffset(66, 86),
			textSize = 14,
			radius = 16,
			onClick = function()
				Window.toggle(panel)
			end,
		})
		if not Ui.touchOnly() then
			Ui.text({ Parent = b.face, Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(16, 16), Text = key, TextSize = 13, Outline = 1.5, ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Left })
		end
		menuButtons[panel] = b
		badges[panel] = Ui.badge(b.root)
	end
	tile(1, "market", "🛒", "Market", "M", "blue")
	tile(2, "craft", "⚒️", "Craft", "C", "purple")
	tile(3, "upgrades", "⛏️", "Gear", "U", "gold")
	tile(4, "quests", "📜", "Quests", "Q", "teal")

	local extras = Ui.new("Frame", {
		Parent = column,
		LayoutOrder = 6,
		Size = UDim2.fromOffset(COLUMN_WIDTH, 44),
		BackgroundTransparency = 1,
	}, { Ui.list(Enum.FillDirection.Horizontal, 12) })
	local dailyButton = Ui.button({
		text = "📅",
		color = "gold",
		parent = extras,
		layoutOrder = 1,
		size = UDim2.fromOffset(52, 40),
		textSize = 22,
		onClick = function()
			Window.toggle("daily")
		end,
	})
	local dailyBadge = Ui.badge(dailyButton.root)

	-- Session gift: counts down, then lights up
	local giftsOpened = 0
	local sessionStarted = os.clock()
	local giftButton: Ui.Button
	giftButton = Ui.button({
		text = "🎁 --:--",
		color = "grey",
		parent = extras,
		layoutOrder = 2,
		size = UDim2.fromOffset(108, 40),
		textSize = 18,
		onClick = function()
			local gift = Rules.GIFTS[giftsOpened + 1]
			if not gift then
				Toasts.error("You've opened every gift this session!")
			elseif os.clock() - sessionStarted < gift.seconds then
				Toasts.error(`Keep playing! Your gift opens in {math.ceil((gift.seconds - (os.clock() - sessionStarted)) / 60)} min`)
			else
				giftsOpened += 1
				ReplicatedStorage.Remotes.GiftRequest:FireServer()
			end
		end,
	})
	local giftBadge = Ui.badge(giftButton.root)
	task.spawn(function()
		while true do
			local gift = Rules.GIFTS[giftsOpened + 1]
			if not gift then
				giftButton:setText("🎁 Done")
				giftButton:setColor("grey")
				giftBadge(nil)
			else
				local left = gift.seconds - (os.clock() - sessionStarted)
				if left <= 0 then
					giftButton:setText("🎁 FREE!")
					giftButton:setColor("green")
					giftBadge("!")
				else
					giftButton:setText(string.format("🎁 %d:%02d", left // 60, math.floor(left % 60)))
					giftButton:setColor("grey")
					giftBadge(nil)
				end
			end
			task.wait(0.5)
		end
	end)
	Ui.button({
		text = "📖",
		color = "orange",
		parent = extras,
		layoutOrder = 3,
		size = UDim2.fromOffset(52, 40),
		textSize = 22,
		onClick = function()
			Window.toggle("collection")
		end,
	})
	local musicButton: Ui.Button
	musicButton = Ui.button({
		text = "🔊",
		color = "paper",
		parent = extras,
		layoutOrder = 4,
		size = UDim2.fromOffset(52, 40),
		textSize = 20,
		onClick = function()
			musicButton:setText(if Sounds.toggleMusic() then "🔊" else "🔇")
		end,
	})
	musicButton.label.TextColor3 = Theme.text
	local musicStroke = musicButton.label:FindFirstChildOfClass("UIStroke")
	if musicStroke then
		musicStroke:Destroy()
	end

	-- Right side: a big Shop button and timers for running boosts --------------------
	local right = Ui.new("Frame", {
		Name = "Right",
		Parent = gui,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(150, 360),
		BackgroundTransparency = 1,
	}, { Ui.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Right) })
	Ui.autoScale(right)
	local shopButton = Ui.button({
		text = `<font size="38">🛍️</font><br/>SHOP`,
		color = "green",
		parent = right,
		layoutOrder = 1,
		size = UDim2.fromOffset(92, 92),
		textSize = 19,
		radius = 24,
		onClick = function()
			Window.toggle("shop")
		end,
	})
	if not Ui.touchOnly() then
		Ui.text({ Parent = shopButton.face, Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(16, 16), Text = "B", TextSize = 13, Outline = 1.5, ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Left })
	end
	menuButtons.shop = shopButton
	local petsButton = Ui.button({
		text = `<font size="38">🐾</font><br/>PETS`,
		color = "orange",
		parent = right,
		layoutOrder = 1,
		size = UDim2.fromOffset(92, 92),
		textSize = 19,
		radius = 24,
		onClick = function()
			Window.toggle("pets")
		end,
	})
	petsButton.root.LayoutOrder = 1
	shopButton.root.LayoutOrder = 0
	if not Ui.touchOnly() then
		Ui.text({ Parent = petsButton.face, Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(16, 16), Text = "P", TextSize = 13, Outline = 1.5, ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Left })
	end
	menuButtons.pets = petsButton
	badges.pets = Ui.badge(petsButton.root)
	local boostChips: { [string]: { frame: Frame, label: TextLabel } } = {}
	for i, id in Products.BOOST_ORDER do
		local boost = Products.BOOSTS[id]
		local chip = Ui.new("Frame", {
			Parent = right,
			LayoutOrder = 1 + i,
			Size = UDim2.fromOffset(140, 36),
			BackgroundColor3 = Theme.white,
			Visible = false,
		}, { Ui.round(), Ui.stroke(), Ui.gradient(Theme.colors[boost.color]) })
		local label = Ui.text({ Parent = chip, Size = UDim2.fromScale(1, 1), TextSize = 17, Outline = 2 })
		boostChips[id] = { frame = chip, label = label }
	end
	task.spawn(function()
		while true do
			for id, chip in boostChips do
				local left = ShopPanel.boostLeft(id)
				chip.frame.Visible = left > 0
				if left > 0 then
					chip.label.Text = `{Products.BOOSTS[id].icon} {Products.BOOSTS[id].name} {ShopPanel.clock(left)}`
				end
			end
			task.wait(0.5)
		end
	end)

	Toasts.setTargets({
		bag = bagTile,
		cash = cashTile,
		onBag = function()
			bounce(bagPill)
		end,
		onCash = function()
			bounce(cashPill)
		end,
	})

	-- Updates -----------------------------------------------------------------------------
	local shownCash = Ui.new("NumberValue", { Value = 0 })
	shownCash.Changed:Connect(function(v)
		cashLabel.Text = Ui.money(v)
	end)
	local lastCash: number? = nil
	local lastGoal: number? = nil
	local lastRealm: string? = nil

	local function refresh()
		local profile, p = Store.profile, Store.wallet()
		if not (profile and p) then
			return
		end
		showTravel()
		local sameRealm = lastRealm == p.realm
		local realm = Realms.byId[p.realm]
		local coinTile = cashTile:FindFirstChild("Icon") :: TextLabel?
		if coinTile then
			coinTile.Text = if p.realm == Realms.MAIN then "💰" else realm.icon
		end

		if lastCash ~= p.cash or lastRealm ~= p.realm then
			if lastCash and sameRealm then
				Ui.tween(shownCash, 0.6, { Value = p.cash })
				cashLabel.TextColor3 = if p.cash > lastCash then Theme.up else Theme.down
				Ui.tween(cashLabel, 0.8, { TextColor3 = Theme.text })
			else
				shownCash.Value = p.cash
				cashLabel.Text = Ui.money(p.cash)
			end
			lastCash = p.cash
		end
		lastRealm = p.realm

		local used, cap = Rules.itemCount(p), Rules.capacity(p)
		bagLabel.Text = `{used} / {cap}`
		bagLabel.TextColor3 = if used >= cap then Theme.down else Theme.text
		setBagBar(used / cap)
		sellButton:setEnabled(used > 0)
		for id, chip in contentChips do
			local n = p.inventory[id] or 0
			chip.frame.Visible = n > 0
			if n > 0 then
				chip.label.Text = `{Rules.goodsById[id].icon} {n}`
			end
		end

		local goal, progress = Rules.currentGoal(p)
		if goal then
			local step = Rules.tutorialStep(p.goal, p.realm)
			local skip = if p.realm == Realms.MAIN then Rules.TUTORIAL_STEPS else 0
			local icon = if p.realm == Realms.MAIN then "⭐" else realm.icon
			goalHeader.Text = if step
				then `🎓 TUTORIAL {step}/{Rules.TUTORIAL_STEPS}`
				else `{icon} GOAL {p.goal - skip}/{#Rules.goals(p.realm) - skip}`
			goalReward.Text = `+{Ui.money(goal.reward)}`
			goalText.Text = goal.text
			goalHint.Text = Ui.controls(goal.hint)
			goalCount.Text = if goal.target >= 1000 then `{Ui.money(progress)} / {Ui.money(goal.target)}` else `{progress} / {goal.target}`
			setGoalBar(progress / goal.target)
		else
			goalHeader.Text = "⭐ ALL GOALS DONE"
			goalReward.Text = ""
			goalText.Text = "You're a master trader!"
			goalHint.Text = "Buy low, sell high, grow your fortune"
			goalCount.Text = "🏆"
			setGoalBar(1)
		end
		if not lastGoal and p.realm == Realms.MAIN and p.goal == 1 and (p.stats.gathered.wood or 0) == 0 then
			-- Brand-new player: say hello and point them at step 1
			Toasts.show({ kind = "goal", header = "👋 WELCOME, TRADER!", text = "Follow the gold arrow to start" })
		end
		if lastGoal and lastGoal ~= p.goal and sameRealm then
			bounce(goalCard)
		end
		lastGoal = p.goal

		-- Badges
		badges.market(if used >= cap * 0.8 and used > 0 then "!" else nil)
		local craftable = 0
		for _, recipe in Recipes do
			craftable += Rules.craftable(p, recipe.id)
		end
		badges.craft(if craftable > 0 then tostring(math.min(craftable, 99)) else nil)
		local affordable = false
		for _, u in Upgrades.list do
			local cost = Rules.upgradeCost(p, u.id)
			if cost and p.cash >= cost and Rules.upgradeBlock(p, u.id) == nil then
				affordable = true
			end
		end
		badges.upgrades(if affordable then "!" else nil)
		local questsReady = QuestPanel.ready()
		badges.quests(if questsReady > 0 then tostring(questsReady) else nil)

		dailyBadge(if DailyPanel.ready() then "!" else nil)
		badges.pets(if PetPanel.affordable() > 0 then "!" else nil)
		local mult = Rules.saleMultiplier(profile)
		bonusChip.Visible = mult > 1.001
		bonusLabel.Text = `⭐ +{math.floor((mult - 1) * 100 + 0.5)}%`
		bonusChip.Size = UDim2.fromOffset(if mult >= 10 then 96 else 78, 30)

		-- Locked zones show a padlock
		for id, button in travelButtons do
			local place = Places.byId[id]
			if place.gearLevel or place.rebirths then
				local locked = Rules.lockReason(profile, Rules.wallet(profile, place.realm), place.gearLevel, place.rebirths) ~= nil
				button:setText(if locked then `🔒 {place.name}` else `{place.icon} {place.name}`)
				button:setColor(if locked then "grey" else place.color)
			end
		end
	end

	Store.subscribe(function(what)
		if what == "profile" then
			refresh()
		end
	end)
	refresh()

	Window.onChanged(function(open)
		for name, b in menuButtons do
			if name == open then
				b:pulse()
			end
		end
	end)

	-- Far from the goal? Pulse its fast-travel button to point out the shortcut.
	task.spawn(function()
		while true do
			task.wait(2)
			local placeId = Guide.placeId
			local d = Guide.distance
			local button = placeId and (travelButtons[placeId] or (Places.byId[placeId].kind == "shop" and travelButtons[Places.marketOf(Places.byId[placeId].realm).id]))
			if button and d and d > 45 and not Window.isOpen() then
				button:pulse()
			end
		end
	end)

	-- Tutorial pointer: a bobbing hand next to the button the current step needs,
	-- shown only once that button will actually do something.
	local pointer = Ui.text({ Parent = gui, Name = "TutorialPointer", AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(44, 44), Text = "👈", TextSize = 38, ZIndex = 20, Visible = false })
	local function pointerTarget(): GuiObject?
		local p = Store.wallet()
		local goal = p and Rules.currentGoal(p)
		if not p or not goal or not goal.ui or Window.isOpen() then
			return nil
		end
		if goal.ui == "sell" then
			return if Rules.itemCount(p) > 0 then sellButton.root else nil
		elseif goal.ui == "craft" then
			local ready = 0
			for _, recipe in Recipes do
				ready += Rules.craftable(p, recipe.id)
			end
			return if ready > 0 then menuButtons.craft.root else nil
		elseif goal.ui == "upgrades" then
			local cost = Rules.upgradeCost(p, "backpack")
			return if cost and p.cash >= cost then menuButtons.upgrades.root else nil
		end
		local b = menuButtons[goal.ui]
		return b and b.root
	end
	RunService.Heartbeat:Connect(function()
		local target = pointerTarget()
		pointer.Visible = target ~= nil and target.Visible
		if target then
			local bob = math.abs(math.sin(os.clock() * 5)) * 10
			pointer.Position = UDim2.fromOffset(target.AbsolutePosition.X + target.AbsoluteSize.X + 4 + bob, target.AbsolutePosition.Y + target.AbsoluteSize.Y / 2)
		end
	end)

	-- Distance to the guide target, shown on the goal card
	task.spawn(function()
		while true do
			task.wait(0.25)
			local p = Store.wallet()
			local goal = p and Rules.currentGoal(p)
			local d = Guide.distance
			if goal and d and d > 12 then
				goalHint.Text = `📍 {math.floor(d)} studs away · follow the arrow`
			elseif goal then
				goalHint.Text = Ui.controls(goal.hint)
			end
		end
	end)
end

return Hud
