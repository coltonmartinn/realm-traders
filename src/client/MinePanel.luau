--!strict
-- The mine lift: pick a level of this world's Deep Mine. Every swing rolls a
-- random ore; deeper levels find rare ones more often. How deep you can ride depends on your
-- Gear (Market Town), Thermal Gear (Frostpeak) or Fireproof Armor (Emberfall).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)
local Realms = require(ReplicatedStorage.Shared.Realms)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Ui = require(script.Parent.Ui)
local Window = require(script.Parent.Window)

local MinePanel = {}

local SEND_GAP = 0.5
local ROW_HEIGHT = 74

function MinePanel.new()
	local content = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.ink,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, { Ui.list(Enum.FillDirection.Vertical, 8), Ui.padding(4, 2) })
	local lastSend = 0
	local MineRequest = ReplicatedStorage.Remotes:WaitForChild("MineRequest") :: RemoteEvent

	local summary = Ui.text({ Parent = content, LayoutOrder = 0, Size = UDim2.new(1, -12, 0, 28), TextSize = 20, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })

	type Row = { depth: number, tile: Frame, name: TextLabel, info: TextLabel, button: Ui.Button, why: string? }
	local rows: { Row } = {}

	local function go(row: Row)
		if row.why then
			Toasts.error(row.why)
			return
		end
		local now = os.clock()
		if now - lastSend < SEND_GAP then
			return
		end
		lastSend = now
		MineRequest:FireServer(row.depth)
		Window.close()
	end

	for depth = 0, Rules.MINE_DEPTHS do
		local frame = Ui.card({ Parent = content, LayoutOrder = depth + 1, Size = UDim2.new(1, -12, 0, ROW_HEIGHT) }, true)
		local tile = Ui.iconTile(if depth == 0 then "☀️" else "⛏️", if depth == 0 then "blue" else "gold", ROW_HEIGHT - 16)
		tile.Position = UDim2.fromOffset(8, 8)
		tile.Parent = frame
		local name = Ui.text({ Parent = frame, Position = UDim2.fromOffset(ROW_HEIGHT + 4, 8), Size = UDim2.new(1, -ROW_HEIGHT - 200, 0, 30), TextSize = 24, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
		local info = Ui.body({ Parent = frame, Position = UDim2.fromOffset(ROW_HEIGHT + 4, 40), Size = UDim2.new(1, -ROW_HEIGHT - 200, 0, 22), TextSize = 15, TextColor3 = Theme.muted, TextXAlignment = Enum.TextXAlignment.Left })
		local row: Row
		local button = Ui.button({
			text = "",
			color = "green",
			parent = frame,
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -12, 0.5, 0),
			size = UDim2.fromOffset(170, ROW_HEIGHT - 20),
			textSize = 20,
			onClick = function()
				go(row)
			end,
		})
		row = { depth = depth, tile = tile, name = name, info = info, button = button }
		table.insert(rows, row)
	end

	local tip = Ui.body({ Parent = content, LayoutOrder = 50, Size = UDim2.new(1, -12, 0, 40), TextSize = 15, TextColor3 = Theme.muted, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextXAlignment = Enum.TextXAlignment.Center })

	local function refresh()
		local w = Store.wallet()
		if not w then
			return
		end
		local realm = Realms.byId[w.realm]
		local upgrade = Upgrades.byId[Upgrades.DEPTH[w.realm] or "gear"]
		local legendary = Rules.legendaryOf(w.realm)
		local character = Players.LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local here = if rootPart then Places.mineDepthAt(rootPart.Position) else nil
		local deepest = Rules.mineDepth(w)
		summary.Text = `⛏️ {realm.name} Deep Mine  ·  {upgrade.icon} {upgrade.name} lets you reach level {deepest} of {Rules.MINE_DEPTHS}`
		tip.Text = if legendary
			then `Every swing digs up a random ore; deeper levels find rare ones more often. {legendary.icon} Legendary {legendary.name} ({Ui.money(legendary.basePrice, w.realm)}) can turn up anywhere, likelier deeper down. Sell ores at the Market.`
			else "Every swing digs up a random ore. Sell ores at the Market."
		for _, row in rows do
			local depth = row.depth
			row.why = nil
			if depth == 0 then
				row.name.Text = "Surface"
				row.info.Text = "Back up to the mine lift"
				row.button:setText(if here == nil then "YOU'RE HERE" else "GO UP")
				row.button:setColor("blue")
				row.button:setEnabled(here ~= nil)
				row.why = if here == nil then "You're already on the surface" else nil
				continue
			end
			local signature = Rules.oreAt(w.realm, depth)
			local block = Rules.depthBlock(w, depth)
			if signature and not row.tile:FindFirstChild("Ore") then
				local label = row.tile:FindFirstChild("Icon") :: TextLabel?
				if label then
					label.Text = ""
				end
				Ui.oreIcon(row.tile, Color3.fromHex(signature.color), depth >= 3)
			end
			-- Every level can turn up any ore; show this level's odds
			local odds = {}
			for _, o in Rules.oreOdds(w.realm, depth) do
				local pct = o.chance * 100
				table.insert(odds, `{o.good.icon}{if pct >= 1 then math.floor(pct + 0.5) else math.floor(pct * 100 + 0.5) / 100}%`)
			end
			row.name.Text = if block then `Level {depth} · 🔒 needs {upgrade.name} {depth}` else `Level {depth} · ~{Ui.money(math.floor(Rules.oreValue(w.realm, depth)), w.realm)} a swing`
			row.info.Text = table.concat(odds, "  ")
			if here == depth then
				row.button:setText("YOU'RE HERE")
				row.button:setColor("grey")
				row.button:setEnabled(false)
				row.why = "You're already on this level"
			elseif block then
				row.button:setText("🔒 LOCKED")
				row.button:setColor("grey")
				row.button:setEnabled(false)
				row.why = block
			else
				row.button:setText(if here and depth < here then "GO UP" else "GO DOWN")
				row.button:setColor(if depth >= 4 then "purple" elseif depth >= 2 then "orange" else "green")
				row.button:setEnabled(true)
			end
		end
	end

	return {
		title = "Deep Mine",
		icon = "⛏️",
		color = "orange",
		subtitle = "Every swing is a surprise. Dig deeper for rarer ores!",
		content = content,
		refresh = refresh,
	}
end

return MinePanel
