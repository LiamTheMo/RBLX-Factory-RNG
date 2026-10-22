--!strict
-- Permanent Coin upgrades bought from the Upgrades panel (factory capacity stays in
-- EconomyConfig.CapacityCosts). Pure data and rules: the server owns levels and charges
-- Coins; the client reads the same costs and effects for display. Costs are provisional
-- balance data for playtests.

export type Upgrade = {
	Id: string,
	DisplayName: string,
	Description: string,
	Order: number,
	-- Coins for each next level; the number of entries is the max level.
	Costs: { number },
	-- Effect added per level: luck/sale multiplier (+0.1 = +10%) or seconds off the roll cooldown.
	PerLevel: number,
}

local UpgradeRules = {}

UpgradeRules.Definitions = table.freeze({
	table.freeze({
		Id = "Luck", DisplayName = "Lucky Rolls", Order = 1, PerLevel = 0.1,
		Description = "Rarer machines roll more often (stacks with Luck boosters).",
		Costs = table.freeze({ 150, 500, 1_500, 5_000, 15_000 }),
	}),
	table.freeze({
		Id = "SaleValue", DisplayName = "Better Prices", Order = 2, PerLevel = 0.1,
		Description = "Every sale pays more (stacks with Coin boosters).",
		Costs = table.freeze({ 100, 400, 1_200, 4_000, 12_000 }),
	}),
	table.freeze({
		Id = "RollSpeed", DisplayName = "Quick Rolls", Order = 3, PerLevel = 0.5,
		Description = "Shorter wait between rolls.",
		Costs = table.freeze({ 200, 800, 3_000 }),
	}),
} :: { Upgrade })

UpgradeRules.MinRollCooldownSeconds = 1

export type Levels = { [string]: number }

local byId: { [string]: Upgrade } = {}
for _, upgrade in ipairs(UpgradeRules.Definitions) do
	byId[upgrade.Id] = upgrade
end

function UpgradeRules.get(upgradeId: any): Upgrade?
	return if type(upgradeId) == "string" then byId[upgradeId] else nil
end

function UpgradeRules.maxLevel(upgradeId: string): number
	local upgrade = byId[upgradeId]
	return if upgrade then #upgrade.Costs else 0
end

function UpgradeRules.level(levels: Levels?, upgradeId: string): number
	local value = levels and levels[upgradeId]
	if type(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	return math.min(math.floor(value), UpgradeRules.maxLevel(upgradeId))
end

-- Coins for the next level, or nil when maxed or unknown.
function UpgradeRules.nextCost(levels: Levels?, upgradeId: string): number?
	local upgrade = byId[upgradeId]
	if not upgrade then
		return nil
	end
	return upgrade.Costs[UpgradeRules.level(levels, upgradeId) + 1]
end

function UpgradeRules.luckMultiplier(levels: Levels?): number
	return 1 + UpgradeRules.level(levels, "Luck") * byId.Luck.PerLevel
end

function UpgradeRules.saleMultiplier(levels: Levels?): number
	return 1 + UpgradeRules.level(levels, "SaleValue") * byId.SaleValue.PerLevel
end

function UpgradeRules.rollCooldown(baseSeconds: number, levels: Levels?): number
	local reduced = baseSeconds - UpgradeRules.level(levels, "RollSpeed") * byId.RollSpeed.PerLevel
	return math.max(UpgradeRules.MinRollCooldownSeconds, reduced)
end

-- Player-facing effect at a level, e.g. "×1.2 luck" or "2.5s rolls".
function UpgradeRules.describe(upgradeId: string, level: number, baseCooldownSeconds: number): string
	local levels = { [upgradeId] = level }
	if upgradeId == "Luck" then
		return string.format("×%.1f luck", UpgradeRules.luckMultiplier(levels))
	elseif upgradeId == "SaleValue" then
		return string.format("×%.1f sale value", UpgradeRules.saleMultiplier(levels))
	elseif upgradeId == "RollSpeed" then
		return string.format("%gs between rolls", UpgradeRules.rollCooldown(baseCooldownSeconds, levels))
	end
	return ""
end

-- Saved levels: known upgrades only, whole numbers within their max.
function UpgradeRules.sanitize(raw: any): Levels
	local safe: Levels = {}
	if type(raw) ~= "table" then
		return safe
	end
	for _, upgrade in ipairs(UpgradeRules.Definitions) do
		local level = UpgradeRules.level(raw, upgrade.Id)
		if level > 0 then
			safe[upgrade.Id] = level
		end
	end
	return safe
end

function UpgradeRules.validate(): (boolean, string?)
	for _, upgrade in ipairs(UpgradeRules.Definitions) do
		if #upgrade.Costs == 0 or upgrade.PerLevel <= 0 then
			return false, `Upgrade {upgrade.Id} needs costs and a positive effect`
		end
		local previous = 0
		for _, cost in ipairs(upgrade.Costs) do
			if cost <= previous then
				return false, `Upgrade {upgrade.Id} costs must rise each level`
			end
			previous = cost
		end
	end
	return true
end

return table.freeze(UpgradeRules)
