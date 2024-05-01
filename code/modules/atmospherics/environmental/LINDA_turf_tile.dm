/turf/assume_air(datum/gas_mixture/giver) //use this for machines to adjust air
	qdel(giver)
	return 0

/turf/return_air()
	RETURN_TYPE(/datum/gas_mixture)
	//Create gas mixture to hold data for passing
	var/datum/gas_mixture/GM = new

	GM.oxygen = oxygen
	GM.carbon_dioxide = carbon_dioxide
	GM.nitrogen = nitrogen
	GM.toxins = toxins
	GM.sleeping_agent = sleeping_agent
	GM.agent_b = agent_b

	GM.temperature = temperature

	return GM

/turf/return_analyzable_air()
	return return_air()

/turf/remove_air(amount)
	var/datum/gas_mixture/GM = new

	var/sum = oxygen + carbon_dioxide + nitrogen + toxins + sleeping_agent + agent_b
	if(sum > 0)
		GM.oxygen = (oxygen / sum) * amount
		GM.carbon_dioxide = (carbon_dioxide / sum) * amount
		GM.nitrogen = (nitrogen / sum) * amount
		GM.toxins = (toxins / sum) * amount
		GM.sleeping_agent = (sleeping_agent / sum) * amount
		GM.agent_b = (agent_b / sum) * amount

	GM.temperature = temperature

	return GM

/turf/simulated/Initialize(mapload)
	. = ..()
	if(!blocks_air)
		var/datum/gas_mixture/air = new()

		air.oxygen = oxygen
		air.carbon_dioxide = carbon_dioxide
		air.nitrogen = nitrogen
		air.toxins = toxins
		air.sleeping_agent = sleeping_agent
		air.agent_b = agent_b

		air.temperature = temperature

		write_air(air)

/turf/simulated/Destroy()
	QDEL_NULL(active_hotspot)
	QDEL_NULL(wet_overlay)
	return ..()

/turf/simulated/assume_air(datum/gas_mixture/giver)
	if(!giver)
		return FALSE
	if(blocks_air)
		return ..()

	var/datum/gas_mixture/air = read_air()
	air.merge(giver)
	write_air(air)
	update_visuals(air)

	return TRUE

/turf/simulated/proc/copy_air_with_tile(turf/simulated/T)
	if(!istype(T) || T.blocks_air || blocks_air)
		return
	write_air(T.read_air())

/turf/simulated/proc/copy_air(datum/gas_mixture/copy)
	if(!copy || blocks_air)
		return
	write_air(copy)

/turf/simulated/return_air()
	RETURN_TYPE(/datum/gas_mixture)
	if(blocks_air)
		return ..()
	return read_air()

/turf/simulated/remove_air(amount)
	var/datum/gas_mixture/air = read_air()
	var/datum/gas_mixture/removed = air.remove(amount)
	write_air(air)
	update_visuals(air)
	return removed

/turf/simulated/proc/mimic_temperature_solid(turf/model, conduction_coefficient)
	var/delta_temperature = (temperature_archived - model.temperature)
	if((heat_capacity > 0) && (abs(delta_temperature) > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER))

		var/heat = conduction_coefficient*delta_temperature* \
			(heat_capacity*model.heat_capacity/(heat_capacity+model.heat_capacity))
		temperature -= heat/heat_capacity

/turf/simulated/proc/share_temperature_mutual_solid(turf/simulated/sharer, conduction_coefficient)
	var/delta_temperature = (temperature_archived - sharer.temperature_archived)
	if(abs(delta_temperature) > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER && heat_capacity && sharer.heat_capacity)

		var/heat = conduction_coefficient*delta_temperature* \
			(heat_capacity*sharer.heat_capacity/(heat_capacity+sharer.heat_capacity))

		temperature -= heat/heat_capacity
		sharer.temperature += heat/sharer.heat_capacity

/turf/simulated/proc/update_visuals(datum/gas_mixture/air)
	var/new_overlay_type = tile_graphic(air)
	if(new_overlay_type == atmos_overlay_type)
		return
	var/atmos_overlay = get_atmos_overlay_by_name(atmos_overlay_type)
	if(atmos_overlay)
		vis_contents -= atmos_overlay
		atmos_overlay_type = null

	atmos_overlay = get_atmos_overlay_by_name(new_overlay_type)
	if(atmos_overlay)
		vis_contents += atmos_overlay
		atmos_overlay_type = new_overlay_type

/turf/simulated/proc/get_atmos_overlay_by_name(name)
	switch(name)
		if("plasma")
			return GLOB.plmaster
		if("sleeping_agent")
			return GLOB.slmaster
	return null

/turf/simulated/proc/tile_graphic(datum/gas_mixture/air)
	if(blocks_air)
		return
	if(!istype(air))
		air = read_air()
	if(air.toxins > MOLES_PLASMA_VISIBLE)
		return "plasma"

	if(air.sleeping_agent > 1)
		return "sleeping_agent"
	return null

/turf/proc/high_pressure_movements(flow_x, flow_y)
	var/atom/movable/M
	for(var/thing in src)
		M = thing
		if(QDELETED(M))
			continue
		if(M.anchored)
			continue
		if(M.pulledby)
			continue
		if(M.last_high_pressure_movement_air_cycle < SSair.times_fired)
			M.experience_pressure_difference(flow_x, flow_y)

/atom/movable/proc/experience_pressure_difference(flow_x, flow_y, pressure_resistance_prob_delta = 0)
	var/const/PROBABILITY_OFFSET = 25
	var/const/PROBABILITY_BASE_PRECENT = 75

	var/pressure_difference = sqrt(flow_x ** 2 + flow_y ** 2)
	var/max_force = sqrt(pressure_difference) * (MOVE_FORCE_DEFAULT / 5)
	set waitfor = 0
	var/move_prob = 100
	if(pressure_resistance > 0)
		move_prob = (pressure_difference / pressure_resistance * PROBABILITY_BASE_PRECENT) - PROBABILITY_OFFSET
	move_prob += pressure_resistance_prob_delta
	if(move_prob > PROBABILITY_OFFSET && prob(move_prob) && (move_resist != INFINITY) && (!anchored && (max_force >= (move_resist * MOVE_FORCE_PUSH_RATIO))) || (anchored && (max_force >= (move_resist * MOVE_FORCE_FORCEPUSH_RATIO))))
		var/direction = 0
		if(flow_x > 0.5)
			direction |= EAST
		if(flow_x < -0.5)
			direction |= WEST
		if(flow_y > 0.5)
			direction |= NORTH
		if(flow_y < -0.5)
			direction |= SOUTH
		step(src, direction)
		last_high_pressure_movement_air_cycle = SSair.times_fired

	return pressure_difference

/turf/simulated/proc/radiate_to_spess() //Radiate excess tile heat to space
	if(temperature > T0C) //Considering 0 degC as te break even point for radiation in and out
		var/delta_temperature = (temperature_archived - TCMB) //hardcoded space temperature
		if((heat_capacity > 0) && (abs(delta_temperature) > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER))

			var/heat = thermal_conductivity*delta_temperature* \
				(heat_capacity*HEAT_CAPACITY_VACUUM/(heat_capacity+HEAT_CAPACITY_VACUUM)) //700000 is the heat_capacity from a space turf, hardcoded here
			temperature -= heat/heat_capacity

#define INDEX_NORTH	1
#define INDEX_EAST	2
#define INDEX_SOUTH	3
#define INDEX_WEST	4

/turf/proc/Initialize_Atmos(times_fired)
	recalculate_atmos_connectivity()

/turf/proc/recalculate_atmos_connectivity()
	if(blocks_air)
		set_tile_atmos(x, y, z, temperature = temperature, innate_heat_capacity = heat_capacity)
		set_tile_atmos_blocking(x, y, z, list(TRUE, TRUE, TRUE, TRUE))
		reset_superconductivity(x, y, z)
		reduce_superconductivity(x, y, z, list(thermal_conductivity, thermal_conductivity, thermal_conductivity, thermal_conductivity))
		return

	var/list/atmos_blocks = list(
		!CanAtmosPass(NORTH, FALSE),
		!CanAtmosPass(EAST, FALSE),
		!CanAtmosPass(SOUTH, FALSE),
		!CanAtmosPass(WEST, FALSE))

	var/list/superconductivity = list(
		OPEN_HEAT_TRANSFER_COEFFICIENT,
		OPEN_HEAT_TRANSFER_COEFFICIENT,
		OPEN_HEAT_TRANSFER_COEFFICIENT,
		OPEN_HEAT_TRANSFER_COEFFICIENT)

	for(var/obj/O in src)
		if(istype(O, /obj/item))
			// Items can't block atmos.
			continue
		if(!O.CanAtmosPass(NORTH))
			atmos_blocks[INDEX_NORTH] = TRUE
		if(!O.CanAtmosPass(EAST))
			atmos_blocks[INDEX_EAST] = TRUE
		if(!O.CanAtmosPass(SOUTH))
			atmos_blocks[INDEX_SOUTH] = TRUE
		if(!O.CanAtmosPass(WEST))
			atmos_blocks[INDEX_WEST] = TRUE
		superconductivity[INDEX_NORTH] = min(superconductivity[INDEX_NORTH], O.get_superconductivity(NORTH))
		superconductivity[INDEX_EAST] = min(superconductivity[INDEX_EAST], O.get_superconductivity(EAST))
		superconductivity[INDEX_SOUTH] = min(superconductivity[INDEX_SOUTH], O.get_superconductivity(SOUTH))
		superconductivity[INDEX_WEST] = min(superconductivity[INDEX_WEST], O.get_superconductivity(WEST))

	set_tile_atmos_blocking(x, y, z, atmos_blocks)
	reset_superconductivity(x, y, z)
	reduce_superconductivity(x, y, z, superconductivity)

#undef INDEX_NORTH
#undef INDEX_EAST
#undef INDEX_SOUTH
#undef INDEX_WEST

/turf/simulated/Initialize_Atmos(times_fired)
	..()

	var/datum/gas_mixture/air = new()
	air.oxygen = oxygen
	air.carbon_dioxide = carbon_dioxide
	air.nitrogen = nitrogen
	air.toxins = toxins
	air.sleeping_agent = sleeping_agent
	air.agent_b = agent_b
	air.temperature = temperature

	write_air(air)
	update_visuals()
