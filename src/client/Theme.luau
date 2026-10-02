--!strict
-- The look of the whole UI, modeled on chunky cartoon simulator UIs:
-- cream "paper" panels, thick dark ink outlines, saturated gradient buttons,
-- white display text with an ink outline on colored surfaces.

export type Pair = { top: Color3, bottom: Color3 }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Theme = {
	ink = rgb(32, 34, 62),
	paper = rgb(255, 249, 236),
	paperDark = rgb(244, 232, 210),
	paperLine = rgb(222, 205, 176),
	text = rgb(48, 42, 70),
	muted = rgb(140, 126, 146),
	white = rgb(255, 255, 255),

	up = rgb(46, 180, 84),
	down = rgb(232, 72, 72),

	colors = {
		green = { top = rgb(132, 230, 100), bottom = rgb(52, 176, 74) },
		blue = { top = rgb(104, 196, 255), bottom = rgb(44, 120, 236) },
		purple = { top = rgb(204, 146, 255), bottom = rgb(132, 76, 228) },
		gold = { top = rgb(255, 226, 96), bottom = rgb(248, 164, 30) },
		orange = { top = rgb(255, 190, 100), bottom = rgb(240, 120, 40) },
		red = { top = rgb(255, 126, 116), bottom = rgb(222, 56, 72) },
		teal = { top = rgb(110, 228, 220), bottom = rgb(30, 160, 170) },
		grey = { top = rgb(214, 212, 222), bottom = rgb(160, 156, 176) },
		paper = { top = rgb(255, 252, 244), bottom = rgb(240, 226, 200) },
	} :: { [string]: Pair },

	-- Luckiest Guy everywhere: big, bubbly cartoon letters (the classic
	-- simulator look). It runs wide, so Ui.text shrinks text that won't fit.
	display = Font.fromEnum(Enum.Font.LuckiestGuy),
	body = Font.fromEnum(Enum.Font.LuckiestGuy),
	bodyHeavy = Font.fromEnum(Enum.Font.LuckiestGuy),

	outline = 2.5, -- ink stroke on buttons and cards
	radius = 14,
}

return Theme
