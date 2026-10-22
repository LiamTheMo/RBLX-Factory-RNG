--!strict
-- Lagoon layout: a "noise" of misshapen rocky islets, stepped rock clusters and small grassy islands
-- dropped at random spots over the lagoon, clear of the islands, the hub and each other, with
-- heights from a smooth random noise field. Nothing here links the islands or reaches the hub:
-- the lagoon is scenery players may explore. Pure, deterministic math so it is unit-tested; the
-- server only clones the models onto the returned pieces.

export type Circle = { X: number, Z: number, R: number }
export type Rock = { X: number, Z: number, Scale: number, Yaw: number, Variant: number }
-- A placed model: Kind "Islet" (Y = top height; the builder picks the variant, sinks or stretches
-- it so its top lands there, and stretches it by Aspect along its own X axis), "Cluster" or
-- "Isle" (Shape names the catalog model; Y = waterline). Radius = waterline footprint.
export type Piece = {
	Kind: string, Shape: string?, X: number, Y: number, Z: number, Yaw: number,
	ScaleXZ: number, ScaleY: number, Radius: number, Aspect: number,
}
-- One walkable top (for checks): Size is its width in studs, Piece the model it belongs to.
export type Top = { X: number, Y: number, Z: number, Size: number, Piece: number }
-- Catalog models (IsletCatalog): walkable tops relative to the waterline pivot, W = top width.
export type Shape = { Name: string, Radius: number, Tops: { { X: number, Y: number, Z: number, W: number } } }
export type Catalog = { Clusters: { Shape }, Isles: { Shape } }
export type Rules = {
	Pieces: number, Region: number, IsletSize: number, MinScale: number, MaxScale: number,
	BaseRatio: number, WaterGap: number, MaxAspect: number,
	WaterlineY: number, MinTopY: number, MaxTopY: number, NoiseScale: number, NoiseWeight: number,
	ClusterChance: number, MaxIsles: number, IsleMinScale: number, IsleMaxScale: number, IsleSpacing: number,
	MinStretch: number, MaxStretch: number,
}

local LagoonLayout = {}

-- Small deterministic generator (plain Luau has no Random class): values in [0, 1).
function LagoonLayout.sequence(seed: number): () -> number
	local state = (math.floor(seed) * 2654435761 + 12345) % 4294967296
	return function(): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

local function outside(x: number, z: number, keepOut: { Circle }, pad: number): boolean
	for _, c in keepOut do
		if (x - c.X) ^ 2 + (z - c.Z) ^ 2 < (c.R + pad) ^ 2 then return false end
	end
	return true
end

-- Keep-out that hugs an irregular shoreline: for each measured bearing (radians, X/Z plane) and
-- shore distance from the centre, one circle spanning centre to shore plus `clearance`. With
-- bearings 15 degrees or less apart the circles overlap enough to cover the coast between them.
function LagoonLayout.shoreFan(cx: number, cz: number, bearings: { number }, distances: { number },
	clearance: number): { Circle }
	local fan = {}
	for k, angle in bearings do
		local half = distances[k] / 2
		table.insert(fan, { X = cx + math.cos(angle) * half, Z = cz + math.sin(angle) * half, R = half + clearance })
	end
	return fan
end

-- Decorative boulders scattered through the lagoon: seeded dart-throwing inside a disc, clear of
-- the keep-out circles and of each other. Bounded: at most `count` rocks and `count * 30` attempts.
function LagoonLayout.scatter(seed: number, count: number, radius: number, keepOut: { Circle },
	minSpacing: number, variants: number): { Rock }
	local nextValue = LagoonLayout.sequence(seed)
	local rocks: { Rock } = {}
	local attempts = 0
	while #rocks < count and attempts < count * 30 do
		attempts += 1
		local angle, r = nextValue() * math.pi * 2, math.sqrt(nextValue()) * radius
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		local clear = outside(x, z, keepOut, 0)
		if clear then
			for _, rock in rocks do
				if (x - rock.X) ^ 2 + (z - rock.Z) ^ 2 < minSpacing * minSpacing then clear = false; break end
			end
		end
		if clear then
			table.insert(rocks, {
				X = x, Z = z,
				Scale = 0.7 + nextValue() * 0.9,
				Yaw = nextValue() * math.pi * 2,
				Variant = 1 + math.floor(nextValue() * variants) % variants,
			})
		end
	end
	return rocks
end

-- A smooth random height field in [0, 1]: three seeded sine waves in random directions at
-- different wavelengths (around `scale` studs), so neighbouring rocks are related but the
-- lagoon rises and falls unpredictably.
function LagoonLayout.heightNoise(seed: number, scale: number): (number, number) -> number
	local nextValue = LagoonLayout.sequence(seed)
	local waves = {}
	for octave = 1, 3 do
		local angle = nextValue() * math.pi * 2
		local wavelength = scale / octave * (0.75 + nextValue() * 0.5)
		table.insert(waves, {
			DX = math.cos(angle) * 2 * math.pi / wavelength, DZ = math.sin(angle) * 2 * math.pi / wavelength,
			Phase = nextValue() * math.pi * 2, Weight = 1 / octave,
		})
	end
	local total = 0
	for _, w in waves do total += w.Weight end
	return function(x: number, z: number): number
		local sum = 0
		for _, w in waves do sum += math.sin(x * w.DX + z * w.DZ + w.Phase) * w.Weight end
		return 0.5 + 0.5 * sum / total
	end
end

-- The lagoon noise. Small islands are placed first (they need the most room), then stepped
-- clusters and loose islets of mixed sizes, each at a random spot in the disc of radius
-- rules.Region, clear of keepOut and of every other piece's footprint. Heights mix the noise
-- field with a random share. Bounded: at most rules.Pieces pieces in rules.Pieces * 40 attempts.
function LagoonLayout.field(seed: number, keepOut: { Circle }, rules: Rules, catalog: Catalog): ({ Top }, { Piece })
	local nextValue = LagoonLayout.sequence(seed)
	local noise = LagoonLayout.heightNoise(seed + 17, rules.NoiseScale)
	local tops: { Top } = {}
	local pieces: { Piece } = {}
	local function between(lo: number, hi: number): number
		return lo + nextValue() * (hi - lo)
	end
	local function fits(x: number, z: number, radius: number): boolean
		if x * x + z * z > rules.Region * rules.Region or not outside(x, z, keepOut, radius) then return false end
		for _, p in pieces do
			local need = radius + p.Radius + rules.WaterGap
			if (x - p.X) ^ 2 + (z - p.Z) ^ 2 < need * need then return false end
		end
		return true
	end
	local function spot(): (number, number)
		local angle, r = nextValue() * math.pi * 2, math.sqrt(nextValue()) * rules.Region
		return math.cos(angle) * r, math.sin(angle) * r
	end
	local function heightAt(x: number, z: number): number
		local mix = noise(x, z) * rules.NoiseWeight + nextValue() * (1 - rules.NoiseWeight)
		return rules.MinTopY + (rules.MaxTopY - rules.MinTopY) * mix
	end
	-- A cluster or small island: its walkable tops, rotated by yaw (Roblox CFrame.Angles(0, yaw, 0))
	-- and scaled about the waterline pivot exactly as the builder places the model.
	local function addShape(kind: string, shape: Shape, x: number, z: number, scaleXZ: number, scaleY: number)
		local yaw = nextValue() * math.pi * 2
		local c, s = math.cos(yaw), math.sin(yaw)
		table.insert(pieces, {
			Kind = kind, Shape = shape.Name, X = x, Y = rules.WaterlineY, Z = z, Yaw = yaw,
			ScaleXZ = scaleXZ, ScaleY = scaleY, Radius = shape.Radius * scaleXZ, Aspect = 1,
		})
		for _, t in shape.Tops do
			table.insert(tops, {
				X = x + (t.X * c + t.Z * s) * scaleXZ, Y = rules.WaterlineY + t.Y * scaleY,
				Z = z + (-t.X * s + t.Z * c) * scaleXZ, Size = t.W * scaleXZ, Piece = #pieces,
			})
		end
	end

	local isles, attempts = 0, 0
	while #pieces < rules.Pieces and attempts < rules.Pieces * 40 do
		attempts += 1
		local x, z = spot()
		if isles < rules.MaxIsles and #catalog.Isles > 0 and attempts <= rules.MaxIsles * 40 then
			local shape = catalog.Isles[1 + math.floor(nextValue() * #catalog.Isles) % #catalog.Isles]
			local scale = between(rules.IsleMinScale, rules.IsleMaxScale)
			if fits(x, z, shape.Radius * scale + rules.IsleSpacing) then
				addShape("Isle", shape, x, z, scale, scale)
				isles += 1
			end
		elseif nextValue() < rules.ClusterChance and #catalog.Clusters > 0 then
			local shape = catalog.Clusters[1 + math.floor(nextValue() * #catalog.Clusters) % #catalog.Clusters]
			local scale = between(0.9, 1.15)
			if fits(x, z, shape.Radius * scale) then
				-- Stretched so its lowest step lands at the noise height; steps stay climbable.
				local lowest = math.huge
				for _, t in shape.Tops do lowest = math.min(lowest, t.Y) end
				local stretch = math.clamp((heightAt(x, z) - rules.WaterlineY) / lowest, rules.MinStretch, rules.MaxStretch)
				addShape("Cluster", shape, x, z, scale, stretch)
			end
		else
			-- Skewed toward small islets, with the occasional big flat rock; stretched along one axis.
			local size = rules.IsletSize * (rules.MinScale + nextValue() ^ 1.8 * (rules.MaxScale - rules.MinScale))
			local aspect = 1 + nextValue() ^ 1.5 * (rules.MaxAspect - 1)
			local radius = size / 2 * rules.BaseRatio * aspect
			if fits(x, z, radius) then
				local y = heightAt(x, z)
				table.insert(pieces, {
					Kind = "Islet", Shape = nil, X = x, Y = y, Z = z, Yaw = nextValue() * math.pi * 2,
					ScaleXZ = size / rules.IsletSize, ScaleY = 0, Radius = radius, Aspect = aspect,
				})
				table.insert(tops, { X = x, Y = y, Z = z, Size = size, Piece = #pieces })
			end
		end
	end
	return tops, pieces
end

return LagoonLayout
