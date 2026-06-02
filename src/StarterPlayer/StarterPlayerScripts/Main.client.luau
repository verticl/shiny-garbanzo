--!strict
--[[
	Main.client.luau
	Temporary developer UI for testing the placement system. Generates a
	button per building from the config and wires them to the controller.
	This is scaffolding — the real Build/Shop screens from the reference
	art come in Phase 5. Kept deliberately plain.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Buildings = require(ReplicatedStorage.Config.Buildings)
local PlacementController = require(script.Parent.PlacementController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── build a sorted building list ─────────────────────────────────
local ids = {}
for id in pairs(Buildings) do
	table.insert(ids, id)
end
table.sort(ids, function(a, b)
	local da, db = Buildings[a], Buildings[b]
	if da.category ~= db.category then
		return da.category < db.category
	end
	return da.displayName < db.displayName
end)

-- ── UI ───────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "DevBuildUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function newButton(parent: Instance, text: string): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 26)
	b.BackgroundColor3 = Color3.fromRGB(45, 50, 60)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.Text = text
	b.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = b
	b.Parent = parent
	return b
end

-- Left panel
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 180, 0, 360)
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, 12)
panel.BackgroundColor3 = Color3.fromRGB(25, 28, 34)
panel.BackgroundTransparency = 0.1
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 20)
title.BackgroundTransparency = 1
title.Text = "BUILD (dev)"
title.TextColor3 = Color3.fromRGB(255, 220, 120)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

-- scrolling building list
local scroller = Instance.new("ScrollingFrame")
scroller.Size = UDim2.new(1, 0, 1, -90)
scroller.BackgroundTransparency = 1
scroller.BorderSizePixel = 0
scroller.ScrollBarThickness = 4
scroller.CanvasSize = UDim2.new(0, 0, 0, #ids * 30)
scroller.Parent = panel
local sLayout = Instance.new("UIListLayout")
sLayout.Padding = UDim.new(0, 4)
sLayout.Parent = scroller

for _, id in ipairs(ids) do
	local btn = newButton(scroller, Buildings[id].displayName)
	btn.Activated:Connect(function()
		PlacementController.startPlacing(id)
	end)
end

-- manage / move / delete row
local manageBtn = newButton(panel, "Manage mode: OFF")
local moveBtn = newButton(panel, "Move selected")
local deleteBtn = newButton(panel, "Delete selected")
moveBtn.BackgroundColor3 = Color3.fromRGB(35, 38, 46)
deleteBtn.BackgroundColor3 = Color3.fromRGB(35, 38, 46)

local managing = false
local selected: number? = nil

local function refreshButtons()
	manageBtn.Text = "Manage mode: " .. (managing and "ON" or "OFF")
	manageBtn.BackgroundColor3 = managing and Color3.fromRGB(60, 110, 75) or Color3.fromRGB(45, 50, 60)
	local enabled = selected ~= nil
	moveBtn.AutoButtonColor = enabled
	deleteBtn.AutoButtonColor = enabled
	moveBtn.TextTransparency = enabled and 0 or 0.5
	deleteBtn.TextTransparency = enabled and 0 or 0.5
end

manageBtn.Activated:Connect(function()
	managing = not managing
	if managing then
		PlacementController.enterManageMode()
	else
		PlacementController.cancel()
	end
	refreshButtons()
end)

moveBtn.Activated:Connect(function()
	if selected then
		PlacementController.beginMove(selected)
	end
end)

deleteBtn.Activated:Connect(function()
	PlacementController.deleteSelected()
end)

PlacementController.onSelectionChanged = function(id: number?)
	selected = id
	refreshButtons()
end

-- toast for hints + rejections
local toast = Instance.new("TextLabel")
toast.Size = UDim2.new(0, 320, 0, 28)
toast.Position = UDim2.new(0.5, -160, 0, 12)
toast.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
toast.BackgroundTransparency = 1
toast.TextColor3 = Color3.new(1, 1, 1)
toast.Font = Enum.Font.GothamMedium
toast.TextSize = 14
toast.Text = ""
toast.Parent = gui
local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 6)
toastCorner.Parent = toast

local toastToken = 0
local function showToast(msg: string)
	toast.Text = msg
	toast.BackgroundTransparency = 0.15
	toastToken += 1
	local myToken = toastToken
	task.delay(2.5, function()
		if toastToken == myToken then
			toast.BackgroundTransparency = 1
			toast.Text = ""
		end
	end)
end

PlacementController.onRejected = function(reason: string?)
	showToast(reason or "Can't build there")
end

-- ── placement controls bar (bottom center, only while placing) ───
local controls = Instance.new("Frame")
controls.Name = "PlacementControls"
controls.AnchorPoint = Vector2.new(0.5, 1)
controls.Position = UDim2.new(0.5, 0, 1, -24)
controls.Size = UDim2.new(0, 320, 0, 40)
controls.BackgroundColor3 = Color3.fromRGB(25, 28, 34)
controls.BackgroundTransparency = 0.1
controls.Visible = false
controls.Parent = gui
local cCorner = Instance.new("UICorner")
cCorner.CornerRadius = UDim.new(0, 8)
cCorner.Parent = controls
local cLayout = Instance.new("UIListLayout")
cLayout.FillDirection = Enum.FillDirection.Horizontal
cLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cLayout.VerticalAlignment = Enum.VerticalAlignment.Center
cLayout.Padding = UDim.new(0, 8)
cLayout.Parent = controls

local rotateBtn = Instance.new("TextButton")
rotateBtn.Size = UDim2.new(0, 150, 0, 28)
rotateBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 75)
rotateBtn.TextColor3 = Color3.new(1, 1, 1)
rotateBtn.Font = Enum.Font.GothamBold
rotateBtn.TextSize = 14
rotateBtn.Text = "\u{21BB} Rotate  (R)"
rotateBtn.Parent = controls
local rCorner = Instance.new("UICorner")
rCorner.CornerRadius = UDim.new(0, 6)
rCorner.Parent = rotateBtn
rotateBtn.Activated:Connect(function()
	PlacementController.rotate()
end)

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(0, 150, 0, 28)
hint.BackgroundTransparency = 1
hint.TextColor3 = Color3.fromRGB(200, 205, 215)
hint.Font = Enum.Font.Gotham
hint.TextSize = 12
hint.Text = "Click to place\nRMB / Esc to cancel"
hint.Parent = controls

PlacementController.onPlacingChanged = function(placing: boolean)
	controls.Visible = placing
end

refreshButtons()
showToast("Pick a building on the right. R rotates, RMB/Esc cancels.")
