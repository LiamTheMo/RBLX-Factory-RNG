--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoosterConfig = require(Shared:WaitForChild("BoosterConfig"))
local BoosterRules = require(Shared:WaitForChild("BoosterRules"))
local IslandWorldConfig = require(Shared:WaitForChild("IslandWorldConfig"))
local HudTheme = require(Shared:WaitForChild("HudTheme"))
local FactoryService = require(script.Parent.FactoryService)
local BoosterService = require(script.Parent.BoosterService)
local EffectService = require(script.Parent.EffectService)
local AnalyticsService = require(script.Parent.AnalyticsService)

local LootService = {}
local started = false
local activeDrops: { [Player]: { BasePart } } = {}
local random = Random.new()

local function getWorldFolder(): Folder
	local existing = workspace:FindFirstChild(BoosterConfig.WorldFolderName)
	if existing and existing:IsA("Folder") then return existing end
	local folder = Instance.new("Folder")
	folder.Name = BoosterConfig.WorldFolderName
	folder.Parent = workspace
	return folder
end

local function getActiveDropCount(player: Player): number
	local drops = activeDrops[player]
	if not drops then return 0 end
	for index = #drops, 1, -1 do
		if not drops[index].Parent then table.remove(drops, index) end
	end
	return #drops
end

function LootService.claim(player: Player, part: BasePart): boolean
	local factory = FactoryService.getState(player)
	if not factory or player:GetAttribute("FactoryDataReady") ~= true or not part:IsA("BasePart")
		or part.Parent ~= getWorldFolder() or part:GetAttribute("Landed") ~= true or part:GetAttribute("Claimed") == true then
		return false
	end
	-- Drops land anywhere on the map, so any loaded player may collect them; the source
	-- player only counts toward per-player spawn caps.
	local booster = BoosterRules.get(part:GetAttribute("BoosterId"))
	if not booster then return false end
	part:SetAttribute("Claimed", true)
	local granted = BoosterService.collect(player, booster.Id)
	if not granted then
		part:SetAttribute("Claimed", false)
		return false
	end
	part:Destroy()
	AnalyticsService.record(player, "LootCollected")
	EffectService.fire(player, "LootClaimed", { BoosterId = booster.Id, DisplayName = booster.DisplayName })
	return true
end

local function connectTouchPickup(part: BasePart)
	part.Touched:Connect(function(hit: BasePart)
		if part:GetAttribute("Claimed") == true then return end
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character or not character:FindFirstChildOfClass("Humanoid") then return end
		local player = Players:GetPlayerFromCharacter(character)
		if player then LootService.claim(player, part) end
	end)
end

-- Matches the client glass HUD: a translucent slate pill with a booster-colored rim and dot.
local function addDisplay(part: BasePart, booster: any): BillboardGui
	local color = Color3.fromRGB(booster.Color[1], booster.Color[2], booster.Color[3])
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BoosterLabel"
	billboard.Enabled = false
	billboard.Adornee = part
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 70
	billboard.Size = UDim2.fromOffset(176, 44)
	billboard.StudsOffset = Vector3.new(0, 1.35, 0)
	billboard.Parent = part
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = HudTheme.Colors.Glass
	pill.BackgroundTransparency = HudTheme.Transparency.Glass
	pill.BorderSizePixel = 0
	pill.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = color
	rim.Transparency = 0.3
	rim.Parent = pill
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, 14, 0.5, 0)
	dot.Size = UDim2.fromOffset(14, 14)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.Parent = pill
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	local function text(name: string, value: string, y: number, height: number, font: Font, size: number, textColor: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 36, 0, y)
		label.Size = UDim2.new(1, -48, 0, height)
		label.FontFace = font
		label.Text = value
		label.TextColor3 = textColor
		label.TextSize = size
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = pill
		return label
	end
	text("Label", booster.DisplayName, 4, 20, HudTheme.Fonts.Bold, 14, HudTheme.Colors.Text)
	text("Hint", "Walk over to collect", 23, 16, HudTheme.Fonts.Medium, 11, HudTheme.Colors.Muted)
	return billboard
end

-- Random dry-ground point anywhere on the map (uniform over a disc around the hub).
local function findMapPosition(): Vector3?
	local map = BoosterConfig.MapSpawn
	local rayConfig = BoosterConfig.LandRaycast
	local fallConfig = BoosterConfig.Fall
	local minimumY = IslandWorldConfig.Field.WaterlineY + map.MinAboveWater
	local maximumY = IslandWorldConfig.Field.MaxTopY + map.MaxAboveFieldTop
	local exclusions: { Instance } = { getWorldFolder() }
	-- Lagoon rocks sit out in the water where nobody can walk; rays fall through to the
	-- floor below and are rejected by the waterline check.
	local world = workspace:FindFirstChild(IslandWorldConfig.MapKey)
	local rocks = world and world:FindFirstChild("LagoonRocks", true)
	if rocks then
		table.insert(exclusions, rocks)
	end
	local plotsFolder = workspace:FindFirstChild("TinyFactoryPlots")
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(exclusions, player.Character)
		end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = exclusions
	rayParams.IgnoreWater = true
	rayParams.RespectCanCollide = true

	for _ = 1, rayConfig.PositionAttempts do
		local distance = map.Radius * math.sqrt(random:NextNumber())
		local angle = random:NextNumber() * math.pi * 2
		local rayOrigin = Vector3.new(math.cos(angle) * distance, rayConfig.StartHeight, math.sin(angle) * distance)
		local result = workspace:Raycast(rayOrigin, Vector3.new(0, -rayConfig.Distance, 0), rayParams)
		-- On a plot only the open platform counts, never the conveyor or machines.
		local onPlot = result ~= nil and plotsFolder ~= nil and result.Instance:IsDescendantOf(plotsFolder)
		if result and result.Normal.Y >= rayConfig.MinimumGroundNormalY
			and result.Position.Y >= minimumY and result.Position.Y <= maximumY
			and (not onPlot or result.Instance.Name == "FactoryPlatform") then
			return result.Position + Vector3.new(0, fallConfig.LandingHeight, 0)
		end
	end
	return nil
end

local function spawnLoot(player: Player)
	local factory = FactoryService.getState(player)
	if not factory or player:GetAttribute("FactoryDataReady") ~= true or not player.Parent then return end
	if getActiveDropCount(player) >= BoosterConfig.MaxActiveDropsPerFactory then return end
	local folder = getWorldFolder()
	if #folder:GetChildren() >= BoosterConfig.MaxActiveDropsWorldwide then return end
	local totalWeight = BoosterRules.getTotalSpawnWeight()
	local boosterId = BoosterRules.pickBoosterId(random:NextNumber() * totalWeight)
	local booster = BoosterRules.get(boosterId)
	if not booster then return end
	local landingPosition = findMapPosition()
	if not landingPosition then
		return
	end
	local fallConfig = BoosterConfig.Fall
	local part = Instance.new("Part")
	part.Name = "WorldBoosterDrop"
	part.Shape = Enum.PartType.Block
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(booster.Color[1], booster.Color[2], booster.Color[3])
	part.Size = Vector3.new(fallConfig.StartingSize, fallConfig.StartingSize, fallConfig.StartingSize)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	-- A turned cube reads as a gem; the fall tween moves Position, so the turn is kept.
	part.CFrame = CFrame.new(landingPosition + Vector3.new(0, fallConfig.DropHeight, 0))
		* CFrame.Angles(math.rad(12), math.rad(random:NextNumber(0, 90)), math.rad(12))
	part:SetAttribute("BoosterId", booster.Id)
	part:SetAttribute("SourcePlotUserId", player.UserId)
	part:SetAttribute("Claimed", false)
	part:SetAttribute("Landed", false)
	part.Parent = folder
	-- The label stays disabled here; clients show it only while the drop is hovered or tapped.
	addDisplay(part, booster)
	connectTouchPickup(part)
	local drops = activeDrops[player]
	if not drops then drops = {}; activeDrops[player] = drops end
	table.insert(drops, part)
	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Brightness = 1.5
	light.Range = 10
	light.Enabled = false
	light.Parent = part
	local landingTween = TweenService:Create(part, TweenInfo.new(fallConfig.DurationSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = landingPosition,
		Size = Vector3.new(fallConfig.LandedSize, fallConfig.LandedSize, fallConfig.LandedSize),
		Transparency = 0,
	})
	landingTween.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed or not part.Parent or part:GetAttribute("Claimed") == true then
			return
		end
		part:SetAttribute("Landed", true)
		part.CanTouch = true
		light.Enabled = true
	end)
	landingTween:Play()
	task.delay(BoosterConfig.DespawnAfterSeconds, function()
		if part.Parent then part:Destroy() end
	end)
end

-- Spawns one drop for the player now (respecting caps); used by the Studio smoke test.
function LootService.spawnFor(player: Player)
	spawnLoot(player)
end

local function removePlayerDrops(player: Player)
	local folder = workspace:FindFirstChild(BoosterConfig.WorldFolderName)
	if folder then
		for _, part in ipairs(folder:GetChildren()) do
			if part:GetAttribute("SourcePlotUserId") == player.UserId then part:Destroy() end
		end
	end
	activeDrops[player] = nil
end

function LootService.start()
	if started then return end
	started = true
	getWorldFolder()
	Players.PlayerRemoving:Connect(removePlayerDrops)
	task.spawn(function()
		task.wait(5)
		while true do
			for _, player in Players:GetPlayers() do spawnLoot(player) end
			task.wait(BoosterConfig.SpawnIntervalSeconds)
		end
	end)
end

return LootService
