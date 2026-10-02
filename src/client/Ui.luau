--!strict
-- UI building blocks in the chunky cartoon style (see Theme): helpers for
-- creating instances, plus buttons, icon tiles, badges and progress bars.

local TweenService = game:GetService("TweenService")

local Sounds = require(script.Parent.Sounds)
local Theme = require(script.Parent.Theme)

local Ui = {}

-- Creates an instance, sets props, parents children. Parent is set last.
function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className) :: any
	local parent = nil
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(radius: number?): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.radius) })
end

function Ui.round(): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Ui.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Ui.new("UIStroke", {
		Color = color or Theme.ink,
		Thickness = thickness or Theme.outline,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function Ui.padding(all: number, horizontal: number?): UIPadding
	local h = UDim.new(0, horizontal or all)
	local v = UDim.new(0, all)
	return Ui.new("UIPadding", { PaddingTop = v, PaddingBottom = v, PaddingLeft = h, PaddingRight = h })
end

function Ui.list(direction: Enum.FillDirection, gap: number, align: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?): UIListLayout
	return Ui.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
	})
end

function Ui.gradient(pair: Theme.Pair): UIGradient
	return Ui.new("UIGradient", { Color = ColorSequence.new(pair.top, pair.bottom), Rotation = 90 })
end

function Ui.tween(inst: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- Display text. Pass Outline = thickness for white-on-color text with an ink edge.
function Ui.text(props: { [string]: any }): TextLabel
	local outline = props.Outline
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		FontFace = Theme.display,
		TextColor3 = Theme.white,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	}
	for k, v in props do
		if k ~= "Outline" then
			defaults[k] = v
		end
	end
	local label = Ui.new("TextLabel", defaults)
	if outline then
		Ui.new("UIStroke", { Parent = label, Color = Theme.ink, Thickness = outline, LineJoinMode = Enum.LineJoinMode.Round })
	end
	Ui.shrinkToFit(label)
	return label
end

-- Keeps a fixed-size label's text inside its box: starts from its own
-- TextSize and steps down (to 60% at most) while the text doesn't fit.
-- Re-checks whenever the text or the box changes. Auto-sized and scaled
-- labels size themselves, so they're left alone.
function Ui.shrinkToFit(label: TextLabel)
	local base = label.TextSize
	local pending = false
	local function fit()
		pending = false
		if label.TextScaled or label.AutomaticSize ~= Enum.AutomaticSize.None or label.AbsoluteSize.X <= 0 then
			return
		end
		label.TextSize = base
		local floor = math.max(8, math.floor(base * 0.6))
		while not label.TextFits and label.TextSize > floor do
			label.TextSize -= 1
		end
	end
	local function schedule()
		if not pending then
			pending = true
			task.defer(fit)
		end
	end
	label:GetPropertyChangedSignal("Text"):Connect(schedule)
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule)
	schedule()
end

-- Dark body text for paper surfaces.
function Ui.body(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		FontFace = Theme.body,
		TextColor3 = Theme.text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in props do
		defaults[k] = v
	end
	return Ui.text(defaults)
end

-- A paper card with an ink outline.
function Ui.card(props: { [string]: any }, dark: boolean?): Frame
	local defaults: { [string]: any } = {
		BackgroundColor3 = if dark then Theme.paperDark else Theme.paper,
	}
	for k, v in props do
		if k ~= "Radius" then
			defaults[k] = v
		end
	end
	return Ui.new("Frame", defaults, { Ui.corner(props.Radius), Ui.stroke() })
end

export type Button = {
	root: TextButton,
	face: Frame,
	label: TextLabel,
	enabled: boolean,
	setEnabled: (self: Button, enabled: boolean) -> (),
	setText: (self: Button, text: string) -> (),
	setColor: (self: Button, color: string) -> (),
	pulse: (self: Button) -> (),
}

export type ButtonOptions = {
	text: string,
	color: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	parent: Instance?,
	layoutOrder: number?,
	textSize: number?,
	radius: number?,
	sound: string?,
	onClick: (enabled: boolean) -> (),
}

local LIP = 4

-- A chunky 3D button: gradient face with a shine, an ink outline, and a dark
-- lip underneath that the face presses down onto. Disabled buttons turn grey
-- but still receive clicks (onClick gets enabled=false) so callers can say why.
function Ui.button(opts: ButtonOptions): Button
	local radius = opts.radius or 12
	local root = Ui.new("TextButton", {
		Name = "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = opts.size,
		Position = opts.position or UDim2.new(),
		AnchorPoint = opts.anchor or Vector2.zero,
		LayoutOrder = opts.layoutOrder or 0,
		Parent = opts.parent,
	})
	local scale = Ui.new("UIScale", { Parent = root })
	local lip = Ui.new("Frame", {
		Name = "Lip",
		Parent = root,
		Position = UDim2.fromOffset(0, LIP),
		Size = UDim2.fromScale(1, 1),
	}, { Ui.corner(radius), Ui.stroke() })
	local face = Ui.new("Frame", {
		Name = "Face",
		Parent = root,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.white,
	}, { Ui.corner(radius), Ui.stroke() })
	local gradient = Ui.new("UIGradient", { Parent = face, Rotation = 90 })
	Ui.new("Frame", {
		Name = "Shine",
		Parent = face,
		Position = UDim2.fromOffset(5, 3),
		Size = UDim2.new(1, -10, 0.36, 0),
		BackgroundColor3 = Theme.white,
		BackgroundTransparency = 0.7,
	}, { Ui.corner(math.max(radius - 4, 2)) })
	local label = Ui.text({
		Parent = face,
		Size = UDim2.fromScale(1, 1),
		Text = opts.text,
		TextSize = opts.textSize or 20,
		RichText = true,
		Outline = 2,
		ZIndex = 2,
	})

	local button = { root = root, face = face, label = label, enabled = true } :: any
	local colorName = opts.color

	local function paint()
		local pair = if button.enabled then Theme.colors[colorName] else Theme.colors.grey
		gradient.Color = ColorSequence.new(pair.top, pair.bottom)
		lip.BackgroundColor3 = pair.bottom:Lerp(Theme.ink, 0.45)
		label.TextTransparency = if button.enabled then 0 else 0.1
	end

	function button.setEnabled(self: Button, enabled: boolean)
		if self.enabled ~= enabled then
			self.enabled = enabled
			paint()
		end
	end
	function button.setText(_: Button, text: string)
		if label.Text ~= text then
			label.Text = text
		end
	end
	function button.setColor(_: Button, name: string)
		if colorName ~= name then
			colorName = name
			paint()
		end
	end
	function button.pulse(_: Button)
		scale.Scale = 1.15
		Ui.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	local function press(down: boolean)
		Ui.tween(face, if down then 0.05 else 0.12, { Position = UDim2.fromOffset(0, if down then LIP - 1 else 0) }, if down then Enum.EasingStyle.Quad else Enum.EasingStyle.Back)
	end
	root.MouseEnter:Connect(function()
		Ui.tween(scale, 0.12, { Scale = 1.05 })
	end)
	root.MouseLeave:Connect(function()
		Ui.tween(scale, 0.12, { Scale = 1 })
		press(false)
	end)
	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			press(true)
		end
	end)
	root.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			press(false)
		end
	end)
	root.Activated:Connect(function()
		Sounds.play(if button.enabled then opts.sound or "click" else "error")
		opts.onClick(button.enabled)
	end)
	paint()
	return button
end

-- A colored rounded square with an emoji in it (icons for goods, menus...).
function Ui.iconTile(icon: string, color: string, size: number): Frame
	local tile = Ui.new("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.white,
	}, { Ui.corner(math.floor(size * 0.28)), Ui.stroke(), Ui.gradient(Theme.colors[color] or Theme.colors.paper) })
	local label = Ui.text({
		Name = "Icon",
		Parent = tile,
		Size = UDim2.fromScale(1, 1),
		Text = icon,
		TextScaled = true,
	})
	Ui.new("UIPadding", {
		Parent = label,
		PaddingTop = UDim.new(0.14, 0),
		PaddingBottom = UDim.new(0.14, 0),
		PaddingLeft = UDim.new(0.14, 0),
		PaddingRight = UDim.new(0.14, 0),
	})
	return tile
end

-- A red notification dot pinned to the top-right corner of parent.
-- Returns a setter: nil hides it, a string shows it (and pops when it changes).
function Ui.badge(parent: GuiObject): (text: string?) -> ()
	local dot = Ui.new("Frame", {
		Name = "Badge",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.white,
		Visible = false,
		ZIndex = 5,
	}, { Ui.round(), Ui.stroke(), Ui.gradient(Theme.colors.red) })
	local scale = Ui.new("UIScale", { Parent = dot })
	local label = Ui.text({ Parent = dot, Size = UDim2.fromScale(1, 1), TextSize = 15, Outline = 1.5, ZIndex = 6 })
	local current: string? = nil
	return function(text: string?)
		if text == current then
			return
		end
		current = text
		dot.Visible = text ~= nil
		if text then
			label.Text = text
			scale.Scale = 0.3
			Ui.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
end

-- A chunky progress bar. Returns the frame and a setter for the 0..1 fill.
function Ui.bar(props: { [string]: any }, color: string): (Frame, (fraction: number) -> ())
	local track = Ui.new("Frame", { BackgroundColor3 = Theme.paperDark }, { Ui.round(), Ui.stroke(Theme.ink, 2) })
	for k, v in props do
		track[k] = v
	end
	local fill = Ui.new("Frame", {
		Parent = track,
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.white,
	}, { Ui.round(), Ui.gradient(Theme.colors[color]) })
	local last = -1
	return track, function(fraction: number)
		fraction = math.clamp(fraction, 0, 1)
		if fraction ~= last then
			last = fraction
			fill.Visible = fraction > 0.01
			Ui.tween(fill, 0.25, { Size = UDim2.fromScale(math.max(fraction, 0.06), 1) })
		end
	end
end

local Realms = require(game:GetService("ReplicatedStorage").Shared.Realms)

-- The world the local player is in; amounts default to its coin.
-- (Main.client keeps this current.)
Ui.realm = "main"

-- An amount of money, in the current world's coin unless `realm` is given.
function Ui.money(n: number, realm: string?): string
	return Realms.money(n, realm or Ui.realm)
end

-- Hub cash (daily rewards, quests, gifts, the Robux shop).
function Ui.cash(n: number): string
	return Realms.money(n, "main")
end

function Ui.price(n: number, realm: string?): string
	if n >= 100 then
		return Ui.money(n, realm)
	end
	local r = Realms.byId[realm or Ui.realm] or Realms.byId.main
	return r.coin .. string.format("%.2f", n)
end

-- True on phones/tablets without a keyboard (no "press E" hints there).
function Ui.touchOnly(): boolean
	local UserInputService = game:GetService("UserInputService")
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Swaps keyboard wording for touch wording on touch-only devices.
function Ui.controls(text: string): string
	if not Ui.touchOnly() then
		return text
	end
	return (text:gsub("Hold E", "Tap & hold"))
end

-- Adds a UIScale that shrinks the element on small screens (phones).
local scaled: { UIScale } = {}
local function screenScale(): number
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 800)
	-- Floor of 0.6 keeps buttons big enough to tap on a phone in landscape (844x390)
	return math.clamp(math.min(size.X / 1150, size.Y / 760), 0.6, 1)
end

function Ui.autoScale(inst: GuiObject)
	local s = Ui.new("UIScale", { Scale = screenScale(), Parent = inst })
	table.insert(scaled, s)
end

local function watchViewport()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local value = screenScale()
			for _, s in scaled do
				s.Scale = value
			end
		end)
	end
end
watchViewport()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)

return Ui
