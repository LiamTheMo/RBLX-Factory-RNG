--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MachineVisualConfig = require(Shared:WaitForChild("MachineVisualConfig"))
local Theme = require(Shared:WaitForChild("HudTheme"))
local InventoryController = require(script.Parent.InventoryController)

-- Clicking a conveyor slot (or the machine on it) opens placement for that slot. Each slot
-- of the local player's conveyor gets a client-only translucent selection box: faint on
-- empty slots, bright while hovered or while its placement panel is open.
local BuildController = {}
local started = false

type SlotBox = { Box: Part, Outline: SelectionBox, Pulse: Tween? }

local BOX = table.freeze({
	EmptyTransparency = 0.86,
	EmptyPulseTransparency = 0.78,
	ActiveTransparency = 0.7,
	EmptyOutline = 0.45,
	ActiveOutline = 0,
	LineThickness = 0.05,
})

function BuildController.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local plotsFolder = workspace:WaitForChild("TinyFactoryPlots")
	local highlightFolder = Instance.new("Folder")
	highlightFolder.Name = "SlotSelectionBoxes"
	highlightFolder.Parent = workspace
	local connectedDetectors: { [ClickDetector]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local boxes: { [number]: SlotBox } = {}
	local hoveredSlot: number? = nil
	local selectedSlot: number? = nil

	local function slotIsEmpty(slotIndex: number): boolean
		local layout = player:GetAttribute("FactoryLayout")
		if type(layout) ~= "string" then
			return false
		end
		local entries = string.split(layout, ",")
		return entries[slotIndex] == nil or entries[slotIndex] == ""
	end

	local function refreshSlot(slotIndex: number)
		local entry = boxes[slotIndex]
		if not entry then
			return
		end
		if entry.Pulse then
			entry.Pulse:Cancel()
			entry.Pulse = nil
		end
		local active = slotIndex == hoveredSlot or slotIndex == selectedSlot
		local empty = slotIsEmpty(slotIndex)
		entry.Outline.Visible = active or empty
		entry.Box.Color = if active then Theme.Colors.Accent else Theme.Colors.Stroke
		entry.Outline.Color3 = Theme.Colors.Accent
		entry.Outline.Transparency = if active then BOX.ActiveOutline else BOX.EmptyOutline
		if active then
			entry.Box.Transparency = BOX.ActiveTransparency
		elseif empty then
			entry.Box.Transparency = BOX.EmptyTransparency
			local pulse = TweenService:Create(entry.Box, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = BOX.EmptyPulseTransparency })
			entry.Pulse = pulse
			pulse:Play()
		else
			entry.Box.Transparency = 1
		end
	end

	local function refreshAll()
		for slotIndex in pairs(boxes) do
			refreshSlot(slotIndex)
		end
	end

	local function setHovered(slotIndex: number?)
		if hoveredSlot == slotIndex then
			return
		end
		local previous = hoveredSlot
		hoveredSlot = slotIndex
		if previous then
			refreshSlot(previous)
		end
		if slotIndex then
			refreshSlot(slotIndex)
		end
	end

	local function isOwned(instance: Instance): boolean
		local ancestor = instance.Parent
		while ancestor and ancestor ~= plotsFolder do
			if ancestor:GetAttribute("OwnerUserId") == player.UserId then
				return true
			end
			ancestor = ancestor.Parent
		end
		return false
	end

	local function addBox(selector: BasePart, slotIndex: number)
		local existing = boxes[slotIndex]
		if existing then
			existing.Box:Destroy()
		end
		local height = MachineVisualConfig.Conveyor.Selector.BoxHeight
		local box = Instance.new("Part")
		box.Name = "SlotBox_" .. slotIndex
		box.Anchored = true
		box.CanCollide = false
		box.CanQuery = false
		box.CanTouch = false
		box.CastShadow = false
		box.Material = Enum.Material.SmoothPlastic
		box.Size = Vector3.new(selector.Size.X, height, selector.Size.Z)
		box.CFrame = selector.CFrame * CFrame.new(0, (height - selector.Size.Y) / 2, 0)
		box.Transparency = 1
		box.Parent = highlightFolder
		local outline = Instance.new("SelectionBox")
		outline.Adornee = box
		outline.LineThickness = BOX.LineThickness
		outline.SurfaceTransparency = 1
		outline.Visible = false
		outline.Parent = box
		boxes[slotIndex] = { Box = box, Outline = outline }
		selector:GetPropertyChangedSignal("CFrame"):Connect(function()
			box.CFrame = selector.CFrame * CFrame.new(0, (height - selector.Size.Y) / 2, 0)
		end)
		selector.AncestryChanged:Connect(function()
			if not selector:IsDescendantOf(workspace) and boxes[slotIndex] and boxes[slotIndex].Box == box then
				box:Destroy()
				boxes[slotIndex] = nil
			end
		end)
		refreshSlot(slotIndex)
	end

	local function connectPhysicalSlot(instance: Instance)
		if not instance:IsA("ClickDetector") or instance.Name ~= "FactorySlotClick" or connectedDetectors[instance] then
			return
		end
		if not isOwned(instance) then
			return
		end
		local slotIndex = instance:GetAttribute("FactorySlotIndex")
		if type(slotIndex) ~= "number" then
			return
		end
		connectedDetectors[instance] = true
		local part = instance.Parent
		if part and part:IsA("BasePart") and part.Name == "SlotSelector_" .. slotIndex then
			addBox(part, slotIndex)
		end
		instance.MouseClick:Connect(function(clicker: Player)
			if clicker == player then
				InventoryController.openPlacement(slotIndex)
			end
		end)
		instance.MouseHoverEnter:Connect(function(hoverer: Player)
			if hoverer == player then
				setHovered(slotIndex)
			end
		end)
		instance.MouseHoverLeave:Connect(function(hoverer: Player)
			if hoverer == player and hoveredSlot == slotIndex then
				setHovered(nil)
			end
		end)
	end

	InventoryController.onPlacementTarget(function(slotIndex: number?)
		local previous = selectedSlot
		selectedSlot = slotIndex
		if previous then
			refreshSlot(previous)
		end
		if slotIndex then
			refreshSlot(slotIndex)
		end
	end)
	player:GetAttributeChangedSignal("FactoryLayout"):Connect(refreshAll)

	for _, instance in ipairs(plotsFolder:GetDescendants()) do
		connectPhysicalSlot(instance)
	end
	plotsFolder.DescendantAdded:Connect(connectPhysicalSlot)
end

return BuildController
