--!strict
-- The pop-up panel that hosts Market / Workshop / Outfitter. One panel is
-- open at a time; opening another swaps the header color, title and content.

local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

export type Panel = {
	title: string,
	icon: string,
	color: string,
	subtitle: string,
	content: Frame,
	refresh: () -> (),
}

local Window = {}

Window.WIDTH = 780
Window.HEIGHT = 560
Window.HEADER = 72

local frame: Frame
local scale: UIScale
local headerGradient: UIGradient
local headerFill: Frame
local iconHolder: Frame
local titleLabel: TextLabel
local subtitleLabel: TextLabel
local body: Frame
local panels: { [string]: Panel } = {}
local current: string? = nil
local listeners: { (name: string?) -> () } = {}

function Window.init(gui: ScreenGui)
	-- Only one UIScale per instance takes effect, so the holder gets the
	-- screen-size scale and the frame inside gets the open animation.
	local holder = Ui.new("Frame", {
		Name = "Window",
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 10),
		Size = UDim2.fromOffset(Window.WIDTH, Window.HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 3,
	})
	Ui.autoScale(holder)
	frame = Ui.new("Frame", {
		Parent = holder,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	})
	scale = Ui.new("UIScale", { Parent = frame })

	Ui.new("Frame", {
		Name = "Shadow",
		Parent = frame,
		Position = UDim2.fromOffset(0, 9),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.ink,
		BackgroundTransparency = 0.45,
	}, { Ui.corner(24) })
	local sheet = Ui.new("Frame", {
		Name = "Sheet",
		Parent = frame,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.paper,
		Active = true,
		ClipsDescendants = false,
	}, { Ui.corner(24), Ui.stroke(Theme.ink, 4) })

	-- Colored header band (rounded top, square bottom)
	local header = Ui.new("Frame", {
		Name = "Header",
		Parent = sheet,
		Size = UDim2.new(1, 0, 0, Window.HEADER),
		BackgroundColor3 = Theme.white,
	}, { Ui.corner(24) })
	headerGradient = Ui.new("UIGradient", { Parent = header, Rotation = 90 })
	headerFill = Ui.new("Frame", {
		Parent = header,
		Position = UDim2.new(0, 0, 1, -24),
		Size = UDim2.new(1, 0, 0, 24),
		BorderSizePixel = 0,
	})
	Ui.new("Frame", { Parent = header, Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = Theme.ink, BorderSizePixel = 0 })

	iconHolder = Ui.new("Frame", {
		Parent = header,
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.fromOffset(52, 52),
		BackgroundTransparency = 1,
	})
	titleLabel = Ui.text({
		Parent = header,
		Position = UDim2.fromOffset(82, 0),
		Size = UDim2.new(1, -170, 1, 0),
		TextSize = 36,
		TextXAlignment = Enum.TextXAlignment.Left,
		Outline = 3,
	})
	subtitleLabel = Ui.body({
		Parent = sheet,
		Position = UDim2.fromOffset(24, Window.HEADER + 10),
		Size = UDim2.new(1, -48, 0, 20),
		TextColor3 = Theme.muted,
		TextSize = 16,
	})
	body = Ui.new("Frame", {
		Parent = sheet,
		Position = UDim2.fromOffset(20, Window.HEADER + 38),
		Size = UDim2.new(1, -40, 1, -(Window.HEADER + 54)),
		BackgroundTransparency = 1,
	})

	Ui.button({
		text = "X",
		color = "red",
		parent = frame,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(1, -14, 0, 12),
		size = UDim2.fromOffset(54, 54),
		radius = 27,
		textSize = 28,
		onClick = function()
			Window.close()
		end,
	}).root.ZIndex = 4
end

function Window.register(name: string, panel: Panel)
	panels[name] = panel
	panel.content.Visible = false
	panel.content.Size = UDim2.fromScale(1, 1)
	panel.content.Parent = body
end

function Window.isOpen(name: string?): boolean
	if name then
		return current == name
	end
	return current ~= nil
end

function Window.onChanged(fn: (name: string?) -> ())
	table.insert(listeners, fn)
end

local function changed()
	for _, fn in listeners do
		task.spawn(fn, current)
	end
end

function Window.open(name: string)
	local panel = panels[name]
	if not panel or current == name then
		return
	end
	if current then
		panels[current].content.Visible = false
	end
	current = name

	local pair = Theme.colors[panel.color]
	headerGradient.Color = ColorSequence.new(pair.top, pair.bottom)
	headerFill.BackgroundColor3 = pair.bottom
	iconHolder:ClearAllChildren()
	local tile = Ui.iconTile(panel.icon, "paper", 52)
	tile.Parent = iconHolder
	titleLabel.Text = panel.title
	subtitleLabel.Text = panel.subtitle
	panel.refresh()
	panel.content.Visible = true
	if not frame.Visible then
		frame.Visible = true
		scale.Scale = 0.7
	end
	-- Also cancels a close animation that is still running
	Ui.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	changed()
end

function Window.close()
	if not current then
		return
	end
	panels[current].content.Visible = false
	current = nil
	Ui.tween(scale, 0.12, { Scale = 0.8 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
		if not current then
			frame.Visible = false
		end
	end)
	changed()
end

function Window.toggle(name: string)
	if current == name then
		Window.close()
	else
		Window.open(name)
	end
end

-- Re-renders the open panel (called when the profile or market changes).
function Window.refresh()
	if current then
		panels[current].refresh()
	end
end

return Window
