/datum/secondary_goal_tracker
	var/datum/secondary_goal_progress/real_progress
	var/datum/secondary_goal_progress/temporary_progress
	var/datum/station_goal/secondary/goal

/datum/secondary_goal_tracker/New(datum/station_goal/secondary/goal_in, datum/secondary_goal_progress/progress)
	goal = goal_in
	real_progress = progress
	temporary_progress = progress.Copy()

/datum/secondary_goal_tracker/proc/register(shuttle)
	RegisterSignal(shuttle, COMSIG_CARGO_BEGIN_SCAN,		PROC_REF(reset_tempporary_progress))
	RegisterSignal(shuttle, COMSIG_CARGO_BEGIN_SELL,		PROC_REF(reset_tempporary_progress))
	RegisterSignal(shuttle, COMSIG_CARGO_CHECK_SELL,		PROC_REF(check_for_progress))
	RegisterSignal(shuttle, COMSIG_CARGO_DO_PRIORITY_SELL,	PROC_REF(update_progress))
	RegisterSignal(shuttle, COMSIG_CARGO_SEND_ERROR,		PROC_REF(update_progress))
	RegisterSignal(shuttle, COMSIG_CARGO_END_SELL,			PROC_REF(check_for_completion))

/datum/secondary_goal_tracker/proc/unregister(shuttle)
	UnregisterSignal(shuttle, COMSIG_CARGO_BEGIN_SCAN)
	UnregisterSignal(shuttle, COMSIG_CARGO_BEGIN_SELL)
	UnregisterSignal(shuttle, COMSIG_CARGO_CHECK_SELL)
	UnregisterSignal(shuttle, COMSIG_CARGO_DO_PRIORITY_SELL)
	UnregisterSignal(shuttle, COMSIG_CARGO_SEND_ERROR)
	UnregisterSignal(shuttle, COMSIG_CARGO_END_SELL)

// Resets the temporary porgress to match the real progress.
/datum/secondary_goal_tracker/proc/reset_tempporary_progress(obj/docking_port/mobile/supply/shuttle)
	SIGNAL_HANDLER  // COMSIG_CARGO_BEGIN_SCAN, COMSIG_CARGO_BEGIN_SELL
	temporary_progress = real_progress.Copy()
	real_progress.start_shipment()

// Checks for temporary goal progress when selling a cargo item.
/datum/secondary_goal_tracker/proc/check_for_progress(obj/docking_port/mobile/supply/shuttle, atom/movable/thing)
	SIGNAL_HANDLER  // COMSIG_CARGO_CHECK_SELL
	return temporary_progress.update(thing)

// Update real goal progress when selling a cargo item.
/datum/secondary_goal_tracker/proc/update_progress(obj/docking_port/mobile/supply/shuttle, atom/movable/thing, datum/economy/cargo_shuttle_manifest/manifest)
	SIGNAL_HANDLER  // COMSIG_CARGO_DO_PRIORITY_SELL, COMSIG_CARGO_DO_SELL, COMSIG_CARGO_SEND_ERROR
	real_progress.update(thing, manifest)

/datum/secondary_goal_tracker/proc/check_for_completion(obj/docking_port/mobile/supply/shuttle, datum/economy/cargo_shuttle_manifest/manifest)
	SIGNAL_HANDLER  // COMSIG_CARGO_END_SELL
	if(real_progress.check_complete(manifest))
		goal.completed = TRUE
		unregister(SSshuttle.supply)


/datum/secondary_goal_progress
	var/personal_account

/datum/secondary_goal_progress/proc/configure(datum/station_goal/secondary/goal)
	personal_account = goal.personal_account

/datum/secondary_goal_progress/proc/Copy()
	return new type

// Override for custom shipment start behavior
// (e.g. ampount-per-shipment tracking)
// Only called on the real progress tracker.
/datum/secondary_goal_progress/proc/start_shipment()
	return

// Check the item to see if it belongs to this goal.
// Update the manifest accodingly, if provided.
// Return values from code/__DEFINES/supply_defines.dm.
// Use COMSIG_CARGO_SELL_PRIORITY, not COMSIG_CARGO_SELL_NORMAL.
/datum/secondary_goal_progress/proc/update(atom/movable/AM, datum/economy/cargo_shuttle_manifest/manifest = null)
	return

// Check to see if this goal has been completed.
// Update the manifest accordingly.
// Returns whether the goal was completed.
/datum/secondary_goal_progress/proc/check_complete(datum/economy/cargo_shuttle_manifest/manifest)
	return FALSE

/datum/secondary_goal_progress/proc/three_way_reward(datum/economy/cargo_shuttle_manifest/manifest, department, department_account, reward, message)
	var/datum/economy/line_item/supply_item = new
	supply_item.account = SSeconomy.cargo_account
	supply_item.credits = reward / 3
	supply_item.reason = message
	manifest.line_items += supply_item

	var/datum/economy/line_item/department_item = new
	department_item.account = department_account
	department_item.credits = reward / 3
	department_item.reason = message
	manifest.line_items += department_item

	var/datum/economy/line_item/personal_item = new
	personal_item.account = personal_account || department_account
	personal_item.credits = reward / 3
	personal_item.reason = message
	manifest.line_items += personal_item

	send_requests_console_message(message, "Central Command", department, "Stamped with the Central Command rubber stamp.", null, RQ_NORMALPRIORITY)
