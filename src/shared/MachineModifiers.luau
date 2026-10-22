--!strict
-- Modifiers rolled onto machines (Golden, Overclocked, Quantum). A modified machine is
-- stored everywhere (inventory, layout, saves) as a variant key: the base machine ID plus
-- its modifiers in canonical order, e.g. "Seller+Golden+Quantum". Pure data and rules so
-- the server roll, simulation, UI and tests share one definition.
local function requireSibling(name: string): any
	if script ~= nil then
		return require(script.Parent[name])
	end
	return require("./" .. name)
end

local RollSources = requireSibling("RollSources")

export type Modifier = {
	Id: string,
	DisplayName: string,
	Order: number,
	-- Rolled independently on every machine roll: 1 in ChanceDenominator.
	ChanceDenominator: number,
	-- Droppers multiply their base cube value by this.
	DropperValueMultiplier: number,
	-- Sellers and upgraders add this to the multiplier they apply (3× + 1 = 4×).
	MultiplierBonus: number,
	Color: { number },
	-- Modifiers listed here never land on the same machine; the rarer roll wins.
	ConflictsWith: { string }?,
	Sources: { string }?,
}

local MachineModifiers = {}

MachineModifiers.Separator = "+"

MachineModifiers.Definitions = table.freeze({
	table.freeze({
		Id = "Golden", DisplayName = "Golden", Order = 1, ChanceDenominator = 100,
		DropperValueMultiplier = 2, MultiplierBonus = 1, Color = table.freeze({ 255, 204, 64 }), Sources = table.freeze({ "StandardRoll" }),
	}),
	table.freeze({
		Id = "Overclocked", DisplayName = "Overclocked", Order = 2, ChanceDenominator = 1_000,
		DropperValueMultiplier = 4, MultiplierBonus = 3, Color = table.freeze({ 255, 112, 64 }), Sources = table.freeze({ "StandardRoll" }),
	}),
	table.freeze({
		Id = "Quantum", DisplayName = "Quantum", Order = 3, ChanceDenominator = 10_000,
		DropperValueMultiplier = 5, MultiplierBonus = 5, Color = table.freeze({ 112, 224, 255 }), Sources = table.freeze({ "StandardRoll" }),
	}),
} :: { Modifier })

local byId: { [string]: Modifier } = {}
for _, modifier in ipairs(MachineModifiers.Definitions) do
	byId[modifier.Id] = modifier
end

function MachineModifiers.get(modifierId: any): Modifier?
	return if type(modifierId) == "string" then byId[modifierId] else nil
end

local function contains(list: { string }?, value: string): boolean
	return list ~= nil and table.find(list, value) ~= nil
end

local function recordsConflict(left: Modifier, right: Modifier): boolean
	return left ~= right and (contains(left.ConflictsWith, right.Id) or contains(right.ConflictsWith, left.Id))
end

function MachineModifiers.conflicts(leftId: string, rightId: string): boolean
	local left, right = byId[leftId], byId[rightId]
	return left ~= nil and right ~= nil and recordsConflict(left, right)
end

local function byOrder(leftId: string, rightId: string): boolean
	return byId[leftId].Order < byId[rightId].Order
end

-- True when every ID is known, appears once and no pair conflicts.
function MachineModifiers.canCombine(modifierIds: { string }): boolean
	local seen = {}
	for index, modifierId in ipairs(modifierIds) do
		if not byId[modifierId] or seen[modifierId] then
			return false
		end
		seen[modifierId] = true
		for other = 1, index - 1 do
			if MachineModifiers.conflicts(modifierIds[other], modifierId) then
				return false
			end
		end
	end
	return true
end

function MachineModifiers.makeKey(baseId: string, modifierIds: { string }?): string
	if not modifierIds or #modifierIds == 0 then
		return baseId
	end
	local ordered = table.clone(modifierIds)
	table.sort(ordered, byOrder)
	return baseId .. MachineModifiers.Separator .. table.concat(ordered, MachineModifiers.Separator)
end

-- Splits a machine key into its base ID and modifiers. Rejects unknown, repeated,
-- conflicting or out-of-order modifiers so each modified machine has exactly one key.
function MachineModifiers.parseKey(key: any): (string?, { string })
	if type(key) ~= "string" or key == "" or #key > 128 then
		return nil, {}
	end
	local parts = string.split(key, MachineModifiers.Separator)
	local baseId = table.remove(parts, 1) :: string
	if baseId == "" then
		return nil, {}
	end
	if #parts == 0 then
		return baseId, parts
	end
	if not MachineModifiers.canCombine(parts) or MachineModifiers.makeKey(baseId, parts) ~= key then
		return nil, {}
	end
	return baseId, parts
end

-- How much rarer a modified machine is than its base machine (Golden: ×100).
function MachineModifiers.oddsFactor(modifierIds: { string }): number
	local factor = 1
	for _, modifierId in ipairs(modifierIds) do
		local modifier = byId[modifierId]
		if modifier then
			factor *= modifier.ChanceDenominator
		end
	end
	return factor
end

-- Rolls every available modifier independently, rarest first, so when two conflict the
-- rarer one is kept. `nextNumber` returns a uniform number in [0, 1); `pool` defaults to
-- every modifier and exists for tests.
function MachineModifiers.roll(nextNumber: () -> number, conditions: { [string]: boolean }?, pool: { Modifier }?): { string }
	local candidates: { Modifier } = table.clone(pool or MachineModifiers.Definitions)
	table.sort(candidates, function(left: Modifier, right: Modifier)
		return left.ChanceDenominator > right.ChanceDenominator
	end)
	local chosen: { Modifier } = {}
	for _, modifier in ipairs(candidates) do
		if RollSources.isAvailable(modifier, conditions) and nextNumber() * modifier.ChanceDenominator < 1 then
			local compatible = true
			for _, existing in ipairs(chosen) do
				if recordsConflict(existing, modifier) then
					compatible = false
					break
				end
			end
			if compatible then
				table.insert(chosen, modifier)
			end
		end
	end
	table.sort(chosen, function(left: Modifier, right: Modifier)
		return left.Order < right.Order
	end)
	local ids = {}
	for _, modifier in ipairs(chosen) do
		table.insert(ids, modifier.Id)
	end
	return ids
end

-- Player-facing summary of one modifier on a machine category.
function MachineModifiers.describe(modifierId: string, category: string?): string
	local modifier = byId[modifierId]
	if not modifier then
		return ""
	end
	if category == "Producer" then
		return `{modifier.DisplayName}: ×{modifier.DropperValueMultiplier} cube value`
	elseif category == "Seller" then
		return `{modifier.DisplayName}: +{modifier.MultiplierBonus}× on every sale`
	end
	return `{modifier.DisplayName}: +{modifier.MultiplierBonus}× multiplier`
end

local function addBonus(value: any, bonus: number): number
	return (if type(value) == "number" then value else 1) + bonus
end

-- Builds the modified machine from its base definition. Numbers are baked into the usual
-- fields so the simulation, effect tags and descriptions all show the modified values.
function MachineModifiers.apply(base: { [string]: any }, modifierIds: { string }): { [string]: any }
	local derived = table.clone(base)
	local names, notes = {}, {}
	local valueMultiplier, bonus = 1, 0
	local ordered = table.clone(modifierIds)
	table.sort(ordered, byOrder)
	for _, modifierId in ipairs(ordered) do
		local modifier = byId[modifierId]
		valueMultiplier *= modifier.DropperValueMultiplier
		bonus += modifier.MultiplierBonus
		table.insert(names, modifier.DisplayName)
		table.insert(notes, MachineModifiers.describe(modifierId, base.Category))
	end
	derived.Id = MachineModifiers.makeKey(base.Id, ordered)
	derived.BaseId = base.Id
	derived.Modifiers = table.freeze(ordered)
	derived.DisplayName = table.concat(names, " ") .. " " .. base.DisplayName
	derived.Description = base.Description .. " " .. table.concat(notes, "; ") .. "."
	if base.Category == "Producer" then
		derived.OutputValue = (base.OutputValue or 1) * valueMultiplier
		derived.ModifierValueMultiplier = valueMultiplier
	elseif base.Category == "Seller" then
		-- Every sale gets the bonus: the ordinary ×1 and the seller's special payouts alike.
		derived.BasePayoutMultiplier = addBonus(base.BasePayoutMultiplier, bonus)
		derived.PayoutMultiplier = addBonus(base.PayoutMultiplier, bonus)
		if base.BonusMultiplier then
			derived.BonusMultiplier = base.BonusMultiplier + bonus
		end
	else
		-- Upgraders add the bonus wherever they apply a multiplier. The Duplicator counts as
		-- 2× (two cubes), so each cube gets (2 + bonus) / 2: Golden 3× total, Quantum 7×.
		if base.Behavior == "DuplicateItem" then
			derived.Multiplier = (2 + bonus) / 2
		elseif base.Behavior == "RandomMultiplier" and base.BonusChance then
			derived.BonusMultiplier = addBonus(base.BonusMultiplier, bonus)
		elseif base.Behavior == "RandomMultiplier" then
			derived.HighMultiplier = addBonus(base.HighMultiplier, bonus)
			derived.LowMultiplier = addBonus(base.LowMultiplier, bonus)
		else
			derived.Multiplier = addBonus(base.Multiplier, bonus)
		end
	end
	return table.freeze(derived)
end

function MachineModifiers.validate(): (boolean, string?)
	local orders = {}
	for _, modifier in ipairs(MachineModifiers.Definitions) do
		if modifier.Id == "" or string.find(modifier.Id, MachineModifiers.Separator, 1, true) then
			return false, `Modifier {modifier.Id} needs an ID without "{MachineModifiers.Separator}"`
		end
		if orders[modifier.Order] then
			return false, `Modifier {modifier.Id} reuses order {modifier.Order}`
		end
		orders[modifier.Order] = true
		if modifier.ChanceDenominator < 1 or modifier.DropperValueMultiplier < 1 or modifier.MultiplierBonus < 0 then
			return false, `Modifier {modifier.Id} has out-of-range numbers`
		end
		for _, other in ipairs(modifier.ConflictsWith or {}) do
			if not byId[other] then
				return false, `Modifier {modifier.Id} conflicts with unknown modifier {other}`
			end
		end
		local ok, message = RollSources.validate(modifier, `Modifier {modifier.Id}`)
		if not ok then
			return false, message
		end
	end
	return true
end

return table.freeze(MachineModifiers)
