--!strict
--[[
	UITheme.luau
	Shared palette, fonts, and tiny helpers so all UI looks consistent.
]]

local UITheme = {}

UITheme.Color = {
	panel = Color3.fromRGB(26, 30, 38),
	panelLight = Color3.fromRGB(40, 46, 56),
	stroke = Color3.fromRGB(70, 78, 92),
	build = Color3.fromRGB(70, 150, 250),
	shop = Color3.fromRGB(235, 150, 60),
	gift = Color3.fromRGB(150, 110, 240),
	gold = Color3.fromRGB(255, 205, 70),
	xp = Color3.fromRGB(160, 100, 240),
	aura = Color3.fromRGB(110, 230, 170),
	good = Color3.fromRGB(90, 210, 140),
	bad = Color3.fromRGB(228, 84, 84),
	text = Color3.fromRGB(240, 243, 250),
	subtext = Color3.fromRGB(165, 172, 186),
}

-- Category swatch colors for placeholder thumbnails (until real art).
UITheme.CategoryColor = {
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

UITheme.FontBold = Enum.Font.GothamBold
UITheme.FontMed = Enum.Font.GothamMedium

function UITheme.corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function UITheme.pad(parent: Instance, p: number)
	local u = Instance.new("UIPadding")
	u.PaddingTop = UDim.new(0, p)
	u.PaddingBottom = UDim.new(0, p)
	u.PaddingLeft = UDim.new(0, p)
	u.PaddingRight = UDim.new(0, p)
	u.Parent = parent
end

function UITheme.stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
	return s
end

return UITheme
