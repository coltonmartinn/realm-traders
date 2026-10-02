--!strict
-- Outfitter panel: one card per upgrade with chunky level pips, the
-- current -> next effect, and a gold buy button with the price.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Rules)
local Realms = require(ReplicatedStorage.Shared.Realms)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Ui = require(script.Parent.Ui)

local UpgradeRequest = ReplicatedStorage.Remotes.UpgradeRequest :: RemoteEvent
local RebirthRequest = ReplicatedStorage.Remotes.RebirthRequest :: RemoteEvent

local SEND_GAP = 0.4
local TILE_COLORS: { [string]: string } = { gear = "teal", backpack = "blue" }

local UpgradePanel = {}

function UpgradePanel.new()
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
		upgrade: Upgrades.Upgrade,
		frame: Frame,
		level: TextLabel,
		effect: TextLabel,
		pips: { Frame },
		buy: Ui.Button,
	}
	local cards: { Card } = {}
	local refreshRebirth: () -> ()

	for i, upgrade in Upgrades.list do
		local frame = Ui.card({ Parent = content, LayoutOrder = i, Size = UDim2.new(1, -12, 0, 150) }, true)
		local tile = Ui.iconTile(upgrade.icon, TILE_COLORS[upgrade.id] or "gold", 92)
		tile.Position = UDim2.fromOffset(16, 16)
		tile.Parent = frame

		Ui.text({ Parent = frame, Position = UDim2.fromOffset(124, 12), Size = UDim2.fromOffset(300, 34), Text = upgrade.name, TextSize = 30, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
		local level = Ui.text({ Parent = frame, Position = UDim2.fromOffset(124, 12), Size = UDim2.fromOffset(380, 34), TextSize = 20, TextColor3 = Theme.colors.gold.bottom, TextXAlignment = Enum.TextXAlignment.Right })
		Ui.body({ Parent = frame, Position = UDim2.fromOffset(124, 48), Size = UDim2.fromOffset(380, 20), Text = upgrade.description, TextColor3 = Theme.muted, TextSize = 15 })
		local effect = Ui.text({ Parent = frame, Position = UDim2.fromOffset(124, 72), Size = UDim2.fromOffset(380, 28), TextSize = 24, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left, RichText = true })

		local pipRow = Ui.new("Frame", {
			Parent = frame,
			Position = UDim2.fromOffset(124, 110),
			Size = UDim2.fromOffset(380, 22),
			BackgroundTransparency = 1,
		}, { Ui.list(Enum.FillDirection.Horizontal, 8) })
		local pips = {}
		for j = 1, #upgrade.levels do
			local pip = Ui.new("Frame", { Parent = pipRow, LayoutOrder = j, Size = UDim2.fromOffset(56, 20), BackgroundColor3 = Theme.paper }, { Ui.round(), Ui.stroke(Theme.ink, 2) })
			table.insert(pips, pip)
		end

		local card: Card
		local buy = Ui.button({
			text = "",
			color = "gold",
			parent = frame,
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -18, 0.5, -2),
			size = UDim2.fromOffset(190, 80),
			textSize = 24,
			onClick = function(enabled)
				local p = Store.wallet()
				if not p then
					return
				end
				if not enabled then
					Toasts.error(Rules.upgradeBlock(p, card.upgrade.id) or "Can't upgrade")
					return
				end
				local now = os.clock()
				if now - lastSend < SEND_GAP then
					return
				end
				lastSend = now
				UpgradeRequest:FireServer(card.upgrade.id)
			end,
		})
		card = { upgrade = upgrade, frame = frame, level = level, effect = effect, pips = pips, buy = buy }
		table.insert(cards, card)
	end

	-- Rebirth: "Expand Business"
	local rebirthCard = Ui.card({ Parent = content, LayoutOrder = 50, Size = UDim2.new(1, -12, 0, 150) }, true)
	local rebirthTile = Ui.iconTile("🏢", "purple", 92)
	rebirthTile.Position = UDim2.fromOffset(16, 16)
	rebirthTile.Parent = rebirthCard
	Ui.text({ Parent = rebirthCard, Position = UDim2.fromOffset(124, 12), Size = UDim2.fromOffset(300, 34), Text = "Expand Business", TextSize = 30, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
	local rebirthLevel = Ui.text({ Parent = rebirthCard, Position = UDim2.fromOffset(124, 12), Size = UDim2.fromOffset(380, 34), TextSize = 20, TextColor3 = Theme.colors.purple.bottom, TextXAlignment = Enum.TextXAlignment.Right })
	Ui.body({ Parent = rebirthCard, Position = UDim2.fromOffset(124, 48), Size = UDim2.fromOffset(380, 40), Text = "Reset cash, backpack and gear. Everything you make sells for more, forever.", TextColor3 = Theme.muted, TextSize = 15, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top })
	local rebirthEffect = Ui.text({ Parent = rebirthCard, Position = UDim2.fromOffset(124, 100), Size = UDim2.fromOffset(380, 28), TextSize = 24, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left, RichText = true })
	local confirmUntil = 0
	local rebirthButton: Ui.Button
	rebirthButton = Ui.button({
		text = "",
		color = "purple",
		parent = rebirthCard,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -18, 0.5, -2),
		size = UDim2.fromOffset(190, 80),
		textSize = 22,
		onClick = function(enabled)
			local p = Store.profile
			if not p then
				return
			end
			if not enabled then
				Toasts.error(Rules.rebirthBlock(p) or "Can't expand yet")
				return
			end
			if os.clock() > confirmUntil then
				-- Destructive: ask for a second click
				confirmUntil = os.clock() + 4
				rebirthButton:setText("SURE?<br/><font size=\"16\">Click again!</font>")
				rebirthButton:pulse()
				task.delay(4, function()
					if os.clock() >= confirmUntil then
						refreshRebirth()
					end
				end)
				return
			end
			confirmUntil = 0
			RebirthRequest:FireServer()
		end,
	})

	refreshRebirth = function()
		local p = Store.profile
		if not p then
			return
		end
		local pct = function(m: number): string
			return `+{math.floor((m - 1) * 100 + 0.5)}%`
		end
		local now = Rules.saleMultiplier(p)
		local after = now * (1 + Rules.REBIRTH_BONUS * (p.rebirths + 1)) / (1 + Rules.REBIRTH_BONUS * p.rebirths)
		rebirthLevel.Text = `REBIRTH {p.rebirths}`
		rebirthEffect.Text = `Sell bonus {pct(now)} → <font color="#2EB454">{pct(after)}</font>`
		if os.clock() > confirmUntil then
			rebirthButton:setText(`EXPAND<br/><font size="20">💰 {Ui.cash(Rules.rebirthCost(p))}</font>`)
		end
		rebirthButton:setEnabled(Rules.rebirthBlock(p) == nil)
	end

	local tip = Ui.body({
		Parent = content,
		LayoutOrder = 100,
		Size = UDim2.new(1, 0, 0, 22),
		Text = "",
		TextColor3 = Theme.muted,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local function refresh()
		local profile, p = Store.profile, Store.wallet()
		if not (profile and p) then
			return
		end
		-- Rebirth and the Helper Bee belong to Market Town; other worlds only
		-- have their own gear and backpack.
		local inHub = p.realm == Realms.MAIN
		rebirthCard.Visible = inHub
		tip.Text = if inHub
			then "💡 Gear level 2 opens the 🔩 Mine, where iron for Tools is found."
			else `💡 Upgrades here cost {Realms.byId[p.realm].coinName} and only count in {Realms.byId[p.realm].name}.`
		refreshRebirth()
		for _, card in cards do
			local id = card.upgrade.id
			card.frame.Visible = inHub or not Upgrades.GLOBAL[id]
			local lvl = p.upgrades[id]
			local maxLvl = Upgrades.maxLevel(id)
			card.level.Text = `LEVEL {lvl}/{maxLvl}`
			for j, pip in card.pips do
				pip.BackgroundColor3 = if j <= lvl then Theme.colors.gold.top else Theme.paper
			end
			local now = Upgrades.value(id, lvl)
			local cost = Rules.upgradeCost(p, id)
			if cost then
				card.effect.Text = `{now} → <font color="#2EB454">{Upgrades.value(id, lvl + 1)}</font> {card.upgrade.unit}`
				card.buy:setText(`UPGRADE<br/><font size="20">💰 {Ui.money(cost)}</font>`)
				card.buy:setEnabled(p.cash >= cost)
			else
				card.effect.Text = `{now} {card.upgrade.unit} · <font color="#F8A41E">MAXED!</font>`
				card.buy:setText("⭐ MAX")
				card.buy:setEnabled(false)
			end
		end
	end

	return {
		title = "Outfitter",
		icon = "⛏️",
		color = "gold",
		subtitle = "Spend your earnings to gather faster and carry more.",
		content = content,
		refresh = refresh,
	}
end

return UpgradePanel
