# Realm Traders

A Roblox trading simulator. Players gather and craft goods, sell them to a shared
server-wide market where prices come from supply and demand, rebirth for permanent
bonuses, and travel through portals to new worlds with their own economies.

See [docs/DESIGN.md](docs/DESIGN.md) for why the game is built this way (research and sources).

## Features

- **Trading economy**: a live market per server; prices move with supply, and events
  push one good up or down. Buying and reselling can't print money.
- **Gather, craft, upgrade**: themed gathering zones (a barn at the Farm, a mine entrance
  at the Mine...), recipes at the Workshop, gear and backpack upgrades at the Outfitter.
- **Beginner tutorial**: five guided steps (chop, harvest, bake, sell, upgrade) with an
  arrow pointing the way, then a goal chain.
- **Rebirths** (Expand Business): +25% on sales of goods you made, per rebirth.
- **Portal worlds**: Frostpeak ❄️ (2 rebirths) and Emberfall 🔥 (5 rebirths). Each has its
  own coin, goods, recipes, upgrades, goals, shops and look.
- **Pets**: bought with each world's coin, they raise sale prices (later worlds' pets are
  stronger). Equip 3; they follow you around.
- **Robux shop** (B): coin packs, an Exotic Egg with the best pets (shown odds, no
  duplicates) and 15-minute boosts (2× Sell, 2× Gather, 3× Luck).
- **Daily rewards, daily quests, codes, session gifts, lucky Golden/Rainbow finds,
  a collection book, a Travelling Merchant and a Top Traders board.**
- **A world with no visible edge**: past the walls, each direction shows more of what's in
  front of it (fields behind the Farm, quarry terraces behind the Quarry, a town behind
  the shops...), then hills and a ring of mountains.
- Cartoony UI with the Luckiest Guy font.

## Progress

| Step | What was built |
|---|---|
| 1 | Price model and offline economy simulation |
| 2 | Trade remotes with server-side validation |
| 3 | Gathering, crafting, upgrades, rebirths, goals, saving with session locks |
| 4 | Cartoony HUD and panels, guide arrow, fast travel, notifications |
| 5 | Retention: daily rewards, quests, codes, gifts, lucky finds, collection, merchant, leaderboard |
| 6 | Beginner tutorial, shopkeeper outfits, Robux shop |
| 7 | Portal worlds (Frostpeak, Emberfall), pets, Exotic Egg |
| 8 | Themed zone scenery, layout so nothing overlaps, backdrops past the walls |
| 9 | Terrain ground (no texture flicker), brighter palette |

## Before publishing

- Create the Developer Products (4 coin packs, the Exotic Egg, 3 boosts) on the Creator
  Dashboard and put their IDs in `src/shared/Products.luau` (they're all `0` now).
- Optional: tick **Decoration** on Workspace.Terrain in Studio for swaying grass.

## Setup

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in the repo root.
   This installs the pinned tools from `rokit.toml` (rojo, selene, luau).
2. Install the Rojo plugin in Studio (`rojo plugin install`).
3. Run `rojo serve`, open a baseplate in Studio, and click Connect in the Rojo plugin.
4. To publish or test without live sync: `rojo build -o RealmTraders.rbxl`.

## Gameplay loop

1. **Gather** raw goods by holding E at nodes: wood (Forest), wheat (Farm),
   stone (Quarry), iron (Mine, Gear 2), gems (Crystal Cave, Rebirth 1 + Gear 3).
   Nodes run out and regrow.
2. **Sell** at the Market (M), or **buy** what you need. Prices move with supply,
   and market **events** push one good's price up or down for two minutes.
3. **Craft** at the Workshop (C): Bread = 3 wheat + 1 wood, Tools = 2 iron + 1 stone + 1 wood,
   Jewelry = 2 gems + 1 iron. Crafting your own gathered goods adds roughly 10-25%;
   buying every input and crafting barely breaks even (`sim/craft_arbitrage.luau`).
4. **Upgrade** at the Outfitter (U): Gear gives more per gather and opens zones,
   Backpack carries more.
5. **Expand Business** (rebirth) at the Outfitter: reset cash, backpack and gear for a
   permanent +25% on sales of goods you made (goals and the Helper Bee are kept).
   The first one unlocks the Crystal Cave.
6. A chain of 13 **goals** (top left) teaches each step; a gold line and arrow point to
   where to go next.

Around the loop:

- **Travelling Merchant** visits the plaza every 5-7 minutes for 2.5 minutes and pays
  2x base price for one good (25 per player, only goods you gathered or crafted).
- **Daily rewards**: a 7-day streak calendar (day 7 is big), scaled by rebirths.
- **Codes**: redeem promo codes from the Rewards panel. Edit `src/server/Codes.luau`.
- **Top Traders** board in the plaza: all-time earnings (global when DataStores work).
- **Helper Bee** (Outfitter upgrade): a pet that follows you and gathers on its own while
  you stand in a zone, 10-30 gathers a minute.
- **Session gifts** at 3 / 10 / 20 / 40 minutes of play (HUD 🎁 button).
- **Lucky finds**: any gather has a 1% chance of a ✨ Golden find (10x value, paid in cash)
  and 0.1% of a 🌈 Rainbow (50x), modeled on Grow a Garden's mutations. About +15% income
  on average.
- **Daily quests** (Q): gather ~$1,000 of a raw good, craft ~$400 of a product, and earn
  $2,000; new ones each day, scaled by rebirths.
- **Collection** (📖): every good in plain, Golden and Rainbow form (24 entries). Each first
  discovery pays $50 / $500 / $2,500, which gives lucky finds a lasting goal.
- **Invite Friends** and **Favorite Game** buttons (Quests panel).
- Big sales, rebirths and Rainbow finds are announced to the server in chat.

Rules that keep it fair: market goods you **bought** never earn the rebirth bonus and the
merchant won't take them, so buying and reselling can't print money. Progression pace is
checked by `sim/progression.luau` (first rebirth ~47 min of optimal play).

Progress saves to DataStore `MarketSim_v1` (the game's working title; keep the name so saves carry over), under a session lock (`src/server/SessionLock.luau`):
a server only loads a profile it can lock and only writes while it holds the lock, so hopping
servers can't lose progress. In Studio, saving needs
Game Settings > Security > Enable Studio Access to API Services; without it the
game still runs and warns that the session won't be saved.

### Studio testing helpers

Set these attributes on `ServerScriptService.Server` (they do nothing outside Studio):
`FastEvents = true` starts events/merchant visits seconds apart; `DevGrant = 5000`
gives every player that much cash once; `ForceLucky = "Golden"` (or `"Rainbow"`) makes
the next gather a lucky find; `TestPurchase = "boost_sell"` (any product key in
`Products.luau`) grants that product to every player as if bought. On the client, setting the local player's `DebugPanel`
attribute to `market` / `craft` / `upgrades` / `daily` / `quests` / `collection` opens that panel.

## Checks you can run without Studio

```sh
selene src sim tests            # lint
luau sim/run.luau               # economy simulation (stability, oscillation, free-money loops)
luau tests/market.test.luau     # trade validation tests
luau tests/rules.test.luau      # gather / craft / upgrade / goals / rebirth / daily / codes / saves
luau tests/lock.test.luau       # save session locking (no overwrites when hopping servers)
luau sim/progression.luau       # minutes to each goal and rebirth for a good player
luau sim/craft_arbitrage.luau   # profit from buy-inputs -> craft -> sell (should be thin)
```

## Layout

| Path | Syncs to | What |
|---|---|---|
| `src/shared` | ReplicatedStorage.Shared | Goods, recipes, upgrades, goals, realms, pets, products, places, and `Rules` (pure game rules used by both sides) |
| `src/server` | ServerScriptService.Server | Market state, price model, NPC traders, player data/saving, world builder (`World`, `Scenery`, `Backdrop`, `Layout`) |
| `src/client` | StarterPlayerScripts.Client | HUD, Market / Workshop / Outfitter / Shop / Pets panels, guide, notifications |
| (project file) | ReplicatedStorage.Shared.PriceModel | Same `PriceModel` file, so the client shows exact trade totals |
| (project file) | ReplicatedStorage.Remotes | Requests: `TradeRequest`, `SellAllRequest`, `CraftRequest`, `UpgradeRequest`, `RebirthRequest`, `DailyRequest`, `CodeRequest`, `GiftRequest`, `QuestRequest`, `PetRequest`. Updates: `MarketUpdate`, `PlayerUpdate`, `Notify`, `News` |
| `sim/`, `tests/` | (not synced) | Offline simulation and tests |

The map is built in code at server start (`src/server/World.luau`), so the place file needs nothing in it.
Modules with no Roblox APIs (`PriceModel`, `MarketState`, `Npc`, everything in `src/shared`)
load each other with string requires (`require("./Rules")`), so they also run in the `luau` CLI.

## Networking

Nothing the client sends is trusted; every request is validated on the server and rate limited.

- `TradeRequest:FireServer(goodId, "buy" | "sell", qty)`: checks good, side, qty (whole, 1-100),
  cash, owned amount, market stock and backpack space.
- `CraftRequest:FireServer(recipeId, qty)`: qty 1-20, needs the inputs.
- `UpgradeRequest:FireServer(upgradeId)`: needs the cash for the next level.
- Gathering uses ProximityPrompts handled on the server (distance and cooldown checked).
- Server -> all clients, every second: `MarketUpdate` with `{ [goodId]: { price, stock, ask, bid } }`.
- Server -> one client: `PlayerUpdate` with the whole profile after any change, and
  `Notify` with `{ kind = "ok" | "error" | "warn" | "gain" | "goal", text, good?, amount? }` for feedback.

## Price model

`src/server/PriceModel.luau` holds the whole formula, as pure functions:

```
spot = basePrice * (targetStock / max(stock, 1)) ^ elasticity    -- clamped to [floor, ceiling] x basePrice
```

- The displayed price eases toward spot each tick (`smoothing`).
- Stock drifts toward `targetStock` each tick (`drift`), so prices return to base.
- Trades are priced unit by unit, at the **worse** of the displayed and spot
  price, plus a `spread`. Buys round up and sells round down. This keeps a lagging
  displayed price from being farmed (the simulation shows the naive version is exploitable).
