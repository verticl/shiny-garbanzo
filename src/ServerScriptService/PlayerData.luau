--!strict
--[[
	PlayerData.luau  (server)
	------------------------------------------------------------------
	Authoritative per-player economy state: resource stock, gold, xp,
	population, and the current per-resource storage capacity.

	Resource model (Phase 3 simplification):
	  Stock is tracked as ONE aggregate number per resource per player
	  (what the HUD shows as supply/capacity). Capacity is the sum of every
	  placed building's storage of that resource (x silo/warehouse multiplier)
	  plus the Manor's flat floor. This gives the lively, single-counter feel
	  the design wants. The doc's per-building "first-come-first-served" filling
	  and "destroying a building loses its internal contents" are deliberately
	  not simulated yet — noted as a later refinement if we need that fidelity.

	No knowledge of PlacementService here (avoids a require cycle) — the
	EconomyService computes capacity from building records and pushes it in
	via setCapacity().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Config.GameConfig)

export type Data = {
	stock: { [string]: number },
	capacity: { [string]: number },
	gold: number,
	xp: number,
	population: number,
	aura: number,
	-- derived each tick by PopulationService (for HUD/economy):
	housingCapacity: number,
	jobSlots: number,
	employed: number,
	idle: number,
}

local PlayerData = {}
local store: { [Player]: Data } = {}

local function blankResourceTable(): { [string]: number }
	local t = {}
	for _, res in ipairs(GameConfig.RESOURCES) do
		t[res] = 0
	end
	return t
end

function PlayerData.create(player: Player): Data
	local stock = blankResourceTable()
	for resource, amount in pairs(GameConfig.Economy.STARTING_STOCK) do
		stock[resource] = amount
	end
	local data: Data = {
		stock = stock,
		capacity = blankResourceTable(),
		gold = GameConfig.Economy.STARTING_GOLD,
		xp = 0,
		population = GameConfig.Population.STARTING,
		aura = GameConfig.Aura.STARTING,
		housingCapacity = 0,
		jobSlots = 0,
		employed = 0,
		idle = 0,
	}
	store[player] = data
	return data
end

function PlayerData.get(player: Player): Data?
	return store[player]
end

function PlayerData.remove(player: Player)
	store[player] = nil
end

function PlayerData.setCapacity(player: Player, capacity: { [string]: number })
	local data = store[player]
	if data then
		data.capacity = capacity
		-- Clamp any stock that now exceeds reduced capacity (e.g. storage removed).
		for res, amount in pairs(data.stock) do
			local cap = capacity[res] or 0
			if amount > cap then
				data.stock[res] = cap
			end
		end
	end
end

-- Adds up to the remaining capacity; returns how much was actually stored.
function PlayerData.addResource(player: Player, resource: string, amount: number): number
	local data = store[player]
	if not data or amount <= 0 then
		return 0
	end
	local current = data.stock[resource] or 0
	local cap = data.capacity[resource] or 0
	local room = math.max(0, cap - current)
	local stored = math.min(amount, room)
	data.stock[resource] = current + stored
	return stored
end

-- Removes up to `amount`; returns how much was actually consumed.
function PlayerData.consumeResource(player: Player, resource: string, amount: number): number
	local data = store[player]
	if not data or amount <= 0 then
		return 0
	end
	local current = data.stock[resource] or 0
	local taken = math.min(amount, current)
	data.stock[resource] = current - taken
	return taken
end

function PlayerData.addGold(player: Player, n: number)
	local data = store[player]
	if data then
		data.gold += n
	end
end

function PlayerData.spendGold(player: Player, n: number): boolean
	local data = store[player]
	if data and data.gold >= n then
		data.gold -= n
		return true
	end
	return false
end

function PlayerData.addXp(player: Player, n: number)
	local data = store[player]
	if data and n > 0 then
		data.xp += n
	end
end

-- Compact snapshot for replication (rounded for display).
function PlayerData.snapshot(player: Player): Data?
	local data = store[player]
	if not data then
		return nil
	end
	local stock = {}
	for res, amount in pairs(data.stock) do
		stock[res] = math.floor(amount)
	end
	return {
		stock = stock,
		capacity = data.capacity,
		gold = math.floor(data.gold),
		xp = math.floor(data.xp),
		population = data.population,
		aura = math.floor(data.aura),
		housingCapacity = data.housingCapacity,
		jobSlots = data.jobSlots,
		employed = data.employed,
		idle = data.idle,
	}
end

return PlayerData
