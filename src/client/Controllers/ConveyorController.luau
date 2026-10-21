--!strict

-- Presentation only: thin client-side cleats ride every factory belt toward the seller at
-- item speed, so the conveyor reads as moving. One throttled loop moves every cleat with
-- BulkMoveTo, and belts far from the camera stay still.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MachineVisualConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MachineVisualConfig"))

local ConveyorController = {}
local started = false

local SLAT = MachineVisualConfig.Conveyor.Slat
local STEP_SECONDS = 1 / 30

type Belt = { Part: BasePart, Cleats: { BasePart }, Speed: number }

function ConveyorController.start()
	if started then
		return
	end
	started = true

	local plotsFolder = workspace:WaitForChild("TinyFactoryPlots")
	local cleatFolder = Instance.new("Folder")
	cleatFolder.Name = "ConveyorCleats"
	cleatFolder.Parent = workspace
	local belts: { [BasePart]: Belt } = {}
	local color = Color3.fromRGB(SLAT.Color[1], SLAT.Color[2], SLAT.Color[3])

	local function removeBelt(part: BasePart)
		local belt = belts[part]
		if belt then
			for _, cleat in ipairs(belt.Cleats) do
				cleat:Destroy()
			end
			belts[part] = nil
		end
	end

	local function addBelt(instance: Instance)
		if not instance:IsA("BasePart") or instance:GetAttribute("ConveyorBelt") ~= true or belts[instance] then
			return
		end
		local part = instance :: BasePart
		local usable = part.Size.X - SLAT.Inset * 2
		local count = math.max(1, math.floor(usable / SLAT.Spacing))
		local cleats = {}
		for index = 1, count do
			local cleat = Instance.new("Part")
			cleat.Name = "Cleat_" .. index
			cleat.Anchored = true
			cleat.CanCollide = false
			cleat.CanQuery = false
			cleat.CanTouch = false
			cleat.CastShadow = false
			cleat.Material = Enum.Material.SmoothPlastic
			cleat.Color = color
			cleat.Size = Vector3.new(SLAT.Length, SLAT.Height, part.Size.Z - 0.3)
			cleat.Parent = cleatFolder
			table.insert(cleats, cleat)
		end
		local speed = part:GetAttribute("BeltSpeed")
		belts[part] = { Part = part, Cleats = cleats, Speed = if type(speed) == "number" then speed else 6 }
		part.AncestryChanged:Connect(function()
			if not part:IsDescendantOf(workspace) then
				removeBelt(part)
			end
		end)
	end

	for _, instance in ipairs(plotsFolder:GetDescendants()) do
		addBelt(instance)
	end
	plotsFolder.DescendantAdded:Connect(addBelt)

	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed < STEP_SECONDS then
			return
		end
		elapsed = 0
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		table.clear(parts)
		table.clear(frames)
		local now = os.clock()
		local focus = camera.CFrame.Position
		for _, belt in pairs(belts) do
			local part = belt.Part
			if (part.Position - focus).Magnitude <= SLAT.AnimateDistance then
				local half = part.Size.X / 2 - SLAT.Inset
				local span = half * 2
				local phase = (now * belt.Speed) % SLAT.Spacing
				local top = part.Size.Y / 2 + SLAT.Height / 2
				for index, cleat in ipairs(belt.Cleats) do
					local x = ((index - 1) * SLAT.Spacing + phase) % span - half
					table.insert(parts, cleat)
					table.insert(frames, part.CFrame * CFrame.new(x, top, 0))
				end
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return ConveyorController
