--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberFormatter = require(Shared:WaitForChild("NumberFormatter"))
local BoosterConfig = require(Shared:WaitForChild("BoosterConfig"))
local HudLayout = require(Shared:WaitForChild("HudLayout"))

local EffectsController = require(script.Parent.EffectsController)
local GlassUI = require(script.Parent.GlassUI)

local Theme = GlassUI.Theme
local C = Theme.Colors
local EconomyController = {}
local started = false

local boosterColors: { [string]: Color3 } = {}
for _, booster in ipairs(BoosterConfig.Definitions) do
	boosterColors[booster.Id] = GlassUI.fromRgb(booster.Color)
end

local function statRow(parent: Instance, name: string, title: string, order: number): TextLabel
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundColor3 = C.Stroke
	row.BackgroundTransparency = 0.94
	row.BorderSizePixel = 0
	GlassUI.corner(row, 8)
	GlassUI.padding(row, 10, 0)
	row.Parent = parent
	local key = GlassUI.label(row, "Key", title, 12)
	key.Size = UDim2.fromScale(0.55, 1)
	key.TextColor3 = C.Muted
	local value = GlassUI.label(row, name, "—", 13, Theme.Fonts.Bold)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.Size = UDim2.fromScale(0.45, 1)
	value.TextXAlignment = Enum.TextXAlignment.Right
	return value
end

function EconomyController.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Factory")
	local getState = remotes:WaitForChild("GetEconomyState") :: RemoteFunction
	local rollMachine = remotes:WaitForChild("RollMachine") :: RemoteFunction
	local buyCapacity = remotes:WaitForChild("BuyCapacity") :: RemoteFunction
	local presentationEvent = remotes:WaitForChild("PresentationEvent") :: RemoteEvent

	local screenGui = GlassUI.screen(playerGui, "EconomyHud", 10)
	local settingsGui = GlassUI.screen(playerGui, "FactorySettings", 18)

	-- Coins pill, top left.
	local coins = GlassUI.glass(screenGui, "CoinHud", 999)
	local coinScale = Instance.new("UIScale")
	coinScale.Parent = coins
	local coinIcon = GlassUI.icon(coins, "Coin")
	coinIcon.AnchorPoint = Vector2.new(0, 0.5)
	local balance = GlassUI.label(coins, "Balance", "—", 20, Theme.Fonts.Heavy)
	balance.TextWrapped = false
	balance.TextTruncate = Enum.TextTruncate.AtEnd
	local coinCaption = GlassUI.label(coins, "Caption", "COINS", 10, Theme.Fonts.Bold)
	coinCaption.TextColor3 = C.Muted

	-- Active booster chips stack under the Coins pill.
	local chips = Instance.new("Frame")
	chips.Name = "EffectChips"
	chips.BackgroundTransparency = 1
	chips.AutomaticSize = Enum.AutomaticSize.XY
	chips.Size = UDim2.fromOffset(0, 0)
	chips.Parent = screenGui
	local chipList = Instance.new("UIListLayout")
	chipList.Padding = UDim.new(0, 6)
	chipList.SortOrder = Enum.SortOrder.LayoutOrder
	chipList.Parent = chips
	local luckChip = GlassUI.chip(chips, "LuckStatus", "", boosterColors.Luck or C.Accent)
	luckChip.LayoutOrder = 1
	local coinChip = GlassUI.chip(chips, "CoinBoostStatus", "", boosterColors.Coin or C.Coin)
	coinChip.LayoutOrder = 2
	for _, chip in ipairs({ luckChip, coinChip }) do
		chip.BackgroundTransparency = 0.35
		chip.BackgroundColor3 = C.Glass
		chip.Visible = false
	end

	-- Roll button, bottom center.
	local rollDock = Instance.new("Frame")
	rollDock.Name = "RollDock"
	rollDock.BackgroundTransparency = 1
	rollDock.Parent = screenGui
	local roll = GlassUI.button(rollDock, "Roll", "", "Primary")
	roll.Size = UDim2.fromScale(1, 1)
	GlassUI.setRadius(roll, 18)
	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.BackgroundColor3 = C.Accent
	progress.BackgroundTransparency = 0.55
	progress.BorderSizePixel = 0
	progress.Size = UDim2.fromScale(0, 1)
	progress.Visible = false
	progress.ZIndex = 1
	GlassUI.corner(progress, 18)
	progress.Parent = roll
	local dice = GlassUI.icon(roll, "Dice", C.AccentText)
	dice.AnchorPoint = Vector2.new(0, 0.5)
	dice.Position = UDim2.fromScale(0.09, 0.5)
	dice.Size = UDim2.fromScale(0.2, 0.5)
	dice.ZIndex = 2
	local caption = GlassUI.label(roll, "Caption", "ROLL", 26, Theme.Fonts.Heavy)
	caption.Position = UDim2.fromScale(0.3, 0.12)
	caption.Size = UDim2.fromScale(0.64, 0.5)
	caption.TextWrapped = false
	caption.TextColor3 = C.AccentText
	caption.ZIndex = 2
	local hint = GlassUI.label(roll, "Hint", "Free machine", 12, Theme.Fonts.Bold)
	hint.Position = UDim2.fromScale(0.3, 0.58)
	hint.Size = UDim2.fromScale(0.64, 0.28)
	hint.TextWrapped = false
	hint.TextColor3 = C.AccentText
	hint.TextTransparency = 0.25
	hint.ZIndex = 2

	-- Settings button and its popover, top right.
	local settings = GlassUI.button(settingsGui, "Settings", "", "Secondary")
	settings.BackgroundColor3 = C.Glass
	settings.BackgroundTransparency = Theme.Transparency.Glass
	GlassUI.setRadius(settings, 14)
	local settingsIcon = GlassUI.icon(settings, "Sliders")
	settingsIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	settingsIcon.Position = UDim2.fromScale(0.5, 0.5)
	settingsIcon.Size = UDim2.fromScale(0.5, 0.5)

	local panel = GlassUI.glass(settingsGui, "EconomyPanel")
	panel.Visible = false
	local panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Size = UDim2.fromScale(1, 1)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.ScrollBarThickness = 3
	body.ScrollBarImageColor3 = C.Muted
	body.Parent = panel
	GlassUI.padding(body, 16, 14)
	local bodyList = Instance.new("UIListLayout")
	bodyList.Padding = UDim.new(0, 8)
	bodyList.SortOrder = Enum.SortOrder.LayoutOrder
	bodyList.Parent = body

	local title = GlassUI.label(body, "Title", "Factory", 18, Theme.Fonts.Heavy)
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 24)
	local subtitle = GlassUI.label(body, "Subtitle", "Rolls are free. Production funds capacity.", 12)
	subtitle.LayoutOrder = 2
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	subtitle.TextColor3 = C.Muted
	local slotsValue = statRow(body, "Slots", "Factory slots", 3)
	local machinesValue = statRow(body, "Machines", "Machines owned", 4)
	local saveValue = statRow(body, "Save", "Save", 5)
	local capacity = GlassUI.button(body, "Capacity", "Expand capacity", "Primary", 14)
	capacity.LayoutOrder = 6
	capacity.Size = UDim2.new(1, 0, 0, 46)
	local status = GlassUI.label(body, "EconomyStatus", "", 12)
	status.LayoutOrder = 7
	status.Size = UDim2.new(1, 0, 0, 32)
	status.TextColor3 = C.Muted

	settings.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	local state: any = nil
	local cooldownEndAt = 0
	local cooldownTotal = 0
	local rolling = false
	local metrics = HudLayout.measure(1024, 768)

	local function setStatus(message: string, good: boolean?)
		status.Text = message
		status.TextColor3 = if good == true then C.Good elseif good == false then C.Bad else C.Muted
	end

	local function boostChip(chip: Frame, prefix: string, multiplier: any, expiresAt: any)
		local remaining = if type(expiresAt) == "number" then expiresAt - workspace:GetServerTimeNow() else 0
		local active = type(multiplier) == "number" and multiplier > 1 and remaining > 0
		chip.Visible = active
		if active then
			(chip :: any).Text.Text = string.format("%s ×%.2f · %ds", prefix, multiplier, math.ceil(remaining))
		end
	end

	local function updateEffectChips()
		boostChip(luckChip, "Luck", player:GetAttribute("FactoryLuckMultiplier"), player:GetAttribute("FactoryLuckExpiresAt"))
		boostChip(coinChip, "Coins", player:GetAttribute("FactorySaleValueMultiplier"), player:GetAttribute("FactorySaleValueExpiresAt"))
	end

	local lastRollState = ""
	local function updateRollButton()
		local remaining = math.max(0, cooldownEndAt - os.clock())
		local ready = state ~= nil and state.DataReady == true
		local rollState = if rolling then "Rolling" elseif not ready then "Loading" elseif remaining > 0 then "Cooldown" else "Ready"
		roll:SetAttribute("RollState", rollState)
		if rollState == "Cooldown" then
			hint.Text = string.format("Ready in %.1fs", remaining)
		end
		if rollState == lastRollState then
			return
		end
		lastRollState = rollState
		local isReady = rollState == "Ready"
		GlassUI.setStyle(roll, if isReady then "Primary" else "Secondary")
		roll.Active = isReady
		local ink = if isReady then C.AccentText else C.Text
		caption.TextColor3 = ink
		hint.TextColor3 = if isReady then C.AccentText else C.Muted
		for _, child in ipairs(dice:GetDescendants()) do
			if child:IsA("Frame") and child.Name == "Face" then
				child.BackgroundColor3 = ink
			end
		end
		caption.Text = if rollState == "Rolling" then "ROLLING…" elseif rollState == "Loading" then "LOADING" else "ROLL"
		if rollState == "Ready" then
			hint.Text = "Free machine"
		elseif rollState == "Loading" then
			hint.Text = "Factory data is loading"
		elseif rollState == "Rolling" then
			hint.Text = "Revealing your machine"
		end
		progress.Visible = rollState == "Cooldown"
	end

	local function syncCooldown(response: any)
		if response and type(response.RollCooldownRemaining) == "number" then
			local remaining = math.max(0, response.RollCooldownRemaining)
			cooldownEndAt = os.clock() + remaining
			if remaining > 0 then
				cooldownTotal = math.max(cooldownTotal, remaining)
				progress.Size = UDim2.fromScale(1 - remaining / cooldownTotal, 1)
				TweenService:Create(progress, TweenInfo.new(remaining, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
			else
				cooldownTotal = 0
			end
			updateRollButton()
		end
	end

	local function invoke(remote: RemoteFunction, ...: any): any
		local arguments = { ... }
		local success, response = pcall(function()
			return remote:InvokeServer(table.unpack(arguments))
		end)
		if not success then
			setStatus("Server request failed. Try again.", false)
			return nil
		end
		return response
	end

	local lastCoins: number? = nil
	local function pulseCoins(value: number)
		if lastCoins and value > lastCoins then
			coinScale.Scale = 1.06
			TweenService:Create(coinScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		lastCoins = value
	end

	local function render()
		if not state then
			return
		end
		balance.Text = NumberFormatter.format(state.Coins)
		pulseCoins(state.Coins)
		slotsValue.Text = `{state.Capacity} / {state.MaxCapacity}`
		machinesValue.Text = `{state.InventoryCount or 0} / {state.MaxInventoryMachines or 200}`
		if player:GetAttribute("FactoryDataLocked") then
			saveValue.Text = "Another session"
			saveValue.TextColor3 = C.Bad
		elseif player:GetAttribute("FactoryDataSaveError") then
			saveValue.Text = "Retrying"
			saveValue.TextColor3 = C.Bad
		elseif player:GetAttribute("FactoryDataLoaded") then
			saveValue.Text = "Saved"
			saveValue.TextColor3 = C.Good
		elseif state.DataError then
			saveValue.Text = "Unavailable"
			saveValue.TextColor3 = C.Bad
		else
			saveValue.Text = "Loading"
			saveValue.TextColor3 = C.Text
		end
		if state.CapacityCost then
			capacity.Text = `Expand capacity · {NumberFormatter.format(state.CapacityCost)} Coins`
			GlassUI.setEnabled(capacity, state.DataReady == true and state.Coins >= state.CapacityCost)
		else
			capacity.Text = "Capacity maxed"
			GlassUI.setEnabled(capacity, false)
		end
		if not state.DataReady then
			setStatus(state.DataError or "Factory data is loading.", nil)
		end
		updateEffectChips()
	end

	local function refresh(responseOverride: any)
		local response = responseOverride or invoke(getState)
		syncCooldown(response)
		if response and response.Success then
			state = response
			local ready = player:GetAttribute("FactoryDataReady")
			if type(ready) == "boolean" then
				state.DataReady = ready
			end
			render()
			updateRollButton()
		else
			setStatus(response and response.Reason or "Economy is loading.", false)
		end
	end

	roll.Activated:Connect(function()
		if rolling or not state or state.DataReady ~= true or os.clock() < cooldownEndAt then
			return
		end
		rolling = true
		updateRollButton()
		EffectsController.play("RollPending")
		local response = invoke(rollMachine)
		if response and response.Success then
			local luckMultiplier = response.LastRollLuckMultiplier or 1
			refresh(response)
			EffectsController.play("MachineRolled", { MachineId = response.LastRoll, Rarity = response.LastRarity, LuckMultiplier = luckMultiplier })
		else
			syncCooldown(response)
			setStatus(response and response.Reason or "Roll unavailable", false)
			EffectsController.play("RollRejected", { Reason = response and response.Reason or "Roll unavailable" })
		end
		task.delay(1.8, function()
			rolling = false
			updateRollButton()
		end)
	end)

	capacity.Activated:Connect(function()
		if capacity:GetAttribute("GlassDisabled") == true then
			if state and state.CapacityCost then
				setStatus(`Need {NumberFormatter.format(state.CapacityCost)} Coins to expand.`, false)
			end
			return
		end
		local response = invoke(buyCapacity)
		if response and response.Success then
			setStatus(`Capacity expanded to {response.Capacity}.`, true)
			refresh(response)
		elseif response then
			setStatus(response.Reason or "Capacity unavailable.", false)
		end
	end)

	local function place(instance: GuiObject, rect: HudLayout.Rect)
		instance.Position = UDim2.fromOffset(rect.X, rect.Y)
		instance.Size = UDim2.fromOffset(rect.W, rect.H)
	end

	local function layout()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		metrics = HudLayout.measure(size.X, size.Y)
		local s = metrics.Scale
		place(coins, metrics.Coin)
		coinIcon.Position = UDim2.new(0, 12 * s, 0.5, 0)
		coinIcon.Size = UDim2.fromOffset(28 * s, 28 * s)
		local textLeft = 50 * s
		balance.Position = UDim2.new(0, textLeft, 0, 6 * s)
		balance.Size = UDim2.new(1, -textLeft - 14 * s, 0.6, -2 * s)
		balance.TextSize = math.round(22 * s)
		coinCaption.Position = UDim2.new(0, textLeft, 0.6, -4 * s)
		coinCaption.Size = UDim2.new(1, -textLeft - 14 * s, 0.32, 0)
		coinCaption.TextSize = math.round(10 * s)
		chips.Position = UDim2.fromOffset(metrics.Coin.X, metrics.ChipsY)
		place(rollDock, metrics.Roll)
		caption.TextSize = math.round(26 * s)
		hint.TextSize = math.round(12 * s)
		place(settings, metrics.Settings)
		local popover = metrics.SettingsPanel
		panelScale.Scale = s
		panel.Position = UDim2.fromOffset(popover.X, popover.Y)
		panel.Size = UDim2.fromOffset(popover.W / s, popover.H / s)
	end

	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
	setStatus("Roll for free; production funds capacity upgrades.", nil)
	player:GetAttributeChangedSignal("FactoryCoins"):Connect(function()
		local value = player:GetAttribute("FactoryCoins")
		if state and type(value) == "number" then
			state.Coins = value
			render()
		end
	end)
	for _, attribute in ipairs({ "FactoryDataReady", "FactoryDataError", "FactoryDataLoaded", "FactoryDataLocked", "FactoryDataSaveError" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if state then
				state.DataReady = player:GetAttribute("FactoryDataReady") == true
				state.DataError = player:GetAttribute("FactoryDataError")
				render()
				updateRollButton()
			end
		end)
	end
	presentationEvent.OnClientEvent:Connect(function(eventName: string, payload: any)
		if eventName == "ItemSold" and state and type(payload) == "table" and type(payload.Balance) == "number" then
			state.Coins = payload.Balance
			render()
		elseif eventName == "InventoryChanged" then
			refresh(nil)
		end
	end)
	refresh(nil)
	task.spawn(function()
		while screenGui.Parent do
			updateRollButton()
			updateEffectChips()
			task.wait(0.1)
		end
	end)
end

return EconomyController
