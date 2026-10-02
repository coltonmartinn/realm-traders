--!strict
-- Server entry point: owns the one market and every player profile, handles
-- gather/trade/craft/upgrade requests, runs the market tick, and saves.
-- Clients only display what they receive and send requests; nothing they send
-- is trusted.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Goods = require(ReplicatedStorage.Shared.Goods)
local Pets = require(ReplicatedStorage.Shared.Pets)
local Places = require(ReplicatedStorage.Shared.Places)
local Products = require(ReplicatedStorage.Shared.Products)
local Realms = require(ReplicatedStorage.Shared.Realms)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local MarketState = require(script.Parent.MarketState)
local Npc = require(script.Parent.Npc)
local PlayerData = require(script.Parent.PlayerData)
local Codes = require(script.Parent.Codes)
local Happenings = require(script.Parent.Happenings)
local Leaderboard = require(script.Parent.Leaderboard)
local World = require(script.Parent.World)

local Remotes = ReplicatedStorage.Remotes
local TradeRequest = Remotes.TradeRequest :: RemoteEvent
local CraftRequest = Remotes.CraftRequest :: RemoteEvent
local UpgradeRequest = Remotes.UpgradeRequest :: RemoteEvent
local SellAllRequest = Remotes.SellAllRequest :: RemoteEvent
local RebirthRequest = Remotes.RebirthRequest :: RemoteEvent
local DailyRequest = Remotes.DailyRequest :: RemoteEvent
local CodeRequest = Remotes.CodeRequest :: RemoteEvent
local GiftRequest = Remotes.GiftRequest :: RemoteEvent
local QuestRequest = Remotes.QuestRequest :: RemoteEvent
local MarketUpdate = Remotes.MarketUpdate :: RemoteEvent
local PlayerUpdate = Remotes.PlayerUpdate :: RemoteEvent
local Notify = Remotes.Notify :: RemoteEvent

-- Remotes added after the project file was set up are created here, so a
-- Rojo session that hasn't picked up the new project structure still works.
local function remote(name: string): RemoteEvent
	local existing = Remotes:FindFirstChild(name)
	if existing then
		return existing :: RemoteEvent
	end
	local made = Instance.new("RemoteEvent")
	made.Name = name
	made.Parent = Remotes
	return made
end
local PetRequest = remote("PetRequest")

local TICK_SECONDS = 1
local AUTOSAVE_SECONDS = 60
local MIN_REQUEST_GAP = 0.15 -- seconds between accepted trade/craft/upgrade requests per player
local MIN_GATHER_GAP = 0.35 -- prompts hold for 0.5s; this stops instant re-triggers

local market = MarketState.new(Goods)
local lastRequest: { [Player]: number } = {}
local lastGather: { [Player]: number } = {}

local goodName: { [string]: string } = {}
for _, g in Goods do
	goodName[g.id] = g.name
end

-- `realm` says which world's coin `amount` is in (the hub's when missing).
export type Notice = { kind: string, text: string, good: string?, amount: number?, rarity: string?, header: string?, realm: string?, pet: string? }

local function notify(player: Player, notice: Notice)
	Notify:FireClient(player, notice)
end

-- Tells everyone in the server about a big moment (shown as a chat message).
local BIG_SALE = 2000
local function announce(text: string)
	Notify:FireAllClients({ kind = "social", text = text })
end

-- An amount in a world's coin ("$1,250", "❄️1,250").
local function money(n: number, realmId: string?): string
	return Realms.money(n, realmId)
end

-- Which world a player is standing in.
local function realmOf(player: Player): string
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if rootPart then Places.realmAt(rootPart.Position) else Realms.MAIN
end

-- The wallet for the world the player is in, or nil (and a message) if they
-- shouldn't be there yet.
local function hereWallet(player: Player, profile: Rules.Profile): Rules.Wallet?
	local realmId = realmOf(player)
	local lock = Rules.realmLock(profile, realmId)
	if lock then
		Notify:FireClient(player, { kind = "error", text = lock })
		return nil
	end
	return Rules.wallet(profile, realmId)
end

-- After any change: pay out finished goals, refresh leaderstats, send the profile.
local function commit(player: Player, profile: Rules.Profile)
	Rules.refreshQuests(profile, math.floor(workspace:GetServerTimeNow() / 86400))
	for _, realm in Realms.list do
		local w = if realm.id == Realms.MAIN then profile else profile.realms[realm.id]
		if w then
			local firstDone = w.goal
			for i, goal in Rules.advanceGoals(w) do
				local step = Rules.tutorialStep(firstDone + i - 1, w.realm)
				local header = if step == Rules.TUTORIAL_STEPS then "🎓 TUTORIAL COMPLETE! 🎓" elseif step then `🎓 STEP {step} DONE!` else nil
				notify(player, { kind = "goal", text = goal.text, amount = goal.reward, header = header, realm = w.realm })
			end
		end
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")
	if cash then
		(cash :: IntValue).Value = profile.cash
	end
	local rebirths = leaderstats and leaderstats:FindFirstChild("Rebirths")
	if rebirths then
		(rebirths :: IntValue).Value = profile.rebirths
	end
	player:SetAttribute("Helper", profile.upgrades.helper or 1) -- clients draw the bee from this
	player:SetAttribute("Pets", table.concat(profile.pets.equipped, ",")) -- ...and the pets
	PlayerUpdate:FireClient(player, profile)
end

local function allowRequest(player: Player): boolean
	local now = os.clock()
	if now - (lastRequest[player] or 0) < MIN_REQUEST_GAP then
		return false
	end
	lastRequest[player] = now
	return true
end

-- First time you get something (or its Golden/Rainbow form): it goes in your
-- Collection and pays a discovery reward.
local function discover(player: Player, profile: Rules.Profile, goodId: string, variant: string?)
	local reward = Rules.discover(profile, goodId, variant)
	if reward then
		local label = if variant then `{variant} {goodName[goodId]}` else goodName[goodId]
		notify(player, { kind = "upgrade", text = `📖 New in your Collection: {label}! +{money(reward, Rules.goodsById[goodId].realm)}` })
	end
end

-- Requests ----------------------------------------------------------------------

TradeRequest.OnServerEvent:Connect(function(player: Player, goodId: unknown, side: unknown, qty: unknown)
	local profile = PlayerData.get(player)
	if not profile or not allowRequest(player) then
		return
	end
	local w = hereWallet(player, profile)
	if not w then
		return
	end
	-- Each world's goods trade only in that world's market
	local good = type(goodId) == "string" and Rules.goodsById[goodId]
	if not good or good.realm ~= w.realm then
		notify(player, { kind = "error", text = "That isn't sold in this world's market" })
		return
	end
	-- Backpack space is a game rule, not a market rule, so it is checked here.
	if side == "buy" and type(qty) == "number" and qty > Rules.space(w) then
		notify(player, { kind = "error", text = "Not enough backpack space" })
		return
	end
	if side == "sell" and type(qty) == "number" and qty > (w.inventory[good.id] or 0) then
		notify(player, { kind = "error", text = "You don't have that many" })
		return
	end
	local total = MarketState.trade(market, w, good.id, side, qty)
	if not total then
		notify(player, { kind = "error", text = "Trade failed. The price may have moved" })
		return
	end
	if side == "sell" then
		local paid = Rules.recordSale(profile, w, good.id, qty :: number, total)
		notify(player, { kind = "sale", text = `Sold {qty} {good.name} for {money(paid, w.realm)}`, amount = paid, realm = w.realm })
		if paid >= BIG_SALE * Rules.costScale(w.realm) then
			announce(`💰 {player.DisplayName} sold {qty} {good.name} for {money(paid, w.realm)}!`)
		end
	else
		Rules.recordPurchase(w, good.id, qty :: number)
		notify(player, { kind = "buy", text = `Bought {qty} {good.name} for {money(total, w.realm)}`, amount = total, realm = w.realm })
	end
	commit(player, profile)
end)

CraftRequest.OnServerEvent:Connect(function(player: Player, recipeId: unknown, qty: unknown)
	local profile = PlayerData.get(player)
	if not profile or not allowRequest(player) then
		return
	end
	local w = hereWallet(player, profile)
	if not w then
		return
	end
	local ok, why = Rules.craft(w, recipeId, qty)
	if not ok then
		notify(player, { kind = "error", text = why or "Can't craft that" })
		return
	end
	notify(player, { kind = "craft", text = `+{qty} {goodName[recipeId :: string]}`, good = recipeId :: string, amount = qty :: number })
	discover(player, profile, recipeId :: string)
	commit(player, profile)
end)

UpgradeRequest.OnServerEvent:Connect(function(player: Player, upgradeId: unknown)
	local profile = PlayerData.get(player)
	if not profile or not allowRequest(player) then
		return
	end
	local w = hereWallet(player, profile)
	if not w then
		return
	end
	local ok, why = Rules.upgrade(w, upgradeId)
	if not ok then
		notify(player, { kind = "error", text = why or "Can't upgrade" })
		return
	end
	local id = upgradeId :: string
	notify(player, { kind = "upgrade", text = `{Upgrades.byId[id].name} upgraded to level {w.upgrades[id]}!` })
	commit(player, profile)
end)

-- Sells everything in the backpack, good by good, in chunks of MAX_QTY.
SellAllRequest.OnServerEvent:Connect(function(player: Player)
	local profile = PlayerData.get(player)
	if not profile or not allowRequest(player) then
		return
	end
	local w = hereWallet(player, profile)
	if not w then
		return
	end
	local total, count = 0, 0
	for _, id in market.order do
		local owned = w.inventory[id]
		while owned and owned > 0 do
			local n = math.min(owned, MarketState.MAX_QTY)
			local value = MarketState.trade(market, w, id, "sell", n)
			if not value then
				break
			end
			total += Rules.recordSale(profile, w, id, n, value)
			count += n
			owned = w.inventory[id]
		end
	end
	if count == 0 then
		notify(player, { kind = "error", text = "Your backpack is empty" })
		return
	end
	notify(player, { kind = "sale", text = `Sold {count} items for {money(total, w.realm)}`, amount = total, realm = w.realm })
	if total >= BIG_SALE * Rules.costScale(w.realm) then
		announce(`💰 {player.DisplayName} sold {count} items for {money(total, w.realm)}!`)
	end
	commit(player, profile)
end)

RebirthRequest.OnServerEvent:Connect(function(player: Player)
	local profile = PlayerData.get(player)
	if not profile or not allowRequest(player) then
		return
	end
	local ok, why = Rules.rebirth(profile)
	if not ok then
		notify(player, { kind = "error", text = why or "Can't expand yet" })
		return
	end
	notify(player, { kind = "rebirth", text = `Business expanded! Sales now pay +{math.floor((Rules.saleMultiplier(profile) - 1) * 100 + 0.5)}%`, amount = profile.rebirths })
	announce(`⭐ {player.DisplayName} expanded their business! (Rebirth {profile.rebirths})`)
	commit(player, profile)
end)

local function today(): number
	return math.floor(workspace:GetServerTimeNow() / 86400)
end

DailyRequest.OnServerEvent:Connect(function(player: Player)
	local profile = PlayerData.get(player)
	if not profile or not allowRequest(player) then
		return
	end
	local reward = Rules.claimDaily(profile, today())
	if not reward then
		notify(player, { kind = "error", text = "Come back tomorrow for your next reward!" })
		return
	end
	notify(player, { kind = "daily", text = `Day {profile.daily.streak} reward: {money(reward)}!`, amount = reward })
	commit(player, profile)
end)

-- Session gifts: the server's clock is the one that counts.
local sessionStart: { [Player]: number } = {}
local giftsClaimed: { [Player]: number } = {}

GiftRequest.OnServerEvent:Connect(function(player: Player)
	local profile = PlayerData.get(player)
	local started = sessionStart[player]
	if not profile or not started or not allowRequest(player) then
		return
	end
	local index = (giftsClaimed[player] or 0) + 1
	local gift = Rules.GIFTS[index]
	if not gift then
		notify(player, { kind = "error", text = "You've opened every gift this session!" })
		return
	end
	local wait = gift.seconds - (os.clock() - started)
	if wait > 1 then
		notify(player, { kind = "error", text = `Your next gift opens in {math.ceil(wait / 60)} min` })
		return
	end
	giftsClaimed[player] = index
	local reward = Rules.giftReward(profile, index)
	profile.cash += reward
	notify(player, { kind = "daily", text = `Free gift: {money(reward)}!`, amount = reward })
	commit(player, profile)
end)

QuestRequest.OnServerEvent:Connect(function(player: Player, index: unknown)
	local profile = PlayerData.get(player)
	if not profile or not allowRequest(player) then
		return
	end
	local reward, why = Rules.claimQuest(profile, index, today())
	if not reward then
		notify(player, { kind = "error", text = why or "Can't claim that" })
		commit(player, profile) -- also hands out a new day's quests if needed
		return
	end
	notify(player, { kind = "daily", text = `Quest complete: {money(reward)}!`, amount = reward })
	commit(player, profile)
end)

CodeRequest.OnServerEvent:Connect(function(player: Player, code: unknown)
	local profile = PlayerData.get(player)
	if not profile or not allowRequest(player) then
		return
	end
	local reward, why = Rules.redeem(profile, code, Codes)
	if not reward then
		notify(player, { kind = "error", text = why or "Invalid code" })
		return
	end
	notify(player, { kind = "daily", text = `Code redeemed: {money(reward)}!`, amount = reward })
	commit(player, profile)
end)

-- Pets: buy with a world's coin, equip or unequip.
PetRequest.OnServerEvent:Connect(function(player: Player, action: unknown, petId: unknown)
	local profile = PlayerData.get(player)
	if not profile or not allowRequest(player) then
		return
	end
	local ok, why
	if action == "buy" then
		ok, why = Rules.buyPet(profile, petId)
	elseif action == "equip" or action == "unequip" then
		ok, why = Rules.equipPet(profile, petId, action == "equip")
	end
	if not ok then
		notify(player, { kind = "error", text = why or "Can't do that" })
		return
	end
	local pet = Pets.byId[petId :: string]
	if action == "buy" then
		notify(player, { kind = "goal", header = "🐾 NEW PET! 🐾", text = `{pet.icon} {pet.name}: +{math.floor(pet.bonus * 100 + 0.5)}% sell bonus`, pet = pet.id })
	end
	commit(player, profile)
end)

-- Lucky finds: rolled on every gather. In Studio, set the ForceLucky attribute
-- on this folder to "Golden" or "Rainbow" to force the next one (testing).
local function tryLucky(player: Player, profile: Rules.Profile, w: Rules.Wallet, goodId: string, gained: number)
	local lucky = Rules.rollLucky(math.random() / Rules.boostMult(profile, "luck"))
	local forced = game:GetService("RunService"):IsStudio() and script.Parent:GetAttribute("ForceLucky")
	if type(forced) == "string" then
		script.Parent:SetAttribute("ForceLucky", nil)
		for _, l in Rules.LUCKY do
			if l.name == forced then
				lucky = l
			end
		end
	end
	if not lucky then
		return
	end
	local cash = Rules.payLucky(w, lucky, goodId, gained)
	discover(player, profile, goodId, lucky.name)
	local text = `{lucky.icon} {lucky.name:upper()} {goodName[goodId]:upper()}!`
	notify(player, { kind = "lucky", text = text, good = goodId, amount = cash, rarity = lucky.name, realm = w.realm })
	if lucky.name == "Rainbow" then
		announce(`🌈 {player.DisplayName} found a RAINBOW {goodName[goodId]:upper()} worth {money(cash, w.realm)}!`)
	end
end

-- Gathering (called by World when a node's prompt is triggered) ------------------

local function onGather(player: Player, node: World.Node): boolean
	local profile = PlayerData.get(player)
	if not profile then
		return false
	end
	local now = os.clock()
	if now - (lastGather[player] or 0) < MIN_GATHER_GAP then
		return false
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local nodePart = node.prompt.Parent :: BasePart
	if not rootPart or (rootPart.Position - nodePart.Position).Magnitude > node.prompt.MaxActivationDistance + 6 then
		return false
	end
	lastGather[player] = now

	local w = Rules.wallet(profile, Rules.goodsById[node.goodId].realm)
	local gained, why = Rules.gather(profile, w, node.goodId)
	if not gained then
		notify(player, { kind = "error", text = why or "Can't gather that" })
		return false
	end
	notify(player, { kind = "gain", text = `+{gained} {goodName[node.goodId]}`, good = node.goodId, amount = gained })
	discover(player, profile, node.goodId)
	tryLucky(player, profile, w, node.goodId, gained)
	commit(player, profile)
	return true
end

-- Portals (called by World when someone walks into one) --------------------------

local function teleport(player: Player, to: Vector3)
	local character = player.Character
	if character then
		character:PivotTo(CFrame.lookAt(to + Vector3.new(0, 3.5, 0), to + Vector3.new(0, 3.5, -20)))
	end
end

local function onPortal(player: Player, realmId: string)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	if realmId == Realms.MAIN then
		teleport(player, Places.SPAWN)
		return
	end
	local lock = Rules.realmLock(profile, realmId)
	if lock then
		notify(player, { kind = "error", text = lock })
		return
	end
	local realm = Realms.byId[realmId]
	local firstVisit = profile.realms[realmId] == nil
	Rules.wallet(profile, realmId)
	teleport(player, Places.spawn(realmId))
	if firstVisit then
		notify(player, { kind = "goal", header = `{realm.icon} WELCOME TO {realm.name:upper()}!`, text = `A new world with its own {realm.coinName}` })
		announce(`{realm.icon} {player.DisplayName} discovered {realm.name}!`)
	end
	commit(player, profile)
end

World.build(onGather, onPortal)
Leaderboard.start(workspace:WaitForChild("World"), PlayerData.get)
Happenings.start(market, {
	getProfile = PlayerData.get,
	notify = notify,
	commit = commit,
	money = money,
})

-- Players -----------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = leaderstats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = leaderstats
	leaderstats.Parent = player

	sessionStart[player] = os.clock()
	MarketUpdate:FireClient(player, MarketState.snapshot(market))
	Happenings.sendTo(player)
	local profile, saving, why = PlayerData.load(player)
	if player.Parent == nil then
		-- Left while loading
		PlayerData.unload(player)
		return
	end
	commit(player, profile)
	if not saving then
		notify(player, {
			kind = "warn",
			text = if why == "locked"
				then "Your last server is still saving. Rejoin in a minute to keep your progress!"
				else "Couldn't reach saved data. Progress this session won't be saved.",
		})
	end
end

local WALK_SPEED = 20 -- a little faster than default; zones are a short jog apart

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.WalkSpeed = WALK_SPEED
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacter)
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	PlayerData.unload(player)
	lastRequest[player] = nil
	lastGather[player] = nil
	sessionStart[player] = nil
	giftsClaimed[player] = nil
end)

-- Studio-only test hook: set the DevGrant attribute on this folder to a number
-- to give every player that much of the coin of the world they're in. Never active in a live server.
if game:GetService("RunService"):IsStudio() then
	script.Parent:GetAttributeChangedSignal("DevGrant"):Connect(function()
		local amount = script.Parent:GetAttribute("DevGrant")
		if type(amount) == "number" and amount > 0 then
			for _, player in Players:GetPlayers() do
				local profile = PlayerData.get(player)
				if profile then
					-- Into the wallet of the world they're standing in
					Rules.wallet(profile, realmOf(player)).cash += math.floor(amount)
					commit(player, profile)
				end
			end
			script.Parent:SetAttribute("DevGrant", 0)
		end
	end)
end

-- Helper Bees gather for players standing inside a zone they can use.
local helperProgress: { [Player]: number } = {}
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local profile = PlayerData.get(player)
			local rate = profile and Rules.helperRate(profile) or 0
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if profile and rate > 0 and rootPart then
				local zone = nil
				for _, place in Places.list do
					if place.kind == "zone" and ((rootPart.Position - place.center) * Vector3.new(1, 0, 1)).Magnitude <= place.radius + 2 then
						zone = place
					end
				end
				local w = zone and Rules.wallet(profile, zone.realm)
				if zone and zone.good and w and Rules.gatherBlock(profile, w, zone.good) == nil then
					local acc = (helperProgress[player] or 0) + rate / 60
					if acc >= 1 then
						acc -= 1
						local gained = Rules.gather(profile, w, zone.good)
						if gained then
							notify(player, { kind = "auto", text = `+{gained} {goodName[zone.good]}`, good = zone.good, amount = gained })
							discover(player, profile, zone.good)
							tryLucky(player, profile, w, zone.good, gained)
							commit(player, profile)
						end
					end
					helperProgress[player] = acc
				end
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(player)
	helperProgress[player] = nil
end)

-- Robux purchases -----------------------------------------------------------------

local function grant(player: Player, profile: Rules.Profile, product: Products.Product, purchaseId: string)
	local granted, hatched = Rules.grantProduct(profile, product, purchaseId, math.random())
	if not granted then
		return -- already granted (Roblox retried the receipt)
	end
	if product.kind == "egg" then
		if hatched then
			notify(player, { kind = "goal", header = "🥚 EXOTIC HATCH! 🥚", text = `{hatched.icon} {hatched.name}: +{math.floor(hatched.bonus * 100 + 0.5)}% sell bonus!`, pet = hatched.id })
			announce(`🥚 {player.DisplayName} hatched an exotic {hatched.icon} {hatched.name}!`)
		else
			notify(player, { kind = "daily", text = `You have every exotic! Here's {money(Rules.EGG_FALLBACK_CASH * (1 + profile.rebirths))} instead`, amount = Rules.EGG_FALLBACK_CASH * (1 + profile.rebirths) })
		end
	elseif product.kind == "cash" then
		notify(player, { kind = "daily", text = `Thanks for your support! +{money(Rules.packCash(profile, product))}`, amount = Rules.packCash(profile, product) })
	else
		local boost = Products.BOOSTS[product.boost :: string]
		notify(player, { kind = "upgrade", text = `{boost.icon} {boost.name} active for {math.ceil((profile.boosts[boost.id] or 0) / 60)} min!` })
	end
	commit(player, profile)
end

-- Roblox calls this (and retries until it gets PurchaseGranted) for every
-- Developer Product bought. Grant once per PurchaseId, and only report it
-- granted once that's saved, so a crash can't lose a paid purchase.
MarketplaceService.ProcessReceipt = function(receipt)
	local product = Products.byId[receipt.ProductId]
	if not product then
		warn(`[Shop] unknown product {receipt.ProductId}; add its ID to Products.luau`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = player and PlayerData.get(player)
	if not player or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- granted when they're next in a server
	end
	grant(player, profile, product, receipt.PurchaseId)
	if PlayerData.isSaving(player) and not PlayerData.save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Boosts count down only while the player is in the game.
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local profile = PlayerData.get(player)
			if profile and next(profile.boosts) then
				local ended = Rules.tickBoosts(profile, 1)
				for _, id in ended do
					local boost = Products.BOOSTS[id]
					notify(player, { kind = "warn", text = `{boost.icon} Your {boost.name} boost ran out. Get more in the 🛍️ Shop!` })
				end
				if #ended > 0 then
					commit(player, profile)
				end
			end
		end
	end
end)

-- Studio-only test hook: set the TestPurchase attribute on this folder to a
-- product key (e.g. "boost_sell") to grant it to every player, as if bought.
if game:GetService("RunService"):IsStudio() then
	script.Parent:GetAttributeChangedSignal("TestPurchase"):Connect(function()
		local key = script.Parent:GetAttribute("TestPurchase")
		local product = type(key) == "string" and Products.byKey[key]
		if product then
			for _, player in Players:GetPlayers() do
				local profile = PlayerData.get(player)
				if profile then
					grant(player, profile, product, `studio-{os.clock()}`)
				end
			end
		end
		if key ~= nil then
			script.Parent:SetAttribute("TestPurchase", nil)
		end
	end)
end

game:BindToClose(PlayerData.saveAll)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, player in Players:GetPlayers() do
			task.spawn(PlayerData.save, player)
		end
	end
end)

while true do
	task.wait(TICK_SECONDS)
	Npc.step(market)
	MarketState.tick(market)
	MarketUpdate:FireAllClients(MarketState.snapshot(market))
end
