--!strict
--[[
	DayNightController.server.luau
	Purely cosmetic day/night cycle. Drives Lighting.ClockTime over a tunable
	period. Has zero effect on the economy (which is normalised to minutes).
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local DN = GameConfig.DayNight

if DN.ENABLED then
	local cycleSeconds = DN.CYCLE_MINUTES * 60
	local elapsed = (DN.START_CLOCK / 24) * cycleSeconds

	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		local frac = (elapsed % cycleSeconds) / cycleSeconds
		Lighting.ClockTime = frac * 24
	end)
end
