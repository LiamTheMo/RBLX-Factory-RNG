--!strict
-- Lagoon parkour layout. Pure, deterministic math so the jump limits and connectivity are
-- unit-tested; the server only clones islet models onto the returned points.
--
-- The lagoon is "noise": groups of loose islets, stepped rock clusters and small islands at
-- widely varying heights, scattered everywhere with no visible paths. After scattering, a
-- one-way jump graph is built (climbs limited, drops allowed) and, only where an island cannot
-- reach the hub or the hub cannot reach an island, the fewest extra islets are dropped in across
-- the narrowest gap. Every island and the hub stay reachable, but players find their own way.

export type Point = { X: number, Y: number, Z: number }
export type Rules = { MaxGap: number, MaxRise: number, MaxDrop: number, PadSize: number, Zigzag: number, MaxPads: number }
export type Circle = { X: number, Z: number, R: number }
export type Rock = { X: number, Z: number, Scale: number, Yaw: number, Variant: number }
-- One walkable top. Size is its width in studs; Connector marks gap-bridging islets; Piece is
-- the index of the placed model it belongs to.
export type Islet = { X: number, Y: number, Z: number, Size: number, Connector: boolean, Piece: number }
-- A placed model: Kind "Islet" (Y = top height; the builder picks the variant and its Y scale),
-- "Cluster" or "Isle" (Shape names the catalog model; Y = waterline). Radius = footprint.
export type Piece = {
	Kind: string, Shape: string?, X: number, Y: number, Z: number, Yaw: number,
	ScaleXZ: number, ScaleY: number, Radius: number, Connector: boolean,
}
-- Catalog models (IsletCatalog): walkable tops relative to the waterline pivot, W = top width.
export type Shape = { Name: string, Radius: number, Tops: { { X: number, Y: number, Z: number, W: number } } }
export type Catalog = { Clusters: { Shape }, Isles: { Shape } }
-- An island or the hub: its walkable ledge points around the shore (found by raycasts in game).
export type Anchor = { Ledges: { Point } }
export type FieldRules = {
	Clusters: number, ClusterSpacing: number, ClusterRadius: number, Region: number,
	MinPerCluster: number, MaxPerCluster: number, MinScale: number, MaxScale: number,
	BaseRatio: number, WaterGap: number, MaxPieces: number, MaxRepairs: number,
	WaterlineY: number, MinTopY: number, MaxTopY: number, HeightSpread: number, MemberSpread: number,
	IsleChance: number, ClusterChance: number, MaxIsles: number, IsleMinScale: number, IsleMaxScale: number,
	MinStretch: number, MaxStretch: number, Wander: number, DecoyChance: number, GoalPull: number,
}

local ParkourLayout = {}

-- Small deterministic generator (plain Luau has no Random class): values in [0, 1).
function ParkourLayout.sequence(seed: number): () -> number
	local state = (math.floor(seed) * 2654435761 + 12345) % 4294967296
	return function(): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

-- Stepping islets (PadSize wide) from one walkable point to another. Islet to islet the full gap
-- is open water (centres up to MaxGap + PadSize apart); ledge to islet only half an islet sits
-- between. Each hop also stays under MaxRise. Used to bridge gaps the noise left open.
function ParkourLayout.route(from: Point, to: Point, rules: Rules, seed: number): { Point }
	assert(rules.MaxGap > 0 and rules.PadSize > 0 and rules.MaxRise > 0, "invalid parkour rules")
	local dx, dz = to.X - from.X, to.Z - from.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	assert(distance > 0, "parkour endpoints must differ")
	local ux, uz = dx / distance, dz / distance
	local rise = to.Y - from.Y
	local slope = math.abs(rise) / distance
	local climbCap = if slope > 0 then rules.MaxRise / slope else math.huge
	local endReach = math.min((rules.MaxGap + rules.PadSize / 2) * 0.95, climbCap)
	local innerReach = math.min(math.sqrt(math.max((rules.MaxGap + rules.PadSize) ^ 2 - (2 * rules.Zigzag) ^ 2, 1)) * 0.95, climbCap)
	local stations: { number } = {}
	if distance <= 2 * endReach then
		stations = { distance / 2 }
	else
		local inner = distance - 2 * endReach
		local hops = math.ceil(inner / innerReach)
		for j = 0, hops do table.insert(stations, endReach + inner * j / hops) end
	end
	assert(#stations <= rules.MaxPads, "parkour route is longer than the pad budget")
	assert(#stations < 2 or (stations[2] - stations[1]) > rules.PadSize, "parkour route is too steep for separate pads")

	local nextValue = ParkourLayout.sequence(seed)
	local shortest = if #stations > 1 then stations[2] - stations[1] else distance / 2
	local wobble = math.max(0, math.min(0.8, (rules.MaxRise - slope * math.max(shortest, endReach)) / 2))
	local pads = {}
	for i, along in stations do
		local t = along / distance
		local endPad = i == 1 or i == #stations
		local side = if endPad then 0 else (nextValue() * 2 - 1) * rules.Zigzag
		local lift = if endPad then 0 else (nextValue() * 2 - 1) * wobble
		table.insert(pads, { X = from.X + dx * t - uz * side, Y = from.Y + rise * t + lift, Z = from.Z + dz * t + ux * side })
	end
	return pads
end

-- Edge-to-edge horizontal gap and climb for every hop, endpoints included (for tests and debugging).
function ParkourLayout.hops(from: Point, to: Point, pads: { Point }, padSize: number): { { Gap: number, Rise: number } }
	local nodes: { Point } = { from }
	for _, pad in pads do table.insert(nodes, pad) end
	table.insert(nodes, to)
	local result = {}
	for i = 1, #nodes - 1 do
		local a, b = nodes[i], nodes[i + 1]
		local centre = math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
		local padEdges = (if i > 1 then padSize / 2 else 0) + (if i < #nodes - 1 then padSize / 2 else 0)
		table.insert(result, { Gap = centre - padEdges, Rise = b.Y - a.Y })
	end
	return result
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
function ParkourLayout.shoreFan(cx: number, cz: number, bearings: { number }, distances: { number },
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
function ParkourLayout.scatter(seed: number, count: number, radius: number, keepOut: { Circle },
	minSpacing: number, variants: number): { Rock }
	local nextValue = ParkourLayout.sequence(seed)
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

-- Can a player jump between these two points either way? `sizeA`/`sizeB` are walkable top
-- widths (0 for an island or hub ledge). Used for bridge routes.
function ParkourLayout.canJump(a: Point, sizeA: number, b: Point, sizeB: number, rules: Rules): boolean
	local gap = math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) - (sizeA + sizeB) / 2
	return gap <= rules.MaxGap and math.abs(a.Y - b.Y) <= rules.MaxRise
end

-- One way: can a player standing on `a` land on `b`? Climbs are limited by MaxRise, drops by
-- MaxDrop, so a tall rock can be a way down without being a way back up.
function ParkourLayout.canStep(a: Point, sizeA: number, b: Point, sizeB: number, rules: Rules): boolean
	local gap = math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) - (sizeA + sizeB) / 2
	local rise = b.Y - a.Y
	return gap <= rules.MaxGap and rise <= rules.MaxRise and -rise <= rules.MaxDrop
end

-- Directed jump graph over anchors (1..#anchors, each one walkable node) and islet tops
-- (#anchors + i). Returns outgoing and incoming adjacency lists.
local function graph(anchors: { Anchor }, islets: { Islet }, rules: Rules): ({ { number } }, { { number } })
	local na = #anchors
	local out, inn = {}, {}
	for i = 1, na + #islets do
		out[i] = {}
		inn[i] = {}
	end
	local function link(u: number, v: number)
		table.insert(out[u], v)
		table.insert(inn[v], u)
	end
	for i, a in islets do
		for j, b in islets do
			if i ~= j and ParkourLayout.canStep(a, a.Size, b, b.Size, rules) then link(na + i, na + j) end
		end
		for k, anchor in anchors do
			local off, on = false, false
			for _, ledge in anchor.Ledges do
				off = off or ParkourLayout.canStep(ledge, 0, a, a.Size, rules)
				on = on or ParkourLayout.canStep(a, a.Size, ledge, 0, rules)
				if off and on then break end
			end
			if off then link(k, na + i) end
			if on then link(na + i, k) end
		end
	end
	return out, inn
end

-- Every node reachable from `start` along `adjacency` (breadth-first, bounded by the node count).
local function reach(start: number, adjacency: { { number } }): { [number]: boolean }
	local seen = { [start] = true }
	local queue, head = { start }, 1
	while head <= #queue do
		for _, v in adjacency[queue[head]] do
			if not seen[v] then
				seen[v] = true
				table.insert(queue, v)
			end
		end
		head += 1
	end
	return seen
end

-- True when every island can reach the hub (anchor 1) and the hub can reach every island.
function ParkourLayout.allConnected(anchors: { Anchor }, islets: { Islet }, rules: Rules): boolean
	local out, inn = graph(anchors, islets, rules)
	local fromHub, toHub = reach(1, out), reach(1, inn)
	for a = 2, #anchors do
		if not (fromHub[a] and toHub[a]) then return false end
	end
	return true
end

-- The noise field. Groups are scattered over the whole lagoon; each is a few loose islets, one
-- stepped rock cluster or a small island, at its own height: heightAt(x, z) (rising toward the
-- hub) plus a wide random offset, so neighbouring groups differ and players pick their way up
-- and down. Bounded: at most MaxPieces placed models and MaxRepairs bridges.
function ParkourLayout.field(seed: number, anchors: { Anchor }, keepOut: { Circle },
	heightAt: (number, number) -> number, field: FieldRules, rules: Rules, catalog: Catalog): ({ Islet }, { Piece })
	local nextValue = ParkourLayout.sequence(seed)
	local islets: { Islet } = {}
	local pieces: { Piece } = {}
	local function between(lo: number, hi: number): number
		return lo + nextValue() * (hi - lo)
	end
	-- `shoreRadius` is the part that must clear islands and the hub (bridge rocks pass only their
	-- walkable top, so their bases may lean on the shore rocks); `radius` keeps clear of other rocks.
	local function fits(x: number, z: number, radius: number, shoreRadius: number?): boolean
		if not outside(x, z, keepOut, shoreRadius or radius) then return false end
		for _, p in pieces do
			local need = radius + p.Radius + field.WaterGap
			if (x - p.X) ^ 2 + (z - p.Z) ^ 2 < need * need then return false end
		end
		return true
	end
	local function addIslet(x: number, y: number, z: number, size: number, connector: boolean)
		table.insert(pieces, {
			Kind = "Islet", Shape = nil, X = x, Y = y, Z = z, Yaw = nextValue() * math.pi * 2,
			ScaleXZ = size / rules.PadSize, ScaleY = 0, Radius = size / 2 * field.BaseRatio, Connector = connector,
		})
		table.insert(islets, { X = x, Y = y, Z = z, Size = size, Connector = connector, Piece = #pieces })
	end
	-- A cluster or small island: its walkable tops, rotated by yaw (Roblox CFrame.Angles(0, yaw, 0))
	-- and scaled about the waterline pivot exactly as the builder places the model.
	local function addShape(kind: string, shape: Shape, x: number, z: number, scaleXZ: number, scaleY: number)
		local yaw = nextValue() * math.pi * 2
		local c, s = math.cos(yaw), math.sin(yaw)
		table.insert(pieces, {
			Kind = kind, Shape = shape.Name, X = x, Y = field.WaterlineY, Z = z, Yaw = yaw,
			ScaleXZ = scaleXZ, ScaleY = scaleY, Radius = shape.Radius * scaleXZ, Connector = false,
		})
		for _, t in shape.Tops do
			table.insert(islets, {
				X = x + (t.X * c + t.Z * s) * scaleXZ, Y = field.WaterlineY + t.Y * scaleY,
				Z = z + (-t.X * s + t.Z * c) * scaleXZ, Size = t.W * scaleXZ, Connector = false, Piece = #pieces,
			})
		end
	end

	-- 1. Group centres scattered over the whole lagoon.
	local centres: { Circle } = {}
	local attempts = 0
	while #centres < field.Clusters and attempts < field.Clusters * 40 do
		attempts += 1
		local angle, r = nextValue() * math.pi * 2, math.sqrt(nextValue()) * field.Region
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		local clear = outside(x, z, keepOut, 4)
		if clear then
			for _, c in centres do
				if (x - c.X) ^ 2 + (z - c.Z) ^ 2 < field.ClusterSpacing ^ 2 then clear = false; break end
			end
		end
		if clear then table.insert(centres, { X = x, Z = z, R = field.ClusterRadius }) end
	end

	-- 2. Each group: a small island, a stepped cluster, or 1..N loose islets of mixed sizes. Kinds
	-- and heights are rolled first; the big pieces are placed first so they always find room.
	local plans = {}
	for _, c in centres do
		local base = math.clamp(heightAt(c.X, c.Z) + (nextValue() * 2 - 1) * field.HeightSpread, field.MinTopY, field.MaxTopY)
		local roll = nextValue()
		local kind = if roll < field.IsleChance then 1 elseif roll < field.IsleChance + field.ClusterChance then 2 else 3
		table.insert(plans, { C = c, Base = base, Kind = kind })
	end
	local budget = field.MaxPieces - field.MaxRepairs * 2
	local isles = 0
	for pass = 1, 3 do
		for _, plan in plans do
			if plan.Kind ~= pass or #pieces >= budget then continue end
			local c, base = plan.C, plan.Base
			if pass == 1 and isles < field.MaxIsles and #catalog.Isles > 0 then
				local shape = catalog.Isles[1 + math.floor(nextValue() * #catalog.Isles) % #catalog.Isles]
				local scale = between(field.IsleMinScale, field.IsleMaxScale)
				for try = 0, 5 do
					local angle, r = nextValue() * math.pi * 2, try * c.R * 0.4
					local x, z = c.X + math.cos(angle) * r, c.Z + math.sin(angle) * r
					if fits(x, z, shape.Radius * scale) then
						addShape("Isle", shape, x, z, scale, scale)
						isles += 1
						break
					end
				end
			elseif pass == 2 and #catalog.Clusters > 0 then
				local shape = catalog.Clusters[1 + math.floor(nextValue() * #catalog.Clusters) % #catalog.Clusters]
				local lowest = math.huge
				for _, t in shape.Tops do lowest = math.min(lowest, t.Y) end
				-- Stretch so the lowest step lands near the group height; steps stay climbable.
				local stretch = math.clamp((base - field.WaterlineY) / lowest, field.MinStretch, field.MaxStretch)
				local scale = between(0.9, 1.15)
				for _ = 1, 4 do
					local angle, r = nextValue() * math.pi * 2, nextValue() * c.R * 0.5
					local x, z = c.X + math.cos(angle) * r, c.Z + math.sin(angle) * r
					if fits(x, z, shape.Radius * scale) then
						addShape("Cluster", shape, x, z, scale, stretch)
						break
					end
				end
			elseif pass == 3 then
				local count = field.MinPerCluster + math.floor(nextValue() * (field.MaxPerCluster - field.MinPerCluster + 1))
				for _ = 1, count do
					for _ = 1, 6 do
						local angle, r = nextValue() * math.pi * 2, nextValue() * c.R
						local x, z = c.X + math.cos(angle) * r, c.Z + math.sin(angle) * r
						-- Skewed toward small islets, with the occasional big flat rock to rest on.
						local size = rules.PadSize * (field.MinScale + nextValue() ^ 1.8 * (field.MaxScale - field.MinScale))
						if fits(x, z, size / 2 * field.BaseRatio) then
							local y = math.clamp(base + (nextValue() * 2 - 1) * field.MemberSpread, field.MinTopY, field.MaxTopY)
							addIslet(x, y, z, size, false)
							break
						end
					end
				end
			end
		end
	end

	-- 3. Bridge only where an island cannot reach the hub or the hub cannot reach an island: from
	-- what one side reaches toward what reaches the other, across the narrowest gap. A bridge
	-- wanders (each rock turns up to field.Wander off the heading, with mixed sizes and heights,
	-- clear of shores and other rocks) and drops a few dead-end side rocks, so it reads as more
	-- scattered rocks rather than a line. Bridge hops work both ways.
	local function rollback(count: number, pieceCount: number)
		while #islets > count do table.remove(islets) end
		while #pieces > pieceCount do table.remove(pieces) end
	end
	local function both(a: Point, sizeA: number, b: Point, sizeB: number): boolean
		return ParkourLayout.canStep(a, sizeA, b, sizeB, rules) and ParkourLayout.canStep(b, sizeB, a, sizeA, rules)
	end
	-- Bridge effort between two tops: the open-water gap, or the ground the hops needed for the
	-- height difference would cover, whichever is longer.
	local limit = rules.MaxRise * 0.85
	local hopLength = rules.PadSize + rules.MaxGap * 0.6
	local function effort(a: Point, sizeA: number, b: Point, sizeB: number): number
		local gap = math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) - (sizeA + sizeB) / 2
		return math.max(gap, (math.abs(a.Y - b.Y) / limit - 1) * hopLength)
	end
	local function wander(from: Point, fromSize: number, to: Point, toSize: number): boolean
		local count, pieceCount = #islets, #pieces
		local cur, curSize = from, fromSize
		for _ = 1, rules.MaxPads do
			if both(cur, curSize, to, toSize) then
				-- Dead-end side rocks off some of the bridge: a choice, not a single line.
				for i = count + 1, #islets do
					local stone = islets[i]
					if nextValue() < field.DecoyChance and #pieces < field.MaxPieces then
						local size = rules.PadSize * between(1, 1.4)
						local angle = nextValue() * math.pi * 2
						local step = stone.Size / 2 + size / 2 + between(2, rules.MaxGap)
						local x, z = stone.X + math.cos(angle) * step, stone.Z + math.sin(angle) * step
						if fits(x, z, size / 2 * 1.2, size / 2) then
							local y = math.clamp(stone.Y + (nextValue() * 2 - 1) * rules.MaxRise * 1.6, field.MinTopY, field.MaxTopY)
							addIslet(x, y, z, size, true)
						end
					end
				end
				return true
			end
			local placed = false
			local start = effort(cur, curSize, to, toSize)
			local heading = math.atan2(to.Z - cur.Z, to.X - cur.X)
			for try = 1, 40 do
				local size = rules.PadSize * between(1, if try > 20 then 1.1 else 1.45)
				local gap = between(1.5, rules.MaxGap * 0.9)
				-- Mostly toward the target; later tries swing wider so a bridge can climb in a curve.
				local turn = (nextValue() * 2 - 1) * (if try > 12 then math.pi * 0.8 else field.Wander)
				local step = curSize / 2 + size / 2 + gap
				local x, z = cur.X + math.cos(heading + turn) * step, cur.Z + math.sin(heading + turn) * step
				-- Head for the target height, never more than 85% of the climb limit per hop.
				local y = math.clamp(cur.Y + math.clamp(to.Y - cur.Y, -limit, limit) + (nextValue() * 2 - 1),
					math.max(field.MinTopY, cur.Y - limit), math.min(field.MaxTopY, cur.Y + limit))
				local p = { X = x, Y = y, Z = z }
				if effort(p, size, to, toSize) < start - 1 and fits(x, z, size / 2 * 1.2, size / 2) then
					addIslet(x, y, z, size, true)
					cur, curSize = islets[#islets], size
					placed = true
					break
				end
			end
			if not placed or #pieces >= field.MaxPieces then break end
		end
		rollback(count, pieceCount)
		return false
	end

	local na = #anchors
	for _ = 1, field.MaxRepairs do
		local out, inn = graph(anchors, islets, rules)
		local fromHub, toHub = reach(1, out), reach(1, inn)
		local src, dst
		for a = 2, na do
			if not toHub[a] then
				src, dst = reach(a, out), toHub
				break
			elseif not fromHub[a] then
				src, dst = fromHub, reach(a, inn)
				break
			end
		end
		if not src or not dst then break end
		local function pointsOf(set: { [number]: boolean }): { { P: Point, Size: number } }
			local list = {}
			for node = 1, na + #islets do
				if set[node] then
					if node <= na then
						for _, ledge in anchors[node].Ledges do table.insert(list, { P = ledge, Size = 0 }) end
					else
						local islet = islets[node - na]
						table.insert(list, { P = { X = islet.X, Y = islet.Y, Z = islet.Z }, Size = islet.Size })
					end
				end
			end
			return list
		end
		-- Link the stranded side to the nearest group it cannot yet reach, steered toward the goal:
		-- each repair is a short hop between neighbouring groups, never one long line.
		local froms, goals = pointsOf(src), pointsOf(dst)
		local others = {}
		for node = 1, na + #islets do
			if not src[node] then others[node] = true end
		end
		local candidates: { { A: { P: Point, Size: number }, B: { P: Point, Size: number }, Score: number, Key: number } } = {}
		for j, b in pointsOf(others) do
			local toGoal = math.huge
			for _, g in goals do
				toGoal = math.min(toGoal, math.sqrt((b.P.X - g.P.X) ^ 2 + (b.P.Z - g.P.Z) ^ 2))
			end
			local best, from = math.huge, nil
			for _, a in froms do
				local e = effort(a.P, a.Size, b.P, b.Size)
				if e < best then best, from = e, a end
			end
			if from then
				table.insert(candidates, { A = from, B = b, Score = best + toGoal * field.GoalPull, Key = j })
			end
		end
		table.sort(candidates, function(p: { Score: number, Key: number }, q: { Score: number, Key: number })
			if p.Score ~= q.Score then return p.Score < q.Score end
			return p.Key < q.Key
		end)
		local bridged = false
		for k = 1, math.min(#candidates, 40) do
			local pair = candidates[k]
			if wander(pair.A.P, pair.A.Size, pair.B.P, pair.B.Size) then
				bridged = true
				break
			end
		end
		-- Fallback where the lagoon is too crowded to wander: a straight zigzag of rocks, which
		-- may lean on neighbouring rocks but always keeps the hub reachable.
		for k = 1, if bridged then 0 else math.min(#candidates, 10) do
			local pair = candidates[k]
			local ok, pads = pcall(ParkourLayout.route, pair.A.P, pair.B.P, rules, seed + k)
			if ok and #pieces + #pads <= field.MaxPieces then
				for _, pad in pads do
					local covered = false
					for _, other in islets do
						if (pad.X - other.X) ^ 2 + (pad.Z - other.Z) ^ 2 < (other.Size / 2) ^ 2
							and math.abs(pad.Y - other.Y) <= rules.MaxRise / 2 then
							covered = true
							break
						end
					end
					if not covered then addIslet(pad.X, pad.Y, pad.Z, rules.PadSize, true) end
				end
				bridged = true
				break
			end
		end
		if not bridged then break end
	end
	return islets, pieces
end

return ParkourLayout
