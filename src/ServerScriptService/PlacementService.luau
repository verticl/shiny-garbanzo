--!strict
--[[
	PlacementService.luau  (server, authoritative)
	------------------------------------------------------------------
	Owns the build grid. Every place/move/delete is validated here; the
	client can only ask. State is per-player (each child builds their own
	kingdom). For this phase all plots share world origin — multiplayer
	plot offsets come with map generation (Phase 7).

	Placed buildings live in Workspace/Placed and carry attributes:
	  InstanceId (number), BuildingId (string), Owner (userId)
	so the client can map a clicked model back to a record.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Buildings = require(ReplicatedStorage.Config.Buildings)
local GridUtil = require(ReplicatedStorage.Shared.GridUtil)
local BuildingVisual = require(ReplicatedStorage.Shared.BuildingVisual)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)

type Tile = GridUtil.Tile

type Record = {
	instanceId: number,
	buildingId: string,
	anchor: Tile,
	rotation: number,
}

type PlayerState = {
	occupied: { [string]: number }, -- tileKey -> instanceId
	buildings: { [number]: Record },
	counts: { [string]: number }, -- buildingId -> placed count
	models: { [number]: Model },
}

local PlacementService = {}
PlacementService.plotTiles = 100 -- set by bootstrap
local placedFolder: Folder
local states: { [Player]: PlayerState } = {}
local nextInstanceId = 0

-- ── state helpers ────────────────────────────────────────────────
local function getState(player: Player): PlayerState
	local s = states[player]
	if not s then
		s = { occupied = {}, buildings = {}, counts = {}, models = {} }
		states[player] = s
	end
	return s
end

local function rotatedFootprint(buildingId: string, rotation: number): (number, number)
	local def = Buildings[buildingId]
	return GridUtil.rotateFootprint(def.footprint[1], def.footprint[2], rotation)
end

-- Validate a footprint. `ignoreId` lets a move skip its own tiles.
local function validate(
	state: PlayerState,
	buildingId: string,
	anchor: Tile,
	rotation: number,
	ignoreId: number?
): (boolean, string?)
	local def = Buildings[buildingId]
	if not def then
		return false, "Unknown building: " .. tostring(buildingId)
	end

	-- build limit (static maxCount; Tower's XP-scaled cap is a later phase)
	if def.maxCount then
		local count = state.counts[buildingId] or 0
		if ignoreId == nil and count >= def.maxCount then
			return false, def.displayName .. " limit reached (" .. def.maxCount .. ")"
		end
	end

	local w, d = rotatedFootprint(buildingId, rotation)

	if not GridUtil.withinPlot(anchor, w, d, PlacementService.plotTiles) then
		return false, "Out of bounds"
	end

	-- Must be over actual ground (your landscape) — this is the real boundary.
	local fc = GridUtil.footprintCenter(anchor, w, d)
	if Ground.heightAt(fc.X, fc.Z, { placedFolder }) == nil then
		return false, "No ground here"
	end

	for _, key in ipairs(GridUtil.footprintKeys(anchor, w, d)) do
		local occupantId = state.occupied[key]
		if occupantId ~= nil and occupantId ~= ignoreId then
			return false, "Tiles already occupied"
		end
	end

	return true, nil
end

local function setOccupancy(state: PlayerState, rec: Record, occupied: boolean)
	local w, d = rotatedFootprint(rec.buildingId, rec.rotation)
	for _, key in ipairs(GridUtil.footprintKeys(rec.anchor, w, d)) do
		state.occupied[key] = occupied and rec.instanceId or nil
	end
end

-- World-space center for a footprint, with Y resting on the ground below it.
local function groundedCenter(anchor: Tile, w: number, d: number, height: number): Vector3
	local fc = GridUtil.footprintCenter(anchor, w, d)
	local groundY = Ground.heightAt(fc.X, fc.Z, { placedFolder }) or 0
	return Vector3.new(fc.X, groundY + height / 2, fc.Z)
end

local function spawnModel(player: Player, rec: Record)
	local w, d = rotatedFootprint(rec.buildingId, rec.rotation)
	local model = BuildingVisual.create(rec.buildingId, w, d, false)
	local height = (model.PrimaryPart :: BasePart).Size.Y
	model:PivotTo(CFrame.new(groundedCenter(rec.anchor, w, d, height)))
	model:SetAttribute("InstanceId", rec.instanceId)
	model:SetAttribute("BuildingId", rec.buildingId)
	model:SetAttribute("Owner", player.UserId)
	model.Parent = placedFolder
	getState(player).models[rec.instanceId] = model
end

local function moveModel(state: PlayerState, rec: Record)
	local model = state.models[rec.instanceId]
	if not model then
		return
	end
	local w, d = rotatedFootprint(rec.buildingId, rec.rotation)
	local height = (model.PrimaryPart :: BasePart).Size.Y
	model:PivotTo(CFrame.new(groundedCenter(rec.anchor, w, d, height)))
end

local function serialize(state: PlayerState): { Record }
	local list = {}
	for _, rec in pairs(state.buildings) do
		table.insert(list, rec)
	end
	return list
end

-- ── request handlers ─────────────────────────────────────────────
local function onPlace(player: Player, buildingId: string, anchor: Tile, rotation: number)
	if typeof(buildingId) ~= "string" or typeof(anchor) ~= "table" then
		return
	end
	local state = getState(player)
	local ok, reason = validate(state, buildingId, anchor, rotation)
	if not ok then
		Net.event("ActionRejected"):FireClient(player, reason)
		return
	end

	-- Cost gate. Building costs are still undefined in the design (cost == nil),
	-- so this is a no-op today; the moment costs are filled in, placement starts
	-- spending lumber/stone/gold automatically.
	local def = Buildings[buildingId]
	if def.cost then
		local data = PlayerData.get(player)
		local discount = GameConfig.Aura.costMultiplier(data and data.aura or 0)
		local needLumber = math.ceil(def.cost.lumber * discount)
		local needStone = math.ceil(def.cost.stone * discount)
		local needGold = math.ceil(def.cost.gold * discount)
		local haveLumber = data and (data.stock.lumber or 0) or 0
		local haveStone = data and (data.stock.stone or 0) or 0
		local haveGold = data and data.gold or 0
		if haveLumber < needLumber or haveStone < needStone or haveGold < needGold then
			Net.event("ActionRejected"):FireClient(player, "Not enough resources")
			return
		end
		PlayerData.consumeResource(player, "lumber", needLumber)
		PlayerData.consumeResource(player, "stone", needStone)
		PlayerData.spendGold(player, needGold)
	end

	nextInstanceId += 1
	local rec: Record = {
		instanceId = nextInstanceId,
		buildingId = buildingId,
		anchor = { x = anchor.x, z = anchor.z },
		rotation = rotation,
	}
	state.buildings[rec.instanceId] = rec
	state.counts[buildingId] = (state.counts[buildingId] or 0) + 1
	setOccupancy(state, rec, true)
	spawnModel(player, rec)
	PlayerData.addXp(player, GameConfig.Economy.XP_PER_BUILDING_PLACED)
	Net.event("BuildingPlaced"):FireClient(player, rec)
end

local function onMove(player: Player, instanceId: number, anchor: Tile, rotation: number)
	local state = getState(player)
	local rec = state.buildings[instanceId]
	if not rec then
		return
	end
	local ok, reason = validate(state, rec.buildingId, anchor, rotation, instanceId)
	if not ok then
		Net.event("ActionRejected"):FireClient(player, reason)
		return
	end

	setOccupancy(state, rec, false) -- free old tiles
	rec.anchor = { x = anchor.x, z = anchor.z }
	rec.rotation = rotation
	setOccupancy(state, rec, true) -- claim new tiles
	moveModel(state, rec)
	Net.event("BuildingMoved"):FireClient(player, rec)
end

local function onDelete(player: Player, instanceId: number)
	local state = getState(player)
	local rec = state.buildings[instanceId]
	if not rec then
		return
	end
	if rec.buildingId == "Manor" then
		Net.event("ActionRejected"):FireClient(player, "The Manor cannot be destroyed")
		return
	end

	setOccupancy(state, rec, false)
	state.counts[rec.buildingId] = math.max(0, (state.counts[rec.buildingId] or 1) - 1)
	state.buildings[instanceId] = nil
	local model = state.models[instanceId]
	if model then
		model:Destroy()
		state.models[instanceId] = nil
	end
	Net.event("BuildingRemoved"):FireClient(player, instanceId)
end

-- ── public accessors (read-only views for other services) ───────
-- Updates the in-world "x/N peasants" label for a worker building.
function PlacementService.setAssigned(player: Player, instanceId: number, assigned: number, required: number)
	local model = getState(player).models[instanceId]
	if not model then
		return
	end
	local base = model.PrimaryPart
	local gui = base and base:FindFirstChild("Info")
	local workers = gui and gui:FindFirstChild("Workers")
	if workers and workers:IsA("TextLabel") then
		workers.Text = string.format("%d/%d peasants", assigned, required)
	end
end

function PlacementService.getBuildings(player: Player): { [number]: Record }
	return getState(player).buildings
end

function PlacementService.getCounts(player: Player): { [string]: number }
	return getState(player).counts
end

-- ── lifecycle ────────────────────────────────────────────────────
function PlacementService.init(plotTiles: number, folder: Folder)
	PlacementService.plotTiles = plotTiles
	placedFolder = folder
end

function PlacementService.start()
	Net.event("PlaceBuilding").OnServerEvent:Connect(onPlace)
	Net.event("MoveBuilding").OnServerEvent:Connect(onMove)
	Net.event("DeleteBuilding").OnServerEvent:Connect(onDelete)

	Net.fn("RequestState").OnServerInvoke = function(player)
		return serialize(getState(player))
	end

	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state then
			for _, model in pairs(state.models) do
				model:Destroy()
			end
			states[player] = nil
		end
	end)
end

return PlacementService
