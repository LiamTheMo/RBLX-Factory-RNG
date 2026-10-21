--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SaveSchema = require(Shared:WaitForChild("SaveSchema"))
local FactoryService = require(script.Parent.FactoryService)
local EconomyService = require(script.Parent.EconomyService)
local AnalyticsService = require(script.Parent.AnalyticsService)
local EffectService = require(script.Parent.EffectService)
local PersistenceSession = require(script.Parent.PersistenceSession)

local DataService = {}
local store: any = nil
local sessionIds: { [Player]: string } = {}
local loadedPlayers: { [Player]: boolean } = {}
local started = false
local autosaveAccumulator = 0
local savingPlayers: { [Player]: boolean } = {}
local sessionStartedAt: { [Player]: number } = {}

local SESSION_LOCK_SECONDS = 300
-- Layout or capacity edits are saved shortly after they happen, not only on the autosave.
-- Kept above the data store's one-write-per-key-per-6s limit.
local CHANGE_SAVE_DELAY_SECONDS = 8
-- A previous server may still hold the session lock briefly after the player left it.
local LOCK_RETRY_SECONDS = 5
local LOCK_RETRY_ATTEMPTS = 12
local pendingChangeSave: { [Player]: boolean } = {}
local watchFactoryChanges: (Player) -> ()

-- Unique per join: a quick rejoin to the same server must not share the previous
-- session's lock while that session's release save is still in flight.
local function sessionIdFor(player: Player): string
	return `{game.JobId}:{player.UserId}:{HttpService:GenerateGUID(false)}`
end

local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

local function setLoadStatus(player: Player, loaded: boolean, locked: boolean, reason: string?, allowUnsavedPrototype: boolean?)
	player:SetAttribute("FactoryDataLoaded", loaded)
	player:SetAttribute("FactoryDataLocked", locked)
	player:SetAttribute("FactoryDataReady", loaded or allowUnsavedPrototype == true)
	if reason then
		player:SetAttribute("FactoryDataError", reason)
	else
		player:SetAttribute("FactoryDataError", nil)
	end
	EffectService.fire(player, "InventoryChanged")
end

local function loadPlayer(player: Player)
	while player.Parent == Players and not FactoryService.getState(player) do
		task.wait()
	end
	if player.Parent ~= Players then
		return
	end
	if not store then
		-- Only a local, unpublished Rojo build may play without cloud saving.
		-- A published place with an unavailable store must not accept changes.
		if game.PlaceId == 0 then
			setLoadStatus(player, false, false, "Saving requires a published place", true)
		else
			setLoadStatus(player, false, false, "Data store unavailable")
		end
		return
	end
	if sessionIds[player] then
		return
	end
	local sessionId = sessionIdFor(player)
	sessionIds[player] = sessionId
	setLoadStatus(player, false, false, nil)

	local success, loadedData, errorKind
	for attempt = 1, LOCK_RETRY_ATTEMPTS do
		success, loadedData, errorKind = PersistenceSession.acquire(store, keyFor(player), sessionId, os.time(), SESSION_LOCK_SECONDS, SaveSchema.sanitizeForStorage)
		if success or errorKind ~= "locked" or attempt == LOCK_RETRY_ATTEMPTS then
			break
		end
		setLoadStatus(player, false, true, "Waiting for your last server to finish saving")
		task.wait(LOCK_RETRY_SECONDS)
		if player.Parent ~= Players then
			sessionIds[player] = nil
			return
		end
	end

	if not success then
		sessionIds[player] = nil
		setLoadStatus(player, false, errorKind == "locked", if errorKind == "locked" then "Active session already owns this data" else "Data store unavailable")
		if errorKind ~= "locked" then
			AnalyticsService.record(player, "DataLoadFailure")
			warn(`Tiny Factory data load failed for {player.UserId}`)
		end
		return
	end

	local safeData = SaveSchema.sanitize(loadedData)
	local factoryApplied, factoryError = FactoryService.applyPersistentState(player, safeData)
	local economyApplied, economyError = EconomyService.applyPersistentState(player, safeData)
	if not factoryApplied or not economyApplied then
		sessionIds[player] = nil
		setLoadStatus(player, false, false, factoryError or economyError or "Invalid saved data")
		AnalyticsService.record(player, "DataLoadFailure")
		warn(`Tiny Factory data apply failed for {player.UserId}: {factoryError or economyError}`)
		return
	end
	AnalyticsService.restore(player, safeData.Analytics)
	local previousSessions = (AnalyticsService.snapshot(player).SessionStarted or 0)
	AnalyticsService.record(player, "SessionStarted")
	if previousSessions > 0 then AnalyticsService.record(player, "ReturnSession") end
	AnalyticsService.record(player, "FactoryActive")
	sessionStartedAt[player] = os.time()
	loadedPlayers[player] = true
	setLoadStatus(player, true, false, nil)
	watchFactoryChanges(player)
end

local function buildSnapshot(player: Player): { [string]: any }?
	local factoryData = FactoryService.getPersistentState(player)
	local economyData = EconomyService.getPersistentState(player)
	if not factoryData or not economyData then
		return nil
	end
	return SaveSchema.sanitize(SaveSchema.liveSnapshot({
		Coins = factoryData.Coins,
		Layout = factoryData.Layout,
		Inventory = factoryData.Inventory,
		BoosterInventory = factoryData.BoosterInventory,
		Capacity = factoryData.Capacity,
		RollCount = economyData.RollCount,
		Statistics = factoryData.Statistics,
		Analytics = AnalyticsService.snapshot(player),
	}))
end

local function saveOnce(player: Player, releaseLock: boolean?)
	-- Snapshot before any yield: on leave, other services tear down per-player state on
	-- the same PlayerRemoving signal, and a missing piece used to skip the final save.
	local safeData = buildSnapshot(player)
	while savingPlayers[player] do task.wait() end
	local sessionId = sessionIds[player]
	if not sessionId or not loadedPlayers[player] or not safeData then
		return
	end
	savingPlayers[player] = true
	local success, errorKind = PersistenceSession.save(store, keyFor(player), sessionId, SaveSchema.toStorage(safeData), releaseLock == true, os.time())
	savingPlayers[player] = nil
	if not success then
		player:SetAttribute("FactoryDataSaveError", if errorKind == "conflict" then "Session ownership changed" else "Data store unavailable")
		if player.Parent == Players then
			-- Recording for a departed player would recreate its analytics entry and leak it.
			AnalyticsService.record(player, "DataSaveFailure")
		end
		warn(`Tiny Factory data save failed for {player.UserId}: {errorKind}`)
		return
	end
	player:SetAttribute("FactoryDataSaved", true)
	player:SetAttribute("FactoryDataSaveError", nil)
	if releaseLock then
		loadedPlayers[player] = nil
		sessionIds[player] = nil
		sessionStartedAt[player] = nil
	end
end

-- Release saves (leave and shutdown) are counted so BindToClose can wait for them.
local releasingSaves = 0
local function savePlayer(player: Player, releaseLock: boolean?)
	if not releaseLock then
		saveOnce(player, false)
		return
	end
	releasingSaves += 1
	local ok, failure = pcall(saveOnce, player, true)
	releasingSaves -= 1
	if not ok then
		warn(`Tiny Factory release save errored for {player.UserId}: {failure}`)
	end
end

watchFactoryChanges = function(player: Player)
	for _, attribute in ipairs({ "FactoryLayout", "FactoryCapacity" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if pendingChangeSave[player] or not loadedPlayers[player] then
				return
			end
			pendingChangeSave[player] = true
			task.delay(CHANGE_SAVE_DELAY_SECONDS, function()
				pendingChangeSave[player] = nil
				if player.Parent == Players then
					savePlayer(player, false)
				end
			end)
		end)
	end
end

function DataService.start()
	if started then
		return
	end
	started = true
	local opened, result = pcall(function()
		return DataStoreService:GetDataStore("TinyFactory_PlayerData_v1")
	end)
	if opened then
		store = result
	else
		warn(`Tiny Factory saving is unavailable in this place: {result}`)
	end
	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local began = sessionStartedAt[player]
		if began then AnalyticsService.record(player, "SessionSeconds", math.max(0, os.time() - began)) end
		savePlayer(player, true)
		loadedPlayers[player] = nil
		sessionIds[player] = nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(savePlayer, player, true)
		end
		-- Also wait for leave saves already in flight: the last player leaving often
		-- triggers the shutdown after their save has started.
		local deadline = os.clock() + 25
		while releasingSaves > 0 and os.clock() < deadline do
			task.wait(0.25)
		end
	end)
	RunService.Heartbeat:Connect(function(deltaTime)
		autosaveAccumulator += deltaTime
		if autosaveAccumulator < 60 then
			return
		end
		autosaveAccumulator = 0
		for player in pairs(loadedPlayers) do
			task.spawn(savePlayer, player, false)
		end
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
end

return DataService
