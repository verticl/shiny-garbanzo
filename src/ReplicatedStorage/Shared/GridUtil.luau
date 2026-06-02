--!strict
--[[
	GridUtil.luau
	Pure, stateless grid math shared by client and server.

	Tile model:
	  - The plot occupies tiles (0,0) .. (plotTiles-1, plotTiles-1).
	  - Tile (x,z) spans world [x*TILE, (x+1)*TILE) on the X axis and
	    [z*TILE, (z+1)*TILE) on the Z axis. (Plot starts at world origin.)
	  - A building's "anchor" is its minimum-corner tile; it occupies a
	    w x d block of tiles from the anchor.
	  - rotation is in 90-degree steps (0..3); odd steps swap width/depth.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Config.GameConfig)

local TILE = GameConfig.TILE_SIZE

local GridUtil = {}
GridUtil.TILE_SIZE = TILE

export type Tile = { x: number, z: number }

-- Returns the (possibly swapped) footprint for a rotation in 90-degree steps.
function GridUtil.rotateFootprint(w: number, d: number, steps: number): (number, number)
	if steps % 2 == 1 then
		return d, w
	end
	return w, d
end

-- Given a world X/Z and a footprint, returns the anchor tile that centers
-- the footprint as close as possible under that world point.
function GridUtil.snapToAnchor(worldX: number, worldZ: number, w: number, d: number): Tile
	return {
		x = math.floor(worldX / TILE - w / 2 + 0.5),
		z = math.floor(worldZ / TILE - d / 2 + 0.5),
	}
end

-- World-space center of the footprint block (y = 0; caller adds height).
function GridUtil.footprintCenter(anchor: Tile, w: number, d: number): Vector3
	return Vector3.new((anchor.x + w / 2) * TILE, 0, (anchor.z + d / 2) * TILE)
end

function GridUtil.tileKey(x: number, z: number): string
	return string.format("%d_%d", x, z)
end

-- All tile keys covered by a footprint anchored at `anchor`.
function GridUtil.footprintKeys(anchor: Tile, w: number, d: number): { string }
	local keys = {}
	for x = anchor.x, anchor.x + w - 1 do
		for z = anchor.z, anchor.z + d - 1 do
			table.insert(keys, GridUtil.tileKey(x, z))
		end
	end
	return keys
end

-- Is the whole footprint inside a square plot of `plotTiles` per side?
function GridUtil.withinPlot(anchor: Tile, w: number, d: number, plotTiles: number): boolean
	return anchor.x >= 0
		and anchor.z >= 0
		and anchor.x + w <= plotTiles
		and anchor.z + d <= plotTiles
end

return GridUtil
