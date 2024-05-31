/datum/disease/zombie
	name = "Necrotizing Plague"
	medical_name = "Advanced Resurrection Syndrome"
	desc = "This virus infects humanoids and drives them insane with a hunger for flesh, along with possessing regenerative abilities."
	max_stages = 7
	spread_text = "Blood and Saliva"
	spread_flags = BLOOD
	cure_text = "Anti-plague viral solutions"
	cures = list()
	agent = ""
	viable_mobtypes = list(/mob/living/carbon/human)
	severity = BIOHAZARD
	allow_dead = TRUE
	disease_flags = CAN_CARRY
	virus_heal_resistant = TRUE
	stage_prob = 1
	cure_chance = 20
	/// How far this particular virus is in being cured (0-4)
	var/cure_stage = 0

/datum/disease/zombie/stage_act()
	if(stage == 8)
		// adminbus for immediate zombie
		var/mob/living/carbon/human/H = affected_mob
		if(!istype(H))
			return FALSE
		for(var/obj/item/organ/limb as anything in H.bodyparts)
			if(!(limb.status & ORGAN_DEAD) && !limb.is_robotic())
				limb.necrotize(TRUE, TRUE)

	if(!..())
		return FALSE
	if(HAS_TRAIT(affected_mob, TRAIT_I_WANT_BRAINS) || affected_mob.mind?.has_antag_datum(/datum/antagonist/zombie))
		handle_rot(TRUE)
		stage = 7
		return FALSE
	switch(stage)
		if(1) // cured by lvl 1 cure
			if(prob(4))
				to_chat(affected_mob, "<span class='warning'>[pick("Your scalp itches.", "Your skin feels flakey.")]</span>")
			else if(prob(5))
				to_chat(affected_mob, "<span class='warning'>Your [pick("back", "arm", "leg", "elbow", "head")] itches.</span>")
		if(2)
			if(prob(2))
				to_chat(affected_mob, "<span class='danger'>Mucous runs down the back of your throat.</span>")
			else if(prob(5))
				to_chat(affected_mob, "<span class='warning'>[pick("You feel hungry.", "You crave for something to eat.")]</span>")
		if(3) // cured by lvl 2 cure
			if(prob(2))
				affected_mob.emote("sneeze")
			else if(prob(2))
				affected_mob.emote("cough")
			else if(prob(5))
				to_chat(affected_mob, "<span class='warning'><i>[pick("So hungry...", "You'd kill someone for a bite of food...", "Hunger cramps seize you...")]</i></span>")
			if(prob(5))
				affected_mob.adjustToxLoss(1)
		if(4) // shows up on medhuds
			if(prob(2))
				affected_mob.emote("stare")
			else if(prob(2))
				affected_mob.emote("drool")
			else if(prob(5))
				to_chat(affected_mob, "<span class='danger'>You feel a cold sweat form.</span>")
			if(prob(25))
				affected_mob.adjustToxLoss(1)
		if(5, 6)  // 5 is cured by lvl 3 cure. 6+ needs lvl 4 cure
			var/turf/T = get_turf(affected_mob)
			if(T.get_lumcount() >= 0.5)
				if(prob(5))
					to_chat(affected_mob, "<span class='danger'>Those lights seem bright. It stings.</span>")
				if(prob(25))
					affected_mob.adjustFireLoss(2)
			if(prob(2))
				affected_mob.emote("drool")
			if(stage == 6 && !affected_mob.reagents.has_reagent("zombiecure3")) // cure 3 can delay it, but not cure it
				if(prob(10))
					to_chat(affected_mob, "<span class='danger zombie'>You feel your flesh rotting.</span>")
				handle_rot()
		if(7)
			if(!handle_rot(TRUE))
				stage = 6
				return



/datum/disease/zombie/proc/handle_rot(forced = FALSE)
	if(!prob(20) && !forced && affected_mob.stat != DEAD)
		return FALSE
	var/mob/living/carbon/human/H = affected_mob
	if(!istype(H))
		return FALSE
	for(var/obj/item/organ/limb as anything in H.bodyparts)
		if(!(limb.status & ORGAN_DEAD) && !limb.vital && !limb.is_robotic())
			limb.necrotize()
			return FALSE

	for(var/obj/item/organ/limb as anything in H.bodyparts)
		if(!(limb.status & ORGAN_DEAD) && !limb.is_robotic())
			limb.necrotize(FALSE, TRUE)
			return FALSE

	if(!HAS_TRAIT(affected_mob, TRAIT_I_WANT_BRAINS))
		affected_mob.AddComponent(/datum/component/zombie_regen)
		ADD_TRAIT(affected_mob, TRAIT_I_WANT_BRAINS, ZOMBIE_TRAIT)
		affected_mob.med_hud_set_health()
		affected_mob.med_hud_set_status()
		affected_mob.update_hands_hud()
		H.update_body()
	if(affected_mob.mind && !affected_mob.mind.has_antag_datum(/datum/antagonist/zombie))
		affected_mob.mind.add_antag_datum(/datum/antagonist/zombie)
	return TRUE


/datum/disease/zombie/handle_cure_testing(has_cure = FALSE)
	if(has_cure && prob(cure_chance))
		stage = max(stage - 1, 0)

	if(stage <= 0 && has_cure)
		cure()
		return FALSE
	return TRUE

/datum/disease/zombie/proc/update_cure_stage()
	for(var/datum/reagent/zombie_cure/reag in affected_mob.reagents?.reagent_list)
		cure_stage = max(cure_stage, reag.cure_level)
	if(cure_stage)
		var/stages = list("Stabilized", "Weakened", "Faltering", "Suppressed")
		name = "[stages[cure_stage]] [initial(name)]"

/datum/disease/zombie/has_cure()
	update_cure_stage()
	var/required_reagent = (stage + 1) / 2 // stage 1 can be cured by cure 1, stage 3 with 2, stage 5 with 3, stage 7 with 4
	return cure_stage >= required_reagent

/datum/disease/zombie/cure()
	affected_mob.mind?.remove_antag_datum(/datum/antagonist/zombie)
	REMOVE_TRAIT(affected_mob, TRAIT_I_WANT_BRAINS, ZOMBIE_TRAIT)
	qdel(affected_mob.GetComponent(/datum/component/zombie_regen))
	affected_mob.med_hud_set_health()
	affected_mob.med_hud_set_status()
	return ..()
