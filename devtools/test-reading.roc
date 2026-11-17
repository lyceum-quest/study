app [main!] {
	fsrs: "../packages/fsrs/main.roc",
	json: "../packages/json/main.roc",
	study: "../packages/study/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.Stdout
import json.JsonValue
import study.Reading
import study.Study
import study.Words

# Checks reading goals (packages/study/Reading.roc): proper names, per-work
# vocabularies, which lemmas are known, coverage and the lemmas a goal needs,
# the learner's pace, and the calculator. Prints a summary and the failures,
# and exits with 1 if any check fails.
main! = |_args| {
	groups = [
		("proper names", name_checks),
		("vocabularies and coverage", coverage_checks),
		("known words", known_checks),
		("reading as evidence", reading_checks),
		("pace and calculator", pace_checks),
		("goals and dates", goal_checks),
	]
	var $failures = []
	for (title, checks) in groups {
		failed = checks.keep_if(|found| found.problem != "")
		Stdout.line!("${(checks.len() - failed.len()).to_str()}/${checks.len().to_str()} ${title}")?
		$failures = $failures.concat(failed)
	}
	if $failures.is_empty() {
		Stdout.line!("All Reading checks pass.")?
		Ok({})
	} else {
		Stdout.line!("\n${$failures.len().to_str()} checks failed:")?
		for found in $failures {
			Stdout.line!("\n${found.name}\n${found.problem}")?
		}
		Err(Exit(1))
	}
}

# A named check; `problem` is "" when it passes.
Check : { name : Str, problem : Str }

check = |name, actual, expected|
	if actual == expected {
		{ name, problem: "" }
	} else {
		{ name, problem: "  roc:      ${Str.inspect(actual)}\n  expected: ${Str.inspect(expected)}" }
	}

day : I64
day = 86400000

t0 : I64
t0 = 1767225600000

found : Str, I64, Str -> Reading.Occurrence
found = |work, position, form| { work, position, form }

lemmas : List((Str, List(Reading.Occurrence)))
lemmas = [
	("ἰησοῦς", [found("luke", 3, "Ἰησοῦς"), found("luke", 1, "Ἰησοῦ"), found("1peter", 5, "ἸΗΣΟΥ")]),
	# Capitalized once, opening a passage: not a name.
	("κύων", [found("2peter", 1, "Κύων")]),
	# Capitalized only in an all-caps heading: not a name.
	("πρεσβύτερος", [found("2john", 2, "ΠΡΕΣΒΥΤΕΡΟΣ"), found("2john", 5, "πρεσβύτερος")]),
	("ῥώμη", [found("romans", 4, "Ῥώμῃ"), found("romans", 9, "Ῥώμῃ")]),
	("ἅγιος", [found("luke", 2, "Ἅγιος"), found("luke", 7, "ἁγίῳ")]),
	("καί", [found("luke", 4, "καὶ"), found("luke", 6, "καὶ"), found("luke", 8, "καὶ"), found("luke", 9, "καί")]),
	("λόγος", [found("luke", 5, "λόγος"), found("luke", 10, "λόγου")]),
	("θεός", [found("luke", 11, "θεὸς")]),
	("ἀρχή", [found("luke", 12, "ἀρχῇ")]),
]

names : Set(Str)
names = Reading.names(lemmas)

luke : Reading.Vocabulary
luke = Reading.vocabularies(lemmas, names).get("luke") ?? { tokens: 0, name_tokens: 0, lemmas: [] }

name_checks : List(Check)
name_checks = [
	check("names", names.to_list().sort_with(|a, b| if a == b Same else if a == "ἰησοῦς" Before else After), ["ἰησοῦς", "ῥώμη"]),
	check("upper Greek", ["Ἰησοῦς", "Ῥώμῃ", "Ἅγιος", "Ω", "ᾼ", "Ἀ"].map(|form| Reading.names([("x", [found("w", 3, "${form}α"), found("w", 4, "${form}α")])]).len()), [1, 1, 1, 1, 1, 1]),
	check("lower Greek", ["ἰησοῦς", "ῥώμῃ", "ἁγίῳ", "ω", "ᾳ"].map(|form| Reading.names([("x", [found("w", 3, form), found("w", 4, form)])]).len()), [0, 0, 0, 0, 0]),
]

coverage_checks : List(Check)
coverage_checks = {
	none = Dict.empty()
	some = Dict.empty().insert("καί", Known).insert("λόγος", Learned)
	[
		check("luke tokens", (luke.tokens, luke.name_tokens), (12, 2)),
		check("luke lemmas by frequency", luke.lemmas, [{ lemma: "καί", count: 4 }, { lemma: "λόγος", count: 2 }, { lemma: "ἅγιος", count: 2 }, { lemma: "θεός", count: 1 }, { lemma: "ἀρχή", count: 1 }]),
		# Names cover 2/12; reaching 95% (11.4 of 12) takes all but one.
		check("standing knowing nothing", Reading.standing(luke, none, 95), { tokens: 12, known_tokens: 2, learned_tokens: 2, unknown: 5, needed: 5 }),
		check("standing knowing καί, λόγος learned", Reading.standing(luke, some, 50), { tokens: 12, known_tokens: 6, learned_tokens: 8, unknown: 3, needed: 0 }),
		check("standing knowing καί, λόγος learned, 90%", Reading.standing(luke, some, 90), { tokens: 12, known_tokens: 6, learned_tokens: 8, unknown: 3, needed: 2 }),
		check("percent rounds down", Reading.percent({ tokens: 12, known_tokens: 11, learned_tokens: 11, unknown: 1, needed: 0 }), 91),
		check("learned percent", Reading.learned_percent({ tokens: 12, known_tokens: 6, learned_tokens: 8, unknown: 3, needed: 0 }), 66),
		check("percent of nothing", Reading.percent({ tokens: 0, known_tokens: 0, learned_tokens: 0, unknown: 0, needed: 0 }), 100),
		check("next words", Reading.next_words(luke, some.insert("ἀρχή", Learning), 3), [{ lemma: "ἅγιος", count: 2, status: Unseen }, { lemma: "θεός", count: 1, status: Unseen }, { lemma: "ἀρχή", count: 1, status: Learning }]),
	]
}

item : Str, [Some(Bool), None], Bool -> Study.Item
item = |lemma, mark, revealed_early| {
	key: "w:1",
	kind: WordItem,
	form: lemma,
	lemma,
	guess: "guess",
	reference: "gloss",
	revealed_early,
	mark,
}

attempt : I64, List(Study.Item) -> Study.Attempt
attempt = |finished_at, items| {
	id: "attempt:${finished_at.to_str()}",
	work: "luke",
	passage: "1.1",
	sentence_id: "s1",
	sentence_text: "text",
	started_at: finished_at - 60000,
	finished_at,
	items,
	rating: Some(Good),
}

attempts : List(Study.Attempt)
attempts = [
	# καί: right on two days 21 days apart: known (two weeks is enough).
	attempt(t0, [item("καί", Some(Bool.True), Bool.False), item("λόγος", Some(Bool.True), Bool.False), item("θεός", Some(Bool.True), Bool.False), item("ἀρχή", Some(Bool.True), Bool.True)]),
	# λόγος: right on two days only 10 apart: learned, not yet known.
	attempt(t0 + 10 * day, [item("λόγος", Some(Bool.True), Bool.False)]),
	attempt(t0 + 21 * day, [item("καί", Some(Bool.True), Bool.False), item("θεός", Some(Bool.True), Bool.False)]),
	# θεός: then missed: learning.
	attempt(t0 + 22 * day, [item("θεός", Some(Bool.False), Bool.False), item("ἀρχή", Some(Bool.True), Bool.True)]),
	# ἀρχή: right in the same day twice and revealed early otherwise: learning.
	attempt(t0 + 30 * day, [item("ἀρχή", Some(Bool.True), Bool.False), item("ἀρχή", None, Bool.False)]),
]

statuses : Dict(Str, I64) -> Dict(Str, Reading.Status)
statuses = |marked| Reading.statuses(attempts, [], Words.cards(attempts, []), marked, [])

# καί missed once in a passage, so it has a word review card, here stable for only 3 days.
unstable : Dict(Str, Words.Card)
unstable = Words.cards([attempt(t0 - day, [item("καί", Some(Bool.False), Bool.False)])], []).map(|_, card| { ..card, card: { ..card.card, stability: 3.0 } })

known_checks : List(Check)
known_checks = {
	plain = statuses(Dict.empty())
	marked = statuses(Dict.empty().insert("λόγος", t0 + day).insert("θεός", t0).insert("ἰησοῦς", t0))
	[
		check("καί known", plain.get("καί"), Ok(Known)),
		check("λόγος 10 days apart", plain.get("λόγος"), Ok(Learned)),
		check("θεός missed last", plain.get("θεός"), Ok(Learning)),
		check("ἀρχή one day", plain.get("ἀρχή"), Ok(Learning)),
		check("unseen", plain.get("ἅγιος").is_ok(), Bool.False),
		check("marked known", marked.get("λόγος"), Ok(Known)),
		check("marked, then missed", marked.get("θεός"), Ok(Learning)),
		check("marked, never answered", marked.get("ἰησοῦς"), Ok(Known)),
		# A word review card not yet stable for two weeks holds the word at learned.
		check("unstable card", Reading.statuses(attempts, [], unstable, Dict.empty(), []).get("καί"), Ok(Learned)),
	]
}

pace_checks : List(Check)
pace_checks = {
	now = t0 + 30 * day
	[
		# 3 lemmas first right within the 28 days before day 30 (καί, λόγος and θεός came on day 0, ἀρχή on day 30).
		check("pace", Reading.pace(now, attempts, []), Some(1)),
		check("pace too early", Reading.pace(t0 + 2 * day, attempts, []), None),
		check("pace with reviews", Reading.pace(now, attempts, List.repeat(0, 56).map_with_index(|_, n| { lemma: "l${n.to_str()}", at: now - day, rating: Good, occurrence: { work: "luke", passage: "1.1", position: 1, form: "f", gloss: "g", text: "t", guess: "g" } })), Some(2)),
		check("days to learn", (Reading.days_to(100, 15), Reading.days_to(0, 15), Reading.days_to(354, 50), Reading.days_to(354, 100), Reading.days_to(354, 354)), (7, 0, 8, 4, 1)),
		check("per day for", (Reading.per_day_for(100, 28), Reading.per_day_for(100, 0), Reading.per_day_for(0, 5)), (4, 100, 0)),
		check("durations", [0, 1, 5, 20, 90, 400, 900].map(Reading.duration), ["now", "1 day", "5 days", "3 weeks", "3 months", "13 months", "2.5 years"]),
	]
}

goal_checks : List(Check)
goal_checks = {
	goals = { coverage: 98, per_day: 20, dates: Dict.empty().insert("luke", "2027-03-01") }
	marks = Dict.empty().insert("λόγος", t0)
	decoded = |text| Reading.decode_goals(JsonValue.decode(text) ?? JsonValue.null)
	[
		check("goals round trip", Reading.decode_goals(Reading.encode_goals(goals)), goals),
		check("goals encoded", JsonValue.encode(Reading.encode_goals(goals)), "{\"coverage\":98,\"perDay\":20,\"targets\":{\"luke\":\"2027-03-01\"}}"),
		check("goals defaults", decoded("{\"coverage\":7,\"perDay\":-1}"), Reading.default_goals),
		check("marks round trip", Reading.decode_marks(Reading.encode_marks(marks)), marks),
		check("day of date", (Reading.day_of_date("1970-01-01"), Reading.day_of_date("2026-01-01"), Reading.day_of_date("2024-02-29"), Reading.day_of_date("soon")), (Ok(0), Ok(20454), Ok(19782), Err(BadDate))),
		check("date of day", [0, 20454, 19782, -1].map(Reading.date_of_day), ["1970-01-01", "2026-01-01", "2024-02-29", "1969-12-31"]),
	]
}

reading_checks : List(Check)
reading_checks = {
	# Passage 1.1 of luke holds ὁ, καί and λόγος; 1.2 holds ὁ and θεός.
	by_passage = Reading.passage_lemmas(
		[
			("ὁ", [{ work: "luke", ref: "1.1" }, { work: "luke", ref: "1.2" }]),
			("καί", [{ work: "luke", ref: "1.1" }]),
			("λόγος", [{ work: "luke", ref: "1.1" }]),
			("θεός", [{ work: "luke", ref: "1.2" }]),
		],
	)
	# 1.1 graded on day 0 (λόγος missed) and day 14 (λόγος revealed); 1.2 on day 1.
	graded = [
		{ ..attempt(t0, [item("λόγος", Some(Bool.False), Bool.False)]), passage: "1.1" },
		{ ..attempt(t0 + day, []), passage: "1.2" },
		{ ..attempt(t0 + 14 * day, [item("λόγος", None, Bool.True)]), passage: "1.1" },
	]
	read = Reading.read_events(graded, by_passage)
	known = Reading.statuses(graded, [], Dict.empty(), Dict.empty(), read)
	[
		check("lemmas by passage", (by_passage.get("luke 1.1").map_ok(|set| set.len()), by_passage.get("luke 1.2").map_ok(|set| set.len())), (Ok(3), Ok(2))),
		check("read events skip missed and revealed words", read.len(), 6),
		check("no events for the troubled word", read.any(|event| event.lemma == "λόγος"), Bool.False),
		check("days 0 and 14: known", known.get("καί"), Ok(Known)),
		check("days 0, 1 and 14: known", known.get("ὁ"), Ok(Known)),
		check("one day: learning", known.get("θεός"), Ok(Learning)),
		check("missed, then revealed: learning", known.get("λόγος"), Ok(Learning)),
	]
}
