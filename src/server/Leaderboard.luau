--!strict
-- "Top Traders" board in the plaza: lifetime earnings (kept through rebirths).
-- Shows the all-time global top 10 from an OrderedDataStore when DataStores
-- work, otherwise the players in this server.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)
local Rules = require(ReplicatedStorage.Shared.Rules)

local ROWS = 10
local REFRESH_SECONDS = 8
local GLOBAL_SECONDS = 90

local INK = Color3.fromRGB(32, 34, 62)
local GOLD = Color3.fromRGB(255, 214, 70)

local Leaderboard = {}

type Entry = { name: string, earned: number, rebirths: number? }

local nameCache: { [number]: string } = {}
local globalRows: { Entry }? = nil

local store: OrderedDataStore? = nil
pcall(function()
	store = DataStoreService:GetOrderedDataStore("TopEarned_v1")
end)

local function money(n: number): string
	if n >= 1e6 then
		return string.format("$%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("$%.1fK", n / 1e3)
	end
	local s = tostring(math.floor(n))
	repeat
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return "$" .. s
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.LuckiestGuy
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		(l :: any)[k] = v
	end
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 3
	stroke.Parent = l
	l.Parent = parent
	return l
end

-- Builds the board; returns a function that redraws it with entries.
local function build(parent: Instance): ({ Entry }, string) -> ()
	local model = Instance.new("Model")
	model.Name = "Leaderboard"
	local at = Places.LEADERBOARD
	local cf = CFrame.lookAt(at, Vector3.new(0, 0, 4))
	local function part(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = cf * offset
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	for _, x in { -6, 6 } do
		part(Vector3.new(0.8, 18, 0.8), CFrame.new(x, 9, 0.6), Color3.fromRGB(110, 74, 48), Enum.Material.Wood)
	end
	local board = part(Vector3.new(13, 14, 0.6), CFrame.new(0, 10, 0), Color3.fromRGB(46, 50, 92))
	part(Vector3.new(14, 2.6, 0.8), CFrame.new(0, 18.2, 0), GOLD)
	model.Parent = parent

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.1
	gui.Parent = board
	label(gui, { Size = UDim2.fromScale(1, 0.12), Position = UDim2.fromScale(0, 0.02), Text = "🏆 TOP TRADERS", TextColor3 = GOLD })
	local sub = label(gui, { Size = UDim2.fromScale(1, 0.06), Position = UDim2.fromScale(0, 0.14), Text = "Total earned" })
	local rows = {}
	for i = 1, ROWS do
		local y = 0.22 + (i - 1) * 0.077
		local color = if i == 1 then GOLD elseif i == 2 then Color3.fromRGB(220, 225, 235) elseif i == 3 then Color3.fromRGB(230, 160, 100) else Color3.new(1, 1, 1)
		rows[i] = {
			rank = label(gui, { Size = UDim2.fromScale(0.12, 0.065), Position = UDim2.fromScale(0.04, y), Text = `#{i}`, TextColor3 = color }),
			name = label(gui, { Size = UDim2.fromScale(0.5, 0.065), Position = UDim2.fromScale(0.18, y), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color }),
			value = label(gui, { Size = UDim2.fromScale(0.3, 0.065), Position = UDim2.fromScale(0.66, y), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = color }),
		}
	end

	return function(entries: { Entry }, scope: string)
		sub.Text = `Total earned · {scope}`
		for i, row in rows do
			local e = entries[i]
			row.name.Text = if e then e.name .. (if e.rebirths and e.rebirths > 0 then ` ⭐{e.rebirths}` else "") else "—"
			row.value.Text = if e then money(e.earned) else ""
		end
	end
end

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and name then name else "Player"
	nameCache[userId] = result
	return result
end

function Leaderboard.start(parent: Instance, getProfile: (Player) -> Rules.Profile?)
	local draw = build(parent)

	local function serverRows(): { Entry }
		local entries = {}
		for _, player in Players:GetPlayers() do
			local p = getProfile(player)
			if p then
				table.insert(entries, { name = player.DisplayName, earned = p.stats.earned, rebirths = p.rebirths })
			end
		end
		table.sort(entries, function(a, b)
			return a.earned > b.earned
		end)
		return entries
	end

	-- Global: push everyone's score, then read the top 10
	task.spawn(function()
		while store do
			local s = store :: OrderedDataStore
			for _, player in Players:GetPlayers() do
				local p = getProfile(player)
				if p and p.stats.earned > 0 then
					pcall(function()
						s:SetAsync(tostring(player.UserId), math.floor(p.stats.earned))
					end)
				end
			end
			local ok, pages = pcall(function()
				return s:GetSortedAsync(false, ROWS)
			end)
			if ok and pages then
				local entries = {}
				for _, item in (pages :: DataStorePages):GetCurrentPage() do
					local userId = tonumber(item.key)
					if userId then
						table.insert(entries, { name = nameFor(userId), earned = item.value })
					end
				end
				globalRows = entries
			else
				globalRows = nil
			end
			task.wait(GLOBAL_SECONDS)
		end
	end)

	task.spawn(function()
		while true do
			if globalRows and #globalRows > 0 then
				draw(globalRows, "all time")
			else
				draw(serverRows(), "this server")
			end
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return Leaderboard
