--!strict
-- Shared palette and metrics for the semi-transparent glass HUD. Pure data so the
-- client UI kit, server-built world labels and tests all read one source of truth.
local HudTheme = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

HudTheme.Colors = table.freeze({
	Glass = rgb(16, 22, 31),
	GlassTop = rgb(38, 48, 64),
	Card = rgb(24, 31, 43),
	CardTop = rgb(44, 55, 72),
	Stroke = rgb(255, 255, 255),
	Text = rgb(244, 247, 250),
	Muted = rgb(166, 178, 194),
	Accent = rgb(255, 196, 92),
	AccentDeep = rgb(240, 146, 52),
	AccentText = rgb(38, 26, 12),
	Coin = rgb(255, 210, 90),
	CoinRim = rgb(214, 150, 40),
	Good = rgb(142, 230, 162),
	Bad = rgb(255, 140, 125),
	Overlay = rgb(8, 12, 18),
	Shadow = rgb(4, 6, 10),
})

HudTheme.Transparency = table.freeze({
	Glass = 0.3,
	Card = 0.22,
	Stroke = 0.84,
	Overlay = 0.42,
	Ghost = 0.88,
	Disabled = 0.55,
})

HudTheme.Radius = table.freeze({
	Panel = 16,
	Card = 12,
	Button = 10,
})

HudTheme.Fonts = table.freeze({
	Regular = Enum.Font.Gotham,
	Medium = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Heavy = Enum.Font.GothamBlack,
})

-- Logical-pixel touch target. Controls scale with the HUD but never drop below it.
HudTheme.MinTouch = 44
HudTheme.RevealBlurSize = 12

return table.freeze(HudTheme)
