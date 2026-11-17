app [main!] {
	fsrs: "../packages/fsrs/main.roc",
	json: "../packages/json/main.roc",
	study: "../packages/study/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.Stdout
import fsrs.Fsrs
import json.JsonValue
import study.Review
import study.Study
import study.Today
import study.Words

# Checks the Roc ports of src/Words.elm and src/Today.elm (packages/study/):
# word cards replayed from attempts and word reviews, today's plan, next and
# upcoming items, and word review records in the Elm app's JSON shape. Expected
# values are read off the Elm code. Prints a summary and the failures, and
# exits with 1 if any check fails.
main! = |_args| {
	groups = [
		("word cards", word_card_checks),
		("word review records", record_checks),
		("today's plan", plan_checks),
		("next and upcoming items", next_checks),
	]
	var $failures = []
	for (title, checks) in groups {
		failed = checks.keep_if(|found| found.problem != "")
		Stdout.line!("${(checks.len() - failed.len()).to_str()}/${checks.len().to_str()} ${title}")?
		$failures = $failures.concat(failed)
	}
	if $failures.is_empty() {
		Stdout.line!("All Words and Today checks pass.")?
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

minute : I64
minute = 60000

day : I64
day = 86400000

# 2023-11-14 22:13:20 UTC.
t0 : I64
t0 = 1700000000000

# FIXTURES

word : Str, Str, [Some(Bool), None], Bool -> Study.Item
word = |key, lemma, mark, revealed_early| {
	key,
	kind: WordItem,
	form: "form-${key}",
	lemma,
	guess: "guess-${key}",
	reference: "gloss-${key}",
	revealed_early,
	mark,
}

attempt : Str, Str, I64, List(Study.Item) -> Study.Attempt
attempt = |work, passage, finished_at, items| {
	id: "attempt:${work}:${passage}:${finished_at.to_str()}",
	work,
	passage,
	sentence_id: "s1",
	sentence_text: "text of ${passage}",
	started_at: finished_at - minute,
	finished_at,
	items,
	rating: Some(Hard),
}

# Missed (λόγος twice: the first occurrence is kept), revealed early (θεός),
# answered right (καί, no card), and items that never make cards: an unusable
# lemma, a blank lemma, a translation item, and a key without a position.
first_attempt : Study.Attempt
first_attempt = attempt(
	"luke",
	"1.1",
	t0,
	[
		word("w:1", "λόγος", Some(Bool.False), Bool.False),
		word("w:2", "θεός", Some(Bool.True), Bool.True),
		word("w:3", "καί", Some(Bool.True), Bool.False),
		word("w:4", "_", Some(Bool.False), Bool.False),
		word("w:5", "  ", Some(Bool.False), Bool.False),
		{ ..word("literal", "λόγος", Some(Bool.False), Bool.False), kind: LiteralItem },
		word("x:6", "ἀρχή", Some(Bool.False), Bool.False),
		word("w:7", "λόγος", None, Bool.True),
	],
)

occurrence : Str, Str, I64, Str -> Words.Occurrence
occurrence = |work, passage, position, form| {
	work,
	passage,
	position,
	form,
	gloss: "gloss",
	text: "text of ${passage}",
	guess: "guess",
}

# θεός reviewed before the attempt; λόγος reviewed after it in another work.
reviews : List(Words.Review)
reviews = [
	{ lemma: "λόγος", at: t0 + 2 * day, rating: Good, occurrence: occurrence("john", "1.1", 2, "λόγος") },
	{ lemma: "θεός", at: t0 - day, rating: Good, occurrence: occurrence("john", "1.1", 4, "θεὸς") },
]

replayed : I64, List((I64, Fsrs.Rating)) -> Fsrs.Card
replayed = |start, events|
	events.fold(Fsrs.new_card(start), |card, (at, rating)| next(at, rating, card).map_ok(|outcome| outcome.card).ok_or(card))

next : I64, Fsrs.Rating, Fsrs.Card -> Try(Fsrs.Outcome, Str)
next = |at, rating, card| Fsrs.next(Review.scheduler?, at, rating, card)

missed_occurrence : Str, I64, Str -> Words.Occurrence
missed_occurrence = |key, position, passage| {
	work: "luke",
	passage,
	position,
	form: "form-${key}",
	gloss: "gloss-${key}",
	text: "text of ${passage}",
	guess: "guess-${key}",
}

word_card_checks : List(Check)
word_card_checks = {
	all = Words.cards([first_attempt], reviews)
	logos = all.get("λόγος")
	theos = all.get("θεός")
	logos_missed = missed_occurrence("w:1", 1, "1.1")
	theos_missed = missed_occurrence("w:2", 2, "1.1")
	john_logos = occurrence("john", "1.1", 2, "λόγος")
	john_theos = occurrence("john", "1.1", 4, "θεὸς")
	[
		check("lemmas with cards", (all.len(), all.contains("λόγος"), all.contains("θεός")), (2, Bool.True, Bool.True)),
		check(
			"λόγος: missed, then reviewed elsewhere",
			logos.map_ok(|w| (w.introduced_at, w.last_at, w.seen, w.misses, w.forms, w.context, w.missed_context)),
			Ok((t0, t0 + 2 * day, 2, 1, ["λόγος", "form-w:1"], logos_missed, Bool.True)),
		),
		check("λόγος works", logos.map_ok(|w| (w.works.get("luke"), w.works.get("john"))), Ok((Ok(logos_missed), Ok(john_logos)))),
		check("λόγος card", logos.map_ok(|w| w.card), Ok(replayed(t0, [(t0, Again), (t0 + 2 * day, Good)]))),
		check(
			"θεός: reviewed, then revealed in a passage",
			theos.map_ok(|w| (w.introduced_at, w.last_at, w.seen, w.misses, w.forms, w.context, w.missed_context)),
			Ok((t0 - day, t0, 2, 1, ["form-w:2", "θεὸς"], theos_missed, Bool.True)),
		),
		check("θεός card", theos.map_ok(|w| w.card), Ok(replayed(t0 - day, [(t0 - day, Good), (t0, Again)]))),
		check(
			"a later right review keeps the missed context",
			Words.cards([first_attempt], [{ lemma: "λόγος", at: t0 + day, rating: Easy, occurrence: john_logos }]).get("λόγος").map_ok(|w| (w.context, w.works.len())),
			Ok((logos_missed, 2)),
		),
		check(
			"a review alone sets context and no miss",
			Words.cards([], [{ lemma: "θεός", at: t0, rating: Hard, occurrence: john_theos }]).get("θεός").map_ok(|w| (w.seen, w.misses, w.context, w.missed_context)),
			Ok((1, 0, john_theos, Bool.False)),
		),
		check("review_context unscoped", logos.map_ok(|w| Words.review_context(None, w)), Ok(logos_missed)),
		check("review_context in a work", logos.map_ok(|w| Words.review_context(Some("john"), w)), Ok(john_logos)),
		check("review_context in an unmet work", logos.map_ok(|w| Words.review_context(Some("acts"), w)), Ok(logos_missed)),
		check(
			"due: most overdue first, ties in lemma order",
			Words.due(t0, word_cards).map(|w| w.lemma),
			["αἷμα", "ἀγάπη", "βίος"],
		),
		check(
			"is_mature",
			[
				mature_card(Review, 21.0),
				mature_card(Review, 20.9),
				mature_card(Relearning, 30.0),
				mature_card(Learning, 21.0),
			].map(Words.is_mature),
			[Bool.True, Bool.False, Bool.False, Bool.False],
		),
	]
}

mature_card : Fsrs.State, F64 -> Words.Card
mature_card = |state, stability| {
	..word_card("λόγος", t0, ["luke"]),
	card: { ..Fsrs.new_card(t0), state, stability },
}

word_card : Str, I64, List(Str) -> Words.Card
word_card = |lemma, due, works| {
	context = occurrence(works.first().ok_or("luke"), "1.1", 1, lemma)
	{
		lemma,
		card: { ..Fsrs.new_card(t0), due },
		introduced_at: t0 - day,
		last_at: t0 - day,
		seen: 1,
		misses: 1,
		forms: [lemma],
		context,
		missed_context: Bool.True,
		works: Dict.from_list(works.map(|work| (work, { ..context, work }))),
	}
}

# Due now: ἀγάπη and αἷμα at the same time (αἷμα first: it starts U+03B1,
# ἀγάπη U+1F00), then βίος. Later today δόξα and ἔργον (δόξα first), and
# ζωή at the end of the day, which is tomorrow.
word_cards : Dict(Str, Words.Card)
word_cards = Dict.from_list(
	[
		word_card("βίος", t0 - minute, ["acts"]),
		word_card("ἀγάπη", t0 - 5 * minute, ["luke", "acts"]),
		word_card("αἷμα", t0 - 5 * minute, ["luke"]),
		word_card("ἔργον", t0 + 30 * minute, ["acts"]),
		word_card("δόξα", t0 + 30 * minute, ["luke"]),
		word_card("ζωή", Review.start_of_day(t0) + day, ["luke"]),
	].map(|w| (w.lemma, w)),
)

# RECORDS

review_json : Str
review_json = "{\"id\":\"wordreview:λόγος:1700000000000\",\"type\":\"wordreview\",\"lemma\":\"λόγος\",\"at\":1700000000000,\"rating\":\"hard\",\"occurrence\":{\"work\":\"luke\",\"passage\":\"1.1\",\"position\":3,\"form\":\"λόγον\",\"gloss\":\"word\",\"text\":\"Ἐν ἀρχῇ \\\"ἦν\\\"\",\"guess\":\"speech\"}}"

stored_review : Words.Review
stored_review = {
	lemma: "λόγος",
	at: t0,
	rating: Hard,
	occurrence: { work: "luke", passage: "1.1", position: 3, form: "λόγον", gloss: "word", text: "Ἐν ἀρχῇ \"ἦν\"", guess: "speech" },
}

decoded : Str -> Try(Words.Review, Str)
decoded = |text| Words.decode_review(JsonValue.decode(text)?)

record_checks : List(Check)
record_checks = [
	check("review_key", Words.review_key(stored_review), "wordreview:λόγος:1700000000000"),
	check("encode_review writes the Elm shape", JsonValue.encode(Words.encode_review(stored_review)), review_json),
	check("decode_review reads the Elm shape", decoded(review_json), Ok(stored_review)),
	check(
		"decode_review ignores field order and extra fields",
		decoded("{\"occurrence\":{\"guess\":\"\",\"text\":\"t\",\"gloss\":\"g\",\"form\":\"f\",\"position\":0,\"passage\":\"2.3\",\"work\":\"acts\"},\"rating\":\"easy\",\"at\":5,\"lemma\":\"ἀγάπη\",\"type\":\"wordreview\",\"updatedAt\":9}"),
		Ok({ lemma: "ἀγάπη", at: 5, rating: Easy, occurrence: { work: "acts", passage: "2.3", position: 0, form: "f", gloss: "g", text: "t", guess: "" } }),
	),
	check("decode_review rejects cards", decoded("{\"type\":\"card\",\"lemma\":\"x\"}").is_ok(), Bool.False),
	check("decode_review rejects rows without a type", decoded("{\"key\":\"today-scope\",\"value\":\"\"}").is_ok(), Bool.False),
	check("decode_review rejects unknown ratings", decoded(review_json.replace_first("\"hard\"", "\"meh\"")).is_ok(), Bool.False),
	check("decode_review rejects a missing occurrence field", decoded(review_json.replace_first(",\"guess\":\"speech\"", "")).is_ok(), Bool.False),
	check("decode_review rejects a fractional time", decoded(review_json.replace_first(":1700000000000,", ":1.5,")).is_ok(), Bool.False),
]

# TODAY

entry : Str, Str, I64, I64 -> (Str, Review.Entry)
entry = |work, passage, due, introduced_at| (
	Review.entry_key(work, passage),
	{ work, passage, card: { ..Fsrs.new_card(introduced_at), due }, introduced_at },
)

works : List(Today.Work)
works = [
	{ id: "luke", passages: ["1.1", "1.2", "1.3", "1.4"] },
	{ id: "acts", passages: ["1.1", "1.2", "1.3"] },
]

# Today: acts 1.1 (introduced today) and luke 1.1 are due at the same time
# (key order puts acts first), luke 1.2 later; luke 1.3 (introduced today)
# comes back at the same time as the words δόξα and ἔργον; acts 1.3 tomorrow.
entries : Dict(Str, Review.Entry)
entries = Dict.from_list(
	[
		entry("luke", "1.1", t0 - 10 * minute, t0 - 3 * day),
		entry("luke", "1.2", t0 - minute, t0 - 2 * day),
		entry("acts", "1.1", t0 - 10 * minute, Review.start_of_day(t0)),
		entry("luke", "1.3", t0 + 30 * minute, t0 - minute),
		entry("acts", "1.3", Review.start_of_day(t0) + day, t0 - 2 * day),
	],
)

plan : I64, [Some(Str), None], [Some(Str), None] -> Today.Plan
plan = |limit, scope, last| Today.plan(t0, limit, scope, last, works, entries, word_cards)

plan_checks : List(Check)
plan_checks = [
	check(
		"everything, acts studied last",
		plan(10, None, Some("acts")),
		{
			words: ["αἷμα", "ἀγάπη", "βίος"],
			due: [("acts", "1.1"), ("luke", "1.1"), ("luke", "1.2")],
			new: [("acts", "1.2"), ("luke", "1.4")],
		},
	),
	check("new passages in library order with no last work", plan(10, None, None).new, [("luke", "1.4"), ("acts", "1.2")]),
	check("an unknown last work changes nothing", plan(10, None, Some("mark")).new, [("luke", "1.4"), ("acts", "1.2")]),
	check("the daily limit counts passages introduced today", plan(3, None, Some("acts")).new, [("acts", "1.2")]),
	check("a spent daily limit leaves no new passages", plan(1, None, None).new, []),
	check(
		"scoped to luke",
		plan(10, Some("luke"), Some("acts")),
		{ words: ["αἷμα", "ἀγάπη"], due: [("luke", "1.1"), ("luke", "1.2")], new: [("luke", "1.4")] },
	),
	check("the limit counts every work when scoped", plan(3, Some("luke"), None).new, [("luke", "1.4")]),
	check("the limit when scoped to acts", plan(2, Some("acts"), None).new, []),
	check("a scope outside the library", plan(10, Some("mark"), None), { words: [], due: [], new: [] }),
	check(
		"last_work: the latest attempt, first of ties",
		Today.last_work([attempt("luke", "1.1", t0, []), attempt("acts", "1.1", t0 + 1, []), attempt("john", "1.1", t0 + 1, [])]),
		Some("acts"),
	),
	check("last_work with no attempts", Today.last_work([]), None),
	check(
		"modes",
		[Today.mode_from_str("all"), Today.mode_from_str("words"), Today.mode_from_str("passages"), Today.mode_from_str("other")].map(Today.mode_to_str),
		["all", "words", "passages", "all"],
	),
]

next_checks : List(Check)
next_checks = {
	today = plan(10, None, Some("acts"))
	no_words = { ..today, words: [] }
	only_new = { words: [], due: [], new: [("luke", "1.4")] }
	upcoming = |mode, scope| Today.upcoming(t0, mode, scope, entries, word_cards)
	[
		check("next, everything", Today.next(Everything, today), Some(WordItem("αἷμα"))),
		check("next, words only", Today.next(WordsOnly, today), Some(WordItem("αἷμα"))),
		check("next, passages only", Today.next(PassagesOnly, today), Some(PassageItem("acts", "1.1"))),
		check("next, everything without words", Today.next(Everything, no_words), Some(PassageItem("acts", "1.1"))),
		check("next, words only without words", Today.next(WordsOnly, no_words), None),
		check("next, only new passages", Today.next(PassagesOnly, only_new), Some(PassageItem("luke", "1.4"))),
		check("next with nothing left", Today.next(Everything, { words: [], due: [], new: [] }), None),
		check("upcoming, everything: words before passages, lemma order", upcoming(Everything, None), Some((WordItem("δόξα"), t0 + 30 * minute))),
		check("upcoming, passages only", upcoming(PassagesOnly, None), Some((PassageItem("luke", "1.3"), t0 + 30 * minute))),
		check("upcoming, words in acts", upcoming(WordsOnly, Some("acts")), Some((WordItem("ἔργον"), t0 + 30 * minute))),
		check("upcoming, passages in acts: tomorrow is not today", upcoming(PassagesOnly, Some("acts")), None),
		check(
			"upcoming: the earliest wins over order",
			Today.upcoming(t0, Everything, None, entries.insert("x", entry("acts", "1.2", t0 + 2 * minute, t0).1), word_cards),
			Some((PassageItem("acts", "1.2"), t0 + 2 * minute)),
		),
	]
}
