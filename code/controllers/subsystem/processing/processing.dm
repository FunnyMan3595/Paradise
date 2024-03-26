//Used to process objects. Fires once every second.

SUBSYSTEM_DEF(processing)
	name = "Processing"
	priority = FIRE_PRIORITY_PROCESS
	flags = SS_BACKGROUND|SS_POST_FIRE_TIMING|SS_NO_INIT
	wait = 10

	var/stat_tag = "P" //Used for logging
	var/list/processing = list()
	var/list/currentrun = list()
	offline_implications = "Objects using the default processor will no longer process. Shuttle call recommended."

/datum/controller/subsystem/processing/get_stat_details()
	return "[stat_tag]:[length(processing)]"

/datum/controller/subsystem/processing/get_metrics()
	. = ..()
	var/list/cust = list()
	cust["processing"] = length(processing)
	.["custom"] = cust

/datum/controller/subsystem/processing/fire(resumed = 0)
	if(!resumed)
		currentrun = processing.Copy()
	//cache for sanic speed (lists are references anyways)
	var/list/current_run = currentrun

	while(current_run.len)
		var/datum/thing = current_run[current_run.len]
		current_run.len--
		if(QDELETED(thing))
			processing -= thing
		else if(thing.process(wait) == PROCESS_KILL)
			// fully stop so that a future START_PROCESSING will work
			STOP_PROCESSING(src, thing)
		if(MC_TICK_CHECK)
			return

/datum/proc/process()
	set waitfor = 0
	var/options = list(1,2,3,4,5,6,7,8,9)
	while(length(options))
		var/chosen = pick_n_take(options)
		var/fake_ckey = "fake[chosen]"
		SSchat.queue(fake_ckey, list("TEST_[fake_ckey]"))
