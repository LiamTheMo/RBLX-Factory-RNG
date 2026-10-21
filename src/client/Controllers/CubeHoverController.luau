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

local Controller = {}
local started = false
local billboard: BillboardGui
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
	valueLabel.Text = "Sale " .. NumberFormatter.format(number("ItemSaleValue", number("ItemValue", 0))) .. " Coins"
	local modifiers = item:GetAttribute("ItemModifiers")
	details.Text = string.format("%s · chain ×%s · sale ×%s\n%s\n+%s bonus · %s",
		item:GetAttribute("ItemType") or "Standard",
		NumberFormatter.format(number("ItemChainMultiplier", 1)),
		NumberFormatter.format(number("ItemSaleMultiplier", 1)),
		if type(modifiers) == "string" and modifiers ~= "" then modifiers else "No upgrades yet",
		NumberFormatter.format(number("ItemAdditiveBonus", 0)),
		item:GetAttribute("ItemSaleLayers") or "No sale bonuses")
	return true
end

function Controller.start()
	if started then return end
	started = true
	local player = Players.LocalPlayer
	billboard = Instance.new("BillboardGui")
	billboard.Name = "CubeValueHover"
	billboard.Size = UDim2.fromOffset(260, 104)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = Visuals.Feedback.HoverDistance
	billboard.Enabled = false
	billboard.Parent = player:WaitForChild("PlayerGui")
	local frame = GlassUI.glass(billboard, "Frame", Theme.Radius.Card)
	frame.Size = UDim2.fromScale(1, 1)
	valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Position = UDim2.fromOffset(12, 8)
	valueLabel.Size = UDim2.new(1, -24, 0, 20)
	valueLabel.BackgroundTransparency = 1
	valueLabel.TextColor3 = Theme.Colors.Coin
	valueLabel.Font = Theme.Fonts.Heavy
	valueLabel.TextSize = 15
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.Parent = frame
	details = Instance.new("TextLabel")
	details.Name = "Modifiers"
	details.Position = UDim2.fromOffset(12, 32)
	details.Size = UDim2.new(1, -24, 1, -40)
	details.BackgroundTransparency = 1
	details.TextColor3 = Theme.Colors.Muted
	details.Font = Theme.Fonts.Medium
	details.TextSize = 11
	details.TextXAlignment = Enum.TextXAlignment.Left
	details.TextWrapped = true
	details.TextYAlignment = Enum.TextYAlignment.Top
	details.Parent = frame
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
		Controller.focusItem(if os.clock() < touchUntil then touchItem else mouse.Target)
	end)
end

return Controller
