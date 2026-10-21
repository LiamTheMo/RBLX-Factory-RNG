--!strict

-- Drifts the lagoon textures so the water shimmers like the island concept art: the layers of the
-- textured water surface (each with its own DriftU/DriftV attributes, so they cross) or, with the
-- Terrain water fallback, the seabed caustics. Presentation only. One RenderStepped connection
-- moves every layer each frame, so the drift is smooth (a slower tick reads as choppy steps).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IslandWorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IslandWorldConfig"))

local CausticsController = {}
local started = false

local DEFAULT_DRIFT = Vector2.new(1.1, 0.7)

type Layer = { Texture: Texture, Drift: Vector2, Offset: Vector2 }

function CausticsController.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local world = workspace:WaitForChild(IslandWorldConfig.MapKey, 60)
		if not world then
			return
		end
		local folder = world:WaitForChild("WaterSurface", 15) or world:FindFirstChild("Caustics")
		if not folder then
			return
		end
		local layers: { Layer } = {}
		for _, descendant in folder:GetDescendants() do
			if descendant:IsA("Texture") then
				local u, v = descendant:GetAttribute("DriftU"), descendant:GetAttribute("DriftV")
				local drift = if typeof(u) == "number" and typeof(v) == "number" then Vector2.new(u, v) else DEFAULT_DRIFT
				table.insert(layers, { Texture = descendant, Drift = drift, Offset = Vector2.zero })
			end
		end
		if #layers == 0 then
			return
		end
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function(dt: number)
			if not folder.Parent then
				connection:Disconnect()
				return
			end
			for _, layer in layers do
				local texture = layer.Texture
				local offset = layer.Offset + layer.Drift * dt
				layer.Offset = Vector2.new(offset.X % texture.StudsPerTileU, offset.Y % texture.StudsPerTileV)
				texture.OffsetStudsU = layer.Offset.X
				texture.OffsetStudsV = layer.Offset.Y
			end
		end)
	end)
end

return CausticsController
