--!strict
--[[
	MapService.luau  (server)
	------------------------------------------------------------------
	Builds the 5000x5000 world and runs mine discovery.

	Layout:
	  - a flat grass plain (the whole map is buildable, minus lakes & mines)
	  - a low-poly mountain ring just outside the play area
	  - scattered cosmetic trees + a few lakes (lakes block building)
	  - two mines near opposite corners: rocky outcroppings with a flat top.
	    Quarries may only be placed on the matching mine, AFTER the player has
	    walked close enough to DISCOVER it.

	Validation helpers (footprintBlocked / mineContaining / touchesAnyMine) and
	discovery state are read by PlacementService. Map data is replicated to the
	client via the RequestMapData remote so the placement ghost stays accurate.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local GridUtil = require(ReplicatedStorage.Shared.GridUtil)
local Net = require(ReplicatedStorage.Shared.Net)

local TILE = GameConfig.TILE_SIZE
local SIZE = GameConfig.MAP_SIZE
local MAP = GameConfig.Map

type Rect = { minX: number, minZ: number, maxX: number, maxZ: number }
type Mine = { type: string, cx: number, cz: number, rect: Rect }

local MapService = {}
MapService.PLOT_TILES = GameConfig.PLOT_TILES

local mines: { [string]: Mine } = {}
local blocked: { [string]: boolean } = {}
local discovered: { [Player]: { [string]: boolean } } = {}
local mapFolder: Folder

-- ── small helpers ────────────────────────────────────────────────
local function studToTile(s: number): number
	return math.floor(s / TILE)
end

local function block(p: Instance)
	p.Parent = mapFolder
end

local function rectFor(cx: number, cz: number): Rect
	local half = math.floor(MAP.MINE_PLATFORM_TILES / 2)
	local tx, tz = studToTile(cx), studToTile(cz)
	return { minX = tx - half, minZ = tz - half, maxX = tx + half - 1, maxZ = tz + half - 1 }
end

local function dist2(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return dx * dx + dz * dz
end

-- ── generation pieces ────────────────────────────────────────────
local function makeGround()
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.Size = Vector3.new(SIZE, 2, SIZE)
	ground.Position = Vector3.new(SIZE / 2, -1, SIZE / 2) -- top at y = 0
	ground.Color = Color3.fromRGB(112, 166, 82)
	ground.Material = Enum.Material.Grass
	ground.TopSurface = Enum.SurfaceType.Smooth
	block(ground)

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(MAP.SPAWN.x, 0.5, MAP.SPAWN.z)
	spawn.Neutral = true
	spawn.Color = Color3.fromRGB(90, 140, 64)
	block(spawn)
end

local function makeMountain(x: number, z: number)
	local h = math.random(130, 280)
	local base = math.random(140, 260)
	local m = Instance.new("Part")
	m.Anchored = true
	m.Size = Vector3.new(base, h, base)
	m.Position = Vector3.new(x, h / 2 - 30, z)
	m.Orientation = Vector3.new(0, math.random(0, 359), 0)
	m.Color = Color3.fromRGB(120, 124, 132)
	m.Material = Enum.Material.Rock
	block(m)

	local cap = Instance.new("Part")
	cap.Anchored = true
	cap.Size = Vector3.new(base * 0.5, h * 0.28, base * 0.5)
	cap.Position = Vector3.new(x, h - 30 - h * 0.10, z)
	cap.Orientation = m.Orientation
	cap.Color = Color3.fromRGB(236, 239, 246)
	cap.Material = Enum.Material.Sand
	block(cap)
end

local function makeMountainRing()
	local margin = 200
	local step = 320
	for x = -margin, SIZE + margin, step do
		makeMountain(x, -margin)
		makeMountain(x, SIZE + margin)
	end
	for z = 0, SIZE, step do
		makeMountain(-margin, z)
		makeMountain(SIZE + margin, z)
	end
end

local function makeTree(x: number, z: number)
	local model = Instance.new("Model")
	model.Name = "Tree"

	local th = math.random(6, 12)
	local trunk = Instance.new("Part")
	trunk.Anchored = true
	trunk.CanCollide = false
	trunk.Size = Vector3.new(2, th, 2)
	trunk.Position = Vector3.new(x, th / 2, z)
	trunk.Color = Color3.fromRGB(96, 68, 44)
	trunk.Material = Enum.Material.Wood
	trunk.Parent = model

	local fs = math.random(9, 15)
	local foliage = Instance.new("Part")
	foliage.Anchored = true
	foliage.CanCollide = false
	foliage.Shape = Enum.PartType.Ball
	foliage.Size = Vector3.new(fs, fs, fs)
	foliage.Position = Vector3.new(x, th + fs * 0.3, z)
	foliage.Color = Color3.fromRGB(68, 128, 58)
	foliage.Material = Enum.Material.Grass
	foliage.Parent = model

	model.Parent = mapFolder
end

local function farFromFeatures(x: number, z: number): boolean
	if dist2(x, z, MAP.SPAWN.x, MAP.SPAWN.z) < MAP.SPAWN_CLEAR_RADIUS ^ 2 then
		return false
	end
	for _, m in pairs(mines) do
		if dist2(x, z, m.cx, m.cz) < (MAP.MINE_PLATFORM_TILES * TILE) ^ 2 then
			return false
		end
	end
	return true
end

local function makeLake()
	local rTiles = math.random(MAP.LAKE_RADIUS_TILES.min, MAP.LAKE_RADIUS_TILES.max)
	local r = rTiles * TILE
	local cx, cz
	repeat
		cx = math.random(r + 200, SIZE - r - 200)
		cz = math.random(r + 200, SIZE - r - 200)
	until farFromFeatures(cx, cz)

	local lake = Instance.new("Part")
	lake.Anchored = true
	lake.CanCollide = false
	lake.Shape = Enum.PartType.Cylinder
	lake.Size = Vector3.new(0.8, 2 * r, 2 * r)
	lake.Orientation = Vector3.new(0, 0, 90)
	lake.Position = Vector3.new(cx, 0.1, cz)
	lake.Color = Color3.fromRGB(70, 130, 200)
	lake.Material = Enum.Material.Glass
	lake.Transparency = 0.25
	block(lake)

	local ctx, ctz = studToTile(cx), studToTile(cz)
	for tx = ctx - rTiles, ctx + rTiles do
		for tz = ctz - rTiles, ctz + rTiles do
			if (tx - ctx) ^ 2 + (tz - ctz) ^ 2 <= rTiles ^ 2 then
				blocked[GridUtil.tileKey(tx, tz)] = true
			end
		end
	end
end

local function makeMine(typeName: string, cx: number, cz: number, rockColor: Color3)
	mines[typeName] = { type = typeName, cx = cx, cz = cz, rect = rectFor(cx, cz) }

	local platStud = MAP.MINE_PLATFORM_TILES * TILE
	-- rocky ring around the (flat, buildable) platform
	for i = 1, 16 do
		local ang = (i / 16) * math.pi * 2
		local rad = platStud * 0.62 + math.random(0, 8)
		local s = math.random(5, 12)
		local rock = Instance.new("Part")
		rock.Anchored = true
		rock.Size = Vector3.new(s, math.random(5, 12), s)
		rock.Position = Vector3.new(cx + math.cos(ang) * rad, rock.Size.Y / 2, cz + math.sin(ang) * rad)
		rock.Orientation = Vector3.new(math.random(-12, 12), math.random(0, 359), math.random(-12, 12))
		rock.Color = rockColor
		rock.Material = Enum.Material.Rock
		block(rock)
	end

	local marker = Instance.new("Part")
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 1
	marker.Size = Vector3.new(1, 1, 1)
	marker.Position = Vector3.new(cx, 16, cz)
	block(marker)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(14, 3)
	gui.AlwaysOnTop = true
	gui.Parent = marker
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextStrokeTransparency = 0
	lbl.Text = (typeName == "stone" and "Stone Mine" or "Diamond Mine")
	lbl.Parent = gui
end

-- ── public: generation ───────────────────────────────────────────
function MapService.generate()
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = Workspace

	makeGround()
	makeMountainRing()
	makeMine("stone", MAP.STONE_MINE.x, MAP.STONE_MINE.z, Color3.fromRGB(140, 142, 150))
	makeMine("diamond", MAP.DIAMOND_MINE.x, MAP.DIAMOND_MINE.z, Color3.fromRGB(120, 170, 200))

	for _ = 1, MAP.LAKE_COUNT do
		makeLake()
	end

	local placed = 0
	while placed < MAP.TREE_COUNT do
		local x = math.random(80, SIZE - 80)
		local z = math.random(80, SIZE - 80)
		if farFromFeatures(x, z) then
			makeTree(x, z)
			placed += 1
		end
	end
end

-- ── validation helpers (read by PlacementService) ────────────────
function MapService.footprintBlocked(anchor: GridUtil.Tile, w: number, d: number): boolean
	for _, key in ipairs(GridUtil.footprintKeys(anchor, w, d)) do
		if blocked[key] then
			return true
		end
	end
	return false
end

local function rectContains(rect: Rect, anchor: GridUtil.Tile, w: number, d: number): boolean
	return anchor.x >= rect.minX
		and anchor.z >= rect.minZ
		and anchor.x + w - 1 <= rect.maxX
		and anchor.z + d - 1 <= rect.maxZ
end

local function rectOverlaps(rect: Rect, anchor: GridUtil.Tile, w: number, d: number): boolean
	return not (anchor.x > rect.maxX or anchor.x + w - 1 < rect.minX or anchor.z > rect.maxZ or anchor.z + d - 1 < rect.minZ)
end

-- Returns the mine type whose platform fully contains the footprint (or nil).
function MapService.mineContaining(anchor: GridUtil.Tile, w: number, d: number): string?
	for t, mine in pairs(mines) do
		if rectContains(mine.rect, anchor, w, d) then
			return t
		end
	end
	return nil
end

function MapService.touchesAnyMine(anchor: GridUtil.Tile, w: number, d: number): boolean
	for _, mine in pairs(mines) do
		if rectOverlaps(mine.rect, anchor, w, d) then
			return true
		end
	end
	return false
end

-- ── discovery ────────────────────────────────────────────────────
function MapService.isDiscovered(player: Player, mineType: string): boolean
	local d = discovered[player]
	return (d ~= nil) and (d[mineType] == true)
end

function MapService.getClientData()
	local blockedList = {}
	for key in pairs(blocked) do
		table.insert(blockedList, key)
	end
	return {
		plotTiles = MapService.PLOT_TILES,
		mines = {
			stone = mines.stone and mines.stone.rect or nil,
			diamond = mines.diamond and mines.diamond.rect or nil,
		},
		blocked = blockedList,
	}
end

function MapService.start()
	Net.fn("RequestMapData").OnServerInvoke = function(_player)
		return MapService.getClientData()
	end

	Players.PlayerRemoving:Connect(function(player)
		discovered[player] = nil
	end)

	task.spawn(function()
		local radius2 = MAP.DISCOVERY_RADIUS ^ 2
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					local d = discovered[player]
					if not d then
						d = {}
						discovered[player] = d
					end
					for typeName, mine in pairs(mines) do
						if not d[typeName] and dist2(hrp.Position.X, hrp.Position.Z, mine.cx, mine.cz) <= radius2 then
							d[typeName] = true
							Net.event("MineDiscovered"):FireClient(player, typeName)
						end
					end
				end
			end
		end
	end)
end

return MapService
