-- How much does buy inputs -> craft -> sell make, with no gathering?
-- Crafting should mainly reward goods you gathered yourself; buying every
-- input should leave at most a thin margin.  luau sim/craft_arbitrage.luau

local Goods = require("../src/shared/Goods")
local Recipes = require("../src/shared/Recipes")
local MarketState = require("../src/server/MarketState")

for _, recipe in Recipes do
	for _, batch in { 1, 10, 30 } do
		local market = MarketState.new(Goods)
		local wallet = { cash = 1e9, inventory = {} }
		local spent = 0
		for _, input in recipe.inputs do
			spent += MarketState.trade(market, wallet, input.id, "buy", input.qty * batch) :: number
		end
		wallet.inventory[recipe.id] = batch
		local got = MarketState.trade(market, wallet, recipe.id, "sell", batch) :: number
		print(string.format("%-6s x%-3d spent %7d  got %7d  profit/craft %6.1f  (%.0f%%)", recipe.id, batch, spent, got, (got - spent) / batch, (got / spent - 1) * 100))
	end
end
