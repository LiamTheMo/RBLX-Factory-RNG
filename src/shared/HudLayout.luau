--!strict
-- Pure HUD geometry for the glass interface. Inputs are the ScreenGui's safe-area
-- size; outputs are real-pixel rectangles plus the UIScale for panel content, so
-- the layout is testable outside Roblox and every control keeps a 44px target.
local HudLayout = {}

export type Rect = { X: number, Y: number, W: number, H: number }
export type Metrics = {
	Compact: boolean,
	Landscape: boolean,
	Portrait: boolean,
	Scale: number,
	Margin: number,
	Coin: Rect,
	Settings: Rect,
	Inventory: Rect,
	InventoryIconOnly: boolean,
	Roll: Rect,
	Panel: Rect,
	SettingsPanel: Rect,
	ChipsY: number,
	Columns: number,
	CardStyle: string,
}

local MIN_TOUCH = 44
local MARGIN = 12
local GAP = 12

local DESIGN = {
	Coin = { 196, 52 },
	Settings = { 56, 56 },
	Inventory = { 172, 64 },
	InventoryIcon = { 64, 64 },
	Roll = { 264, 76 },
	PanelWidth = 540,
	SettingsPanel = { 300, 268 },
}

local function rect(x: number, y: number, w: number, h: number): Rect
	return { X = x, Y = y, W = w, H = h }
end

local function touch(size: number, scale: number): number
	return math.max(MIN_TOUCH, size * scale)
end

function HudLayout.measure(width: number, height: number): Metrics
	width = math.max(width, 240)
	height = math.max(height, 240)
	local compact = width < 900 or height < 600
	local landscape = compact and width >= height
	local portrait = compact and not landscape
	local scale = if compact
		then math.clamp(math.min(width / 760, height / 420), 0.8, 1)
		else math.clamp(math.min(width / 1600, height / 900), 0.85, 1.35)

	local coin = rect(MARGIN, MARGIN, DESIGN.Coin[1] * scale, touch(DESIGN.Coin[2], scale))
	local settingsSize = touch(DESIGN.Settings[1], scale)
	-- Landscape phones dock the inventory on the right, so settings sit beside Coins.
	local settings = if landscape
		then rect(coin.X + coin.W + 8, MARGIN, settingsSize, settingsSize)
		else rect(width - MARGIN - settingsSize, MARGIN, settingsSize, settingsSize)

	local iconOnly = compact
	local inventoryDesign = if iconOnly then DESIGN.InventoryIcon else DESIGN.Inventory
	local inventoryHeight = touch(inventoryDesign[2], scale)
	local inventory = rect(MARGIN, height - MARGIN - inventoryHeight, math.max(inventoryHeight, inventoryDesign[1] * scale), inventoryHeight)

	local panel: Rect
	if landscape then
		local panelWidth = math.min(420, width * 0.5)
		panel = rect(width - MARGIN - panelWidth, MARGIN, panelWidth, height - MARGIN * 2)
	elseif portrait then
		local top = coin.Y + coin.H + GAP
		local bottom = height - MARGIN - touch(DESIGN.Roll[2], scale) - GAP
		panel = rect(MARGIN, top, width - MARGIN * 2, math.max(120, bottom - top))
	else
		local panelWidth = math.min(DESIGN.PanelWidth * scale, width * 0.48)
		local top = settings.Y + settings.H + GAP
		panel = rect(width - MARGIN - panelWidth, top, panelWidth, height - top - MARGIN)
	end

	-- Roll sits bottom-center, shifted into the free lane between Inventory and the panel.
	local laneLeft = inventory.X + inventory.W + GAP
	local laneRight = if portrait then width - MARGIN else panel.X - GAP
	local rollWidth = math.min(DESIGN.Roll[1] * scale, laneRight - laneLeft)
	local rollHeight = touch(DESIGN.Roll[2], scale)
	local center = math.clamp(width / 2, laneLeft + rollWidth / 2, laneRight - rollWidth / 2)
	local roll = rect(center - rollWidth / 2, height - MARGIN - rollHeight, rollWidth, rollHeight)

	local settingsPanelWidth = math.min(DESIGN.SettingsPanel[1] * scale, width - MARGIN * 2)
	-- The popover stops above the bottom dock; its content scrolls when space is short.
	local popoverBottom = if landscape then roll.Y - 8 else height - MARGIN
	local settingsPanelHeight = math.min(DESIGN.SettingsPanel[2] * scale, popoverBottom - settings.Y - settings.H - 8)
	local settingsPanelX = if landscape then settings.X else settings.X + settings.W - settingsPanelWidth
	local settingsPanel = rect(math.max(MARGIN, settingsPanelX), settings.Y + settings.H + 8, settingsPanelWidth, settingsPanelHeight)

	local logicalPanelWidth = panel.W / scale
	local columns = if landscape then 1 elseif logicalPanelWidth >= 500 then 3 else 2
	return {
		Compact = compact,
		Landscape = landscape,
		Portrait = portrait,
		Scale = scale,
		Margin = MARGIN,
		Coin = coin,
		Settings = settings,
		Inventory = inventory,
		InventoryIconOnly = iconOnly,
		Roll = roll,
		Panel = panel,
		SettingsPanel = settingsPanel,
		ChipsY = coin.Y + coin.H + 6,
		Columns = columns,
		CardStyle = if landscape then "Row" else "Tile",
	}
end

function HudLayout.overlaps(a: Rect, b: Rect): boolean
	return a.X < b.X + b.W and b.X < a.X + a.W and a.Y < b.Y + b.H and b.Y < a.Y + a.H
end

function HudLayout.inside(a: Rect, width: number, height: number): boolean
	return a.X >= 0 and a.Y >= 0 and a.X + a.W <= width + 1e-6 and a.Y + a.H <= height + 1e-6
end

return HudLayout
