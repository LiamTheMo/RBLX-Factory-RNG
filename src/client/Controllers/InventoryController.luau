--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MachineDefinitions = require(Shared:WaitForChild("MachineDefinitions"))
local FactoryLayout = require(Shared:WaitForChild("FactoryLayout"))
local PlacementRules = require(Shared:WaitForChild("PlacementRules"))
local EconomyConfig = require(Shared:WaitForChild("EconomyConfig"))
local EconomyRules = require(Shared:WaitForChild("EconomyRules"))
local BoosterConfig = require(Shared:WaitForChild("BoosterConfig"))
local HudLayout = require(Shared:WaitForChild("HudLayout"))
local ModelBuilder = require(Shared:WaitForChild("MachineModelBuilder"))
local MachineEffects = require(Shared:WaitForChild("MachineEffects"))
local MachineModifiers = require(Shared:WaitForChild("MachineModifiers"))

local GlassUI = require(script.Parent.GlassUI)

local Theme = GlassUI.Theme
local C = Theme.Colors

local TABS = {
	{ Category = "Producer", Title = "Droppers" },
	{ Category = "Processor", Title = "Upgraders" },
	{ Category = "Seller", Title = "Sellers" },
	{ Category = "Booster", Title = "Boosters" },
}

local InventoryController = {}
local started = false
local openPanel: ((string, number?, string?) -> ())? = nil
local closePanel: (() -> ())? = nil
local openListeners: { () -> () } = {}
local targetListeners: { (number?) -> () } = {}

local rarityColors: { [string]: Color3 } = {}
for _, band in ipairs(EconomyConfig.RarityOddsBands) do
	rarityColors[band.Name] = GlassUI.fromRgb(band.Color)
end

local function rarityColor(rarity: string): Color3
	return rarityColors[rarity] or C.Text
end

local function clearRows(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

function InventoryController.openInventory(category: string?)
	if openPanel then
		openPanel("Inventory", nil, category)
	end
end

function InventoryController.openPlacement(slotIndex: number)
	if openPanel then
		openPanel("Placement", slotIndex)
	end
end

function InventoryController.close()
	if closePanel then
		closePanel()
	end
end

-- Lets other HUD panels that share screen space close when the drawer opens.
function InventoryController.onOpen(listener: () -> ())
	table.insert(openListeners, listener)
end

-- Reports the conveyor slot whose placement panel is open (nil when none) for world highlights.
function InventoryController.onPlacementTarget(listener: (number?) -> ())
	table.insert(targetListeners, listener)
end

function InventoryController.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Factory")
	local getFactoryState = remotes:WaitForChild("GetFactoryState") :: RemoteFunction
	local placeMachine = remotes:WaitForChild("PlaceMachine") :: RemoteFunction
	local removeMachine = remotes:WaitForChild("RemoveMachine") :: RemoteFunction
	local moveMachine = remotes:WaitForChild("MoveMachine") :: RemoteFunction
	local sellMachine = remotes:WaitForChild("SellMachine") :: RemoteFunction
	local useBooster = remotes:WaitForChild("UseBooster") :: RemoteFunction
	local presentationEvent = remotes:WaitForChild("PresentationEvent") :: RemoteEvent

	local screenGui = GlassUI.screen(playerGui, "FactoryInventoryHud", 15)

	-- Persistent Inventory button, bottom left.
	local inventoryButton = GlassUI.button(screenGui, "InventoryButton", "", "Secondary")
	inventoryButton:SetAttribute("GlassBaseTransparency", Theme.Transparency.Glass)
	GlassUI.setStyle(inventoryButton, "Secondary")
	inventoryButton.BackgroundColor3 = C.Glass
	GlassUI.setRadius(inventoryButton, 16)
	local buttonScale = inventoryButton:FindFirstChildOfClass("UIScale")
	local boxIcon = GlassUI.icon(inventoryButton, "Box")
	boxIcon.AnchorPoint = Vector2.new(0, 0.5)
	local buttonCaption = GlassUI.label(inventoryButton, "Caption", "Inventory", 16, Theme.Fonts.Bold)
	buttonCaption.TextWrapped = false
	local countBadge = Instance.new("TextLabel")
	countBadge.Name = "CountBadge"
	countBadge.AnchorPoint = Vector2.new(0.5, 0.5)
	countBadge.Position = UDim2.new(1, -4, 0, 4)
	countBadge.Size = UDim2.fromOffset(24, 24)
	countBadge.BackgroundColor3 = C.Accent
	countBadge.TextColor3 = C.AccentText
	countBadge.FontFace = Theme.Fonts.Heavy
	countBadge.TextSize = 11
	countBadge.Text = "0"
	countBadge.Visible = false
	GlassUI.round(countBadge)
	countBadge.Parent = inventoryButton

	-- Inventory drawer.
	local panel = GlassUI.glass(screenGui, "MachinePanel")
	panel.Visible = false
	local panelScale = Instance.new("UIScale")
	panelScale.Parent = panel

	local title = GlassUI.label(panel, "PanelTitle", "Inventory", 22, Theme.Fonts.Heavy)
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local subtitle = GlassUI.label(panel, "Subtitle", "", 12)
	subtitle.TextColor3 = C.Muted

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Text = ""
	closeButton.BackgroundTransparency = 1
	closeButton.AutoButtonColor = false
	closeButton.Parent = panel
	local closeFace = GlassUI.glass(closeButton, "Face", 999)
	closeFace.AnchorPoint = Vector2.new(0.5, 0.5)
	closeFace.Position = UDim2.fromScale(0.5, 0.5)
	closeFace.Size = UDim2.fromOffset(34, 34)
	local closeIcon = GlassUI.icon(closeFace, "Close")
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)
	closeIcon.Size = UDim2.fromOffset(14, 14)

	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.BackgroundColor3 = C.Stroke
	tabBar.BackgroundTransparency = 0.94
	tabBar.BorderSizePixel = 0
	GlassUI.corner(tabBar, 12)
	tabBar.Parent = panel
	local categoryTabs: { [string]: TextButton } = {}
	for index, tab in ipairs(TABS) do
		local button = GlassUI.button(tabBar, tab.Category .. "Tab", tab.Title, "Ghost", 13)
		button.Position = UDim2.new((index - 1) / #TABS, 4, 0, 4)
		button.Size = UDim2.new(1 / #TABS, -8, 1, -8)
		button.TextWrapped = false
		button.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MinTextSize = 9
		limit.MaxTextSize = 14
		limit.Parent = button
		GlassUI.padding(button, 6, 8)
		categoryTabs[tab.Category] = button
	end

	local backButton = GlassUI.button(panel, "BackButton", "‹  Back to inventory", "Ghost", 13)
	backButton.Visible = false

	local status = GlassUI.label(panel, "Status", "Loading factory inventory...", 12)
	status.TextColor3 = C.Muted
	status.TextWrapped = false
	status.TextTruncate = Enum.TextTruncate.AtEnd

	local list = Instance.new("ScrollingFrame")
	list.Name = "MachineList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = if UserInputService.TouchEnabled then 3 else 4
	list.ScrollBarImageColor3 = C.Muted
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.Parent = panel
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.PaddingLeft = UDim.new(0, 2)
	listPadding.PaddingRight = UDim.new(0, 6)
	listPadding.PaddingTop = UDim.new(0, 2)
	listPadding.Parent = list
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list

	local empty = GlassUI.label(panel, "EmptyInventory", "", 13)
	empty.TextColor3 = C.Muted
	empty.TextXAlignment = Enum.TextXAlignment.Center
	empty.Visible = false

	local state: any = nil
	local metrics = HudLayout.measure(1024, 768)
	local touch = Theme.MinTouch
	local cardHeight = 290
	local mode = "Inventory"
	local activeCategory = "Producer"
	local targetSlot: number? = nil
	local lastOwned: number? = nil
	local panelTarget = UDim2.new()

	local function setStatus(message: string, success: boolean?)
		status.Text = message
		status.TextColor3 = if success == true then C.Good elseif success == false then C.Bad else C.Muted
	end

	local function invoke(remote: RemoteFunction, ...: any): any
		local arguments = { ... }
		local success, result = pcall(function()
			return remote:InvokeServer(table.unpack(arguments))
		end)
		if not success then
			setStatus("Request failed. Try again.", false)
			return nil
		end
		return result
	end

	local function normalizeLayout(): { [number]: string }
		local result: { [number]: string } = {}
		if not state then
			return result
		end
		for slotIndex = 1, state.SlotCount or FactoryLayout.SlotCount do
			local machineId = state.Layout and state.Layout[slotIndex]
			if type(machineId) == "string" and machineId ~= "" then
				result[slotIndex] = machineId
			end
		end
		return result
	end

	local function getCounts(): ({ string }, { [string]: number }, { [string]: number }, { [string]: number })
		local totals: { [string]: number } = {}
		local placed: { [string]: number } = {}
		local available: { [string]: number } = {}
		for machineId in pairs(MachineDefinitions.all()) do
			totals[machineId] = 0
			placed[machineId] = 0
		end
		for machineId, quantity in pairs(state and state.Inventory or {}) do
			local count = math.max(0, math.floor(tonumber(quantity) or 0))
			available[machineId] = count
			totals[machineId] = (totals[machineId] or 0) + count
			placed[machineId] = placed[machineId] or 0
		end
		local layout = normalizeLayout()
		for slotIndex = 1, state.SlotCount or FactoryLayout.SlotCount do
			local machineId = layout[slotIndex]
			if machineId then
				placed[machineId] = (placed[machineId] or 0) + 1
				totals[machineId] = (totals[machineId] or 0) + 1
			end
		end
		local ids = {}
		for machineId, count in pairs(totals) do
			if count > 0 then
				table.insert(ids, machineId)
			end
		end
		table.sort(ids, function(left, right)
			local leftDefinition = MachineDefinitions.get(left)
			local rightDefinition = MachineDefinitions.get(right)
			local leftName = leftDefinition and leftDefinition.DisplayName or left
			local rightName = rightDefinition and rightDefinition.DisplayName or right
			return leftName < rightName
		end)
		return ids, totals, placed, available
	end

	local render: () -> ()
	local function refresh()
		local response = invoke(getFactoryState)
		if response and response.Success then
			state = response
			render()
		elseif response then
			setStatus(response.Reason or "Factory is not ready.", false)
		end
	end

	local function setGrid()
		grid.CellSize = UDim2.new(1 / metrics.Columns, -10, 0, cardHeight)
	end

	local announcedTarget: number? = nil
	local function announceTarget()
		local slot = if panel.Visible and mode == "Placement" then targetSlot else nil
		if slot ~= announcedTarget then
			announcedTarget = slot
			for _, listener in ipairs(targetListeners) do
				task.spawn(listener, slot)
			end
		end
	end

	-- Shared card chrome: preview well, name, rarity chip, odds, counts and a button row.
	local function makeCard(name: string, order: number, tint: Color3, displayName: string, chipText: string, odds: string, details: string): (Frame, Frame, Frame)
		local row = metrics.CardStyle == "Row"
		local card = GlassUI.card(list, name, tint)
		card.LayoutOrder = order
		local well = Instance.new("Frame")
		well.Name = "PreviewWell"
		well.BackgroundColor3 = C.Stroke
		well.BackgroundTransparency = 0.95
		well.BorderSizePixel = 0
		GlassUI.corner(well, 10)
		well.Position = UDim2.fromOffset(8, 8)
		well.Size = if row then UDim2.new(0.34, -8, 1, -16) else UDim2.new(1, -16, 0, cardHeight - 132 - touch)
		well.Parent = card
		local infoX = if row then 0.34 else 0
		local infoTop = if row then 10 else cardHeight - 118 - touch
		local nameLabel = GlassUI.label(card, if name:sub(1, 8) == "Booster_" then "BoosterName" else "MachineName", displayName, 15, Theme.Fonts.Bold)
		nameLabel.Position = UDim2.new(infoX, 10, 0, infoTop)
		nameLabel.Size = UDim2.new(1 - infoX, -20, 0, 20)
		nameLabel.TextWrapped = false
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextXAlignment = if row then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
		local chipRow = Instance.new("Frame")
		chipRow.Name = "Tags"
		chipRow.BackgroundTransparency = 1
		chipRow.Position = UDim2.new(infoX, 10, 0, infoTop + 26)
		chipRow.Size = UDim2.new(1 - infoX, -20, 0, 22)
		chipRow.Parent = card
		local chipLayout = Instance.new("UIListLayout")
		chipLayout.FillDirection = Enum.FillDirection.Horizontal
		chipLayout.HorizontalAlignment = if row then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center
		chipLayout.Padding = UDim.new(0, 6)
		chipLayout.Parent = chipRow
		GlassUI.chip(chipRow, "Rarity", chipText, tint, 11)
		local oddsLabel = GlassUI.label(card, if name:sub(1, 8) == "Booster_" then "BoosterEffect" else "RollOdds", odds, 12, Theme.Fonts.Medium)
		oddsLabel.Position = UDim2.new(infoX, 10, 0, infoTop + 54)
		oddsLabel.Size = UDim2.new(1 - infoX, -20, 0, 16)
		oddsLabel.TextWrapped = false
		oddsLabel.TextTruncate = Enum.TextTruncate.AtEnd
		oddsLabel.TextXAlignment = nameLabel.TextXAlignment
		local detailLabel = GlassUI.label(card, if name:sub(1, 8) == "Booster_" then "BoosterDetails" else "MachineDetails", details, 11)
		detailLabel.Position = UDim2.new(infoX, 10, 0, infoTop + 72)
		detailLabel.Size = UDim2.new(1 - infoX, -20, 0, 16)
		detailLabel.TextColor3 = C.Muted
		detailLabel.TextWrapped = false
		detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
		detailLabel.TextXAlignment = nameLabel.TextXAlignment
		local actions = Instance.new("Frame")
		actions.Name = "Actions"
		actions.BackgroundTransparency = 1
		actions.Position = UDim2.new(infoX, 10, 1, -touch - 10)
		actions.Size = UDim2.new(1 - infoX, -20, 0, touch)
		actions.Parent = card
		local actionLayout = Instance.new("UIListLayout")
		actionLayout.FillDirection = Enum.FillDirection.Horizontal
		actionLayout.Padding = UDim.new(0, 8)
		actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
		actionLayout.Parent = actions
		return card, well, actions
	end

	-- Buttons share the action row; `weight` splits its width (Place gets more than Recycle).
	local function addAction(actions: Frame, name: string, text: string, style: GlassUI.ButtonStyle, weight: number, order: number): TextButton
		local button = GlassUI.button(actions, name, text, style, 13)
		button.LayoutOrder = order
		button.Size = UDim2.new(weight, if weight < 1 then -4 else 0, 1, 0)
		return button
	end

	local function addPreview(well: Frame, definition: any)
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "MachinePreview"
		viewport.BackgroundTransparency = 1
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.Ambient = Color3.fromRGB(205, 212, 224)
		viewport.LightColor = Color3.fromRGB(255, 244, 225)
		viewport.LightDirection = Vector3.new(-1, -1, -1)
		viewport.Parent = well
		local world = Instance.new("WorldModel")
		world.Parent = viewport
		local model = ModelBuilder.build(world, Vector3.zero, 1, definition)
		for _, child in ipairs(model:GetDescendants()) do
			if child:IsA("BasePart") and child.Transparency == 1 then
				child:Destroy()
			end
		end
		local box, size = model:GetBoundingBox()
		local camera = Instance.new("Camera")
		camera.FieldOfView = 35
		local distance = math.max(size.X, size.Y, size.Z) * 2.3
		camera.CFrame = CFrame.lookAt(box.Position + Vector3.new(-distance, distance * 0.65, -distance), box.Position)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end

	local function machineCard(machineId: string, order: number, isPlacement: boolean, details: string): (Frame, Frame)
		local definition = MachineDefinitions.get(machineId)
		local rarity = definition and definition.Rarity or "Common"
		local odds = if definition and definition.Rollable then EconomyRules.getMachineOddsLabel(machineId, MachineDefinitions.getRollPool()) else "Starter"
		local name = if isPlacement then string.format("Place_%s_%d", machineId, order) else "Owned_" .. machineId
		-- The chip carries what the machine does (rarity-tinted); rarity and odds share the line below.
		local effect = if definition then MachineEffects.tag(definition) else rarity
		-- Odds include any modifiers (Golden 1/100 turns 1/10 into 1/1,000); the source says where to roll it.
		local oddsText = if odds and odds ~= "Starter" then `{rarity} · Odds {odds} · {MachineDefinitions.describeSources(definition)}` else `{rarity} · Starter`
		local card, well, actions = makeCard(name, order, rarityColor(rarity), definition and definition.DisplayName or machineId, effect, oddsText, details)
		card:SetAttribute("Description", definition and definition.Description or "")
		if definition then
			addPreview(well, definition)
			-- Corner badges on the preview: the machine's job, then any rolled modifiers.
			local badges = Instance.new("Frame")
			badges.Name = "Badges"
			badges.BackgroundTransparency = 1
			badges.Position = UDim2.fromOffset(6, 6)
			badges.Size = UDim2.new(1, -12, 1, -12)
			badges.ZIndex = 2
			-- Narrow phone rows: never let a badge spill over the card text.
			badges.ClipsDescendants = true
			badges.Parent = well
			local badgeList = Instance.new("UIListLayout")
			badgeList.Padding = UDim.new(0, 4)
			badgeList.SortOrder = Enum.SortOrder.LayoutOrder
			badgeList.Parent = badges
			local role = MachineEffects.role(definition)
			if role then
				GlassUI.chip(badges, "Role", string.upper(role.Name), GlassUI.fromRgb(role.Color), 11).LayoutOrder = 0
			end
			for order, modifierId in ipairs(definition.Modifiers or {}) do
				local modifier = MachineModifiers.get(modifierId)
				if modifier then
					GlassUI.chip(badges, modifier.Id, string.upper(modifier.DisplayName), GlassUI.fromRgb(modifier.Color), 10).LayoutOrder = order
				end
			end
		end
		return card, actions
	end

	local function confirmable(button: TextButton, label: string, action: () -> ())
		local armed = false
		button.Activated:Connect(function()
			if not armed then
				armed = true
				button.Text = "Confirm"
				GlassUI.setStyle(button, "Danger")
				task.delay(3, function()
					if armed and button.Parent then
						armed = false
						button.Text = label
						GlassUI.setStyle(button, "Secondary")
					end
				end)
				return
			end
			armed = false
			action()
		end)
	end

	local function boosterCard(booster: any, count: number, order: number)
		local color = GlassUI.fromRgb(booster.Color)
		local effect = booster.Effect
		local multiplier = effect.Multiplier or 1
		local kind = if effect.Kind == "SaleValue" then "Sale value" elseif effect.Kind == "Luck" then "Roll luck" else tostring(effect.Kind)
		local card, well, actions = makeCard("Booster_" .. booster.Id, order, color, booster.DisplayName, "Booster", `{kind} ×{multiplier} · {effect.DurationSeconds or 0}s`, string.format("Owned ×%d", count))
		local badge = Instance.new("TextLabel")
		badge.Name = "BoosterBadge"
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.fromScale(0.5, 0.5)
		badge.Size = UDim2.fromScale(0.6, 0.6)
		badge.BackgroundColor3 = color
		badge.BackgroundTransparency = 0.2
		badge.Text = `×{multiplier}`
		badge.TextColor3 = C.AccentText
		badge.FontFace = Theme.Fonts.Heavy
		badge.TextScaled = true
		GlassUI.round(badge)
		GlassUI.stroke(badge, C.Stroke, 0.6, 2)
		GlassUI.padding(badge, 10)
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 1
		ratio.Parent = badge
		badge.Parent = well
		local use = addAction(actions, "UseButton", "Use", "Primary", 1, 1)
		use.Activated:Connect(function()
			local response = invoke(useBooster, booster.Id)
			if response and response.Success then
				setStatus(`{booster.DisplayName} active.`, true)
				refresh()
			elseif response then
				setStatus(response.Reason or "Booster could not be used.", false)
			end
		end)
		return card
	end

	local function placementRow(machineId: string, order: number, detail: string, actionText: string, enabled: boolean, action: () -> ())
		local _, actions = machineCard(machineId, order, true, detail)
		local button = addAction(actions, "ActionButton", actionText, "Primary", 1, 1)
		GlassUI.setEnabled(button, enabled)
		button.Activated:Connect(function()
			if enabled then
				action()
			end
		end)
	end

	render = function()
		clearRows(list)
		empty.Visible = false
		if not state then
			title.Text = "Inventory"
			subtitle.Text = "Factory data is not ready yet."
			setStatus("Waiting for the factory to load...", nil)
			return
		end
		local inventoryMode = mode == "Inventory"
		tabBar.Visible = inventoryMode
		backButton.Visible = not inventoryMode
		for category, button in pairs(categoryTabs) do
			GlassUI.setStyle(button, if category == activeCategory then "Selected" else "Ghost")
		end
		setGrid()

		local ids, totals, placed, available = getCounts()
		local ownedCount = 0
		for _, count in pairs(totals) do
			ownedCount += count
		end
		inventoryButton:SetAttribute("OwnedCount", ownedCount)
		countBadge.Text = if ownedCount > 99 then "99+" else tostring(ownedCount)
		countBadge.Visible = ownedCount > 0
		if lastOwned and ownedCount > lastOwned and buttonScale then
			buttonScale.Scale = 1.1
			TweenService:Create(buttonScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		lastOwned = ownedCount
		-- Hidden panels only track the badge; cards and previews rebuild when opened.
		if not panel.Visible then
			return
		end
		local visibleRowCount = 0

		if mode == "Placement" and targetSlot then
			local placementSlot = targetSlot :: number
			local requiredCategory = FactoryLayout.expectedCategoryForSlot(placementSlot)
			local areaLabel = FactoryLayout.getAreaLabel(placementSlot)
			title.Text = if requiredCategory == "Seller" then "Select Seller" else string.format("Place in Area %d", placementSlot)
			subtitle.Text = if requiredCategory == "Seller" then "Choose a seller you own for the end of the conveyor."
				elseif requiredCategory == "Producer" then "Choose a dropper you own." else "Choose an upgrader you own."
			local currentId = state.Layout[placementSlot]
			local currentDefinition = if currentId and currentId ~= "" then MachineDefinitions.get(currentId) else nil
			local currentName = if currentId and currentId ~= "" then (currentDefinition and currentDefinition.DisplayName or currentId) else "Empty"
			setStatus(string.format("%s · %s · Capacity %d", areaLabel, currentName, state.Capacity), nil)

			local layout = normalizeLayout()
			local rowIndex = 0
			for _, machineId in ipairs(ids) do
				local count = available[machineId] or 0
				local definition = MachineDefinitions.get(machineId)
				if count > 0 and definition and definition.Category == requiredCategory then
					rowIndex += 1
					local candidate, placementError = PlacementRules.createPlacementLayout(layout, machineId, placementSlot, state.Capacity)
					local canPlace = candidate ~= nil
					local detail = if canPlace then string.format("Available ×%d", count) else (placementError or "Cannot place here")
					placementRow(machineId, rowIndex, detail, if currentId and currentId ~= "" then "Replace" else "Place", canPlace, function()
						local response = invoke(placeMachine, machineId, placementSlot, currentId ~= nil and currentId ~= "")
						if response and response.Success then
							setStatus(string.format("Placed %s in area %d.", definition.DisplayName, placementSlot), true)
						elseif response then
							setStatus(response.Reason or "Machine could not be placed.", false)
						end
						refresh()
					end)
					visibleRowCount += 1
				end
			end

			for sourceSlot = 1, state.SlotCount do
				local sourceId = layout[sourceSlot]
				local sourceDefinition = sourceId and MachineDefinitions.get(sourceId)
				if sourceId and sourceDefinition and sourceDefinition.Category == requiredCategory and sourceSlot ~= placementSlot then
					local candidate, moveError = PlacementRules.createMoveLayout(layout, sourceSlot, placementSlot, state.Capacity)
					rowIndex += 1
					local canMove = candidate ~= nil
					local detail = if canMove then string.format("Currently in area %d", sourceSlot) else (moveError or "Cannot move here")
					placementRow(sourceId, rowIndex, detail, string.format("Move from %d", sourceSlot), canMove, function()
						local response = invoke(moveMachine, sourceSlot, placementSlot)
						if response and response.Success then
							setStatus(string.format("Moved %s to area %d.", sourceDefinition.DisplayName, placementSlot), true)
						elseif response then
							setStatus(response.Reason or "Machine could not be moved.", false)
						end
						refresh()
					end)
					visibleRowCount += 1
				end
			end

			local removable = PlacementRules.createRemoveLayout(layout, placementSlot, state.Capacity)
			if removable and currentId and currentId ~= "" and currentDefinition and currentDefinition.Category == "Processor" then
				rowIndex += 1
				placementRow(currentId, rowIndex, "Installed in this area", "Return to inventory", true, function()
					local response = invoke(removeMachine, placementSlot)
					if response and response.Success then
						setStatus(string.format("Returned %s to your available machines.", currentName), true)
						refresh()
					elseif response then
						setStatus(response.Reason or "Machine could not be returned.", false)
					end
				end)
				visibleRowCount += 1
			end
		elseif activeCategory == "Booster" then
			title.Text = "Inventory"
			subtitle.Text = "Collected boosters stay here until you use them."
			setStatus("Run over world drops to collect boosters.", nil)
			local boosterCounts = state.BoosterInventory or {}
			for index, booster in ipairs(BoosterConfig.Definitions) do
				local count = boosterCounts[booster.Id] or 0
				if count > 0 then
					boosterCard(booster, count, index)
					visibleRowCount += 1
				end
			end
		else
			title.Text = "Inventory"
			subtitle.Text = "Click a conveyor slot to place or swap machines."
			setStatus(string.format("%d machine%s owned across %d type%s.", ownedCount, if ownedCount == 1 then "" else "s", #ids, if #ids == 1 then "" else "s"), nil)
			local rowIndex = 0
			for _, machineId in ipairs(ids) do
				local definition = MachineDefinitions.get(machineId)
				if definition and definition.Category == activeCategory then
					rowIndex += 1
					local count = available[machineId] or 0
					local detail = string.format("Owned %d  ·  Placed %d  ·  Free %d", totals[machineId] or 0, placed[machineId] or 0, count)
					local _, actions = machineCard(machineId, rowIndex, false, detail)
					-- Placement happens by clicking a conveyor slot; cards only offer recycling.
					if count > 0 and definition.Rollable == true then
						local recycle = addAction(actions, "ActionButton", "Recycle", "Secondary", 1, 1)
						confirmable(recycle, "Recycle", function()
							local response = invoke(sellMachine, machineId, 1)
							if response and response.Success then
								setStatus(string.format("Recycled one %s.", definition.DisplayName), true)
								refresh()
							elseif response then
								setStatus(response.Reason or "Machine could not be recycled.", false)
							end
						end)
					end
					visibleRowCount += 1
				end
			end
		end

		if visibleRowCount == 0 then
			empty.Text = if mode == "Placement" then "No owned machines of this type are available yet."
				elseif activeCategory == "Booster" then "No boosters collected yet. Watch for drops around your island."
				else "Nothing here yet. Hit Roll to get a free machine."
			empty.Visible = true
		end
	end

	openPanel = function(nextMode: string, slotIndex: number?, category: string?)
		if nextMode == "Placement" and not FactoryLayout.isEditableMachineSlot(slotIndex) then
			setStatus("Select a valid factory area first.", false)
			return
		end
		mode = nextMode
		activeCategory = if category and categoryTabs[category] then category else "Producer"
		targetSlot = if nextMode == "Placement" then slotIndex else nil
		if not panel.Visible then
			for _, listener in ipairs(openListeners) do
				task.spawn(listener)
			end
			panel.Visible = true
			panel.Position = panelTarget + UDim2.fromOffset(18, 0)
			TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = panelTarget }):Play()
		end
		announceTarget()
		refresh()
	end
	closePanel = function()
		panel.Visible = false
		announceTarget()
	end

	inventoryButton.Activated:Connect(function()
		if panel.Visible then
			closePanel()
		else
			openPanel("Inventory", nil)
		end
	end)
	for category, button in pairs(categoryTabs) do
		button.Activated:Connect(function()
			activeCategory = category
			mode = "Inventory"
			announceTarget()
			render()
		end)
	end
	backButton.Activated:Connect(function()
		mode = "Inventory"
		targetSlot = nil
		announceTarget()
		render()
	end)
	closeButton.Activated:Connect(function()
		closePanel()
	end)

	local function layout()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		metrics = HudLayout.measure(size.X, size.Y)
		local s = metrics.Scale
		touch = math.max(40, Theme.MinTouch / s)
		cardHeight = if metrics.CardStyle == "Row" then touch + 118 else 250 + touch

		local button = metrics.Inventory
		inventoryButton.Position = UDim2.fromOffset(button.X, button.Y)
		inventoryButton.Size = UDim2.fromOffset(button.W, button.H)
		local iconSize = math.round(button.H * 0.46)
		boxIcon.Size = UDim2.fromOffset(iconSize, iconSize)
		boxIcon.Position = if metrics.InventoryIconOnly then UDim2.new(0.5, -iconSize / 2, 0.5, 0) else UDim2.new(0, 16 * s, 0.5, 0)
		buttonCaption.Visible = not metrics.InventoryIconOnly
		buttonCaption.Position = UDim2.new(0, 22 * s + iconSize, 0, 0)
		buttonCaption.Size = UDim2.new(1, -(30 * s + iconSize), 1, 0)
		buttonCaption.TextSize = math.round(16 * s)

		local rect = metrics.Panel
		panelScale.Scale = s
		panelTarget = UDim2.fromOffset(rect.X, rect.Y)
		panel.Position = panelTarget
		local width = rect.W / s
		local height = rect.H / s
		panel.Size = UDim2.fromOffset(width, height)

		local pad = 16
		local closeSize = math.max(40, Theme.MinTouch / s)
		closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
		closeButton.Position = UDim2.new(1, -pad - closeSize + 6, 0, 8)
		local showSubtitle = not metrics.Landscape
		title.Position = UDim2.fromOffset(pad + 2, 12)
		title.Size = UDim2.new(1, -pad * 2 - closeSize, 0, 30)
		subtitle.Visible = showSubtitle
		subtitle.Position = UDim2.fromOffset(pad + 2, 42)
		subtitle.Size = UDim2.new(1, -pad * 2 - closeSize, 0, 18)
		local barTop = if showSubtitle then 70 else 50
		local barHeight = touch + 8
		tabBar.Position = UDim2.fromOffset(pad, barTop)
		tabBar.Size = UDim2.new(1, -pad * 2, 0, barHeight)
		backButton.Position = UDim2.fromOffset(pad, barTop)
		backButton.Size = UDim2.new(1, -pad * 2, 0, barHeight)
		local listTop = barTop + barHeight + 12
		list.Position = UDim2.fromOffset(pad - 2, listTop)
		list.Size = UDim2.new(1, -pad * 2 + 6, 1, -listTop - 34)
		empty.Position = UDim2.fromOffset(pad, listTop + 24)
		empty.Size = UDim2.new(1, -pad * 2, 0, 48)
		status.Position = UDim2.new(0, pad + 2, 1, -28)
		status.Size = UDim2.new(1, -pad * 2, 0, 20)
		if state and panel.Visible then
			render()
		end
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	presentationEvent.OnClientEvent:Connect(function(eventName: string)
		if eventName == "InventoryChanged" then
			refresh()
		end
	end)

	refresh()
end

return InventoryController
