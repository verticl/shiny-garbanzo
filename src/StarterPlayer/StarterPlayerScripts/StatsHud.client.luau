--!strict
--[[
	StatsHud.client.luau
	Live economy readout on the left. Updates every server tick so you can
	watch resources, gold, and XP climb. This is a functional dev HUD — the
	polished player card / XP bar from the reference art comes in Phase 5.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function titleCase(s: string): string
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- ── UI ───────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "StatsHUD"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 170, 0, 340)
panel.Position = UDim2.new(0, 12, 0, 12)
panel.BackgroundColor3 = Color3.fromRGB(25, 28, 34)
panel.BackgroundTransparency = 0.1
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 3)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local function makeRow(order: number, color: Color3): TextLabel
	local row = Instance.new("TextLabel")
	row.Size = UDim2.new(1, 0, 0, 18)
	row.BackgroundTransparency = 1
	row.Font = Enum.Font.GothamMedium
	row.TextSize = 13
	row.TextColor3 = color
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.LayoutOrder = order
	row.Text = ""
	row.Parent = panel
	return row
end

local goldRow = makeRow(1, Color3.fromRGB(255, 215, 90))
local xpRow = makeRow(2, Color3.fromRGB(180, 140, 255))
local auraRow = makeRow(3, Color3.fromRGB(120, 230, 170))
local popRow = makeRow(4, Color3.fromRGB(120, 200, 255))
local jobsRow = makeRow(5, Color3.fromRGB(150, 180, 220))
local idleRow = makeRow(6, Color3.fromRGB(150, 180, 220))

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, 0, 0, 1)
divider.BackgroundColor3 = Color3.fromRGB(70, 76, 88)
divider.BorderSizePixel = 0
divider.LayoutOrder = 7
divider.Parent = panel

-- one reusable label per resource
local resourceRows: { [string]: TextLabel } = {}
for i, res in ipairs(GameConfig.RESOURCES) do
	resourceRows[res] = makeRow(10 + i, Color3.fromRGB(210, 215, 225))
end

-- ── live updates ─────────────────────────────────────────────────
Net.event("StatsUpdate").OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then
		return
	end
	goldRow.Text = string.format("Gold   %d", data.gold or 0)
	xpRow.Text = string.format("XP     %d", data.xp or 0)
	auraRow.Text = string.format("Aura   %d", data.aura or 0)
	popRow.Text = string.format("Pop    %d/%d", data.population or 0, data.housingCapacity or 0)
	jobsRow.Text = string.format("Jobs   %d/%d", data.employed or 0, data.jobSlots or 0)
	idleRow.Text = string.format("Idle   %d", data.idle or 0)

	for _, res in ipairs(GameConfig.RESOURCES) do
		local row = resourceRows[res]
		local stock = (data.stock and data.stock[res]) or 0
		local cap = math.floor((data.capacity and data.capacity[res]) or 0)
		-- show a row only once it's relevant (has storage or some stock)
		if cap > 0 or stock > 0 then
			row.Visible = true
			row.Text = string.format("%-8s %d/%d", titleCase(res), stock, cap)
		else
			row.Visible = false
		end
	end
end)
