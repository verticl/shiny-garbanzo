--!strict
--[[
	GameConfig.luau
	------------------------------------------------------------------
	Global tunables and game-wide constants. Anything that isn't tied
	to a single building lives here so designers can balance in one place.

	NOTE ON TIME SCALE: the design doc states peasant consumption "per day"
	and storage as "1 hour of production". We need to decide whether a
	"day" means a real-world day or a compressed game-day. This is one of
	the open balance questions (see README). Values below assume REAL time
	for now and are easy to swap once we lock the time model.
]]

local GameConfig = {}

-- ── World ────────────────────────────────────────────────────────
GameConfig.MAP_SIZE = 5000 -- studs per side (5000 x 5000)
GameConfig.TILE_SIZE = 4 -- studs per tile edge  (TODO: confirm with art/character scale)

-- Temporary flat build plot for testing the placement system.
-- The real 5000x5000 world (full map = MAP_SIZE / TILE_SIZE tiles) is Phase 7.
GameConfig.TEST_PLOT_TILES = 100

-- Two outcroppings spawn near opposite corners: one Stone mine, one Diamond mine.
GameConfig.RESOURCE_NODES = {
	{ type = "stone", quarry = "StoneQuarry" },
	{ type = "diamond", quarry = "DiamondQuarry" },
}

-- ── Resources & currencies ───────────────────────────────────────
GameConfig.FOOD_TYPES = { "bread", "fruit", "veggies", "meat" } -- diversity feeds Aura
GameConfig.MATERIALS = { "lumber", "stone", "diamond" }
GameConfig.LIVESTOCK = { "cow", "sheep", "horse" }
GameConfig.CURRENCY = "gold" -- the only thing that can't be produced; bought w/ Robux or earned by selling/raiding

-- Every storable/trackable resource (everything except gold + xp, which are tracked separately).
GameConfig.RESOURCES = {
	"wheat", "bread", "fruit", "veggies", "meat", -- crops + food
	"cow", "sheep", "horse", -- livestock
	"clothes", -- clothing
	"lumber", "stone", "diamond", -- materials
}

-- ── Peasants ─────────────────────────────────────────────────────
-- All consumption is normalised to PER MINUTE (no "days" in the economy).
-- Day/night is purely visual (see GameConfig.DayNight) and does not gate any
-- of these rates.
GameConfig.Peasant = {
	FOOD_PER_MIN = 0.5 / 60, -- was "0.5T per day" -> 0.5 per 60 min
	CLOTHING_PER_MIN = 0.1 / 300, -- was "0.1T per 5 days" -> 0.1 per 300 min
	-- A peasant needs: a home slot + food + clothing.
	-- Job-fill priority when peasants move in:
	JOB_PRIORITY = { "Farm", "Producer", "Quarry", "Stable", "Military" },
	-- When needs aren't met, peasants leave in this order (soldiers first, wheat farmers last):
	EVICTION_ORDER = { "Military", "Stable", "Quarry", "Producer", "Farm" },
}

GameConfig.HOUSE_DEFAULT_CAPACITY = 4

-- ── Population ───────────────────────────────────────────────────
GameConfig.Population = {
	STARTING = 5, -- peasants that arrive with the King's carriages (bootstraps first farms)
	STUB_AURA = 75, -- placeholder Aura until Phase 6 computes it for real (drives move-in speed)
	STARVE_SECONDS_PER_LOSS = 4, -- when food runs out, lose one peasant per this many seconds
	MANOR_HOUSING = 5, -- the royal household; lets starting peasants live before Houses exist

	-- *** POPULATION GROWTH RATE DIAL ***
	-- New residents per minute at 100 Aura. Move-in scales linearly with Aura
	-- (so at this default: 100 Aura -> 1 per 5 min, 50 Aura -> 1 per 10 min).
	-- Raise this to make population arrive faster across the board.
	MOVE_IN_PER_MIN_AT_100_AURA = 10,
}

-- ── Camera ───────────────────────────────────────────────────────
-- Start zoomed well back to sell the "mini" scale; player can still zoom freely.
GameConfig.Camera = {
	DEFAULT_ZOOM = 85, -- studs the camera sits back on spawn
	MIN_ZOOM = 4,
	MAX_ZOOM = 320,
}

-- ── Aura (0–100) ─────────────────────────────────────────────────
-- Move-in cadence scales linearly with Aura, anchored by
-- Population.MOVE_IN_PER_MIN_AT_100_AURA. Returns seconds between move-ins
-- (or nil if none happen).
function GameConfig.moveInInterval(aura: number): number?
	if aura <= 0 then
		return nil
	end
	local ratePerMin = GameConfig.Population.MOVE_IN_PER_MIN_AT_100_AURA * (aura / 100)
	if ratePerMin <= 0 then
		return nil
	end
	return 60 / ratePerMin
end

-- Aura's downstream multipliers. These are PLACEHOLDER curves — the doc
-- says "higher aura = % increase/decrease" without exact magnitudes (TODO).
GameConfig.Aura = {
	-- military strength multiplier (HP & DPS): +0% at 0 aura, +50% at 100
	militaryMultiplier = function(aura: number): number
		return 1 + (aura / 100) * 0.5
	end,
	-- cost-of-goods multiplier: -0% at 0 aura, -25% at 100
	costMultiplier = function(aura: number): number
		return 1 - (aura / 100) * 0.25
	end,
	-- low-aura threshold below which NPC villages may attack first
	HOSTILE_THRESHOLD = 50,
}

-- ── Storage multipliers ──────────────────────────────────────────
-- Effective capacity = base * (1 + Σ silo bonuses + Σ warehouse bonuses)
GameConfig.Storage = {
	SILO_BONUS = 0.20, -- +20% per silo
	SILO_UPGRADE_BONUS = 0.10, -- +10% per upgrade level
	WAREHOUSE_BONUS = 0.30, -- +30% per warehouse
	WAREHOUSE_UPGRADE_BONUS = 0.15, -- +15% per upgrade level
}

-- ── Economy ──────────────────────────────────────────────────────
-- The "alive" dials. Production runs continuously: every TICK_RATE seconds
-- buildings accrue a fraction of their per-minute rate, so counters climb
-- smoothly instead of dumping in batches.
GameConfig.Economy = {
	TICK_RATE = 1, -- seconds between economy ticks (lower = smoother)
	STARTING_GOLD = 500, -- the King's starting carriage of gold

	-- The carriages also arrive with some food so the starting peasants don't
	-- starve before the first farm is up. Add any resource key here.
	STARTING_STOCK = {
		bread = 15,
		meat = 10,
	},

	-- Always-available storage floor for EVERY resource, even with no buildings
	-- (think baskets/carts). Lets starting supplies + early production persist
	-- before you've placed a Manor or storage. Set to 0 for strict storage.
	BASE_STORAGE_PER_RESOURCE = 50,

	-- Manor adds this much storage capacity to EVERY resource, on top of the base.
	MANOR_STORAGE_PER_RESOURCE = 100,

	-- Producers (Butcher/Baker/Tailor) consume input and emit output at a 1:1
	-- ratio by default; tune per-feel later.
	PRODUCER_INPUT_PER_OUTPUT = 1,

	-- Once the population loop (Phase 4) is live, buildings scale output by the
	-- ratio of assigned workers to required. Set true to debug at full output.
	ASSUME_FULL_STAFFING = false,

	-- XP feel: keep it ticking alongside production.
	XP_PER_RESOURCE_UNIT = 1, -- xp per unit of raw resource produced
	XP_PER_BUILDING_PLACED = 50, -- flat xp per building (TODO: per-building values)
	XP_PER_PEASANT_ADDED = 10, -- xp when a peasant moves in
}

-- ── Day / night (cosmetic only) ──────────────────────────────────
GameConfig.DayNight = {
	ENABLED = true,
	CYCLE_MINUTES = 20, -- real minutes for a full day->night->day loop
	START_CLOCK = 9, -- clock hour to start at (morning)
}

-- ── XP / progression ─────────────────────────────────────────────
GameConfig.XP = {
	TOWERS_PER_MILLION_XP = 4, -- tower cap scales with XP
}

-- ── Building lifecycle rules ─────────────────────────────────────
GameConfig.DESTROY_GRACE_PERIOD = 300 -- seconds before destroyed housing reduces population

return GameConfig
