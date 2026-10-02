--!strict
-- Game rules on a player profile: gathering, crafting, upgrades, goals.
-- Pure and shared: the server runs them for real, the client runs them to
-- grey out buttons and explain why. Every function taking `unknown` treats it
-- as untrusted client input.
--
-- Worlds: each world's own progress (cash, backpack, gear, goals...) is a
-- Wallet. The hub's wallet is the profile itself (so old saves load as-is);
-- other worlds' live in profile.realms. Functions that only touch one world
-- take a Wallet `w`; ones that also need player-wide things (rebirths, pets,
-- boosts) take the profile `p` too.

local Goals = require("./Goals")
local Goods = require("./Goods")
local Pets = require("./Pets")
local Products = require("./Products")
local Realms = require("./Realms")
local Recipes = require("./Recipes")
local Upgrades = require("./Upgrades")

export type Wallet = {
	realm: string, -- Realms id
	cash: number,
	inventory: { [string]: number },
	upgrades: { [string]: number },
	stats: Goals.Stats,
	goal: number, -- index into the world's goal chain; past the end means all done
	bought: { [string]: number }, -- units in the backpack that came from the market
}

export type Profile = {
	realm: string, -- always "main": the profile is also the hub's wallet
	cash: number,
	inventory: { [string]: number },
	upgrades: { [string]: number },
	stats: Goals.Stats,
	goal: number,
	bought: { [string]: number },
	rebirths: number, -- each one adds REBIRTH_BONUS to sales of goods you made
	daily: { day: number, streak: number }, -- last claimed day (days since epoch) and streak length
	codes: { [string]: boolean }, -- promo codes already redeemed
	quests: Quests, -- today's daily quests
	collection: { [string]: boolean }, -- discovered "good" or "good:Golden" / "good:Rainbow"
	boosts: { [string]: number }, -- seconds left on each bought boost (counts down while online)
	receipts: { string }, -- recent Robux purchase IDs, so a purchase is never granted twice
	realms: { [string]: Wallet }, -- progress in the portal worlds
	pets: { owned: { [string]: boolean }, equipped: { string } },
}

export type Quest = { kind: string, good: string?, target: number, reward: number, claimed: boolean }
-- `base` is a copy of stats when the day's quests were handed out; progress is
-- measured from there.
export type Quests = { day: number, list: { Quest }, base: { gathered: { [string]: number }, crafted: { [string]: number }, earned: number } }

local START_CASH = 100
local MAX_CRAFT = 20
local REBIRTH_BONUS = 0.25
local DAILY_REWARDS = { 50, 100, 150, 250, 400, 600, 1500 } -- day 7 is the big one
local RECEIPTS_KEPT = 50 -- recent purchase IDs remembered per player

local goodsById: { [string]: Goods.Good } = {}
for _, g in Goods do
	goodsById[g.id] = g
end

local recipesById: { [string]: Recipes.Recipe } = {}
for _, r in Recipes do
	recipesById[r.id] = r
end

local Rules = {}

Rules.START_CASH = START_CASH
Rules.REBIRTH_BONUS = REBIRTH_BONUS
Rules.DAILY_REWARDS = DAILY_REWARDS
Rules.MAX_CRAFT = MAX_CRAFT
Rules.goodsById = goodsById
Rules.recipesById = recipesById

-- Free gifts for staying in a session: unlock after `seconds` of play.
Rules.GIFTS = {
	{ seconds = 3 * 60, cash = 150 },
	{ seconds = 10 * 60, cash = 400 },
	{ seconds = 20 * 60, cash = 1000 },
	{ seconds = 40 * 60, cash = 2500 },
}

-- Lucky finds (like Grow a Garden's Gold/Rainbow mutations): any gather may
-- turn up something special that pays a multiple of the good's value.
export type Lucky = { name: string, icon: string, chance: number, mult: number }
Rules.LUCKY = {
	{ name = "Rainbow", icon = "🌈", chance = 0.001, mult = 50 },
	{ name = "Golden", icon = "✨", chance = 0.01, mult = 10 },
} :: { Lucky }

-- Which lucky find a roll in [0, 1) gives, rarest first, or nil.
function Rules.rollLucky(roll: number): Lucky?
	local edge = 0
	for _, lucky in Rules.LUCKY do
		edge += lucky.chance
		if roll < edge then
			return lucky
		end
	end
	return nil
end

-- Pays a lucky find on a gather of `gained` units of goodId into w. Returns the cash.
function Rules.payLucky(w: Wallet, lucky: Lucky, goodId: string, gained: number): number
	local good = goodsById[goodId]
	local cash = math.floor(lucky.mult * good.basePrice * gained)
	w.cash += cash
	return cash
end

function Rules.giftReward(p: Profile, index: number): number
	local gift = Rules.GIFTS[index]
	return if gift then gift.cash * (1 + p.rebirths) else 0
end

-- New profiles and saves --------------------------------------------------------

local function startUpgrades(): { [string]: number }
	local upgrades = {}
	for _, u in Upgrades.list do
		upgrades[u.id] = 1
	end
	return upgrades
end

function Rules.newWallet(realmId: string): Wallet
	local realm = Realms.byId[realmId]
	return {
		realm = realmId,
		cash = realm.startCash,
		inventory = {},
		upgrades = startUpgrades(),
		stats = { gathered = {}, crafted = {}, sold = 0, earned = 0 },
		goal = 1,
		bought = {},
	}
end

function Rules.newProfile(): Profile
	return {
		realm = Realms.MAIN,
		cash = START_CASH,
		inventory = {},
		upgrades = startUpgrades(),
		stats = { gathered = {}, crafted = {}, sold = 0, earned = 0 },
		goal = 1,
		bought = {},
		rebirths = 0,
		daily = { day = 0, streak = 0 },
		codes = {},
		quests = { day = 0, list = {}, base = { gathered = {}, crafted = {}, earned = 0 } },
		collection = {},
		boosts = {},
		receipts = {},
		realms = {},
		pets = { owned = {}, equipped = {} },
	}
end

local function count(v: unknown): number
	if type(v) == "number" and v == v and v >= 0 and v < math.huge then
		return math.floor(v)
	end
	return 0
end

local function counts(t: unknown, valid: { [string]: any }): { [string]: number }
	local out = {}
	if type(t) == "table" then
		for id in valid do
			local n = count((t :: any)[id])
			if n > 0 then
				out[id] = n
			end
		end
	end
	return out
end

-- Fills a wallet's fields from saved data, keeping only its own world's goods.
local function reconcileWallet(w: Wallet, s: any)
	local goods = {}
	for id, g in goodsById do
		if g.realm == w.realm then
			goods[id] = g
		end
	end
	if type(s.cash) == "number" then
		w.cash = count(s.cash)
	end
	w.inventory = counts(s.inventory, goods)
	for id, n in counts(s.upgrades, Upgrades.byId) do
		w.upgrades[id] = math.clamp(n, 1, Upgrades.maxLevel(id))
	end
	if type(s.stats) == "table" then
		w.stats.gathered = counts(s.stats.gathered, goods)
		w.stats.crafted = counts(s.stats.crafted, goods)
		w.stats.sold = count(s.stats.sold)
		w.stats.earned = count(s.stats.earned)
	end
	w.goal = math.clamp(count(s.goal), 1, #Goals[w.realm] + 1)
	w.bought = counts(s.bought, goods)
	for id, n in w.bought do
		w.bought[id] = math.min(n, w.inventory[id] or 0)
	end
end

-- Builds a clean profile from saved data, dropping anything unknown or broken,
-- so old saves and new goods/upgrades both load safely.
function Rules.reconcile(saved: unknown): Profile
	local p = Rules.newProfile()
	if type(saved) ~= "table" then
		return p
	end
	local s = saved :: any
	reconcileWallet(p, s)
	p.rebirths = count(s.rebirths)
	if type(s.realms) == "table" then
		for _, realm in Realms.list do
			if realm.id ~= Realms.MAIN and type(s.realms[realm.id]) == "table" then
				local w = Rules.newWallet(realm.id)
				reconcileWallet(w, s.realms[realm.id])
				p.realms[realm.id] = w
			end
		end
	end
	if type(s.pets) == "table" then
		if type(s.pets.owned) == "table" then
			for id in Pets.byId do
				if s.pets.owned[id] == true then
					p.pets.owned[id] = true
				end
			end
		end
		if type(s.pets.equipped) == "table" then
			for _, id in s.pets.equipped do
				if type(id) == "string" and p.pets.owned[id] and not table.find(p.pets.equipped, id) and #p.pets.equipped < Pets.SLOTS then
					table.insert(p.pets.equipped, id)
				end
			end
		end
	end
	if type(s.codes) == "table" then
		for code, used in s.codes do
			if type(code) == "string" and #code <= 30 and used == true then
				p.codes[code] = true
			end
		end
	end
	if type(s.quests) == "table" and type(s.quests.list) == "table" and type(s.quests.base) == "table" then
		local list = {}
		for _, q in s.quests.list do
			if type(q) == "table" and type(q.kind) == "string" and type(q.target) == "number" and type(q.reward) == "number" then
				table.insert(list, { kind = q.kind, good = if type(q.good) == "string" then q.good else nil, target = count(q.target), reward = count(q.reward), claimed = q.claimed == true })
			end
		end
		p.quests = {
			day = count(s.quests.day),
			list = list,
			base = { gathered = counts(s.quests.base.gathered, goodsById), crafted = counts(s.quests.base.crafted, goodsById), earned = count(s.quests.base.earned) },
		}
	end
	if type(s.collection) == "table" then
		for key in Rules.collectionKeys() do
			if s.collection[key] == true then
				p.collection[key] = true
			end
		end
	end
	for id, n in counts(s.boosts, Products.BOOSTS) do
		p.boosts[id] = math.min(n, Products.MAX_BOOST_SECONDS)
	end
	if type(s.receipts) == "table" then
		for _, r in s.receipts do
			if type(r) == "string" and #r <= 100 and #p.receipts < RECEIPTS_KEPT then
				table.insert(p.receipts, r)
			end
		end
	end
	if type(s.daily) == "table" then
		p.daily = { day = count(s.daily.day), streak = count(s.daily.streak) }
	end
	return p
end

-- Worlds ---------------------------------------------------------------------

-- The wallet for a world (the profile itself for the hub), created on first visit.
function Rules.wallet(p: Profile, realmId: string): Wallet
	if realmId == Realms.MAIN or not Realms.byId[realmId] then
		return p
	end
	local w = p.realms[realmId]
	if not w then
		w = Rules.newWallet(realmId)
		p.realms[realmId] = w
	end
	return w
end

-- Why p can't enter a world yet, or nil.
function Rules.realmLock(p: Profile, realmId: string): string?
	local realm = Realms.byId[realmId]
	if not realm then
		return "Unknown world"
	end
	if p.rebirths < realm.rebirths then
		return `{realm.icon} {realm.name} opens at {realm.rebirths} Rebirths (you have {p.rebirths})`
	end
	return nil
end

-- A world's scale for prices, costs and rewards (1 in the hub).
function Rules.costScale(realmId: string): number
	local realm = Realms.byId[realmId]
	return if realm then realm.costScale else 1
end

-- Backpack and gathering ----------------------------------------------------------

function Rules.itemCount(w: Wallet): number
	local n = 0
	for _, qty in w.inventory do
		n += qty
	end
	return n
end

function Rules.capacity(w: Wallet): number
	return Upgrades.value("backpack", w.upgrades.backpack)
end

function Rules.space(w: Wallet): number
	return math.max(0, Rules.capacity(w) - Rules.itemCount(w))
end

-- Automatic gathers per minute from the Helper Bee (0 without one).
function Rules.helperRate(p: Profile): number
	return Upgrades.value("helper", p.upgrades.helper or 1)
end

function Rules.gatherYield(p: Profile, w: Wallet): number
	return Upgrades.value("gear", w.upgrades.gear) * Rules.boostMult(p, "gather")
end

-- Why something gated by gear level (in world w) and/or rebirths is still
-- locked, or nil.
function Rules.lockReason(p: Profile, w: Wallet, gearLevel: number?, rebirths: number?): string?
	if rebirths and p.rebirths < rebirths then
		return "Unlocks after your first Rebirth (Expand Business at the Outfitter)"
	end
	if gearLevel and w.upgrades.gear < gearLevel then
		return `Needs Gear level {gearLevel}. Upgrade at the Outfitter`
	end
	return nil
end

-- Deep Mine ------------------------------------------------------------------------

Rules.MINE_DEPTHS = 5
Rules.LEGENDARY_CHANCE = 0.002 -- per swing, per mine level down (1% on level 5)

-- The deepest mine level w can reach: its Gear level in Market Town, its
-- Thermal Gear in Frostpeak, its Fireproof Armor in Emberfall.
function Rules.mineDepth(w: Wallet): number
	local id = Upgrades.DEPTH[w.realm] or "gear"
	return math.min(Upgrades.value(id, w.upgrades[id] or 1), Rules.MINE_DEPTHS)
end

-- Why w can't go down to mine level `depth`, or nil.
function Rules.depthBlock(w: Wallet, depth: number): string?
	if depth < 1 or depth > Rules.MINE_DEPTHS or depth ~= math.floor(depth) then
		return "There's no such level"
	end
	if Rules.mineDepth(w) < depth then
		local upgrade = Upgrades.byId[Upgrades.DEPTH[w.realm] or "gear"]
		return `Level {depth} needs {upgrade.icon} {upgrade.name} level {depth}. Upgrade at the Outfitter`
	end
	return nil
end

-- Chance (in %) of each ore tier, 1 (common) to 5 (rarest), per mine level.
-- Every level can turn up anything; deeper levels make good ores the norm.
-- Average value per swing roughly matches gathering at the gear the level needs, times 1.5-2.
Rules.ORE_ODDS = {
	{ 80, 16, 3.5, 0.45, 0.05 },
	{ 45, 32, 16, 5, 2 },
	{ 15, 27, 33, 17, 8 },
	{ 5, 15, 30, 32, 18 },
	{ 2, 6, 17, 35, 40 },
} :: { { number } }

-- A world's ore of a given tier.
function Rules.oreAt(realmId: string, tier: number): Goods.Good?
	for _, g in Goods do
		if g.realm == realmId and g.tier == tier then
			return g
		end
	end
	return nil
end

-- Each ore on a mine level with its chance (0-1), commonest first.
function Rules.oreOdds(realmId: string, depth: number): { { good: Goods.Good, chance: number } }
	local out = {}
	local odds = Rules.ORE_ODDS[math.clamp(depth, 1, #Rules.ORE_ODDS)]
	for tier, pct in odds do
		local good = Rules.oreAt(realmId, tier)
		if good then
			table.insert(out, { good = good, chance = pct / 100 })
		end
	end
	return out
end

-- Which ore a swing on a mine level turns up, for a roll in [0, 1).
function Rules.rollOre(realmId: string, depth: number, roll: number): Goods.Good
	local edge = 0
	local odds = Rules.oreOdds(realmId, depth)
	for _, o in odds do
		edge += o.chance
		if roll < edge then
			return o.good
		end
	end
	return odds[#odds].good
end

-- Average value of one swing on a mine level (at base prices).
function Rules.oreValue(realmId: string, depth: number): number
	local v = 0
	for _, o in Rules.oreOdds(realmId, depth) do
		v += o.chance * o.good.basePrice
	end
	return v
end

-- One swing on mine level `depth` of w's world that turned up oreId: adds it
-- (one per swing, two with a Gather boost). Returns the amount, or nil and why.
function Rules.mine(p: Profile, w: Wallet, depth: number, oreId: string): (number?, string?)
	local good = goodsById[oreId]
	if not good or not good.tier or good.realm ~= w.realm then
		return nil, "That isn't found here"
	end
	local block = Rules.realmLock(p, w.realm) or Rules.depthBlock(w, depth)
	if block then
		return nil, block
	end
	if Rules.space(w) <= 0 then
		return nil, "Backpack full! Sell or craft to make room"
	end
	local gained = math.min(Rules.boostMult(p, "gather"), Rules.space(w))
	w.inventory[oreId] = (w.inventory[oreId] or 0) + gained
	w.stats.gathered[oreId] = (w.stats.gathered[oreId] or 0) + gained
	return gained, nil
end

-- A world's legendary ore.
function Rules.legendaryOf(realmId: string): Goods.Good?
	for _, g in Goods do
		if g.realm == realmId and g.legendary then
			return g
		end
	end
	return nil
end

-- Chance that a swing on mine level `depth` also turns up the legendary ore.
function Rules.legendaryChance(depth: number): number
	return Rules.LEGENDARY_CHANCE * depth
end

-- Adds one legendary ore of w's world (if there's room). Returns whether it did.
function Rules.findLegendary(w: Wallet): boolean
	local good = Rules.legendaryOf(w.realm)
	if not good or Rules.space(w) <= 0 then
		return false
	end
	w.inventory[good.id] = (w.inventory[good.id] or 0) + 1
	w.stats.gathered[good.id] = (w.stats.gathered[good.id] or 0) + 1
	return true
end

-- Why goodId can't be gathered into wallet w right now, or nil if it can.
function Rules.gatherBlock(p: Profile, w: Wallet, goodId: string): string?
	local good = goodsById[goodId]
	if not good or not good.raw or good.realm ~= w.realm or good.legendary or good.tier then
		return "That can't be gathered" -- ores are mined (Rules.mine)
	end
	local lock = Rules.realmLock(p, w.realm) or Rules.lockReason(p, w, good.gearLevel, good.rebirths)
	if lock then
		return lock
	end
	if Rules.space(w) <= 0 then
		return "Backpack full! Sell or craft to make room"
	end
	return nil
end

-- Adds one gather's worth of goodId to w, limited by backpack space.
-- Returns the amount gained, or nil and the reason.
function Rules.gather(p: Profile, w: Wallet, goodId: string): (number?, string?)
	local block = Rules.gatherBlock(p, w, goodId)
	if block then
		return nil, block
	end
	local gained = math.min(Rules.gatherYield(p, w), Rules.space(w))
	w.inventory[goodId] = (w.inventory[goodId] or 0) + gained
	w.stats.gathered[goodId] = (w.stats.gathered[goodId] or 0) + gained
	return gained, nil
end

-- Crafting ------------------------------------------------------------------------

-- How many of recipeId could be crafted from w right now (capped at MAX_CRAFT).
function Rules.craftable(w: Wallet, recipeId: string): number
	local recipe = recipesById[recipeId]
	if not recipe or recipe.realm ~= w.realm then
		return 0
	end
	local n = MAX_CRAFT
	for _, input in recipe.inputs do
		n = math.min(n, (w.inventory[input.id] or 0) // input.qty)
	end
	return n
end

-- Crafts qty units in w. Inputs always outnumber the output, so this never
-- overfills the backpack. Returns true, or false and the reason.
function Rules.craft(w: Wallet, recipeId: unknown, qty: unknown): (boolean, string?)
	if type(recipeId) ~= "string" or not recipesById[recipeId] or recipesById[recipeId].realm ~= w.realm then
		return false, "Unknown recipe"
	end
	if type(qty) ~= "number" or qty ~= math.floor(qty) or qty < 1 or qty > MAX_CRAFT then
		return false, "Bad amount"
	end
	local recipe = recipesById[recipeId]
	if Rules.craftable(w, recipeId) < qty then
		return false, "Not enough materials"
	end
	-- Inputs bought from the market make the output count as bought too (in
	-- proportion), so buy -> craft -> sell can't farm the sale bonus.
	local used, usedBought = 0, 0
	for _, input in recipe.inputs do
		local n = input.qty * qty
		local left = w.inventory[input.id] - n
		w.inventory[input.id] = if left > 0 then left else nil
		local b = math.min(w.bought[input.id] or 0, n)
		local bLeft = (w.bought[input.id] or 0) - b
		w.bought[input.id] = if bLeft > 0 then bLeft else nil
		used += n
		usedBought += b
	end
	w.inventory[recipeId] = (w.inventory[recipeId] or 0) + qty
	local outBought = math.ceil(qty * usedBought / used)
	if outBought > 0 then
		w.bought[recipeId] = (w.bought[recipeId] or 0) + outBought
	end
	w.stats.crafted[recipeId] = (w.stats.crafted[recipeId] or 0) + qty
	return true, nil
end

-- Upgrades ------------------------------------------------------------------------

-- What the next level of upgradeId costs in world w (nil when maxed).
function Rules.upgradeCost(w: Wallet, upgradeId: string): number?
	return Upgrades.nextCost(upgradeId, w.upgrades[upgradeId], Rules.costScale(w.realm))
end

-- Why w can't buy the next level of upgradeId, or nil if it can.
function Rules.upgradeBlock(w: Wallet, upgradeId: string): string?
	if Upgrades.GLOBAL[upgradeId] and w.realm ~= Realms.MAIN then
		return "Upgrade this back in Market Town"
	end
	if not Upgrades.availableIn(upgradeId, w.realm) then
		return "Not sold in this world"
	end
	local cost = Rules.upgradeCost(w, upgradeId)
	if not cost then
		return "Already at max level"
	end
	if w.cash < cost then
		return `Need {Realms.money(cost - w.cash, w.realm)} more`
	end
	return nil
end

function Rules.upgrade(w: Wallet, upgradeId: unknown): (boolean, string?)
	if type(upgradeId) ~= "string" or not Upgrades.byId[upgradeId] then
		return false, "Unknown upgrade"
	end
	local block = Rules.upgradeBlock(w, upgradeId)
	if block then
		return false, block
	end
	w.cash -= Rules.upgradeCost(w, upgradeId) :: number
	w.upgrades[upgradeId] += 1
	return true, nil
end

-- Selling -------------------------------------------------------------------------

-- Sale income multiplier: rebirths (+25% each) times equipped pets.
function Rules.saleMultiplier(p: Profile): number
	return (1 + REBIRTH_BONUS * p.rebirths) * (1 + Rules.petBonus(p))
end

-- Units of goodId that were made by the player (gathered or crafted), as
-- opposed to bought from the market.
function Rules.ownMade(w: Wallet, goodId: string): number
	return math.max(0, (w.inventory[goodId] or 0) - (w.bought[goodId] or 0))
end

function Rules.recordPurchase(w: Wallet, goodId: string, qty: number)
	w.bought[goodId] = (w.bought[goodId] or 0) + qty
end

-- The bonus (rebirths, pets, 2x Sell boost) on selling qty of goodId from
-- wallet w for value. Bought units are sold first and earn no bonus
-- (otherwise buying and reselling would print money).
function Rules.saleBonus(p: Profile, w: Wallet, goodId: string, qty: number, value: number): number
	local mult = Rules.saleMultiplier(p) * Rules.boostMult(p, "sell")
	if mult <= 1 or qty <= 0 then
		return 0
	end
	local fromBought = math.min(w.bought[goodId] or 0, qty)
	return math.floor(value * (mult - 1) * (qty - fromBought) / qty)
end

-- Records a sale whose base value was already paid into w (inventory already
-- reduced by qty), and pays the bonus on top. Returns the total.
function Rules.recordSale(p: Profile, w: Wallet, goodId: string, qty: number, value: number): number
	local bonus = Rules.saleBonus(p, w, goodId, qty, value)
	local fromBought = math.min(w.bought[goodId] or 0, qty)
	local bLeft = (w.bought[goodId] or 0) - fromBought
	w.bought[goodId] = if bLeft > 0 then bLeft else nil
	w.cash += bonus
	w.stats.sold += qty
	w.stats.earned += value + bonus
	return value + bonus
end

-- Rebirth ("Expand Business"): costs grow each time.
function Rules.rebirthCost(p: Profile): number
	return math.floor(30000 * (p.rebirths + 1) ^ 2 / 500 + 0.5) * 500
end

function Rules.rebirthBlock(p: Profile): string?
	local cost = Rules.rebirthCost(p)
	if p.cash < cost then
		return `Need {Realms.money(cost - p.cash)} more to expand`
	end
	return nil
end

-- Resets the hub's cash, backpack and gear for a permanent sale bonus. Goals,
-- stats, pets, the Helper Bee, the daily streak and other worlds are kept.
function Rules.rebirth(p: Profile): (boolean, string?)
	local block = Rules.rebirthBlock(p)
	if block then
		return false, block
	end
	p.rebirths += 1
	p.cash = START_CASH
	p.inventory = {}
	p.bought = {}
	p.upgrades.gear = 1
	p.upgrades.backpack = 1
	return true, nil
end

-- Daily reward streak. `today` is whole days since the epoch (server time).
-- Returns whether today's reward can be claimed and which streak day it is.
function Rules.dailyStatus(p: Profile, today: number): (boolean, number)
	if p.daily.day >= today then
		return false, p.daily.streak
	end
	local continues = p.daily.day == today - 1
	local nextStreak = if continues then p.daily.streak % #DAILY_REWARDS + 1 else 1
	return true, nextStreak
end

function Rules.claimDaily(p: Profile, today: number): number?
	local can, streak = Rules.dailyStatus(p, today)
	if not can then
		return nil
	end
	local reward = DAILY_REWARDS[streak] * (1 + p.rebirths)
	p.daily = { day = today, streak = streak }
	p.cash += reward
	return reward
end

-- Sells up to `limit` of goodId (a hub good) to the Travelling Merchant at a
-- fixed price (outside the market, so it doesn't move prices). Returns units
-- sold and cash.
function Rules.merchantSell(p: Profile, goodId: string, price: number, limit: number): (number, number)
	-- Only goods you gathered or crafted: reselling market goods at 2x would be free money
	local n = math.min(Rules.ownMade(p, goodId), math.max(0, math.floor(limit)))
	if n <= 0 then
		return 0, 0
	end
	local value = math.floor(n * price)
	local left = p.inventory[goodId] - n
	p.inventory[goodId] = if left > 0 then left else nil
	p.cash += value
	return n, Rules.recordSale(p, p, goodId, n, value)
end

-- Daily quests (hub only) -------------------------------------------------------

-- Hands out a new set of 3 quests when the day changes: gather a raw good you
-- can reach, craft something whose inputs you can reach, and earn from sales.
-- Which good rotates with the day. Rewards and targets grow with rebirths.
function Rules.refreshQuests(p: Profile, today: number)
	if p.quests.day == today then
		return
	end
	local scale = 1 + p.rebirths
	local raws, crafts = {}, {}
	for _, g in Goods do
		if g.realm == Realms.MAIN and g.raw and not g.tier and not g.legendary and Rules.lockReason(p, p, g.gearLevel, g.rebirths) == nil then
			table.insert(raws, g.id)
		end
	end
	for _, r in Recipes do
		local ok = r.realm == Realms.MAIN
		for _, input in r.inputs do
			local g = goodsById[input.id]
			if Rules.lockReason(p, p, g.gearLevel, g.rebirths) then
				ok = false
			end
		end
		if ok then
			table.insert(crafts, r.id)
		end
	end
	local gatherGood = raws[today % #raws + 1]
	-- Sized by value: gather ~$1,000 worth, craft ~$400 worth, earn $2,000
	local list: { Quest } = {
		{ kind = "gathered", good = gatherGood, target = math.max(5, math.floor(200 / goodsById[gatherGood].basePrice + 0.5) * 5), reward = 500 * scale, claimed = false },
	}
	if #crafts > 0 then
		local craftGood = crafts[today % #crafts + 1]
		table.insert(list, { kind = "crafted", good = craftGood, target = math.max(2, math.floor(400 / goodsById[craftGood].basePrice + 0.5)), reward = 600 * scale, claimed = false })
	end
	table.insert(list, { kind = "earned", target = 2000 * scale, reward = 800 * scale, claimed = false })
	p.quests = {
		day = today,
		list = list,
		base = { gathered = table.clone(p.stats.gathered), crafted = table.clone(p.stats.crafted), earned = p.stats.earned },
	}
end

function Rules.questProgress(p: Profile, index: number): number
	local q = p.quests.list[index]
	if not q then
		return 0
	end
	local base = p.quests.base
	local value
	if q.kind == "earned" then
		value = p.stats.earned - base.earned
	elseif q.kind == "gathered" then
		value = (p.stats.gathered[q.good :: string] or 0) - (base.gathered[q.good :: string] or 0)
	else
		value = (p.stats.crafted[q.good :: string] or 0) - (base.crafted[q.good :: string] or 0)
	end
	return math.clamp(value, 0, q.target)
end

function Rules.questText(q: Quest): string
	if q.kind == "earned" then
		return `Earn {Realms.money(q.target)} from sales`
	end
	local g = goodsById[q.good :: string]
	return `{if q.kind == "gathered" then "Gather" else "Craft"} {q.target} {g.icon} {g.name}`
end

-- Claims quest `index` (untrusted input). Returns the reward, or nil and why.
function Rules.claimQuest(p: Profile, index: unknown, today: number): (number?, string?)
	if p.quests.day ~= today then
		return nil, "New quests are ready! Check again"
	end
	if type(index) ~= "number" or not p.quests.list[index] then
		return nil, "Unknown quest"
	end
	local q = p.quests.list[index]
	if q.claimed then
		return nil, "Already claimed"
	end
	if Rules.questProgress(p, index) < q.target then
		return nil, "Not finished yet"
	end
	q.claimed = true
	p.cash += q.reward
	return q.reward, nil
end

-- Collection book ------------------------------------------------------------

Rules.VARIANTS = { "", "Golden", "Rainbow" } -- "" is the plain good
Rules.DISCOVERY_REWARD = { [""] = 50, Golden = 500, Rainbow = 2500 }

function Rules.collectionKey(goodId: string, variant: string?): string
	return if variant and variant ~= "" then `{goodId}:{variant}` else goodId
end

-- Set of every key in the book.
function Rules.collectionKeys(): { [string]: boolean }
	local keys = {}
	for _, g in Goods do
		for _, v in Rules.VARIANTS do
			keys[Rules.collectionKey(g.id, v)] = true
		end
	end
	return keys
end

-- Marks a discovery. Returns the reward if it's new (and pays it, in the
-- good's world's coin), else nil.
function Rules.discover(p: Profile, goodId: string, variant: string?): number?
	local key = Rules.collectionKey(goodId, variant)
	if p.collection[key] or not goodsById[goodId] then
		return nil
	end
	p.collection[key] = true
	local realmId = goodsById[goodId].realm
	local reward = (Rules.DISCOVERY_REWARD[variant or ""] or 0) * Rules.costScale(realmId)
	Rules.wallet(p, realmId).cash += reward
	return reward
end

-- Redeems a promo code from `codes` (code -> cash). Untrusted input.
-- Returns the reward, or nil and why.
function Rules.redeem(p: Profile, input: unknown, codes: { [string]: number }): (number?, string?)
	if type(input) ~= "string" or #input == 0 or #input > 30 then
		return nil, "Enter a code"
	end
	local code = input:upper():gsub("%s", "")
	local reward = codes[code]
	if not reward then
		return nil, "That code doesn't exist (or has expired)"
	end
	if p.codes[code] then
		return nil, "You already used that code"
	end
	p.codes[code] = true
	p.cash += reward
	return reward, nil
end

-- Robux shop ----------------------------------------------------------------

-- How much a boost multiplies its effect right now (1 when it isn't running).
function Rules.boostMult(p: Profile, boostId: string): number
	local boost = Products.BOOSTS[boostId]
	return if boost and (p.boosts[boostId] or 0) > 0 then boost.mult else 1
end

-- Counts boosts down by `seconds` of play. Returns the boosts that ran out.
function Rules.tickBoosts(p: Profile, seconds: number): { string }
	local ended = {}
	for id, left in p.boosts do
		local now = left - seconds
		if now <= 0 then
			p.boosts[id] = nil
			table.insert(ended, id)
		else
			p.boosts[id] = now
		end
	end
	return ended
end

-- Coins a cash pack gives: grows with rebirths so packs stay worth buying.
function Rules.packCash(p: Profile, product: Products.Product): number
	return (product.cash or 0) * (1 + p.rebirths)
end

-- What an Exotic Egg gives once every exotic is owned (so it's never wasted).
Rules.EGG_FALLBACK_CASH = 30000

-- Grants a Robux purchase once. Returns false if purchaseId was already
-- granted, else true plus the hatched pet for eggs. `roll` in [0, 1) picks it.
-- `randomAllowed` is false for players where paid random items aren't
-- allowed (Roblox PolicyService): an egg bought anyway pays coins instead.
function Rules.grantProduct(p: Profile, product: Products.Product, purchaseId: string, roll: number?, randomAllowed: boolean?): (boolean, Pets.Pet?)
	if table.find(p.receipts, purchaseId) then
		return false, nil
	end
	local hatched: Pets.Pet? = nil
	if product.kind == "cash" then
		p.cash += Rules.packCash(p, product)
	elseif product.kind == "egg" then
		hatched = if randomAllowed == false then nil else Pets.rollExotic(p.pets.owned, roll or 0)
		if hatched then
			Rules.addPet(p, hatched.id)
		else
			p.cash += Rules.EGG_FALLBACK_CASH * (1 + p.rebirths)
		end
	elseif product.kind == "boost" and product.boost then
		local id = product.boost
		p.boosts[id] = math.min((p.boosts[id] or 0) + (product.minutes or 0) * 60, Products.MAX_BOOST_SECONDS)
	end
	table.insert(p.receipts, purchaseId)
	while #p.receipts > RECEIPTS_KEPT do
		table.remove(p.receipts, 1)
	end
	return true, hatched
end

-- Pets ------------------------------------------------------------------------

-- Total bonus from equipped pets (0.35 = +35% on sales).
function Rules.petBonus(p: Profile): number
	local total = 0
	for _, id in p.pets.equipped do
		local pet = Pets.byId[id]
		if pet then
			total += pet.bonus
		end
	end
	return total
end

-- Gives a pet and equips it if there's a free slot.
function Rules.addPet(p: Profile, petId: string)
	p.pets.owned[petId] = true
	if #p.pets.equipped < Pets.SLOTS and not table.find(p.pets.equipped, petId) then
		table.insert(p.pets.equipped, petId)
	end
end

-- Why p can't buy petId, or nil.
function Rules.petBlock(p: Profile, petId: string): string?
	local pet = Pets.byId[petId]
	if not pet or pet.exotic or not pet.realm or not pet.cost then
		return "That pet isn't for sale"
	end
	if p.pets.owned[petId] then
		return "You already have this pet"
	end
	local lock = Rules.realmLock(p, pet.realm)
	if lock then
		return lock
	end
	local w = Rules.wallet(p, pet.realm)
	if w.cash < pet.cost then
		return `Need {Realms.money(pet.cost - w.cash, pet.realm)} more`
	end
	return nil
end

-- Buys a pet with its world's coin (untrusted input). Returns true, or false and why.
function Rules.buyPet(p: Profile, petId: unknown): (boolean, string?)
	if type(petId) ~= "string" then
		return false, "Unknown pet"
	end
	local block = Rules.petBlock(p, petId)
	if block then
		return false, block
	end
	local pet = Pets.byId[petId]
	Rules.wallet(p, pet.realm :: string).cash -= pet.cost :: number
	Rules.addPet(p, petId)
	return true, nil
end

-- Equips (on = true) or unequips an owned pet (untrusted input).
-- Returns true, or false and why.
function Rules.equipPet(p: Profile, petId: unknown, on: unknown): (boolean, string?)
	if type(petId) ~= "string" or not p.pets.owned[petId] then
		return false, "You don't have that pet"
	end
	local at = table.find(p.pets.equipped, petId)
	if on == true then
		if at then
			return true, nil
		end
		if #p.pets.equipped >= Pets.SLOTS then
			return false, `You can only equip {Pets.SLOTS} pets. Unequip one first`
		end
		table.insert(p.pets.equipped, petId)
	elseif at then
		table.remove(p.pets.equipped, at)
	end
	return true, nil
end

-- Goals -------------------------------------------------------------------------

-- A world's goal chain.
function Rules.goals(realmId: string): { Goals.Goal }
	return Goals[realmId] or Goals.main
end

-- The active goal in world w and its clamped progress, or nil when every goal is done.
function Rules.currentGoal(w: Wallet): (Goals.Goal?, number)
	local goal = Rules.goals(w.realm)[w.goal]
	if not goal then
		return nil, 0
	end
	return goal, math.min(goal.progress(w), goal.target)
end

-- The tutorial is the run of `tutorial` goals at the start of the hub's chain.
local TUTORIAL_STEPS = 0
while Goals.main[TUTORIAL_STEPS + 1] and Goals.main[TUTORIAL_STEPS + 1].tutorial do
	TUTORIAL_STEPS += 1
end
Rules.TUTORIAL_STEPS = TUTORIAL_STEPS

-- Goal `index` of world realmId as a tutorial step number, or nil if it isn't one.
function Rules.tutorialStep(index: number, realmId: string?): number?
	return if (realmId or Realms.MAIN) == Realms.MAIN and index <= TUTORIAL_STEPS then index else nil
end

-- Completes every finished goal in world w in order, paying rewards. Returns them.
function Rules.advanceGoals(w: Wallet): { Goals.Goal }
	local done = {}
	while true do
		local goal, progress = Rules.currentGoal(w)
		if not goal or progress < goal.target then
			break
		end
		w.cash += goal.reward
		w.goal += 1
		table.insert(done, goal)
	end
	return done
end

return Rules
