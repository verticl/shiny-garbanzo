--!strict
--[[
	EconomyService.luau  (server)
	------------------------------------------------------------------
	The economy heartbeat. Every Economy.TICK_RATE seconds, for each player:
	  1. recompute per-resource storage capacity from their buildings
	     (base storage x silo/warehouse multiplier, + Manor flat floor),
	  2. run harvesters (farms/stables/quarries) -> add output up to capacity,
	  3. run producers (Butcher/Baker/Tailor) -> consume input, emit output,
	  4. award XP for what was actually produced,
	  5. push a live snapshot to the client.

	Production accrues a fraction of each per-minute rate every tick, so
	counters tick up smoothly instead of dumping in batches.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Buildings = require(ReplicatedStorage.Config.Buildings)
local Net = require(ReplicatedStorage.Shared.Net)
local PlacementService = require(script.Parent.PlacementService)
local PlayerData = require(script.Parent.PlayerData)
local PopulationService = require(script.Parent.PopulationService)

local ECON = GameConfig.Economy
local STORAGE = GameConfig.Storage

local EconomyService = {}

-- Horses can't be stored externally (no silos/warehouse/Manor help) per the design.
local NO_EXTERNAL_STORAGE: { [string]: boolean } = { horse = true }

-- Output ratio for a building. Worker-free buildings always run; worker
-- buildings scale by assigned/required (from PopulationService).
local function outputRatio(def: any, staffing: { [number]: number }, instanceId: number): number
	if def.peasants == 0 then
		return 1
	end
	if ECON.ASSUME_FULL_STAFFING then
		return 1
	end
	return staffing[instanceId] or 0
end

local function storageMultiplier(counts: { [string]: number }): number
	local silos = counts.Silo or 0
	local warehouses = counts.Warehouse or 0
	return 1 + silos * STORAGE.SILO_BONUS + warehouses * STORAGE.WAREHOUSE_BONUS
end

local function computeCapacity(buildings, counts): { [string]: number }
	local mult = storageMultiplier(counts)
	local hasManor = (counts.Manor or 0) > 0

	local capacity: { [string]: number } = {}
	for _, res in ipairs(GameConfig.RESOURCES) do
		if NO_EXTERNAL_STORAGE[res] then
			capacity[res] = 0
		else
			-- always-on base floor, plus the Manor's contribution when present
			capacity[res] = ECON.BASE_STORAGE_PER_RESOURCE + (hasManor and ECON.MANOR_STORAGE_PER_RESOURCE or 0)
		end
	end

	for _, rec in pairs(buildings) do
		local def = Buildings[rec.buildingId]
		if def and def.storage then
			local res = def.storage.resource
			if NO_EXTERNAL_STORAGE[res] then
				capacity[res] = (capacity[res] or 0) + def.storage.amount -- raw, no multiplier
			else
				capacity[res] = (capacity[res] or 0) + def.storage.amount * mult
			end
		end
	end
	return capacity
end

local function tickPlayer(player: Player, dtMinutes: number, dtSeconds: number)
	local data = PlayerData.get(player)
	if not data then
		return
	end

	local buildings = PlacementService.getBuildings(player)
	local counts = PlacementService.getCounts(player)

	PlayerData.setCapacity(player, computeCapacity(buildings, counts))

	-- Assign current population to jobs -> staffing ratios for this tick.
	local staffing = PopulationService.assign(player)

	-- 1) Harvesters: farms, stables, quarries (production with no input).
	for _, rec in pairs(buildings) do
		local def = Buildings[rec.buildingId]
		local prod = def and def.production
		if prod and prod.input == nil and def.category ~= "Military" then
			local amount = prod.ratePerMin * outputRatio(def, staffing, rec.instanceId) * dtMinutes
			local stored = PlayerData.addResource(player, prod.output, amount)
			PlayerData.addXp(player, stored * ECON.XP_PER_RESOURCE_UNIT)
		end
	end

	-- 2) Producers: consume an input resource to make a finished good.
	for _, rec in pairs(buildings) do
		local def = Buildings[rec.buildingId]
		local prod = def and def.production
		if prod and prod.input ~= nil then
			local room = (data.capacity[prod.output] or 0) - (data.stock[prod.output] or 0)
			if room > 0 then
				local desired = math.min(prod.ratePerMin * outputRatio(def, staffing, rec.instanceId) * dtMinutes, room)
				local inputNeeded = desired * ECON.PRODUCER_INPUT_PER_OUTPUT
				local gotInput = PlayerData.consumeResource(player, prod.input, inputNeeded)
				local madeOutput = gotInput / ECON.PRODUCER_INPUT_PER_OUTPUT
				local stored = PlayerData.addResource(player, prod.output, madeOutput)
				PlayerData.addXp(player, stored * ECON.XP_PER_RESOURCE_UNIT)
			end
		end
	end

	-- 3) Population eats, grows, or shrinks.
	PopulationService.upkeep(player, dtMinutes, dtSeconds)

	-- 4) Replicate.
	local snapshot = PlayerData.snapshot(player)
	if snapshot then
		Net.event("StatsUpdate"):FireClient(player, snapshot)
	end
end

function EconomyService.start()
	local function onAdded(player: Player)
		PlayerData.create(player)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		onAdded(player)
	end
	Players.PlayerAdded:Connect(onAdded)
	Players.PlayerRemoving:Connect(function(player)
		PlayerData.remove(player)
		PopulationService.remove(player)
	end)

	local dtSeconds = ECON.TICK_RATE
	local dtMinutes = ECON.TICK_RATE / 60
	task.spawn(function()
		while true do
			task.wait(ECON.TICK_RATE)
			for _, player in ipairs(Players:GetPlayers()) do
				tickPlayer(player, dtMinutes, dtSeconds)
			end
		end
	end)
end

return EconomyService
