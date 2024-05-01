
/atom/proc/temperature_expose(datum/gas_mixture/air, exposed_temperature, exposed_volume)
	if(reagents)
		reagents.temperature_reagents(exposed_temperature)
	return null



/turf/proc/hotspot_expose(exposed_temperature, exposed_volume, soh = 0)
	return


/turf/simulated/hotspot_expose(exposed_temperature, exposed_volume, soh)
	var/datum/gas_mixture/air_contents = return_air()
	if(reagents)
		reagents.temperature_reagents(exposed_temperature, 10, 300)
	if(!air_contents)
		return 0
	if(active_hotspot)
		if(soh)
			if(air_contents.toxins > 0.5 && air_contents.oxygen > 0.5)
				if(active_hotspot.temperature < exposed_temperature)
					active_hotspot.temperature = exposed_temperature
				if(active_hotspot.volume < exposed_volume)
					active_hotspot.volume = exposed_volume
		return 1

	var/igniting = 0

	if((exposed_temperature > PLASMA_MINIMUM_BURN_TEMPERATURE) && air_contents.toxins > 0.5)
		igniting = 1

	if(igniting)
		if(air_contents.oxygen < 1.3 || air_contents.toxins < 0.5)
			return 0

		active_hotspot = new /obj/effect/hotspot(src)
		active_hotspot.temperature = exposed_temperature
		active_hotspot.volume = exposed_volume
		active_hotspot.just_spawned = TRUE
	return igniting

//This is the icon for fire on turfs, also helps for nurturing small fires until they are full tile
/obj/effect/hotspot
	anchored = TRUE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	icon = 'icons/goonstation/effects/fire.dmi'
	icon_state = "1"
	layer = MASSIVE_OBJ_LAYER
	alpha = 250
	blend_mode = BLEND_ADD
	light_range = 2

	var/volume = 125
	var/temperature = FIRE_MINIMUM_TEMPERATURE_TO_EXIST
	var/just_spawned = 1
	var/bypassing = 0
	var/fake = FALSE
	var/burn_time = 0
	/// Used to carry over the amount of fuel burnt by the hotspot directly
	/// to the next tick.
	var/own_fuel_burnt = 0

/obj/effect/hotspot/New()
	..()
	if(!fake)
		SSair.hotspots += src
		perform_exposure()
	dir = pick(GLOB.cardinal)
	air_update_turf()

/obj/effect/hotspot/proc/perform_exposure()
	var/turf/simulated/location = loc
	if(!istype(location) || location.blocks_air)
		return FALSE

	if(volume > CELL_VOLUME * 0.95)
		bypassing = TRUE
	else
		bypassing = FALSE

	var/datum/gas_mixture/location_air = location.read_air()
	if(bypassing)
		if(!just_spawned)
			temperature = location_air.temperature
			volume = (own_fuel_burnt + location.fuel_burnt) * FIRE_GROWTH_RATE
			own_fuel_burnt = 0
	else
		var/datum/gas_mixture/affected = location_air.remove_ratio(volume / location_air.volume)
		affected.temperature = temperature
		affected.react()
		temperature = affected.temperature
		volume = affected.fuel_burnt * FIRE_GROWTH_RATE
		own_fuel_burnt = affected.fuel_burnt
		location_air.merge(affected)
		location.write_air(location_air)

	for(var/A in loc)
		var/atom/item = A
		if(!QDELETED(item) && item != src) // It's possible that the item is deleted in temperature_expose
			item.fire_act(null, temperature, volume)

	color = heat2color(temperature)
	set_light(l_color = color)
	return FALSE


/obj/effect/hotspot/process()
	if(just_spawned)
		just_spawned = 0
		return 0

	var/turf/simulated/location = loc
	if(!istype(location))
		qdel(src)
		return

	if((temperature < FIRE_MINIMUM_TEMPERATURE_TO_EXIST) || (volume <= 1))
		qdel(src)
		return

	var/datum/gas_mixture/location_air = location.read_air()
	if(location.blocks_air || location_air.toxins < 0.5 || location_air.oxygen < 0.5)
		qdel(src)
		return

	perform_exposure()

	if(location.wet) location.wet = TURF_DRY

	if(bypassing)
		icon_state = "3"
		location.burn_tile()

		//Possible spread due to radiated heat
		if(location_air.temperature > FIRE_MINIMUM_TEMPERATURE_TO_SPREAD)
			var/radiated_temperature = location_air.temperature*FIRE_SPREAD_RADIOSITY_SCALE
			for(var/direction in GLOB.cardinal)
				var/turf/simulated/T = get_step(location, direction)
				if(!istype(T))
					continue
				if(T.active_hotspot)
					continue
				if(src.CanAtmosPass(direction) && T.CanAtmosPass(turn(direction, 180)))
					T.hotspot_expose(radiated_temperature, CELL_VOLUME / 4)

	else
		if(volume > CELL_VOLUME*0.4)
			icon_state = "2"
		else
			icon_state = "1"

	if(temperature > location.max_fire_temperature_sustained)
		location.max_fire_temperature_sustained = temperature

	if(location.heat_capacity && temperature > location.heat_capacity)
		location.to_be_destroyed = 1
		/*if(prob(25))
			location.ReplaceWithSpace()
			return 0*/
	return 1

// Garbage collect itself by nulling reference to it

/obj/effect/hotspot/Destroy()
	set_light(0)
	SSair.hotspots -= src
	var/turf/simulated/T = loc
	if(istype(T) && T.active_hotspot == src)
		T.active_hotspot = null
	if(!fake)
		DestroyTurf()
	return ..()

/obj/effect/hotspot/proc/DestroyTurf()
	if(issimulatedturf(loc))
		var/turf/simulated/T = loc
		if(T.to_be_destroyed && !T.changing_turf)
			var/chance_of_deletion
			if(T.heat_capacity) //beware of division by zero
				chance_of_deletion = T.max_fire_temperature_sustained / T.heat_capacity * 8 //there is no problem with prob(23456), min() was redundant --rastaf0
			else
				chance_of_deletion = 100
			if(prob(chance_of_deletion))
				T.ChangeTurf(T.baseturf)
			else
				T.to_be_destroyed = 0
				T.max_fire_temperature_sustained = 0

/obj/effect/hotspot/Crossed(mob/living/L, oldloc)
	..()
	if(isliving(L))
		L.fire_act()

/obj/effect/hotspot/singularity_pull()
	return

/// Largely for the fireflash procs below
/obj/effect/hotspot/fake
	fake = TRUE
	burn_time = 30

/obj/effect/hotspot/fake/New()
	..()
	if(burn_time)
		QDEL_IN(src, burn_time)

/proc/fireflash(atom/center, radius, temp)
	if(!temp)
		temp = rand(2800, 3200)
	for(var/turf/T in view(radius, get_turf(center)))
		if(isspaceturf(T))
			continue
		if(locate(/obj/effect/hotspot) in T)
			continue
		if(!can_line(get_turf(center), T, radius + 1))
			continue

		var/obj/effect/hotspot/fake/H = new(T)
		H.temperature = temp
		H.volume = 400
		H.color = heat2color(H.temperature)
		H.set_light(l_color = H.color)

		T.hotspot_expose(H.temperature, H.volume)
		for(var/atom/A in T)
			if(isliving(A))
				continue
			if(A != H)
				A.fire_act(null, H.temperature, H.volume)

		if(isfloorturf(T))
			var/turf/simulated/floor/F = T
			F.burn_tile()

		for(var/mob/living/L in T)
			L.adjust_fire_stacks(3)
			L.IgniteMob()
			if(ishuman(L))
				var/mob/living/carbon/human/M = L
				var/heatBlockPercent = 1 - M.get_heat_protection(temp)
				M.bodytemperature += (temp - M.bodytemperature) * heatBlockPercent / 3
			else
				L.bodytemperature = (2 * L.bodytemperature + temp) / 3

/proc/fireflash_s(atom/center, radius, temp, falloff)
	if(temp < T0C + 60)
		return list()
	var/list/open = list()
	var/list/affected = list()
	var/list/closed = list()
	var/turf/Ce = get_turf(center)
	var/max_dist = radius
	if(falloff)
		max_dist = min((temp - (T0C + 60)) / falloff, radius)
	open[Ce] = 0
	while(length(open))
		var/turf/T = open[1]
		var/dist = open[T]
		open -= T
		closed[T] = TRUE

		if(isspaceturf(T))
			continue
		if(dist > max_dist)
			continue
		if(!ff_cansee(Ce, T))
			continue

		var/obj/effect/hotspot/existing_hotspot = locate(/obj/effect/hotspot) in T
		var/prev_temp = 0
		var/need_expose = 0
		var/expose_temp = 0
		if(!existing_hotspot)
			var/obj/effect/hotspot/fake/H = new(T)
			need_expose = TRUE
			H.temperature = temp - dist * falloff
			expose_temp = H.temperature
			H.volume = 400
			H.color = heat2color(H.temperature)
			H.set_light(l_color = H.color)
			existing_hotspot = H

		else if(existing_hotspot.temperature < temp - dist * falloff)
			expose_temp = (temp - dist * falloff) - existing_hotspot.temperature
			prev_temp = existing_hotspot.temperature
			if(expose_temp > prev_temp * 3)
				need_expose = TRUE
			existing_hotspot.temperature = temp - dist * falloff
			existing_hotspot.color = heat2color(existing_hotspot.temperature)
			existing_hotspot.set_light(l_color = existing_hotspot.color)

		affected[T] = existing_hotspot.temperature
		if(need_expose && expose_temp)
			T.hotspot_expose(expose_temp, existing_hotspot.volume)
			for(var/atom/A in T)
				if(isliving(A))
					continue
				if(A != existing_hotspot)
					A.fire_act(null, expose_temp, existing_hotspot.volume)
		if(isfloorturf(T))
			var/turf/simulated/floor/F = T
			F.burn_tile()
		for(var/mob/living/L in T)
			L.adjust_fire_stacks(3)
			L.IgniteMob()
			if(ishuman(L))
				var/mob/living/carbon/human/M = L
				var/heatBlockPercent = 1 - M.get_heat_protection(temp)
				M.bodytemperature += (temp - M.bodytemperature) * heatBlockPercent / 3
			else
				L.bodytemperature = (2 * L.bodytemperature + temp) / 3

		if(T.density)
			continue

		if(dist == max_dist)
			continue

		for(var/direction in GLOB.cardinal)
			var/turf/link = get_step(T, direction)
			if(!link)
				continue
			// Check if it wasn't already visited and if you can get to that turf
			if(!closed[link] && T.CanAtmosPass(direction) && link.CanAtmosPass(turn(direction, 180)))
				var/dx = link.x - Ce.x
				var/dy = link.y - Ce.y
				var/target_dist = max((dist + 1 + sqrt(dx * dx + dy * dy)) / 2, dist)
				if(link in open)
					if(open[link] > target_dist)
						open[link] = target_dist
				else
					open[link] = target_dist

	return affected

/proc/fireflash_sm(atom/center, radius, temp, falloff, capped = TRUE, bypass_rng = FALSE)
	var/list/affected = fireflash_s(center, radius, temp, falloff)
	for(var/turf/simulated/T in affected)
		var/mytemp = affected[T]
		var/melt = 1643.15 // default steel melting point
		var/divisor = melt
		if(mytemp >= melt * 2)
			var/chance = mytemp / divisor
			if(capped)
				chance = min(chance, 30)
			if(prob(chance) || bypass_rng)
				T.visible_message("<span class='warning'>[T] melts!</span>")
				T.burn_down()
	return affected
