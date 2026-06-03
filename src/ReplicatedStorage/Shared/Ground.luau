--!strict
--[[
	Ground.luau
	Finds the ground surface height at a world X/Z by raycasting straight down.
	Used so buildings sit on whatever landscape exists (Studio terrain or parts)
	instead of a hardcoded y = 0. Returns nil when there's no ground there, which
	is what bounds building to the actual landscape.
]]

local Workspace = game:GetService("Workspace")

local Ground = {}

local PROBE_TOP = 2000 -- start the ray well above any terrain
local PROBE_DEPTH = 6000 -- and cast far below it

function Ground.heightAt(x: number, z: number, ignore: { Instance }?): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.IgnoreWater = true
	local result = Workspace:Raycast(Vector3.new(x, PROBE_TOP, z), Vector3.new(0, -PROBE_DEPTH, 0), params)
	return result and result.Position.Y or nil
end

return Ground
