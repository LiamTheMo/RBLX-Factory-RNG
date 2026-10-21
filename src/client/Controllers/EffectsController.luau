--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared:WaitForChild("EconomyConfig"))
local BoosterConfig = require(Shared:WaitForChild("BoosterConfig"))
local FloatingText = require(script.Parent.FloatingText)
local NumberFormatter = require(Shared:WaitForChild("NumberFormatter"))
local GlassUI = require(script.Parent.GlassUI)
local RollReveal = require(script.Parent.RollRevealController)

local Theme = GlassUI.Theme
local C = Theme.Colors
local FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- A small event registry keeps presentation separate from gameplay authority.
-- New moments can register a handler without changing the economy or factory services.
local EffectsController = {}
local handlers: { [string]: ({ [string]: any }) -> () } = {}
local started = false
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

	local reveal = RollReveal.mount(gui)

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
	toastText.FontFace = Theme.Fonts.Bold
	toastText.TextSize = 15
	toastText.TextColor3 = C.Text
	toastText.TextTruncate = Enum.TextTruncate.AtEnd
	toastText.Parent = toastContent
	-- Cap the label inside the 520px pill so long reasons truncate instead of clipping.
	local toastTextLimit = Instance.new("UISizeConstraint")
	toastTextLimit.MaxSize = Vector2.new(470, 46)
	toastTextLimit.Parent = toastText

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
		reveal.pending()
	end)
	EffectsController.register("MachineRolled", function(payload)
		reveal.rolled(payload.MachineId, payload.Rarity, payload.LuckMultiplier)
	end)
	EffectsController.register("UltraRareRollCutscene", function(payload)
		reveal.ultra(payload.MachineName or "New machine", payload.Rarity or "Legendary", payload.Odds or "")
	end)
	EffectsController.register("RollRejected", function(payload)
		reveal.cancel()
		showToast(payload.Reason or "Roll unavailable", C.Bad)
	end)
	EffectsController.register("FirstItemSpawned", function()
		showToast("Your dropper made its first item!", getRarityColor("Rare"))
	end)
	EffectsController.register("ItemSold", function(payload)
		if type(payload.Coins) == "number" and payload.Coins > 0 and typeof(payload.Position) == "Vector3" then
			FloatingText.show(payload.Position, "+" .. NumberFormatter.format(payload.Coins), C.Coin)
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
