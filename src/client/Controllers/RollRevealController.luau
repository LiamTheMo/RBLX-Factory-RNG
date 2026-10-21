--!strict

-- Roll presentation only; the server has already chosen the machine. A virtualised reel of
-- machine cards spins while the request is in flight, eases onto the server result under a
-- centre marker, then hands over to a result card with a live 3D preview. Rarer results add
-- light rays, sparkles and (for ultra-rare odds) a flash and a longer hold.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared:WaitForChild("EconomyConfig"))
local EconomyRules = require(Shared:WaitForChild("EconomyRules"))
local MachineDefinitions = require(Shared:WaitForChild("MachineDefinitions"))
local MachineVisualConfig = require(Shared:WaitForChild("MachineVisualConfig"))
local ModelBuilder = require(Shared:WaitForChild("MachineModelBuilder"))
local GlassUI = require(script.Parent.GlassUI)

local Theme = GlassUI.Theme
local C = Theme.Colors

local RollReveal = {}

local STAGE = Vector2.new(760, 460)
local CARD = Vector2.new(124, 156)
local PITCH = CARD.X + 12
local VISIBLE_CARDS = 9
local SPIN_SPEED = 20 -- cards per second while waiting for the server
local LAND_SECONDS = 2.6
local FADE = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CATEGORY_NAMES = { Producer = "Dropper", Processor = "Upgrader", Seller = "Seller" }
local CATEGORY_GLYPHS = { Producer = "▼", Processor = "◆", Seller = "$" }

local rarityColors: { [string]: Color3 } = {}
local rarityTier: { [string]: number } = {}
for index, band in ipairs(EconomyConfig.RarityOddsBands) do
	rarityColors[band.Name] = GlassUI.fromRgb(band.Color)
	rarityTier[band.Name] = index
end

local function rarityColor(rarity: string?): Color3
	return rarityColors[rarity or ""] or C.Text
end

type CardData = { Id: string, Name: string, Rarity: string, Odds: string, Glyph: string }
type CardView = { Frame: Frame, Glyph: TextLabel, Ring: Frame, Name: TextLabel, Odds: TextLabel, Bar: Frame, Stroke: UIStroke, Index: number }

function RollReveal.mount(gui: ScreenGui)
	-- The dim layer never takes input; only the stage-sized Skip button does, and only
	-- while landing or showing the result, so movement controls keep working.
	local overlay = Instance.new("Frame")
	overlay.Name = "CutsceneOverlay"
	overlay.Active = false
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = C.Overlay
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.Parent = gui

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = C.Text
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 20
	flash.Parent = overlay

	-- Fixed logical stage, scaled to fit any viewport.
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromOffset(STAGE.X, STAGE.Y)
	stage.BackgroundTransparency = 1
	stage.Parent = overlay
	local stageScale = Instance.new("UIScale")
	stageScale.Parent = stage
	local function fit()
		local size = gui.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			stageScale.Scale = math.clamp(math.min((size.X - 24) / STAGE.X, (size.Y - 24) / STAGE.Y), 0.4, 1.25)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local title = GlassUI.label(stage, "Title", "ROLLING", 40, Theme.Fonts.Heavy)
	title.Size = UDim2.new(1, 0, 0, 52)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextStrokeColor3 = C.Shadow
	title.TextStrokeTransparency = 0.6
	title.ZIndex = 4
	local subtitle = GlassUI.label(stage, "Subtitle", "", 15, Theme.Fonts.Bold)
	subtitle.Position = UDim2.fromOffset(0, 52)
	subtitle.Size = UDim2.new(1, 0, 0, 22)
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.TextColor3 = C.Muted
	subtitle.ZIndex = 4

	-- Reel: a CanvasGroup so a transparency gradient can fade both edges.
	local reel = Instance.new("CanvasGroup")
	reel.Name = "Reel"
	reel.Position = UDim2.fromOffset(0, 100)
	reel.Size = UDim2.new(1, 0, 0, CARD.Y + 36)
	reel.BackgroundTransparency = 1
	reel.Parent = stage
	local reelFade = Instance.new("UIGradient")
	reelFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.16, 0),
		NumberSequenceKeypoint.new(0.84, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	reelFade.Parent = reel
	local track = GlassUI.glass(reel, "Track", 18)
	track.Position = UDim2.fromOffset(2, 2)
	track.Size = UDim2.new(1, -4, 1, -4)

	local cards: { CardView } = {}
	for slot = 1, VISIBLE_CARDS do
		local frame = GlassUI.card(reel, "ReelCard" .. slot, C.Stroke)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromOffset(CARD.X, CARD.Y)
		frame.Position = UDim2.new(0.5, 0, 0.5, 0)
		frame.ZIndex = 2
		local ring = Instance.new("Frame")
		ring.Name = "Ring"
		ring.AnchorPoint = Vector2.new(0.5, 0)
		ring.Position = UDim2.new(0.5, 0, 0, 14)
		ring.Size = UDim2.fromOffset(58, 58)
		ring.BorderSizePixel = 0
		ring.BackgroundTransparency = 0.7
		GlassUI.round(ring)
		ring.Parent = frame
		local glyph = GlassUI.label(ring, "Glyph", "", 26, Theme.Fonts.Heavy)
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		local nameLabel = GlassUI.label(frame, "MachineName", "", 13, Theme.Fonts.Bold)
		nameLabel.Position = UDim2.fromOffset(8, 80)
		nameLabel.Size = UDim2.new(1, -16, 0, 34)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.TextYAlignment = Enum.TextYAlignment.Top
		local oddsLabel = GlassUI.label(frame, "RollOdds", "", 11, Theme.Fonts.Medium)
		oddsLabel.Position = UDim2.fromOffset(8, 116)
		oddsLabel.Size = UDim2.new(1, -16, 0, 16)
		oddsLabel.TextXAlignment = Enum.TextXAlignment.Center
		oddsLabel.TextColor3 = C.Muted
		local bar = Instance.new("Frame")
		bar.Name = "RarityBar"
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -8)
		bar.Size = UDim2.new(1, -28, 0, 4)
		bar.BorderSizePixel = 0
		GlassUI.round(bar)
		bar.Parent = frame
		local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
		table.insert(cards, { Frame = frame, Glyph = glyph, Ring = ring, Name = nameLabel, Odds = oddsLabel, Bar = bar, Stroke = stroke, Index = -1 })
	end

	-- Centre marker: a glowing line with pointers, outside the faded group.
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0)
	marker.Position = UDim2.new(0.5, 0, 0, 92)
	marker.Size = UDim2.fromOffset(4, CARD.Y + 52)
	marker.BackgroundColor3 = C.Accent
	marker.BorderSizePixel = 0
	marker.ZIndex = 5
	GlassUI.round(marker)
	marker.Parent = stage
	local markerScale = Instance.new("UIScale")
	markerScale.Parent = marker
	for _, pointer in ipairs({ { 0, -2, 0 }, { 1, 2, 180 } }) do
		local tip = GlassUI.label(marker, "Pointer", "▼", 20, Theme.Fonts.Heavy)
		tip.AnchorPoint = Vector2.new(0.5, pointer[1])
		tip.Position = UDim2.new(0.5, 0, pointer[1], pointer[2] * 6)
		tip.Size = UDim2.fromOffset(24, 20)
		tip.Rotation = pointer[3]
		tip.TextColor3 = C.Accent
		tip.TextXAlignment = Enum.TextXAlignment.Center
	end

	-- Light rays behind the result for Rare and above.
	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.new(0.5, 0, 0, 250)
	rays.Size = UDim2.fromOffset(820, 820)
	rays.BackgroundTransparency = 1
	rays.Visible = false
	rays.Parent = stage
	local rayBars: { Frame } = {}
	for index = 1, 12 do
		local ray = Instance.new("Frame")
		ray.Name = "Ray" .. index
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(0, 46, 1, 0)
		ray.Rotation = index * 15
		ray.BorderSizePixel = 0
		ray.BackgroundTransparency = 0.55
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 0.35),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(0.58, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
		ray.Parent = rays
		table.insert(rayBars, ray)
	end

	-- Result card; the names Heading and RevealCard are kept for the Studio smoke test.
	local result = Instance.new("CanvasGroup")
	result.Name = "RevealPanel"
	result.AnchorPoint = Vector2.new(0.5, 0)
	result.Position = UDim2.new(0.5, 0, 0, 92)
	result.Size = UDim2.fromOffset(600, 300)
	result.BackgroundTransparency = 1
	result.GroupTransparency = 1
	result.Visible = false
	result.ZIndex = 3
	result.Parent = stage
	local resultScale = Instance.new("UIScale")
	resultScale.Parent = result
	local resultBackdrop = GlassUI.glass(result, "Backdrop", 22)
	resultBackdrop.Position = UDim2.fromOffset(3, 3)
	resultBackdrop.Size = UDim2.new(1, -6, 1, -6)
	local resultStroke = resultBackdrop:FindFirstChildOfClass("UIStroke") :: UIStroke
	resultStroke.Thickness = 3
	resultStroke.Transparency = 0.2
	local heading = GlassUI.label(result, "Heading", "", 22, Theme.Fonts.Heavy)
	heading.Position = UDim2.fromOffset(24, 16)
	heading.Size = UDim2.new(1, -48, 0, 28)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	local previewWell = Instance.new("Frame")
	previewWell.Name = "PreviewWell"
	-- Lives beside the CanvasGroup (over its left side) so the ViewportFrame renders directly.
	previewWell.Position = UDim2.new(0.5, -300 + 24, 0, 92 + 56)
	previewWell.Size = UDim2.fromOffset(200, 200)
	previewWell.BackgroundColor3 = C.Stroke
	previewWell.BackgroundTransparency = 1
	previewWell.BorderSizePixel = 0
	previewWell.Visible = false
	previewWell.ZIndex = 4
	GlassUI.corner(previewWell, 16)
	previewWell.Parent = stage
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "MachinePreview"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(205, 212, 224)
	viewport.LightColor = Color3.fromRGB(255, 244, 225)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.ImageTransparency = 1
	viewport.ZIndex = 4
	viewport.Parent = previewWell
	local previewGlyph = GlassUI.label(previewWell, "Glyph", "", 72, Theme.Fonts.Heavy)
	previewGlyph.Size = UDim2.fromScale(1, 1)
	previewGlyph.TextXAlignment = Enum.TextXAlignment.Center
	previewGlyph.ZIndex = 5
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.Text = ""
	skip.AutoButtonColor = false
	skip.BackgroundTransparency = 1
	skip.Size = UDim2.fromScale(1, 1)
	skip.Visible = false
	skip.ZIndex = 10
	skip.Parent = stage
	local nameCard = GlassUI.label(result, "RevealCard", "", 40, Theme.Fonts.Heavy)
	nameCard.Position = UDim2.fromOffset(244, 54)
	nameCard.Size = UDim2.new(1, -268, 0, 92)
	nameCard.TextScaled = true
	nameCard.TextWrapped = true
	nameCard.TextYAlignment = Enum.TextYAlignment.Center
	local nameLimit = Instance.new("UITextSizeConstraint")
	nameLimit.MinTextSize = 22
	nameLimit.MaxTextSize = 48
	nameLimit.Parent = nameCard
	local tags = Instance.new("Frame")
	tags.Name = "Tags"
	tags.BackgroundTransparency = 1
	tags.Position = UDim2.fromOffset(244, 154)
	tags.Size = UDim2.new(1, -268, 0, 26)
	tags.Parent = result
	local tagList = Instance.new("UIListLayout")
	tagList.FillDirection = Enum.FillDirection.Horizontal
	tagList.Padding = UDim.new(0, 8)
	tagList.SortOrder = Enum.SortOrder.LayoutOrder
	tagList.Parent = tags
	local description = GlassUI.label(result, "Description", "", 14, Theme.Fonts.Medium)
	description.Position = UDim2.fromOffset(244, 190)
	description.Size = UDim2.new(1, -268, 0, 60)
	description.TextColor3 = C.Muted
	description.TextYAlignment = Enum.TextYAlignment.Top
	local footnote = GlassUI.label(result, "Footnote", "", 13, Theme.Fonts.Bold)
	footnote.Position = UDim2.new(0, 24, 1, -36)
	footnote.Size = UDim2.new(1, -48, 0, 20)
	footnote.TextColor3 = C.Accent

	local hint = GlassUI.label(stage, "Hint", "Click anywhere to continue", 13, Theme.Fonts.Bold)
	hint.Position = UDim2.new(0, 0, 1, -26)
	hint.Size = UDim2.new(1, 0, 0, 20)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.TextColor3 = C.Muted
	hint.Visible = false
	hint.ZIndex = 4

	local sparkleLayer = Instance.new("Frame")
	sparkleLayer.Name = "Sparkles"
	sparkleLayer.Size = UDim2.fromScale(1, 1)
	sparkleLayer.BackgroundTransparency = 1
	sparkleLayer.ZIndex = 6
	sparkleLayer.Parent = stage

	local blur = Instance.new("BlurEffect")
	blur.Name = "RollRevealBlur"
	blur.Size = 0
	blur.Enabled = false

	-- Reel state ---------------------------------------------------------------------------
	local sequence = 0
	local phase = "Idle" -- Idle, Spinning, Landing, Result
	local position = 0 -- in cards; card index k sits under the marker when position == k
	local landFrom, landTo, landStart, landDuration = 0, 0, 0, LAND_SECONDS
	local pool: { any } = MachineDefinitions.getRollPool()
	local data: { [number]: CardData } = {}
	local random = Random.new()
	local lastTick = 0
	local pendingResult: any = nil
	local autoHide: thread? = nil
	local spinConnection: RBXScriptConnection? = nil
	local previewConnection: RBXScriptConnection? = nil

	local function cardFor(definition: any): CardData
		local rarity = EconomyRules.getMachineRarity(definition.Id, pool) or definition.Rarity or "Common"
		local variant = MachineVisualConfig.Variants[definition.Id]
		return {
			Id = definition.Id,
			Name = definition.DisplayName,
			Rarity = rarity,
			Odds = EconomyRules.getMachineOddsLabel(definition.Id, pool) or "",
			Glyph = (variant and variant.Symbol) or CATEGORY_GLYPHS[definition.Category] or "?",
		}
	end

	-- Weighted by the real roll chances, so the reel shows commons far more than legendaries.
	local function sample(index: number): CardData
		local existing = data[index]
		if existing then
			return existing
		end
		local total = 0
		for _, entry in ipairs(pool) do
			total += entry.RollChance or entry.RollWeight or 1
		end
		local pick = random:NextNumber() * total
		local chosen = pool[1]
		for _, entry in ipairs(pool) do
			pick -= entry.RollChance or entry.RollWeight or 1
			if pick <= 0 then
				chosen = entry
				break
			end
		end
		local card = cardFor(chosen)
		data[index] = card
		return card
	end

	local function paint(view: CardView, card: CardData)
		local color = rarityColor(card.Rarity)
		view.Glyph.Text = card.Glyph
		view.Glyph.TextColor3 = color
		view.Ring.BackgroundColor3 = color
		view.Name.Text = card.Name
		view.Odds.Text = card.Odds
		view.Bar.BackgroundColor3 = color
		view.Stroke.Color = color
		view.Stroke.Transparency = 0.45
		local gradient = view.Frame:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, C.CardTop:Lerp(color, 0.45)),
				ColorSequenceKeypoint.new(0.6, C.Card),
				ColorSequenceKeypoint.new(1, C.Card),
			})
		end
	end

	local function layoutReel()
		local base = math.floor(position) - math.floor(VISIBLE_CARDS / 2)
		for offset = 0, VISIBLE_CARDS - 1 do
			local index = base + offset
			local view = cards[(index % VISIBLE_CARDS) + 1]
			if view.Index ~= index then
				view.Index = index
				paint(view, sample(index))
			end
			view.Frame.Position = UDim2.new(0.5, (index - position) * PITCH, 0.5, 0)
		end
		local nearest = math.floor(position + 0.5)
		if nearest ~= lastTick then
			lastTick = nearest
			markerScale.Scale = 1.25
			TweenService:Create(markerScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end
	end

	local function stopSpinLoop()
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end
	end

	local function stopPreview()
		if previewConnection then
			previewConnection:Disconnect()
			previewConnection = nil
		end
		viewport:ClearAllChildren()
	end

	local function clearSparkles()
		sparkleLayer:ClearAllChildren()
	end

	local function attachBlur()
		local camera = workspace.CurrentCamera
		if camera and blur.Parent ~= camera then
			blur.Parent = camera
		end
	end

	local function hide(token: number)
		if token ~= sequence then
			return
		end
		phase = "Idle"
		stopSpinLoop()
		TweenService:Create(overlay, FADE, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(result, FADE, { GroupTransparency = 1 }):Play()
		TweenService:Create(reel, FADE, { GroupTransparency = 1 }):Play()
		TweenService:Create(viewport, FADE, { ImageTransparency = 1 }):Play()
		TweenService:Create(previewWell, FADE, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(previewGlyph, FADE, { TextTransparency = 1 }):Play()
		TweenService:Create(blur, FADE, { Size = 0 }):Play()
		skip.Visible = false
		task.delay(FADE.Time, function()
			if token == sequence then
				overlay.Visible = false
				blur.Enabled = false
				rays.Visible = false
				result.Visible = false
				previewWell.Visible = false
				skip.Visible = false
				hint.Visible = false
				stopPreview()
				clearSparkles()
			end
		end)
	end

	local function scheduleHide(token: number, seconds: number)
		if autoHide then
			task.cancel(autoHide)
		end
		autoHide = task.delay(seconds, function()
			autoHide = nil
			hide(token)
		end)
	end

	local function show()
		attachBlur()
		blur.Enabled = true
		overlay.Visible = true
		flash.BackgroundTransparency = 1
		TweenService:Create(overlay, FADE, { BackgroundTransparency = Theme.Transparency.Overlay }):Play()
		TweenService:Create(blur, FADE, { Size = Theme.RevealBlurSize }):Play()
	end

	local function sparkle(color: Color3, count: number)
		for _ = 1, count do
			local dot = Instance.new("Frame")
			dot.Name = "Sparkle"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.new(0.5, 0, 0, 240)
			local size = random:NextInteger(6, 14)
			dot.Size = UDim2.fromOffset(size, size)
			dot.Rotation = 45
			dot.BackgroundColor3 = if random:NextNumber() < 0.35 then C.Text else color
			dot.BorderSizePixel = 0
			dot.Parent = sparkleLayer
			local angle = random:NextNumber() * math.pi * 2
			local distance = random:NextNumber(180, 380)
			local duration = random:NextNumber(0.7, 1.2)
			TweenService:Create(dot, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, math.cos(angle) * distance, 0, 240 + math.sin(angle) * distance * 0.6),
				BackgroundTransparency = 1,
				Rotation = 45 + random:NextNumber(-180, 180),
			}):Play()
			task.delay(duration + 0.05, function()
				dot:Destroy()
			end)
		end
	end

	-- One RenderStepped connection for the result: turns the rays and orbits the preview.
	local function startPreview(definition: any?)
		stopPreview()
		previewGlyph.Visible = definition == nil
		if not definition then
			previewConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
				rays.Rotation = (rays.Rotation + deltaTime * 12) % 360
			end)
			return
		end
		local world = Instance.new("WorldModel")
		world.Parent = viewport
		local model = ModelBuilder.build(world, Vector3.zero, 1, definition)
		for _, child in ipairs(model:GetDescendants()) do
			if child:IsA("BasePart") and child.Transparency == 1 then
				child:Destroy()
			end
		end
		local box, size = model:GetBoundingBox()
		local camera = Instance.new("Camera")
		camera.FieldOfView = 32
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		local distance = math.max(size.X, size.Y, size.Z) * 2.4
		local angle = 0
		previewConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
			rays.Rotation = (rays.Rotation + deltaTime * 12) % 360
			angle += deltaTime * 0.8
			local offset = Vector3.new(math.cos(angle) * distance, distance * 0.55, math.sin(angle) * distance)
			camera.CFrame = CFrame.lookAt(box.Position + offset, box.Position)
		end)
	end

	-- Shows the result card. `info` carries display strings; `definition` enables the preview.
	local function showResult(token: number, info: { Name: string, Rarity: string, Odds: string, Definition: any?, Luck: number?, Ultra: boolean })
		if token ~= sequence then
			return
		end
		phase = "Result"
		stopSpinLoop()
		local color = rarityColor(info.Rarity)
		local tier = rarityTier[info.Rarity] or 1
		title.Text = if info.Ultra then "ULTRA RARE!" else string.upper(info.Rarity) .. "!"
		title.TextColor3 = color
		subtitle.Text = if info.Luck and info.Luck > 1 then string.format("Luck ×%.2f applied", info.Luck) else "Added to your machines"
		heading.Text = if info.Ultra then "ULTRA RARE MACHINE!" else string.upper(info.Rarity) .. " MACHINE!"
		heading.TextColor3 = color
		nameCard.Text = info.Name
		resultStroke.Color = color
		for _, child in ipairs(tags:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local rarityChip = GlassUI.chip(tags, "Rarity", info.Rarity, color, 13)
		rarityChip.LayoutOrder = 1
		rarityChip.Size = UDim2.fromOffset(0, 26)
		if info.Odds ~= "" then
			local oddsChip = GlassUI.chip(tags, "Odds", "Odds " .. info.Odds, C.Accent, 13)
			oddsChip.LayoutOrder = 2
			oddsChip.Size = UDim2.fromOffset(0, 26)
		end
		local definition = info.Definition
		if definition then
			local categoryChip = GlassUI.chip(tags, "Category", CATEGORY_NAMES[definition.Category] or definition.Category, C.Muted, 13)
			categoryChip.LayoutOrder = 3
			categoryChip.Size = UDim2.fromOffset(0, 26)
		end
		description.Text = if definition then definition.Description else ""
		footnote.Text = "Click a conveyor slot to place it"
		previewGlyph.Text = (definition and MachineVisualConfig.Variants[definition.Id] and MachineVisualConfig.Variants[definition.Id].Symbol) or "?"
		previewGlyph.TextColor3 = color
		startPreview(definition)

		TweenService:Create(reel, FADE, { GroupTransparency = 1 }):Play()
		marker.Visible = false
		result.Visible = true
		result.GroupTransparency = 1
		resultScale.Scale = 0.82
		TweenService:Create(result, FADE, { GroupTransparency = 0 }):Play()
		TweenService:Create(resultScale, POP, { Scale = 1 }):Play()
		previewWell.Visible = true
		previewGlyph.TextTransparency = 1
		viewport.ImageTransparency = 1
		TweenService:Create(previewWell, FADE, { BackgroundTransparency = 0.94 }):Play()
		TweenService:Create(viewport, FADE, { ImageTransparency = 0 }):Play()
		TweenService:Create(previewGlyph, FADE, { TextTransparency = 0 }):Play()
		hint.Visible = true
		skip.Visible = true

		rays.Visible = tier >= 3 or info.Ultra
		for _, ray in ipairs(rayBars) do
			ray.BackgroundColor3 = color
		end
		if tier >= 4 or info.Ultra then
			sparkle(color, if info.Ultra then 40 else 24)
		end
		if info.Ultra then
			flash.BackgroundColor3 = color
			flash.BackgroundTransparency = 0.15
			TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		end
		local hold = if info.Ultra then EconomyConfig.UltraRareCutscene.DurationSeconds elseif tier >= 3 then 3.4 else 2.4
		scheduleHide(token, hold)
	end

	local function landedResult(token: number)
		local resultInfo = pendingResult
		if token ~= sequence or not resultInfo then
			return
		end
		local landed = cards[(landTo % VISIBLE_CARDS) + 1]
		landed.Stroke.Thickness = 3
		landed.Stroke.Transparency = 0
		local pop = Instance.new("UIScale")
		pop.Scale = 1.15
		pop.Parent = landed.Frame
		TweenService:Create(pop, POP, { Scale = 1.06 }):Play()
		task.delay(0.55, function()
			pop:Destroy()
			landed.Stroke.Thickness = 1
			showResult(token, resultInfo)
		end)
	end

	local function runSpinLoop(token: number)
		stopSpinLoop()
		local last = os.clock()
		spinConnection = RunService.RenderStepped:Connect(function()
			if token ~= sequence then
				stopSpinLoop()
				return
			end
			local now = os.clock()
			local deltaTime = now - last
			last = now
			if phase == "Spinning" then
				position += SPIN_SPEED * deltaTime
			elseif phase == "Landing" then
				local t = math.clamp((now - landStart) / landDuration, 0, 1)
				local eased = 1 - (1 - t) ^ 3
				position = landFrom + (landTo - landFrom) * eased
				if t >= 1 then
					phase = "Landed"
					position = landTo
					layoutReel()
					landedResult(token)
					return
				end
			end
			layoutReel()
		end)
	end

	local function beginReel(luck: number?)
		pool = EconomyRules.getLuckAdjustedRollPool(MachineDefinitions.getRollPool(), luck or 1)
		data = {}
		position = 0
		lastTick = 0
		for _, view in ipairs(cards) do
			view.Index = -1
			view.Stroke.Thickness = 1
		end
		stopPreview()
		clearSparkles()
		rays.Visible = false
		result.Visible = false
		result.GroupTransparency = 1
		previewWell.Visible = false
		skip.Visible = false
		hint.Visible = false
		marker.Visible = true
		reel.GroupTransparency = 0
		title.Text = "ROLLING"
		title.TextColor3 = C.Text
		subtitle.Text = if luck and luck > 1 then string.format("Luck ×%.2f active", luck) else "Free roll"
		layoutReel()
	end

	-- Public API ---------------------------------------------------------------------------
	local api = {}

	function api.pending()
		sequence += 1
		if autoHide then
			task.cancel(autoHide)
			autoHide = nil
		end
		pendingResult = nil
		show()
		beginReel(nil)
		phase = "Spinning"
		runSpinLoop(sequence)
	end

	function api.rolled(machineId: string?, rarityOverride: string?, luck: number?)
		local token = sequence
		if phase ~= "Spinning" then
			sequence += 1
			token = sequence
			show()
			beginReel(luck)
			phase = "Spinning"
			runSpinLoop(token)
		end
		pool = EconomyRules.getLuckAdjustedRollPool(MachineDefinitions.getRollPool(), luck or 1)
		local definition = MachineDefinitions.get(machineId or "")
		local rarity = rarityOverride or (definition and EconomyRules.getMachineRarity(definition.Id, pool)) or "Common"
		local odds = if definition then EconomyRules.getMachineOddsLabel(definition.Id, pool) or "" else ""
		local denominator = if definition then EconomyRules.getMachineOddsDenominator(definition.Id, pool) else nil
		pendingResult = {
			Name = if definition then definition.DisplayName else "New machine",
			Rarity = rarity,
			Odds = odds,
			Definition = definition,
			Luck = luck,
			Ultra = EconomyRules.shouldPlayUltraRareCutscene(denominator),
		}
		-- Ease from the current speed onto a card ~SPIN_SPEED*LAND/3 cards ahead (cubic ease-out
		-- starts at exactly the spin speed), then paint the server result into that card.
		landFrom = position
		landTo = math.floor(position + SPIN_SPEED * LAND_SECONDS / 3) + 1
		landDuration = 3 * (landTo - landFrom) / SPIN_SPEED
		landStart = os.clock()
		if definition then
			local card = cardFor(definition)
			card.Rarity = rarity
			data[landTo] = card
			local view = cards[(landTo % VISIBLE_CARDS) + 1]
			if view.Index == landTo then
				paint(view, card)
			end
		end
		phase = "Landing"
		skip.Visible = true
	end

	-- Direct reveal without the reel (kept for the ultra-rare test event).
	function api.ultra(name: string, rarity: string, odds: string)
		sequence += 1
		local token = sequence
		show()
		beginReel(nil)
		showResult(token, { Name = name, Rarity = rarity, Odds = odds, Definition = nil, Ultra = true })
	end

	function api.cancel()
		sequence += 1
		local token = sequence
		phase = "Idle"
		hide(token)
	end

	skip.Activated:Connect(function()
		if phase == "Landing" then
			-- Skip ahead to the landing moment.
			landStart = os.clock() - landDuration
		elseif phase == "Result" then
			hide(sequence)
		end
	end)

	return api
end

return RollReveal
