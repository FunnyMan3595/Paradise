/datum/station_goal/secondary/random_bulk_reagent/medchem
	name = "Random Bulk Medicine"
	department = "Medbay"
	abstract = FALSE

/datum/station_goal/secondary/random_bulk_reagent/medchem/randomize_params()
	..()
	account = GLOB.station_money_database.get_account_by_department(DEPARTMENT_MEDICAL)
	reward = SSeconomy.credits_per_medchem_goal
	report_message = "Doctor, I've got a fever, and the only prescription, is more [initial(reagent_type.name)]. No, really, send us [amount] units of it, please."
