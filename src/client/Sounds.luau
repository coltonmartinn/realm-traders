--!strict
-- UI sound effects and background music (free Creator Store audio).

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local IDS: { [string]: { id: string, volume: number } } = {
	click = { id = "rbxassetid://88442833509532", volume = 0.5 },
	gather = { id = "rbxassetid://127036696152728", volume = 0.35 },
	coins = { id = "rbxassetid://1319346243", volume = 0.6 },
	success = { id = "rbxassetid://122399158411452", volume = 0.5 },
	goal = { id = "rbxassetid://1840076509", volume = 0.5 },
	error = { id = "rbxassetid://88442833509532", volume = 0.25 },
}
local MUSIC = { id = "rbxassetid://75831120610810", volume = 0.18 }

local Sounds = {}

local folder = Instance.new("Folder")
folder.Name = "UISounds"
folder.Parent = SoundService

local sounds: { [string]: Sound } = {}
for name, info in IDS do
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = info.id
	s.Volume = info.volume
	if name == "error" then
		s.PlaybackSpeed = 0.6
	end
	s.Parent = folder
	sounds[name] = s
end

local music = Instance.new("Sound")
music.Name = "Music"
music.SoundId = MUSIC.id
music.Volume = MUSIC.volume
music.Looped = true
music.Parent = folder

task.spawn(function()
	local all: { Instance } = { music }
	for _, s in sounds do
		table.insert(all, s)
	end
	pcall(function()
		ContentProvider:PreloadAsync(all)
	end)
end)

-- Plays a one-shot sound; overlapping plays are fine (PlayOnRemove clone).
function Sounds.play(name: string, pitch: number?)
	local s = sounds[name]
	if not s then
		return
	end
	local c = s:Clone()
	c.PlaybackSpeed = (pitch or 1) * s.PlaybackSpeed
	c.Parent = folder
	c:Play()
	c.Ended:Once(function()
		c:Destroy()
	end)
	task.delay(6, function()
		if c.Parent then
			c:Destroy()
		end
	end)
end

local musicOn = true

function Sounds.startMusic()
	if musicOn and not music.IsPlaying then
		music:Play()
	end
end

function Sounds.toggleMusic(): boolean
	musicOn = not musicOn
	if musicOn then
		music:Play()
	else
		music:Stop()
	end
	return musicOn
end

function Sounds.musicOn(): boolean
	return musicOn
end

return Sounds
