--!strict

-- Swells the lagoon surf like lapping waves: every surf part (tagged by the server's island builder)
-- grows outward by about Foam.SwellStuds and back on an endless engine tween, each with its own
-- period and start, so the shoreline breathes without ever moving in sync. The rim foam stays
-- hugging the rock. Presentation only; bounded to Foam.MaxAnimated parts and uses no per-frame
-- script work.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local IslandWorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IslandWorldConfig"))

local SurfController = {}
local started = false

function SurfController.start()
	if started then
		return
	end
	started = true
	local foam = IslandWorldConfig.Foam
	local animated = 0
	local random = Random.new()
	local function swell(instance: Instance)
		if animated >= foam.MaxAnimated or not instance:IsA("BasePart") then
			return
		end
		animated += 1
		local base = instance.Size
		local grow = foam.SwellStuds * 2
		local seconds = random:NextNumber(foam.SwellSeconds[1], foam.SwellSeconds[2])
		local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, random:NextNumber(0, seconds))
		TweenService:Create(instance, info, { Size = Vector3.new(base.X + grow, base.Y, base.Z + grow) }):Play()
	end
	for _, instance in CollectionService:GetTagged(foam.SurfTag) do
		swell(instance)
	end
	CollectionService:GetInstanceAddedSignal(foam.SurfTag):Connect(swell)
end

return SurfController
