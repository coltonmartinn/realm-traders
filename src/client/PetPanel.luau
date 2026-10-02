--!strict
-- Pet shop and collection: every pet, grouped by the world whose coin buys
-- it, plus the exotics from the Exotic Egg. Buy, equip and unequip here; the
-- equipped pets' bonuses add up on the sale multiplier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pets = require(ReplicatedStorage.Shared.Pets)
local Realms = require(ReplicatedStorage.Shared.Realms)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Ui = require(script.Parent.Ui)
local Window = require(script.Parent.Window)

local PetPanel = {}

local SEND_GAP = 0.3
local CARD = Vector2.new(172, 152)

local function pct(bonus: number): string
	return `+{math.floor(bonus * 100 + 0.5)}%`
end

-- How many pets the player could buy right now (for the menu badge).
function PetPanel.affordable(): number
	local p = Store.profile
	if not p then
		return 0
	end
	local n = 0
	for _, pet in Pets.list do
		if not pet.exotic and Rules.petBlock(p, pet.id) == nil then
			n += 1
		end
	end
	return n
end

function PetPanel.new()
	local content = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.ink,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, { Ui.list(Enum.FillDirection.Vertical, 10), Ui.padding(4, 2) })
	local lastSend = 0
	local PetRequest = ReplicatedStorage.Remotes:WaitForChild("PetRequest") :: RemoteEvent

	local summary = Ui.text({ Parent = content, LayoutOrder = 0, Size = UDim2.new(1, -12, 0, 28), TextSize = 22, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })

	type Card = {
		pet: Pets.Pet,
		frame: Frame,
		status: TextLabel,
		button: Ui.Button,
		action: string?, -- "buy" | "equip" | "unequip" | nil (blocked)
		why: string?,
	}
	local cards: { Card } = {}

	local function send(card: Card)
		if not card.action then
			Toasts.error(card.why or "Can't do that")
			return
		end
		if card.action == "egg" then
			Window.open("shop")
			return
		end
		local now = os.clock()
		if now - lastSend < SEND_GAP then
			return
		end
		lastSend = now
		PetRequest:FireServer(card.action, card.pet.id)
	end

	local function section(order: number, title: string)
		Ui.text({ Parent = content, LayoutOrder = order, Size = UDim2.new(1, -12, 0, 26), Text = title, TextSize = 20, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
		return Ui.new("Frame", {
			Parent = content,
			LayoutOrder = order + 1,
			Size = UDim2.new(1, -12, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(CARD.X, CARD.Y), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
	end

	local function card(grid: Instance, order: number, pet: Pets.Pet)
		local frame = Ui.card({ Parent = grid, LayoutOrder = order }, true)
		local tile = Ui.iconTile(pet.icon, if pet.exotic then "purple" else "paper", 56)
		tile.Position = UDim2.fromOffset(10, 10)
		tile.Parent = frame
		Ui.text({ Parent = frame, Position = UDim2.fromOffset(72, 10), Size = UDim2.new(1, -80, 0, 26), Text = pet.name, TextSize = 19, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
		Ui.text({ Parent = frame, Position = UDim2.fromOffset(72, 36), Size = UDim2.new(1, -80, 0, 24), Text = `{pct(pet.bonus)} sell`, TextSize = 19, TextColor3 = Theme.up, TextXAlignment = Enum.TextXAlignment.Left })
		local status = Ui.body({ Parent = frame, Position = UDim2.fromOffset(10, 70), Size = UDim2.new(1, -20, 0, 18), TextSize = 13, TextColor3 = Theme.muted, TextXAlignment = Enum.TextXAlignment.Center })
		local c: Card
		local button = Ui.button({
			text = "",
			color = "green",
			parent = frame,
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -10),
			size = UDim2.fromOffset(CARD.X - 24, 44),
			textSize = 17,
			onClick = function()
				send(c)
			end,
		})
		c = { pet = pet, frame = frame, status = status, button = button }
		table.insert(cards, c)
	end

	local order = 10
	for _, realm in Realms.list do
		local grid = section(order, `{realm.icon} {realm.name} pets · bought with {realm.coinName}`)
		local i = 0
		for _, pet in Pets.list do
			if pet.realm == realm.id then
				i += 1
				card(grid, i, pet)
			end
		end
		order += 10
	end
	local exoticGrid = section(order, "🥚 Exotic pets · only from the Exotic Egg in the 🛍️ Shop")
	local i = 0
	for _, pet in Pets.list do
		if pet.exotic then
			i += 1
			card(exoticGrid, i, pet)
		end
	end

	local function refresh()
		local p = Store.profile
		if not p then
			return
		end
		local odds: { [string]: number } = {}
		for _, o in Pets.exoticOdds(p.pets.owned) do
			odds[o.pet.id] = o.chance
		end
		summary.Text = `🐾 Equipped {#p.pets.equipped}/{Pets.SLOTS}  ·  Pets {pct(Rules.petBonus(p))}  ·  Total sell bonus {pct(Rules.saleMultiplier(p) - 1)}`
		for _, c in cards do
			local pet = c.pet
			local owned = p.pets.owned[pet.id] == true
			local equipped = table.find(p.pets.equipped, pet.id) ~= nil
			c.why = nil
			if equipped then
				c.action = "unequip"
				c.status.Text = "✅ Equipped"
				c.button:setText("UNEQUIP")
				c.button:setColor("grey")
				c.button:setEnabled(true)
			elseif owned then
				local full = #p.pets.equipped >= Pets.SLOTS
				c.action = if full then nil else "equip"
				c.why = if full then `You can only equip {Pets.SLOTS} pets. Unequip one first` else nil
				c.status.Text = "Owned"
				c.button:setText("EQUIP")
				c.button:setColor("blue")
				c.button:setEnabled(not full)
			elseif pet.exotic then
				c.action = "egg"
				c.status.Text = string.format("%.0f%% chance per egg", (odds[pet.id] or 0) * 100)
				c.button:setText("🥚 GET EGG")
				c.button:setColor("purple")
				c.button:setEnabled(true)
			else
				local lock = Rules.realmLock(p, pet.realm :: string)
				local block = Rules.petBlock(p, pet.id)
				c.action = if block then nil else "buy"
				c.why = block
				c.status.Text = if lock then `🔒 {Realms.byId[pet.realm :: string].rebirths} Rebirths` else `In {Realms.byId[pet.realm :: string].name}`
				c.button:setText(`BUY {Ui.money(pet.cost :: number, pet.realm)}`)
				c.button:setColor("green")
				c.button:setEnabled(block == nil)
			end
		end
	end

	return {
		title = "Pets",
		icon = "🐾",
		color = "orange",
		subtitle = `Equip up to {Pets.SLOTS} pets. Each one boosts the cash from everything you sell!`,
		content = content,
		refresh = refresh,
	}
end

return PetPanel
