--!strict

local UpgradeRules = require("../src/shared/UpgradeRules")
local EconomyRules = require("../src/shared/EconomyRules")
local EconomyConfig = require("../src/shared/EconomyConfig")
local MachineDefinitions = require("../src/shared/MachineDefinitions")
local SaveSchema = require("../src/shared/SaveSchema")

local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function near(left: number, right: number): boolean
	return math.abs(left - right) < 1e-9
end

local valid, problem = UpgradeRules.validate()
expect(valid, problem or "upgrade definitions should validate")

-- Levels, costs and effects.
expect(UpgradeRules.level(nil, "Luck") == 0 and UpgradeRules.level({ Luck = 2 }, "Luck") == 2, "levels default to 0")
expect(UpgradeRules.level({ Luck = 99 }, "Luck") == UpgradeRules.maxLevel("Luck"), "levels clamp to the max")
expect(UpgradeRules.level({ Luck = -1 }, "Luck") == 0 and UpgradeRules.level({ Luck = 0 / 0 }, "Luck") == 0, "bad levels read as 0")
expect(UpgradeRules.nextCost({}, "Luck") == assert(UpgradeRules.get("Luck")).Costs[1], "the first level costs the first price")
expect(UpgradeRules.nextCost({ Luck = UpgradeRules.maxLevel("Luck") }, "Luck") == nil, "maxed upgrades have no next cost")
expect(UpgradeRules.nextCost({}, "Nope") == nil and UpgradeRules.get("Nope") == nil, "unknown upgrades are rejected")
expect(near(UpgradeRules.luckMultiplier({ Luck = 2 }), 1.2), "each Lucky Rolls level adds 10% luck")
expect(near(UpgradeRules.saleMultiplier({ SaleValue = 3 }), 1.3), "each Better Prices level adds 10% sale value")
expect(UpgradeRules.rollCooldown(3, { RollSpeed = 2 }) == 2, "Quick Rolls takes 0.5s off per level")
expect(UpgradeRules.rollCooldown(1.2, { RollSpeed = 3 }) == UpgradeRules.MinRollCooldownSeconds, "the roll cooldown has a floor")
local maxLuck = UpgradeRules.luckMultiplier({ Luck = UpgradeRules.maxLevel("Luck") })
expect(maxLuck * 2 <= EconomyConfig.MaxLuckMultiplier + 1e-9, "a Luck booster on a maxed upgrade stays within the luck cap")
expect(UpgradeRules.describe("Luck", 1, 3) == "×1.1 luck" and UpgradeRules.describe("RollSpeed", 1, 3) == "2.5s between rolls", "effects describe themselves")
local sanitized = UpgradeRules.sanitize({ Luck = 2, SaleValue = 99, RollSpeed = "x", Bogus = 3 })
expect(sanitized.Luck == 2 and sanitized.SaleValue == UpgradeRules.maxLevel("SaleValue") and sanitized.RollSpeed == nil and sanitized.Bogus == nil, "saved levels are sanitized")

-- Auto-recycle thresholds.
expect(EconomyRules.parseAutoRecycle("1/1000") == 1000, "1/1000 parses")
expect(EconomyRules.parseAutoRecycle(" 1 / 1,000 ") == 1000, "spaces and digit groups are ignored")
expect(EconomyRules.parseAutoRecycle("1:250") == 250 and EconomyRules.parseAutoRecycle("5000") == 5000, "ratio and bare denominators parse")
expect(EconomyRules.parseAutoRecycle("off") == 0 and EconomyRules.parseAutoRecycle("") == 0 and EconomyRules.parseAutoRecycle("0") == 0, "off disables")
expect(EconomyRules.parseAutoRecycle("abc") == nil and EconomyRules.parseAutoRecycle("1/1") == nil and EconomyRules.parseAutoRecycle("2/10") == nil, "nonsense is rejected")
expect(EconomyRules.parseAutoRecycle("1/99999999999999") == EconomyRules.MaxAutoRecycleThreshold, "huge thresholds are capped")
expect(EconomyRules.sanitizeAutoRecycle(1) == 0 and EconomyRules.sanitizeAutoRecycle("1000") == 0 and EconomyRules.sanitizeAutoRecycle(1000.7) == 1000, "stored thresholds are whole and bounded")
expect(EconomyRules.formatAutoRecycle(1000) == "1/1000" and EconomyRules.formatAutoRecycle(50000) == "1/50,000" and EconomyRules.formatAutoRecycle(0) == "Off", "thresholds format like card odds")
expect(EconomyRules.shouldAutoRecycle(40, 1000) and not EconomyRules.shouldAutoRecycle(1000, 1000) and not EconomyRules.shouldAutoRecycle(5000, 1000), "only rolls more common than the threshold are recycled")
expect(not EconomyRules.shouldAutoRecycle(40, 0) and not EconomyRules.shouldAutoRecycle(nil, 1000), "off or unknown odds keep the machine")
-- The server compares the odds shown on cards: a common machine goes, its Golden version stays.
local pool = MachineDefinitions.getRollPool()
local common = assert(EconomyRules.getMachineOddsDenominator("PolishedRoller", pool))
local golden = assert(EconomyRules.getMachineOddsDenominator("PolishedRoller+Golden", pool))
expect(EconomyRules.shouldAutoRecycle(common, 1000) and not EconomyRules.shouldAutoRecycle(golden, 1000), "modifiers can lift a machine above the threshold")

-- Saves keep upgrades and settings.
local saved = SaveSchema.sanitize({
	SchemaVersion = SaveSchema.CurrentVersion,
	Upgrades = { Luck = 3, Bogus = 1 },
	Settings = { AutoRecycleBelow = 1000 },
})
expect(saved.Upgrades.Luck == 3 and saved.Upgrades.Bogus == nil, "upgrade levels survive a save")
expect(saved.Settings.AutoRecycleBelow == 1000, "the auto-recycle setting survives a save")
local fresh = SaveSchema.sanitize({ SchemaVersion = SaveSchema.CurrentVersion })
expect(next(fresh.Upgrades) == nil and fresh.Settings.AutoRecycleBelow == 0, "older saves load with no upgrades and auto-recycle off")
local hostile = SaveSchema.sanitize({ SchemaVersion = SaveSchema.CurrentVersion, Settings = { AutoRecycleBelow = 0 / 0 }, Upgrades = "x" })
expect(hostile.Settings.AutoRecycleBelow == 0 and next(hostile.Upgrades) == nil, "malformed settings fall back safely")

print("Upgrade and settings tests passed")
