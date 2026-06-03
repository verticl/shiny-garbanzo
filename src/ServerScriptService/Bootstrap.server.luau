--!strict
--[[
	Bootstrap.server.luau
	Server entry point. Builds a temporary flat plot to build on (real
	5000x5000 map generation is Phase 7), then starts PlacementService.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local PlacementService = require(script.Parent.PlacementService)
local EconomyService = require(script.Parent.EconomyService)

local PLOT_TILES = GameConfig.TEST_PLOT_TILES
local plotStuds = PLOT_TILES * GameConfig.TILE_SIZE

-- Folder that holds all placed buildings.
local placed = Instance.new("Folder")
placed.Name = "Placed"
placed.Parent = Workspace

-- Flat ground; top surface sits at y = 0 so buildings rest on it.
local ground = Instance.new("Part")
ground.Name = "Plot"
ground.Anchored = true
ground.Size = Vector3.new(plotStuds, 1, plotStuds)
ground.Position = Vector3.new(plotStuds / 2, -0.5, plotStuds / 2)
ground.Color = Color3.fromRGB(110, 165, 80)
ground.Material = Enum.Material.Grass
ground.TopSurface = Enum.SurfaceType.Smooth
ground.Parent = Workspace

-- Spawn near the plot center.
local spawn = Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Size = Vector3.new(6, 1, 6)
spawn.Position = Vector3.new(plotStuds / 2, 0.5, plotStuds / 2)
spawn.Neutral = true
spawn.Parent = Workspace

PlacementService.init(GameConfig.BUILDABLE_TILES, placed)
PlacementService.start()
EconomyService.start()

print("[MiniKing] Server ready. Building conforms to the landscape; a small spawn pad is at the origin.")
