/datum/html_template
	var/id
	var/raw
	var/processed

/datum/html_template/proc/Initialize()
	if(!id)
		return

	processed = list()

	var/first = TRUE
	var/regex/splitter = SShtml_templates.token_splitter
	var/last_end = 1
	while(TRUE)
		var/found
		if(first)
			found = splitter.Find(raw, 1)
			first = FALSE
		else
			found = splitter.Find(raw)
		if(found == 0)
			processed += copytext(raw, last_end)
			return
		else
			last_end = splitter.next

		processed += splitter.group[1]
		processed += new /datum/html_template_tag(splitter.group[2])

/datum/html_template_tag
	var/raw

/datum/html_template_tag/New(raw)
	src.raw = raw

REGISTER_HTML_TEMPLATE(test_template, {"
This is a {test}!
Yup, just {testing} stuff.
"})

REGISTER_HTML_TEMPLATE(test_template_2, {"
MORE!
"})
