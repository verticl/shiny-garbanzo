--!strict
--[[
	Net.luau
	Central definition + accessor for all client/server remotes.
	On the server, requiring this creates the remotes under
	ReplicatedStorage/Remotes. On the client it waits for them.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENTS = {
	-- client -> server (requests)
	"PlaceBuilding",
	"MoveBuilding",
	"DeleteBuilding",
	-- server -> client (confirmations / state changes)
	"BuildingPlaced",
	"BuildingMoved",
	"BuildingRemoved",
	"ActionRejected",
	"StatsUpdate", -- server -> client: live economy snapshot (gold/xp/stock/capacity/pop)
}

local FUNCTIONS = {
	"RequestState", -- client asks server for its current buildings on join
}

local Net = {}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(EVENTS) do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
	for _, name in ipairs(FUNCTIONS) do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.fn(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Net
