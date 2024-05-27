/datum/pipeline
	var/datum/gas_mixture/air
	var/list/datum/gas_mixture/other_airs = list()

	var/list/obj/machinery/atmospherics/pipe/members = list()
	var/list/obj/machinery/atmospherics/other_atmosmch = list()

	var/update = TRUE

/datum/pipeline/New()
	SSair.networks += src

/datum/pipeline/Destroy()
	SSair.networks -= src
	var/datum/gas_mixture/ghost = null
	if(air && air.volume)
		ghost = air
		air = null
	for(var/obj/machinery/atmospherics/pipe/P in members)
		if(QDELETED(P))
			continue
		P.ghost_pipeline = ghost
		P.parent = null
	for(var/obj/machinery/atmospherics/A in other_atmosmch)
		A.nullifyPipenet(src)
	return ..()

/datum/pipeline/process()//This use to be called called from the pipe networks
	if(update)
		update = FALSE
		reconcile_air()
	return

/datum/pipeline/proc/build_pipeline(obj/machinery/atmospherics/base)
	var/volume = 0
	var/list/ghost_pipelines = list()
	if(istype(base, /obj/machinery/atmospherics/pipe))
		var/obj/machinery/atmospherics/pipe/E = base
		volume = E.volume
		members += E
		if(E.ghost_pipeline)
			ghost_pipelines[E.ghost_pipeline] = E.volume
			E.ghost_pipeline = null
	else
		addMachineryMember(base)
	if(!air)
		air = new
	var/list/possible_expansions = list(base)
	while(length(possible_expansions)>0)
		for(var/obj/machinery/atmospherics/borderline in possible_expansions)

			var/list/result = borderline.pipeline_expansion(src)

			if(length(result)>0)
				for(var/obj/machinery/atmospherics/P in result)
					if(istype(P, /obj/machinery/atmospherics/pipe))
						var/obj/machinery/atmospherics/pipe/item = P
						if(!members.Find(item))

							if(item.parent)
								stack_trace("[item.type] \[\ref[item]] added to a pipenet while still having one ([item.parent]) (pipes leading to the same spot stacking in one turf). Nearby: [item.x], [item.y], [item.z].")
							members += item
							possible_expansions += item

							volume += item.volume
							item.parent = src

							if(item.ghost_pipeline)
								if(!ghost_pipelines[item.ghost_pipeline])
									ghost_pipelines[item.ghost_pipeline] = item.volume
								else
									ghost_pipelines[item.ghost_pipeline] += item.volume
								item.ghost_pipeline = null
					else
						P.setPipenet(src, borderline)
						addMachineryMember(P)

			possible_expansions -= borderline

	for(var/datum/gas_mixture/ghost in ghost_pipelines)
		var/collected_ghost_volume = ghost_pipelines[ghost]
		var/collected_fraction = collected_ghost_volume / ghost.volume

		var/datum/gas_mixture/ghost_copy = new()
		ghost_copy.copy_from(ghost)
		air.merge(ghost_copy.remove_ratio(collected_fraction))

	air.volume = volume

/datum/pipeline/proc/addMachineryMember(obj/machinery/atmospherics/A)
	other_atmosmch |= A
	var/datum/gas_mixture/G = A.returnPipenetAir(src)
	other_airs |= G

/datum/pipeline/proc/addMember(obj/machinery/atmospherics/A, obj/machinery/atmospherics/N)
	update = TRUE
	if(istype(A, /obj/machinery/atmospherics/pipe))
		var/obj/machinery/atmospherics/pipe/P = A
		P.parent = src
		var/list/adjacent = P.pipeline_expansion()
		for(var/obj/machinery/atmospherics/pipe/I in adjacent)
			if(I.parent == src)
				continue
			var/datum/pipeline/E = I.parent
			merge(E)
		if(!members.Find(P))
			members += P
			air.volume += P.volume
	else
		A.setPipenet(src, N)
		addMachineryMember(A)

/datum/pipeline/proc/merge(datum/pipeline/E)
	air.volume += E.air.volume
	members.Add(E.members)
	for(var/obj/machinery/atmospherics/pipe/S in E.members)
		S.parent = src
	air.merge(E.air)
	for(var/obj/machinery/atmospherics/A in E.other_atmosmch)
		A.replacePipenet(E, src)
	other_atmosmch.Add(E.other_atmosmch)
	other_airs.Add(E.other_airs)
	E.members.Cut()
	E.other_atmosmch.Cut()
	qdel(E)

/obj/machinery/atmospherics/proc/addMember(obj/machinery/atmospherics/A)
	var/datum/pipeline/P = returnPipenet(A)
	P.addMember(A, src)

/obj/machinery/atmospherics/pipe/addMember(obj/machinery/atmospherics/A)
	parent.addMember(A, src)

/datum/pipeline/proc/temperature_interact(turf/target, share_volume, thermal_conductivity)
	var/total_heat_capacity = air.heat_capacity()
	var/partial_heat_capacity = total_heat_capacity*(share_volume/air.volume)

	if(issimulatedturf(target))
		var/turf/simulated/modeled_location = target

		if(modeled_location.blocks_air)

			if((modeled_location.heat_capacity>0) && (partial_heat_capacity>0))
				var/delta_temperature = air.temperature - modeled_location.temperature

				var/heat = thermal_conductivity*delta_temperature* \
					(partial_heat_capacity*modeled_location.heat_capacity/(partial_heat_capacity+modeled_location.heat_capacity))

				air.temperature -= heat/total_heat_capacity
				modeled_location.temperature += heat/modeled_location.heat_capacity

		else
			var/delta_temperature = 0
			var/sharer_heat_capacity = 0

			delta_temperature = (air.temperature - modeled_location.air.temperature)
			sharer_heat_capacity = modeled_location.air.heat_capacity()

			var/self_temperature_delta = 0
			var/sharer_temperature_delta = 0

			if((sharer_heat_capacity>0) && (partial_heat_capacity>0))
				var/heat = thermal_conductivity*delta_temperature* \
					(partial_heat_capacity*sharer_heat_capacity/(partial_heat_capacity+sharer_heat_capacity))

				self_temperature_delta = -heat/total_heat_capacity
				sharer_temperature_delta = heat/sharer_heat_capacity
			else
				return 1

			air.temperature += self_temperature_delta

			modeled_location.air.temperature += sharer_temperature_delta


	else
		if((target.heat_capacity>0) && (partial_heat_capacity>0))
			var/delta_temperature = air.temperature - target.temperature

			var/heat = thermal_conductivity*delta_temperature* \
				(partial_heat_capacity*target.heat_capacity/(partial_heat_capacity+target.heat_capacity))

			air.temperature -= heat/total_heat_capacity
	update = TRUE

/datum/pipeline/proc/reconcile_air()
	var/list/datum/gas_mixture/GL = list()
	var/list/datum/pipeline/PL = list()
	PL += src

	for(var/i=1;i<=length(PL);i++)
		var/datum/pipeline/P = PL[i]
		if(!P)
			return
		GL += P.air
		GL += P.other_airs
		for(var/obj/machinery/atmospherics/binary/valve/V in P.other_atmosmch)
			if(V.open)
				PL |= V.parent1
				PL |= V.parent2
		for(var/obj/machinery/atmospherics/trinary/tvalve/T in P.other_atmosmch)
			if(!T.state)
				if(src != T.parent2) // otherwise dc'd side connects to both other sides!
					PL |= T.parent1
					PL |= T.parent3
			else
				if(src != T.parent3)
					PL |= T.parent1
					PL |= T.parent2
		for(var/obj/machinery/atmospherics/unary/portables_connector/C in P.other_atmosmch)
			if(C.connected_device)
				GL += C.portableConnectorReturnAir()

	var/total_volume = 0
	var/total_thermal_energy = 0
	var/total_heat_capacity = 0
	var/total_oxygen = 0
	var/total_nitrogen = 0
	var/total_toxins = 0
	var/total_carbon_dioxide = 0
	var/total_sleeping_agent = 0
	var/total_agent_b = 0

	for(var/datum/gas_mixture/G in GL)
		total_volume += G.volume
		total_thermal_energy += G.thermal_energy()
		total_heat_capacity += G.heat_capacity()

		total_oxygen += G.oxygen
		total_nitrogen += G.nitrogen
		total_toxins += G.toxins
		total_carbon_dioxide += G.carbon_dioxide
		total_sleeping_agent += G.sleeping_agent
		total_agent_b += G.agent_b

	if(total_volume > 0)

		//Calculate temperature
		var/temperature = 0

		if(total_heat_capacity > 0)
			temperature = total_thermal_energy/total_heat_capacity

		//Update individual gas_mixtures by volume ratio
		for(var/datum/gas_mixture/G in GL)
			G.oxygen = total_oxygen * G.volume / total_volume
			G.nitrogen = total_nitrogen * G.volume / total_volume
			G.toxins = total_toxins * G.volume / total_volume
			G.carbon_dioxide = total_carbon_dioxide * G.volume / total_volume
			G.sleeping_agent = total_sleeping_agent * G.volume / total_volume
			G.agent_b = total_agent_b * G.volume / total_volume

			G.temperature = temperature
