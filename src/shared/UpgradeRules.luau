--!strict
-- Permanent Coin upgrades bought from the Upgrades panel (factory capacity stays in
-- EconomyConfig.CapacityCosts). Pure data and rules: the server owns levels and charges
-- Coins; the client reads the same costs and effects for display. Costs grow
-- exponentially (BaseCost × Growth^(level - 1), rounded to two significant digits) and are
-- provisional balance data for playtests.

export type Upgrade = {
	Id: string,
	DisplayName: string,
	Description: string,
	Order: number,
	-- Coins for level 1, the multiplier applied for each further level, and the max level.
	BaseCost: number,
	Growth: number,
	MaxLevel: number,
	-- Coins for each next level, built from the three fields above.
	Costs: { number },
	-- Effect added per level: luck/sale multiplier (+0.1 = +10%) or seconds off the roll cooldown.
	PerLevel: number,
}

local UpgradeRules = {}

-- Two significant digits keep prices readable: 54,000 × 6 lists as 320,000.
local function roundCost(value: number): number
	local magnitude = 10 ^ math.max(0, math.floor(math.log10(value)) - 1)
	return math.floor(value / magnitude + 0.5) * magnitude
end

local function defineUpgrade(fields: { [string]: any }): Upgrade
	local costs = {}
	for level = 1, fields.MaxLevel do
		costs[level] = roundCost(fields.BaseCost * fields.Growth ^ (level - 1))
	end
	fields.Costs = table.freeze(costs)
	return table.freeze(fields) :: any
end

UpgradeRules.Definitions = table.freeze({
	defineUpgrade({
		Id = "Luck", DisplayName = "Lucky Rolls", Order = 1, PerLevel = 0.1,
		Description = "Rarer machines roll more often (stacks with Luck boosters).",
		BaseCost = 250, Growth = 6, MaxLevel = 5,
	}),
	defineUpgrade({
		Id = "SaleValue", DisplayName = "Better Prices", Order = 2, PerLevel = 0.1,
		Description = "Every sale pays more (stacks with Coin boosters).",
		BaseCost = 200, Growth = 5, MaxLevel = 5,
	}),
	defineUpgrade({
		Id = "RollSpeed", DisplayName = "Quick Rolls", Order = 3, PerLevel = 0.5,
		Description = "Shorter wait between rolls.",
		BaseCost = 500, Growth = 8, MaxLevel = 3,
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
		if #upgrade.Costs == 0 or upgrade.PerLevel <= 0 or upgrade.Growth <= 1 then
			return false, `Upgrade {upgrade.Id} needs costs, a positive effect and growing prices`
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
