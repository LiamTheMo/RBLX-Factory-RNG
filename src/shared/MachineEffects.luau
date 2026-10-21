--!strict
-- Short, player-facing effect tags derived from machine definitions, e.g. "2× All",
-- "1.35× Ice", "Makes Ice" or "Sells 1.4× Ice". Pure data so UI, world badges and tests
-- share one wording and new machines get a tag without UI changes.
local function requireSibling(name: string): any
	if script ~= nil then
		return require(script.Parent[name])
	end
	return require("./" .. name)
end

local CubeTypeDefinitions = requireSibling("CubeTypeDefinitions")

local MachineEffects = {}

function MachineEffects.number(value: number): string
	local rounded = math.floor(value * 100 + 0.5) / 100
	if rounded % 1 == 0 then
		return string.format("%d", rounded)
	end
	return (string.format("%.2f", rounded):gsub("0+$", ""))
end

local function typeName(typeId: any): string
	local definition = if type(typeId) == "string" then CubeTypeDefinitions.get(typeId) else nil
	return if definition then definition.DisplayName else tostring(typeId or "All")
end

local function times(value: any): string
	return MachineEffects.number(if type(value) == "number" then value else 1) .. "×"
end

local function percent(chance: number): string
	return MachineEffects.number(chance * 100) .. "%"
end

function MachineEffects.tag(definition: any): string
	if type(definition) ~= "table" then
		return ""
	end
	local behavior = definition.Behavior
	if definition.Category == "Producer" then
		return "Makes " .. typeName(definition.CubeType or "Standard")
	elseif definition.Category == "Seller" then
		if type(definition.BonusEvery) == "number" then
			return string.format("Every %dth: %s", definition.BonusEvery, times(definition.BonusMultiplier))
		elseif type(definition.BonusChance) == "number" then
			return string.format("%s: %s sale", percent(definition.BonusChance), times(definition.BonusMultiplier))
		elseif definition.TypeFilter then
			return string.format("Sells %s %s", times(definition.PayoutMultiplier), typeName(definition.TypeFilter))
		elseif definition.RequiredCubeRarity then
			return string.format("Sells %s %s+", times(definition.PayoutMultiplier), tostring(definition.RequiredCubeRarity))
		elseif type(definition.MinimumValue) == "number" then
			return string.format("Sells %s %s+", times(definition.PayoutMultiplier), MachineEffects.number(definition.MinimumValue))
		end
		return "Sells " .. times(definition.PayoutMultiplier)
	elseif behavior == "TypeMultiplier" then
		return times(definition.Multiplier) .. " " .. typeName(definition.TypeFilter)
	elseif behavior == "MultiplyValue" then
		return times(definition.Multiplier) .. " All"
	elseif behavior == "Goldenize" then
		return times(definition.Multiplier) .. " All · Gold"
	elseif behavior == "RandomMultiplier" then
		if type(definition.BonusChance) == "number" then
			return string.format("%s: %s All", percent(definition.BonusChance), times(definition.BonusMultiplier))
		end
		return "Random ×"
	elseif behavior == "ScaleVisual" then
		return times(definition.SizeScale) .. " Size"
	elseif behavior == "SetMaterial" then
		return "Paint"
	elseif behavior == "AdjustThroughput" then
		local scale = if type(definition.TravelScale) == "number" and definition.TravelScale > 0 then definition.TravelScale else 1
		return times(1 / scale) .. " Speed"
	elseif behavior == "DuplicateItem" then
		return "+1 Cube"
	end
	return times(definition.Multiplier) .. " All"
end

return MachineEffects
