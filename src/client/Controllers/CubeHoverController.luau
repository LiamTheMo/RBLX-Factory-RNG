--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberFormatter = require(Shared.NumberFormatter)
local Visuals = require(Shared.MachineVisualConfig)
local GlassUI = require(script.Parent.GlassUI)
local Theme = GlassUI.Theme

local CubeTypeDefinitions = require(Shared.CubeTypeDefinitions)

local Controller = {}
local started = false
local billboard: BillboardGui
local typeDot: Frame
local typeLabel: TextLabel
local chainChip: Frame
local valueLabel: TextLabel
local details: TextLabel

function Controller.focusItem(item: Instance?): boolean
	if not started or not billboard or not valueLabel then return false end
	local camera = workspace.CurrentCamera
	if not item or not item:IsA("BasePart") or not item.Parent or item:GetAttribute("FactoryItem") ~= true
		or not camera or (camera.CFrame.Position - item.Position).Magnitude > Visuals.Feedback.HoverDistance then
		billboard.Enabled = false
		billboard.Adornee = nil
		return false
	end
	local function number(name: string, default: number): number
		local value = item:GetAttribute(name)
		return if type(value) == "number" then value else default
	end
	billboard.Adornee = item
	billboard.StudsOffsetWorldSpace = Vector3.new(0, item.Size.Y / 2 + 1.2, 0)
	billboard.Enabled = true
	local typeId = item:GetAttribute("ItemType")
	local cubeType = CubeTypeDefinitions.get(if type(typeId) == "string" then typeId else "Standard")
	typeLabel.Text = (if cubeType then cubeType.DisplayName else tostring(typeId or "Standard")) .. " cube"
	typeDot.BackgroundColor3 = if cubeType then GlassUI.fromRgb(cubeType.Color) else Theme.Colors.Text
	local chainText = (chainChip :: any).Text :: TextLabel
	chainText.Text = "chain ×" .. NumberFormatter.format(number("ItemChainMultiplier", 1))
	valueLabel.Text = NumberFormatter.format(number("ItemSaleValue", number("ItemValue", 0))) .. " Coins"
	local modifiers = item:GetAttribute("ItemModifiers")
	details.Text = string.format("Upgrades: %s\nSale ×%s · +%s · %s",
		if type(modifiers) == "string" and modifiers ~= "" then modifiers else "none yet",
		NumberFormatter.format(number("ItemSaleMultiplier", 1)),
		NumberFormatter.format(number("ItemAdditiveBonus", 0)),
		item:GetAttribute("ItemSaleLayers") or "No sale bonuses")
	return true
end

-- Booster floor drops keep their server-made label hidden; show it only while hovered/tapped.
local focusedDrop: BillboardGui? = nil
function Controller.focusDrop(target: Instance?): boolean
	local label: BillboardGui? = nil
	if target and target:IsA("BasePart") and target:GetAttribute("BoosterId") ~= nil and target:GetAttribute("Landed") == true then
		local candidate = target:FindFirstChild("BoosterLabel")
		if candidate and candidate:IsA("BillboardGui") then
			label = candidate
		end
	end
	if focusedDrop and focusedDrop ~= label then
		focusedDrop.Enabled = false
	end
	focusedDrop = label
	if label then
		label.Enabled = true
	end
	return label ~= nil
end

function Controller.start()
	if started then return end
	started = true
	local player = Players.LocalPlayer
	billboard = Instance.new("BillboardGui")
	billboard.Name = "CubeValueHover"
	billboard.Size = UDim2.fromOffset(270, 112)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = Visuals.Feedback.HoverDistance
	billboard.Enabled = false
	billboard.Parent = player:WaitForChild("PlayerGui")
	local frame = GlassUI.glass(billboard, "Frame", Theme.Radius.Card)
	frame.Size = UDim2.fromScale(1, 1)
	typeDot = Instance.new("Frame")
	typeDot.Name = "TypeDot"
	typeDot.Position = UDim2.fromOffset(12, 13)
	typeDot.Size = UDim2.fromOffset(12, 12)
	typeDot.BorderSizePixel = 0
	GlassUI.round(typeDot)
	GlassUI.stroke(typeDot, Theme.Colors.Stroke, 0.5)
	typeDot.Parent = frame
	typeLabel = GlassUI.label(frame, "CubeType", "", 13, Theme.Fonts.Bold)
	typeLabel.Position = UDim2.fromOffset(30, 8)
	typeLabel.Size = UDim2.new(1, -130, 0, 22)
	typeLabel.TextWrapped = false
	typeLabel.TextTruncate = Enum.TextTruncate.AtEnd
	chainChip = GlassUI.chip(frame, "Chain", "", Theme.Colors.Accent, 11)
	chainChip.AnchorPoint = Vector2.new(1, 0)
	chainChip.Position = UDim2.new(1, -10, 0, 8)
	local coin = GlassUI.icon(frame, "Coin")
	coin.Position = UDim2.fromOffset(12, 38)
	coin.Size = UDim2.fromOffset(22, 22)
	valueLabel = GlassUI.label(frame, "Value", "", 22, Theme.Fonts.Heavy)
	valueLabel.Position = UDim2.fromOffset(40, 34)
	valueLabel.Size = UDim2.new(1, -52, 0, 30)
	valueLabel.TextColor3 = Theme.Colors.Coin
	valueLabel.TextWrapped = false
	details = GlassUI.label(frame, "Modifiers", "", 11, Theme.Fonts.Medium)
	details.Position = UDim2.fromOffset(12, 68)
	details.Size = UDim2.new(1, -24, 1, -74)
	details.TextColor3 = Theme.Colors.Muted
	details.TextYAlignment = Enum.TextYAlignment.Top
	local mouse = player:GetMouse()
	local touchItem: Instance? = nil
	local touchUntil = 0
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processed: boolean)
		if processed then return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		local ray = camera:ViewportPointToRay(position.X, position.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
		local hit = workspace:Raycast(ray.Origin, ray.Direction * Visuals.Feedback.HoverDistance, params)
		touchItem = if hit then hit.Instance else nil
		touchUntil = os.clock() + 2.5
	end)
	local elapsed = 0
	RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed < 0.1 then return end
		elapsed = 0
		local target = if os.clock() < touchUntil then touchItem else mouse.Target
		Controller.focusItem(target)
		Controller.focusDrop(target)
	end)
end

return Controller
