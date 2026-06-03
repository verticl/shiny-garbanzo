--!strict
--[[
	Hud.client.luau
	------------------------------------------------------------------
	The real game UI, replacing the dev panels. Built from the reference art:
	  - top-left player card (avatar, gold, XP/level bar, aura, population)
	  - a collapsible resources panel
	  - right-side action buttons: Build, Shop, Daily Gift
	  - Build menu: a grid of building cards (placeholder swatches for now —
	    real thumbnails drop in later) that start placement
	  - Shop menu: laid out per the reference; gold packs / Job Fair / military
	    are shells until monetization (Phase 10) and military (Phase 8) land
	  - building context menu (Move / Delete / Upgrade) on selecting a building
	  - placement controls (rotate) while building

	All live numbers come from the server's StatsUpdate snapshot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Buildings = require(ReplicatedStorage.Config.Buildings)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local PlacementController = require(script.Parent.PlacementController)

local C = UITheme.Color
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local XP_PER_LEVEL = 1000

local function titleCase(s: string): string
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- ── root ─────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "MiniKingHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- ── shared little builders ───────────────────────────────────────
local function makeButton(text: string, color: Color3, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.TextColor3 = C.text
	b.Font = UITheme.FontBold
	b.TextSize = 14
	b.Text = text
	b.AutoButtonColor = true
	UITheme.corner(b, 8)
	return b
end

local function label(parent: Instance, text: string, color: Color3, sizePx: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 18)
	l.Font = UITheme.FontMed
	l.TextSize = sizePx
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

-- ════════════════════════════════════════════════════════════════
-- PLAYER CARD (top-left)
-- ════════════════════════════════════════════════════════════════
local card = Instance.new("Frame")
card.Size = UDim2.new(0, 230, 0, 96)
card.Position = UDim2.new(0, 14, 0, 14)
card.BackgroundColor3 = C.panel
card.Parent = gui
UITheme.corner(card, 12)
UITheme.stroke(card, C.stroke, 1)

-- avatar
local avatar = Instance.new("ImageLabel")
avatar.Size = UDim2.new(0, 64, 0, 64)
avatar.Position = UDim2.new(0, 12, 0, 16)
avatar.BackgroundColor3 = C.panelLight
avatar.Parent = card
UITheme.corner(avatar, 10)
task.spawn(function()
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	if ok and content then
		avatar.Image = content
	end
end)

local goldText = Instance.new("TextLabel")
goldText.BackgroundTransparency = 1
goldText.Position = UDim2.new(0, 86, 0, 12)
goldText.Size = UDim2.new(1, -96, 0, 22)
goldText.Font = UITheme.FontBold
goldText.TextSize = 18
goldText.TextColor3 = C.gold
goldText.TextXAlignment = Enum.TextXAlignment.Left
goldText.Text = "0 Gold"
goldText.Parent = card

local auraText = Instance.new("TextLabel")
auraText.BackgroundTransparency = 1
auraText.Position = UDim2.new(0, 86, 0, 34)
auraText.Size = UDim2.new(1, -96, 0, 16)
auraText.Font = UITheme.FontMed
auraText.TextSize = 13
auraText.TextColor3 = C.aura
auraText.TextXAlignment = Enum.TextXAlignment.Left
auraText.Text = "Aura 0   Pop 0/0"
auraText.Parent = card

-- xp bar
local xpBack = Instance.new("Frame")
xpBack.Position = UDim2.new(0, 86, 0, 56)
xpBack.Size = UDim2.new(1, -98, 0, 16)
xpBack.BackgroundColor3 = C.panelLight
xpBack.Parent = card
UITheme.corner(xpBack, 8)
local xpFill = Instance.new("Frame")
xpFill.Size = UDim2.new(0, 0, 1, 0)
xpFill.BackgroundColor3 = C.xp
xpFill.Parent = xpBack
UITheme.corner(xpFill, 8)
local xpText = Instance.new("TextLabel")
xpText.BackgroundTransparency = 1
xpText.Size = UDim2.new(1, 0, 1, 0)
xpText.Font = UITheme.FontBold
xpText.TextSize = 11
xpText.TextColor3 = C.text
xpText.Text = "Lv 1"
xpText.ZIndex = 2
xpText.Parent = xpBack

-- resources toggle
local resToggle = makeButton("Resources \u{25BE}", C.panelLight, UDim2.new(0, 230, 0, 24))
resToggle.Position = UDim2.new(0, 14, 0, 116)
resToggle.TextSize = 13
resToggle.Parent = gui

-- ════════════════════════════════════════════════════════════════
-- RESOURCES PANEL (collapsible)
-- ════════════════════════════════════════════════════════════════
local resPanel = Instance.new("Frame")
resPanel.Size = UDim2.new(0, 230, 0, 300)
resPanel.Position = UDim2.new(0, 14, 0, 146)
resPanel.BackgroundColor3 = C.panel
resPanel.Visible = false
resPanel.Parent = gui
UITheme.corner(resPanel, 12)
UITheme.stroke(resPanel, C.stroke, 1)
UITheme.pad(resPanel, 10)
local resLayout = Instance.new("UIListLayout")
resLayout.Padding = UDim.new(0, 2)
resLayout.Parent = resPanel

local resourceRows: { [string]: TextLabel } = {}
for _, res in ipairs(GameConfig.RESOURCES) do
	resourceRows[res] = label(resPanel, "", C.subtext, 13)
end

resToggle.Activated:Connect(function()
	resPanel.Visible = not resPanel.Visible
	resToggle.Text = resPanel.Visible and "Resources \u{25B4}" or "Resources \u{25BE}"
end)

-- ════════════════════════════════════════════════════════════════
-- RIGHT-SIDE ACTION BUTTONS
-- ════════════════════════════════════════════════════════════════
local actions = Instance.new("Frame")
actions.AnchorPoint = Vector2.new(1, 0.5)
actions.Position = UDim2.new(1, -16, 0.5, 0)
actions.Size = UDim2.new(0, 78, 0, 240)
actions.BackgroundTransparency = 1
actions.Parent = gui
local aLayout = Instance.new("UIListLayout")
aLayout.Padding = UDim.new(0, 12)
aLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
aLayout.Parent = actions

local function actionButton(text: string, color: Color3): TextButton
	local b = makeButton(text, color, UDim2.new(0, 78, 0, 70))
	b.TextSize = 15
	UITheme.stroke(b, Color3.new(1, 1, 1), 1).Transparency = 0.7
	b.Parent = actions
	return b
end

local buildBtn = actionButton("\u{1F528}\nBuild", C.build)
local shopBtn = actionButton("\u{1F3EA}\nShop", C.shop)
local giftBtn = actionButton("\u{1F381}\nDaily", C.gift)

-- ════════════════════════════════════════════════════════════════
-- TOAST
-- ════════════════════════════════════════════════════════════════
local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 16)
toast.Size = UDim2.new(0, 360, 0, 30)
toast.BackgroundColor3 = C.panel
toast.BackgroundTransparency = 1
toast.TextColor3 = C.text
toast.Font = UITheme.FontMed
toast.TextSize = 14
toast.Text = ""
toast.Parent = gui
UITheme.corner(toast, 8)

local toastToken = 0
local function showToast(msg: string)
	toast.Text = msg
	toast.BackgroundTransparency = 0.1
	toastToken += 1
	local mine = toastToken
	task.delay(2.5, function()
		if toastToken == mine then
			toast.BackgroundTransparency = 1
			toast.Text = ""
		end
	end)
end

-- ════════════════════════════════════════════════════════════════
-- OVERLAY MENU SCAFFOLD (shared by Build + Shop)
-- ════════════════════════════════════════════════════════════════
local function makeOverlay(titleText: string): (Frame, Frame)
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = gui

	local window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.new(0.5, 0, 0.5, 0)
	window.Size = UDim2.new(0, 640, 0, 420)
	window.BackgroundColor3 = C.panel
	window.ZIndex = 6
	window.Parent = backdrop
	UITheme.corner(window, 14)
	UITheme.stroke(window, C.stroke, 1)

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Position = UDim2.new(0, 20, 0, 12)
	header.Size = UDim2.new(1, -80, 0, 32)
	header.Font = UITheme.FontBold
	header.TextSize = 26
	header.TextColor3 = C.text
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = titleText
	header.ZIndex = 7
	header.Parent = window

	local close = makeButton("\u{2715}", C.bad, UDim2.new(0, 34, 0, 34))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.ZIndex = 7
	close.Parent = window
	close.Activated:Connect(function()
		backdrop.Visible = false
	end)

	return backdrop, window
end

-- ════════════════════════════════════════════════════════════════
-- BUILD MENU
-- ════════════════════════════════════════════════════════════════
local buildBackdrop, buildWindow = makeOverlay("BUILD")

local buildScroll = Instance.new("ScrollingFrame")
buildScroll.Position = UDim2.new(0, 16, 0, 56)
buildScroll.Size = UDim2.new(1, -32, 1, -72)
buildScroll.BackgroundTransparency = 1
buildScroll.BorderSizePixel = 0
buildScroll.ScrollBarThickness = 6
buildScroll.ZIndex = 7
buildScroll.Parent = buildWindow
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0, 142, 0, 116)
grid.CellPadding = UDim2.new(0, 12, 0, 12)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = buildScroll

-- sorted building ids
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

for _, id in ipairs(ids) do
	local def = Buildings[id]
	local cardBtn = Instance.new("TextButton")
	cardBtn.BackgroundColor3 = C.panelLight
	cardBtn.Text = ""
	cardBtn.AutoButtonColor = true
	cardBtn.ZIndex = 7
	cardBtn.Parent = buildScroll
	UITheme.corner(cardBtn, 10)

	-- placeholder thumbnail swatch (real art later)
	local thumb = Instance.new("Frame")
	thumb.Size = UDim2.new(1, -16, 0, 54)
	thumb.Position = UDim2.new(0, 8, 0, 8)
	thumb.BackgroundColor3 = UITheme.CategoryColor[def.category] or C.stroke
	thumb.ZIndex = 7
	thumb.Parent = cardBtn
	UITheme.corner(thumb, 8)
	local cat = Instance.new("TextLabel")
	cat.BackgroundTransparency = 1
	cat.Size = UDim2.new(1, 0, 1, 0)
	cat.Font = UITheme.FontBold
	cat.TextSize = 12
	cat.TextColor3 = Color3.new(1, 1, 1)
	cat.TextTransparency = 0.25
	cat.Text = def.category
	cat.ZIndex = 8
	cat.Parent = thumb

	local nm = Instance.new("TextLabel")
	nm.BackgroundTransparency = 1
	nm.Position = UDim2.new(0, 8, 0, 66)
	nm.Size = UDim2.new(1, -16, 0, 18)
	nm.Font = UITheme.FontBold
	nm.TextSize = 13
	nm.TextColor3 = C.text
	nm.TextXAlignment = Enum.TextXAlignment.Left
	nm.TextTruncate = Enum.TextTruncate.AtEnd
	nm.Text = def.displayName
	nm.ZIndex = 7
	nm.Parent = cardBtn

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.new(0, 8, 0, 86)
	sub.Size = UDim2.new(1, -16, 0, 16)
	sub.Font = UITheme.FontMed
	sub.TextSize = 11
	sub.TextColor3 = C.subtext
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.ZIndex = 7
	if def.peasants > 0 then
		sub.Text = string.format("%d peasants", def.peasants)
	elseif def.cost then
		sub.Text = "cost varies"
	else
		sub.Text = "no workers"
	end
	sub.Parent = cardBtn

	cardBtn.Activated:Connect(function()
		PlacementController.startPlacing(id)
		buildBackdrop.Visible = false
	end)
end

buildBtn.Activated:Connect(function()
	buildBackdrop.Visible = not buildBackdrop.Visible
end)

-- ════════════════════════════════════════════════════════════════
-- SHOP MENU (shell — items wire up with Phases 8 & 10)
-- ════════════════════════════════════════════════════════════════
local shopBackdrop, shopWindow = makeOverlay("SHOP")

local shopList = Instance.new("ScrollingFrame")
shopList.Position = UDim2.new(0, 16, 0, 56)
shopList.Size = UDim2.new(1, -32, 1, -72)
shopList.BackgroundTransparency = 1
shopList.BorderSizePixel = 0
shopList.ScrollBarThickness = 6
shopList.ZIndex = 7
shopList.Parent = shopWindow
local shopLayout = Instance.new("UIListLayout")
shopLayout.Padding = UDim.new(0, 10)
shopLayout.Parent = shopList

local SHOP_ITEMS = {
	{ name = "Small Bag of Gold", desc = "+100 Gold", tag = "Robux (Phase 10)" },
	{ name = "Big Bag of Gold", desc = "+250 Gold", tag = "Robux (Phase 10)" },
	{ name = "Treasure Chest", desc = "+600 Gold", tag = "Robux (Phase 10)" },
	{ name = "Job Fair", desc = "+10% faster population growth for 2 hrs", tag = "Coming soon" },
	{ name = "Knights", desc = "+10 mounted knights", tag = "Needs military (Phase 8)" },
	{ name = "Infantry", desc = "+20 spearmen", tag = "Needs military (Phase 8)" },
	{ name = "Bowmen", desc = "+20 bowmen", tag = "Needs military (Phase 8)" },
}

for _, item in ipairs(SHOP_ITEMS) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 56)
	row.BackgroundColor3 = C.panelLight
	row.ZIndex = 7
	row.Parent = shopList
	UITheme.corner(row, 10)
	UITheme.pad(row, 10)

	local nm = Instance.new("TextLabel")
	nm.BackgroundTransparency = 1
	nm.Size = UDim2.new(0.6, 0, 0.5, 0)
	nm.Font = UITheme.FontBold
	nm.TextSize = 15
	nm.TextColor3 = C.text
	nm.TextXAlignment = Enum.TextXAlignment.Left
	nm.Text = item.name
	nm.ZIndex = 8
	nm.Parent = row

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.new(0, 0, 0.5, 0)
	desc.Size = UDim2.new(0.7, 0, 0.5, 0)
	desc.Font = UITheme.FontMed
	desc.TextSize = 12
	desc.TextColor3 = C.subtext
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Text = item.desc
	desc.ZIndex = 8
	desc.Parent = row

	local buy = makeButton(item.tag, C.stroke, UDim2.new(0, 150, 0, 30))
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, 0, 0.5, 0)
	buy.TextSize = 11
	buy.ZIndex = 8
	buy.Parent = row
	buy.Activated:Connect(function()
		showToast(item.name .. " — not available yet")
	end)
end

shopBtn.Activated:Connect(function()
	shopBackdrop.Visible = not shopBackdrop.Visible
end)

giftBtn.Activated:Connect(function()
	showToast("Daily Gift coming soon")
end)

-- ════════════════════════════════════════════════════════════════
-- BUILDING CONTEXT MENU (on selection)
-- ════════════════════════════════════════════════════════════════
local ctx = Instance.new("Frame")
ctx.AnchorPoint = Vector2.new(0.5, 1)
ctx.Position = UDim2.new(0.5, 0, 1, -90)
ctx.Size = UDim2.new(0, 300, 0, 70)
ctx.BackgroundColor3 = C.panel
ctx.Visible = false
ctx.ZIndex = 4
ctx.Parent = gui
UITheme.corner(ctx, 12)
UITheme.stroke(ctx, C.stroke, 1)

local selectedId: number? = nil

local ctxTitle = Instance.new("TextLabel")
ctxTitle.BackgroundTransparency = 1
ctxTitle.Position = UDim2.new(0, 0, 0, 6)
ctxTitle.Size = UDim2.new(1, 0, 0, 18)
ctxTitle.Font = UITheme.FontBold
ctxTitle.TextSize = 14
ctxTitle.TextColor3 = C.text
ctxTitle.Text = ""
ctxTitle.ZIndex = 5
ctxTitle.Parent = ctx

local ctxRow = Instance.new("Frame")
ctxRow.Position = UDim2.new(0, 10, 0, 28)
ctxRow.Size = UDim2.new(1, -20, 0, 32)
ctxRow.BackgroundTransparency = 1
ctxRow.ZIndex = 5
ctxRow.Parent = ctx
local ctxLayout = Instance.new("UIListLayout")
ctxLayout.FillDirection = Enum.FillDirection.Horizontal
ctxLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
ctxLayout.Padding = UDim.new(0, 8)
ctxLayout.Parent = ctxRow

local moveBtn = makeButton("Move", C.build, UDim2.new(0, 84, 1, 0))
moveBtn.TextSize = 13
moveBtn.ZIndex = 5
moveBtn.Parent = ctxRow
local delBtn = makeButton("Delete", C.bad, UDim2.new(0, 84, 1, 0))
delBtn.TextSize = 13
delBtn.ZIndex = 5
delBtn.Parent = ctxRow
local upBtn = makeButton("Upgrade", C.panelLight, UDim2.new(0, 84, 1, 0))
upBtn.TextSize = 13
upBtn.ZIndex = 5
upBtn.Parent = ctxRow

moveBtn.Activated:Connect(function()
	if selectedId then
		PlacementController.beginMove(selectedId)
	end
end)
delBtn.Activated:Connect(function()
	PlacementController.deleteSelected()
end)
upBtn.Activated:Connect(function()
	showToast("Upgrades coming soon")
end)

PlacementController.onSelectionChanged = function(id: number?)
	selectedId = id
	if id then
		local rec = PlacementController.getRecord(id)
		local def = rec and Buildings[rec.buildingId]
		ctxTitle.Text = def and def.displayName or "Building"
		upBtn.Visible = (def ~= nil) and (def.id ~= "Manor")
		delBtn.Visible = (def == nil) or (def.id ~= "Manor")
		ctx.Visible = true
	else
		ctx.Visible = false
	end
end

-- ════════════════════════════════════════════════════════════════
-- PLACEMENT CONTROLS (rotate, while placing)
-- ════════════════════════════════════════════════════════════════
local controls = Instance.new("Frame")
controls.AnchorPoint = Vector2.new(0.5, 1)
controls.Position = UDim2.new(0.5, 0, 1, -24)
controls.Size = UDim2.new(0, 330, 0, 42)
controls.BackgroundColor3 = C.panel
controls.Visible = false
controls.ZIndex = 4
controls.Parent = gui
UITheme.corner(controls, 10)
UITheme.stroke(controls, C.stroke, 1)
local cLayout = Instance.new("UIListLayout")
cLayout.FillDirection = Enum.FillDirection.Horizontal
cLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cLayout.VerticalAlignment = Enum.VerticalAlignment.Center
cLayout.Padding = UDim.new(0, 10)
cLayout.Parent = controls

local rotateBtn = makeButton("\u{21BB} Rotate (R)", C.good, UDim2.new(0, 150, 0, 30))
rotateBtn.ZIndex = 5
rotateBtn.Parent = controls
rotateBtn.Activated:Connect(function()
	PlacementController.rotate()
end)
local ctrlHint = Instance.new("TextLabel")
ctrlHint.BackgroundTransparency = 1
ctrlHint.Size = UDim2.new(0, 150, 1, 0)
ctrlHint.Font = UITheme.FontMed
ctrlHint.TextSize = 12
ctrlHint.TextColor3 = C.subtext
ctrlHint.Text = "Click to place\nRMB / Esc to cancel"
ctrlHint.ZIndex = 5
ctrlHint.Parent = controls

PlacementController.onPlacingChanged = function(placing: boolean)
	controls.Visible = placing
	if placing then
		ctx.Visible = false
	end
end

PlacementController.onRejected = function(reason: string?)
	showToast(reason or "Can't build there")
end

-- ════════════════════════════════════════════════════════════════
-- LIVE DATA
-- ════════════════════════════════════════════════════════════════
Net.event("StatsUpdate").OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then
		return
	end
	goldText.Text = string.format("%d Gold", data.gold or 0)
	auraText.Text = string.format("Aura %d   Pop %d/%d", data.aura or 0, data.population or 0, data.housingCapacity or 0)

	local xp = tonumber(data.xp) or 0
	local level = math.floor(xp / XP_PER_LEVEL) + 1
	local into = xp % XP_PER_LEVEL
	xpFill.Size = UDim2.new(into / XP_PER_LEVEL, 0, 1, 0)
	xpText.Text = string.format("Lv %d  (%d/%d)", level, into, XP_PER_LEVEL)

	if resPanel.Visible then
		for _, res in ipairs(GameConfig.RESOURCES) do
			local row = resourceRows[res]
			local stock = (data.stock and data.stock[res]) or 0
			local cap = math.floor((data.capacity and data.capacity[res]) or 0)
			if cap > 0 or stock > 0 then
				row.Visible = true
				row.Text = string.format("%-9s %d/%d", titleCase(res), stock, cap)
			else
				row.Visible = false
			end
		end
	end
end)

showToast("Tap Build to start. Click a building to Move/Delete it.")
