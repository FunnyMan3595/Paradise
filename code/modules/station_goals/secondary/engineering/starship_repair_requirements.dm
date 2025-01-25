#define OXYGEN "Oxygen"
#define CARBON_DIOXIDE "Carbon Dioxide"
#define NITROGEN "Nitrogen"
#define TOXINS "Plasma"
#define SLEEPING_AGENT "Nitrous Oxide"
#define AGENT_B "Agent B"
#define ALL_GASES list(OXYGEN, CARBON_DIOXIDE, NITROGEN, TOXINS, SLEEPING_AGENT, AGENT_B)

#define NORMAL_AIR list(OXYGEN = 20, NITROGEN = 80)
#define VOX_BOX list(NITROGEN = 100)
#define PURE_PLASMA list(TOXINS = 100)
#define BURN_MIX list(OXYGEN = 30, TOXINS = 70)
#define VACUUM list()

/datum/starship_repair_requirement
	var/name = "Freebie"
	var/desc = "The ship must exist."

/datum/starship_repair_requirement/proc/Initialize()
	return

/datum/starship_repair_requirement/proc/check(obj/docking_port/mobile/ship, obj/machinery/computer/starship_repair/console)
	return STARSHIP_REPAIR_DONE

/datum/starship_repair_requirement/room
	name = "Room"
	desc = "A generic room."

	/// The minimum size, in tiles, of the room.
	var/minimum_size = 10
	/// A list of (atom type -> count) that must be present in the room.
	var/required_contents = list()
	/// A list of (gas name -> kPa required) that the room must be pressurized with. If set, no other gases may be present (above 0.1 moles per tile).
	var/required_air = NORMAL_AIR
	/// Should the room be powered?
	var/requires_power = TRUE

/datum/starship_repair_requirement/room/Initialize()
	var/list/parts = list("Minimum size: [minimum_size] m^2")
	if(required_contents)
		parts += "Must contain:"
		for(var/thing in required_contents)
			parts += "* [initial(thing.name)]: [required_contents[thing]]"
	if(required_air)
		parts += "Must be pressurized within 5% of:"
		for(var/gas in required_air)
			parts += "* [gas]: [required_air[gas]] kPa"
	desc = parts.Join("<br>")

/datum/starship_repair_requirement/room/proc/check_room(datum/starship_repair_room/room, obj/machinery/computer/starship_repair/console)
	for(var/required_thing in required_contents)
		var/have = room.contents[required_thing]
		var/wanted = required_contents[required_thing]
		if(have < wanted)
			return "[initial(required_thing.name)]: [have] / [wanted]"

	if(!isnull(required_air))
		for(var/turf/tile in room.internal_tiles)
			var/datum/gas_mixture/air = tile.get_readonly_air()
			for(var/gas in ALL_GASES)
				var/moles
				switch(gas)
					if(OXYGEN)
						moles = air.oxygen()
					if(CARBON_DIOXIDE)
						moles = air.carbon_dioxide()
					if(NITROGEN)
						moles = air.nitrogen()
					if(TOXINS)
						moles = air.toxins()
					if(SLEEPING_AGENT)
						moles = air.sleeping_agent()
					if(AGENT_B)
						moles = air.agent_b()
				if(!required_gases[gas])
					if(moles > 0.1)
						return "Contaminated with [gas] at ([tile.x], [tile.y])"
					else
						continue
				var/partial_pressure = moles * R_IDEAL_GAS_EQUATION * air.temperature() / CELL_VOLUME
				var/wanted = required_gases[gas]
				if(partial_pressure < 0.95 * wanted || partial_pressure > 1.05 * wanted)
					return "[gas]: [partial_pressure] kPa / [wanted] kPa at ([tile.x], [tile.z])"

/datum/starship_repair_requirement/room/breakroom
	name = "Break Room"
	desc = "A room for the crew to hang out when they really should be somewhere else."
	required_contents = list(
		/obj/machinery/kitchen_machine/microwave = 1,
		/obj/structure/table = 1,
		/obj/structure/chair = 2,
		/obj/machinery/economy/vending = 2
	)

/datum/starship_repair_requirement/room/kitchen
	name = "Kitchen"
	desc = "A place to cook fruits, vegetables, and former crew."
	required_contents = list(
		/obj/machinery/kitchen_machine/grill = 1,
		/obj/machinery/kitchen_machine/oven = 1,
		/obj/structure/table = 2,
		/obj/machinery/economy/vending/dinnerware = 1
	)

/datum/starship_repair_requirement/room/bar
	name = "Bar"
	desc = "Booze is an essential part of the pre-flight checklist."
	required_contents = list(
		/obj/machinery/chem_dispenser/beer = 1,
		/obj/machinery/chem_dispenser/soda = 1,
		/obj/machinery/economy/vending/boozeomat = 1
	)

/datum/starship_repair_requirement/room/hydroponics
	name = "Hydroponics"
	desc = "Somewhere to grow weeds."
	required_contents = list(
		/obj/machinery/hydroponics/constructable = 4,
		/obj/machinery/economy/vending/hydronutrients = 1,
		/obj/machinery/economy/vending/hydronseeds = 1
	)

/datum/starship_repair_requirement/room/chemistry
	name = "Chemistry Lab"
	desc = "For making medicine, drugs, or explosions."
	required_contents = list(
		/obj/machinery/chem_master = 1,
		/obj/machinery/chem_dispenser = 1,
		/obj/machinery/chem_heater = 1,
		/obj/item/reagent_containers/glass/beaker/large = 2,
		/obj/structure/table = 1,
		/obj/structure/chair = 1
	)

/datum/starship_repair_requirement/room/medical
	name = "Medbay"
	desc = "A place to fix little boo-boos."
	required_contents = list(
		/obj/machinery/economy/vending/medical = 1,
		/obj/machinery/sleeper = 1,
		/obj/machinery/bodyscanner = 1,
		/obj/machinery/optable = 1
	)

/datum/starship_repair_requirement/room/cloning
	name = "Cloning"
	desc = "A place to fix big boo-boos."
	required_contents = list(
		/obj/machinery/clonepod = 1,
		/obj/machinery/computer/cloning = 1,
		/obj/machinery/clonescanner = 1,
		/obj/machinery/atmospherics/unary/cryo_cell = 1,
		/obj/machinery/atmospherics/unary/thermomachine = 1,
		/obj/machinery/atmospherics/portable/canister = 1
	)

/datum/starship_repair_requirement/room/dorms
	name = "Dormitories"
	desc = "Snoring or non-snoring?"
	required_contents = list(
		/obj/structure/bed = 4
	)

/datum/starship_repair_requirement/room/cargo_bay
	name = "Cargo Bay"
	desc = "Storage space for all the stuff they've righfully stolen."
	minimum_size = 25
	required_air = null
	requires_power = FALSE

/datum/starship_repair_requirement/room/bridge
	name = "Bridge"
	desc = "The pilot's bedroom."
	required_contents = list(
		/obj/machinery/computer/shuttle = 1,
		/obj/machinery/computer = 5,
		/obj/structure/chair = 1
	)

#undef OXYGEN
#undef CARBON_DIOXIDE
#undef NITROGEN
#undef TOXINS
#undef SLEEPING_AGENT
#undef AGENT_B
#undef ALL_GASES

#undef NORMAL_AIR
#undef VOX_BOX
#undef PURE_PLASMA
#undef BURN_MIX
#undef VACUUM
