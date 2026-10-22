--!strict
local Config = require("../src/shared/IslandWorldConfig")
local FactoryLayout = require("../src/shared/FactoryLayout")
local MachineVisualConfig = require("../src/shared/MachineVisualConfig")
local occupied = {}
local origins = {}
for i = 1, Config.PlotCount do
	assert(Config.findFreePlot(occupied) == i, "allocate the first free island")
	occupied[i] = true
	local p = Config.getPlotOrigin(i)
	assert(p.Y == Config.GroundY, "factories sit on island ground")
	for _, other in origins do
		local dx, dz = p.X-other.X, p.Z-other.Z
		assert(dx*dx+dz*dz > 120*120, "island factories must remain physically isolated")
	end
	table.insert(origins,p)
end
assert(Config.findFreePlot(occupied) == nil, "a full server never creates a factory in water")
occupied[3] = nil
assert(Config.findFreePlot(occupied) == 3, "departed players release their island")
for _, bad in {0,7,1.5,-1} do
	assert(not pcall(Config.getPlotOrigin,bad), "reject invalid island indices")
	assert(not pcall(Config.getIslandCenter,bad), "reject invalid island centres")
end

-- The island centre (template pivot) must sit on the conveyor midpoint, or the factory
-- would hang off the imported clearing.
local halfConveyor = (FactoryLayout.SlotCount - 1) * MachineVisualConfig.SlotPitch / 2
assert(Config.FactoryCenterOffsetX == halfConveyor, "island centre offset matches half the conveyor")
for i = 1, Config.PlotCount do
	local c, o, axis = Config.getIslandCenter(i), Config.getPlotOrigin(i), Config.getPlotAxis(i)
	assert(math.abs(axis.X * axis.X + axis.Z * axis.Z - 1) < 1e-9, "plot axis is a unit vector")
	assert(math.abs(axis.X * c.X + axis.Z * c.Z) < 1e-6, "conveyors run tangent to the ring, framing the hub")
	assert(math.abs(c.X - o.X - axis.X * halfConveyor) < 1e-9 and math.abs(c.Z - o.Z - axis.Z * halfConveyor) < 1e-9,
		"plot origin is the conveyor start, half a conveyor back along the axis")
end

-- Imported islands reach at most ~106 studs from their pivot in any direction (measured in Studio),
-- and each is rotated to its plot axis, so neighbouring centres need two reaches plus open water.
local ISLAND_REACH = 106
for i = 1, Config.PlotCount do
	for j = i + 1, Config.PlotCount do
		local a, b = Config.getIslandCenter(i), Config.getIslandCenter(j)
		local apart = math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) - 2 * ISLAND_REACH
		assert(apart > 12, string.format("islands %d and %d keep open water between them", i, j))
	end
end

-- Heights: the factory ground and the hub both sit above the water, and the hub is a climb.
assert(Config.GroundY > Config.WaterY + 5, "island ground is well above the lagoon")
assert(Config.getHubGroundY() > Config.GroundY, "the hub is reached by climbing")
assert(Config.FallRecoveryY > Config.WaterY and Config.FallRecoveryY < Config.GroundY - 5,
	"fall recovery triggers in the water, never on island ground")

-- Textured water: every surface part is a whole number of tiles wide for every layer, so the
-- pattern never breaks at part seams, and parts stay under Roblox's 2048-stud size limit.
local Surface = Config.Water.Surface
local parts = math.ceil(Surface.Size / Surface.MaxPartSize)
local side = Surface.Size / parts
assert(side <= 2048, "water surface parts stay under the part size limit")
for _, layer in Surface.Layers do
	local tiles = side / layer.StudsPerTile
	assert(math.abs(tiles - math.round(tiles)) < 1e-6, "water layers tile seamlessly across parts")
end
assert(Surface.Layers[1].OuterTransparency == 0, "beyond the floor the base water layer is opaque, so nothing empty shows")
assert(Surface.Layers[1].Transparency > 0 and Surface.Layers[1].Transparency < 0.5, "over the lagoon floor the water is slightly see-through")
assert(Surface.MaxPartSize * 2 >= Config.Water.Size and Config.Water.Size % Surface.MaxPartSize == 0,
	"the floor area lines up with whole surface parts, so see-through parts always have floor under them")

-- Foam: white with the rim denser than the surf, and a bounded, gentle, unsynchronised swell.
local Foam = Config.Foam
assert(Foam.RimTransparency >= 0 and Foam.RimTransparency < Foam.SurfTransparency and Foam.SurfTransparency < 1,
	"foam rim is denser than the surf and both stay visible")
assert(Foam.SwellStuds > 0 and Foam.SwellStuds <= 1.5, "the surf swell stays gentle")
assert(Foam.SwellSeconds[1] > 0 and Foam.SwellSeconds[1] < Foam.SwellSeconds[2], "surf periods vary per part")
assert(Foam.MaxAnimated > 0 and Foam.MaxAnimated <= 600, "surf animation is bounded")
assert(Config.Water.Surface.Drop >= 0.3, "the water surface sits clearly under the foam, so they never depth-fight")
print("Island allocation, layout and isolation tests passed")
