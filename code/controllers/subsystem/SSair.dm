#define SSAIR_DEFERREDPIPENETS 1
#define SSAIR_PIPENETS 2
#define SSAIR_ATMOSMACHINERY 3
#define SSAIR_INTERESTING_TILES 4
#define SSAIR_HOTSPOTS 5
#define SSAIR_BOUND_MIXTURES 6
#define SSAIR_MILLA_TICK 7
#define SSAIR_SUPERCONDUCTIVITY 8

SUBSYSTEM_DEF(air)
	name = "Atmospherics"
	init_order = INIT_ORDER_AIR
	priority = FIRE_PRIORITY_AIR
	wait = 5
	flags = SS_BACKGROUND
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	offline_implications = "Turfs will no longer process atmos, and all atmospheric machines (including cryotubes) will no longer function. Shuttle call recommended."
	cpu_display = SS_CPUDISPLAY_HIGH

	/// The cost of a pass through bound gas mixtures, shown in SS Info's C block as BM.
	var/datum/resumable_cost_counter/cost_bound_mixtures = new()
	/// The cost of a MILLA tick in ms, shown in SS Info's C block as MT.
	var/cost_milla_tick = 0
	/// The cost of a pass through interesting tiles, shown in SS Info's C block as IT.
	var/datum/resumable_cost_counter/cost_interesting_tiles = new()
	/// The cost of a pass through hotspots, shown in SS Info's C block as HS.
	var/datum/resumable_cost_counter/cost_hotspots = new()
	/// The cost of a pass through pipenets, shown in SS Info's C block as PN.
	var/datum/resumable_cost_counter/cost_pipenets = new()
	/// The cost of a pass through building pipenets, shown in SS Info's C block as DPN.
	var/datum/resumable_cost_counter/cost_pipenets_to_build = new()
	/// The cost of a pass through atmos machinery, shown in SS Info's C block as AM.
	var/datum/resumable_cost_counter/cost_atmos_machinery = new()

	/// The set of current bound mixtures. Shown in SS Info as BM:x+y, where x is the length at the start of the most recent processing, and y is the number of mixtures that have been added during processing.
	var/list/bound_mixtures = list()
	/// The original length of bound_mixtures.
	var/original_bound_mixtures = 0
	/// The number of bound mixtures we saw when we last stopped processing them.
	var/last_bound_mixtures = 0
	/// The number of bound mixtures that were added during this processing cycle.
	var/added_bound_mixtures = 0
	/// The length of the most recent interesting tiles list, shown in SS Info as IT.
	var/interesting_tile_count = 0
	/// The set of current active hotspots. Length shown in SS Info as HS.
	var/list/hotspots = list()
	/// The set of pipenets that need to be built. Length shown in SS Info as PTB.
	var/list/pipenets_to_build = list()
	/// The set of active pipenets. Length shown in SS Info as PN.
	var/list/pipenets = list()
	/// The set of active atmos machinery. Length shown in SS Info as AM.
	var/list/atmos_machinery = list()

	/// A list of atmos machinery to set up in Initialize.
	var/list/machinery_to_construct = list()

	/// Pipe overlay/underlay icon manager
	var/datum/pipe_icon_manager/icon_manager

	/// An arbitrary list of stuff currently being processed.
	var/list/currentrun = list()

	/// Which step we're currently on, used to let us resume if our time budget elapses.
	var/currentpart = SSAIR_DEFERREDPIPENETS

	/// Tracks how many MILLA ticks we've run. Used to safely run Interesting Tiles, and to track whether bound gas mixtures have read their MILLA value this tick.
	var/milla_ticks = 0

/// A cost counter for resumable, repeating processes.
/datum/resumable_cost_counter
	var/last_complete_ms = 0
	var/ongoing_ms = 0

/// Updates the counter based on the time spent making progress and whether we finished the task.
/datum/resumable_cost_counter/proc/record_progress(cost_ms, finished)
	if(finished)
		last_complete_ms = ongoing_ms + cost_ms
		ongoing_ms = 0
	else
		ongoing_ms += cost_ms

/// Gets a display string for this cost counter.
/datum/resumable_cost_counter/proc/to_string()
	if(ongoing_ms > last_complete_ms)
		// We're in the middle of a task that's already longer than the prior one took in total, report the in-progress time instead, but mark that it's still incomplete with a +
		return "[round(ongoing_ms, 1)]+"
	return "[round(last_complete_ms, 1)]"

/datum/controller/subsystem/air/get_stat_details()
	var/list/msg = list()
	msg += "C:{"
	msg += "BM:[cost_bound_mixtures.to_string()]|"
	msg += "MT:[round(cost_milla_tick,1)]|"
	msg += "IT:[cost_interesting_tiles.to_string()]|"
	msg += "HS:[cost_hotspots.to_string()]|"
	msg += "PN:[cost_pipenets.to_string()]|"
	msg += "PTB:[cost_pipenets_to_build.to_string()]|"
	msg += "AM:[cost_atmos_machinery.to_string()]"
	msg += "} "
	msg += "BM:[original_bound_mixtures]+[added_bound_mixtures]|"
	msg += "IT:[interesting_tile_count]|"
	msg += "HS:[length(hotspots)]|"
	msg += "PN:[length(pipenets)]|"
	msg += "AM:[length(atmos_machinery)]|"
	return msg.Join("")

/datum/controller/subsystem/air/get_metrics()
	. = ..()
	var/list/cust = list()
	cust["hotspots"] = length(hotspots)
	.["custom"] = cust

/datum/controller/subsystem/air/Initialize()
	setup_overlays() // Assign icons and such for gas-turf-overlays
	icon_manager = new() // Sets up icon manager for pipes
	setup_allturfs()
	setup_atmos_machinery(GLOB.machines)
	setup_pipenets(GLOB.machines)
	for(var/obj/machinery/atmospherics/A in machinery_to_construct)
		A.initialize_atmos_network()

/datum/controller/subsystem/air/Recover()
	hotspots = SSair.hotspots
	pipenets_to_build = SSair.pipenets_to_build
	pipenets = SSair.pipenets
	atmos_machinery = SSair.atmos_machinery
	machinery_to_construct = SSair.machinery_to_construct
	icon_manager = SSair.icon_manager
	currentrun = SSair.currentrun
	currentpart = SSair.currentpart

/datum/controller/subsystem/air/fire(resumed = 0)
	var/timer = TICK_USAGE_REAL

	if(currentpart == SSAIR_DEFERREDPIPENETS || !resumed)
		build_pipenets(resumed)
		cost_pipenets_to_build.record_progress(TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer), state == SS_RUNNING)
		if(state != SS_RUNNING)
			return
		resumed = 0
		currentpart = SSAIR_PIPENETS

	if(currentpart == SSAIR_PIPENETS || !resumed)
		process_pipenets(resumed)
		cost_pipenets.record_progress(TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer), state == SS_RUNNING)
		if(state != SS_RUNNING)
			return
		resumed = 0
		currentpart = SSAIR_ATMOSMACHINERY

	if(currentpart == SSAIR_ATMOSMACHINERY)
		timer = TICK_USAGE_REAL
		process_atmos_machinery(resumed)
		cost_atmos_machinery.record_progress(TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer), state == SS_RUNNING)
		if(state != SS_RUNNING)
			return
		resumed = 0
		currentpart = SSAIR_INTERESTING_TILES

	if(currentpart == SSAIR_INTERESTING_TILES)
		timer = TICK_USAGE_REAL
		// We gate this on a MILLA tick happening, so that both buffers have
		// been initialized.
		if(milla_ticks > 0)
			process_interesting_tiles(resumed)
		cost_interesting_tiles.record_progress(TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer), state == SS_RUNNING)
		if(state != SS_RUNNING)
			return
		resumed = 0
		currentpart = SSAIR_HOTSPOTS

	if(currentpart == SSAIR_HOTSPOTS)
		timer = TICK_USAGE_REAL
		process_hotspots(resumed)
		cost_hotspots.record_progress(TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer), state == SS_RUNNING)
		if(state != SS_RUNNING)
			return
		resumed = 0
		currentpart = SSAIR_BOUND_MIXTURES

	if(currentpart == SSAIR_BOUND_MIXTURES)
		timer = TICK_USAGE_REAL
		process_bound_mixtures(resumed)
		cost_bound_mixtures.record_progress(TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer), state == SS_RUNNING)
		if(state != SS_RUNNING)
			return
		resumed = 0
		currentpart = SSAIR_MILLA_TICK

	if(currentpart == SSAIR_MILLA_TICK)
		timer = TICK_USAGE_REAL
		spawn_milla_tick_thread()
		milla_ticks++
		cost_milla_tick = TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer)
		if(state != SS_RUNNING)
			return
		resumed = 0

	currentpart = SSAIR_DEFERREDPIPENETS

/datum/controller/subsystem/air/proc/build_pipenets(resumed = 0)
	if(!resumed)
		src.currentrun = pipenets_to_build.Copy()
	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun
	while(length(currentrun))
		var/obj/machinery/atmospherics/A = currentrun[length(currentrun)]
		currentrun.len--
		if(A)
			A.build_network(remove_deferral = TRUE)
		else
			pipenets_to_build.Remove(A)
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/air/proc/process_pipenets(resumed = 0)
	if(!resumed)
		src.currentrun = pipenets.Copy()
	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun
	while(length(currentrun))
		var/datum/pipeline/thing = currentrun[length(currentrun)]
		currentrun.len--
		if(thing)
			thing.process()
		else
			pipenets.Remove(thing)
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/air/proc/process_atmos_machinery(resumed = 0)
	var/seconds = wait * 0.1
	if(!resumed)
		src.currentrun = atmos_machinery.Copy()
	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun
	while(length(currentrun))
		var/obj/machinery/atmospherics/M = currentrun[length(currentrun)]
		currentrun.len--
		if(isnull(M) || (M.process_atmos(seconds) == PROCESS_KILL))
			atmos_machinery -= M
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/air/proc/process_hotspots(resumed = 0)
	if(!resumed)
		src.currentrun = hotspots.Copy()
	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun
	while(length(currentrun))
		var/obj/effect/hotspot/H = currentrun[length(currentrun)]
		currentrun.len--
		if(H)
			H.process()
		else
			hotspots -= H
		if(MC_TICK_CHECK)
			return

/// The number of values per interesting tile.
#define INTERESTING_TILE_SIZE 6
/// Interesting because it needs a display update.
#define REASON_DISPLAY	(1 << 0)
/// Interesting because it's hot enough to start a fire. Excludes normal-temperature Lavaland tiles without an active fire.
#define REASON_HOT		(1 << 1)
/// Interesting because it has wind that can push stuff around.
#define REASON_WIND		(1 << 2)
/datum/controller/subsystem/air/proc/process_interesting_tiles(resumed = 0)
	if(!resumed)
		// Fetch the list of interesting tiles from MILLA.
		src.currentrun = get_interesting_atmos_tiles()
		interesting_tile_count = length(src.currentrun) / INTERESTING_TILE_SIZE
	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun
	while(length(currentrun))
		// Pop a tile off the list.
		var/offset = length(currentrun) - INTERESTING_TILE_SIZE
		var/x = currentrun[offset + 1]
		var/y = currentrun[offset + 2]
		var/z = currentrun[offset + 3]
		var/reasons = currentrun[offset + 4]
		var/x_flow = currentrun[offset + 5]
		var/y_flow = currentrun[offset + 6]
		currentrun.len -= INTERESTING_TILE_SIZE

		var/turf/simulated/T = locate(x, y, z)
		if(!istype(T))
			if(MC_TICK_CHECK)
				return
			continue

		if(reasons & REASON_DISPLAY)
			T.update_visuals()

		if(reasons & REASON_HOT)
			var/datum/gas_mixture/air = T.get_air()
			T.hotspot_expose(air.temperature(), CELL_VOLUME)
			for(var/atom/movable/item in T)
				item.temperature_expose(air, air.temperature(), CELL_VOLUME)
			T.temperature_expose(air, air.temperature(), CELL_VOLUME)

		if(reasons & REASON_WIND)
			T.high_pressure_movements(x_flow, y_flow)

		if(MC_TICK_CHECK)
			return
#undef INTERESTING_TILE_SIZE
#undef REASON_DISPLAY
#undef REASON_HOT
#undef REASON_WIND

/datum/controller/subsystem/air/proc/process_bound_mixtures(resumed = 0)
	if(!resumed)
		original_bound_mixtures = length(bound_mixtures)
		last_bound_mixtures = length(bound_mixtures)
	// Note that we do NOT copy this list. We're fine with things being added to it as we work, because it all needs to get written before the next MILLA tick.
	src.currentrun = bound_mixtures
	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun
	added_bound_mixtures = length(currentrun) - last_bound_mixtures
	while(length(currentrun))
		var/datum/gas_mixture/bound_to_turf/mixture = currentrun[length(currentrun)]
		currentrun.len--
		if(mixture.dirty)
			mixture.write()
		mixture.bound_turf.bound_air = null
		mixture.bound_turf = null
		if(MC_TICK_CHECK)
			last_bound_mixtures = length(bound_mixtures)
			return

/datum/controller/subsystem/air/proc/setup_allturfs(list/turfs_to_init = block(locate(1, 1, 1), locate(world.maxx, world.maxy, world.maxz)))
	for(var/thing in turfs_to_init)
		var/turf/T = thing
		T.Initialize_Atmos(times_fired)
		CHECK_TICK

/datum/controller/subsystem/air/proc/setup_atmos_machinery(list/machines_to_init)
	var/watch = start_watch()
	log_startup_progress("Initializing atmospherics machinery...")
	var/count = _setup_atmos_machinery(machines_to_init)
	log_startup_progress("Initialized [count] atmospherics machines in [stop_watch(watch)]s.")

// this underscored variant is so that we can have a means of late initing
// atmos machinery without a loud announcement to the world
/datum/controller/subsystem/air/proc/_setup_atmos_machinery(list/machines_to_init)
	var/count = 0
	for(var/obj/machinery/atmospherics/A in machines_to_init)
		A.atmos_init()
		count++
		CHECK_TICK
	return count

//this can't be done with setup_atmos_machinery() because
//	all atmos machinery has to initalize before the first
//	pipenet can be built.
/datum/controller/subsystem/air/proc/setup_pipenets(list/pipes)
	var/watch = start_watch()
	log_startup_progress("Initializing pipe pipenets...")
	var/count = _setup_pipenets(pipes)
	log_startup_progress("Initialized [count] pipenets in [stop_watch(watch)]s.")

// An underscored wrapper that exists for the same reason
// the machine init wrapper does
/datum/controller/subsystem/air/proc/_setup_pipenets(list/pipes)
	var/count = 0
	for(var/obj/machinery/atmospherics/machine in pipes)
		machine.build_network()
		count++
	return count

/obj/effect/overlay/turf
	icon = 'icons/effects/tile_effects.dmi'
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	anchored = TRUE  // should only appear in vis_contents, but to be safe
	layer = FLY_LAYER
	appearance_flags = TILE_BOUND | RESET_TRANSFORM | RESET_COLOR

/obj/effect/overlay/turf/plasma
	icon_state = "plasma"

/obj/effect/overlay/turf/sleeping_agent
	icon_state = "sleeping_agent"

/datum/controller/subsystem/air/proc/setup_overlays()
	GLOB.plmaster = new /obj/effect/overlay/turf/plasma
	GLOB.slmaster = new /obj/effect/overlay/turf/sleeping_agent

/datum/controller/subsystem/air/proc/bind_turf(turf/T)
	var/datum/gas_mixture/bound_to_turf/B = new()
	B.copy_from_milla(get_tile_atmos(T.x, T.y, T.z), mark_dirty = FALSE)
	B.bound_turf = T
	T.bound_air = B
	bound_mixtures += B

#undef SSAIR_DEFERREDPIPENETS
#undef SSAIR_PIPENETS
#undef SSAIR_ATMOSMACHINERY
#undef SSAIR_INTERESTING_TILES
#undef SSAIR_HOTSPOTS
#undef SSAIR_BOUND_MIXTURES
#undef SSAIR_MILLA_TICK
#undef SSAIR_SUPERCONDUCTIVITY
