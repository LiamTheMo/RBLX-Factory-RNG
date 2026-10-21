--!strict
-- Code-only glass UI kit: translucent panels, pill buttons and simple drawn icons.
-- No image assets, so every control renders identically in Studio and live servers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudTheme"))

local GlassUI = {}
GlassUI.Theme = Theme
local C = Theme.Colors
local T = Theme.Transparency

local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type ButtonStyle = "Primary" | "Secondary" | "Ghost" | "Danger" | "Selected"

-- Running hover tweens, cancelled by setStyle so a restyle mid-hover always wins.
local hoverTweens: { [GuiButton]: Tween } = setmetatable({}, { __mode = "k" }) :: any

local STYLES: { [string]: { Color: Color3, Transparency: number, Text: Color3, Stroke: number } } = {
	Primary = { Color = C.Accent, Transparency = 0.12, Text = C.AccentText, Stroke = 0.6 },
	Secondary = { Color = C.CardTop, Transparency = 0.25, Text = C.Text, Stroke = T.Stroke },
	Ghost = { Color = C.Stroke, Transparency = T.Ghost, Text = C.Text, Stroke = 0.9 },
	Danger = { Color = C.Bad, Transparency = 0.15, Text = C.AccentText, Stroke = 0.6 },
	Selected = { Color = C.Accent, Transparency = 0.12, Text = C.AccentText, Stroke = 0.6 },
}

function GlassUI.corner(instance: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.Radius.Button)
	corner.Parent = instance
	return corner
end

function GlassUI.setRadius(instance: Instance, radius: number)
	local corner = instance:FindFirstChildOfClass("UICorner") or GlassUI.corner(instance, radius)
	corner.CornerRadius = UDim.new(0, radius)
end

function GlassUI.round(instance: Instance): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = instance
	return corner
end

function GlassUI.stroke(instance: Instance, color: Color3?, transparency: number?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color or C.Stroke
	stroke.Transparency = transparency or T.Stroke
	stroke.Thickness = thickness or 1
	stroke.Parent = instance
	return stroke
end

function GlassUI.padding(instance: Instance, x: number, y: number?)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, x)
	padding.PaddingRight = UDim.new(0, x)
	padding.PaddingTop = UDim.new(0, y or x)
	padding.PaddingBottom = UDim.new(0, y or x)
	padding.Parent = instance
end

-- Vertical sheen: lighter top edge fading into the base glass tone.
function GlassUI.sheen(instance: GuiObject, top: Color3, base: Color3): UIGradient
	instance.BackgroundColor3 = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(0.55, base),
		ColorSequenceKeypoint.new(1, base),
	})
	gradient.Parent = instance
	return gradient
end

function GlassUI.glass(parent: Instance, name: string, radius: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = T.Glass
	GlassUI.sheen(frame, C.GlassTop, C.Glass)
	GlassUI.corner(frame, radius or Theme.Radius.Panel)
	GlassUI.stroke(frame)
	frame.Parent = parent
	return frame
end

function GlassUI.card(parent: Instance, name: string, tint: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = T.Card
	GlassUI.sheen(frame, if tint then C.CardTop:Lerp(tint, 0.38) else C.CardTop, C.Card)
	GlassUI.corner(frame, Theme.Radius.Card)
	GlassUI.stroke(frame, tint or C.Stroke, if tint then 0.55 else T.Stroke)
	frame.Parent = parent
	return frame
end

function GlassUI.label(parent: Instance, name: string, text: string, size: number?, font: Font?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = C.Text
	label.FontFace = font or Theme.Fonts.Medium
	label.TextSize = size or 14
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

-- Resting transparency: the style's, unless the button sets a GlassBaseTransparency override.
local function restingTransparency(button: GuiButton): number
	local spec = STYLES[(button:GetAttribute("GlassStyle") or "Secondary") :: string]
	local override = button:GetAttribute("GlassBaseTransparency")
	local base = if type(override) == "number" then override else spec.Transparency
	if button:GetAttribute("GlassDisabled") == true then
		return math.max(base, T.Disabled)
	end
	return base
end

function GlassUI.setStyle(button: GuiButton, style: ButtonStyle)
	local spec = STYLES[style]
	local hover = hoverTweens[button]
	if hover then
		hover:Cancel()
		hoverTweens[button] = nil
	end
	button:SetAttribute("GlassStyle", style)
	button.BackgroundColor3 = spec.Color
	local enabled = button:GetAttribute("GlassDisabled") ~= true
	button.BackgroundTransparency = restingTransparency(button)
	if button:IsA("TextButton") then
		button.TextColor3 = spec.Text
		button.TextTransparency = if enabled then 0 else 0.45
	end
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = spec.Stroke
	end
end

function GlassUI.setEnabled(button: GuiButton, enabled: boolean)
	button:SetAttribute("GlassDisabled", not enabled)
	button.Active = enabled
	GlassUI.setStyle(button, (button:GetAttribute("GlassStyle") or "Secondary") :: ButtonStyle)
end

-- Hover lifts the glass slightly; presses compress the control for tactile feedback.
local function attachFeedback(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local function fadeTo(transparency: number)
		local previous = hoverTweens[button]
		if previous then
			previous:Cancel()
		end
		local tween = TweenService:Create(button, FAST, { BackgroundTransparency = transparency })
		hoverTweens[button] = tween
		tween.Completed:Connect(function()
			if hoverTweens[button] == tween then
				hoverTweens[button] = nil
			end
		end)
		tween:Play()
	end
	button.MouseEnter:Connect(function()
		if button:GetAttribute("GlassDisabled") ~= true then
			fadeTo(math.max(0, restingTransparency(button) - 0.12))
		end
	end)
	button.MouseLeave:Connect(function()
		fadeTo(restingTransparency(button))
		TweenService:Create(scale, FAST, { Scale = 1 }):Play()
	end)
	button.InputBegan:Connect(function(input: InputObject)
		if button:GetAttribute("GlassDisabled") ~= true and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			TweenService:Create(scale, FAST, { Scale = 0.96 }):Play()
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(scale, FAST, { Scale = 1 }):Play()
		end
	end)
end

function GlassUI.button(parent: Instance, name: string, text: string, style: ButtonStyle?, size: number?): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.FontFace = Theme.Fonts.Bold
	button.TextSize = size or 14
	button.TextWrapped = true
	GlassUI.corner(button, Theme.Radius.Button)
	GlassUI.stroke(button)
	GlassUI.setStyle(button, style or "Secondary")
	attachFeedback(button)
	button.Parent = parent
	return button
end

local function dot(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	GlassUI.round(frame)
	frame.Parent = parent
	return frame
end

-- Simple vector icons drawn from frames. `kind` is Coin, Dice, Box, Sliders or Close.
function GlassUI.icon(parent: Instance, kind: string, color: Color3?): Frame
	local holder = Instance.new("Frame")
	holder.Name = kind .. "Icon"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(28, 28)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = holder
	local tint = color or C.Text
	if kind == "Coin" then
		local outer = dot(holder, "Rim", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1), C.CoinRim)
		GlassUI.stroke(outer, C.Coin, 0.4, 1)
		dot(holder, "Face", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.74, 0.74), C.Coin)
		dot(holder, "Shine", UDim2.fromScale(0.38, 0.36), UDim2.fromScale(0.2, 0.2), Color3.fromRGB(255, 243, 200))
	elseif kind == "Dice" then
		local face = Instance.new("Frame")
		face.Name = "Face"
		face.AnchorPoint = Vector2.new(0.5, 0.5)
		face.Position = UDim2.fromScale(0.5, 0.5)
		face.Size = UDim2.fromScale(0.86, 0.86)
		face.Rotation = -8
		face.BackgroundColor3 = tint
		face.BorderSizePixel = 0
		GlassUI.corner(face, 6)
		face.Parent = holder
		for index, spot in ipairs({ { 0.28, 0.28 }, { 0.72, 0.28 }, { 0.5, 0.5 }, { 0.28, 0.72 }, { 0.72, 0.72 } }) do
			dot(face, "Pip" .. index, UDim2.fromScale(spot[1], spot[2]), UDim2.fromScale(0.18, 0.18), C.Glass)
		end
	elseif kind == "Box" then
		local body = Instance.new("Frame")
		body.Name = "Body"
		body.Position = UDim2.fromScale(0.1, 0.36)
		body.Size = UDim2.fromScale(0.8, 0.56)
		body.BackgroundColor3 = tint
		body.BackgroundTransparency = 0.15
		body.BorderSizePixel = 0
		GlassUI.corner(body, 4)
		body.Parent = holder
		local lid = Instance.new("Frame")
		lid.Name = "Lid"
		lid.Position = UDim2.fromScale(0.04, 0.14)
		lid.Size = UDim2.fromScale(0.92, 0.2)
		lid.BackgroundColor3 = tint
		lid.BorderSizePixel = 0
		GlassUI.corner(lid, 3)
		lid.Parent = holder
		local latch = Instance.new("Frame")
		latch.Name = "Latch"
		latch.AnchorPoint = Vector2.new(0.5, 0)
		latch.Position = UDim2.fromScale(0.5, 0.46)
		latch.Size = UDim2.fromScale(0.22, 0.12)
		latch.BackgroundColor3 = C.Glass
		latch.BorderSizePixel = 0
		GlassUI.corner(latch, 2)
		latch.Parent = holder
	elseif kind == "Sliders" then
		for index, knob in ipairs({ 0.3, 0.68, 0.42 }) do
			local y = 0.22 + (index - 1) * 0.28
			local track = Instance.new("Frame")
			track.Name = "Track" .. index
			track.AnchorPoint = Vector2.new(0, 0.5)
			track.Position = UDim2.fromScale(0.08, y)
			track.Size = UDim2.fromScale(0.84, 0.08)
			track.BackgroundColor3 = tint
			track.BackgroundTransparency = 0.35
			track.BorderSizePixel = 0
			GlassUI.round(track)
			track.Parent = holder
			dot(holder, "Knob" .. index, UDim2.fromScale(knob, y), UDim2.fromScale(0.24, 0.24), tint)
		end
	elseif kind == "Close" then
		for index, rotation in ipairs({ 45, -45 }) do
			local bar = Instance.new("Frame")
			bar.Name = "Bar" .. index
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.fromScale(0.9, 0.12)
			bar.Rotation = rotation
			bar.BackgroundColor3 = tint
			bar.BorderSizePixel = 0
			GlassUI.round(bar)
			bar.Parent = holder
		end
	end
	holder.Parent = parent
	return holder
end

-- Compact rounded tag, e.g. a rarity or booster chip. Width follows the text.
function GlassUI.chip(parent: Instance, name: string, text: string, color: Color3, size: number?): Frame
	local chip = Instance.new("Frame")
	chip.Name = name
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, 22)
	chip.BackgroundColor3 = color
	chip.BackgroundTransparency = 0.78
	chip.BorderSizePixel = 0
	GlassUI.round(chip)
	GlassUI.stroke(chip, color, 0.5)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = chip
	local label = GlassUI.label(chip, "Text", text, size or 12, Theme.Fonts.Bold)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.TextWrapped = false
	label.TextColor3 = color
	chip.Parent = parent
	return chip
end

function GlassUI.screen(parent: Instance, name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = parent
	return gui
end

-- Rarity and booster colors stay in shared config; this only converts them.
function GlassUI.fromRgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

return GlassUI
