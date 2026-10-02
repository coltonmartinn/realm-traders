# Publishing Realm Traders

Everything in the code is ready. These steps need the Roblox Creator Dashboard
or Studio, so they're done by hand. Total time is about 30 minutes.

## 1. Studio settings (once)

- **File → Game Settings → Security → Enable Studio Access to API Services.**
  Without this, progress isn't saved when you test in Studio. The live game saves either way.
- **Basic Info → Name:** `Realm Traders`.
- **Workspace → Terrain → Decoration:** leave this off. The ground is smooth parts now.

## 2. Developer Products (the Robux shop)

Until each product has an ID, its shop button shows **SOON** and can't be bought.

1. Go to the Creator Dashboard → Realm Traders → **Monetization → Developer Products**.
2. Create these 8, with the names and prices exactly as listed.
3. Copy each product's ID into its `id = 0` in `src/shared/Products.luau`, matching the `key`.

| key | Name | Price (Robux) | Description |
|---|---|---|---|
| cash_1 | Pouch of Coins | 25 | 1,000 coins. More with every Rebirth! |
| cash_2 | Sack of Coins | 99 | 6,000 coins. More with every Rebirth! |
| cash_3 | Chest of Coins | 399 | 30,000 coins. More with every Rebirth! |
| cash_4 | Vault of Coins | 999 | 100,000 coins. More with every Rebirth! |
| egg_exotic | Exotic Egg | 199 | Hatch an exotic pet with a huge sell bonus. Odds shown in game. |
| boost_sell | 2× Sell Boost | 49 | Double cash from selling goods you made, for 15 minutes. |
| boost_gather | 2× Gather Boost | 49 | Double goods from every gather, for 15 minutes. |
| boost_luck | 3× Luck Boost | 39 | Triple the chance of Golden and Rainbow finds, for 15 minutes. |

✅ Done: all 8 are created and their IDs are in `Products.luau`. When you create
a product, it asks about trading or gifting. Answer "does not allow trading or
gifting": players only trade with the market, never with each other.

**Already handled in code:**
- Each purchase is granted once and only confirmed after it saves.
- The shop shows each player's real egg odds.
- The egg is hidden where Roblox's policy bans paid random items. If it's bought anyway, it pays coins.

## 3. Store page

On the Creator Dashboard → **Configure → Basic Info**:

**Description** (paste and edit):

> Gather, craft and trade your way to the top! 🌲 Chop wood, 🌾 harvest wheat and ⛰️ mine
> stone, then sell them to a live market where prices rise and fall with supply and demand.
> Bake bread, forge tools and craft jewelry for bigger profits.
>
> ⛏️ Ride the lift into the **Deep Mine**: every swing digs up a random ore, and the deeper
> you go, the rarer the finds. Hunt for legendary ores!
>
> 🌀 Rebirth to unlock new worlds: ❄️ **Frostpeak** and 🔥 **Emberfall**, each with its own
> goods, coins and mine. 🐾 Collect pets that boost your sales, 📖 complete your collection
> and climb the 🏆 Top Traders board.
>
> 🎁 Codes: RELEASE, MARKET, TRADER

- **Genre:** Simulation (or Economic). **Max players:** 16.
- **Devices:** Computer, Phone, Tablet and Console. Most simulator players are on phones.
- **Icon** (512×512) and **thumbnails** (1920×1080). Take these in a Play test: the
  Coin Monument from spawn, the Deep Mine, the Frostpeak and Emberfall plazas, and the
  Market with its odds open. Bright, close-up shots with the UI showing get the most clicks.
- **Maturity & Compliance questionnaire:** required before the game can go public.

## 4. Test the live game (while it's still private)

1. Play from the game page, not from Studio.
2. Gather, sell, upgrade, then rejoin and check that your progress saved.
3. Buy the cheapest product (Pouch of Coins, 25 Robux) and check that the coins arrive.
4. Go through both portals. Frostpeak needs 2 rebirths; in Studio the DevGrant hook speeds that up.
5. Ride the mine lift down and back up.
6. Try it on a phone. Check that the top buttons don't overlap and the panels fit.

## 5. Go public

Creator Dashboard → Realm Traders → **Make Public**. After that, each
**File → Publish to Roblox** updates the game. Use **Restart Servers** on the dashboard
to move players onto the new version.

## Promo codes

Codes are in `src/server/Codes.luau`. RELEASE pays 500 coins; MARKET and TRADER pay 250 each.
Add new codes for updates and milestones (e.g. `LIKES1K`). Players who redeemed a
code keep its reward when you remove it.
