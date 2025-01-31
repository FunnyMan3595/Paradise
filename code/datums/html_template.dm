#define TAG_INVALID			0
#define TAG_IF				1
#define TAG_ELSE			2
#define TAG_ENDIF			3
#define TAG_FOR				4
#define TAG_ENDFOR			5
#define TAG_ALIAS			6
#define TAG_SIMPLE			7
#define TAG_INLINE_IF		8
#define TAG_DEFAULT			9

#define MODIFIER_NONE			0
#define MODIFIER_NAME			1
#define MODIFIER_REF			2
#define MODIFIER_LITERAL		3
#define MODIFIER_PENCODE		4
#define MODIFIER_ADMIN_PENCODE	5

#define SELECTOR_START			1
#define SELECTOR_NAME			2
#define SELECTOR_VAR			3
#define SELECTOR_INDEX			4
#define SELECTOR_QUOTED			5
#define SELECTOR_MODIFIER 		6

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
			break
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
			ASSERT(length(split_tag) >= next + 4)
			ASSERT(split_tag[next] == " ")
			switch(split_tag[next + 1])
				if("?")
					tag.tag_type = TAG_INLINE_IF
					ASSERT(length(split_tag) >= next + 6)
					ASSERT(split_tag[next + 2] == " ")
					next = tag.parse_selector(split_tag, next + 3)
					ASSERT(length(split_tag) >= next + 4)
					ASSERT(split_tag[next] == " ")
					ASSERT(split_tag[next + 1] == ":")
					ASSERT(split_tag[next + 2] == " ")
					next = tag.parse_selector(split_tag, next + 3)
					ASSERT(length(split_tag) == next - 1)
				if("or")
					tag.tag_type = TAG_DEFAULT
					ASSERT(length(split_tag) >= next + 4)
					ASSERT(split_tag[next + 1] == " ")
					ASSERT(split_tag[next + 2] == "default")
					ASSERT(split_tag[next + 3] == " ")
					next = tag.parse_selector(split_tag, next + 4)
					ASSERT(length[split_tag]) == next - 1)
				else
					CRASH("Invalid token [split_tag[next]] after selector.")

	if(tag.tag_type == TAG_INVALID)
		CRASH("Tag '[split_tag.Join("")]' was recognized, but did not become a valid tag. This is a bug in the template engine.")
	return tag

/datum/html_template_tag
	var/tag_type = TAG_INVALID
	var/parameters = list()

/datum/html_template_tag/proc/parse_selector(split_tag, start, is_index = FALSE)
	var/next = start
	var/datum/html_template_selector/selector = new()
	while(next <= length(split_tag))
		switch(split_tag[next])
			if(" ")
				if(is_index)
					CRASH("Index selector not closed.")
				break
			if("]")
				if(!is_index)
					CRASH("Index selector closed when none was open.")
				break
			if(".")
				assert(length(split_tag) >= next + 1)
				assert(SShtml_templates.name_matcher.Find(split_tag[next + 1]) == 1)
				selector.add_piece(SELECTOR_VAR, split_tag[next + 1])
				next += 2
			if(":")
				assert(length(split_tag) >= next + 1)
				switch(split_tag[next + 1])
					if("name")
						selector.add_piece(SELECTOR_MODIFIER, MODIFIER_NAME)
					if("ref")
						selector.add_piece(SELECTOR_MODIFIER, MODIFIER_REF)
					if("literal")
						selector.add_piece(SELECTOR_MODIFIER, MODIFIER_LITERAL)
					if("pencode")
						selector.add_piece(SELECTOR_MODIFIER, MODIFIER_PENCODE)
					if("admin_pencode")
						selector.add_piece(SELECTOR_MODIFIER, MODIFIER_ADMIN_PENCODE)
					else
						CRASH("Invalid modifier '[split_tag[next + 1]]'")
				next += 2
			if(

/datum/html_template_tag/New(raw)

REGISTER_HTML_TEMPLATE(test_template, {"
This is a {test}!
Yup, just {testing} stuff.
"})

REGISTER_HTML_TEMPLATE(test_template_2, {"
MORE!
"})
