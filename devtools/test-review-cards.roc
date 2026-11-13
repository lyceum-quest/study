app [main!] {
	fsrs: "../packages/fsrs/main.roc",
	json: "../packages/json/main.roc",
	study: "../packages/study/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.0/2yhxoR7cZPSYbyUzPWULFw8AA6QEcdsgFNRmzu7pZbst.tar.zst",
}

import pf.Stdout
import fsrs.Fsrs
import study.Review
import study.Study

# Passage cards replayed from attempts (`Review.cards` in
# packages/study/Review.roc), which sync relies on: any device holding the same
# attempts, in any order, must reach the same cards. The cases of
# tests/ReviewCardsTest.elm. Prints a summary and the failures, and exits with 1
# if any check fails.
main! = |_args| {
	checks = [
		rated_attempts_replay_to_live_grading,
		arrival_order_does_not_matter,
		unrated_attempt_keeps_stored_card,
		unrated_attempt_without_card_uses_suggestion,
		rating_survives_encoding,
	]
	failed = checks.keep_if(|check| check.problem != "")
	Stdout.line!("${(checks.len() - failed.len()).to_str()}/${checks.len().to_str()} Review.cards")?
	if failed.is_empty() {
		Stdout.line!("All Review.cards checks pass.")?
		Ok({})
	} else {
		for check in failed {
			Stdout.line!("\n${check.name}\n${check.problem}")?
		}
		Err(Exit(1))
	}
}

# A named check; `problem` is "" when it passes.
Check : { name : Str, problem : Str }

expect_equal : Str, a, a -> Check where [a.is_eq : a, a -> Bool]
expect_equal = |name, actual, expected|
	if actual == expected {
		{ name, problem: "" }
	} else {
		{ name, problem: "${Str.inspect(actual)}\n/=\n${Str.inspect(expected)}" }
	}

day : I64
day = 86400000

start : I64
start = 1760000000000

item : [Some(Bool), None] -> Study.Item
item = |mark| { key: "w:1", kind: WordItem, form: "λόγος", lemma: "λόγος", guess: "", reference: "word", revealed_early: Bool.False, mark }

attempt : Str, I64, [Some(Fsrs.Rating), None] -> Study.Attempt
attempt = |passage, at, rating| {
	id: "attempt:plato.crito:${passage}:${at.to_str()}",
	work: "plato.crito",
	passage,
	sentence_id: "s1",
	sentence_text: "text",
	started_at: at - 60000,
	finished_at: at,
	items: [item(Some(Bool.True))],
	rating,
}

## Grading as the app does it live: one `Review.schedule` per attempt, in order.
graded_live : List((Study.Attempt, Fsrs.Rating)) -> Dict(Str, Review.Entry)
graded_live = |graded|
	graded.fold(
		Dict.empty(),
		|entries, (a, rating)| match Review.schedule(a.finished_at, rating, a.work, a.passage, entries) {
			Ok(entry) => entries.insert(Review.entry_key(a.work, a.passage), entry)
			Err(_) => entries
		},
	)

rated_attempts_replay_to_live_grading : Check
rated_attempts_replay_to_live_grading = {
	graded = [
		(attempt("1.1", start, Some(Good)), Good),
		(attempt("1.1", start + 3 * day, Some(Hard)), Hard),
		(attempt("1.2", start + day, Some(Again)), Again),
	]
	expect_equal(
		"rated attempts replay to the cards live grading made",
		Review.cards(Dict.empty(), graded.map(|(a, _)| a)),
		graded_live(graded.sort_by(|(a, _)| a.finished_at)),
	)
}

arrival_order_does_not_matter : Check
arrival_order_does_not_matter = {
	attempts = [attempt("1.1", start + 3 * day, Some(Hard)), attempt("1.2", start + day, Some(Again)), attempt("1.1", start, Some(Good))]
	expect_equal(
		"the order attempts arrive in does not matter",
		Review.cards(Dict.empty(), attempts),
		Review.cards(Dict.empty(), attempts.rev()),
	)
}

unrated_attempt_keeps_stored_card : Check
unrated_attempt_keeps_stored_card = {
	stored = graded_live([(attempt("1.1", start, None), Easy)])
	later = attempt("1.1", start + 5 * day, Some(Again))
	expect_equal(
		"a passage with an unrated (older) attempt keeps its stored card, and later rated attempts apply on top",
		Review.cards(stored, [attempt("1.1", start, None), later]),
		graded_live([(attempt("1.1", start, None), Easy), (later, Again)]),
	)
}

unrated_attempt_without_card_uses_suggestion : Check
unrated_attempt_without_card_uses_suggestion = {
	old = attempt("1.1", start, None)
	expect_equal(
		"without a stored card, an unrated attempt replays with the suggested rating",
		Review.cards(Dict.empty(), [old]),
		graded_live([(old, Review.suggest_rating(old.items))]),
	)
}

rating_survives_encoding : Check
rating_survives_encoding = {
	round_trip = |a| Study.decode_attempt(Study.encode_attempt(a)).map_ok(|decoded| decoded.rating)
	expect_equal(
		"the rating survives encoding, and older attempts decode without one",
		(round_trip(attempt("1.1", start, Some(Hard))), round_trip(attempt("1.1", start, None))),
		(Ok(Some(Hard)), Ok(None)),
	)
}
