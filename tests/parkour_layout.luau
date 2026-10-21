--!strict
local Config = require("../src/shared/IslandWorldConfig")
local ParkourLayout = require("../src/shared/ParkourLayout")

local rules = Config.Parkour
local function check(from, to, seed, label)
	local pads = ParkourLayout.route(from, to, rules, seed)
	assert(#pads >= 1 and #pads <= rules.MaxPads, label .. ": pad count stays inside the budget")
	for _, hop in ParkourLayout.hops(from, to, pads, rules.PadSize) do
		assert(hop.Gap <= rules.MaxGap + 1e-6, string.format("%s: gap %.2f within jump reach", label, hop.Gap))
		assert(hop.Gap > 0, label .. ": pads never overlap their neighbours")
		assert(math.abs(hop.Rise) <= rules.MaxRise + 1e-6, string.format("%s: climb %.2f within jump height", label, hop.Rise))
	end
	local again = ParkourLayout.route(from, to, rules, seed)
	for i, pad in pads do
		local twin = again[i]
		assert(pad.X == twin.X and pad.Y == twin.Y and pad.Z == twin.Z, label .. ": routes are deterministic")
	end
	return pads
end


-- Noise field over the real layout. Islands use the imported model's measured profile (studs from
-- the clearing pivot every 15 degrees, Blender bearings): the plateau edge at ground height, the
-- shoreline for the keep-out fan, and the low dock end. The hub is its placeholder cylinder.
local Catalog = require("../src/shared/IsletCatalog")
local F = Config.Field
local PLATEAU = { 51.0, 52.3, 57.1, 61.9, 64.7, 66.3, 66.0, 64.4, 60.8, 58.3, 56.3, 50.7, 47.6, 47.5, 47.9, 47.6, 44.3,
	42.1, 43.3, 49.4, 51.0, 51.1, 51.8, 51.3 }
local SHORE = { 54.2, 55.8, 59.2, 65.9, 68.1, 68.3, 81.6, 81.1, 65.5, 62.0, 59.4, 56.8, 62.9, 62.0, 72.6, 56.6, 66.5,
	66.5, 66.7, 64.4, 62.2, 52.7, 53.6, 57.6 }
local DOCK_BEARING, DOCK_DISTANCE, DOCK_HEIGHT = math.rad(247), 66, 2.7
local shore = Config.Scatter.ShoreClearance
local hubLedges = {}
for k = 0, F.LedgeSamples - 1 do
	local a = k * math.pi * 2 / F.LedgeSamples
	local r = Config.Hub.PlaceholderRadius
	table.insert(hubLedges, { X = math.cos(a) * r, Y = Config.getHubGroundY(), Z = math.sin(a) * r })
end
local anchors = { { Ledges = hubLedges } }
local fieldKeepOut = { { X = 0, Z = 0, R = Config.Hub.PlaceholderRadius + shore } }
for index = 1, Config.PlotCount do
	local c, axis = Config.getIslandCenter(index), Config.getPlotAxis(index)
	-- Blender bearing b -> Roblox local angle -b -> world angle plotYaw - b (the template frame).
	local yaw = math.atan2(axis.Z, axis.X)
	local ledges, bearings = {}, {}
	for k, r in PLATEAU do
		local a = yaw - (k - 1) * math.pi / 12
		table.insert(ledges, { X = c.X + math.cos(a) * r, Y = Config.GroundY, Z = c.Z + math.sin(a) * r })
		table.insert(bearings, a)
	end
	local dock = yaw - DOCK_BEARING
	table.insert(ledges, { X = c.X + math.cos(dock) * DOCK_DISTANCE, Y = F.WaterlineY + DOCK_HEIGHT, Z = c.Z + math.sin(dock) * DOCK_DISTANCE })
	table.insert(anchors, { Ledges = ledges })
	for _, circle in ParkourLayout.shoreFan(c.X, c.Z, bearings, SHORE, shore) do table.insert(fieldKeepOut, circle) end
end
local islets, pieces = ParkourLayout.field(F.Seed, anchors, fieldKeepOut, Config.landingHeight, F, rules, Catalog)
local isletsAgain, piecesAgain = ParkourLayout.field(F.Seed, anchors, fieldKeepOut, Config.landingHeight, F, rules, Catalog)
assert(#islets == #isletsAgain and #pieces == #piecesAgain, "field is deterministic")
assert(#islets >= 150 and #pieces <= F.MaxPieces, string.format("field fills the lagoon within budget (%d tops, %d pieces)", #islets, #pieces))
assert(ParkourLayout.allConnected(anchors, islets, rules), "every island reaches the hub and back by fair jumps")

-- Cluster steps stay climbable at the maximum stretch, so every cluster is a way up on its own.
for _, shape in Catalog.Clusters do
	for i, a in shape.Tops do
		local best = math.huge
		for j, b in shape.Tops do
			if i ~= j then best = math.min(best, math.abs(a.Y - b.Y)) end
		end
		assert(best * F.MaxStretch <= rules.MaxRise, shape.Name .. ": each step has a climbable neighbour")
	end
end

-- Noise, not a path: islets, clusters and small islands, at widely varying heights, spread over
-- the whole lagoon, with only a few bridging rocks.
local kinds = { Islet = 0, Cluster = 0, Isle = 0 }
local small, big, connectors = 0, 0, 0
local quadrants = { 0, 0, 0, 0 }
local lowY, highY = math.huge, -math.huge
local sum, sumSq = 0, 0
for i, piece in pieces do
	local twin = piecesAgain[i]
	assert(piece.X == twin.X and piece.Z == twin.Z and piece.Kind == twin.Kind and piece.Yaw == twin.Yaw, "pieces are deterministic")
	if piece.Kind == "Cluster" then kinds.Cluster += 1 elseif piece.Kind == "Isle" then kinds.Isle += 1 else kinds.Islet += 1 end
	if piece.Connector then connectors += 1 end
	if piece.Kind == "Islet" then
		local size = piece.ScaleXZ * rules.PadSize
		assert(size >= rules.PadSize - 1e-6 and size <= rules.PadSize * F.MaxScale + 1e-6, "islet size in range")
		if size < rules.PadSize * 1.25 then small += 1 elseif size > rules.PadSize * 1.5 then big += 1 end
	else
		assert(piece.ScaleY >= F.MinStretch - 1e-6 and piece.ScaleY <= math.max(F.MaxStretch, F.IsleMaxScale) + 1e-6, "model stretch in range")
	end
	local q = (if piece.X >= 0 then 1 else 0) + (if piece.Z >= 0 then 2 else 0) + 1
	quadrants[q] += 1
	if not piece.Connector then
		for _, c in fieldKeepOut do
			assert((piece.X - c.X) ^ 2 + (piece.Z - c.Z) ^ 2 >= (c.R + piece.Radius) ^ 2 - 1e-6, "scattered pieces stay clear of islands and the hub")
		end
		for j, other in pieces do
			if j ~= i and not other.Connector then
				local need = piece.Radius + other.Radius + F.WaterGap
				assert((piece.X - other.X) ^ 2 + (piece.Z - other.Z) ^ 2 >= need * need - 1e-6, "scattered pieces never overlap")
			end
		end
	end
end
for _, islet in islets do
	assert(islet.Y >= F.WaterlineY + 2 and islet.Y <= F.MaxTopY + 8, string.format("tops stay above the water and near the hub height (%.2f, %s)", islet.Y, pieces[islet.Piece].Kind))
	assert(pieces[islet.Piece] ~= nil, "every top belongs to a placed piece")
	lowY = math.min(lowY, islet.Y)
	highY = math.max(highY, islet.Y)
	sum += islet.Y
	sumSq += islet.Y * islet.Y
end
local spread = math.sqrt(sumSq / #islets - (sum / #islets) ^ 2)
assert(highY - lowY > 12 and spread > 2.5, string.format("heights vary (%.1f to %.1f, sd %.1f)", lowY, highY, spread))
assert(kinds.Cluster >= 8 and kinds.Isle >= 4, string.format("clusters (%d) and small islands (%d) mix in", kinds.Cluster, kinds.Isle))
assert(kinds.Isle <= F.MaxIsles, "small islands stay bounded")
assert(small > 20 and big > 5, string.format("islet sizes are mixed (%d small, %d big)", small, big))
assert(connectors <= F.MaxRepairs * rules.MaxPads, "bridging stays bounded")
assert(connectors * 3 < #pieces, string.format("bridges are a minority (%d of %d): it reads as noise", connectors, #pieces))
for q = 1, 4 do assert(quadrants[q] > #pieces / 8, "pieces are spread over every part of the lagoon") end
print(string.format("field: %d pieces (%d islets, %d clusters, %d isles), %d tops, %d bridging; heights %.1f-%.1f sd %.1f",
	#pieces, kinds.Islet, kinds.Cluster, kinds.Isle, #islets, connectors, lowY, highY, spread))

-- Seeded generator stays in [0, 1) and repeats for the same seed.
local s1, s2 = ParkourLayout.sequence(5), ParkourLayout.sequence(5)
for _ = 1, 200 do
	local v = s1()
	assert(v >= 0 and v < 1 and v == s2(), "sequence is bounded and deterministic")
end

-- Boulder scatter: bounded, deterministic, clear of keep-out circles and of each other.
local keepOut = { { X = 0, Z = 0, R = 60 } }
for i = 1, Config.PlotCount do
	local c = Config.getIslandCenter(i)
	table.insert(keepOut, { X = c.X, Z = c.Z, R = 100 })
end
local S = Config.Scatter
local rocks = ParkourLayout.scatter(97, S.Count, S.Radius, keepOut, S.MinSpacing, 4)
local twin = ParkourLayout.scatter(97, S.Count, S.Radius, keepOut, S.MinSpacing, 4)
assert(#rocks > S.Count * 0.6 and #rocks <= S.Count, "scatter fills most of the lagoon within its budget")
for i, rock in rocks do
	assert(rock.X == twin[i].X and rock.Z == twin[i].Z, "scatter is deterministic")
	assert(rock.X * rock.X + rock.Z * rock.Z <= S.Radius * S.Radius + 1e-6, "rocks stay inside the scatter disc")
	assert(rock.Variant >= 1 and rock.Variant <= 4 and rock.Scale >= 0.7 and rock.Scale <= 1.6, "variant and scale in range")
	for _, c in keepOut do
		assert((rock.X - c.X) ^ 2 + (rock.Z - c.Z) ^ 2 >= c.R * c.R, "rocks keep clear of islands and the hub")
	end
	for j = i + 1, #rocks do
		local other = rocks[j]
		assert((rock.X - other.X) ^ 2 + (rock.Z - other.Z) ^ 2 >= S.MinSpacing ^ 2, "rocks keep their spacing")
	end
end
assert(#ParkourLayout.scatter(1, 10, 50, { { X = 0, Z = 0, R = 100 } }, 5, 4) == 0, "no room means no rocks, without looping forever")

-- Short and steep routes still respect the limits by adding hops.
check({ X = 0, Y = 0, Z = 0 }, { X = 12, Y = 0, Z = 0 }, 1, "short route")
check({ X = 0, Y = 0, Z = 0 }, { X = 60, Y = 12, Z = 5 }, 2, "climbing route")

assert(not pcall(ParkourLayout.route, { X = 0, Y = 0, Z = 0 }, { X = 30, Y = 20, Z = 5 }, rules, 1), "reject staircase-steep routes")
assert(not pcall(ParkourLayout.route, { X = 0, Y = 0, Z = 0 }, { X = 0, Y = 0, Z = 0 }, rules, 1), "reject zero-length routes")
assert(not pcall(ParkourLayout.route, { X = 0, Y = 0, Z = 0 }, { X = 2000, Y = 0, Z = 0 }, rules, 1), "reject routes over the pad budget")
print("Parkour layout tests passed")
