--!strict
--[[
	Buildings.luau
	------------------------------------------------------------------
	Single source of truth for every placeable building in Mini-King.
	All numbers are pulled directly from the design doc. Where the doc
	left something undefined, the field is marked  TODO  so we never
	silently ship a guessed value.

	Conventions
	-----------
	footprint   = { width, depth } in TILES (see GameConfig.TILE_SIZE for studs)
	peasants    = workers required to run the building at 100% output
	ratePerMin  = production normalised to per-minute (raw doc value kept in comment)
	storage     = BASE internal capacity of the building's own product
	              (Silos / Warehouses multiply this — see GameConfig)
	maxCount    = build limit per player (nil = unlimited)
	cost        = { lumber, stone, gold }  -- TODO: doc does not define these yet

	Resource keys used across the game:
	  wheat, bread, fruit, veggies, meat        (food chain)
	  cow, sheep, horse                          (livestock)
	  clothes                                    (clothing)
	  lumber, stone, diamond, gold               (materials / currency)
]]

export type Category = "Manor" | "Housing" | "Farm" | "Stable" | "Producer"
	| "Quarry" | "Storage" | "Military" | "Defense"

export type Production = {
	input: string?, -- resource consumed (producers/processors); nil if harvested
	output: string, -- resource produced
	ratePerMin: number, -- normalised production rate
}

export type Building = {
	id: string,
	displayName: string,
	category: Category,
	footprint: { number }, -- { width, depth } in tiles
	peasants: number,
	production: Production?,
	storage: { resource: string, amount: number }?,
	maxCount: number?,
	requiresDiscovery: boolean?, -- must be unlocked by exploring the map
	prerequisite: string?, -- human-readable build gate
	notes: string?,
	cost: { lumber: number, stone: number, gold: number }?, -- TODO: define
}

local Buildings: { [string]: Building } = {

	-----------------------------------------------------------------
	-- MANOR
	-----------------------------------------------------------------
	Manor = {
		id = "Manor",
		displayName = "Manor",
		category = "Manor",
		footprint = { 6, 6 }, -- 36 tiles
		peasants = 0,
		-- Stores gold + 1 hour of production from ALL buildings (see EconomySystem).
		-- Upgrades increase internal storage and hitpoints.
		maxCount = 1,
		notes = "Cannot be destroyed. Upgrades require XP + Aura thresholds (TODO).",
		cost = nil, -- starter building, placed during onboarding
	},

	-----------------------------------------------------------------
	-- HOUSING
	-----------------------------------------------------------------
	House = {
		id = "House",
		displayName = "House",
		category = "Housing",
		footprint = { 2, 2 }, -- 4 tiles
		peasants = 0,
		-- Default 4 residents; upgrades increase capacity.
		notes = "Default capacity 4. Aura governs move-in speed (see GameConfig).",
		cost = nil, -- TODO
	},

	-----------------------------------------------------------------
	-- FARMS  (harvest is automatic & non-destructive)
	-----------------------------------------------------------------
	WheatFarm = {
		id = "WheatFarm",
		displayName = "Wheat Farm",
		category = "Farm",
		footprint = { 6, 10 }, -- 60 tiles
		peasants = 10,
		production = { output = "wheat", ratePerMin = 12 }, -- 12 / min
		storage = { resource = "wheat", amount = 200 },
		cost = nil, -- TODO
	},
	FruitFarm = {
		id = "FruitFarm",
		displayName = "Fruit Farm (Orchard)",
		category = "Farm",
		footprint = { 10, 10 }, -- 100 tiles
		peasants = 8,
		production = { output = "fruit", ratePerMin = 15 }, -- 15 / min
		storage = { resource = "fruit", amount = 200 },
		cost = nil, -- TODO
	},
	VeggieFarm = {
		id = "VeggieFarm",
		displayName = "Veggie Farm",
		category = "Farm",
		footprint = { 4, 10 }, -- 40 tiles
		peasants = 6,
		production = { output = "veggies", ratePerMin = 12 }, -- 12 / min
		storage = { resource = "veggies", amount = 240 },
		cost = nil, -- TODO
	},
	TreeFarm = {
		id = "TreeFarm",
		displayName = "Tree Farm",
		category = "Farm",
		footprint = { 20, 10 }, -- 200 tiles
		peasants = 20,
		production = { output = "lumber", ratePerMin = 4 }, -- 20 / 5 min
		storage = { resource = "lumber", amount = 100 },
		cost = nil, -- TODO
	},

	-----------------------------------------------------------------
	-- STABLES  (harvest is automatic)
	-----------------------------------------------------------------
	CattleStable = {
		id = "CattleStable",
		displayName = "Cattle Stable",
		category = "Stable",
		footprint = { 4, 4 }, -- 16 tiles
		peasants = 4,
		production = { output = "cow", ratePerMin = 2.2 }, -- 11 / 5 min
		storage = { resource = "cow", amount = 6 },
		notes = "Cows feed the Butcher for meat.",
		cost = nil, -- TODO
	},
	SheepStable = {
		id = "SheepStable",
		displayName = "Sheep Stable",
		category = "Stable",
		footprint = { 3, 4 }, -- 12 tiles
		peasants = 6,
		production = { output = "sheep", ratePerMin = 13 / 3 }, -- 13 / 3 min
		storage = { resource = "sheep", amount = 10 },
		notes = "Sheep feed the Tailor for clothes.",
		cost = nil, -- TODO
	},
	HorseStable = {
		id = "HorseStable",
		displayName = "Horse Stable",
		category = "Stable",
		footprint = { 4, 5 }, -- 20 tiles
		peasants = 4,
		production = { output = "horse", ratePerMin = 1 / 7 }, -- 1 / 7 min
		storage = { resource = "horse", amount = 4 },
		notes = "Horses are required for Knights. No external storage — Silos/Warehouses do NOT apply.",
		cost = nil, -- TODO
	},

	-----------------------------------------------------------------
	-- PRODUCERS  (process stored livestock/crops into finished goods)
	-----------------------------------------------------------------
	Butcher = {
		id = "Butcher",
		displayName = "Butcher",
		category = "Producer",
		footprint = { 2, 2 }, -- 4 tiles
		peasants = 2,
		production = { input = "cow", output = "meat", ratePerMin = 2 }, -- 2 / min
		storage = { resource = "meat", amount = 100 },
		cost = nil, -- TODO
	},
	Baker = {
		id = "Baker",
		displayName = "Baker",
		category = "Producer",
		footprint = { 2, 2 }, -- 4 tiles
		peasants = 2,
		production = { input = "wheat", output = "bread", ratePerMin = 2 }, -- 2 / min
		storage = { resource = "bread", amount = 50 },
		cost = nil, -- TODO
	},
	Tailor = {
		id = "Tailor",
		displayName = "Tailor",
		category = "Producer",
		footprint = { 2, 2 }, -- 4 tiles
		peasants = 2,
		production = { input = "sheep", output = "clothes", ratePerMin = 3 }, -- 3 / min
		storage = { resource = "clothes", amount = 30 },
		cost = nil, -- TODO
	},

	-----------------------------------------------------------------
	-- QUARRIES  (must be discovered; placed only on the matching node)
	-----------------------------------------------------------------
	StoneQuarry = {
		id = "StoneQuarry",
		displayName = "Stone Quarry",
		category = "Quarry",
		footprint = { 4, 4 }, -- 16 tiles
		peasants = 12,
		production = { output = "stone", ratePerMin = 3 }, -- 15 / 5 min
		storage = { resource = "stone", amount = 90 },
		requiresDiscovery = true,
		prerequisite = "Place on a discovered Stone mine outcropping.",
		cost = nil, -- TODO
	},
	DiamondQuarry = {
		id = "DiamondQuarry",
		displayName = "Diamond Quarry",
		category = "Quarry",
		footprint = { 5, 4 }, -- 20 tiles
		peasants = 14,
		production = { output = "diamond", ratePerMin = 2 }, -- 10 / 5 min
		storage = { resource = "diamond", amount = 60 },
		requiresDiscovery = true,
		prerequisite = "Place on a discovered Diamond mine outcropping.",
		cost = nil, -- TODO
	},

	-----------------------------------------------------------------
	-- STORAGE  (multiply every building's own-product capacity)
	-----------------------------------------------------------------
	Silo = {
		id = "Silo",
		displayName = "Silo",
		category = "Storage",
		footprint = { 2, 2 }, -- 4 tiles
		peasants = 0,
		maxCount = 6,
		notes = "+20% internal storage to all buildings; upgrade adds +10%.",
		cost = nil, -- TODO
	},
	Warehouse = {
		id = "Warehouse",
		displayName = "Warehouse",
		category = "Storage",
		footprint = { 4, 6 }, -- 24 tiles
		peasants = 0,
		maxCount = 2,
		notes = "+30% internal storage to all buildings; upgrade adds +15%.",
		cost = nil, -- TODO
	},

	-----------------------------------------------------------------
	-- MILITARY  (no capacity limit; convert spare peasants into units)
	-----------------------------------------------------------------
	InfantryBarracks = {
		id = "InfantryBarracks",
		displayName = "Infantry Barracks",
		category = "Military",
		footprint = { 6, 7 }, -- 42 tiles
		peasants = 0,
		production = { output = "spearman", ratePerMin = 2 }, -- 2 / min
		maxCount = 1,
		notes = "Upgrades buff HP + DPS of ALL soldiers. 3 levels, then XP+Aura gated (TODO).",
		cost = nil, -- TODO
	},
	BowmenBarracks = {
		id = "BowmenBarracks",
		displayName = "Bowmen Barracks",
		category = "Military",
		footprint = { 4, 10 }, -- 40 tiles
		peasants = 0,
		production = { output = "bowman", ratePerMin = 1 }, -- 1 / min
		maxCount = 1,
		notes = "Upgrades buff HP + DPS of ALL soldiers. 3 levels, then XP+Aura gated (TODO).",
		cost = nil, -- TODO
	},
	KnightBarracks = {
		id = "KnightBarracks",
		displayName = "Knight Barracks",
		category = "Military",
		footprint = { 6, 8 }, -- 48 tiles
		peasants = 0,
		production = { output = "knight", ratePerMin = 0.2 }, -- 1 / 5 min
		maxCount = 1,
		prerequisite = "Requires 100 Spearmen and 40 Bowmen trained.",
		notes = "Knights consume horses. Upgrades buff HP + DPS of ALL soldiers.",
		cost = nil, -- TODO
	},

	-----------------------------------------------------------------
	-- DEFENSE
	-----------------------------------------------------------------
	Tower = {
		id = "Tower",
		displayName = "Tower",
		category = "Defense",
		footprint = { 3, 3 }, -- 9 tiles
		peasants = 0,
		-- maxCount is dynamic: 4 towers per 1,000,000 XP (handled in code, not a flat cap)
		notes = "Cap = 4 per 1,000,000 XP. Upgrades buff HP + DPS per individual tower.",
		cost = nil, -- TODO
	},
	Wall = {
		id = "Wall",
		displayName = "Wall",
		category = "Defense",
		footprint = { 1, 10 }, -- 10 tiles
		peasants = 0,
		notes = "Upgrades increase strength (HP).",
		cost = nil, -- TODO
	},
}

return Buildings
