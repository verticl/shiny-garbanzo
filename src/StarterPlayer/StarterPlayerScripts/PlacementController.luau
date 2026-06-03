--!strict
--[[
	PlacementController.luau  (client)
	------------------------------------------------------------------
	Drives the build experience: a ghost preview that snaps to the grid,
	rotates, and shows green/red validity, plus move/delete on existing
	buildings. The server is authoritative — this only previews and asks.

	Modes:
	  idle      - nothing active
	  placing   - ghost following the cursor (new building, or a move)
	  managing  - click a building to select it, then Move / Delete

	Controls:
	  Left click  - place (placing) / select (managing)
	  R           - rotate the ghost
	  Esc / RMB   - cancel
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Buildings = require(ReplicatedStorage.Config.Buildings)
local GridUtil = require(ReplicatedStorage.Shared.GridUtil)
local BuildingVisual = require(ReplicatedStorage.Shared.BuildingVisual)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Net = require(ReplicatedStorage.Shared.Net)

type Tile = GridUtil.Tile
type Record = { instanceId: number, buildingId: string, anchor: Tile, rotation: number }

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local PLOT_TILES = GameConfig.BUILDABLE_TILES

local PlacementController = {}

-- Local mirror of the player's buildings (kept in sync via remotes).
local localBuildings: { [number]: Record } = {}

local mode: "idle" | "placing" | "managing" = "idle"
local ghost: Model? = nil
local ghostBuildingId: string? = nil
local ghostRotation = 0
local movingId: number? = nil -- set when the ghost is an in-progress move
local currentAnchor: Tile? = nil
local currentValid = false

local selectedId: number? = nil
local highlight: Highlight? = nil

-- Callbacks the UI can hook.
PlacementController.onSelectionChanged = nil :: ((selectedId: number?) -> ())?
PlacementController.onRejected = nil :: ((reason: string?) -> ())?
-- Fired true when a ghost becomes active (placing/moving), false when it ends.
PlacementController.onPlacingChanged = nil :: ((placing: boolean) -> ())?

-- ── raycasting ───────────────────────────────────────────────────
local function mouseRay(): Ray
	local pos = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(pos.X, pos.Y)
end

-- Ground hit for ghost positioning (ignore ghost + placed buildings).
local function raycastGround(): Vector3?
	local ray = mouseRay()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { Workspace:FindFirstChild("Placed") :: Instance }
	if ghost then
		table.insert(exclude, ghost)
	end
	if player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 4000, params)
	return result and result.Position or nil
end

-- Building hit for selection -> its InstanceId attribute (nil if none).
local function raycastBuilding(): number?
	local ray = mouseRay()
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 4000)
	if not result then
		return nil
	end
	local inst: Instance? = result.Instance
	while inst and inst ~= Workspace do
		local id = inst:GetAttribute("InstanceId")
		if typeof(id) == "number" then
			return id
		end
		inst = inst.Parent
	end
	return nil
end

-- ── validity (local prediction; server re-checks) ────────────────
local function occupiedSet(excludeId: number?): { [string]: boolean }
	local set = {}
	for id, rec in pairs(localBuildings) do
		if id ~= excludeId then
			local def = Buildings[rec.buildingId]
			local w, d = GridUtil.rotateFootprint(def.footprint[1], def.footprint[2], rec.rotation)
			for _, key in ipairs(GridUtil.footprintKeys(rec.anchor, w, d)) do
				set[key] = true
			end
		end
	end
	return set
end

local function isValid(buildingId: string, anchor: Tile, rotation: number, ignoreId: number?): boolean
	local def = Buildings[buildingId]
	local w, d = GridUtil.rotateFootprint(def.footprint[1], def.footprint[2], rotation)
	if not GridUtil.withinPlot(anchor, w, d, PLOT_TILES) then
		return false
	end
	local occupied = occupiedSet(ignoreId)
	for _, key in ipairs(GridUtil.footprintKeys(anchor, w, d)) do
		if occupied[key] then
			return false
		end
	end
	return true
end

-- ── ghost lifecycle ──────────────────────────────────────────────
local function destroyGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
end

local function rebuildGhost()
	destroyGhost()
	if not ghostBuildingId then
		return
	end
	local def = Buildings[ghostBuildingId]
	local w, d = GridUtil.rotateFootprint(def.footprint[1], def.footprint[2], ghostRotation)
	ghost = BuildingVisual.create(ghostBuildingId, w, d, true)
	ghost.Parent = Workspace
end

local function updateGhost()
	local buildingId = ghostBuildingId
	if mode ~= "placing" or not ghost or not buildingId then
		return
	end
	local hit = raycastGround()
	if not hit then
		ghost.PrimaryPart.Transparency = 1
		return
	end
	ghost.PrimaryPart.Transparency = 0.5
	local def = Buildings[buildingId]
	local w, d = GridUtil.rotateFootprint(def.footprint[1], def.footprint[2], ghostRotation)
	local anchor = GridUtil.snapToAnchor(hit.X, hit.Z, w, d)
	currentAnchor = anchor

	-- Sit the ghost on the ground at the snapped footprint center.
	local fc = GridUtil.footprintCenter(anchor, w, d)
	local ignore: { Instance } = {}
	local placedFolder = Workspace:FindFirstChild("Placed")
	if placedFolder then
		table.insert(ignore, placedFolder)
	end
	table.insert(ignore, ghost)
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local groundY = Ground.heightAt(fc.X, fc.Z, ignore)
	if not groundY then
		ghost.PrimaryPart.Transparency = 1
		currentValid = false
		return
	end

	currentValid = isValid(buildingId, anchor, ghostRotation, movingId)
	BuildingVisual.setGhostValid(ghost, currentValid)
	local height = (ghost.PrimaryPart :: BasePart).Size.Y
	ghost:PivotTo(CFrame.new(Vector3.new(fc.X, groundY + height / 2, fc.Z)))
end

-- ── selection ────────────────────────────────────────────────────
local function clearSelection()
	selectedId = nil
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	if PlacementController.onSelectionChanged then
		PlacementController.onSelectionChanged(nil)
	end
end

local function select(instanceId: number)
	clearSelection()
	local placed = Workspace:FindFirstChild("Placed")
	if not placed then
		return
	end
	for _, model in ipairs(placed:GetChildren()) do
		if model:GetAttribute("InstanceId") == instanceId then
			selectedId = instanceId
			highlight = Instance.new("Highlight")
			highlight.FillColor = Color3.fromRGB(255, 220, 120)
			highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
			highlight.FillTransparency = 0.6
			highlight.Parent = model
			break
		end
	end
	if PlacementController.onSelectionChanged then
		PlacementController.onSelectionChanged(selectedId)
	end
end

-- ── public API ───────────────────────────────────────────────────
function PlacementController.startPlacing(buildingId: string)
	clearSelection()
	mode = "placing"
	movingId = nil
	ghostBuildingId = buildingId
	ghostRotation = 0
	rebuildGhost()
	if PlacementController.onPlacingChanged then
		PlacementController.onPlacingChanged(true)
	end
end

-- Rotate the active ghost 90 degrees. Safe to call when not placing.
function PlacementController.rotate()
	if mode == "placing" then
		ghostRotation = (ghostRotation + 1) % 4
		rebuildGhost()
	end
end

-- Look up a placed building's record (for UI display).
function PlacementController.getRecord(instanceId: number): Record?
	return localBuildings[instanceId]
end

function PlacementController.beginMove(instanceId: number)
	local rec = localBuildings[instanceId]
	if not rec then
		return
	end
	clearSelection()
	mode = "placing"
	movingId = instanceId
	ghostBuildingId = rec.buildingId
	ghostRotation = rec.rotation
	rebuildGhost()
	if PlacementController.onPlacingChanged then
		PlacementController.onPlacingChanged(true)
	end
end

function PlacementController.deleteSelected()
	if selectedId then
		Net.event("DeleteBuilding"):FireServer(selectedId)
		clearSelection()
	end
end

function PlacementController.enterManageMode()
	PlacementController.cancel()
	mode = "managing"
end

function PlacementController.cancel()
	destroyGhost()
	ghostBuildingId = nil
	movingId = nil
	currentAnchor = nil
	mode = "idle"
	clearSelection()
	if PlacementController.onPlacingChanged then
		PlacementController.onPlacingChanged(false)
	end
end

-- ── input ────────────────────────────────────────────────────────
local function commitPlacement()
	if not currentValid or not currentAnchor or not ghostBuildingId then
		return
	end
	if movingId then
		Net.event("MoveBuilding"):FireServer(movingId, currentAnchor, ghostRotation)
		PlacementController.cancel()
	else
		Net.event("PlaceBuilding"):FireServer(ghostBuildingId, currentAnchor, ghostRotation)
		-- stay in placing mode to chain placements; mirror updates on confirm
	end
end

local function onInput(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if mode == "placing" then
			commitPlacement()
		else
			-- idle: click a building to select it (opens its context menu)
			local id = raycastBuilding()
			if id and localBuildings[id] then
				select(id)
			else
				clearSelection()
			end
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if mode == "placing" then
			PlacementController.cancel()
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		PlacementController.rotate()
	elseif input.KeyCode == Enum.KeyCode.Escape then
		PlacementController.cancel()
	elseif input.KeyCode == Enum.KeyCode.X or input.KeyCode == Enum.KeyCode.Delete then
		PlacementController.deleteSelected()
	end
end

-- ── remote sync ──────────────────────────────────────────────────
local function init()
	-- initial state
	local existing = Net.fn("RequestState"):InvokeServer() :: { Record }
	if typeof(existing) == "table" then
		for _, rec in ipairs(existing) do
			localBuildings[rec.instanceId] = rec
		end
	end

	Net.event("BuildingPlaced").OnClientEvent:Connect(function(rec: Record)
		localBuildings[rec.instanceId] = rec
	end)
	Net.event("BuildingMoved").OnClientEvent:Connect(function(rec: Record)
		localBuildings[rec.instanceId] = rec
	end)
	Net.event("BuildingRemoved").OnClientEvent:Connect(function(instanceId: number)
		localBuildings[instanceId] = nil
		if selectedId == instanceId then
			clearSelection()
		end
	end)
	Net.event("ActionRejected").OnClientEvent:Connect(function(reason: string?)
		if PlacementController.onRejected then
			PlacementController.onRejected(reason)
		end
	end)

	RunService.RenderStepped:Connect(updateGhost)
	UserInputService.InputBegan:Connect(onInput)
end

init()
return PlacementController
