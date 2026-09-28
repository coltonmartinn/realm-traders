# Market Sim

A Roblox market economy game. Players gather or craft goods, sell them to a shared
server-wide market, and buy what they need. Prices come from supply and demand.

## Setup

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in the repo root.
   This installs the pinned tools from `rokit.toml` (rojo, selene, luau).
2. Install the Rojo plugin in Studio (`rojo plugin install`).
3. Run `rojo serve`, open a baseplate in Studio, and click Connect in the Rojo plugin.
4. To publish or test without live sync: `rojo build -o MarketSim.rbxl`.

## Checks you can run without Studio

```sh
selene src sim tests            # lint
luau sim/run.luau               # economy simulation (stability, oscillation, free-money loops)
luau tests/market.test.luau     # trade validation tests
```

## Layout

| Path | Syncs to | What |
|---|---|---|
| `src/shared` | ReplicatedStorage.Shared | Good definitions |
| `src/server` | ServerScriptService.Server | Market state, price model, NPC traders, player data |
| (project file) | ReplicatedStorage.Remotes | `TradeRequest`, `MarketUpdate`, `PlayerUpdate` |
| `sim/`, `tests/` | (not synced) | Offline simulation and tests |

`PriceModel`, `MarketState` and `Npc` use no Roblox APIs and load each other with
string requires (`require("./PriceModel")`), so the same files run in the `luau` CLI.

## Networking

- Client -> server: `TradeRequest:FireServer(goodId, "buy" | "sell", qty)`.
  The server checks the good, side, qty (whole number, 1-100), cash, owned
  amount, market stock and a per-player rate limit. Bad requests are ignored.
- Server -> all clients, every second: `MarketUpdate` with `{ [goodId]: { price, stock, ask, bid } }`.
- Server -> one client, after a trade: `PlayerUpdate` with `{ cash, inventory }`.

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
