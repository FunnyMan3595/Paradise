/datum/html_template
	var/id
	var/raw
	var/processed

/datum/html_template/proc/Initialize()
	if(!id)
		return

	processed = list()

	var/first = TRUE
	var/regex/finder = SShtml_templates.token_finder
	var/last_end = 1
	while(TRUE)
		var/found
		if(first)
			found = finder.Find(raw, 1)
			first = FALSE
		else
			found = finder.Find(raw)
		if(found == 0)
			processed += copytext(raw, last_end)
			return
		else
			last_end = finder.next

		processed += finder.group[1]
		processed += parse_tag(finder.group[2])

/datum/html_template/proc/parse_tag(raw)
	var/regex/splitter = SShtml_templates.token_splitter
	var/list/split_tag = list()
	var/last_end = 1
	while(TRUE)
		var/piece
		if(first)
			piece = splitter.Find(raw, 1)
			first = FALSE
		else
			piece = splitter.Find(raw)
		if(piece == 0)
			split_tag += copytext(raw, last_end)
			return
		else
			last_end = splitter.next
		split_tag += splitter.group[1]
		split_tag += splitter.group[2]

	var/datum/html_template_tag/tag = new()
	switch (split_tag[1])
		if("if")
			tag.tag_type = TAG_IF
			ASSERT(length(split_tag) >= 3)
			ASSERT(split_tag[2] == " ")
			var/next = tag.parse_selector(split_tag, 3)
			ASSERT(length(split_tag) == next - 1)
		if("else")
			tag.tag_type = TAG_ELSE
			ASSERT(length(split_tag) == 1)
		if("endif")
			tag.tag_type = TAG_ENDIF
			ASSERT(length(split_tag) == 1)
		if("for")
			tag.tag_type = TAG_FOR
			ASSERT(length(split_tag) >= 7)
			ASSERT(split_tag[2] == " ")
			tag.params += split_tag[3]
			ASSERT(split_tag[4] == " ")
			ASSERT(split_tag[5] == "in")
			ASSERT(split_tag[6] == " ")
			var/next = tag.parse_selector(split_tag, 7)
			ASSERT(length(split_tag) == next - 1)
		if("endfor")
			tag.tag_type = TAG_ENDFOR
			ASSERT(length(split_tag) == 1)
		if("alias")
			tag.tag_type = TAG_ALIAS
			ASSERT(length(split_tag) >= 7)
			ASSERT(split_tag[2] == " ")
			var/next = tag.parse_selector(split_tag, 3)
			ASSERT(length(split_tag) == next + 3)
			ASSERT(split_tag[next] == " ")
			ASSERT(split_tag[next + 1] == "as")
			ASSERT(split_tag[next + 2] == " ")
			tag.params += split_tag[next + 3]
		else
			var/next = tag.parse_selector(split_tag, 1)
			if(next == length(split_tag) + 1)
				tag.tag_type = TAG_SIMPLE
				var/datum/html_template_selector/selector = tag.params[1]
				ASSERT(selector.selector_type != SELECTOR_LITERAL)
				return tag
			else if(split_tag[next] == ":")
				ASSERT(length(split_tag) == next)
				switch(split_tag[1])
					if("name")
						tag.tag_type = TAG_NAME
					if("ref")
						tag.tag_type = TAG_REF
					if("literal")
						tag.tag_type = TAG_LITERAL
					if("pencode")
						tag.tag_type = TAG_PENCODE
					if("admin_pencode")
						tag.tag_type = TAG_ADMIN_PENCODE
				return tag
			ASSERT(length(split_tag) >= next + 5)
			ASSERT(split_tag[next] == " ")
			switch(split_tag[next + 1])
				if("?")
					ASSERT(length(split_tag) >= next + 6)
					ASSERT(split_tag[next] = " ")
					next = tag.parse_selector(split_tag, next + 1)
					ASSERT(length(split_tag) >= next + 4)
					ASSERT(split_tag[next] = " ")
					ASSERT(split_tag[next + 1] = ":")
					ASSERT(split_tag[next + 2] = " ")
					next = tag.parse_selector(split_tag, next + 3)
					ASSERT(length(split_tag) == next - 1)
				if("or")
					ASSERT(length(split_tag) >= next + 9)
					next = tag.parse_selector(split_tag, 1)
					ASSERT(length[split_tag] >= mext + 



/datum/html_template_tag



/datum/html_template_tag/New(raw)

REGISTER_HTML_TEMPLATE(test_template, {"
This is a {test}!
Yup, just {testing} stuff.
"})

REGISTER_HTML_TEMPLATE(test_template_2, {"
MORE!
"})
