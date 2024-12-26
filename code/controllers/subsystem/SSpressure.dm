SUBSYSTEM_DEF(pressure)
	name = "Pressure HUD"
	init_order = INIT_ORDER_PRESSURE
	priority = FIRE_PRIORITY_PRESSURE
	wait = 2
	flags = SS_BACKGROUND
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	offline_implications = "Pressure HUD will no longer work."
	cpu_display = SS_CPUDISPLAY_LOW

	var/x = 1
	var/y = 1
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
		x = 1
		y = 1
		z = 1

		for(var/origin_z in 1 to world.maxz)
			for(var/origin_y in 0 to (world.maxy - 1) / PRESSURE_HUD_TILE_SIZE)
				for(var/origin_x in 0 to (world.maxx - 1) / PRESSURE_HUD_TILE_SIZE)
					var/icon/canvas = new('icons/effects/effects.dmi', "white")
					var/turf/origin = locate(1 + origin_x * PRESSURE_HUD_TILE_SIZE, 1 + origin_y * PRESSURE_HUD_TILE_SIZE, origin_z)
					next["[origin.x],[origin.y],[origin.z]"] = canvas

	var/datum/atom_hud/data/pressure/hud = GLOB.huds[DATA_HUD_PRESSURE]
	while(z <= world.maxz)
		var/icon/canvas = next[pressure_hud_origin_key(x, y, z)]
		while(y <= world.maxy)
			if(y % PRESSURE_HUD_TILE_SIZE == 1)
				canvas = next[pressure_hud_origin_key(x, y, z)]
			while(x <= world.maxx)
				if(x % PRESSURE_HUD_TILE_SIZE == 1)
					canvas = next[pressure_hud_origin_key(x, y, z)]
				// Set the turf's pixel in the next tick's image.
				set_pixel(canvas, locate(x, y, z))
				x++
				if(MC_TICK_CHECK)
					return
			x = 1
			y++

		// Next tick's image is done, copy it onto the HUD.
		for(var/origin_y in 0 to (world.maxy - 1) / PRESSURE_HUD_TILE_SIZE)
			for(var/origin_x in 0 to (world.maxx - 1) / PRESSURE_HUD_TILE_SIZE)
				var/turf/origin = locate(1 + origin_x * PRESSURE_HUD_TILE_SIZE, 1 + origin_y * PRESSURE_HUD_TILE_SIZE, z)
				hud.remove_from_hud(origin)
				var/image/screen = origin.hud_list[PRESSURE_HUD]
				screen.icon = next["[origin.x],[origin.y],[origin.z]"]
				current["[origin.x],[origin.y],[origin.z]"] = screen.icon
				hud.add_to_hud(origin)

		y = 1
		z++

	cost = TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer)

/// Colors a single pixel in the next tick of the pressure HUD.
/datum/controller/subsystem/pressure/proc/set_pixel(icon/canvas, turf/T)
	var/datum/gas_mixture/air = T.get_readonly_air()
	var/ratio = min(1, air.return_pressure() / ONE_ATMOSPHERE)
	canvas.DrawBox(rgb(255 * (1 - ratio), 0, 255 * ratio), (T.x - 1) % PRESSURE_HUD_TILE_SIZE + 1, (T.y - 1) % PRESSURE_HUD_TILE_SIZE + 1)

/datum/controller/subsystem/pressure/proc/pressure_hud_origin_key(tile_x, tile_y, tile_z)
	return "[PRESSURE_HUD_COORD(tile_x)],[PRESSURE_HUD_COORD(tile_y)],[tile_z]"
