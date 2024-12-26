SUBSYSTEM_DEF(pressure)
	name = "Pressure HUD"
	init_order = INIT_ORDER_PRESSURE
	priority = FIRE_PRIORITY_PRESSURE
	wait = 2
	flags = SS_BACKGROUND
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	offline_implications = "Pressure HUD will no longer work."
	cpu_display = SS_CPUDISPLAY_LOW

	var/x = 0
	var/y = 0
	var/z = 1

	var/list/current = list()
	var/list/next = list()
	var/icon/pixel

/datum/controller/subsystem/pressure/Initialize()
	pixel = new('icons/mob/hud/pressure_1.dmi', "blank")

	for(var/origin_z in 1 to world.maxz)
		for(var/origin_y in 0 to (world.maxy - 1) / PRESSURE_HUD_TILE_SIZE)
			for(var/origin_x in 0 to (world.maxx - 1) / PRESSURE_HUD_TILE_SIZE)
				var/turf/origin = locate(1 + origin_x * PRESSURE_HUD_TILE_SIZE, 1 + origin_y * PRESSURE_HUD_TILE_SIZE, origin_z)
				current["[origin.x],[origin.y],[origin.z]"] = origin.setup_pressure_hud()

/datum/controller/subsystem/pressure/get_stat_details()
	return "[cost]"

/datum/controller/subsystem/pressure/get_metrics()
	. = ..()
	var/list/cust = list()
	.["cost"] = cost
	.["custom"] = cust

/datum/controller/subsystem/pressure/fire(resumed = 0)
	var/timer = TICK_USAGE_REAL

	if(!resumed)
		x = 0
		y = 0
		z = 0

	while(z <= world.maxz)
		while(y <=  (world.maxy - 1) / PRESSURE_HUD_TILE_SIZE)
			while(x <= (world.maxx - 1) / PRESSURE_HUD_TILE_SIZE)
				var/turf/origin = locate(1 + x * PRESSURE_HUD_TILE_SIZE, 1 + y * PRESSURE_HUD_TILE_SIZE, 1 + z)
				var/image/screen = origin.hud_list[PRESSURE_HUD]

				var/icon/pressure_icon = new("data/milla/pressure_[x]_[y]_[z].png")
				current["[x],[y],[z]"] = pressure_icon
				screen.icon = pressure_icon
				x++
				if(MC_TICK_CHECK)
					return
			x = 0
			y++
		y = 0
		z++

	cost = TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer)
