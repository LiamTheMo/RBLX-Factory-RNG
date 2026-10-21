--!strict

-- Temporary, data-driven proof-of-concept visuals for the factory route.
-- Conveyor dimensions and machine styles live here so the world presentation
-- can grow without changing placement rules or simulation behavior.
local Visuals = {
	SlotPitch = 7.5,
	MachineProfileBaseDeckTop = 0.22,
	FactoryPlot = {
		SpacingX = 70,
		BaseLengthPadding = 8,
		BaseWidth = 16,
		BaseThickness = 0.6,
		BaseCenterY = -0.3,
		BaseColor = { 154, 119, 81 },
	},
	-- Geometry fields (Elevation, DeckCenterY, DeckThickness, RollerCenterY, RollerDiameter)
	-- also drive item landing and machine lift in FactoryItemGeometry; the visible belt top
	-- sits at the roller top so cubes ride on it. The conveyor rests on the ground: a low
	-- base fills the gap under the belt and the rails start at ground level.
	Conveyor = {
		Elevation = 0,
		SegmentOverlap = 0.16,
		BeltWidth = 4.8,
		DeckThickness = 0.38,
		DeckCenterY = 0.4,
		RollerCenterY = 0.71,
		RollerDiameter = 0.22,
		BeltColor = { 40, 43, 49 },
		BaseColor = { 58, 63, 72 },
		DrumColor = { 156, 165, 176 },
		Rail = { TopAboveBelt = 0.5, Thickness = 0.3, Color = { 188, 197, 207 }, LipColor = { 233, 237, 242 } },
		Stripe = { Height = 0.16, Depth = 0.04, Color = { 255, 196, 92 } },
		Bolt = { Diameter = 0.22, Depth = 0.08, Color = { 92, 99, 110 } },
		-- Client-animated cleats that ride the belt toward the seller at item speed.
		Slat = { Spacing = 1.25, Length = 0.16, Height = 0.05, Inset = 0.25, Color = { 96, 103, 116 }, AnimateDistance = 160 },
		-- Invisible click plates on each slot; the client draws the selection box.
		Selector = { Thickness = 0.04, LengthInset = 0.3, BoxHeight = 2.2 },
		SellerBay = { StripeColor = { 240, 168, 143 } },
	},
	ConveyorItem = {
		Size = 1.0,
		LandingClearance = 0.08,
		-- Cubes appear just under the dropper housing, measured from the machine base.
		DropStartAboveLift = 4.58,
		DropDurationSeconds = 0.16,
	},
	SellerHitbox = { Size = { 2.4, 1.6, 2.1 }, Offset = { 0, 0.9, 0 } },
	Feedback = { HoverDistance = 90, SaleDuration = 1.15, MaxSalePopups = 12 },
	Variants = {
		BasicDropper = { PrimaryColor = { 82, 145, 255 }, AccentColor = { 255, 194, 66 }, Symbol = "•", Parts = {
			{ Name = "ControlKnob", Size = { 0.4, 0.4, 0.4 }, Offset = { 1.25, 2.7, 0 }, Shape = "Ball" },
		} },
		FastDropper = { PrimaryColor = { 83, 204, 213 }, AccentColor = { 247, 250, 220 }, Symbol = "≫", Parts = {
			{ Name = "SpeedFinLeft", Size = { 0.2, 0.9, 1.5 }, Offset = { -1.3, 2.9, 0 } },
			{ Name = "SpeedFinRight", Size = { 0.2, 0.9, 1.5 }, Offset = { 1.3, 2.9, 0 } },
		} },
		HeavyDropper = { PrimaryColor = { 140, 113, 195 }, AccentColor = { 208, 190, 245 }, Symbol = "◆", WidthScale = 1.18, Parts = {
			{ Name = "HeavyWeightLeft", Size = { 0.65, 1.2, 1.4 }, Offset = { -1.3, 2.5, 0 } },
			{ Name = "HeavyWeightRight", Size = { 0.65, 1.2, 1.4 }, Offset = { 1.3, 2.5, 0 } },
		} },
		ValueMultiplier = { PrimaryColor = { 245, 190, 78 }, AccentColor = { 255, 230, 149 }, Symbol = "×2", Parts = {
			{ Name = "Stamp", Size = { 1.3, 0.35, 1.1 }, Offset = { 0, 2.25, 0 } },
		} },
		Giantifier = { PrimaryColor = { 113, 191, 124 }, AccentColor = { 197, 243, 180 }, Symbol = "↗", Parts = {
			{ Name = "GrowthPylonLeft", Size = { 0.4, 2.25, 0.4 }, Offset = { -1.4, 1.55, 0 } },
			{ Name = "GrowthPylonRight", Size = { 0.4, 2.25, 0.4 }, Offset = { 1.4, 1.55, 0 } },
		} },
		PaintMachine = { PrimaryColor = { 233, 121, 163 }, AccentColor = { 253, 194, 214 }, Symbol = "●", Parts = {
			{ Name = "PaintTankLeft", Size = { 1.4, 0.8, 0.8 }, Offset = { -1.35, 1.25, 0 }, Shape = "Cylinder", Rotation = { 0, 0, 90 } },
			{ Name = "PaintTankRight", Size = { 1.4, 0.8, 0.8 }, Offset = { 1.35, 1.25, 0 }, Shape = "Cylinder", Rotation = { 0, 0, 90 } },
		} },
		CompoundPress = { PrimaryColor = { 219, 128, 78 }, AccentColor = { 252, 194, 131 }, Symbol = "×3", Parts = {
			{ Name = "PressPiston", Size = { 1.2, 0.6, 0.6 }, Offset = { 0, 2.55, 0 }, Shape = "Cylinder", Rotation = { 0, 0, 90 } },
			{ Name = "PressPlate", Size = { 1.7, 0.25, 1.4 }, Offset = { 0, 2.1, 0 } },
		} },
		ConveyorBooster = { PrimaryColor = { 87, 179, 229 }, AccentColor = { 176, 236, 255 }, Symbol = "≫", Parts = {
			{ Name = "TurboFinLeft", Size = { 1.5, 0.2, 0.4 }, Offset = { 0, 2.25, -0.7 } },
			{ Name = "TurboFinRight", Size = { 1.5, 0.2, 0.4 }, Offset = { 0, 2.25, 0.7 } },
		} },
		CooldownTuner = { PrimaryColor = { 100, 178, 173 }, AccentColor = { 190, 226, 206 }, Symbol = "◷", Parts = {
			{ Name = "TunerDial", Size = { 0.25, 1.1, 1.1 }, Offset = { 1.25, 1.4, 0 }, Shape = "Ball" },
		} },
		Duplicator = { PrimaryColor = { 167, 133, 219 }, AccentColor = { 224, 202, 255 }, Symbol = "Ⅱ", Parts = {
			{ Name = "TwinArmLeft", Size = { 0.4, 0.9, 0.5 }, Offset = { -0.7, 2.25, 0 } },
			{ Name = "TwinArmRight", Size = { 0.4, 0.9, 0.5 }, Offset = { 0.7, 2.25, 0 } },
		} },
		Goldenizer = { PrimaryColor = { 233, 182, 60 }, AccentColor = { 255, 237, 136 }, Symbol = "✦", Parts = {
			{ Name = "GoldOrb", Size = { 0.9, 0.9, 0.9 }, Offset = { 0, 2.45, 0 }, Shape = "Ball" },
		} },
		LuckyModifier = { PrimaryColor = { 97, 200, 161 }, AccentColor = { 204, 250, 201 }, Symbol = "?", Parts = {
			{ Name = "LuckyDice", Size = { 0.9, 0.9, 0.9 }, Offset = { 0, 2.45, 0 }, Rotation = { 0, 35, 15 } },
		} },
		Seller = { PrimaryColor = { 97, 198, 123 }, AccentColor = { 255, 213, 105 }, Symbol = "$", Parts = {
			{ Name = "SaleCoin", Size = { 0.18, 0.7, 0.7 }, Offset = { 0, 3.15, 0 }, Shape = "Cylinder", Rotation = { 0, 90, 0 } },
		} },
	},
	Profiles = {
		Dropper = {
			Style = "Dropper",
			PrimaryColor = { 82, 145, 255 },
			AccentColor = { 255, 194, 66 },
		},
		Processor = {
			Style = "Processor",
			PrimaryColor = { 255, 194, 66 },
			AccentColor = { 70, 53, 38 },
		},
		Seller = {
			Style = "Seller",
			PrimaryColor = { 83, 207, 113 },
			AccentColor = { 47, 105, 63 },
		},
	},
}

local MachineDefinitions
if script ~= nil then
	MachineDefinitions = require(script.Parent.MachineDefinitions)
else
	MachineDefinitions = require("./MachineDefinitions")
end
local ids = {}
for id in pairs(MachineDefinitions.all()) do
	if Visuals.Variants[id] == nil then table.insert(ids, id) end
end
table.sort(ids)
for index, id in ipairs(ids) do
	local hue = (index * 0.61803398875) % 1
	local red = math.floor(110 + 110 * math.abs(math.sin(hue * math.pi * 2)))
	local green = math.floor(110 + 110 * math.abs(math.sin((hue + 0.33) * math.pi * 2)))
	local blue = math.floor(110 + 110 * math.abs(math.sin((hue + 0.66) * math.pi * 2)))
	Visuals.Variants[id] = {
		PrimaryColor = { red, green, blue },
		AccentColor = { math.min(255, red + 35), math.min(255, green + 35), math.min(255, blue + 35) },
		Symbol = string.sub(id, 1, 1),
		Parts = { { Name = "ThemedDetail", Size = { 0.35, 0.9, 0.35 }, Offset = { 0, 2.25, 0 } } },
	}
end

return Visuals
