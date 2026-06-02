--!strict
--[[
	CameraController.client.luau
	Pulls the camera well back on spawn to emphasize the "mini" scale,
	while leaving the player free to zoom in/out afterward.

	Technique: there's no direct "set zoom distance" API, so we briefly
	clamp min == max to snap the camera to DEFAULT_ZOOM, then relax the
	bounds so normal scroll-zoom works again.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local CAM = GameConfig.Camera

local player = Players.LocalPlayer

local function applyDefaultZoom()
	-- Snap to the default distance...
	player.CameraMinZoomDistance = CAM.DEFAULT_ZOOM
	player.CameraMaxZoomDistance = CAM.DEFAULT_ZOOM
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	-- ...then relax so the player can zoom freely.
	player.CameraMinZoomDistance = CAM.MIN_ZOOM
	player.CameraMaxZoomDistance = CAM.MAX_ZOOM
end

local function onCharacter(character: Model)
	character:WaitForChild("Humanoid")
	task.defer(applyDefaultZoom)
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)
