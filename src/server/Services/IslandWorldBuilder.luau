--!nonstrict
-- Builds the island world. Preferred path: clone the imported low-poly island (and hub, when
-- modeled) from ServerStorage.IslandAssets per plot, scatter the lagoon with islets, stepped rock
-- clusters and small islands (ParkourLayout.field), and fill Terrain water. Fallback: the original
-- native-part map, so a place without the imported models still runs.
local ServerStorage = game:GetService("ServerStorage")
local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.IslandWorldConfig)
local ParkourLayout = require(Shared.ParkourLayout)
local IsletCatalog = require(Shared.IsletCatalog)
local Builder = {}
local C = {
	Grass = Color3.fromRGB(159, 209, 74), GrassLight = Color3.fromRGB(185, 225, 91),
	Sand = Color3.fromRGB(224, 189, 133), Cliff = Color3.fromRGB(197, 162, 111),
	Rock = Color3.fromRGB(117, 130, 137), Wood = Color3.fromRGB(149, 97, 54),
	DarkWood = Color3.fromRGB(89, 58, 38), Amber = Color3.fromRGB(255, 186, 69),
	Roof = Color3.fromRGB(204, 97, 47), Leaf = Color3.fromRGB(70, 166, 91),
	Pine = Color3.fromRGB(32, 139, 100), Water = Color3.fromRGB(42, 178, 205),
}

local function part(parent, name, size, cf, color, material, collide, class)
	local p = Instance.new(class or "Part")
	p.Name, p.Size, p.CFrame = name, size, cf
	p.Color, p.Material = color, material or Enum.Material.SmoothPlastic
	p.Anchored, p.CanCollide = true, collide == true
	p.CanTouch = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function beam(parent, name, a, b, width, color, material, collide)
	return part(parent, name, Vector3.new(width, width, (b-a).Magnitude), CFrame.lookAt((a+b)/2, b), color, material, collide)
end

local function ball(parent, name, pos, size, color)
	local p = part(parent, name, size, CFrame.new(pos), color)
	p.Shape = Enum.PartType.Ball
	return p
end

local function polygon(parent, center, rx, rz, height, color, seed)
	-- An overlapping fan of triangular wedges makes a solid, flat polygonal top.
	-- Broad, invisible strips provide reliable collision across wedge seams.
	for strip = -5, 5 do
		local z = strip * rz / 6
		local halfWidth = rx * math.sqrt(1 - (math.abs(z) / rz)^2) * 0.88
		local floor = part(parent, "LandCollision", Vector3.new(halfWidth * 2, height, rz / 6 + 0.08),
			CFrame.new(center + Vector3.new(0, 0, z)), color, Enum.Material.SmoothPlastic, true)
		floor.Transparency = 1
		floor:SetAttribute("LandSurface", true)
	end
	local rng = Random.new(seed)
	local vertices = {}
	for i = 1, 16 do
		local angle = (i-1)*math.pi/8
		local radius = rng:NextNumber(0.95, 1.05)
		vertices[i] = center + Vector3.new(math.cos(angle)*rx*radius, 0, math.sin(angle)*rz*radius)
	end
	for i = 1, 16 do
		local a,b = vertices[i], vertices[i%16+1]
		local edge = b-a
		local along = edge.Unit
		local mid = a + along * (center-a):Dot(along)
		local inward = (center-mid).Unit
		local depth = (center-mid).Magnitude
		for _, endpoint in {a,b} do
			local width = (endpoint-mid).Magnitude
			local direction = (endpoint-mid).Unit
			local wedge = part(parent, "Facet", Vector3.new(height, depth, width+0.05),
				CFrame.fromMatrix((center+endpoint)/2, inward:Cross(-direction), inward, -direction), color, Enum.Material.SmoothPlastic, false, "WedgePart")
			wedge.CanQuery = false
			-- Wedge local X is vertical; local Y/Z describe the fan triangle.
			wedge:SetAttribute("LandSurface", true)
		end
	end
	return vertices
end

local function island(parent, center, rx, rz, top, seed)
	local group = Instance.new("Model")
	group.Name = "Landform"
	group.Parent = parent
	polygon(group, center+Vector3.new(0, top-0.6, 0), rx, rz, 1.2, C.Grass, seed)
	polygon(group, center+Vector3.new(0, top-2.0, 0), rx*1.02, rz*1.02, 1.8, C.Sand, seed)
	polygon(group, center+Vector3.new(0, (top-4)/2-3, 0), rx*0.98, rz*0.98, top+4, C.Cliff, seed)
	-- Shore accents remain noncolliding and do not block land raycasts.
	for i = 1, 24 do
		local a = i*math.pi/12
		local p = part(group, "ShoreFoam", Vector3.new(5.5, 0.08, 1.2),
			CFrame.new(center+Vector3.new(math.cos(a)*rx*1.03, Config.WaterY+0.12, math.sin(a)*rz*1.03))*CFrame.Angles(0,-a+math.pi/2,0), Color3.fromRGB(213,248,245))
		p.Transparency = 0.25
	end
end

local function tree(parent, pos, scale, pine, tint)
	local group = Instance.new("Model")
	group.Name = if pine then "Pine" else "MeadowTree"
	group.Parent = parent
	part(group,"Trunk",Vector3.new(1.5,7,1.5)*scale,CFrame.new(pos+Vector3.new(0,3.5*scale,0)),C.Wood,Enum.Material.Wood,true)
	if pine then
		for layer = 1,3 do
			local radius = (7-layer*1.3)*scale
			local y = (5+layer*2.4)*scale
			for face = 0,3 do
				part(group,"PineCrown",Vector3.new(radius, radius*1.3, radius),
					CFrame.new(pos+Vector3.new(0,y,0))*CFrame.Angles(0,face*math.pi/2,0),tint or C.Pine,nil,false,"WedgePart")
			end
		end
	else
		for i=0,3 do
			local a=i*math.pi/2
			ball(group,"LeafCluster",pos+Vector3.new(math.cos(a)*2.2*scale, (8+i%2)*scale,math.sin(a)*2.2*scale),Vector3.new(7,6,7)*scale,tint or C.Leaf)
		end
	end
end

local function flowers(parent, pos, seed)
	local rng = Random.new(seed)
	local colors = {Color3.fromRGB(255,221,78),Color3.fromRGB(245,149,190),Color3.fromRGB(117,216,237),Color3.fromRGB(250,248,222)}
	for i=1,3 do
		local base=pos+Vector3.new(rng:NextNumber(-2,2),0,rng:NextNumber(-2,2))
		ball(parent,"MeadowShrub",base+Vector3.new(0,0.65,0),Vector3.new(2.3,1.5,2),Color3.fromRGB(65,179,125))
		local c=colors[(seed+i)%4+1]
		for petal=0,3 do
			local a=petal*math.pi/2
			ball(parent,"Petal",base+Vector3.new(math.cos(a)*0.45,1.4,math.sin(a)*0.45),Vector3.new(0.65,0.25,0.65),c)
		end
		ball(parent,"FlowerCenter",base+Vector3.new(0,1.5,0),Vector3.new(0.35,0.25,0.35),C.Amber)
	end
end

local function lantern(parent, pos)
	part(parent,"LampPost",Vector3.new(0.65,7,0.65),CFrame.new(pos+Vector3.new(0,3.5,0)),C.DarkWood,Enum.Material.Wood,true)
	part(parent,"LanternBase",Vector3.new(1.8,0.25,1.8),CFrame.new(pos+Vector3.new(0,7,0)),C.DarkWood)
	local glow=part(parent,"AmberLantern",Vector3.new(1.2,1.8,1.2),CFrame.new(pos+Vector3.new(0,8,0)),C.Amber,Enum.Material.Neon)
	part(parent,"LanternCap",Vector3.new(2,0.3,2),CFrame.new(pos+Vector3.new(0,9,0)),C.DarkWood)
	local light=Instance.new("PointLight")
	light.Color,light.Brightness,light.Range=C.Amber,0.5,13
	light.Parent=glow
end

local function cabin(parent, pos, scale, name)
	local model=Instance.new("Model")
	model.Name=name or "WorkshopCabin"
	model.Parent=parent
	local function p(n,s,o,c,m,collide)
		return part(model,n,s*scale,CFrame.new(pos+o*scale),c,m,collide)
	end
	p("Floor",Vector3.new(16,0.7,13),Vector3.new(0,0.35,0),C.Wood,Enum.Material.WoodPlanks,true)
	p("BackWall",Vector3.new(16,9,0.7),Vector3.new(0,5,-6),C.Wood,Enum.Material.WoodPlanks,true)
	for _,x in {-7.6,7.6} do p("SideWall",Vector3.new(0.7,9,12),Vector3.new(x,5,0),C.Wood,Enum.Material.WoodPlanks,true) end
	for _,x in {-5.3,5.3} do p("FrontWall",Vector3.new(5.3,9,0.7),Vector3.new(x,5,6),C.Wood,Enum.Material.WoodPlanks,true) end
	p("DoorLintel",Vector3.new(5.3,2.5,0.7),Vector3.new(0,8.25,6),C.Wood,Enum.Material.WoodPlanks,true)
	for _,x in {-7.7,7.7} do for _,z in {-6,6} do p("CornerBeam",Vector3.new(0.9,10,0.9),Vector3.new(x,5,z),C.DarkWood,Enum.Material.Wood,true) end end
	for _,side in {-1,1} do
		local roof=p("TerracottaRoof",Vector3.new(10.3,0.7,16),Vector3.new(side*4.4,11,0),C.Roof,Enum.Material.SmoothPlastic,true)
		roof.CFrame *= CFrame.Angles(0,0,-side*math.rad(25))
		for stripe=-3,3 do
			local rib=p("RoofTileSeam",Vector3.new(10.3,0.14,0.12),Vector3.new(side*4.4,11.4,stripe*2),Color3.fromRGB(228,129,61))
			rib.CFrame *= CFrame.Angles(0,0,-side*math.rad(25))
		end
	end
	p("RidgeCap",Vector3.new(0.8,0.6,16.5),Vector3.new(0,13,0),C.Roof)
	p("Chimney",Vector3.new(1.5,6,1.5),Vector3.new(4,13,-3),Color3.fromRGB(228,222,201),Enum.Material.Brick,true)
	for _,x in {-5.4,5.4} do
		p("WindowFrame",Vector3.new(2.6,3.3,0.4),Vector3.new(x,5.5,6.5),C.DarkWood)
		p("WarmWindow",Vector3.new(2.1,2.7,0.2),Vector3.new(x,5.5,6.75),C.Amber,Enum.Material.Neon)
		p("WindowMullion",Vector3.new(0.2,2.8,0.25),Vector3.new(x,5.5,6.9),C.DarkWood)
	end
	p("Porch",Vector3.new(18,0.6,5),Vector3.new(0,0.3,9),C.Wood,Enum.Material.WoodPlanks,true)
	return model
end

local function walkway(parent, a, b, width, rails)
	local length=(b-a).Magnitude
	local cf=CFrame.lookAt((a+b)/2,b)
	part(parent,"WalkwayCollision",Vector3.new(width,0.6,length+1),cf,C.Wood,Enum.Material.WoodPlanks,true)
	local count=math.ceil(length/2.5)
	for i=0,count do
		local t=i/count
		local point=a:Lerp(b,t)
		part(parent,"TimberPlank",Vector3.new(width+0.25,0.2,2.1),CFrame.new(point)*cf.Rotation,C.Wood,Enum.Material.WoodPlanks)
		if rails and i%4==0 then
			for _,side in {-1,1} do
				local post=point+cf.RightVector*(width/2-0.3)*side
				part(parent,"BridgePost",Vector3.new(0.65,4.5,0.65),CFrame.new(post+Vector3.new(0,2,0)),C.DarkWood,Enum.Material.Wood,true)
			end
		end
	end
	if rails then
		for _,side in {-1,1} do
			local offset=cf.RightVector*(width/2-0.3)*side+Vector3.new(0,3.6,0)
			beam(parent,"BridgeHandrail",a+offset,b+offset,0.45,C.DarkWood,Enum.Material.Wood,true)
		end
	end
end

local function playerIsland(parent,index)
	local data=Config.getPlotOrigin(index)
	local islandCenter=Config.getIslandCenter(index)
	local center=Vector3.new(islandCenter.X,0,islandCenter.Z)
	local model=Instance.new("Model")
	model.Name=string.format("StarterIsland_%02d",index)
	model:SetAttribute("PlotIndex",index)
	island(model,center,51,39,Config.GroundY,100+index)
	local y=Config.GroundY
	-- Raised garden behind the factory; clear center is reserved for all five slots.
	polygon(model,center+Vector3.new(-26,y+3,-22),16,12,6,C.Sand,300+index)
	polygon(model,center+Vector3.new(-26,y+6.1,-22),16,12,0.5,C.GrassLight,300+index)
	cabin(model,center+Vector3.new(28,y,-23),0.85)
	for i=1,11 do
		local a=(i+0.35)*math.pi*2/12
		local pos=center+Vector3.new(math.cos(a)*42,y,math.sin(a)*31)
		if not (pos.X>center.X+15 and pos.Z<center.Z-16) and math.abs(pos.X-center.X)>9 then
			tree(model,pos,0.65+(i%3)*0.12,i%3~=0,if i%4==0 then Color3.fromRGB(194,213,66) elseif i%5==0 then Color3.fromRGB(230,150,193) else nil)
			flowers(model,pos+Vector3.new(-3,0,1),index*20+i)
			local rock=part(model,"SandstoneBoulder",Vector3.new(3.8,2.7,3.5),CFrame.new(pos+Vector3.new(3,1.2,1))*CFrame.Angles(0,i,0.15),C.Sand)
			rock.Shape=Enum.PartType.Ball
		end
	end
	for i=0,10 do
		local a=-0.2+i*math.pi/24
		part(model,"GardenPath",Vector3.new(5.5,0.08,4),CFrame.new(center+Vector3.new(math.sin(a)*27,y+0.05,13+math.cos(a)*9))*CFrame.Angles(0,a,0),C.Sand)
	end
	walkway(model,center+Vector3.new(0,y,30),center+Vector3.new(0,y,48),9,false)
	for _,x in {-4,4} do for _,z in {35,46} do part(model,"DockPile",Vector3.new(1.2,16,1.2),CFrame.new(center+Vector3.new(x,1,z)),C.Wood,Enum.Material.Wood,true) end end
	lantern(model,center+Vector3.new(-6,y,29))
	local marker=part(model,"FactoryOrigin",Vector3.new(1,1,1),CFrame.new(data.X,data.Y,data.Z),C.Amber)
	marker.Transparency=1
	marker.CanQuery=false
	local spawn=part(model,"IslandSpawn",Vector3.new(5,0.4,5),CFrame.new(center+Vector3.new(0,y+0.25,15)),C.Sand,nil,false,"SpawnLocation")
	spawn.Transparency=1
	spawn.Neutral,spawn.Enabled,spawn.Duration=true,false,0
	model.Parent=parent
	task.wait()
end

local function hub(parent)
	local model=Instance.new("Model")
	model.Name="TreehouseMesa"
	island(model,Vector3.zero,69,66,8,55)
	polygon(model,Vector3.new(0,17,0),45,43,18,C.Rock,56)
	polygon(model,Vector3.new(0,26.2,0),45,43,0.7,C.Grass,56)
	polygon(model,Vector3.new(0,38,0),28,25,24,C.Rock,57)
	polygon(model,Vector3.new(0,50.3,0),28,25,0.8,C.GrassLight,57)
	-- Broad switchback boardwalks climb each terrace without jump-only navigation.
	walkway(model,Vector3.new(62,8,25),Vector3.new(38,26.6,25),10,true)
	walkway(model,Vector3.new(38,26.6,25),Vector3.new(-34,26.6,25),10,true)
	walkway(model,Vector3.new(-34,26.6,25),Vector3.new(-34,50.8,-18),10,true)
	walkway(model,Vector3.new(-34,50.8,-18),Vector3.new(27,50.8,-18),10,true)
	part(model,"OldTreeTrunk",Vector3.new(9,47,9),CFrame.new(0,71,0),C.DarkWood,Enum.Material.Wood,true)
	for i=0,4 do
		local a=i*math.pi*2/5
		beam(model,"TreeBranch",Vector3.new(0,82,0),Vector3.new(math.cos(a)*17,96,math.sin(a)*17),4,C.DarkWood,Enum.Material.Wood,true)
		ball(model,"GreatTreeCanopy",Vector3.new(math.cos(a)*15,103+i%2*4,math.sin(a)*15),Vector3.new(31,24,31),if i%2==0 then C.Leaf else C.Grass)
	end
	part(model,"TreehouseDeck",Vector3.new(42,1.2,36),CFrame.new(0,65,0),C.Wood,Enum.Material.WoodPlanks,true)
	cabin(model,Vector3.new(0,65.6,-4),1.7,"CentralTreehouse")
	walkway(model,Vector3.new(27,50.8,-18),Vector3.new(27,65.8,17),9,true)
	walkway(model,Vector3.new(27,65.8,17),Vector3.new(17,65.8,17),9,true)
	for _,x in {-19,19} do
		beam(model,"DeckSupport",Vector3.new(x/2,53,0),Vector3.new(x,64,13),1.5,C.DarkWood,Enum.Material.Wood,true)
		lantern(model,Vector3.new(x,65.6,15))
	end
	-- Two open caves with physical roof/side geometry; crystals are decoration.
	for _,side in {-1,1} do
		local c=Vector3.new(side*46,8,-28)
		for _,x in {-6,6} do part(model,"CavePillar",Vector3.new(4,11,11),CFrame.new(c+Vector3.new(x,5,0)),C.Rock,nil,true) end
		part(model,"CaveRoof",Vector3.new(16,4,12),CFrame.new(c+Vector3.new(0,11,0)),C.Rock,nil,true)
		for i=1,3 do
			local crystal=part(model,"CaveCrystal",Vector3.new(1.4,2+i,1.4),CFrame.new(c+Vector3.new(i-2,1+i/2,-3))*CFrame.Angles(0,0,(i-2)*0.18),Color3.fromRGB(97,211,218),Enum.Material.Neon)
			crystal.Transparency=0.1
		end
	end
	for i=1,9 do
		local a=i*math.pi*2/9
		tree(model,Vector3.new(math.cos(a)*57,8,math.sin(a)*52),0.9,i%2==0)
		flowers(model,Vector3.new(math.cos(a)*60,8,math.sin(a)*55),500+i)
	end
	local water=part(model,"Waterfall",Vector3.new(7,37,0.45),CFrame.new(36,7,-24)*CFrame.Angles(0,-0.4,0),C.Water,Enum.Material.Glass)
	water.Transparency=0.3
	model.Parent=parent
	task.wait()
end

local function buildNative(world)
	local sea=part(world,"Lagoon",Vector3.new(2048,1,2048),CFrame.new(0,Config.WaterY-0.5,0),C.Water,Enum.Material.Glass)
	sea.Transparency=0.18
	sea.CastShadow=false
	hub(world)
	for index=1,Config.PlotCount do playerIsland(world,index) end
	local bridges=Instance.new("Model")
	bridges.Name="IslandBoardwalks"
	for i=1,Config.PlotCount do
		local a=(i-1)*math.pi/3
		local direction=Vector3.new(math.cos(a),0,math.sin(a))
		local inner=direction*63+Vector3.new(0,8,0)
		local outer=direction*Config.IslandRadius-direction*(if math.abs(direction.X)>0.6 then 47 else 37)+Vector3.new(0,Config.GroundY,0)
		walkway(bridges,inner,outer,8,true)
	end
	bridges.Parent=world
	task.wait()
	local spawn=part(world,"HarborSpawn",Vector3.new(6,0.5,6),CFrame.new(51,8.25,20),C.Sand,nil,true,"SpawnLocation")
	spawn.Neutral,spawn.Duration=true,0
	spawn.Transparency=1
end

-- ---------------------------------------------------------------- imported low-poly world

local function findTemplate(name)
	local folder=ServerStorage:FindFirstChild(Config.Templates.Folder)
	local template=folder and folder:FindFirstChild(name)
	return if template and template:IsA("Model") then template else nil
end

local function rgb(t) return Color3.fromRGB(t[1],t[2],t[3]) end

local function only(model)
	local params=RaycastParams.new()
	params.FilterType=Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances={model}
	return params
end

-- Walks outward from `origin` and returns the outermost point that still lands on `model` at
-- or above minY, at the height it landed: the ledge or shoreline facing `direction`. Scans the
-- whole span (a gap in the mesh must not end the search early) and is bounded to 81 raycasts.
local function findEdge(model, origin, direction, minY)
	local params=only(model)
	local last=origin
	for step=0,160,2 do
		local p=origin+direction*step
		local hit=workspace:Raycast(Vector3.new(p.X,origin.Y+40,p.Z),Vector3.new(0,-80,0),params)
		if hit and hit.Position.Y>=minY then
			last=Vector3.new(p.X,hit.Position.Y,p.Z)
		end
	end
	return last
end

-- The island ground mesh only, so ledge searches ignore trees, fences and the cabin roof.
local function walkableGround(model)
	local ground=model:FindFirstChild(Config.Templates.GroundPart,true)
	return if ground and ground:IsA("BasePart") then ground else model
end

local function groundAt(model, x, z, fallbackY)
	local hit=workspace:Raycast(Vector3.new(x,fallbackY+40,z),Vector3.new(0,-80,0),only(model))
	return if hit then math.min(hit.Position.Y,fallbackY+1) else fallbackY
end

local function templateIsland(world, template, index)
	local center=Config.getIslandCenter(index)
	local origin=Config.getPlotOrigin(index)
	local model=template:Clone()
	model.Name=string.format("StarterIsland_%02d",index)
	model:SetAttribute("PlotIndex",index)
	-- Template +X (its conveyor axis) follows the plot axis, so every clearing faces the hub.
	local axis=Config.getPlotAxis(index)
	local frame=CFrame.fromMatrix(Vector3.new(center.X,Config.WaterY+Config.Templates.WaterlineLift,center.Z),Vector3.new(axis.X,0,axis.Z),Vector3.yAxis)
	model:PivotTo(frame)
	model.Parent=world
	local marker=part(model,"FactoryOrigin",Vector3.new(1,1,1),CFrame.new(origin.X,origin.Y,origin.Z),C.Amber)
	marker.Transparency=1
	marker.CanQuery=false
	-- Spawn beside the conveyor platform (16 studs wide) unless the template marks a spot.
	local anchor=model:FindFirstChild("SpawnAnchor",true)
	local spot=if anchor and anchor:IsA("BasePart") then anchor.Position else frame:PointToWorldSpace(Vector3.new(0,Config.GroundY-frame.Position.Y,12))
	local y=groundAt(walkableGround(model),spot.X,spot.Z,Config.GroundY)
	local spawn=part(model,"IslandSpawn",Vector3.new(5,0.4,5),CFrame.new(spot.X,y+0.25,spot.Z),C.Sand,nil,false,"SpawnLocation")
	spawn.Transparency=1
	spawn.CanQuery=false
	spawn.Neutral,spawn.Enabled,spawn.Duration=true,false,0
	task.wait()
	return model
end

local function placeholderHub(world)
	local model=Instance.new("Model")
	model.Name="CentralHub"
	model:SetAttribute("Placeholder",true)
	local top=Config.getHubGroundY()
	local r=Config.Hub.PlaceholderRadius
	local base=Config.WaterY-6
	local rock=part(model,"HubRock",Vector3.new(top-1-base,r*2,r*2),CFrame.new(0,(top-1+base)/2,0)*CFrame.Angles(0,0,math.pi/2),C.Rock,Enum.Material.Slate,true)
	rock.Shape=Enum.PartType.Cylinder
	local lawn=part(model,"HubLawn",Vector3.new(1,r*2+1,r*2+1),CFrame.new(0,top-0.5,0)*CFrame.Angles(0,0,math.pi/2),C.Grass,Enum.Material.Grass,true)
	lawn.Shape=Enum.PartType.Cylinder
	model.Parent=world
	return model
end

local function buildHub(world)
	local template=findTemplate(Config.Templates.Hub)
	local model
	if template then
		model=template:Clone()
		model.Name="CentralHub"
		model:PivotTo(CFrame.new(0,Config.WaterY+Config.Templates.WaterlineLift,0))
		model.Parent=world
	else
		model=placeholderHub(world)
	end
	if not model:FindFirstChildWhichIsA("SpawnLocation",true) then
		local y=groundAt(model,0,0,Config.getHubGroundY())
		local spawn=part(model,"HarborSpawn",Vector3.new(6,0.5,6),CFrame.new(0,y+0.25,0),C.Sand,nil,true,"SpawnLocation")
		spawn.Neutral,spawn.Duration=true,0
		spawn.Transparency=1
	end
	return model
end

-- Imported lagoon models, all pivoted at their waterline centre: walkable sea stacks ("Islet_*",
-- TopHeight attribute in studs above the waterline), stepped clusters ("Cluster_*") and small
-- islands ("Isle_*") whose walkable tops are listed in IsletCatalog, and boulders ("Boulder_*").
local function isletLibrary()
	local folder=ServerStorage:FindFirstChild(Config.Templates.Folder)
	local islets=folder and folder:FindFirstChild(Config.Templates.Islets)
	local walkable,boulders,shapes={},{},{}
	if islets then
		for _,m in islets:GetChildren() do
			if m:IsA("Model") then
				local top=m:GetAttribute("TopHeight")
				if string.sub(m.Name,1,6)=="Islet_" and typeof(top)=="number" and top>0 then
					table.insert(walkable,{model=m,top=top})
				elseif string.sub(m.Name,1,8)=="Boulder_" then
					table.insert(boulders,m)
				elseif string.sub(m.Name,1,8)=="Cluster_" or string.sub(m.Name,1,5)=="Isle_" then
					shapes[m.Name]=m
				end
			end
		end
	end
	table.sort(walkable,function(a,b) return a.model.Name<b.model.Name end)
	table.sort(boulders,function(a,b) return a.Name<b.Name end)
	return walkable,boulders,shapes
end

local WATERLINE=Config.WaterY+Config.Templates.WaterlineLift

-- Scales a placed model about its waterline pivot at (x, z): `sxz` across, `sy` up. Foam stays
-- flat on the water.
local function scaleAbout(model, x, z, sxz, sy)
	for _,p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local foam=string.find(p.Name,"Foam",1,true)~=nil
			local y=if foam then 1 else sy
			local pos=p.Position
			p.Size=Vector3.new(p.Size.X*sxz,p.Size.Y*y,p.Size.Z*sxz)
			p.Position=Vector3.new(x+(pos.X-x)*sxz,WATERLINE+(pos.Y-WATERLINE)*y,z+(pos.Z-z)*sxz)
		end
	end
end

-- One walkable islet whose grass top lands exactly on the pad height: the closest-height variant,
-- stretched a little in Y about the waterline and scaled across by `scale`, so the lagoon mixes
-- small stepping rocks with broad ones.
local function placeIslet(parent, walkable, pad, yaw, pick, scale)
	local want=pad.Y-WATERLINE
	if #walkable==0 then
		local size=Config.Parkour.PadSize*scale+1.5
		local rock=part(parent,"IsletRock",Vector3.new(size,want+3.4,size),CFrame.new(pad.X,(pad.Y-0.6+WATERLINE-4)/2,pad.Z)*CFrame.Angles(0,yaw,0),C.Rock,Enum.Material.Slate,true)
		rock.CastShadow=false
		part(parent,"IsletTop",Vector3.new(size-0.6,0.6,size-0.6),CFrame.new(pad.X,pad.Y-0.3,pad.Z)*CFrame.Angles(0,yaw,0),C.Grass,Enum.Material.Grass,true)
		return
	end
	-- The shortest variant that reaches the height, sunk until its top lands there (so low islets
	-- keep their proportions instead of being squashed); only above the tallest one is stretched.
	local best,score=nil,math.huge
	for k,entry in walkable do
		local s=(if entry.top>=want-0.05 then entry.top else 1000-entry.top)+(if (k+pick)%2==0 then 0 else 0.01)
		if s<score then best,score=entry,s end
	end
	local model=best.model:Clone()
	model:PivotTo(CFrame.new(pad.X,WATERLINE,pad.Z)*CFrame.Angles(0,yaw,0))
	scaleAbout(model,pad.X,pad.Z,scale,math.max(1,want/best.top))
	local sink=math.max(0,best.top-want)
	for _,p in model:GetDescendants() do
		if p:IsA("BasePart") and not string.find(p.Name,"Foam",1,true) then
			p.Position-=Vector3.new(0,sink,0)
		end
	end
	model.Parent=parent
end

-- A stepped cluster or small island exactly as ParkourLayout placed its walkable tops. Without
-- the model, each top becomes a loose islet so the layout stays reachable.
local function placeShape(parent, walkable, shapes, piece, pick)
	local template=shapes[piece.Shape]
	if not template then
		for _,shape in (if piece.Kind=="Isle" then IsletCatalog.Isles else IsletCatalog.Clusters) do
			if shape.Name==piece.Shape then
				local c,s=math.cos(piece.Yaw),math.sin(piece.Yaw)
				for k,t in shape.Tops do
					local pad={X=piece.X+(t.X*c+t.Z*s)*piece.ScaleXZ,Y=WATERLINE+t.Y*piece.ScaleY,Z=piece.Z+(-t.X*s+t.Z*c)*piece.ScaleXZ}
					placeIslet(parent,walkable,pad,piece.Yaw,pick+k,math.max(1,t.W*piece.ScaleXZ/Config.Parkour.PadSize))
				end
			end
		end
		return
	end
	local model=template:Clone()
	model:PivotTo(CFrame.new(piece.X,WATERLINE,piece.Z)*CFrame.Angles(0,piece.Yaw,0))
	scaleAbout(model,piece.X,piece.Z,piece.ScaleXZ,piece.ScaleY)
	model.Parent=parent
end

local function scatterBoulders(world, boulders, keepOut)
	local S=Config.Scatter
	local rocks=ParkourLayout.scatter(97,S.Count,S.Radius,keepOut,S.MinSpacing,math.max(#boulders,1))
	local folder=Instance.new("Folder")
	folder.Name="LagoonRocks"
	for _,rock in rocks do
		if #boulders>0 then
			local model=boulders[rock.Variant]:Clone()
			model:PivotTo(CFrame.new(rock.X,WATERLINE,rock.Z)*CFrame.Angles(0,rock.Yaw,0))
			model:ScaleTo(rock.Scale)
			model.Parent=folder
		else
			local ball=part(folder,"LagoonRock",Vector3.new(7,5,6)*rock.Scale,CFrame.new(rock.X,WATERLINE,rock.Z)*CFrame.Angles(0,rock.Yaw,0.2),C.Rock,Enum.Material.Slate,true)
			ball.Shape=Enum.PartType.Ball
		end
	end
	folder.Parent=world
	return rocks
end

-- Translucent Terrain water: light sand shelves around every island and the hub (turquoise
-- through the water) over a dark deep floor between them (deep blue), deep footings under every
-- lagoon rock so nothing appears to float, and horizon haze.
-- `withWater` false builds only the floor (sand shelves, deep floor, footings) under the
-- translucent textured surface.
local function buildWater(centers, mounds, withWater)
	local terrain=workspace.Terrain
	local W=Config.Water
	terrain:SetMaterialColor(Enum.Material.Sand,rgb(W.SandRGB))
	terrain:SetMaterialColor(Enum.Material.Mud,rgb(W.DeepFloorRGB))
	local bottom=Config.WaterY-W.Depth
	if withWater then
		terrain.WaterColor=rgb(W.ColorRGB)
		terrain.WaterTransparency=W.Transparency
		terrain.WaterReflectance=W.Reflectance
		terrain.WaterWaveSize=W.WaveSize
		terrain.WaterWaveSpeed=W.WaveSpeed
		terrain:FillBlock(CFrame.new(0,Config.WaterY-W.Depth/2,0),Vector3.new(W.Size,W.Depth,W.Size),Enum.Material.Water)
	end
	-- A dark floor so open water reads deep blue; sand only on the shelves around land.
	terrain:FillBlock(CFrame.new(0,(bottom+W.DeepFloorY)/2,0),Vector3.new(W.Size,W.DeepFloorY-bottom,W.Size),Enum.Material.Mud)
	for _,c in centers do
		-- Terraces 4 studs apart (outermost and deepest first), so the turquoise shallows fade out
		-- instead of ending at one hard edge.
		for k=W.ShelfTerraces,0,-1 do
			local top=W.ShallowFloorY-4*k
			terrain:FillCylinder(CFrame.new(c.X,(bottom+top)/2,c.Z),top-bottom,W.ShoreRadius+W.ShelfFade*k,Enum.Material.Sand)
		end
		task.wait()
	end
	-- Deep footings under lagoon rocks, in the floor colour and on a voxel-layer boundary: they
	-- stop rocks floating without showing as bright sand squares near the surface.
	for i,m in mounds do
		local top=math.ceil(m.TopY/4)*4
		terrain:FillCylinder(CFrame.new(m.X,(bottom+top)/2,m.Z),top-bottom,m.R,Enum.Material.Mud)
		if i%20==0 then task.wait() end
	end
	-- Haze toward the horizon so the water's far edge fades into the sky.
	local lighting=game:GetService("Lighting")
	local atmosphere=lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density,atmosphere.Offset,atmosphere.Glare,atmosphere.Haze=W.HazeDensity,0.2,0,1.4
	atmosphere.Color,atmosphere.Decay=rgb(W.HazeRGB),rgb(W.ColorRGB)
	atmosphere.Parent=lighting
end

-- Optional caustics: one textured, non-colliding sheet over each sandy shelf; the client scrolls it.
local function buildCaustics(world, centers)
	if Config.CausticsTextureId=="" then return end
	local folder=Instance.new("Folder")
	folder.Name="Caustics"
	local W=Config.Water
	local side=W.ShoreRadius*math.sqrt(2)
	for _,c in centers do
		local sheet=part(folder,"CausticsLayer",Vector3.new(side,0.2,side),CFrame.new(c.X,W.ShallowFloorY+0.3,c.Z),C.Water,nil,false)
		sheet.Transparency=1
		sheet.CanQuery=false
		sheet.CastShadow=false
		local texture=Instance.new("Texture")
		texture.Face=Enum.NormalId.Top
		texture.Texture=Config.CausticsTextureId
		texture.StudsPerTileU=Config.CausticsStudsPerTile
		texture.StudsPerTileV=Config.CausticsStudsPerTile
		texture.Transparency=0.5
		texture.Parent=sheet
	end
	folder.Parent=world
end

-- Stylized water like the Blender preview: parts covering the lagoon, textured with the
-- baked seamless water tile (textures/roblox_water_surface_1024.png), plus a translucent second
-- layer at another scale. CausticsController drifts the layers in different directions so the
-- surface shimmers. Each part is a whole number of tiles wide, so the pattern never breaks at seams.
-- Over the terrain floor the base layer is slightly see-through (shelves and rock bases show).
-- Beyond the floor it is opaque, so nothing empty shows below.
local function buildWaterSurface(world)
	local W=Config.Water
	local S=W.Surface
	local folder=Instance.new("Folder")
	folder.Name="WaterSurface"
	local count=math.ceil(S.Size/S.MaxPartSize)
	local side=S.Size/count
	for i=0,count-1 do
		for j=0,count-1 do
			local x,z=-S.Size/2+side*(i+0.5),-S.Size/2+side*(j+0.5)
			local sheet=part(folder,"WaterSurface",Vector3.new(side,1,side),CFrame.new(x,Config.WaterY-0.5,z),rgb(S.ColorRGB))
			-- Over the terrain floor the water is see-through; beyond it, opaque (nothing below).
			local overFloor=math.abs(x)<W.Size/2 and math.abs(z)<W.Size/2
			sheet.Transparency=1
			sheet.CanQuery=false
			sheet.CastShadow=false
			for k,layer in S.Layers do
				local texture=Instance.new("Texture")
				texture.Name="WaterLayer"..k
				texture.Face=Enum.NormalId.Top
				texture.Texture=S.TextureId
				texture.StudsPerTileU,texture.StudsPerTileV=layer.StudsPerTile,layer.StudsPerTile
				texture.Transparency=if overFloor then layer.Transparency else layer.OuterTransparency
				texture.Color3=rgb(layer.TintRGB)
				texture.ZIndex=k
				texture:SetAttribute("DriftU",layer.Drift[1])
				texture:SetAttribute("DriftV",layer.Drift[2])
				texture.Parent=sheet
			end
		end
	end
	folder.Parent=world
	-- Haze toward the horizon so the water's far edge fades into the sky.
	local lighting=game:GetService("Lighting")
	local atmosphere=lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density,atmosphere.Offset,atmosphere.Glare,atmosphere.Haze=W.HazeDensity,0.2,0,1.4
	atmosphere.Color,atmosphere.Decay=rgb(W.HazeRGB),rgb(S.HazeDecayRGB)
	atmosphere.Parent=lighting
end

local function buildFromTemplates(world, islandTemplate)
	local declared=islandTemplate:GetAttribute("GroundHeight")
	if typeof(declared)=="number" and math.abs(declared-Config.Templates.GroundHeight)>0.5 then
		warn(string.format("[IslandWorldBuilder] %s GroundHeight %.2f differs from config %.2f; factories may float or sink",
			islandTemplate.Name,declared,Config.Templates.GroundHeight))
	end
	local hubModel=buildHub(world)
	local hubBox=hubModel:GetBoundingBox()
	local centers={{X=hubBox.X,Z=hubBox.Z}}
	local islands={}
	for index=1,Config.PlotCount do
		local islandModel=templateIsland(world,islandTemplate,index)
		islands[index]=islandModel
		-- Shelves centre on the island's footprint, not its clearing (they differ by ~9 studs).
		local box=islandModel:GetBoundingBox()
		table.insert(centers,{X=box.X,Z=box.Z})
	end

	local walkable,boulders,shapes=isletLibrary()
	if #walkable==0 then
		warn("[IslandWorldBuilder] ServerStorage."..Config.Templates.Folder.."."..Config.Templates.Islets.." has no Islet_* models; using placeholder rocks")
	end
	local mounds={}
	local F=Config.Field
	local hubY=Config.getHubGroundY()

	-- Measured around the hub and every island: walkable ledges (ground mesh only, so trees and
	-- roofs are ignored), the shoreline at every bearing (any part that takes queries, so not the
	-- foam) for keep-out fans that hug the real coast, and each dock's far end as a low way on.
	local function bearings(n)
		local list={}
		for k=0,n-1 do table.insert(list,k*math.pi*2/n) end
		return list
	end
	local function ledges(model, centre, y)
		local points={}
		for _,a in bearings(F.LedgeSamples) do
			local e=findEdge(model,centre,Vector3.new(math.cos(a),0,math.sin(a)),y-3)
			table.insert(points,{X=e.X,Y=y,Z=e.Z})
		end
		return points
	end
	local keepOut,scatterKeepOut={},{}
	local function shoreFan(model, centre)
		local angles,distances={},{}
		for _,a in bearings(F.ShoreSamples) do
			local e=findEdge(model,centre,Vector3.new(math.cos(a),0,math.sin(a)),WATERLINE-6)
			table.insert(angles,a)
			table.insert(distances,math.max(4,Vector3.new(e.X-centre.X,0,e.Z-centre.Z).Magnitude))
		end
		local S=Config.Scatter
		for _,circle in ParkourLayout.shoreFan(centre.X,centre.Z,angles,distances,S.ShoreClearance) do
			table.insert(keepOut,circle)
		end
		for _,circle in ParkourLayout.shoreFan(centre.X,centre.Z,angles,distances,S.BoulderShoreClearance) do
			table.insert(scatterKeepOut,circle)
		end
	end
	local function dockEnd(dock, centre)
		-- The bounding-box corner farthest from the clearing, walked back onto the deck.
		local far,reach=nil,-1
		for _,sx in {-1,1} do
			for _,sz in {-1,1} do
				local corner=dock.CFrame:PointToWorldSpace(Vector3.new(sx*dock.Size.X/2,0,sz*dock.Size.Z/2))
				local d=Vector3.new(corner.X-centre.X,0,corner.Z-centre.Z).Magnitude
				if d>reach then far,reach=corner,d end
			end
		end
		for t=0.05,0.95,0.05 do
			local p=far:Lerp(dock.Position,t)
			local hit=workspace:Raycast(Vector3.new(p.X,dock.Position.Y+40,p.Z),Vector3.new(0,-80,0),only(dock))
			if hit then return {X=hit.Position.X,Y=hit.Position.Y,Z=hit.Position.Z} end
		end
		return nil
	end
	local hubCentre=Vector3.new(hubBox.X,hubY,hubBox.Z)
	local anchors={{Ledges=ledges(hubModel,hubCentre,hubY)}}
	shoreFan(hubModel,hubCentre)
	for index,islandModel in islands do
		local c=Config.getIslandCenter(index)
		local centre=Vector3.new(c.X,Config.GroundY,c.Z)
		local points=ledges(walkableGround(islandModel),centre,Config.GroundY)
		local dock=islandModel:FindFirstChild(Config.Templates.DockPart,true)
		local deck=dock and dock:IsA("BasePart") and dockEnd(dock,centre)
		if deck then table.insert(points,deck) end
		table.insert(anchors,{Ledges=points})
		shoreFan(islandModel,centre)
	end

	-- The noise field: loose islets, stepped clusters and small islands at varied heights
	-- everywhere, bridged only where something is cut off.
	local islets,pieces=ParkourLayout.field(F.Seed,anchors,keepOut,Config.landingHeight,F,Config.Parkour,IsletCatalog)
	if not ParkourLayout.allConnected(anchors,islets,Config.Parkour) then
		warn("[IslandWorldBuilder] lagoon parkour leaves an island or the hub unreachable; raise Field.MaxRepairs or MaxPieces")
	end
	local field=Instance.new("Model")
	field.Name="ParkourIslets"
	for i,piece in pieces do
		if piece.Kind=="Islet" then
			placeIslet(field,walkable,piece,piece.Yaw,i,piece.ScaleXZ)
		else
			placeShape(field,walkable,shapes,piece,i)
		end
		table.insert(scatterKeepOut,{X=piece.X,Z=piece.Z,R=piece.Radius+Config.Scatter.RouteClearance})
		-- Rock bases reach ~13 studs under the waterline (x their Y scale, never below 0.8): a deep
		-- footing meets them out of sight.
		table.insert(mounds,{X=piece.X,Z=piece.Z,R=4+piece.Radius*0.75,TopY=WATERLINE-Config.Water.FootingDepth})
		if i%25==0 then task.wait() end
	end
	field.Parent=world
	for _,rock in scatterBoulders(world,boulders,scatterKeepOut) do
		-- Boulder footings reach 13 studs under at scale 1; the footing stays deep in the water.
		table.insert(mounds,{X=rock.X,Z=rock.Z,R=4*rock.Scale+4,TopY=math.min(WATERLINE-13*rock.Scale+1.5,WATERLINE-8)})
	end
	-- The textured surface matches the Blender preview; Terrain water is the fallback until the
	-- texture is uploaded (it needs a group-owned image, since the place belongs to a group).
	if Config.Water.Surface.TextureId~="" then
		buildWater(centers,mounds,false)
		buildWaterSurface(world)
	else
		buildWater(centers,mounds,true)
		buildCaustics(world,centers)
	end
end

function Builder.build()
	local existing=workspace:FindFirstChild(Config.MapKey)
	if existing then return existing end
	local world=Instance.new("Model")
	world.Name=Config.MapKey
	world:SetAttribute("MapRevision",Config.Revision)
	world.Parent=workspace
	local islandTemplate=findTemplate(Config.Templates.Island)
	if islandTemplate then
		world:SetAttribute("MapSource","Template")
		buildFromTemplates(world,islandTemplate)
	else
		warn("[IslandWorldBuilder] ServerStorage."..Config.Templates.Folder.."."..Config.Templates.Island.." not found; building the native fallback map")
		world:SetAttribute("MapSource","Native")
		buildNative(world)
	end
	local lighting=game:GetService("Lighting")
	lighting.ClockTime=14
	lighting.Brightness=2.5
	lighting.Ambient=Color3.fromRGB(132,145,151)
	lighting.OutdoorAmbient=Color3.fromRGB(159,173,185)
	lighting.GlobalShadows=true
	lighting.EnvironmentDiffuseScale=0.65
	lighting.EnvironmentSpecularScale=0.4
	return world
end

return Builder
