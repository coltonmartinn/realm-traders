-- Game rule tests (gather, craft, upgrade, goals, save reconcile).
-- From the repo root:  luau tests/rules.test.luau

local Goals = require("../src/shared/Goals")
local Products = require("../src/shared/Products")
local Rules = require("../src/shared/Rules")
local Upgrades = require("../src/shared/Upgrades")

local failures = 0
local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
		print("FAIL: " .. name)
	end
end

-- Gathering
do
	local p = Rules.newProfile()
	check("gather wood gives 1 at gear 1", Rules.gather(p, p, "wood") == 1 and p.inventory.wood == 1)
	check("gather counts stat", p.stats.gathered.wood == 1)
	local n, why = Rules.gather(p, p, "iron")
	check("iron needs gear 2", n == nil and why ~= nil and p.inventory.iron == nil)
	check("crafted goods can't be gathered", Rules.gather(p, p, "bread") == nil)
	check("unknown good can't be gathered", Rules.gather(p, p, "unobtainium") == nil)

	p.upgrades.gear = 3
	check("gear 3 yields 3", Rules.gather(p, p, "iron") == 3)

	p.inventory = { stone = Rules.capacity(p) - 2 }
	check("gather clamps to space", Rules.gather(p, p, "wood") == 2)
	check("full backpack blocks gather", Rules.gather(p, p, "wood") == nil)
	check("itemCount equals capacity", Rules.itemCount(p) == Rules.capacity(p))
end

-- Crafting
do
	local p = Rules.newProfile()
	p.inventory = { wheat = 7, wood = 5 }
	check("craftable bread = 2", Rules.craftable(p, "bread") == 2)
	check("craft 3 bread fails", not Rules.craft(p, "bread", 3))
	check("failed craft leaves inventory", p.inventory.wheat == 7 and p.inventory.wood == 5)
	check("craft 2 bread", Rules.craft(p, "bread", 2))
	check("inputs consumed", p.inventory.wheat == 1 and p.inventory.wood == 3 and p.inventory.bread == 2)
	check("crafted stat", p.stats.crafted.bread == 2)
	check("bad recipe", not Rules.craft(p, "gold", 1))
	check("bad qty 0", not Rules.craft(p, "bread", 0))
	check("bad qty frac", not Rules.craft(p, "bread", 0.5))
	check("bad qty NaN", not Rules.craft(p, "bread", 0 / 0))
	check("bad qty string", not Rules.craft(p, "bread", "1"))
	check("bad qty too big", not Rules.craft(p, "bread", Rules.MAX_CRAFT + 1))

	p.inventory = { wheat = 3, wood = 1 }
	Rules.craft(p, "bread", 1)
	check("used-up inputs removed, not zero", p.inventory.wheat == nil and p.inventory.wood == nil)
end

-- Upgrades
do
	local p = Rules.newProfile()
	p.cash = 99
	check("can't afford backpack", not Rules.upgrade(p, "backpack") and p.upgrades.backpack == 1 and p.cash == 99)
	p.cash = 100
	check("buy backpack 2", Rules.upgrade(p, "backpack") and p.upgrades.backpack == 2 and p.cash == 0)
	check("capacity grows", Rules.capacity(p) == Upgrades.value("backpack", 2))
	check("bad upgrade id", not Rules.upgrade(p, "jetpack"))
	check("non-string upgrade id", not Rules.upgrade(p, 5))
	p.cash = 1e9
	for _ = 1, 10 do
		Rules.upgrade(p, "gear")
	end
	check("gear stops at max", p.upgrades.gear == Upgrades.maxLevel("gear"))
end

-- Goals
do
	local p = Rules.newProfile()
	check("starts at goal 1", p.goal == 1)
	for _ = 1, 4 do
		Rules.gather(p, p, "wood")
	end
	check("not done at 4 wood", #Rules.advanceGoals(p) == 0 and p.goal == 1)
	Rules.gather(p, p, "wood")
	local cash = p.cash
	local done = Rules.advanceGoals(p)
	check("goal 1 done at 5 wood", #done == 1 and p.goal == 2 and p.cash == cash + Goals.main[1].reward)

	-- Several goals can complete at once (later ones may already be satisfied).
	p.stats.gathered.wheat = 6
	p.stats.crafted.bread = 1
	Rules.recordSale(p, p, "wood", 5, 90)
	p.upgrades.backpack = 2
	done = Rules.advanceGoals(p)
	check("rest of the tutorial completes together", #done == 4 and p.goal == 6)

	-- Tutorial: the leading run of tutorial goals, then regular goals
	check("tutorial has steps", Rules.TUTORIAL_STEPS == 5)
	check("goal 1 is tutorial step 1", Rules.tutorialStep(1) == 1)
	check("goal after the tutorial isn't a step", Rules.tutorialStep(Rules.TUTORIAL_STEPS + 1) == nil)
	for i = 1, Rules.TUTORIAL_STEPS do
		check(`tutorial goal {i} is marked`, Goals.main[i].tutorial == true)
	end

	p.goal = #Goals.main + 1
	check("all done -> no current goal", Rules.currentGoal(p) == nil and #Rules.advanceGoals(p) == 0)
end

-- Robux shop: purchases and boosts
do
	local p = Rules.newProfile()
	local pack = Products.byKey.cash_2
	local cash = p.cash
	check("cash pack grants", Rules.grantProduct(p, pack, "r1") and p.cash == cash + pack.cash)
	check("same receipt never grants twice", not Rules.grantProduct(p, pack, "r1") and p.cash == cash + pack.cash)
	p.rebirths = 2
	check("packs scale with rebirths", Rules.packCash(p, pack) == pack.cash * 3)
	p.rebirths = 0

	-- Gather boost doubles yield
	local base = Rules.gatherYield(p, p)
	Rules.grantProduct(p, Products.byKey.boost_gather, "r2")
	check("gather boost doubles yield", Rules.gatherYield(p, p) == base * 2)
	check("boost lasts 15 minutes", p.boosts.gather == 15 * 60)
	Rules.grantProduct(p, Products.byKey.boost_gather, "r3")
	check("boosts stack time", p.boosts.gather == 30 * 60)
	for i = 1, 20 do
		Rules.grantProduct(p, Products.byKey.boost_gather, "s" .. i)
	end
	check("boost time is capped", p.boosts.gather == Products.MAX_BOOST_SECONDS)
	local ended = Rules.tickBoosts(p, Products.MAX_BOOST_SECONDS)
	check("boost runs out", #ended == 1 and p.boosts.gather == nil and Rules.gatherYield(p, p) == base)

	-- Sell boost: doubles sales of goods you made, but not goods you bought
	Rules.grantProduct(p, Products.byKey.boost_sell, "r4")
	p.inventory.wood = 0
	check("sell boost pays double on own goods", Rules.saleBonus(p, p, "wood", 10, 100) == 100)
	p.bought.wood = 10
	check("sell boost ignores bought goods", Rules.saleBonus(p, p, "wood", 10, 100) == 0)
	p.bought.wood = nil
	p.rebirths = 1
	check("sell boost stacks with rebirth bonus", Rules.saleBonus(p, p, "wood", 10, 100) == 150)

	-- Receipts list stays bounded, and saves round-trip
	check("receipts are capped", #p.receipts <= 50)
	local loaded = Rules.reconcile(p)
	check("boosts survive a save", loaded.boosts.sell == p.boosts.sell)
	check("receipts survive a save", table.find(loaded.receipts, "r4") ~= nil)
	check("bad boost data dropped", next(Rules.reconcile({ boosts = { fake = 10, sell = -5 } }).boosts) == nil)
end

-- Worlds: separate progress, locked by rebirths
do
	local p = Rules.newProfile()
	check("hub wallet is the profile", Rules.wallet(p, "main") == p)
	check("frost locked at 0 rebirths", Rules.realmLock(p, "frost") ~= nil)
	local frost = Rules.wallet(p, "frost")
	check("frost wallet starts fresh", frost.realm == "frost" and frost.cash == 400 and frost.goal == 1 and frost.upgrades.gear == 1)
	check("can't gather in a locked world", Rules.gather(p, frost, "pine") == nil)
	p.rebirths = 2
	check("frost opens at 2 rebirths", Rules.realmLock(p, "frost") == nil and Rules.realmLock(p, "ember") ~= nil)
	check("gather pine into the frost wallet", Rules.gather(p, frost, "pine") == 1 and frost.inventory.pine == 1 and p.inventory.pine == nil)
	check("hub goods can't go in the frost wallet", Rules.gather(p, frost, "wood") == nil and Rules.gather(p, p, "pine") == nil)
	check("fish needs frost gear 2, not hub gear", (function()
		p.upgrades.gear = 5
		return Rules.gather(p, frost, "fish") == nil
	end)())
	check("frost upgrades cost 4x, in frost coins", Rules.upgradeCost(frost, "backpack") == 400 and Rules.upgrade(frost, "backpack") and frost.cash == 0 and p.upgrades.backpack == 1)
	check("helper is bought in the hub only", Rules.upgradeBlock(frost, "helper") ~= nil)
	frost.inventory = { fish = 4, pine = 2 }
	check("frost recipes craft in frost", Rules.craft(frost, "stew", 2) and frost.inventory.stew == 2)
	check("hub recipes don't craft in frost", not Rules.craft(frost, "bread", 1))
	check("frost has its own goals", Rules.currentGoal(frost) ~= nil and (Rules.currentGoal(frost) :: any).where:sub(1, 6) == "frost_")
	local cash = frost.cash
	check("frost discoveries pay frost coins x4", Rules.discover(p, "fish") == 200 and frost.cash == cash + 200)
	local hubCash = p.cash
	Rules.rebirth((function()
		p.cash = Rules.rebirthCost(p)
		return p
	end)())
	check("rebirth leaves other worlds alone", frost.inventory.stew == 2 and frost.upgrades.backpack == 2 and hubCash >= 0)
	local loaded = Rules.reconcile(p)
	check("world progress survives a save", loaded.realms.frost.inventory.stew == 2 and loaded.realms.frost.upgrades.backpack == 2)
	check("bad world data is cleaned", Rules.reconcile({ realms = { frost = { inventory = { wood = 5, fish = 3 } }, mars = {} } }).realms.frost.inventory.wood == nil)
	check("unknown worlds dropped", Rules.reconcile({ realms = { mars = {} } }).realms.mars == nil)
end

-- Pets
do
	local Pets = require("../src/shared/Pets")
	local p = Rules.newProfile()
	check("no pets, no bonus", Rules.petBonus(p) == 0 and Rules.saleMultiplier(p) == 1)
	check("can't afford a puppy", not Rules.buyPet(p, "puppy"))
	p.cash = 1500
	check("buy a puppy with hub cash", Rules.buyPet(p, "puppy") and p.cash == 0 and p.pets.owned.puppy)
	check("bought pets are equipped", p.pets.equipped[1] == "puppy" and math.abs(Rules.saleMultiplier(p) - 1.1) < 1e-9)
	check("can't buy twice", not Rules.buyPet(p, "puppy"))
	check("exotics aren't for sale", not Rules.buyPet(p, "unicorn"))
	check("frost pets need frost unlocked", (function()
		Rules.wallet(p, "frost").cash = 1e9
		return not Rules.buyPet(p, "penguin")
	end)())
	p.rebirths = 2
	check("frost pets cost frost coins", Rules.buyPet(p, "penguin") and Rules.wallet(p, "frost").cash == 1e9 - 30000)
	check("later worlds' pets are stronger", Pets.byId.penguin.bonus > Pets.byId.fox.bonus and Pets.byId.salamander.bonus > Pets.byId.reindeer.bonus)
	check("pets stack with rebirths", math.abs(Rules.saleMultiplier(p) - 1.5 * 1.85) < 1e-9)
	p.pets.owned.kitten, p.pets.owned.bunny = true, true
	check("equip up to 3", Rules.equipPet(p, "kitten", true) and not Rules.equipPet(p, "bunny", true) and #p.pets.equipped == 3)
	check("unequip frees a slot", Rules.equipPet(p, "puppy", false) and Rules.equipPet(p, "bunny", true))
	check("can't equip unowned", not Rules.equipPet(p, "dragon", true))
	check("pet bonus pays on own goods only", (function()
		local q = Rules.newProfile()
		q.pets.owned.puppy, q.pets.equipped = true, { "puppy" }
		q.bought.wood = 10
		return Rules.saleBonus(q, q, "wood", 10, 100) == 0 and Rules.saleBonus(q, q, "wood", 5, 100) == 0
	end)())
	check("pets kept on rebirth", (function()
		p.cash = Rules.rebirthCost(p)
		Rules.rebirth(p)
		return p.pets.owned.puppy and #p.pets.equipped == 3
	end)())
	local loaded = Rules.reconcile(p)
	check("pets survive a save", loaded.pets.owned.penguin and #loaded.pets.equipped == 3)
	check("junk pets dropped", (function()
		local q = Rules.reconcile({ pets = { owned = { puppy = true, gryphon = true }, equipped = { "puppy", "gryphon", "kitten" } } })
		return q.pets.owned.gryphon == nil and #q.pets.equipped == 1
	end)())

	-- Exotic Egg (Robux)
	local egg = Products.byKey.egg_exotic
	local q = Rules.newProfile()
	local odds = Pets.exoticOdds(q.pets.owned)
	local sum = 0
	for _, o in odds do
		sum += o.chance
	end
	check("egg odds add up to 100%", math.abs(sum - 1) < 1e-9 and #odds == 4)
	local ok, pet = Rules.grantProduct(q, egg, "e1", 0)
	check("egg hatches an exotic", ok and pet ~= nil and (pet :: any).exotic and q.pets.owned[(pet :: any).id])
	check("exotics beat every world pet", (function()
		for _, pt in Pets.list do
			if not pt.exotic and pt.bonus >= 6 then
				return false
			end
		end
		return true
	end)())
	for i = 2, 4 do
		Rules.grantProduct(q, egg, "e" .. i, 0.99)
	end
	check("no duplicates: 4 eggs give all 4 exotics", q.pets.owned.unicorn and q.pets.owned.shark and q.pets.owned.kraken and q.pets.owned.lion)
	local cash = q.cash
	local _, none = Rules.grantProduct(q, egg, "e5", 0.5)
	check("egg after owning all gives cash instead", none == nil and q.cash == cash + Rules.EGG_FALLBACK_CASH)
end

-- Travelling Merchant
do
	local p = Rules.newProfile()
	p.inventory = { bread = 10 }
	local n, value = Rules.merchantSell(p, "bread", 240, 25)
	check("merchant buys all you have under the limit", n == 10 and value == 2400 and p.inventory.bread == nil)
	check("merchant pays cash and counts the sale", p.cash == Rules.START_CASH + 2400 and p.stats.sold == 10 and p.stats.earned == 2400)
	p.inventory = { bread = 10 }
	n = Rules.merchantSell(p, "bread", 240, 4)
	check("merchant respects the limit", n == 4 and p.inventory.bread == 6)
	check("nothing to sell", Rules.merchantSell(p, "tools", 600, 25) == 0)
	check("limit used up", Rules.merchantSell(p, "bread", 240, 0) == 0 and p.inventory.bread == 6)
end

-- Rebirth and sale bonus
do
	local p = Rules.newProfile()
	check("no bonus before rebirth", Rules.saleMultiplier(p) == 1 and Rules.recordSale(p, p, "wood", 1, 100) == 100 and p.cash == Rules.START_CASH)
	local cost = Rules.rebirthCost(p)
	check("first rebirth costs 30000", cost == 30000)
	p.cash = cost - 1
	check("can't rebirth short of cash", not Rules.rebirth(p) and p.rebirths == 0)
	p.cash = cost + 777
	p.inventory = { wood = 10 }
	p.upgrades.gear, p.upgrades.backpack = 4, 3
	p.goal = 7
	check("rebirth succeeds", Rules.rebirth(p))
	check("rebirth resets cash, bag and upgrades", p.cash == Rules.START_CASH and next(p.inventory) == nil and p.upgrades.gear == 1 and p.upgrades.backpack == 1)
	check("rebirth keeps goals", p.goal == 7 and p.rebirths == 1)
	check("rebirth keeps the helper bee", (function()
		local q = Rules.newProfile()
		q.upgrades.helper = 3
		q.cash = Rules.rebirthCost(q)
		Rules.rebirth(q)
		return q.upgrades.helper == 3 and q.upgrades.gear == 1
	end)())
	check("rebirth gives +25% sales", Rules.saleMultiplier(p) == 1.25)
	local cash = p.cash
	check("sale bonus is paid", Rules.recordSale(p, p, "wood", 2, 100) == 125 and p.cash == cash + 25 and p.stats.earned >= 125)
	check("second rebirth costs more", Rules.rebirthCost(p) > cost)

	-- merchant sales get the bonus too
	p.inventory = { bread = 2 }
	local _, paid = Rules.merchantSell(p, "bread", 100, 25)
	check("merchant sale includes bonus", paid == 250)
end

-- No free money from the rebirth bonus or the merchant
do
	local p = Rules.newProfile()
	p.rebirths = 2 -- +50%
	-- 10 wood: 4 bought, 6 gathered
	p.inventory = { wood = 10 }
	Rules.recordPurchase(p, "wood", 4)
	check("ownMade excludes bought", Rules.ownMade(p, "wood") == 6)
	check("bonus only on the gathered share", Rules.saleBonus(p, p, "wood", 10, 200) == 60)
	check("selling bought units first: none of 4 get a bonus", Rules.saleBonus(p, p, "wood", 4, 80) == 0)
	p.inventory.wood = 6 -- the market took 4
	check("recordSale of the bought 4 pays no bonus", Rules.recordSale(p, p, "wood", 4, 80) == 80 and p.bought.wood == nil)
	check("rest earns the bonus", Rules.saleBonus(p, p, "wood", 6, 120) == 60)

	-- Merchant won't take market goods
	p.inventory = { tools = 5 }
	p.bought = { tools = 5 }
	check("merchant refuses bought goods", Rules.merchantSell(p, "tools", 600, 25) == 0 and p.inventory.tools == 5)
	p.inventory.tools = 8 -- 3 crafted
	local n = Rules.merchantSell(p, "tools", 600, 25)
	check("merchant takes only the crafted ones", n == 3 and p.inventory.tools == 5)

	-- Crafting with bought inputs makes bought output
	p.inventory = { wheat = 6, wood = 2 }
	p.bought = { wheat = 6, wood = 2 }
	Rules.craft(p, "bread", 2)
	check("bread from bought inputs counts as bought", p.bought.bread == 2 and Rules.ownMade(p, "bread") == 0)
	p.inventory = { wheat = 6, wood = 2 }
	p.bought = { wheat = 3 }
	Rules.craft(p, "bread", 2)
	check("3 of 8 inputs bought -> 1 of 2 bread is bought (rounded up)", p.bought.bread == 1 and Rules.ownMade(p, "bread") == 1)
	check("rebirth clears bought", (function()
		p.cash = 1e9
		Rules.rebirth(p)
		return next(p.bought) == nil
	end)())
end

-- Daily rewards
do
	local p = Rules.newProfile()
	local day = 20000
	local can, streak = Rules.dailyStatus(p, day)
	check("first day claimable as day 1", can and streak == 1)
	check("claim day 1", Rules.claimDaily(p, day) == Rules.DAILY_REWARDS[1] and p.cash == Rules.START_CASH + Rules.DAILY_REWARDS[1])
	check("can't claim twice", Rules.claimDaily(p, day) == nil)
	check("next day is day 2", Rules.claimDaily(p, day + 1) == Rules.DAILY_REWARDS[2] and p.daily.streak == 2)
	check("missing a day resets", select(2, Rules.dailyStatus(p, day + 3)) == 1)
	p.daily = { day = day + 10, streak = 7 }
	check("streak wraps after day 7", select(2, Rules.dailyStatus(p, day + 11)) == 1)
	p.rebirths = 2
	p.daily = { day = day + 20, streak = 6 }
	check("day 7 reward scales with rebirths", Rules.claimDaily(p, day + 21) == Rules.DAILY_REWARDS[7] * 3)
	check("reconcile keeps daily + rebirths", Rules.reconcile(p).daily.streak == 7 and Rules.reconcile(p).rebirths == 2)
end

-- Helper bee
do
	local p = Rules.newProfile()
	check("no helper at start", Rules.helperRate(p) == 0 and p.upgrades.helper == 1)
	p.cash = 2500
	check("buy helper", Rules.upgrade(p, "helper") and Rules.helperRate(p) == 10)
	check("old saves get a helper level", Rules.reconcile({ upgrades = { gear = 2 } }).upgrades.helper == 1)
end

-- Lucky finds
do
	check("rainbow is the rarest slice", Rules.rollLucky(0) ~= nil and (Rules.rollLucky(0) :: any).name == "Rainbow")
	check("golden next", (Rules.rollLucky(0.005) :: any).name == "Golden")
	check("most rolls are nothing", Rules.rollLucky(0.5) == nil and Rules.rollLucky(0.0111) == nil)
	local p = Rules.newProfile()
	local cash = p.cash
	check("golden pays 10x value per unit", Rules.payLucky(p, Rules.LUCKY[2], "wood", 2) == 200 and p.cash == cash + 200)
	-- expected bonus stays modest (~15% of gather value)
	local ev = 0
	for _, l in Rules.LUCKY do
		ev += l.chance * l.mult
	end
	check("lucky finds add ~15% on average", ev > 0.1 and ev < 0.2)
end

-- Daily quests
do
	local p = Rules.newProfile()
	Rules.refreshQuests(p, 100)
	check("3 quests on a fresh profile", #p.quests.list == 3)
	check("gather quest uses an unlocked good", ({ wood = true, wheat = true, stone = true })[p.quests.list[1].good :: string] == true)
	check("craft quest is bread (only unlocked recipe)", p.quests.list[2].good == "bread")
	local q1 = p.quests.list[1]
	check("no progress at start", Rules.questProgress(p, 1) == 0)
	check("can't claim unfinished", Rules.claimQuest(p, 1, 100) == nil)
	p.stats.gathered[q1.good :: string] = (p.stats.gathered[q1.good :: string] or 0) + q1.target + 10
	check("progress clamps at target", Rules.questProgress(p, 1) == q1.target)
	local cash = p.cash
	check("claim pays", Rules.claimQuest(p, 1, 100) == q1.reward and p.cash == cash + q1.reward)
	check("claim once", Rules.claimQuest(p, 1, 100) == nil)
	check("bad index", Rules.claimQuest(p, 9, 100) == nil and Rules.claimQuest(p, "1", 100) == nil)
	check("old day can't be claimed", Rules.claimQuest(p, 2, 101) == nil)
	Rules.refreshQuests(p, 100)
	check("same day keeps quests", p.quests.list[1].claimed)
	Rules.refreshQuests(p, 101)
	check("new day, new quests, progress from now", not p.quests.list[1].claimed and Rules.questProgress(p, 1) == 0)
	check("quest text", Rules.questText(p.quests.list[3]):find("Earn") ~= nil)
	check("reconcile keeps quests", Rules.reconcile(p).quests.day == 101 and #Rules.reconcile(p).quests.list == 3)
end

-- Collection
do
	local p = Rules.newProfile()
	local total = 0
	for _ in Rules.collectionKeys() do
		total += 1
	end
	check("3 entries per good", total == 3 * #require("../src/shared/Goods"))
	local cash = p.cash
	check("first wood pays 50", Rules.discover(p, "wood") == 50 and p.cash == cash + 50)
	check("only once", Rules.discover(p, "wood") == nil)
	check("golden wood is separate", Rules.discover(p, "wood", "Golden") == 500)
	check("unknown good ignored", Rules.discover(p, "unobtainium") == nil)
	check("reconcile keeps entries, drops junk", (function()
		local q = Rules.reconcile({ collection = { wood = true, ["wood:Golden"] = true, ["junk"] = true } })
		return q.collection.wood == true and q.collection["wood:Golden"] == true and q.collection.junk == nil
	end)())
end

-- Promo codes
do
	local codes = { RELEASE = 500 }
	local p = Rules.newProfile()
	check("bad input", Rules.redeem(p, 42, codes) == nil and Rules.redeem(p, "", codes) == nil and Rules.redeem(p, string.rep("A", 40), codes) == nil)
	check("unknown code", Rules.redeem(p, "NOPE", codes) == nil)
	check("redeem is case/space-insensitive", Rules.redeem(p, " release ", codes) == 500 and p.cash == Rules.START_CASH + 500)
	check("only once", Rules.redeem(p, "RELEASE", codes) == nil and p.cash == Rules.START_CASH + 500)
	check("reconcile keeps used codes", Rules.reconcile(p).codes.RELEASE == true)
end

-- Reconcile (loading saves)
do
	local p = Rules.reconcile(nil)
	check("nil save -> new profile", p.cash == Rules.START_CASH and p.goal == 1)

	p = Rules.reconcile({
		cash = 250.7,
		inventory = { wood = 4, unobtainium = 9, stone = -3, iron = 0 / 0 },
		upgrades = { gear = 99, backpack = 2, jetpack = 3 },
		stats = { gathered = { wood = 10 }, sold = "lots", earned = 40 },
		goal = 3,
	})
	check("cash floored", p.cash == 250)
	check("unknown and bad goods dropped", p.inventory.wood == 4 and p.inventory.unobtainium == nil and p.inventory.stone == nil and p.inventory.iron == nil)
	check("upgrade level clamped", p.upgrades.gear == Upgrades.maxLevel("gear") and p.upgrades.backpack == 2)
	check("unknown upgrade dropped", (p.upgrades :: any).jetpack == nil)
	check("stats kept / bad stats zeroed", p.stats.gathered.wood == 10 and p.stats.sold == 0 and p.stats.earned == 40)
	check("goal kept", p.goal == 3)
	check("goal clamped", Rules.reconcile({ goal = 500 }).goal == #Goals.main + 1)
	check("garbage save", Rules.reconcile("garbage").cash == Rules.START_CASH)
end

-- Exotic Egg where paid random items aren't allowed: coins, never a pet
do
	local p = Rules.newProfile()
	local cash = p.cash
	local ok, hatched = Rules.grantProduct(p, Products.byKey.egg_exotic, "egg-r1", 0.5, false)
	check("restricted egg grants coins", ok and hatched == nil and next(p.pets.owned) == nil and p.cash == cash + Rules.EGG_FALLBACK_CASH)
	local ok2, hatched2 = Rules.grantProduct(p, Products.byKey.egg_exotic, "egg-r2", 0.5, true)
	check("allowed egg hatches a pet", ok2 and hatched2 ~= nil)
end

-- Deep Mine: depth by gear (hub) or protective gear (portal worlds), random ores
do
	local p = Rules.newProfile()
	check("everyone can mine level 1", Rules.depthBlock(p, 1) == nil and Rules.mineDepth(p) == 1)
	check("level 2 needs gear 2", Rules.depthBlock(p, 2) ~= nil)
	check("no level 6", Rules.depthBlock(p, 6) ~= nil and Rules.depthBlock(p, 0) ~= nil)
	check("ores can't be gathered, only mined", Rules.gather(p, p, "copper") == nil)
	check("mine level 1: one ore per swing", Rules.mine(p, p, 1, "gold") == 1 and p.inventory.gold == 1)
	check("can't mine level 2 at gear 1", Rules.mine(p, p, 2, "copper") == nil)
	check("other worlds' ores aren't found here", Rules.mine(p, p, 1, "pearl") == nil)
	p.upgrades.gear = 4
	check("gear 4 reaches level 4", Rules.mineDepth(p) == 4 and Rules.depthBlock(p, 4) == nil and Rules.depthBlock(p, 5) ~= nil)
	check("legendary can't be mined directly", Rules.mine(p, p, 1, "starstone") == nil and Rules.gather(p, p, "starstone") == nil)
	check("legendary found by luck", Rules.findLegendary(p) and p.inventory.starstone == 1)
	check("deeper is luckier", Rules.legendaryChance(5) > Rules.legendaryChance(1))

	-- Odds: every level has every ore, sums to 100%, rarer ores more common deeper
	local ok, rising = true, true
	for depth = 1, Rules.MINE_DEPTHS do
		local sum = 0
		local odds = Rules.oreOdds("main", depth)
		for _, o in odds do
			sum += o.chance
		end
		ok = ok and #odds == 5 and math.abs(sum - 1) < 1e-9
		if depth > 1 then
			rising = rising and Rules.oreValue("main", depth) > Rules.oreValue("main", depth - 1) and odds[5].chance > Rules.oreOdds("main", depth - 1)[5].chance
		end
	end
	check("every level can give all five ores", ok)
	check("deeper levels give better ores", rising)
	check("roll 0 is the commonest ore, roll ~1 the rarest", Rules.rollOre("main", 3, 0).id == "copper" and Rules.rollOre("main", 3, 0.9999).id == "sapphire")
	local seen: { [string]: boolean } = {}
	for i = 0, 999 do
		seen[Rules.rollOre("ember", 5, i / 1000).id] = true
	end
	check("level 5 still has variety", seen.obsidian and seen.dragonheart and seen.garnet)

	local frost = Rules.wallet(p, "frost")
	check("gear doesn't help in Frostpeak's mine", frost.upgrades.gear == 1 and Rules.depthBlock(frost, 2) ~= nil)
	check("thermal gear sold in Frostpeak only", Rules.upgradeBlock(p, "thermal") ~= nil and Rules.upgradeBlock(Rules.wallet(p, "ember"), "thermal") ~= nil)
	frost.cash = 1e9
	check("thermal gear upgrade", Rules.upgrade(frost, "thermal") and Rules.mineDepth(frost) == 2)
	check("fireproof armor sets ember depth", Rules.wallet(p, "ember").upgrades.fireproof == 1 and Rules.mineDepth(Rules.wallet(p, "ember")) == 1)
	check("every world has five ores and a legendary", Rules.oreAt("frost", 5) ~= nil and Rules.oreAt("ember", 5) ~= nil and Rules.legendaryOf("frost") ~= nil and Rules.legendaryOf("ember") ~= nil)
end

if failures > 0 then
	error(`{failures} rule test(s) failed`)
end
print("All rule tests passed")
