/datum/station_goal/secondary/variety_reagent
	name = "Variety of Reagent"
	progress_type = /datum/secondary_goal_progress/variety_reagent
	var/different_types = 10
	var/amount_per = 50
	var/account
	var/generic_name_plural = "reagents"
	var/reward

/datum/secondary_goal_progress/variety_reagent
	var/list/reagents_sent = list()
	var/department
	var/needed
	var/amount_per
	var/account
	var/reward
	var/generic_name_plural

/datum/secondary_goal_progress/variety_reagent/configure(datum/station_goal/secondary/variety_reagent/goal)
	department = goal.department
	needed = goal.different_types
	amount_per = goal.amount_per
	account = goal.account
	reward = goal.reward
	generic_name_plural = goal.generic_name_plural

/datum/secondary_goal_progress/variety_reagent/Copy()
	var/datum/secondary_goal_progress/variety_reagent/copy = new
	copy.reagents_sent = reagents_sent.Copy()
	copy.department = department
	copy.needed = needed
	copy.amount_per = amount_per
	copy.account = account
	copy.reward = reward
	copy.generic_name_plural = generic_name_plural
	return copy

/datum/secondary_goal_progress/variety_reagent/update(atom/movable/AM, datum/economy/cargo_shuttle_manifest/manifest = null)
	if(!istype(AM, /obj/item/reagent_containers))
		return

	var/obj/item/reagent_containers/container = AM
	// No reagents, ignore.
	if(!container.reagents.reagent_list)
		return

	var/datum/reagent/reagent = container.reagents.get_master_reagent()

	// Make sure it's for our department.
	if(reagent.goal_department != department)
		return

	// Isolated reagents only, please.
	if(length(container.reagents.reagent_list) != 1)
		if(!manifest)
			return COMSIG_CARGO_SELL_WRONG
		var/datum/economy/line_item/item = new
		item.account = account
		item.credits = 0
		item.reason = "That [reagent.name] seems to be mixed with something else. Send it by itself, please."
		manifest.line_items += item
		return COMSIG_CARGO_SELL_WRONG

	// No easy reagents allowed.
	if(reagent.goal_difficulty == REAGENT_GOAL_SKIP)
		if(!manifest)
			return COMSIG_CARGO_SELL_WRONG
		var/datum/economy/line_item/item = new
		item.account = account
		item.credits = 0
		item.reason = "We don't need [reagent.name]. Send something better."
		manifest.line_items += item
		return COMSIG_CARGO_SELL_WRONG
		
	// Make sure there's enough.
	if(reagent.volume < amount_per)
		if(!manifest)
			return COMSIG_CARGO_SELL_WRONG
		var/datum/economy/line_item/item = new
		item.account = account
		item.credits = 0
		item.reason = "That batch of [reagent.name] was too small; send at least [amount_per] units."
		manifest.line_items += item
		return COMSIG_CARGO_SELL_WRONG

	if(reagents_sent[reagent.id])
		if(!manifest)
			return COMSIG_CARGO_SELL_WRONG
		var/datum/economy/line_item/item = new
		item.account = account
		item.credits = 0
		item.reason = "You already sent us [reagent.name]."
		manifest.line_items += item
		return COMSIG_CARGO_SELL_WRONG

	reagents_sent += reagent.id

	if(!manifest)
		return COMSIG_CARGO_SELL_PRIORITY
	var/datum/economy/line_item/item = new
	item.account = account
	item.credits = 0
	item.reason = "Received [initial(reagent.name)]."
	item.zero_is_good = TRUE
	manifest.line_items += item
	return COMSIG_CARGO_SELL_PRIORITY

/datum/secondary_goal_progress/variety_reagent/check_complete(datum/economy/cargo_shuttle_manifest/manifest)
	if(length(reagents_sent) < needed)
		return

	var/datum/economy/line_item/supply_item = new
	supply_item.account = SSeconomy.cargo_account
	supply_item.credits = reward / 2
	supply_item.reason = "Secondary goal complete: [needed] different [generic_name_plural]."
	manifest.line_items += supply_item

	var/datum/economy/line_item/department_item = new
	department_item.account = account
	department_item.credits = reward / 2
	department_item.reason = "Secondary goal complete: [needed] different [generic_name_plural]."
	manifest.line_items += department_item

	return TRUE
