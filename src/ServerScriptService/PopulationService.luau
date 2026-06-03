--!strict
--[[
	PopulationService.luau  (server)
	------------------------------------------------------------------
	The living population. Two phases per economy tick:

	  assign(player)  -> distributes the current population across worker
	                     buildings by JOB_PRIORITY (farms first, military
	                     last). Returns a staffing ratio per building that
	                     the EconomyService uses to scale output.

	  upkeep(player)  -> peasants eat food + wear clothing; the kingdom
	                     gains residents when there's a free home and food
	                     to spare (speed set by Aura), and loses them when
	                     food runs out or housing is destroyed.

	Because jobs are re-assigned from the population COUNT every tick,
	shrinking the population automatically de-staffs the lowest-priority
	jobs first — i.e. "soldiers leave first, farmers last" emerges for free.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Buildings = require(ReplicatedStorage.Config.Buildings)
local PlacementService = require(script.Parent.PlacementService)
local PlayerData = require(script.Parent.PlayerData)

local POP = GameConfig.Population
local PEASANT = GameConfig.Peasant
local ECON = GameConfig.Economy

local PopulationService = {}

type PerPlayer = {
	moveInAccum: number, -- seconds banked toward the next move-in
	starveAccum: number, -- seconds banked toward the next starvation loss
	overCapacitySince: number?, -- timestamp housing first went over capacity
}

local state: { [Player]: PerPlayer } = {}

local function getState(player: Player): PerPlayer
	local s = state[player]
	if not s then
		local fresh: PerPlayer = { moveInAccum = 0, starveAccum = 0, overCapacitySince = nil }
		s = fresh
		state[player] = s
	end
	return s
end

function PopulationService.remove(player: Player)
	state[player] = nil
end

local function housingCapacity(counts: { [string]: number }): number
	local fromHouses = (counts.House or 0) * GameConfig.HOUSE_DEFAULT_CAPACITY
	local fromManor = ((counts.Manor or 0) > 0) and POP.MANOR_HOUSING or 0
	return fromHouses + fromManor
end

-- ── job assignment ───────────────────────────────────────────────
-- Returns staffing ratios keyed by building instanceId (only for buildings
-- that require workers). Also records job/employment totals on PlayerData.
function PopulationService.assign(player: Player): { [number]: number }
	local data = PlayerData.get(player)
	local staffing: { [number]: number } = {}
	if not data then
		return staffing
	end

	local buildings = PlacementService.getBuildings(player)
	local available = data.population
	local jobSlots = 0

	for _, category in ipairs(PEASANT.JOB_PRIORITY) do
		for _, rec in pairs(buildings) do
			local def = Buildings[rec.buildingId]
			if def and def.category == category and def.peasants > 0 then
				jobSlots += def.peasants
				local assigned = math.min(available, def.peasants)
				staffing[rec.instanceId] = assigned / def.peasants
				available -= assigned
				PlacementService.setAssigned(player, rec.instanceId, assigned, def.peasants)
			end
		end
	end

	data.jobSlots = jobSlots
	data.employed = data.population - available
	data.idle = available
	data.housingCapacity = housingCapacity(PlacementService.getCounts(player))
	return staffing
end

-- ── upkeep: consume, then grow or shrink ─────────────────────────
local function totalFood(data): number
	local sum = 0
	for _, ft in ipairs(GameConfig.FOOD_TYPES) do
		sum += data.stock[ft] or 0
	end
	return sum
end

local function deductFood(data, amount: number)
	local total = totalFood(data)
	if total <= 0 or amount <= 0 then
		return
	end
	for _, ft in ipairs(GameConfig.FOOD_TYPES) do
		local have = data.stock[ft] or 0
		data.stock[ft] = math.max(0, have - amount * (have / total))
	end
end

function PopulationService.upkeep(player: Player, dtMinutes: number, dtSeconds: number)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	local s = getState(player)
	local now = os.clock()

	-- 1) Consume food.
	local foodNeed = data.population * PEASANT.FOOD_PER_MIN * dtMinutes
	local foodAvail = totalFood(data)
	local consumed = math.min(foodNeed, foodAvail)
	deductFood(data, consumed)
	local starving = foodNeed - consumed > 1e-6

	-- 2) Consume clothing (soft need; shortage will feed into Aura in Phase 6).
	PlayerData.consumeResource(player, "clothes", data.population * PEASANT.CLOTHING_PER_MIN * dtMinutes)

	-- 3) Housing over-capacity (e.g. a House was destroyed) -> grace, then trim.
	local cap = housingCapacity(PlacementService.getCounts(player))
	if data.population > cap then
		local since = s.overCapacitySince or now
		s.overCapacitySince = since
		if now - since >= GameConfig.DESTROY_GRACE_PERIOD then
			data.population = cap
		end
	else
		s.overCapacitySince = nil
	end

	-- 4) Starvation -> lose peasants over time (lowest-priority jobs de-staff first).
	if starving and data.population > 0 then
		s.starveAccum += dtSeconds
		while s.starveAccum >= POP.STARVE_SECONDS_PER_LOSS and data.population > 0 do
			data.population -= 1
			s.starveAccum -= POP.STARVE_SECONDS_PER_LOSS
		end
	else
		s.starveAccum = 0
	end

	-- 5) Move-in: needs a free home + food to spare + not starving; speed from Aura.
	local foodAfter = totalFood(data)
	if not starving and foodAfter > 0 and data.population < cap then
		local interval = GameConfig.moveInInterval(data.aura)
		if interval then
			s.moveInAccum += dtSeconds
			while s.moveInAccum >= interval and data.population < cap do
				data.population += 1
				PlayerData.addXp(player, ECON.XP_PER_PEASANT_ADDED)
				s.moveInAccum -= interval
			end
		end
	else
		s.moveInAccum = 0
	end
end

return PopulationService
