--!strict
local Config = require("../src/shared/IslandWorldConfig")
local LagoonLayout = require("../src/shared/LagoonLayout")
local Catalog = require("../src/shared/IsletCatalog")

local L = Config.Lagoon

-- Keep-out like the builder's: the hub's placeholder disc and a shoreline fan per island (the
-- imported model's measured shore, studs from the clearing pivot every 15 degrees).
local SHORE = { 54.2, 55.8, 59.2, 65.9, 68.1, 68.3, 81.6, 81.1, 65.5, 62.0, 59.4, 56.8, 62.9, 62.0, 72.6, 56.6, 66.5,
	66.5, 66.7, 64.4, 62.2, 52.7, 53.6, 57.6 }
local keepOut = { { X = 0, Z = 0, R = Config.Hub.PlaceholderRadius + Config.Scatter.ShoreClearance } }
for index = 1, Config.PlotCount do
	local c, axis = Config.getIslandCenter(index), Config.getPlotAxis(index)
	local yaw = math.atan2(axis.Z, axis.X)
	local bearings = {}
	for k = 1, #SHORE do table.insert(bearings, yaw - (k - 1) * math.pi / 12) end
	for _, circle in LagoonLayout.shoreFan(c.X, c.Z, bearings, SHORE, Config.Scatter.ShoreClearance) do
		table.insert(keepOut, circle)
	end
end

local tops, pieces = LagoonLayout.field(L.Seed, keepOut, L, Catalog)
local topsAgain, piecesAgain = LagoonLayout.field(L.Seed, keepOut, L, Catalog)
assert(#pieces == #piecesAgain and #tops == #topsAgain, "the lagoon is deterministic")
assert(#pieces > L.Pieces * 0.7 and #pieces <= L.Pieces, string.format("the lagoon fills within its budget (%d pieces)", #pieces))

local kinds = { Islet = 0, Cluster = 0, Isle = 0 }
local quadrants = { 0, 0, 0, 0 }
for i, piece in pieces do
	local twin = piecesAgain[i]
	assert(piece.X == twin.X and piece.Z == twin.Z and piece.Kind == twin.Kind and piece.Yaw == twin.Yaw, "pieces are deterministic")
	if piece.Kind == "Cluster" then kinds.Cluster += 1 elseif piece.Kind == "Isle" then kinds.Isle += 1 else kinds.Islet += 1 end
	assert(piece.X * piece.X + piece.Z * piece.Z <= L.Region * L.Region + 1e-6, "pieces stay inside the lagoon")
	for _, c in keepOut do
		assert((piece.X - c.X) ^ 2 + (piece.Z - c.Z) ^ 2 >= (c.R + piece.Radius) ^ 2 - 1e-6, "pieces stay clear of islands and the hub")
	end
	for j = i + 1, #pieces do
		local other = pieces[j]
		local need = piece.Radius + other.Radius + L.WaterGap
		assert((piece.X - other.X) ^ 2 + (piece.Z - other.Z) ^ 2 >= need * need - 1e-6, "pieces never overlap")
	end
	if piece.Kind == "Islet" then
		assert(piece.Y >= L.MinTopY - 1e-6 and piece.Y <= L.MaxTopY + 1e-6, "islet heights stay in range")
		assert(piece.Aspect >= 1 and piece.Aspect <= L.MaxAspect + 1e-6, "islet stretch stays in range")
	end
	local q = (if piece.X >= 0 then 1 else 0) + (if piece.Z >= 0 then 2 else 0) + 1
	quadrants[q] += 1
end
assert(kinds.Isle >= 4 and kinds.Isle <= L.MaxIsles, string.format("small islands mix in (%d)", kinds.Isle))
assert(kinds.Cluster >= 5 and kinds.Islet >= 30, string.format("clusters (%d) and islets (%d) mix in", kinds.Cluster, kinds.Islet))
for q = 1, 4 do assert(quadrants[q] > #pieces / 8, "pieces are spread over every part of the lagoon") end

-- Heights vary across the lagoon.
local low, high = math.huge, -math.huge
for _, top in tops do
	low = math.min(low, top.Y)
	high = math.max(high, top.Y)
	assert(pieces[top.Piece] ~= nil, "every top belongs to a placed piece")
end
assert(high - low > 8, string.format("heights vary (%.1f to %.1f)", low, high))

-- The noise field is smooth, bounded and deterministic.
local noise, noiseAgain = LagoonLayout.heightNoise(5, L.NoiseScale), LagoonLayout.heightNoise(5, L.NoiseScale)
for k = 1, 50 do
	local x, z = k * 13.7 - 300, k * -9.1 + 200
	local v = noise(x, z)
	assert(v >= 0 and v <= 1 and v == noiseAgain(x, z), "noise is bounded and deterministic")
	assert(math.abs(noise(x + 1, z) - v) < 0.05, "noise is smooth")
end

-- Cluster steps stay climbable at the maximum stretch.
for _, shape in Catalog.Clusters do
	for i, a in shape.Tops do
		local best = math.huge
		for j, b in shape.Tops do
			if i ~= j then best = math.min(best, math.abs(a.Y - b.Y)) end
		end
		assert(best * L.MaxStretch <= L.StepRise, shape.Name .. ": each step has a climbable neighbour")
	end
end

-- Seeded generator stays in [0, 1) and repeats for the same seed.
local s1, s2 = LagoonLayout.sequence(5), LagoonLayout.sequence(5)
for _ = 1, 200 do
	local v = s1()
	assert(v >= 0 and v < 1 and v == s2(), "sequence is bounded and deterministic")
end

-- Boulder scatter: bounded, deterministic, clear of keep-out circles and of each other.
local S = Config.Scatter
local rocks = LagoonLayout.scatter(97, S.Count, S.Radius, keepOut, S.MinSpacing, 4)
local twin = LagoonLayout.scatter(97, S.Count, S.Radius, keepOut, S.MinSpacing, 4)
assert(#rocks > S.Count * 0.6 and #rocks <= S.Count, "scatter fills most of the lagoon within its budget")
for i, rock in rocks do
	assert(rock.X == twin[i].X and rock.Z == twin[i].Z, "scatter is deterministic")
	assert(rock.Variant >= 1 and rock.Variant <= 4 and rock.Scale >= 0.7 and rock.Scale <= 1.6, "variant and scale in range")
	for _, c in keepOut do
		assert((rock.X - c.X) ^ 2 + (rock.Z - c.Z) ^ 2 >= c.R * c.R, "rocks keep clear of islands and the hub")
	end
	for j = i + 1, #rocks do
		assert((rock.X - rocks[j].X) ^ 2 + (rock.Z - rocks[j].Z) ^ 2 >= S.MinSpacing ^ 2, "rocks keep their spacing")
	end
end
assert(#LagoonLayout.scatter(1, 10, 50, { { X = 0, Z = 0, R = 100 } }, 5, 4) == 0, "no room means no rocks, without looping forever")
print("Lagoon layout tests passed")
