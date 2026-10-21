--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared:WaitForChild("EconomyConfig"))
local BoosterConfig = require(Shared:WaitForChild("BoosterConfig"))
local MachineDefinitions = require(Shared:WaitForChild("MachineDefinitions"))
local FloatingText = require(script.Parent.FloatingText)
local NumberFormatter = require(Shared:WaitForChild("NumberFormatter"))
local EconomyRules = require(Shared:WaitForChild("EconomyRules"))
local GlassUI = require(script.Parent.GlassUI)

local Theme = GlassUI.Theme
local C = Theme.Colors
local FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- A small event registry keeps presentation separate from gameplay authority.
-- New moments can register a handler without changing the economy or factory services.
local EffectsController = {}
local handlers: { [string]: ({ [string]: any }) -> () } = {}
local started = false
local sequence = 0
local toastSequence = 0

local rarityColors: { [string]: Color3 } = {}
for _, band in ipairs(EconomyConfig.RarityOddsBands) do
	local color = band.Color
	rarityColors[band.Name] = GlassUI.fromRgb(color)
end
local firstRarityBand = EconomyConfig.RarityOddsBands[1]
local defaultRarityColor = Color3.new(1, 1, 1)
if firstRarityBand then
	defaultRarityColor = rarityColors[firstRarityBand.Name] or defaultRarityColor
end

local function getRarityColor(rarity: string): Color3
	return rarityColors[rarity] or defaultRarityColor
end

local function getBoosterColor(boosterId: string?): Color3
	for _, booster in ipairs(BoosterConfig.Definitions) do
		if booster.Id == boosterId then
			local color = booster.Color
			return Color3.fromRGB(color[1], color[2], color[3])
		end
	end
	return getRarityColor("Legendary")
end

function EffectsController.register(eventName: string, handler: ({ [string]: any }) -> ())
	handlers[eventName] = handler
end

function EffectsController.play(eventName: string, payload: { [string]: any }?)
	local handler = handlers[eventName]
	if handler then
		handler(payload or {})
	end
end

function EffectsController.start()
	if started then
		return
	end
	started = true
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Factory"):WaitForChild("PresentationEvent") :: RemoteEvent
	local gui = GlassUI.screen(playerGui, "FactoryEffects", 20)
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None

	-- Full-screen dim plus a camera blur keep the world visible behind the glass reveal.
	local overlay = Instance.new("Frame")
	overlay.Name = "CutsceneOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = C.Overlay
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.Parent = gui

	local reveal = Instance.new("CanvasGroup")
	reveal.Name = "RevealPanel"
	reveal.AnchorPoint = Vector2.new(0.5, 0.5)
	reveal.Position = UDim2.fromScale(0.5, 0.46)
	reveal.Size = UDim2.new(0.9, 0, 0, 210)
	reveal.BackgroundTransparency = 1
	reveal.BorderSizePixel = 0
	reveal.Parent = overlay
	-- A gradient on the CanvasGroup itself would tint its text, so the glass is a child,
	-- inset so the outer stroke is not clipped by the group bounds.
	local revealBackdrop = GlassUI.glass(reveal, "Backdrop", 22)
	revealBackdrop.Position = UDim2.fromOffset(2, 2)
	revealBackdrop.Size = UDim2.new(1, -4, 1, -4)
	local revealStroke = revealBackdrop:FindFirstChildOfClass("UIStroke") :: UIStroke
	revealStroke.Thickness = 2
	revealStroke.Transparency = 0.6
	local revealLimit = Instance.new("UISizeConstraint")
	revealLimit.MaxSize = Vector2.new(620, 210)
	revealLimit.Parent = reveal
	local scale = Instance.new("UIScale")
	scale.Parent = reveal
	local pulse: Tween? = nil

	local heading = Instance.new("TextLabel")
	heading.Name = "Heading"
	heading.Position = UDim2.new(0, 20, 0, 22)
	heading.Size = UDim2.new(1, -40, 0, 40)
	heading.BackgroundTransparency = 1
	heading.TextColor3 = C.Text
	heading.Font = Theme.Fonts.Heavy
	heading.TextScaled = true
	local headingTextLimit = Instance.new("UITextSizeConstraint")
	headingTextLimit.MinTextSize = 20
	headingTextLimit.MaxTextSize = 36
	headingTextLimit.Parent = heading
	heading.Parent = reveal

	local card = Instance.new("TextLabel")
	card.Name = "RevealCard"
	card.Position = UDim2.new(0, 20, 0, 70)
	card.Size = UDim2.new(1, -40, 0, 92)
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.TextColor3 = C.Text
	card.Font = Theme.Fonts.Heavy
	card.TextScaled = true
	card.TextWrapped = true
	local cardTextLimit = Instance.new("UITextSizeConstraint")
	cardTextLimit.MinTextSize = 22
	cardTextLimit.MaxTextSize = 48
	cardTextLimit.Parent = card
	card.Parent = reveal

	local footnote = Instance.new("TextLabel")
	footnote.Name = "Footnote"
	footnote.Position = UDim2.new(0, 20, 1, -40)
	footnote.Size = UDim2.new(1, -40, 0, 20)
	footnote.BackgroundTransparency = 1
	footnote.TextColor3 = C.Muted
	footnote.Font = Theme.Fonts.Medium
	footnote.TextSize = 13
	footnote.Text = ""
	footnote.Parent = reveal

	local blur = Instance.new("BlurEffect")
	blur.Name = "RollRevealBlur"
	blur.Size = 0
	blur.Enabled = false

	local function attachBlur()
		local camera = workspace.CurrentCamera
		if camera and blur.Parent ~= camera then
			blur.Parent = camera
		end
	end

	local function showOverlay(accent: Color3)
		attachBlur()
		revealStroke.Color = accent
		if not overlay.Visible then
			overlay.Visible = true
			reveal.GroupTransparency = 1
			blur.Enabled = true
			TweenService:Create(reveal, FADE, { GroupTransparency = 0 }):Play()
			TweenService:Create(blur, FADE, { Size = Theme.RevealBlurSize }):Play()
		end
		TweenService:Create(overlay, FADE, { BackgroundTransparency = Theme.Transparency.Overlay }):Play()
	end

	local function hideOverlay(token: number)
		TweenService:Create(overlay, FADE, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(reveal, FADE, { GroupTransparency = 1 }):Play()
		TweenService:Create(blur, FADE, { Size = 0 }):Play()
		task.delay(FADE.Time, function()
			if token == sequence then
				overlay.Visible = false
				blur.Enabled = false
			end
		end)
	end

	-- Toast pill sits just below Roblox's top bar.
	local toast = Instance.new("CanvasGroup")
	toast.Name = "EventToast"
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.AutomaticSize = Enum.AutomaticSize.X
	toast.Size = UDim2.fromOffset(0, 46)
	toast.BackgroundTransparency = 1
	toast.BorderSizePixel = 0
	toast.GroupTransparency = 1
	toast.Visible = false
	toast.Parent = gui
	local toastLimit = Instance.new("UISizeConstraint")
	toastLimit.MaxSize = Vector2.new(520, 46)
	toastLimit.Parent = toast
	local toastBackdrop = GlassUI.glass(toast, "Backdrop", 999)
	toastBackdrop.Position = UDim2.fromOffset(1, 1)
	toastBackdrop.Size = UDim2.new(1, -2, 1, -2)
	local toastContent = Instance.new("Frame")
	toastContent.Name = "Content"
	toastContent.AutomaticSize = Enum.AutomaticSize.X
	toastContent.Size = UDim2.fromOffset(0, 46)
	toastContent.BackgroundTransparency = 1
	toastContent.Parent = toast
	local toastPadding = Instance.new("UIPadding")
	toastPadding.PaddingLeft = UDim.new(0, 16)
	toastPadding.PaddingRight = UDim.new(0, 18)
	toastPadding.Parent = toastContent
	local toastList = Instance.new("UIListLayout")
	toastList.FillDirection = Enum.FillDirection.Horizontal
	toastList.VerticalAlignment = Enum.VerticalAlignment.Center
	toastList.Padding = UDim.new(0, 10)
	toastList.SortOrder = Enum.SortOrder.LayoutOrder
	toastList.Parent = toastContent
	local toastDot = Instance.new("Frame")
	toastDot.Name = "Accent"
	toastDot.Size = UDim2.fromOffset(10, 10)
	toastDot.BorderSizePixel = 0
	toastDot.LayoutOrder = 1
	GlassUI.round(toastDot)
	toastDot.Parent = toastContent
	local toastText = Instance.new("TextLabel")
	toastText.Name = "Message"
	toastText.LayoutOrder = 2
	toastText.AutomaticSize = Enum.AutomaticSize.X
	toastText.Size = UDim2.fromOffset(0, 46)
	toastText.BackgroundTransparency = 1
	toastText.Font = Theme.Fonts.Bold
	toastText.TextSize = 15
	toastText.TextColor3 = C.Text
	toastText.TextTruncate = Enum.TextTruncate.AtEnd
	toastText.Parent = toastContent

	local function placeToast()
		toast.Position = UDim2.new(0.5, 0, 0, GuiService.TopbarInset.Max.Y + 10)
	end
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placeToast)
	placeToast()

	local function showToast(message: string, color: Color3)
		toastSequence += 1
		local token = toastSequence
		toastText.Text = message
		toastDot.BackgroundColor3 = color
		toast.Visible = true
		TweenService:Create(toast, FADE, { GroupTransparency = 0 }):Play()
		task.delay(2.6, function()
			if token == toastSequence then
				TweenService:Create(toast, TweenInfo.new(0.35), { GroupTransparency = 1 }):Play()
				task.delay(0.36, function()
					if token == toastSequence then
						toast.Visible = false
					end
				end)
			end
		end)
	end

	EffectsController.register("RollPending", function()
		sequence += 1
		if pulse then
			pulse:Cancel()
		end
		showOverlay(C.Stroke)
		heading.Text = "ROLLING A MACHINE"
		heading.TextColor3 = C.Text
		card.Text = "? ? ?"
		card.TextColor3 = C.Text
		footnote.Text = "Free roll · results come from the server"
		scale.Scale = 1
		pulse = TweenService:Create(scale, TweenInfo.new(0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.04 })
		pulse:Play()
	end)

	EffectsController.register("UltraRareRollCutscene", function(payload)
		sequence += 1
		local token = sequence
		if pulse then
			pulse:Cancel()
		end
		local rarity = payload.Rarity or "Legendary"
		local rarityColor = getRarityColor(rarity)
		showOverlay(rarityColor)
		heading.Text = "ULTRA RARE MACHINE!"
		heading.TextColor3 = rarityColor
		card.TextColor3 = C.Text
		card.Text = string.format("%s · %s", payload.MachineName or "New machine", payload.Odds or "1/?")
		footnote.Text = "Open Inventory to place it"
		scale.Scale = 0.72
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(EconomyConfig.UltraRareCutscene.DurationSeconds, function()
			if token == sequence then
				hideOverlay(token)
			end
		end)
	end)

	EffectsController.register("MachineRolled", function(payload)
		sequence += 1
		local token = sequence
		if pulse then
			pulse:Cancel()
		end
		showOverlay(C.Stroke)
		heading.Text = "ROLLING A MACHINE"
		heading.TextColor3 = C.Text
		footnote.Text = ""
		local basePool = MachineDefinitions.getRollPool()
		local luckMultiplier = payload.LuckMultiplier or 1
		local pool = EconomyRules.getLuckAdjustedRollPool(basePool, luckMultiplier)
		local definition = MachineDefinitions.get(payload.MachineId or "")
		local rarity = payload.Rarity or (definition and EconomyRules.getMachineRarity(definition.Id, pool)) or "Common"
		local odds = if definition then EconomyRules.getMachineOddsLabel(definition.Id, pool) else nil
		task.spawn(function()
			for index = 1, 16 do
				if token ~= sequence then
					return
				end
				local sample = pool[(index * 7) % #pool + 1]
				local sampleOdds = EconomyRules.getMachineOddsLabel(sample.Id, pool) or "1/?"
				card.Text = string.format("%s · %s", sample.DisplayName, sampleOdds)
				local sampleRarity = EconomyRules.getMachineRarity(sample.Id, pool) or sample.Rarity
				card.TextColor3 = getRarityColor(sampleRarity)
				card.Rotation = if index % 2 == 0 then 1.5 else -1.5
				task.wait(0.045 + index * 0.005)
			end
			if token ~= sequence then
				return
			end
			local rarityColor = getRarityColor(rarity)
			card.Rotation = 0
			card.Text = if definition and odds then string.format("%s · %s", definition.DisplayName, odds) else "New machine"
			card.TextColor3 = C.Text
			heading.Text = string.upper(rarity) .. " MACHINE!"
			heading.TextColor3 = rarityColor
			revealStroke.Color = rarityColor
			footnote.Text = if luckMultiplier > 1 then string.format("Luck ×%.2f applied · open Inventory to place it", luckMultiplier) else "Open Inventory to place it"
			scale.Scale = 1.12
			TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			local oddsDenominator = if definition then EconomyRules.getMachineOddsDenominator(definition.Id, pool) else nil
			if EconomyRules.shouldPlayUltraRareCutscene(oddsDenominator) then
				task.wait(0.55)
				if token == sequence then
					EffectsController.play("UltraRareRollCutscene", {
						MachineName = definition.DisplayName,
						Rarity = rarity,
						Odds = odds or "1/?",
					})
				end
				return
			end
			task.wait(1.4)
			if token == sequence then
				hideOverlay(token)
			end
		end)
	end)

	EffectsController.register("RollRejected", function(payload)
		sequence += 1
		if pulse then
			pulse:Cancel()
		end
		hideOverlay(sequence)
		showToast(payload.Reason or "Roll unavailable", C.Bad)
	end)
	EffectsController.register("FirstItemSpawned", function()
		showToast("Your dropper made its first item!", getRarityColor("Rare"))
	end)
	EffectsController.register("ItemSold", function(payload)
		if type(payload.Coins) == "number" and payload.Coins > 0 and typeof(payload.Position) == "Vector3" then
			FloatingText.show(payload.Position, "+" .. NumberFormatter.format(payload.Coins) .. " Coins", C.Coin)
		end
	end)
	EffectsController.register("FirstItemSold", function()
		showToast("First sale! The seller earned Coins.", getRarityColor("Uncommon"))
	end)
	EffectsController.register("LootSpawned", function(payload)
		showToast("A booster appeared nearby", getBoosterColor(payload.BoosterId))
	end)
	EffectsController.register("LootClaimed", function(payload)
		showToast(string.format("Picked up %s · see Boosters", payload.DisplayName or "booster"), getBoosterColor(payload.BoosterId))
	end)
	EffectsController.register("BoosterUsed", function(payload)
		local color = getBoosterColor(payload.BoosterId)
		if payload.BoosterId == "Luck" then
			showToast(string.format("Luck x%.2f · %ds", payload.Multiplier, payload.DurationSeconds or 0), color)
		elseif payload.BoosterId == "Coin" and payload.Multiplier then
			showToast(string.format("Coins x%.2f · %ds", payload.Multiplier, payload.DurationSeconds or 0), color)
		end
	end)

	remote.OnClientEvent:Connect(function(eventName: string, payload: { [string]: any })
		EffectsController.play(eventName, payload)
	end)
end

return EffectsController
