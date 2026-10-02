--!strict
-- Collection book (like Pet Simulator's Index or Fisch's Bestiary): every good
-- in its plain, ✨ Golden and 🌈 Rainbow form. Undiscovered entries show ❓.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Goods = require(ReplicatedStorage.Shared.Goods)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local CollectionPanel = {}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 110)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 80)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(110, 225, 130)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(100, 170, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 130, 255)),
})

function CollectionPanel.new()
	local content = Ui.new("Frame", { BackgroundTransparency = 1 })
	local progress = Ui.text({ Parent = content, Size = UDim2.new(1, 0, 0, 28), TextSize = 22, TextColor3 = Theme.text })

	local headers = Ui.new("Frame", { Parent = content, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1 })
	for i, h in { "Normal", "✨ Golden", "🌈 Rainbow" } do
		Ui.body({ Parent = headers, Position = UDim2.fromOffset(200 + (i - 1) * 170, 0), Size = UDim2.fromOffset(160, 20), Text = h, TextColor3 = Theme.muted, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center })
	end

	local list = Ui.new("ScrollingFrame", {
		Parent = content,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.ink,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, { Ui.list(Enum.FillDirection.Vertical, 8), Ui.padding(2, 2) })

	type Cell = { gradient: UIGradient, label: TextLabel, key: string, variant: string }
	local cells: { Cell } = {}
	for i, good in Goods do
		local row = Ui.card({ Parent = list, LayoutOrder = i, Size = UDim2.new(1, -12, 0, 48), Radius = 12 }, true)
		Ui.text({ Parent = row, Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(180, 48), Text = good.name, TextSize = 21, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left })
		for v, variant in Rules.VARIANTS do
			local cell = Ui.new("Frame", {
				Parent = row,
				Position = UDim2.fromOffset(200 + (v - 1) * 170 + 50, 5),
				Size = UDim2.fromOffset(60, 38),
				BackgroundColor3 = Theme.white,
			}, { Ui.corner(10), Ui.stroke(Theme.ink, 2) })
			local gradient = Ui.new("UIGradient", { Parent = cell, Rotation = if variant == "Rainbow" then 0 else 90 })
			local label = Ui.text({ Parent = cell, Size = UDim2.fromScale(1, 1), TextSize = 24 })
			table.insert(cells, { gradient = gradient, label = label, key = Rules.collectionKey(good.id, variant), variant = variant })
			label:SetAttribute("Icon", good.icon)
		end
	end

	local function refresh()
		local p = Store.profile
		if not p then
			return
		end
		local found, total = 0, 0
		for _, cell in cells do
			total += 1
			local has = p.collection[cell.key] == true
			if has then
				found += 1
				cell.label.Text = cell.label:GetAttribute("Icon") :: string
				if cell.variant == "Rainbow" then
					cell.gradient.Color = RAINBOW
				else
					local pair = if cell.variant == "Golden" then Theme.colors.gold else Theme.colors.paper
					cell.gradient.Color = ColorSequence.new(pair.top, pair.bottom)
				end
			else
				cell.label.Text = "❓"
				local pair = Theme.colors.grey
				cell.gradient.Color = ColorSequence.new(pair.top, pair.bottom)
			end
		end
		progress.Text = `📖 {found} / {total} discovered`
	end

	return {
		title = "Collection",
		icon = "📖",
		color = "orange",
		subtitle = "Find every good, plus rare Golden and Rainbow ones. Each discovery pays!",
		content = content,
		refresh = refresh,
	}
end

return CollectionPanel
