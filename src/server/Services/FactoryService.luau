--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FactoryConfig = require(Shared:WaitForChild("FactoryConfig"))
local CubeTypeDefinitions = require(Shared:WaitForChild("CubeTypeDefinitions"))
local MachineVisualConfig = require(Shared:WaitForChild("MachineVisualConfig"))
local FactoryLayout = require(Shared:WaitForChild("FactoryLayout"))
local FactoryItemGeometry = require(Shared:WaitForChild("FactoryItemGeometry"))
local SaleValueRules = require(Shared:WaitForChild("SaleValueRules"))
local NumberFormatter = require(Shared:WaitForChild("NumberFormatter"))
local MachineModelBuilder = require(script.Parent.MachineModelBuilder)
local FactorySimulation = require(Shared:WaitForChild("FactorySimulation"))
local MachineDefinitions = require(Shared:WaitForChild("MachineDefinitions"))
local PlacementRules = require(Shared:WaitForChild("PlacementRules"))
local AnalyticsService = require(script.Parent.AnalyticsService)
local EffectService = require(script.Parent.EffectService)
local IslandWorldConfig = require(Shared:WaitForChild("IslandWorldConfig"))

local FactoryService = {}
local factories = {}
local lastRequestAt = {}
local started = false
local occupiedPlots = {}
local attributeUpdateAccumulator = 0
local visualUpdateAccumulator = 0
local VISUAL_UPDATE_INTERVAL_SECONDS = 1 / 20
local cubeTypeColorCache = {}

local function copyInventory(inventory: { [string]: number }): { [string]: number }
	local result = {}
	for machineId, quantity in pairs(inventory) do
		result[machineId] = quantity
	end
	return result
end

local function layoutForClient(layout: FactoryLayout.Layout): { string }
	local result = {}
	for slotIndex = 1, FactoryLayout.SlotCount do
		result[slotIndex] = layout[slotIndex] or ""
	end
	return result
end

local function createPart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Size = size
	part.Position = position
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addSlotClickDetector(part: BasePart, slotIndex: number)
	part:SetAttribute("FactorySlotIndex", slotIndex)
	if not FactoryLayout.isEditableMachineSlot(slotIndex) then
		return
	end
	local detector = Instance.new("ClickDetector")
	detector.Name = "FactorySlotClick"
	detector.MaxActivationDistance = 32
	detector:SetAttribute("FactorySlotIndex", slotIndex)
	detector.Parent = part
end

local function colorFromRgb(channels: { number }): Color3
	return Color3.fromRGB(channels[1], channels[2], channels[3])
end

local function overlapsHitbox(hitbox: BasePart, item: BasePart): boolean
	local localPosition = hitbox.CFrame:PointToObjectSpace(item.Position)
	return FactoryItemGeometry.overlapsBox(localPosition.X, localPosition.Y, localPosition.Z, hitbox.Size.X, hitbox.Size.Y, hitbox.Size.Z, item.Size.X)
end

local function getSaleBuffModifiers(player: Player): { [string]: number? }
	-- EconomyService owns these server-side attributes. Missing attributes remain neutral.
	local expiresAt = player:GetAttribute("FactorySaleValueExpiresAt")
	if type(expiresAt) ~= "number" or expiresAt <= workspace:GetServerTimeNow() then
		return { AdditiveBonus = 0, Multiplier = 1 }
	end
	return {
		AdditiveBonus = player:GetAttribute("FactorySaleValueAdditiveBonus"),
		Multiplier = player:GetAttribute("FactorySaleValueMultiplier"),
	}
end

-- Plots face the hub: the conveyor runs along the plot axis (tangent to the island ring).
local function plotFrame(origin: Vector3, plotIndex: number): CFrame
	local axis = IslandWorldConfig.getPlotAxis(plotIndex)
	return CFrame.fromMatrix(origin, Vector3.new(axis.X, 0, axis.Z), Vector3.yAxis)
end

-- Factory geometry is built axis-aligned at the plot origin (the simulation's local +X), then
-- swung into the plot's orientation here, so the builders stay simple.
local function alignToPlot(root: Instance, frame: CFrame)
	local swing = CFrame.new(frame.Position) * frame.Rotation * CFrame.new(-frame.Position)
	if root:IsA("BasePart") then root.CFrame = swing * root.CFrame end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then descendant.CFrame = swing * descendant.CFrame end
	end
end

local function createConveyor(plot: Folder, origin: Vector3): Folder
	local config = MachineVisualConfig.Conveyor
	local slotPitch = MachineVisualConfig.SlotPitch
	local slotCount = FactoryLayout.SlotCount
	local segmentLength = slotPitch + config.SegmentOverlap
	local startX = -segmentLength / 2
	local endX = (slotCount - 1) * slotPitch + segmentLength / 2
	local length = endX - startX
	local centerX = (startX + endX) / 2
	local beltTop = config.RollerCenterY + config.RollerDiameter / 2 + config.Elevation
	local beltBottom = config.DeckCenterY - config.DeckThickness / 2 + config.Elevation
	local beltMid = (beltTop + beltBottom) / 2
	local railZ = config.BeltWidth / 2 + config.Rail.Thickness / 2
	local railBottom = 0
	local railTop = beltTop + config.Rail.TopAboveBelt
	local railHeight = railTop - railBottom
	local sellerStartX = (FactoryLayout.SellerSlotIndex - 1) * slotPitch - slotPitch / 2

	local conveyor = Instance.new("Folder")
	conveyor.Name = "Conveyor"
	conveyor.Parent = plot
	conveyor:SetAttribute("SlotCount", slotCount)

	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end
	local function piece(name: string, size: Vector3, position: Vector3, color: { number }, material: Enum.Material): Part
		local result = createPart(conveyor, name, size, position, colorFromRgb(color))
		result.Material = material
		return result
	end
	local function drum(name: string, x: number)
		local diameter = beltTop - beltBottom + 0.12
		local result = piece(name, Vector3.new(config.BeltWidth + 0.1, diameter, diameter), at(x, beltMid, 0), config.DrumColor, Enum.Material.Metal)
		result.Shape = Enum.PartType.Cylinder
		result.CFrame = CFrame.new(result.Position) * CFrame.Angles(0, math.rad(90), 0)
	end

	-- Continuous belt between two end drums, resting on a low base on the ground.
	local belt = piece("ConveyorBelt", Vector3.new(length, beltTop - beltBottom, config.BeltWidth), at(centerX, beltMid, 0), config.BeltColor, Enum.Material.Rubber)
	belt:SetAttribute("ConveyorBelt", true)
	belt:SetAttribute("BeltSpeed", slotPitch / FactoryConfig.TravelTimePerSlotSeconds)
	piece("ConveyorBase", Vector3.new(length, beltBottom, config.BeltWidth), at(centerX, beltBottom / 2, 0), config.BaseColor, Enum.Material.Metal)
	drum("ConveyorDrumTail", startX)
	drum("ConveyorDrumHead", endX)

	local sideNames = { "Left", "Right" }
	for sideIndex, side in ipairs({ -1, 1 }) do
		local sideName = sideNames[sideIndex]
		local z = side * railZ
		piece("ConveyorRail" .. sideName, Vector3.new(length + 0.3, railHeight, config.Rail.Thickness),
			at(centerX, (railTop + railBottom) / 2, z), config.Rail.Color, Enum.Material.Metal)
		piece("ConveyorRailLip" .. sideName, Vector3.new(length + 0.34, 0.1, config.Rail.Thickness + 0.08),
			at(centerX, railTop + 0.05, z), config.Rail.LipColor, Enum.Material.SmoothPlastic)
		-- Safety stripe on the outer face; the seller bay section uses its own color.
		local stripeY = railTop - 0.32
		local stripeZ = z + side * (config.Rail.Thickness / 2 + config.Stripe.Depth / 2)
		local routeLength = sellerStartX - startX
		piece("ConveyorStripe" .. sideName, Vector3.new(routeLength, config.Stripe.Height, config.Stripe.Depth),
			at(startX + routeLength / 2, stripeY, stripeZ), config.Stripe.Color, Enum.Material.SmoothPlastic)
		piece("ConveyorSellerStripe" .. sideName, Vector3.new(endX - sellerStartX, config.Stripe.Height, config.Stripe.Depth),
			at((sellerStartX + endX) / 2, stripeY, stripeZ), config.SellerBay.StripeColor, Enum.Material.SmoothPlastic)
		for boundary = 0, slotCount do
			local bolt = piece(string.format("ConveyorBolt%s_%d", sideName, boundary), Vector3.new(config.Bolt.Depth, config.Bolt.Diameter, config.Bolt.Diameter),
				at(startX + boundary * slotPitch + (if boundary == 0 then 0.35 elseif boundary == slotCount then -0.35 else 0), railBottom + 0.3,
					z + side * (config.Rail.Thickness / 2 + config.Bolt.Depth / 2)),
				config.Bolt.Color, Enum.Material.Metal)
			bolt.Shape = Enum.PartType.Cylinder
			bolt.CFrame = CFrame.new(bolt.Position) * CFrame.Angles(0, math.rad(90), 0)
		end
	end

	-- One invisible click plate per slot, flush with the belt and below riding cubes.
	for slotIndex = 1, slotCount do
		local selector = createPart(conveyor, string.format("SlotSelector_%d", slotIndex),
			Vector3.new(slotPitch - config.Selector.LengthInset, config.Selector.Thickness, config.BeltWidth + config.Rail.Thickness * 2),
			at((slotIndex - 1) * slotPitch, beltTop + config.Selector.Thickness / 2, 0), Color3.new(1, 1, 1))
		selector.Transparency = 1
		selector.CastShadow = false
		selector.CanTouch = false
		addSlotClickDetector(selector, slotIndex)
	end

	return conveyor
end

local function createIslandPlot(player: Player, plotIndex: number): (Folder, Vector3, Folder)
	local plotsFolder = workspace:FindFirstChild("TinyFactoryPlots")
	if not plotsFolder then
		plotsFolder = Instance.new("Folder")
		plotsFolder.Name = "TinyFactoryPlots"
		plotsFolder.Parent = workspace
	end

	local plotConfig = MachineVisualConfig.FactoryPlot
	local position = IslandWorldConfig.getPlotOrigin(plotIndex)
	local origin = Vector3.new(position.X, position.Y, position.Z)
	local plot = Instance.new("Folder")
	plot.Name = string.format("Factory_%d", player.UserId)
	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("IslandIndex", plotIndex)
	plot.Parent = plotsFolder

	local slotCount = FactoryLayout.SlotCount
	local slotPitch = MachineVisualConfig.SlotPitch
	local conveyorConfig = MachineVisualConfig.Conveyor
	local segmentLength = slotPitch + conveyorConfig.SegmentOverlap
	local conveyorLength = (slotCount - 1) * slotPitch + segmentLength
	local centerOffsetX = (slotCount - 1) * slotPitch / 2
	local base = createPart(
		plot,
		"FactoryPlatform",
		Vector3.new(conveyorLength + plotConfig.BaseLengthPadding, plotConfig.BaseThickness, plotConfig.BaseWidth),
		origin + Vector3.new(centerOffsetX, plotConfig.BaseCenterY, 0),
		colorFromRgb(plotConfig.BaseColor)
	)
	base.Material = Enum.Material.WoodPlanks
	base.CanCollide = true

	local conveyor = createConveyor(plot, origin)
	alignToPlot(plot, plotFrame(origin, plotIndex))
	return plot, origin, conveyor
end

local function updateDebugAttributes(player: Player, factory: any)
	local snapshot = factory.simulation:getSnapshot()
	player:SetAttribute("FactoryCoins", snapshot.Coins)
	player:SetAttribute("FactoryActiveItems", snapshot.ActiveItems)
	player:SetAttribute("FactoryProducedItems", snapshot.ProducedItems)
	player:SetAttribute("FactorySoldItems", snapshot.SoldItems)
	player:SetAttribute("FactoryTotalValueSold", snapshot.TotalValueSold)
	player:SetAttribute("FactoryDroppedItemsAtCap", snapshot.DroppedItemsAtCap)
	player:SetAttribute("FactoryCapacity", factory.capacity)
	player:SetAttribute("FactoryLayout", table.concat(layoutForClient(factory.layout), ","))
end

local function refreshMachineVisuals(factory: any)
	local machineFolder = factory.plot:FindFirstChild("Machines")
	if machineFolder then
		machineFolder:Destroy()
	end
	machineFolder = Instance.new("Folder")
	machineFolder.Name = "Machines"
	machineFolder.Parent = factory.plot
	factory.sellerHitbox = nil

	for slotIndex = 1, FactoryLayout.EditableSlotCount do
		local selector = factory.conveyor:FindFirstChild(string.format("SlotSelector_%d", slotIndex))
		local detector = selector and selector:FindFirstChild("FactorySlotClick")
		if detector and detector:IsA("ClickDetector") then
			detector.MaxActivationDistance = 32
		end
	end

	for slotIndex = 1, FactoryLayout.SlotCount do
		local machineId = factory.layout[slotIndex]
		if machineId then
			local definition = MachineDefinitions.get(machineId)
			if definition then
				local model, clickPart, sellerHitbox = MachineModelBuilder.build(machineFolder, factory.origin, slotIndex, definition)
				alignToPlot(model, factory.frame)
				if sellerHitbox then factory.sellerHitbox = sellerHitbox end
				for _, part in ipairs(model:GetChildren()) do
					if part:IsA("BasePart") and part ~= sellerHitbox then addSlotClickDetector(part, slotIndex) end
				end
				clickPart:SetAttribute("MachineId", definition.Id)
				clickPart:SetAttribute("DisplayName", definition.DisplayName)
				clickPart:SetAttribute("Description", definition.Description)
				clickPart:SetAttribute("Rarity", definition.Rarity)
				clickPart:SetAttribute("Behavior", definition.Behavior or definition.Category)

			end
		end
	end
end

local function updateVisualItems(player: Player, factory: any): boolean
	local activeItems = factory.simulation:getActiveItemsForDebug()
	local activeById = {}
	local visualConfig = MachineVisualConfig.ConveyorItem
	local buffModifiers = getSaleBuffModifiers(player)
	local seller = MachineDefinitions.get(factory.layout[FactoryLayout.SellerSlotIndex])
	local soldAny = false
	factory.itemPresentationState = factory.itemPresentationState or {}
	local function setAttribute(part: BasePart, name: string, value: any)
		if part:GetAttribute(name) ~= value then part:SetAttribute(name, value) end
	end
	for _, item in ipairs(activeItems) do
		activeById[item.Id] = true
		local visual = factory.visualItems[item.Id]
		if not visual then
			visual = createPart(factory.plot, string.format("Item_%d", item.Id), Vector3.new(visualConfig.Size, visualConfig.Size, visualConfig.Size), factory.frame:PointToWorldSpace(Vector3.new(0, visualConfig.DropStartHeight + MachineVisualConfig.Conveyor.Elevation, 0)), Color3.fromRGB(235, 235, 235))
			visual.Material = Enum.Material.SmoothPlastic
			visual:SetAttribute("FactoryItem", true)
			visual:SetAttribute("OwnerUserId", player.UserId)
			visual:SetAttribute("ItemId", item.Id)
			factory.visualItems[item.Id] = visual
		end
		local cubeColor = cubeTypeColorCache[item.TypeId]
		if not cubeColor then
			local cubeType = CubeTypeDefinitions.get(item.TypeId)
			local color = cubeType and cubeType.Color
			cubeColor = if color then Color3.fromRGB(color[1], color[2], color[3]) else Color3.fromRGB(235, 235, 235)
			cubeTypeColorCache[item.TypeId] = cubeColor
		end
		local stateColors = {
			Base = cubeColor,
			Painted = Color3.fromRGB(255, 105, 160),
			Golden = Color3.fromRGB(255, 211, 66),
		}
		local size = visualConfig.Size * math.clamp(item.SizeScale or 1, 0.5, 4)
		local nextSize = Vector3.new(size, size, size)
		if visual.Size ~= nextSize then visual.Size = nextSize end
		local nextColor = stateColors[item.VisualState] or stateColors.Base
		if visual.Color ~= nextColor then visual.Color = nextColor end

		local x, y = FactoryItemGeometry.itemPosition(factory.layout, item)
		local nextPosition = factory.frame:PointToWorldSpace(Vector3.new(x, y, 0))
		if visual.Position ~= nextPosition then visual.Position = nextPosition end
		local cache = factory.itemPresentationState[item.Id]
		local sellerModifiers = factory.simulation:getSaleModifiers(item.Id) or (seller and seller.SaleModifiers)
		local typeAdd, typeMult = item.TypeModifiers.AdditiveBonus or 0, item.TypeModifiers.Multiplier or 1
		local buffAdd, buffMult = buffModifiers.AdditiveBonus or 0, buffModifiers.Multiplier or 1
		local sellerAdd, sellerMult = if sellerModifiers then sellerModifiers.AdditiveBonus or 0 else 0, if sellerModifiers then sellerModifiers.Multiplier or 1 else 1
		if not cache or cache.Value ~= item.Value or cache.Count ~= #item.ModifierLabels
			or cache.TypeAdd ~= typeAdd or cache.TypeMult ~= typeMult
			or cache.BuffAdd ~= buffAdd or cache.BuffMult ~= buffMult
			or cache.SellerAdd ~= sellerAdd or cache.SellerMult ~= sellerMult then
			local breakdown = SaleValueRules.getBreakdown(item.Value, item.TypeModifiers, buffModifiers, sellerModifiers, FactoryConfig.MaxItemValue)
			setAttribute(visual, "ItemValue", item.Value)
			setAttribute(visual, "ItemBaseValue", item.BaseValue)
			setAttribute(visual, "ItemType", item.TypeId)
			setAttribute(visual, "ItemModifiers", table.concat(item.ModifierLabels, " · "))
			setAttribute(visual, "ItemChainMultiplier", item.Value / item.BaseValue)
			if breakdown then
				setAttribute(visual, "ItemSaleValue", breakdown.Value)
				setAttribute(visual, "ItemSaleMultiplier", breakdown.Multiplier)
				setAttribute(visual, "ItemAdditiveBonus", breakdown.AdditiveBonus)
			end
			local layers = {}
			local function describeLayer(name: string, layer: any)
				if layer and ((layer.AdditiveBonus or 0) ~= 0 or (layer.Multiplier or 1) ~= 1) then
					table.insert(layers, name .. " +" .. NumberFormatter.format(layer.AdditiveBonus or 0) .. " ×" .. NumberFormatter.format(layer.Multiplier or 1))
				end
			end
			describeLayer("Type", item.TypeModifiers)
			describeLayer("Buff", buffModifiers)
			describeLayer("Seller", sellerModifiers)
			setAttribute(visual, "ItemSaleLayers", if #layers > 0 then table.concat(layers, " · ") else "No sale bonuses")
			factory.itemPresentationState[item.Id] = { Value = item.Value, Count = #item.ModifierLabels,
				TypeAdd = typeAdd, TypeMult = typeMult, BuffAdd = buffAdd, BuffMult = buffMult, SellerAdd = sellerAdd, SellerMult = sellerMult }
		end

		local sellerHitbox = factory.sellerHitbox
		if item.ReadyForSale and sellerHitbox and overlapsHitbox(sellerHitbox, visual) then
			local sold, credited = factory.simulation:sellItem(item.Id, buffModifiers)
			if sold then
				soldAny = true
				EffectService.fire(player, "ItemSold", { Coins = credited, Balance = factory.simulation:getCoins(), Position = visual.Position, ItemId = item.Id })
				activeById[item.Id] = nil
			end
		end
	end

	if soldAny then updateDebugAttributes(player, factory) end

	for itemId, visual in pairs(factory.visualItems) do
		if not activeById[itemId] then
			visual:Destroy()
			factory.visualItems[itemId] = nil
			factory.itemPresentationState[itemId] = nil
		end
	end
	return soldAny
end

local function buildResponse(factory: any, success: boolean, reason: string?): { [string]: any }
	return {
		Success = success,
		Reason = reason,
		Layout = layoutForClient(factory.layout),
		Inventory = copyInventory(factory.inventory),
	}
end

local function isRateLimited(player: Player): boolean
	local now = os.clock()
	local previous = lastRequestAt[player] or 0
	if now - previous < 0.1 then
		return true
	end
	lastRequestAt[player] = now
	return false
end

local function dataIsReady(player: Player): boolean
	return player:GetAttribute("FactoryDataReady") == true
end

local function commitLayout(factory: any, layout: FactoryLayout.Layout): (boolean, string?)
	local valid, errorMessage = PlacementRules.validateLayout(layout, factory.capacity)
	if not valid then
		return false, errorMessage
	end
	local route = FactoryLayout.toRoute(layout)
	local success, routeError = pcall(function()
		factory.simulation:setRoute(route)
	end)
	if not success then
		return false, tostring(routeError)
	end
	factory.layout = FactoryLayout.copy(layout)
	refreshMachineVisuals(factory)
	return true
end

local function placeMachine(player: Player, machineId: any, slotIndex: any, replaceRequested: any)
	local factory = factories[player]
	if not factory then
		return { Success = false, Reason = "Factory is not ready" }
	end
	if not dataIsReady(player) then
		return buildResponse(factory, false, "Factory data is loading")
	end
	if isRateLimited(player) then
		return buildResponse(factory, false, "Too many requests")
	end
	local valid, errorMessage = PlacementRules.validateMachineForSlot(machineId, slotIndex)
	if not valid then
		return buildResponse(factory, false, errorMessage)
	end
	local previousMachineId = factory.layout[slotIndex]
	if previousMachineId and replaceRequested ~= true then
		return buildResponse(factory, false, "Slot is occupied")
	end
	if (factory.inventory[machineId] or 0) <= 0 then
		return buildResponse(factory, false, "Machine is not in inventory")
	end

	local candidate, candidateError = PlacementRules.createPlacementLayout(factory.layout, machineId, slotIndex, factory.capacity)
	if not candidate then
		return buildResponse(factory, false, candidateError)
	end
	local nextInventory = copyInventory(factory.inventory)
	nextInventory[machineId] = (nextInventory[machineId] or 0) - 1
	if nextInventory[machineId] <= 0 then
		nextInventory[machineId] = nil
	end
	if previousMachineId then
		nextInventory[previousMachineId] = (nextInventory[previousMachineId] or 0) + 1
	end
	for otherSlot = 1, FactoryLayout.SlotCount do
		local oldMachineId = factory.layout[otherSlot]
		if otherSlot ~= slotIndex and oldMachineId and candidate[otherSlot] ~= oldMachineId then
			nextInventory[oldMachineId] = (nextInventory[oldMachineId] or 0) + 1
		end
	end

	local committed, commitError = commitLayout(factory, candidate)
	if not committed then
		return buildResponse(factory, false, commitError)
	end
	factory.inventory = nextInventory
	AnalyticsService.record(player, "MachinePlaced")
	EffectService.fire(player, "InventoryChanged")
	return buildResponse(factory, true)
end

local function removeMachine(player: Player, slotIndex: any)
	local factory = factories[player]
	if not factory then
		return { Success = false, Reason = "Factory is not ready" }
	end
	if not dataIsReady(player) then
		return buildResponse(factory, false, "Factory data is loading")
	end
	if isRateLimited(player) then
		return buildResponse(factory, false, "Too many requests")
	end
	local machineId = factory.layout[slotIndex]
	if not machineId then
		return buildResponse(factory, false, "Slot is already empty")
	end
	local definition = MachineDefinitions.get(machineId)
	if definition and (definition.Category == "Producer" or definition.Category == "Seller") then
		return buildResponse(factory, false, "Keep the dropper at the start and a seller at the route end")
	end
	local candidate, candidateError = PlacementRules.createRemoveLayout(factory.layout, slotIndex, factory.capacity)
	if not candidate then
		return buildResponse(factory, false, candidateError)
	end
	local committed, commitError = commitLayout(factory, candidate)
	if not committed then
		return buildResponse(factory, false, commitError)
	end
	factory.inventory[machineId] = (factory.inventory[machineId] or 0) + 1
	AnalyticsService.record(player, "MachineRemoved")
	EffectService.fire(player, "InventoryChanged")
	return buildResponse(factory, true)
end

local function moveMachine(player: Player, sourceSlotIndex: any, destinationSlotIndex: any)
	local factory = factories[player]
	if not factory then
		return { Success = false, Reason = "Factory is not ready" }
	end
	if not dataIsReady(player) then
		return buildResponse(factory, false, "Factory data is loading")
	end
	if isRateLimited(player) then
		return buildResponse(factory, false, "Too many requests")
	end
	local candidate, candidateError = PlacementRules.createMoveLayout(factory.layout, sourceSlotIndex, destinationSlotIndex, factory.capacity)
	if not candidate then
		return buildResponse(factory, false, candidateError)
	end
	local committed, commitError = commitLayout(factory, candidate)
	if not committed then
		return buildResponse(factory, false, commitError)
	end
	AnalyticsService.record(player, "MachineMoved")
	EffectService.fire(player, "InventoryChanged")
	return buildResponse(factory, true)
end

local function createFactory(player: Player)
	if factories[player] then
		return
	end
	local plotIndex = IslandWorldConfig.findFreePlot(occupiedPlots)
	if not plotIndex then
		player:Kick("All six factory islands are occupied. Please join another server.")
		return
	end
	occupiedPlots[plotIndex] = true
	player:SetAttribute("FactoryBuildVersion", FactoryConfig.BuildVersion)
	if player:GetAttribute("FactoryDataReady") == nil then
		player:SetAttribute("FactoryDataReady", false)
	end
	local simulation = FactorySimulation.new({ Route = FactoryLayout.toRoute(FactoryLayout.Default) })
	local plot, origin, conveyor = createIslandPlot(player, plotIndex)
	local factory = {
		simulation = simulation,
		plot = plot,
		conveyor = conveyor,
		origin = origin,
		plotIndex = plotIndex,
		layout = FactoryLayout.copy(FactoryLayout.Default),
		capacity = 1,
		inventory = {},
		boosterInventory = {},
		visualItems = {},
		announcedSpawn = false,
		announcedSale = false,
		-- Where the player is placed on join and after a fall; the island spawn when the map has one.
		frame = plotFrame(origin, plotIndex),
		homeCFrame = plotFrame(origin, plotIndex) * CFrame.new(IslandWorldConfig.FactoryCenterOffsetX, 4, 15),
	}
	factories[player] = factory
	local world = workspace:FindFirstChild(IslandWorldConfig.MapKey)
	local island = if world then world:FindFirstChild(string.format("StarterIsland_%02d", plotIndex)) else nil
	local islandSpawn = if island then island:FindFirstChild("IslandSpawn") else nil
	if islandSpawn and islandSpawn:IsA("SpawnLocation") then
		islandSpawn.Enabled = true
		player.RespawnLocation = islandSpawn
		island:SetAttribute("OwnerUserId", player.UserId)
		factory.homeCFrame = CFrame.new(islandSpawn.Position + Vector3.new(0, 3, 0))
	end
	local function placeCharacter(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and factories[player] == factory and character.Parent then
			character:PivotTo(factory.homeCFrame)
		end
	end
	factory.characterConnection = player.CharacterAdded:Connect(placeCharacter)
	if player.Character then task.spawn(placeCharacter, player.Character) end
	refreshMachineVisuals(factory)
	updateDebugAttributes(player, factory)
end

local function removeFactory(player: Player)
	local factory = factories[player]
	if factory then
		occupiedPlots[factory.plotIndex] = nil
		if factory.characterConnection then factory.characterConnection:Disconnect() end
		player.RespawnLocation = nil
		local world = workspace:FindFirstChild(IslandWorldConfig.MapKey)
		local island = if world then world:FindFirstChild(string.format("StarterIsland_%02d", factory.plotIndex)) else nil
		if island then
			island:SetAttribute("OwnerUserId", nil)
			local spawn = island:FindFirstChild("IslandSpawn")
			if spawn and spawn:IsA("SpawnLocation") then spawn.Enabled = false end
		end
		factory.plot:Destroy()
		factories[player] = nil
	end
	lastRequestAt[player] = nil
end

local function createRemotes()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	local factoryRemotes = remotes:FindFirstChild("Factory")
	if not factoryRemotes then
		factoryRemotes = Instance.new("Folder")
		factoryRemotes.Name = "Factory"
		factoryRemotes.Parent = remotes
	end

	local function remoteFunction(name: string): RemoteFunction
		local remote = factoryRemotes:FindFirstChild(name) :: RemoteFunction?
		if not remote then
			remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = factoryRemotes
		end
		return remote
	end

	remoteFunction("PlaceMachine").OnServerInvoke = placeMachine
	remoteFunction("RemoveMachine").OnServerInvoke = removeMachine
	remoteFunction("MoveMachine").OnServerInvoke = moveMachine
	remoteFunction("GetFactoryState").OnServerInvoke = FactoryService.getClientState
end

function FactoryService.getSimulation(player: Player): any?
	local factory = factories[player]
	return factory and factory.simulation
end

function FactoryService.getState(player: Player): any?
	return factories[player]
end

function FactoryService.getClientState(player: Player): { [string]: any }
	local factory = factories[player]
	if not factory then
		return { Success = false, Reason = "Factory is not ready" }
	end
	return {
		Success = true,
		Layout = layoutForClient(factory.layout),
		Inventory = copyInventory(factory.inventory),
		BoosterInventory = copyInventory(factory.boosterInventory),
		Capacity = factory.capacity,
		SlotCount = FactoryLayout.SlotCount,
	}
end

function FactoryService.setCapacity(player: Player, capacity: number): (boolean, string?)
	local factory = factories[player]
	if not factory then
		return false, "Factory is not ready"
	end
	if capacity < factory.capacity or capacity > FactoryConfig.MaxFactoryCapacity then
		return false, "Invalid capacity change"
	end
	factory.capacity = capacity
	updateDebugAttributes(player, factory)
	return true
end

function FactoryService.getPersistentState(player: Player): { [string]: any }?
	local factory = factories[player]
	if not factory then
		return nil
	end
	return {
		Coins = factory.simulation:getCoins(),
		Layout = FactoryLayout.copy(factory.layout),
		Inventory = copyInventory(factory.inventory),
		BoosterInventory = copyInventory(factory.boosterInventory),
		Capacity = factory.capacity,
		Statistics = (function()
			local snapshot = factory.simulation:getSnapshot()
			return {
				ProducedItems = snapshot.ProducedItems,
				SoldItems = snapshot.SoldItems,
				TotalValueSold = snapshot.TotalValueSold,
				DroppedItemsAtCap = snapshot.DroppedItemsAtCap,
			}
		end)(),
	}
end

function FactoryService.applyPersistentState(player: Player, data: { [string]: any }): (boolean, string?)
	local factory = factories[player]
	if not factory then
		return false, "Factory is not ready"
	end
	local valid, errorMessage = PlacementRules.validateLayout(data.Layout, data.Capacity)
	if not valid then
		return false, errorMessage
	end
	local route = FactoryLayout.toRoute(data.Layout)
	local routeApplied, routeError = pcall(function()
		factory.simulation:setRoute(route)
	end)
	if not routeApplied then
		return false, tostring(routeError)
	end
	factory.capacity = data.Capacity
	factory.layout = FactoryLayout.copy(data.Layout)
	factory.inventory = copyInventory(data.Inventory)
	factory.boosterInventory = copyInventory(data.BoosterInventory)
	factory.simulation:setCoins(data.Coins)
	refreshMachineVisuals(factory)
	updateDebugAttributes(player, factory)
	return true
end

function FactoryService.start()
	if started then
		return
	end
	started = true
	createRemotes()
	Players.PlayerAdded:Connect(createFactory)
	Players.PlayerRemoving:Connect(function(player)
		-- DataService saves on the same signal. Deferring teardown lets its
		-- handler read the final factory state before the plot is destroyed.
		task.defer(removeFactory, player)
	end)
	for _, player in Players:GetPlayers() do
		createFactory(player)
	end

	RunService.Heartbeat:Connect(function(deltaTime)
		attributeUpdateAccumulator += deltaTime
		visualUpdateAccumulator += deltaTime
		local shouldUpdateVisuals = visualUpdateAccumulator >= VISUAL_UPDATE_INTERVAL_SECONDS
		if shouldUpdateVisuals then visualUpdateAccumulator %= VISUAL_UPDATE_INTERVAL_SECONDS end
		for player, factory in pairs(factories) do
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			-- In the lagoon (missed parkour jump, swimming, or falling off the map): return home.
			if root and root:IsA("BasePart") and root.Position.Y < IslandWorldConfig.FallRecoveryY then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				character:PivotTo(factory.homeCFrame)
			end
			if not dataIsReady(player) then continue end
			local produced = factory.simulation:step(deltaTime)
			local sold = if shouldUpdateVisuals then updateVisualItems(player, factory) else false
			if not factory.announcedSpawn and produced then
				factory.announcedSpawn = true
				AnalyticsService.record(player, "FirstItemProduced")
				EffectService.fire(player, "FirstItemSpawned")
			end
			if not factory.announcedSale and sold then
				factory.announcedSale = true
				AnalyticsService.record(player, "FirstItemSold")
				EffectService.fire(player, "FirstItemSold", { Coins = factory.simulation:getCoins() })
			end
			if attributeUpdateAccumulator >= 0.25 then updateDebugAttributes(player, factory) end
		end
		if attributeUpdateAccumulator >= 0.25 then attributeUpdateAccumulator = 0 end
	end)
end

return FactoryService
