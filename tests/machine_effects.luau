local MachineDefinitions = require("../src/shared/MachineDefinitions")
local MachineEffects = require("../src/shared/MachineEffects")

local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function tag(id: string): string
	return MachineEffects.tag(assert(MachineDefinitions.get(id), id))
end

expect(MachineEffects.number(2) == "2" and MachineEffects.number(1.35) == "1.35" and MachineEffects.number(1.1) == "1.1", "numbers drop trailing zeros")
expect(tag("ValueMultiplier") == "2× All", "global upgraders read as N× All")
expect(tag("FrostFramer") == "1.35× Ice", "type upgraders name their cube type")
expect(tag("MossMixer") == "1.25× Nature", "type upgraders use the cube display name")
expect(tag("FrostPopper") == "Makes Ice", "droppers name the cube they make")
expect(tag("BasicDropper") == "Makes Standard", "starter dropper is labelled")
expect(tag("FrostFair") == "Sells 1.4× Ice", "type sellers name their bonus")
expect(tag("FestivalTreasury") == "Every 5th: 3×", "streak sellers show their cadence")
expect(tag("LuckyTill") == "12.5%: 1.5× sale", "chance sellers show their odds")
expect(tag("RainbowExchange") == "Sells 1.5× Epic+", "rarity sellers show the threshold")
expect(tag("BulkBooth") == "Sells 1.15× 20+", "conditional sellers show the value floor")
expect(tag("Seller") == "Sells 1×", "the default seller is labelled")
expect(tag("ConveyorBooster") == "1.2× All · Fast", "throughput machines show their value bonus")
expect(tag("Giantifier") == "1.5× All · Big", "the size machine shows its value bonus")
expect(tag("PaintMachine") == "1.25× All · Paint", "the paint machine shows its value bonus")
expect(tag("LuckyModifier") == "3× or 0.5× All", "the alternating modifier shows both outcomes")
expect(tag("LuckyLantern") == "10%: 2× All", "chance upgraders show their odds")

local function role(id: string): string?
	local found = MachineEffects.role(MachineDefinitions.get(id))
	return found and found.Name
end

expect(role("BasicDropper") == "Dropper" and role("FrostPopper") == "Dropper", "producers read as droppers")
expect(role("ValueMultiplier") == "Upgrader" and role("FrostFramer") == "Upgrader", "processors read as upgraders")
expect(role("Seller") == "Seller" and role("LuckyTill") == "Seller", "sellers read as sellers")
expect(MachineEffects.role(nil) == nil and MachineEffects.role({ Category = "Unknown" }) == nil, "unknown categories have no role")

for id, definition in pairs(MachineDefinitions.all()) do
	local text = MachineEffects.tag(definition)
	expect(text ~= "" and #text <= 24, `machine {id} needs a short effect tag, got "{text}"`)
	local found = MachineEffects.role(definition)
	expect(found ~= nil and #found.Color == 3, `machine {id} needs a role label`)
end

print("Machine effect tags and roles passed")
