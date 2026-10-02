--!strict
-- Fast travel to any shop or zone (like Grow a Garden's top teleport buttons).
-- The character is client-owned, so moving it here replicates on its own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Ui = require(script.Parent.Ui)

local Travel = {}

local fade: Frame
local busy = false

function Travel.init(gui: ScreenGui)
	fade = Ui.new("Frame", {
		Name = "TravelFade",
		Parent = gui,
		-- Reaches up under the top bar inset too
		Size = UDim2.new(1, 0, 1, 60),
		Position = UDim2.fromOffset(0, -60),
		BackgroundColor3 = Theme.paper,
		BackgroundTransparency = 1,
		ZIndex = 50,
		Visible = false,
	})
end

-- Why the player can't go there yet, or nil.
function Travel.blocked(placeId: string): string?
	local place = Places.byId[placeId]
	local p = Store.profile
	if not (place and p) then
		return nil
	end
	local lock = Rules.realmLock(p, place.realm) or Rules.lockReason(p, Rules.wallet(p, place.realm), place.gearLevel, place.rebirths)
	return if lock then `The {place.name} is locked. {lock}` else nil
end

local function teleport(cf: CFrame)
	local character = Players.LocalPlayer.Character
	if not character or busy then
		return
	end
	busy = true
	fade.Visible = true
	Ui.tween(fade, 0.15, { BackgroundTransparency = 0 }).Completed:Wait()
	character:PivotTo(cf + Vector3.new(0, 3, 0))
	-- Swing the camera behind the character so you face where you arrived
	local camera = workspace.CurrentCamera
	if camera then
		local eye = cf * CFrame.new(0, 9, 16)
		camera.CFrame = CFrame.lookAt(eye.Position, cf.Position + Vector3.new(0, 3, 0))
	end
	task.wait(0.05)
	Ui.tween(fade, 0.3, { BackgroundTransparency = 1 }).Completed:Wait()
	fade.Visible = false
	busy = false
end

function Travel.go(placeId: string)
	local place = Places.byId[placeId]
	if not place then
		return
	end
	local why = Travel.blocked(placeId)
	if why then
		Toasts.error(why)
		return
	end
	teleport(Places.arrival(place))
end

-- In front of this world's Deep Mine lift.
function Travel.toMine()
	local realm = Store.realm
	local at = Places.mineEntrance(realm)
	local center = Places.CENTERS[realm] or Places.HUB
	local front = at + ((center - at) * Vector3.new(1, 0, 1)).Unit * 12
	teleport(CFrame.lookAt(front, Vector3.new(at.X, front.Y, at.Z)))
end

-- Back to Market Town's plaza (leaving a world is always allowed).
function Travel.home()
	teleport(CFrame.lookAt(Places.SPAWN, Places.SPAWN + Vector3.new(0, 0, -20)))
end

-- In front of the hub's portals.
function Travel.toPortals()
	local at = Places.PORTALS.frost
	local front = at + (Places.HUB - at).Unit * 14
	teleport(CFrame.lookAt(front, Vector3.new(at.X, front.Y, at.Z)))
end

-- Next to the Travelling Merchant's cart, facing it.
function Travel.toMerchant()
	local front = Places.MERCHANT + (Places.HUB - Places.MERCHANT).Unit * 8
	teleport(CFrame.lookAt(front, Vector3.new(Places.MERCHANT.X, front.Y, Places.MERCHANT.Z)))
end

return Travel
