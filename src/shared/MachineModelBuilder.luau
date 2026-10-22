--!strict

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Visuals = require(Shared.MachineVisualConfig)
local Geometry = require(Shared.FactoryItemGeometry)
local CubeTypeDefinitions = require(Shared.CubeTypeDefinitions)
local Theme = require(Shared.HudTheme)
local MachineEffects = require(Shared.MachineEffects)
local MachineModifiers = require(Shared.MachineModifiers)
local Builder = {}

local function rgb(channels: { number }): Color3
	return Color3.fromRGB(channels[1], channels[2], channels[3])
end

-- Floating glass pill (sized in studs so it shrinks with distance; hidden past MaxDistance
-- to keep other plots tidy).
local function addPill(housing: Part, name: string, text: string, color: Color3, width: number, height: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = name
	billboard.Adornee = housing
	billboard.Size = UDim2.fromScale(width, 0.62)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	billboard.MaxDistance = 60
	billboard.LightInfluence = 0
	billboard.Parent = housing
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Theme.Colors.Glass
	pill.BackgroundTransparency = Theme.Transparency.Glass
	pill.BorderSizePixel = 0
	pill.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = color
	rim.Thickness = 2
	rim.Transparency = 0.2
	rim.Parent = pill
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.82, 0.72)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.FontFace = Theme.Fonts.Heavy
	label.TextScaled = true
	label.Parent = pill
end

-- Above the machine: its job ("DROPPER", "UPGRADER", "SELLER") and, higher up, any rolled
-- modifiers ("GOLDEN · QUANTUM") in the rarest modifier's color.
local function addRoleLabel(model: Model, housing: Part, definition: any)
	local role = MachineEffects.role(definition)
	if not role then
		return
	end
	local top = housing.Position.Y + housing.Size.Y / 2
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child.Transparency < 1 then
			top = math.max(top, child.Position.Y + child.Size.Y / 2)
		end
	end
	local height = top - housing.Position.Y + 0.65
	addPill(housing, "RoleLabel", string.upper(role.Name), rgb(role.Color), 2.6, height)
	local names, rarest: any = {}, nil
	for _, modifierId in ipairs(definition.Modifiers or {}) do
		local modifier = MachineModifiers.get(modifierId)
		if modifier then
			table.insert(names, string.upper(modifier.DisplayName))
			if not rarest or modifier.ChanceDenominator > rarest.ChanceDenominator then
				rarest = modifier
			end
		end
	end
	if rarest then
		local text = table.concat(names, " · ")
		addPill(housing, "ModifierLabel", text, rgb(rarest.Color), math.max(2.6, #text * 0.17), height + 0.75)
	end
end

function Builder.build(parent: Instance, origin: Vector3, slot: number, definition: any): (Model, Part, Part?)
	local profileKey = definition.VisualStyle or (if definition.Category == "Producer" then "Dropper" else definition.Category)
	local profile = Visuals.Profiles[profileKey] or Visuals.Profiles.Processor
	local variant = Visuals.Variants[definition.BaseId or definition.Id] or {}
	local themedType = CubeTypeDefinitions.get(definition.CubeType or definition.TypeFilter or "")
	local themedColor = themedType and themedType.Color or nil
	local primaryColor = variant.PrimaryColor or (themedColor or profile.PrimaryColor)
	local primary = rgb(primaryColor)
	local accent = rgb(variant.AccentColor or profile.AccentColor)
	local base = origin + Vector3.new((slot - 1) * Visuals.SlotPitch, Geometry.machineLift(), 0)
	local model = Instance.new("Model")
	model.Name = string.format("Slot_%d_%s", slot, definition.Id)
	model:SetAttribute("MachineId", definition.Id)
	model:SetAttribute("VisualVariant", definition.Id)
	model.Parent = parent
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		local result = Instance.new("Part")
		result.Name = name
		result.Anchored = true
		result.CanCollide = false
		result.Material = Enum.Material.SmoothPlastic
		result.Size = size
		result.Position = base + offset
		result.Color = color
		result.TopSurface = Enum.SurfaceType.Smooth
		result.BottomSurface = Enum.SurfaceType.Smooth
		result.Parent = model
		return result
	end
	local housing: Part
	local hitbox: Part? = nil
	if profile.Style == "Dropper" then
		local width = variant.WidthScale or 1
		part("DropperFoot", Vector3.new(2.8, 0.3, 2.4), Vector3.new(0, 0.32, 0), accent)
		for _, side in ipairs({ -1, 1 }) do
			part("DropperSupport", Vector3.new(0.3, 2.2, 0.3), Vector3.new(0, 1.4, side * 0.86), accent)
			part("DropperHead", Vector3.new(0.62 * width, 1.2, 1.8), Vector3.new(side * 0.78 * width, 2.55, 0), primary)
			part("DropperNozzle", Vector3.new(0.18, 0.5, 0.18), Vector3.new(side * 0.48, 1.65, 0), accent)
		end
		for _, side in ipairs({ -1, 1 }) do
			part("DropperNozzleSide", Vector3.new(0.18, 0.5, 0.18), Vector3.new(0, 1.65, side * 0.48), accent)
		end
		housing = part("DropperHousing", Vector3.new(2.2 * width, 0.35, 2.0), Vector3.new(0, 3.25, 0), primary)
	elseif profile.Style == "Seller" then
		part("SellerFoot", Vector3.new(2.8, 0.3, 2.4), Vector3.new(0, 0.32, 0), primary)
		part("SellerTray", Vector3.new(2.4, 0.2, 2.1), Vector3.new(0, 0.36, 0), accent)
		for _, side in ipairs({ -1, 1 }) do
			part("SellerDoorPillar", Vector3.new(0.35, 2.2, 0.4), Vector3.new(0, 1.55, side * 1.25), primary)
		end
		housing = part("SellerHousing", Vector3.new(1.5, 0.35, 2.9), Vector3.new(0, 2.75, 0), primary)
		local box = Visuals.SellerHitbox
		hitbox = part("SellerHitbox", Vector3.new(table.unpack(box.Size)), Vector3.new(table.unpack(box.Offset)), primary)
		hitbox.Transparency = 1
		hitbox.CanTouch = false
		hitbox.CanQuery = false
		hitbox.CastShadow = false
	else
		part("ProcessorFoot", Vector3.new(2.8, 0.3, 2.4), Vector3.new(0, 0.32, 0), accent)
		housing = part("ProcessorHousing", Vector3.new(2.1, 1.5, 1.9), Vector3.new(0, 1.25, 0), primary)
	end
	for _, detail in ipairs(variant.Parts or {}) do
		local extra = part(detail.Name, Vector3.new(table.unpack(detail.Size)), Vector3.new(table.unpack(detail.Offset)), accent)
		if detail.Shape == "Ball" then extra.Shape = Enum.PartType.Ball end
		if detail.Shape == "Cylinder" then extra.Shape = Enum.PartType.Cylinder end
		local rotation = detail.Rotation
		if rotation then extra.CFrame *= CFrame.Angles(math.rad(rotation[1]), math.rad(rotation[2]), math.rad(rotation[3])) end
	end
	local badgeY = if profile.Style == "Dropper" then 2.7 elseif profile.Style == "Seller" then 2.65 else 1.25
	local badgeZ = if profile.Style == "Seller" then -1.5 else -1.1
	-- Identity plate: the machine symbol plus its effect tag (e.g. "1.35× Ice").
	local identityPlate = part("IdentityPlate", Vector3.new(1.7, 0.7, 0.12), Vector3.new(0, badgeY, badgeZ), primary)
	local effect = MachineEffects.tag(definition)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local badge = Instance.new("SurfaceGui")
		badge.Name = "MachineBadge"
		badge.Face = face
		badge.CanvasSize = Vector2.new(340, 140)
		badge.Parent = identityPlate
		local icon = Instance.new("TextLabel")
		icon.Name = "Symbol"
		icon.Size = UDim2.new(0, 96, 1, 0)
		icon.BackgroundTransparency = 1
		icon.Text = variant.Symbol or "•"
		icon.TextColor3 = accent
		icon.TextStrokeColor3 = Color3.fromRGB(35, 38, 42)
		icon.TextStrokeTransparency = 0.25
		icon.FontFace = Theme.Fonts.Heavy
		icon.TextSize = 64
		icon.Parent = badge
		local tag = Instance.new("TextLabel")
		tag.Name = "Effect"
		tag.Position = UDim2.fromOffset(96, 16)
		tag.Size = UDim2.new(1, -108, 1, -32)
		tag.BackgroundTransparency = 1
		tag.Text = effect
		tag.TextColor3 = Color3.new(1, 1, 1)
		tag.TextStrokeColor3 = Color3.fromRGB(35, 38, 42)
		tag.TextStrokeTransparency = 0.25
		tag.FontFace = Theme.Fonts.Heavy
		tag.TextScaled = true
		tag.TextXAlignment = Enum.TextXAlignment.Left
		tag.Parent = badge
	end
	addRoleLabel(model, housing, definition)
	return model, housing, hitbox
end

return Builder
