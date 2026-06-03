--!strict
--[[
	AuraService.luau  (server)
	------------------------------------------------------------------
	Computes Aura (0–100) from how well the kingdom is run, then eases the
	current value toward that target so it drifts rather than snaps.

	Components (each scored 0..1, then weighted — see GameConfig.Aura.Weights):
	  foodVolume     - food stocked relative to population
	  foodDiversity  - how many of the four food types are present
	  clothing       - clothes stocked relative to population
	  timeInGame     - ruler presence this session ("they like to see you")
	  lowWaste       - reward for NOT leaving storages sitting full
	  security       - defense vs NPCs        (stubbed neutral until Phase 8)
	  relations      - standing with neighbors (stubbed neutral until Phase 8)

	Aura already drives population move-in speed (GameConfig.moveInInterval).
	Its military and cost multipliers exist (GameConfig.Aura) and take effect
	once those systems / building costs are defined.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local PlayerData = require(script.Parent.PlayerData)

local AURA = GameConfig.Aura
local FOOD_TYPES = GameConfig.FOOD_TYPES

local AuraService = {}
local sessionStart: { [Player]: number } = {}

type Data = {
	stock: { [string]: number },
	capacity: { [string]: number },
	population: number,
	aura: number,
}

function AuraService.remove(player: Player)
	sessionStart[player] = nil
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function computeTarget(player: Player, data: Data): number
	local pop = math.max(data.population, 1)

	-- food volume + diversity
	local food = 0
	local presentTypes = 0
	for _, ft in ipairs(FOOD_TYPES) do
		local s = data.stock[ft] or 0
		food += s
		if s > 0 then
			presentTypes += 1
		end
	end
	local foodVolume = clamp01(food / (pop * AURA.FOOD_COMFORT_PER_PEASANT + 1))
	local foodDiversity = presentTypes / #FOOD_TYPES

	-- clothing
	local clothing = clamp01((data.stock.clothes or 0) / (pop * AURA.CLOTH_COMFORT_PER_PEASANT + 1))

	-- time in game this session
	local started = sessionStart[player] or os.clock()
	local timeScore = clamp01(((os.clock() - started) / 60) / AURA.TIME_FULL_MINUTES)

	-- wastefulness: penalise resources sitting at/near full capacity
	local full, counted = 0, 0
	for res, cap in pairs(data.capacity) do
		if cap > 0 then
			counted += 1
			if (data.stock[res] or 0) >= cap * 0.95 then
				full += 1
			end
		end
	end
	local lowWaste = counted > 0 and (1 - full / counted) or 1

	local w = AURA.Weights
	local sum = w.foodVolume * foodVolume
		+ w.foodDiversity * foodDiversity
		+ w.clothing * clothing
		+ w.timeInGame * timeScore
		+ w.lowWaste * lowWaste
		+ w.security * AURA.STUB_SECURITY
		+ w.relations * AURA.STUB_RELATIONS

	return 100 * sum
end

function AuraService.update(player: Player, dtSeconds: number)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	if not sessionStart[player] then
		sessionStart[player] = os.clock()
	end

	local target = computeTarget(player, data)
	local maxStep = AURA.ADJUST_PER_SEC * dtSeconds
	local diff = target - data.aura
	data.aura = math.clamp(data.aura + math.clamp(diff, -maxStep, maxStep), 0, 100)
end

return AuraService
