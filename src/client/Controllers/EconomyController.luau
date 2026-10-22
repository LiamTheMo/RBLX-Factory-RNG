--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberFormatter = require(Shared:WaitForChild("NumberFormatter"))
local BoosterConfig = require(Shared:WaitForChild("BoosterConfig"))
local HudLayout = require(Shared:WaitForChild("HudLayout"))
local EconomyRules = require(Shared:WaitForChild("EconomyRules"))
local UpgradeRules = require(Shared:WaitForChild("UpgradeRules"))

local EffectsController = require(script.Parent.EffectsController)
local InventoryController = require(script.Parent.InventoryController)
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
	local buyUpgrade = remotes:WaitForChild("BuyUpgrade") :: RemoteFunction
	local setAutoRecycle = remotes:WaitForChild("SetAutoRecycle") :: RemoteFunction
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

	-- Settings and Upgrades buttons, top right; each opens a popover in the same spot.
	local function topButton(name: string, iconKind: string): TextButton
		local button = GlassUI.button(settingsGui, name, "", "Secondary")
		button:SetAttribute("GlassBaseTransparency", Theme.Transparency.Glass)
		GlassUI.setStyle(button, "Secondary")
		button.BackgroundColor3 = C.Glass
		GlassUI.setRadius(button, 14)
		local icon = GlassUI.icon(button, iconKind)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.5, 0.5)
		return button
	end
	local settings = topButton("Settings", "Sliders")
	local upgradesButton = topButton("UpgradesButton", "Arrow")

	local function popover(name: string, heading: string, caption: string): (Frame, ScrollingFrame, UIScale)
		local frame = GlassUI.glass(settingsGui, name)
		frame.Visible = false
		local scale = Instance.new("UIScale")
		scale.Parent = frame
		local scroller = Instance.new("ScrollingFrame")
		scroller.Name = "Body"
		scroller.BackgroundTransparency = 1
		scroller.BorderSizePixel = 0
		scroller.Size = UDim2.fromScale(1, 1)
		scroller.CanvasSize = UDim2.new()
		scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroller.ScrollingDirection = Enum.ScrollingDirection.Y
		scroller.ScrollBarThickness = 3
		scroller.ScrollBarImageColor3 = C.Muted
		scroller.Parent = frame
		GlassUI.padding(scroller, 16, 14)
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 8)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = scroller
		local titleLabel = GlassUI.label(scroller, "Title", heading, 18, Theme.Fonts.Heavy)
		titleLabel.LayoutOrder = 1
		titleLabel.Size = UDim2.new(1, 0, 0, 24)
		local captionLabel = GlassUI.label(scroller, "Subtitle", caption, 12)
		captionLabel.LayoutOrder = 2
		captionLabel.Size = UDim2.new(1, 0, 0, 30)
		captionLabel.TextColor3 = C.Muted
		captionLabel.TextYAlignment = Enum.TextYAlignment.Top
		return frame, scroller, scale
	end

	-- Settings: save state, machine count and auto-recycle.
	local panel, body, panelScale = popover("EconomyPanel", "Settings", "Your factory saves automatically.")
	local saveValue = statRow(body, "Save", "Save", 3)
	local machinesValue = statRow(body, "Machines", "Machines owned", 4)
	local recycleTitle = GlassUI.label(body, "AutoRecycleTitle", "Auto-recycle", 14, Theme.Fonts.Bold)
	recycleTitle.LayoutOrder = 5
	recycleTitle.Size = UDim2.new(1, 0, 0, 20)
	local recycleHelp = GlassUI.label(body, "AutoRecycleHelp", "Rolls more common than these odds are recycled instead of kept. Example: 1/1000.", 11)
	recycleHelp.LayoutOrder = 6
	recycleHelp.Size = UDim2.new(1, 0, 0, 30)
	recycleHelp.TextColor3 = C.Muted
	recycleHelp.TextYAlignment = Enum.TextYAlignment.Top
	local recycleRow = Instance.new("Frame")
	recycleRow.Name = "AutoRecycleRow"
	recycleRow.LayoutOrder = 7
	recycleRow.BackgroundTransparency = 1
	recycleRow.Size = UDim2.new(1, 0, 0, 46)
	recycleRow.Parent = body
	local recycleInput = GlassUI.input(recycleRow, "AutoRecycleInput", "1/1000 or Off", 14)
	recycleInput.Size = UDim2.new(0.5, -6, 1, 0)
	local recycleSave = GlassUI.button(recycleRow, "AutoRecycleSave", "Save", "Primary", 14)
	recycleSave.Position = UDim2.new(0.5, 0, 0, 0)
	recycleSave.Size = UDim2.new(0.25, -4, 1, 0)
	local recycleOff = GlassUI.button(recycleRow, "AutoRecycleOff", "Off", "Secondary", 14)
	recycleOff.Position = UDim2.new(0.75, 2, 0, 0)
	recycleOff.Size = UDim2.new(0.25, -2, 1, 0)
	local recycleValue = statRow(body, "AutoRecycle", "Recycling below", 8)
	local status = GlassUI.label(body, "EconomyStatus", "", 12)
	status.LayoutOrder = 20
	status.Size = UDim2.new(1, 0, 0, 32)
	status.TextColor3 = C.Muted

	-- Upgrades: factory capacity plus the permanent Coin upgrades from UpgradeRules.
	local upgradesPanel, upgradesBody, upgradesScale = popover("UpgradesPanel", "Upgrades", "Spend Coins on permanent upgrades.")
	local slotsValue = statRow(upgradesBody, "Slots", "Factory slots", 3)
	local capacity = GlassUI.button(upgradesBody, "Capacity", "Expand capacity", "Primary", 14)
	capacity.LayoutOrder = 4
	capacity.Size = UDim2.new(1, 0, 0, 46)
	type UpgradeRow = { Card: Frame, Level: TextLabel, Effect: TextLabel, Buy: TextButton }
	local upgradeRows: { [string]: UpgradeRow } = {}
	for index, upgrade in ipairs(UpgradeRules.Definitions) do
		local card = Instance.new("Frame")
		card.Name = upgrade.Id .. "Upgrade"
		card.LayoutOrder = 10 + index
		card.Size = UDim2.new(1, 0, 0, 104)
		card.BackgroundColor3 = C.Stroke
		card.BackgroundTransparency = 0.94
		card.BorderSizePixel = 0
		GlassUI.corner(card, 10)
		GlassUI.padding(card, 10, 8)
		card.Parent = upgradesBody
		local name = GlassUI.label(card, "Name", upgrade.DisplayName, 14, Theme.Fonts.Bold)
		name.Size = UDim2.new(0.65, 0, 0, 18)
		local level = GlassUI.label(card, "Level", "", 12, Theme.Fonts.Bold)
		level.AnchorPoint = Vector2.new(1, 0)
		level.Position = UDim2.fromScale(1, 0)
		level.Size = UDim2.new(0.35, 0, 0, 18)
		level.TextXAlignment = Enum.TextXAlignment.Right
		level.TextColor3 = C.Accent
		local effect = GlassUI.label(card, "Effect", upgrade.Description, 11)
		effect.Position = UDim2.fromOffset(0, 20)
		effect.Size = UDim2.new(1, 0, 0, 28)
		effect.TextColor3 = C.Muted
		effect.TextYAlignment = Enum.TextYAlignment.Top
		local buy = GlassUI.button(card, "Buy", "Buy", "Primary", 13)
		buy.AnchorPoint = Vector2.new(0, 1)
		buy.Position = UDim2.fromScale(0, 1)
		buy.Size = UDim2.new(1, 0, 0, 40)
		upgradeRows[upgrade.Id] = { Card = card, Level = level, Effect = effect, Buy = buy }
	end
	local upgradeStatus = GlassUI.label(upgradesBody, "UpgradeStatus", "", 12)
	upgradeStatus.LayoutOrder = 30
	upgradeStatus.Size = UDim2.new(1, 0, 0, 32)
	upgradeStatus.TextColor3 = C.Muted

	-- The popovers and the inventory drawer overlap on most layouts, so only one is open.
	local function togglePopover(target: Frame)
		local opening = not target.Visible
		panel.Visible = false
		upgradesPanel.Visible = false
		target.Visible = opening
		if opening then
			InventoryController.close()
		end
	end
	settings.Activated:Connect(function()
		togglePopover(panel)
	end)
	upgradesButton.Activated:Connect(function()
		togglePopover(upgradesPanel)
	end)
	InventoryController.onOpen(function()
		panel.Visible = false
		upgradesPanel.Visible = false
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
	local function setUpgradeStatus(message: string, good: boolean?)
		upgradeStatus.Text = message
		upgradeStatus.TextColor3 = if good == true then C.Good elseif good == false then C.Bad else C.Muted
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
		local baseCooldown = state.BaseRollCooldownSeconds or 3
		for upgradeId, row in pairs(upgradeRows) do
			local level = UpgradeRules.level(state.Upgrades, upgradeId)
			local maxLevel = UpgradeRules.maxLevel(upgradeId)
			local cost = UpgradeRules.nextCost(state.Upgrades, upgradeId)
			row.Level.Text = `Lv {level}/{maxLevel}`
			local now = UpgradeRules.describe(upgradeId, level, baseCooldown)
			row.Effect.Text = if cost then `Now {now} → next {UpgradeRules.describe(upgradeId, level + 1, baseCooldown)}` else `Maxed: {now}`
			row.Buy.Text = if cost then `Buy · {NumberFormatter.format(cost)} Coins` else "Maxed"
			GlassUI.setEnabled(row.Buy, cost ~= nil and state.DataReady == true and state.Coins >= cost)
		end
		local threshold = EconomyRules.sanitizeAutoRecycle(state.AutoRecycleBelow)
		recycleValue.Text = EconomyRules.formatAutoRecycle(threshold)
		if not recycleInput:IsFocused() then
			recycleInput.Text = if threshold > 0 then EconomyRules.formatAutoRecycle(threshold) else ""
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
			EffectsController.play("MachineRolled", { MachineId = response.LastRoll, Rarity = response.LastRarity, LuckMultiplier = luckMultiplier, AutoRecycled = response.LastRollAutoRecycled == true })
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
				setUpgradeStatus(`Need {NumberFormatter.format(state.CapacityCost)} Coins to expand.`, false)
			end
			return
		end
		local response = invoke(buyCapacity)
		if response and response.Success then
			setUpgradeStatus(`Capacity expanded to {response.Capacity}.`, true)
			refresh(response)
		elseif response then
			setUpgradeStatus(response.Reason or "Capacity unavailable.", false)
		end
	end)

	for upgradeId, row in pairs(upgradeRows) do
		row.Buy.Activated:Connect(function()
			local upgrade = UpgradeRules.get(upgradeId)
			local cost = state and UpgradeRules.nextCost(state.Upgrades, upgradeId)
			if row.Buy:GetAttribute("GlassDisabled") == true then
				if cost then
					setUpgradeStatus(`Need {NumberFormatter.format(cost)} Coins.`, false)
				end
				return
			end
			local response = invoke(buyUpgrade, upgradeId)
			if response and response.Success and upgrade then
				setUpgradeStatus(`{upgrade.DisplayName} is now level {UpgradeRules.level(response.Upgrades, upgradeId)}.`, true)
				refresh(response)
			elseif response then
				setUpgradeStatus(response.Reason or "Upgrade unavailable.", false)
			end
		end)
	end

	local function saveAutoRecycle(threshold: number)
		local response = invoke(setAutoRecycle, threshold)
		if response and response.Success then
			local saved = EconomyRules.sanitizeAutoRecycle(response.AutoRecycleBelow)
			setStatus(if saved > 0 then `Auto-recycling rolls more common than {EconomyRules.formatAutoRecycle(saved)}.` else "Auto-recycle is off.", true)
			refresh(response)
		elseif response then
			setStatus(response.Reason or "Setting unavailable.", false)
		end
	end
	recycleSave.Activated:Connect(function()
		local threshold = EconomyRules.parseAutoRecycle(recycleInput.Text)
		if not threshold then
			setStatus("Enter odds like 1/1000, or Off.", false)
			return
		end
		saveAutoRecycle(threshold)
	end)
	recycleInput.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			local threshold = EconomyRules.parseAutoRecycle(recycleInput.Text)
			if threshold then
				saveAutoRecycle(threshold)
			else
				setStatus("Enter odds like 1/1000, or Off.", false)
			end
		end
	end)
	recycleOff.Activated:Connect(function()
		saveAutoRecycle(0)
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
		place(upgradesButton, metrics.Upgrades)
		local popoverRect = metrics.SettingsPanel
		local touchHeight = math.max(46, Theme.MinTouch / s)
		capacity.Size = UDim2.new(1, 0, 0, touchHeight)
		recycleRow.Size = UDim2.new(1, 0, 0, touchHeight)
		local buyHeight = math.max(40, Theme.MinTouch / s)
		for _, row in pairs(upgradeRows) do
			row.Buy.Size = UDim2.new(1, 0, 0, buyHeight)
			-- Name and effect lines (48) above the button, plus the card's padding.
			row.Card.Size = UDim2.new(1, 0, 0, 48 + 6 + buyHeight + 16)
		end
		for _, pair in ipairs({ { panel, panelScale }, { upgradesPanel, upgradesScale } }) do
			local frame, scale = pair[1] :: Frame, pair[2] :: UIScale
			scale.Scale = s
			frame.Position = UDim2.fromOffset(popoverRect.X, popoverRect.Y)
			frame.Size = UDim2.fromOffset(popoverRect.W / s, popoverRect.H / s)
		end
	end

	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
	setUpgradeStatus("Production funds every upgrade.", nil)
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
