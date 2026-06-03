--!strict
--[[
	BuildingVisual.luau
	Builds a temporary placeholder model sized to a building's footprint.
	Used by the server (solid, the real building) and the client (ghost
	preview). Replace with real low-poly models in a later art pass —
	callers only depend on create()/setGhostValid().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Buildings = require(ReplicatedStorage.Config.Buildings)

local TILE = GameConfig.TILE_SIZE

local CATEGORY_COLOR: { [string]: Color3 } = {
	Manor = Color3.fromRGB(150, 90, 200),
	Housing = Color3.fromRGB(205, 165, 115),
	Farm = Color3.fromRGB(120, 190, 90),
	Stable = Color3.fromRGB(170, 130, 90),
	Producer = Color3.fromRGB(210, 180, 90),
	Quarry = Color3.fromRGB(150, 150, 160),
	Storage = Color3.fromRGB(120, 170, 200),
	Military = Color3.fromRGB(200, 90, 90),
	Defense = Color3.fromRGB(110, 120, 130),
}

local BuildingVisual = {}

-- w/d are the ALREADY-ROTATED footprint dimensions (in tiles).
function BuildingVisual.create(buildingId: string, w: number, d: number, ghost: boolean): Model
	local def = Buildings[buildingId]
	local model = Instance.new("Model")
	model.Name = buildingId

	local sizeX, sizeZ = w * TILE, d * TILE
	local height = math.clamp((sizeX + sizeZ) / 6, 4, 24)

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.Size = Vector3.new(sizeX, height, sizeZ)
	base.Color = (def and CATEGORY_COLOR[def.category]) or Color3.fromRGB(180, 180, 180)
	base.Material = ghost and Enum.Material.ForceField or Enum.Material.SmoothPlastic
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Transparency = ghost and 0.5 or 0
	base.CanCollide = not ghost
	base.Parent = model
	model.PrimaryPart = base

	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromScale(8, (def and def.peasants > 0) and 2.6 or 1.9)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height / 2 + 2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = base

	local needsWorkers = def ~= nil and def.peasants > 0

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.Size = needsWorkers and UDim2.fromScale(1, 0.62) or UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = (def and def.displayName) or buildingId
	label.Parent = gui

	if needsWorkers then
		local workers = Instance.new("TextLabel")
		workers.Name = "Workers"
		workers.BackgroundTransparency = 1
		workers.Position = UDim2.fromScale(0, 0.64)
		workers.Size = UDim2.fromScale(1, 0.36)
		workers.TextScaled = true
		workers.Font = Enum.Font.GothamMedium
		workers.TextColor3 = Color3.fromRGB(210, 225, 255)
		workers.TextStrokeTransparency = 0.4
		workers.Text = ghost and string.format("needs %d peasants", def.peasants)
			or string.format("0/%d peasants", def.peasants)
		workers.Parent = gui
	end

	return model
end

function BuildingVisual.setGhostValid(model: Model, valid: boolean)
	local base = model.PrimaryPart
	if base then
		base.Color = valid and Color3.fromRGB(90, 220, 110) or Color3.fromRGB(220, 80, 80)
	end
end

return BuildingVisual
