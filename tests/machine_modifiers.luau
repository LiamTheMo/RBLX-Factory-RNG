--!strict

local FactorySimulation = require("../src/shared/FactorySimulation")
local MachineDefinitions = require("../src/shared/MachineDefinitions")
local MachineModifiers = require("../src/shared/MachineModifiers")
local MachineEffects = require("../src/shared/MachineEffects")
local EconomyRules = require("../src/shared/EconomyRules")
local RollSources = require("../src/shared/RollSources")
local SaveSchema = require("../src/shared/SaveSchema")

local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function near(left: number?, right: number): boolean
	return left ~= nil and math.abs(left - right) < 1e-6
end

local function get(key: string): any
	return assert(MachineDefinitions.get(key), key)
end

local valid, problem = MachineDefinitions.validate()
expect(valid, problem or "definitions with modifiers should validate")

-- Keys: one canonical spelling per modified machine.
expect(MachineModifiers.makeKey("Seller", { "Quantum", "Golden" }) == "Seller+Golden+Quantum", "keys list modifiers in canonical order")
expect(MachineModifiers.makeKey("Seller", {}) == "Seller", "an unmodified key is the base ID")
local baseId, modifierIds = MachineModifiers.parseKey("Seller+Golden+Quantum")
expect(baseId == "Seller" and #modifierIds == 2 and modifierIds[1] == "Golden" and modifierIds[2] == "Quantum", "keys parse back to base and modifiers")
expect(MachineModifiers.parseKey("Seller+Quantum+Golden") == nil, "out-of-order keys are rejected")
expect(MachineModifiers.parseKey("Seller+Golden+Golden") == nil, "repeated modifiers are rejected")
expect(MachineModifiers.parseKey("Seller+Shiny") == nil, "unknown modifiers are rejected")
expect(MachineModifiers.parseKey("+Golden") == nil and MachineModifiers.parseKey("") == nil, "a key needs a base ID")
expect(MachineDefinitions.get("Seller+Quantum+Golden") == nil, "non-canonical keys do not resolve")
expect(MachineDefinitions.get("BasicDropper+Golden") == nil, "the starter dropper cannot be modified")
expect(MachineDefinitions.get("Nope+Golden") == nil, "unknown base machines do not resolve")
expect(get("Seller+Golden") == get("Seller+Golden"), "modified machines are cached")
expect(MachineDefinitions.baseId("ValueMultiplier+Quantum") == "ValueMultiplier", "the base ID is recoverable")

-- Upgraders: Golden +1, Overclocked +3, Quantum +5 to the multiplier, stacking.
expect(near(get("ValueMultiplier+Golden").Multiplier, 3), "Golden turns a 2× upgrader into 3×")
expect(near(get("ValueMultiplier+Overclocked").Multiplier, 5), "Overclocked adds 3× to the multiplier")
expect(near(get("ValueMultiplier+Quantum").Multiplier, 7), "Quantum turns 2× into 7×")
expect(near(get("ValueMultiplier+Golden+Overclocked+Quantum").Multiplier, 11), "all three modifiers stack")
expect(near(get("LuckyLantern+Golden").BonusMultiplier, 3), "chance upgraders boost their bonus")
expect(near(get("LuckyModifier+Golden").HighMultiplier, 4) and near(get("LuckyModifier+Golden").LowMultiplier, 1.5), "alternating upgraders boost both outcomes")
expect(near(get("Duplicator+Golden").Multiplier, 2), "the Duplicator gains a multiplier")

-- Droppers: ×2, ×4, ×5 base cube value, stacking.
local fast = get("FastDropper")
expect(near(get("FastDropper+Golden").OutputValue, fast.OutputValue * 2), "Golden doubles dropper value")
expect(near(get("FastDropper+Overclocked").OutputValue, fast.OutputValue * 4), "Overclocked quadruples dropper value")
expect(near(get("FastDropper+Quantum").OutputValue, fast.OutputValue * 5), "Quantum gives dropper value ×5")
expect(near(get("FastDropper+Golden+Overclocked+Quantum").OutputValue, fast.OutputValue * 40), "dropper modifiers multiply together")
expect(get("FastDropper+Golden").SpawnInterval == fast.SpawnInterval, "modifiers leave the drop rate alone")

-- Sellers: every sale gets the bonus.
expect(near(get("Seller+Golden").PayoutMultiplier, 2) and near(get("Seller+Golden").BasePayoutMultiplier, 2), "Golden sellers pay +1×")
expect(near(get("FrostFair+Quantum").PayoutMultiplier, 6.4) and near(get("FrostFair+Quantum").BasePayoutMultiplier, 6), "type sellers boost matching and other cubes")
expect(near(get("FestivalTreasury+Golden").BonusMultiplier, 4), "streak sellers boost their bonus sale")

-- Names, descriptions and tags show the modified numbers.
local golden = get("ValueMultiplier+Golden")
expect(golden.DisplayName == "Golden Value Multiplier" and golden.Id == "ValueMultiplier+Golden" and golden.BaseId == "ValueMultiplier", "modified machines are named after their modifiers")
expect(string.find(golden.Description, "Golden: +1× multiplier", 1, true) ~= nil, "descriptions explain the modifier")
expect(MachineEffects.tag(golden) == "3× All", "effect tags use the modified multiplier")
expect(MachineEffects.tag(get("FastDropper+Golden")) == "Makes Standard · ×2", "dropper tags show the value boost")
expect(MachineEffects.tag(get("LuckyModifier+Golden")) == "4× or 1.5× All", "alternating tags show both boosted outcomes")
expect(MachineEffects.tag(get("Duplicator+Golden")) == "2× All · +1 Cube", "duplicator tags show the new multiplier")
expect(MachineEffects.role(get("Seller+Quantum")).Name == "Seller", "modified machines keep their role")
local combos = { { "Golden" }, { "Overclocked" }, { "Quantum" }, { "Golden", "Overclocked", "Quantum" } }
for id, definition in pairs(MachineDefinitions.all()) do
	if definition.Rollable then
		for _, combo in ipairs(combos) do
			local key = MachineModifiers.makeKey(id, combo)
			local text = MachineEffects.tag(get(key))
			expect(#text <= 24, `{key} needs a short effect tag, got "{text}"`)
		end
	end
end

-- Odds: each modifier multiplies the machine's odds by its own chance.
local pool = MachineDefinitions.getRollPool()
local baseOdds = assert(EconomyRules.getMachineOddsDenominator("ValueMultiplier", pool))
expect(near(EconomyRules.getMachineOddsDenominator("ValueMultiplier+Golden", pool), baseOdds * 100), "Golden makes a machine 100× rarer")
expect(near(EconomyRules.getMachineOddsDenominator("ValueMultiplier+Golden+Quantum", pool), baseOdds * 1_000_000), "modifier odds multiply")
expect(EconomyRules.getMachineRarity("ValueMultiplier+Quantum", pool) == get("ValueMultiplier").Rarity, "modifiers keep the machine's rarity")
expect(EconomyRules.getMachineOddsDenominator("ValueMultiplier+Bogus", pool) == nil, "invalid keys have no odds")
expect(EconomyRules.formatOddsDenominator(40) == "40" and EconomyRules.formatOddsDenominator(12.5) == "12.5", "short odds stay plain")
expect(EconomyRules.formatOddsDenominator(1_000_000) == "1,000,000" and EconomyRules.formatOddsDenominator(250_000) == "250,000", "long odds are grouped")
local luckyPool = EconomyRules.getLuckAdjustedRollPool(pool, 2)
local label = assert(EconomyRules.getMachineOddsLabel("ValueMultiplier+Golden", luckyPool))
local plain = assert(EconomyRules.getMachineOddsLabel("ValueMultiplier", luckyPool))
expect(label ~= plain and string.sub(label, 1, 2) == "1/", "luck-adjusted labels include modifiers")
expect(EconomyRules.shouldPlayUltraRareCutscene(EconomyRules.getMachineOddsDenominator("ValueMultiplier+Quantum", pool)), "a Quantum roll plays the ultra-rare reveal")

-- Rolling: independent chances, rarest first, conflicts keep the rarer modifier.
local function always(value: number): () -> number
	return function()
		return value
	end
end
local all = MachineModifiers.roll(always(0))
expect(#all == 3 and all[1] == "Golden" and all[2] == "Overclocked" and all[3] == "Quantum", "every modifier can land on one machine")
expect(#MachineModifiers.roll(always(0.5)) == 0, "most rolls get no modifier")
local sequence = { 0.5, 0.5, 0.005 } -- Quantum miss, Overclocked miss, Golden hit (1/100)
local index = 0
local goldenOnly = MachineModifiers.roll(function()
	index += 1
	return sequence[index]
end)
expect(#goldenOnly == 1 and goldenOnly[1] == "Golden", "Golden lands on 1 in 100 rolls")
local testPool = {
	{ Id = "Common", DisplayName = "Common", Order = 1, ChanceDenominator = 10, DropperValueMultiplier = 1, MultiplierBonus = 1, Color = { 1, 1, 1 }, ConflictsWith = { "Rare" } },
	{ Id = "Rare", DisplayName = "Rare", Order = 2, ChanceDenominator = 100, DropperValueMultiplier = 1, MultiplierBonus = 1, Color = { 1, 1, 1 } },
	{ Id = "Event", DisplayName = "Event", Order = 3, ChanceDenominator = 5, DropperValueMultiplier = 1, MultiplierBonus = 1, Color = { 1, 1, 1 }, Sources = { "LuckyRoll" } },
}
local conflicted = MachineModifiers.roll(always(0), nil, testPool :: any)
expect(#conflicted == 1 and conflicted[1] == "Rare", "conflicting modifiers keep the rarer one and skip source-locked ones")
local withLuck = MachineModifiers.roll(always(0), RollSources.conditionsForRoll(2), testPool :: any)
expect(#withLuck == 2 and withLuck[1] == "Rare" and withLuck[2] == "Event", "source-locked modifiers roll when their condition is active")

-- Sources: where things are obtainable.
expect(RollSources.describe(get("ValueMultiplier")) == "Any roll", "machines default to ordinary rolls")
expect(MachineDefinitions.describeSources(get("ValueMultiplier+Golden")) == "Any roll", "modifiers from ordinary rolls add nothing")
expect(not RollSources.isAvailable({ Sources = { "LuckyRoll" } }, RollSources.conditionsForRoll(1)), "luck-only content needs luck")
expect(RollSources.isAvailable({ Sources = { "LuckyRoll" } }, RollSources.conditionsForRoll(2)), "luck-only content rolls with luck")
expect(RollSources.isAvailable({ Sources = { "LuckyRoll", "StandardRoll" } }, nil), "any active source is enough")
expect(not RollSources.validate({ Sources = { "Nowhere" } }, "Test"), "unknown sources fail validation")
expect(#MachineDefinitions.getRollPool(nil, RollSources.conditionsForRoll(2)) == #pool, "luck adds no machines until some are luck-only")

-- Simulation: modified machines change what the belt earns.
local function earnings(route: { string }, seconds: number): number
	local simulation = FactorySimulation.new({ Route = route, SpawnIntervalSeconds = 1, TravelTimePerSlotSeconds = 0.1 })
	local elapsed = 0
	while elapsed < seconds do
		simulation:step(0.05)
		elapsed += 0.05
		for _, item in ipairs(simulation:getActiveItemsForDebug()) do
			if item.ReadyForSale then
				simulation:sellItem(item.Id, { AdditiveBonus = 0, Multiplier = 1 })
			end
		end
	end
	return simulation:getSnapshot().Coins
end
local plainCoins = earnings({ "FastDropper", "ValueMultiplier", "Seller" }, 0.5)
expect(plainCoins > 0, "the plain route sells a cube")
expect(near(earnings({ "FastDropper", "ValueMultiplier+Golden", "Seller" }, 0.5), plainCoins * 1.5), "a Golden 2× upgrader earns 3/2 as much")
expect(near(earnings({ "FastDropper", "ValueMultiplier", "Seller+Golden" }, 0.5), plainCoins * 2), "a Golden seller pays double on a ×1 sale")
expect(near(earnings({ "FastDropper+Golden", "ValueMultiplier", "Seller" }, 0.5), plainCoins * 2), "a Golden dropper doubles cube value")
expect(near(earnings({ "FastDropper+Quantum", "ValueMultiplier+Quantum", "Seller+Quantum" }, 0.5), plainCoins * 5 * 3.5 * 6), "Quantum stacks across the route")
expect(near(earnings({ "FastDropper", "Duplicator+Golden", "Seller" }, 0.5), earnings({ "FastDropper", "Duplicator", "Seller" }, 0.5) * 2), "a Golden Duplicator doubles both cubes")

-- Saves keep modified machines and drop invalid keys.
local saved = SaveSchema.sanitize({
	SchemaVersion = SaveSchema.CurrentVersion,
	Inventory = { ["Seller+Golden"] = 2, ["Seller+Quantum+Golden"] = 1, ["Seller+Shiny"] = 1 },
	Layout = { "FastDropper+Overclocked", "ValueMultiplier+Golden", "", "", "Seller+Quantum" },
	Capacity = 1,
})
expect(saved.Inventory["Seller+Golden"] == 2, "modified machines survive a save")
expect(saved.Inventory["Seller+Quantum+Golden"] == nil and saved.Inventory["Seller+Shiny"] == nil, "invalid modifier keys are dropped")
expect(saved.Layout[1] == "FastDropper+Overclocked" and saved.Layout[2] == "ValueMultiplier+Golden" and saved.Layout[5] == "Seller+Quantum", "modified machines stay placed")

print("Machine modifier and source tests passed")
