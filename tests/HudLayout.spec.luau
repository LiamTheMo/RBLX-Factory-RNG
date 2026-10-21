local Layout = require("../src/shared/HudLayout")

local sizes = {
	{ 1672, 884 }, { 1366, 710 }, { 1920, 1022 }, { 2560, 1400 }, { 900, 600 },
	{ 874, 344 }, { 667, 317 }, { 812, 375 }, { 320, 568 }, { 390, 786 }, { 768, 1024 },
}

for _, size in ipairs(sizes) do
	local w, h = size[1], size[2]
	local m = Layout.measure(w, h)
	local label = `{w}x{h}`
	local controls = { Coin = m.Coin, Settings = m.Settings, Inventory = m.Inventory, Roll = m.Roll }
	for name, rect in pairs(controls) do
		assert(Layout.inside(rect, w, h), `{name} escapes the safe area at {label}`)
		assert(Layout.overlaps(rect, m.Panel) == false, `{name} overlaps the inventory panel at {label}`)
	end
	assert(Layout.inside(m.Panel, w, h), "inventory panel escapes the safe area at " .. label)
	assert(Layout.inside(m.SettingsPanel, w, h), "settings panel escapes the safe area at " .. label)
	assert(m.Panel.W > 200 and m.Panel.H >= 120, "inventory panel too small at " .. label)
	assert(m.SettingsPanel.H >= 120, "settings panel too short at " .. label)
	for _, name in ipairs({ "Coin", "Settings", "Inventory", "Roll" }) do
		assert(not Layout.overlaps(m.SettingsPanel, controls[name]), `settings panel covers {name} at {label}`)
	end
	local names = { "Coin", "Settings", "Inventory", "Roll" }
	for i = 1, #names do
		for j = i + 1, #names do
			assert(not Layout.overlaps(controls[names[i]], controls[names[j]]), `{names[i]} overlaps {names[j]} at {label}`)
		end
	end
	for _, name in ipairs({ "Settings", "Inventory", "Roll" }) do
		assert(controls[name].H >= 44 and controls[name].W >= 44, `{name} below the 44px touch target at {label}`)
	end
	assert(m.Roll.W >= 160, "roll button too narrow at " .. label)
	assert(m.Scale >= 0.8, "content scale too small to read at " .. label)
	assert(m.Columns >= 1 and m.Columns <= 3, "unexpected column count at " .. label)
	if m.Landscape then
		assert(m.CardStyle == "Row" and m.Columns == 1, "landscape phones use one row-style column")
	end
	if not m.Compact then
		assert(math.abs((m.Roll.X + m.Roll.W / 2) - w / 2) < 1 or m.Roll.X + m.Roll.W <= m.Panel.X, "desktop roll should be centered when it fits")
	end
end

print("HudLayout: desktop, landscape and portrait safe-area geometry passed")
