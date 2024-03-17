/datum/station_goal/secondary/variety_reagent/bar
	name = "Variety of Drinks"
	progress_type = /datum/secondary_goal_progress/variety_reagent
	department = "Bar"
	generic_name_plural = "alcoholic drinks"
	abstract = FALSE

/datum/station_goal/secondary/variety_reagent/bar/randomize_params()
	..()
	report_message = "We're hosting a party, and need a variety of alcoholic drinks. Send us at least [amount_per] units of [different_types] different ones. Keep them separate, and don't include anything too simple; we have our own booze dispenser."
