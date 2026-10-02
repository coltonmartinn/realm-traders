# Realm Traders: design notes

Why the game works the way it does: what we took from successful Roblox games and
Roblox's own design guidance, and where each idea lives in the code.

## The core loop

Gather → sell or craft → upgrade → gather faster. Every step is visible on screen
and pointed at by the goal card and guide arrow.

| Step | Where |
|---|---|
| Gather by holding E at nodes (zones gated by Gear and Rebirth) | `src/server/World.luau`, `Rules.gather` |
| Sell / buy on a supply-and-demand market | `src/server/MarketState.luau`, `PriceModel.luau` |
| Craft products worth more than their parts | `src/shared/Recipes.luau`, `Rules.craft` |
| Upgrade gear, backpack, Helper Bee; rebirth for a sale bonus | `src/shared/Upgrades.luau`, `Rules.rebirth` |

## What we borrowed, and why

**Compact hub with fast travel** (Grow a Garden). All shops sit in a row in front of
spawn; zones are a short walk away and one click via the top bar. Grow a Garden's
"Sell / Garden / Seeds" buttons at the top of the screen are its most-used UI.
→ `Places.luau`, `Travel.luau`, HUD travel bar.

**Show, don't tell** (Roblox onboarding guide). Arrows and trails beat text, and
they don't need translating. A gold line and bouncing arrow point at the current
goal's target (the nearest node inside a zone), and the fast-travel button for a
far-away goal pulses. → `Guide.luau`, `Hud.luau`.

**First minute matters** (retention guides: core action within 10-30 seconds, first
reward within 60). A five-step tutorial opens the goal chain: chop wood, harvest
wheat, bake bread, sell, upgrade the backpack. Each step is one action with a small
reward; the goal card reads "TUTORIAL 2/5", the arrow points at the place, and a
bobbing 👈 points at the button to press once it will work. New players get a
welcome banner. → `Goals.luau` (`tutorial`, `ui`), `Hud.luau`.

**Timed reasons to act** (Grow a Garden's weather and Travelling Merchant). Market
events push one good's price up or down for 2 minutes; a merchant visits the plaza
for 2.5 minutes paying 2x. Both show countdown banners.
→ `Events.luau`, `Happenings.luau`, `NewsBar.luau`.

**Random rare drops** (Grow a Garden's Gold 1% / 20x and Rainbow 0.1% / 50x
mutations). Any gather can be a ✨ Golden (1%, 10x) or 🌈 Rainbow (0.1%, 50x)
find, with a banner and a server-wide announcement for Rainbows. About +15% income
on average, so it's exciting without breaking balance. → `Rules.rollLucky`.

**Collection** (Pet Simulator's Index, Fisch's Bestiary). 24 entries (8 goods x
plain/Golden/Rainbow) with a reward for each first discovery. Gives rare finds a
lasting purpose. → `Rules.discover`, `CollectionPanel.luau`.

**Daily streak + daily quests** (retention guides: "the simplest effective retention
tool"; day-7 reward visible from day 1). 7-day calendar; three quests a day sized by
value. → `DailyPanel.luau`, `QuestPanel.luau`, `Rules.claimDaily`, `Rules.refreshQuests`.

**Rebirth** (nearly every simulator). Reset cash, backpack and gear for a permanent
+25% sale bonus; the first unlocks the Crystal Cave, which is the "new content around
the 2-3 hour mark" retention guides recommend for beating the day-3 drop.

**Pets that work for you** (Pet Simulator, Bee Swarm). The Helper Bee follows you and
gathers on its own; it survives rebirths. → `Helpers.luau`, helper loop in `Main.server.luau`.

**Session rewards and codes**. Gifts at 3/10/20/40 minutes; promo codes for update
notes and socials. → `Rules.GIFTS`, `src/server/Codes.luau`.

**Social proof and friends** (players with friends retain 3-5x better). Top Traders
board, chat announcements for big sales/rebirths/Rainbows, Invite and Favorite buttons.

**Chunky cartoon UI** (top simulators, DevForum UI guides). FredokaOne, thick ink
outlines, gradient buttons with a pressable lip, red notification badges, sounds on
every action. Never a dead click: disabled buttons say why. → `Theme.luau`, `Ui.luau`.

**Portal worlds** (Pet Simulator's worlds). ❄️ Frostpeak opens at 2 rebirths and
🔥 Emberfall at 5. Walk through a portal by the hub's shop street. Each world has its
own goods, recipes, market, coin, gear, backpack and goal chain, saved separately
(`profile.realms`), so it's a fresh climb with bigger numbers. The HUD, travel bar,
panels and lighting switch to whichever world you stand in.
→ `Realms.luau`, `Places.luau`, `Rules.wallet`, `World.luau`.

**Pets** (the core of Pet Simulator and Bee Swarm). Each world's pet shop sells
pets for its own coin, and later worlds' pets are stronger (+10% for a Puppy up to
+500% for a Phoenix). Equip 3; their bonuses add up and multiply with rebirths on
everything you sell (only goods you made, like the rebirth bonus). Pets follow you
around. The ✨ Exotic Egg (Robux) hatches the strongest pets (+600% to +1500%). The
shop shows each player's real odds and never gives a duplicate, as Roblox requires
for paid random items. → `Pets.luau`, `PetPanel.luau`, `Rules.buyPet`.

**Themed gathering zones**. Each zone is dressed for what you gather there: a barn,
silo, tractor and scarecrow at the Farm; a log cabin and lumber pile in the Forest;
a mine entrance with rails and an ore cart at the Mine; an ice-fishing shanty and
igloo at the Frozen Lake; dragon bones and a gold hoard in the Dragon's Lair.
Props reserve their spot so gathering nodes never spawn inside them. → `Scenery.luau`.

**No visible map edge**. Past each world's walls the scenery keeps going, matched to
what's in front of it: more fields, barns and windmills behind the Farm; stepped
quarry walls behind the Quarry; mine tunnels in brown crags behind the Mine; glowing
crystal crags behind the Cave; a town behind the shops; snowy peaks and a smoking
volcano behind the hub's two portals; a frozen lake with fishing huts behind the
Frozen Lake; a lava lake behind the Magma Pits. Behind that, hills and a full ring
of mountains close off the horizon. None of it can be reached or collided with.
Every building and prop claims its own ground, so nothing overlaps. → `Backdrop.luau`, `Layout.luau`.

**Ground that never flickers**. Smooth, flat, bright colour, the clean cartoon look
of Pet Simulator 99, with no busy texture to shimmer. Flicker (z-fighting) happens
when two surfaces sit at nearly the same height, and the further away they are, the
bigger the gap they need. So nothing overlaps the ground: each world is one disc,
and the ring past the walls is tiled with exact slices (a rectangle plus a wedge
each side) that meet edge to edge. Floors laid on top (zone floors, cobblestone
paths with curbs, the street, the plaza) each have their own height, at least
0.1 studs from the next; distant lakes and fields sit 0.4 up. Shops stand on raised
stone bases so their decks never share a plane with the street.
→ `World.LAYER`, `Backdrop.groundSlice`.

**Themed shops and visible portals**. The Market is a striped bazaar tent, the
Workshop a timber-framed forge with a smoking chimney, and the Outfitter an
explorer's tent with a pickaxe rack showing each gear tier. Portals stand either
side of the Market, straight ahead of where you spawn.

**The Deep Mine** (every world). A mine lift on the surface takes you down to five
cavern levels. Every swing digs up a random ore, a small RNG moment like
Grow a Garden's mutations. Any level can turn up any of the world's five ores, but
deeper levels make the good ones the norm:

| Level | Common → rarest (Market Town: 🔸 Copper $15, 🔘 Silver $50, 🔶 Gold $150, 💚 Emerald $400, 💙 Sapphire $1,200) |
|---|---|
| 1 | 80% · 16% · 3.5% · 0.45% · 0.05% |
| 2 | 45% · 32% · 16% · 5% · 2% |
| 3 | 15% · 27% · 33% · 17% · 8% |
| 4 | 5% · 15% · 30% · 32% · 18% |
| 5 | 2% · 6% · 17% · 35% · 40% |

How deep you can go depends on how strong you are in that world:
- Market Town: your Gathering Gear (tools), level for level.
- Frostpeak: cold-proof Thermal Gear.
- Emberfall: Fireproof Armor.

Everyone can mine level 1. Each vein shows chunks of the ores its level turns up, and
rare finds get their own toast. Ores come one per swing (not multiplied by gear) with
a longer hold, and markets stock few of the rare ones. `sim/mine_income.luau` rolls
real swings through the market. Per swing, a level pays about 2× surface gathering
at the same gear, and more over time because sales spread across five markets.
Each world also has a legendary ore (🌟 Starstone, 💫 Aurora Heart, 🌞 Sun Core).
Every swing has a 0.2% chance per level down to find one (1% on level 5), and finds
are announced to the server. All ores buy and sell in that world's market.
→ `Rules.ORE_ODDS`, `Rules.rollOre`, `Rules.mine`, `World.buildMineLevel`, `MinePanel.luau`.

**Robux shop** (coin packs and timed boosts, as in most top simulators). 🛍️ button
on the right, hotkey B. Coin packs give more coins per Robux the bigger they are,
and scale with rebirths so they never become worthless. Boosts last 15 minutes,
stack up to 4 hours, and only count down while you play: 2× Sell, 2× Gather, 3× Luck.
The 2× Sell boost follows the same rule as rebirth bonuses (no bonus on goods bought
from the market). Purchases are granted once per receipt and only confirmed to
Roblox after the save succeeds. → `Products.luau`, `ShopPanel.luau`, `Rules.grantProduct`.

## Keeping the economy fair

Checked by simulations rather than guesses:

- `sim/run.luau`: no buy/sell round trip makes money (0 of 384 strategies).
- `sim/craft_arbitrage.luau`: buying every input to craft is roughly break-even;
  crafting pays when you gathered the inputs yourself.
- `sim/progression.luau`: a good player finishes the goal chain in ~30 min and
  rebirths at ~50 / 87 / 136 min (real players roughly 1.5-2x slower).
- Goods bought from the market are tracked: they never earn the rebirth bonus and
  the merchant won't take them, so reselling can't print money (`Rules.recordPurchase`).
- Saves use a session lock so hopping servers can't lose progress (`SessionLock.luau`).

## Sources

- Roblox: [UI and UX design](https://create.roblox.com/docs/production/game-design/ui-ux-design),
  [Onboarding techniques](https://create.roblox.com/docs/production/game-design/onboarding-techniques)
- [Grow a Garden (Wikipedia)](https://en.wikipedia.org/wiki/Grow_a_Garden),
  [teleport buttons](https://nerdschalk.com/how-to-teleport-in-grow-a-garden-2/),
  [mutations](https://www.pcgamesn.com/grow-a-garden/mutations)
- Retention: [first-week retention](https://rolearn.dev/guidance/first-week-retention-optimization/),
  [player retention strategies](https://bloxg.com/guides/roblox-player-retention)
- [Highest-earning Roblox games 2026](https://rowatcher.com/news/the-10-highest-earning-roblox-games-in-2026-and-what-they-mean-for-the-platform)
- [The Ultimate UI Design Guide (DevForum)](https://devforum.roblox.com/t/the-ultimate-ui-design-guide/1236916)
