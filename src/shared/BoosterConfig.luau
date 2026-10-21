--!strict

return {
	WorldFolderName = "TinyFactoryBoosters",
	-- One drop per player per minute, anywhere on the map, each lasting five minutes.
	SpawnIntervalSeconds = 60,
	MaxActiveDropsPerFactory = 5,
	MaxActiveDropsWorldwide = 30,
	DespawnAfterSeconds = 300,
	MaxLuckDurationSeconds = 120,
	MaxSaleValueDurationSeconds = 120,
	MaxStoredPerType = 99,
	-- Drops land on dry ground anywhere within Radius of the hub, above the waterline and
	-- no higher than the tallest walkable field piece (keeps them off roofs and canopies).
	MapSpawn = { Radius = 340, MinAboveWater = 0.5, MaxAboveFieldTop = 4 },
	LandRaycast = {
		StartHeight = 120,
		Distance = 240,
		PositionAttempts = 32,
		MinimumGroundNormalY = 0.7,
	},
	Fall = {
		DropHeight = 8,
		DurationSeconds = 0.75,
		StartingSize = 0.25,
		LandedSize = 1.3,
		LandingHeight = 0.75,
	},
	Definitions = {
		{ Id = "Coin", DisplayName = "Coins x2.00 · 30s", SpawnWeight = 70, Color = { 255, 218, 76 }, Effect = { Kind = "SaleValue", Multiplier = 2, DurationSeconds = 30 } },
		{ Id = "Luck", DisplayName = "Luck x2.00 · 30s", SpawnWeight = 30, Color = { 207, 176, 240 }, Effect = { Kind = "Luck", Multiplier = 2, DurationSeconds = 30 } },
	},
}
