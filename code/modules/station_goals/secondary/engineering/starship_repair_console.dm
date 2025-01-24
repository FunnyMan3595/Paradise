/obj/machinery/computer/starship_repair
	name = "starship repair console"
	desc = "Used to request and complete starship repair goals"
	icon_screen = "power"
	icon_keyboard = "power_key"
	power_state = ACTIVE_POWER_USE
	idle_power_consumption = 20
	active_power_consumption = 80
	light_color = LIGHT_COLOR_ORANGE
	circuit = /obj/item/circuitboard/starship_repair

/obj/machinery/computer/starship_repair/attack_ai(mob/user)
	attack_hand(user)

/obj/machinery/computer/starship_repair/attack_hand(mob/user)
	add_fingerprint(user)
	if(stat & (BROKEN|NOPOWER))
		return
	ui_interact(user)

/obj/machinery/computer/starship_repair/ui_state(mob/user)
	return GLOB.default_state

/obj/machinery/computer/starship_repair/ui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "StarshipRepair", name)
		ui.open()

/obj/machinery/computer/starship_repair/ui_data(mob/user)
	var/list/data = list()

	var/obj/docking_port/stationary/dock = SSshuttle.getDock("repair_dock")
	data["docked"] = !isnull(dock?.get_docked())

	return data

/obj/machinery/computer/starship_repair/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return

	add_fingerprint(ui.user)

	. = TRUE
	switch(action)
		if("request")
			request(ui.user)
		if("complete")
			complete(ui.user)

/obj/machinery/computer/starship_repair/proc/request(mob/user)
	var/datum/map_template/shuttle/damaged_ship/dock_test/template = new()
	var/error = SSshuttle.try_load_template(template)
	if(istext(error))
		audible_message("<span class='notice'>[src] beeps, \"[error]\"")
		return

	var/obj/docking_port/stationary/dock = SSshuttle.getDock("repair_dock")
	if(dock)
		SSshuttle.imported_shuttle.ripple_duration = 30 SECONDS
		SSshuttle.imported_shuttle.callTime = 30 SECONDS
		SSshuttle.imported_shuttle.should_transit = FALSE
		SSshuttle.send_imported_shuttle(dock)
		audible_message("<span class='notice'>[src] beeps, \"Damaged starship incoming. Please stand clear of the docking zone.\"</span>")
	else
		audible_message("<span class='notice'>[src] beeps, \"Unable to locate docking zone.\"</span>")
		SSshuttle.delete_imported_shuttle()

/obj/machinery/computer/starship_repair/proc/complete(mob/user)
	var/obj/docking_port/stationary/dock = SSshuttle.getDock("repair_dock")
	if(dock)
		var/obj/docking_port/mobile/ship = dock.get_docked()
		if(isnull(ship))
			audible_message("<span class='notice'>[src] beeps, \"No starship present.\"</span>")
			return

		ship.jumpToNullSpace()
		audible_message("<span class='notice'>[src] beeps, \"Starship repair successful.\"</span>")
	else
		audible_message("<span class='notice'>[src] beeps, \"Unable to locate docking zone.\"</span>")
