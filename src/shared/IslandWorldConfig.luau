--!strict
-- World layout: six player islands on a ring, a central hub reached by parkour, and the lagoon.
-- World-space factory origins preserve the existing left-to-right simulation (conveyor along +X).
local Config = {
	MapKey = "WorkshopAmberIslands",
	Revision = 2,
	WaterY = -2,
	IslandRadius = 230, -- radius of the plot ring around the hub, not of an island
	PlotCount = 6,
	-- Island centres sit half a conveyor (4 gaps * 7.5 studs / 2) to the +X of each factory origin.
	FactoryCenterOffsetX = 15,
	-- Characters below this are in the lagoon (missed jump or swim) and return to their island.
	FallRecoveryY = -1,
	-- Imported island/hub models live in ServerStorage, which the scripts-only publisher leaves intact.
	Templates = {
		Folder = "IslandAssets",
		-- Pivot convention: X/Z = factory clearing centre, Y = waterline, +X = conveyor axis.
		Island = "TinyFactoryIsland",
		-- Pivot convention: X/Z = hub centre, Y = waterline. Optional until the hub is modeled.
		Hub = "TinyFactoryHub",
		-- The island sits slightly proud of the water so its shore foam stays above the surface.
		WaterlineLift = 0.15,
		-- Clearing surface height above the template waterline (low-poly island: 1.385 m x 6.5 studs/m).
		GroundHeight = 9.0,
		-- The island ground mesh, used for ledge and spawn raycasts (trees and roofs are ignored).
		GroundPart = "Island | grass plateau",
		-- Lagoon models: "Islet_*" (TopHeight attribute), "Cluster_*" and "Isle_*" (tops in
		-- IsletCatalog) and "Boulder_*"; every pivot is the waterline centre.
		Islets = "Islets",
	},
	Hub = {
		GroundHeight = 15, -- hub landing height above the water
		PlaceholderRadius = 36,
	},
	Water = {
		Size = 2400, -- edge sits well beyond the camera; horizon haze hides it
		Depth = 40,
		-- Terrain voxels are 4 studs: every floor top sits on a voxel-layer boundary, so no partly
		-- filled layer near the surface pushes sand up into view as blocky squares.
		DeepFloorY = -20, -- dark floor (Mud) so open water reads deep blue
		DeepFloorRGB = { 34, 84, 104 },
		ShallowFloorY = -8, -- 6 studs under the surface: the shallows read turquoise through the water
		ShelfTerraces = 2, -- terraces 4 studs deeper each, ShelfFade studs apart, fading the shallows out
		ShelfFade = 22,
		ShoreRadius = 95,
		ColorRGB = { 18, 128, 168 },
		Transparency = 0.7,
		Reflectance = 0.06,
		WaveSize = 0.15,
		WaveSpeed = 10,
		SandRGB = { 230, 215, 170 },
		HazeRGB = { 196, 226, 238 },
		HazeDensity = 0.3,
		-- Stylized textured surface (preferred, like the Blender preview), slightly see-through over
		-- the sand shelves and deep floor of the lagoon. Empty TextureId falls back
		-- to Terrain water. The image must be owned by the place's group (Asset Manager import).
		Surface = {
			TextureId = "rbxassetid://81151046367054", -- textures/roblox_water_surface_1024.png (group Decal 88130318172422)
			ColorRGB = { 0, 150, 210 },
			Size = 4800, -- far wider than the Terrain fallback: the edge never shows, even from above
			MaxPartSize = 1200, -- parts are whole tiles wide: 1200 is a multiple of every layer's tile
			-- The surface sits this far under WaterY, so the foam (at the waterline, ~0.15 above WaterY)
			-- never depth-fights it and flickers.
			Drop = 0.45,
			-- The haze fades far water toward this deeper blue instead of a flat neon cyan.
			HazeDecayRGB = { 26, 104, 160 },
			Layers = {
				-- Tint pulls the texture slightly bluer under Roblox lighting, like the Blender render.
				-- Transparency applies over the terrain floor (the lagoon); OuterTransparency beyond it.
				{ StudsPerTile = 120, Transparency = 0.3, OuterTransparency = 0, Drift = { 1.2, 0.5 }, TintRGB = { 214, 232, 255 } },
				{ StudsPerTile = 75, Transparency = 0.75, OuterTransparency = 0.75, Drift = { -0.8, 0.9 }, TintRGB = { 255, 255, 255 } },
			},
		},
		FootingDepth = 11, -- lagoon rock footings stop about this far under the waterline (rounded up to a voxel layer)
	},
	-- The lagoon is scenery: a random noise of misshapen islets, stepped rock clusters and small
	-- islands (LagoonLayout.field). Nothing links the islands to each other or to the hub.
	Lagoon = {
		Seed = 3,
		Pieces = 110, -- placed models in all (small islands, clusters and loose islets)
		Region = 330,
		IsletSize = 6, -- a loose islet's top width at scale 1 (studs)
		MinScale = 1.0, -- loose islet top = IsletSize x scale (6 to ~11 studs)
		MaxScale = 1.9,
		MaxAspect = 1.5, -- loose islets stretch up to this along one axis (lopsided, not round)
		BaseRatio = 2.4, -- islet footprints are ~2.1-2.7x their top radius (measured from the models)
		WaterGap = 3, -- open water between neighbouring footprints
		NoiseScale = 220, -- the height noise's main wavelength (studs)
		NoiseWeight = 0.7, -- share of each height from the noise field (the rest is random)
		MinTopAboveWater = 3.5,
		MaxTopAboveHub = 5,
		ClusterChance = 0.3, -- share of pieces after the small islands that are stepped clusters
		MaxIsles = 12,
		IsleMinScale = 0.85,
		IsleMaxScale = 1.15,
		IsleSpacing = 6, -- extra open water kept round each small island (placed first)
		MinStretch = 0.8, -- cluster height stretch; catalog steps stay climbable at the maximum
		MaxStretch = 1.3,
		StepRise = 4, -- cluster steps are at most this far apart in height (with MaxStretch)
		ShoreSamples = 48, -- shoreline raycast bearings for the islands' keep-out fans
		WaterlineY = 0,
		MinTopY = 0,
		MaxTopY = 0,
	},
	-- Decorative boulders scattered through the lagoon, clear of islands, the hub and islets.
	Scatter = {
		Count = 60,
		Radius = 380,
		MinSpacing = 16,
		ShoreClearance = -1, -- islet bases may just touch the shore rocks (measured shoreline)
		BoulderShoreClearance = 8, -- decorative boulders keep this much water off every shore
		RouteClearance = 12, -- boulders keep this much water off every lagoon piece
	},
	-- rbxassetid:// of the uploaded caustics image; empty leaves the caustics layer out.
	-- Foam: white only, laced by an alpha texture (textures/roblox_foam_512.png, group-owned image),
	-- denser on the rim and lighter on the surf, which the client swells like lapping waves.
	Foam = {
		TextureId = "rbxassetid://128727564395963", -- group Decal 127163213330493; empty: plain white foam
		RimTransparency = 0,
		SurfTransparency = 0.2,
		SurfTag = "LagoonSurf",
		RetiredHalo = "Foam | shallow water halo",
		SwellStuds = 0.7, -- the surf grows outward by about this much and back
		SwellSeconds = { 2.4, 3.6 }, -- each surf part's half-cycle, picked per part so they never sync
		MaxAnimated = 450,
	},
	CausticsTextureId ="rbxassetid://86338176716899", -- textures/roblox_water_caustics_512.png
	CausticsStudsPerTile = 24,
	GroundY = 0,
}
Config.GroundY = Config.WaterY + Config.Templates.WaterlineLift + Config.Templates.GroundHeight
Config.Lagoon.WaterlineY = Config.WaterY + Config.Templates.WaterlineLift
Config.Lagoon.MinTopY = Config.Lagoon.WaterlineY + Config.Lagoon.MinTopAboveWater
Config.Lagoon.MaxTopY = Config.Lagoon.WaterlineY + Config.Hub.GroundHeight + Config.Lagoon.MaxTopAboveHub

function Config.getIslandCenter(index: number): { X: number, Y: number, Z: number }
	assert(index >= 1 and index <= Config.PlotCount and index % 1 == 0, "invalid island index")
	local angle = (index - 1) * math.pi / 3
	return { X = math.cos(angle) * Config.IslandRadius, Y = Config.GroundY, Z = math.sin(angle) * Config.IslandRadius }
end

-- Conveyor direction (unit X/Z) for a plot: tangent to the ring, so the six conveyors frame the
-- hub like the sides of a hexagon and each runs left-to-right for a player facing the hub.
function Config.getPlotAxis(index: number): { X: number, Z: number }
	assert(index >= 1 and index <= Config.PlotCount and index % 1 == 0, "invalid island index")
	local angle = (index - 1) * math.pi / 3
	return { X = -math.sin(angle), Z = math.cos(angle) }
end

-- The conveyor start: half a conveyor back along the plot axis from the island centre.
function Config.getPlotOrigin(index: number): { X: number, Y: number, Z: number }
	local center, axis = Config.getIslandCenter(index), Config.getPlotAxis(index)
	return {
		X = center.X - axis.X * Config.FactoryCenterOffsetX,
		Y = center.Y,
		Z = center.Z - axis.Z * Config.FactoryCenterOffsetX,
	}
end

function Config.getHubGroundY(): number
	return Config.WaterY + Config.Templates.WaterlineLift + Config.Hub.GroundHeight
end

function Config.findFreePlot(occupied: { [number]: boolean }): number?
	for index = 1, Config.PlotCount do
		if not occupied[index] then return index end
	end
	return nil
end

return Config
