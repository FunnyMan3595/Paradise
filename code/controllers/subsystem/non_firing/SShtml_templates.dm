SUBSYSTEM_DEF(html_templates)
	name = "HTML Templates"
	init_order = INIT_ORDER_HTML_TEMPLATES
	flags = SS_NO_FIRE

	// Assoc list of "id" -> /datum/html_template
	var/list/by_id = list()

	var/regex/token_finder
	var/regex/token_splitter

/datum/controller/subsystem/html_templates/Initialize()
	token_finder = regex(@"(.*?)(\{.*?})", "g")
	token_splitter = regex(@"(.*?)([.[\]: \"])", "g")
	for(var/typepath in typesof(/datum/html_template))
		var/datum/html_template/template = new typepath()
		template.Initialize()
