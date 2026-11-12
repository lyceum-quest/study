## CHANGELOG.md as the What's new page shows it, ported from `src/Changelog.elm`.
## The file follows a small part of Keep a Changelog: `## [version]` headings,
## `### Section` headings, and `- item` bullets (continued on indented lines).
## Internal sections and HTML comments (release drafts) are left out, and so are
## versions with nothing left to show. Items are plain text: `**bold**`,
## backticks, and `[text](url)` keep only their text.
Changelog := [].{

	Version : { name : Str, sections : List(Section) }

	## A version's bullets under a `### title`; `title` is "" for bullets before
	## any section heading.
	Section : { title : Str, items : List(Str) }

	## The versions in file order (newest first in CHANGELOG.md).
	parse : Str -> List(Version)
	parse = |text| {
		start = { versions: [], in_comment: Bool.False, internal: Bool.False, item: None }
		flush(lines(text).fold(start, step))
			.versions
			.map(|version| { ..version, sections: version.sections.keep_if(|section| !section.items.is_empty()) })
			.keep_if(|version| !version.sections.is_empty())
	}
}

## Versions, sections and items are appended, so the last of each is the one
## being filled. `item` is the bullet being read, which may continue on the
## following lines.
State : { versions : List(Changelog.Version), in_comment : Bool, internal : Bool, item : [Some(Str), None] }

step : State, Str -> State
step = |state, line| {
	trimmed = js_trim(line)
	if state.in_comment {
		{ ..state, in_comment: !trimmed.contains("-->") }
	} else if trimmed.starts_with("<!--") {
		flush({ ..state, in_comment: !trimmed.contains("-->") })
	} else if trimmed.starts_with("## ") {
		name = js_trim(trimmed.drop_prefix("## ")).replace_each("[", "").replace_each("]", "")
		flushed = flush(state)
		{ ..flushed, versions: flushed.versions.append({ name, sections: [] }), internal: Bool.False }
	} else if trimmed.starts_with("### ") {
		title = js_trim(trimmed.drop_prefix("### "))
		flushed = flush(state)
		{
			..flushed,
			# Elm's `String.toLower`; Unicode lowercasing yields "internal" only from ASCII.
			internal: title.with_ascii_lowercased() == "internal",
			versions: map_last(flushed.versions, |version| { ..version, sections: version.sections.append({ title, items: [] }) }),
		}
	} else if trimmed.starts_with("- ") {
		started = flush(state)
		if started.versions.is_empty() {
			started
		} else {
			{
				..started,
				item: Some(trimmed.drop_prefix("- ")),
				versions: map_last(
					started.versions,
					|version| if version.sections.is_empty() { ..version, sections: [{ title: "", items: [] }] } else version,
				),
			}
		}
	} else if trimmed == "" {
		flush(state)
	} else {
		match state.item {
			Some(item) => { ..state, item: Some("${item} ${trimmed}") }
			None => state
		}
	}
}

## Adds the bullet being read to the current section, unless it is internal.
flush : State -> State
flush = |state| match state.item {
	Some(item) =>
		if state.internal {
			{ ..state, item: None }
		} else {
			{
				..state,
				item: None,
				versions: map_last(
					state.versions,
					|version| { ..version, sections: map_last(version.sections, |section| { ..section, items: section.items.append(plain(item)) }) },
				),
			}
		}
	None => state
}

map_last : List(a), (a -> a) -> List(a)
map_last = |list, f| match list.last() {
	Ok(last) => list.drop_last(1).append(f(last))
	Err(_) => list
}

## Elm's `String.lines`: split on `\r\n`, `\r` and `\n`.
lines : Str -> List(Str)
lines = |text| text.replace_each("\r\n", "\n").replace_each("\r", "\n").split_on("\n")

## Elm's `String.trim`, which is JavaScript's: Roc's `Str.trim` also strips
## U+0085, U+200E and U+200F but keeps U+FEFF.
js_trim : Str -> Str
js_trim = |text| trim_end(trim_start(text))

trim_start : Str -> Str
trim_start = |text| match js_whitespace.keep_if(|space| text.starts_with(space)) {
	[space, ..] => trim_start(text.drop_prefix(space))
	[] => text
}

trim_end : Str -> Str
trim_end = |text| match js_whitespace.keep_if(|space| text.ends_with(space)) {
	[space, ..] => trim_end(text.drop_suffix(space))
	[] => text
}

## ECMAScript WhiteSpace and LineTerminator code points.
js_whitespace : List(Str)
js_whitespace = [
	"\t", "\n", "\u(0B)", "\u(0C)", "\r", " ", "\u(A0)", "\u(1680)",
	"\u(2000)", "\u(2001)", "\u(2002)", "\u(2003)", "\u(2004)", "\u(2005)",
	"\u(2006)", "\u(2007)", "\u(2008)", "\u(2009)", "\u(200A)",
	"\u(2028)", "\u(2029)", "\u(202F)", "\u(205F)", "\u(3000)", "\u(FEFF)",
]

## Markdown's markers off: `**`, backticks, and `[text](url)` to `text`.
plain : Str -> Str
plain = |text| links(text.replace_each("**", "").replace_each("`", ""))

## Each `[text](url)` to `text`, the first `](` first, taking the last `[`
## before it and the first `)` after it. Stops, leaving the rest as is, at a
## `](` without both.
links : Str -> Str
links = |text| match text.split_first("](") {
	Ok({ before, after: rest }) =>
		match (before.split_last("["), rest.split_first(")")) {
			(Ok(open), Ok(close)) => links("${open.before}${open.after}${close.after}")
			_ => text
		}
	Err(NotFound) => text
}
