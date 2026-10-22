--!strict
-- Where machines, rarities and modifiers can be obtained. A source is active when every
-- condition it requires is present in the roll context, e.g. a weather ("Weather:Storm"),
-- an event ("Event:Festival"), a place ("Zone:Volcano") or an active effect ("Effect:Luck").
-- Anything with several sources is obtainable while any one of them is active.
-- Adding weather or events later means adding a source here, tagging content with it and
-- having the server put the matching condition into the roll context.

export type Source = { Id: string, DisplayName: string, Requires: { string } }
export type Conditions = { [string]: boolean }

local RollSources = {}

RollSources.Default = "StandardRoll"

RollSources.Definitions = table.freeze({
	StandardRoll = table.freeze({ Id = "StandardRoll", DisplayName = "Any roll", Requires = table.freeze({}) }),
	LuckyRoll = table.freeze({ Id = "LuckyRoll", DisplayName = "Rolls with Luck active", Requires = table.freeze({ "Effect:Luck" }) }),
} :: { [string]: Source })

RollSources.DefaultSources = table.freeze({ RollSources.Default })

function RollSources.get(sourceId: any): Source?
	return if type(sourceId) == "string" then RollSources.Definitions[sourceId] else nil
end

-- Content without an explicit Sources list comes from ordinary rolls.
function RollSources.of(content: any): { string }
	local sources = if type(content) == "table" then content.Sources else nil
	return if type(sources) == "table" and #sources > 0 then sources else RollSources.DefaultSources
end

function RollSources.isActive(sourceId: string, conditions: Conditions?): boolean
	local source = RollSources.get(sourceId)
	if not source then
		return false
	end
	for _, condition in ipairs(source.Requires) do
		if not (conditions and conditions[condition]) then
			return false
		end
	end
	return true
end

function RollSources.isAvailable(content: any, conditions: Conditions?): boolean
	for _, sourceId in ipairs(RollSources.of(content)) do
		if RollSources.isActive(sourceId, conditions) then
			return true
		end
	end
	return false
end

function RollSources.describe(content: any): string
	local names = {}
	for _, sourceId in ipairs(RollSources.of(content)) do
		local source = RollSources.get(sourceId)
		table.insert(names, if source then source.DisplayName else sourceId)
	end
	return table.concat(names, " or ")
end

function RollSources.isDefault(content: any): boolean
	local sources = RollSources.of(content)
	return #sources == 1 and sources[1] == RollSources.Default
end

-- Conditions a roll happens under, shared by the server roll and the client odds display.
-- Weather, events and special places add their conditions here when they exist.
function RollSources.conditionsForRoll(luckMultiplier: number?): Conditions
	local conditions: Conditions = {}
	if type(luckMultiplier) == "number" and luckMultiplier > 1 then
		conditions["Effect:Luck"] = true
	end
	return conditions
end

-- Every Sources list must name known sources so a typo can't make content unobtainable.
function RollSources.validate(content: any, label: string): (boolean, string?)
	if type(content) == "table" and content.Sources ~= nil and type(content.Sources) ~= "table" then
		return false, `{label} has an invalid Sources list`
	end
	for _, sourceId in ipairs(RollSources.of(content)) do
		if not RollSources.get(sourceId) then
			return false, `{label} names unknown source {tostring(sourceId)}`
		end
	end
	return true
end

return table.freeze(RollSources)
