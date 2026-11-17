import fsrs.FsrsMath
import json.JsonValue
import Study
import Words

## How close each work is to readable, and what it takes to get there.
##
## Reading comfortably depends on lexical coverage: the share of a text's
## running words the reader knows. Laufer and Ravenhorst-Kalovski (2010) put
## the minimum for acceptable comprehension with support (a dictionary, or this
## app's word popups) at 95%, and independent reading at 98%. Words are
## counted by lemma, so every form of a word is learned once.
##
## A lemma is known when the learner has shown durable, unassisted recall of
## its meaning (see `statuses`): right on at least two separate days at least
## two weeks (`settle_days`) apart, never missed since, and, if it ever needed
## a word review card, with that card's FSRS stability at two weeks or more
## (recall still expected 90% of the time two weeks out). The rule follows the
## research on successive relearning (correct recalls in spaced sessions, not
## repeated recalls in one) and the spacing effect: recall a few days after
## learning overstates what lasts. Learners can also mark a lemma known
## themselves; a later miss undoes that.
##
## Before that, a lemma right on two separate days and not missed since is
## learned: the learner has done their part, and it counts as known once two
## weeks separate its right answers. Plans count the days to learn the words
## a goal needs, and the words count as known `settle_days` later.
##
## Proper names need no learning and count as known. The corpus does not tag
## them, so a lemma is taken as a name when every occurrence is capitalized in
## running text (see `names`).
Reading := [].{

	## One occurrence of a lemma in the library (`preload/lemmas.json`).
	Occurrence : { work : Str, position : I64, form : Str }

	Status : [Known, Learned, Learning]

	## A work's vocabulary: its running words (tokens) and how often each
	## lemma that needs learning occurs, most frequent first; names are only
	## counted in `name_tokens`.
	Vocabulary : { tokens : U64, name_tokens : U64, lemmas : List({ lemma : Str, count : U64 }) }

	## Where a work stands for a learner: its running words, those whose lemma
	## is known (names count), those known or learned, how many of its lemmas
	## are still to learn, and how many of those reach the goal.
	Standing : { tokens : U64, known_tokens : U64, learned_tokens : U64, unknown : U64, needed : U64 }

	## The learner's reading goals, synced as the `reading-goals` setting: the
	## coverage to aim for, the words a day to plan with (0: their own pace),
	## and target dates (`2027-03-01`) by work.
	Goals : { coverage : U64, per_day : U64, dates : Dict(Str, Str) }

	default_goals : Goals
	default_goals = { coverage: default_goal, per_day: 0, dates: Dict.empty() }

	## `{"coverage": 95, "perDay": 0, "targets": {"luke": "2027-03-01"}}`.
	encode_goals : Goals -> JsonValue
	encode_goals = |plan|
		JsonValue.object(
			[
				("coverage", JsonValue.int(plan.coverage.to_i64_wrap())),
				("perDay", JsonValue.int(plan.per_day.to_i64_wrap())),
				("targets", JsonValue.object(plan.dates.to_list().map(|(work, date)| (work, JsonValue.str(date))))),
			],
		)

	## Missing or malformed parts keep their defaults.
	decode_goals : JsonValue -> Goals
	decode_goals = |json| {
		number = |name, fallback|
			match JsonValue.field(json, name) {
				Ok(found) => match JsonValue.as_i64(found) {
					Ok(n) if n >= 0 => n.to_u64_wrap()
					_ => fallback
				}
				Err(_) => fallback
			}
		coverage = number("coverage", default_goal)
		dates = match JsonValue.field(json, "targets") {
			Ok(found) => JsonValue.fields(found).keep_oks(|(work, date)| JsonValue.as_str(date).map_ok(|text| (work, text))).fold(Dict.empty(), |acc, (work, date)| acc.insert(work, date))
			Err(_) => Dict.empty()
		}
		{ coverage: if coverage >= 50 and coverage <= 100 coverage else default_goal, per_day: number("perDay", 0), dates }
	}

	## The lemmas marked known, with when: `{"λόγος": 1767225600000}`, synced
	## as the `known-words` setting.
	encode_marks : Dict(Str, I64) -> JsonValue
	encode_marks = |marks| JsonValue.object(marks.to_list().map(|(lemma, at)| (lemma, JsonValue.int(at))))

	decode_marks : JsonValue -> Dict(Str, I64)
	decode_marks = |json| JsonValue.fields(json).keep_oks(|(lemma, at)| JsonValue.as_i64(at).map_ok(|n| (lemma, n))).fold(Dict.empty(), |acc, (lemma, at)| acc.insert(lemma, at))

	## The day number (days since 1970-01-01) of an ISO date, `2027-03-01`.
	day_of_date : Str -> Try(I64, [BadDate])
	day_of_date = |text| {
		parts = text.split_on("-")
		match parts {
			[y, m, d] => match (I64.from_str(y), I64.from_str(m), I64.from_str(d)) {
				(Ok(year), Ok(month), Ok(day)) if month >= 1 and month <= 12 and day >= 1 and day <= 31 => Ok(days_from_civil(year, month, day))
				_ => Err(BadDate)
			}
			_ => Err(BadDate)
		}
	}

	## The ISO date of a day number.
	date_of_day : I64 -> Str
	date_of_day = |days| {
		date = civil(days)
		"${date.year.to_str()}-${two_digits(date.month)}-${two_digits(date.day)}"
	}

	## A coverage goal in percent.
	default_goal : U64
	default_goal = 95

	## The words a day assumed before the learner has a pace of their own:
	## about what an hour of daily flashcard study introduces.
	default_pace : U64
	default_pace = 15

	## The goals the app offers, from "readable with help" to "independent".
	goals : List(U64)
	goals = [90, 95, 98]

	## Lemmas taken to be proper names: capitalized in every occurrence,
	## ignoring forms in capitals throughout (headings), and not resting on a
	## single occurrence that opens a passage, where any word is capitalized.
	names : List((Str, List(Occurrence))) -> Set(Str)
	names = |lemmas|
		lemmas
			.keep_if(
				|(_, found)| {
					running = found.keep_if(|occurrence| has_lowercase(occurrence.form))
					!running.is_empty()
					and running.all(|occurrence| starts_uppercase(occurrence.form))
					and !(running.len() == 1 and running.all(|occurrence| occurrence.position <= 1))
				},
			)
			.map(|(lemma, _)| lemma)
			.fold(Set.empty(), |set, lemma| set.insert(lemma))

	## Each work's vocabulary.
	vocabularies : List((Str, List(Occurrence))), Set(Str) -> Dict(Str, Vocabulary)
	vocabularies = |lemmas, name_set| {
		counted = lemmas.fold(
			Dict.empty(),
			|works, (lemma, found)|
				found.fold(
					works,
					|acc, occurrence| {
						current = acc.get(occurrence.work) ?? { tokens: 0, name_tokens: 0, counts: Dict.empty() }
						if name_set.contains(lemma) {
							acc.insert(occurrence.work, { ..current, tokens: current.tokens + 1, name_tokens: current.name_tokens + 1 })
						} else {
							acc.insert(occurrence.work, { ..current, tokens: current.tokens + 1, counts: current.counts.insert(lemma, (current.counts.get(lemma) ?? 0) + 1) })
						}
					},
				),
		)
		counted.map(
			|_, found| {
				tokens: found.tokens,
				name_tokens: found.name_tokens,
				lemmas: found.counts.to_list().map(|(lemma, count)| { lemma, count }).sort_with(by_frequency),
			},
		)
	}

	## What the learner knows: a status for every lemma they have answered,
	## reviewed or marked known (others are unseen). `marked` holds the lemmas
	## the learner marked known, with when.
	statuses : List(Study.Attempt), List(Words.Review), Dict(Str, Words.Card), Dict(Str, I64) -> Dict(Str, Status)
	statuses = |attempts, reviews, cards, marked| {
		from_attempts = attempts.join_map(
			|attempt| attempt.items.keep_oks(
				|item|
					if item.kind != WordItem or item.lemma == "" or item.revealed_early {
						Err({})
					} else {
						match item.mark {
							Some(right) => Ok({ lemma: item.lemma, at: attempt.finished_at, right })
							None => Err({})
						}
					},
			),
		)
		from_reviews = reviews.map(|review| { lemma: review.lemma, at: review.at, right: review.rating != Again })
		events = from_attempts.concat(from_reviews).fold(Dict.empty(), |acc, event| acc.insert(event.lemma, (acc.get(event.lemma) ?? []).append({ at: event.at, right: event.right })))
		answered = events.map(
			|lemma, found| {
				ordered = found.sort_with(|a, b| compare_i64(a.at, b.at))
				mark_at = marked.get(lemma) ?? -1
				missed_after_mark = mark_at >= 0 and ordered.any(|event| !event.right and event.at > mark_at)
				if (mark_at >= 0 and !missed_after_mark) or durable(ordered, cards.get(lemma)) {
					Known
				} else if learned(ordered) {
					Learned
				} else {
					Learning
				}
			},
		)
		marked.to_list().fold(answered, |acc, (lemma, _)| if acc.contains(lemma) acc else acc.insert(lemma, Known))
	}

	## How a work stands: its running words, how many the learner knows (names
	## count as known) and has learned, how many lemmas are still to learn
	## (neither known nor learned), and how many of those, most frequent first,
	## bring known and learned words to `goal` percent coverage.
	standing : Vocabulary, Dict(Str, Status), U64 -> Standing
	standing = |vocabulary, known, goal| {
		tokens_of = |entries| entries.fold(0, |sum, entry| sum + entry.count)
		is_known = |lemma| known.get(lemma) == Ok(Known)
		is_learned = |lemma| known.get(lemma) == Ok(Learned)
		known_tokens = vocabulary.name_tokens + tokens_of(vocabulary.lemmas.keep_if(|entry| is_known(entry.lemma)))
		learned_tokens = known_tokens + tokens_of(vocabulary.lemmas.keep_if(|entry| is_learned(entry.lemma)))
		unknown = vocabulary.lemmas.drop_if(|entry| is_known(entry.lemma) or is_learned(entry.lemma))
		# Coverage reaches the goal once covered * 100 >= goal * tokens.
		target = goal * vocabulary.tokens
		needed = unknown
			.fold(
				{ covered: learned_tokens * 100, count: 0 },
				|acc, entry| if acc.covered >= target acc else { covered: acc.covered + entry.count * 100, count: acc.count + 1 },
			)
			.count
		{ tokens: vocabulary.tokens, known_tokens, learned_tokens, unknown: unknown.len(), needed }
	}

	## Known coverage in whole percent, rounded down (so 94.9% never shows as 95%).
	percent : Standing -> U64
	percent = |found| if found.tokens == 0 100 else found.known_tokens * 100 // found.tokens

	## Coverage by known and learned words, in whole percent, rounded down.
	learned_percent : Standing -> U64
	learned_percent = |found| if found.tokens == 0 100 else found.learned_tokens * 100 // found.tokens

	## The learner's pace in new words a day: lemmas first answered right in
	## the last 28 days, once they have been studying for at least three days.
	pace : I64, List(Study.Attempt), List(Words.Review) -> [Some(U64), None]
	pace = |now, attempts, reviews| {
		window = 28 * day_ms
		firsts = attempts
			.join_map(|attempt| attempt.items.keep_if(|item| item.kind == WordItem and item.lemma != "" and item.mark == Some(Bool.True) and !item.revealed_early).map(|item| (item.lemma, attempt.finished_at)))
			.concat(reviews.keep_if(|review| review.rating != Again).map(|review| (review.lemma, review.at)))
			.fold(Dict.empty(), |acc, (lemma, at)| if (acc.get(lemma) ?? at) <= at and acc.contains(lemma) acc else acc.insert(lemma, at))
		earliest = attempts.map(|attempt| attempt.finished_at).concat(reviews.map(|review| review.at)).min() ?? now
		recent = firsts.to_list().count_if(|(_, at)| at > now - window)
		if now - earliest < pace_days.to_i64_wrap() * day_ms {
			None
		} else {
			# The window, or the time since the learner began if shorter.
			span_days = ((now - earliest).min(window) // day_ms).max(1).to_u64_wrap()
			Some(((recent + span_days // 2) // span_days).max(1))
		}
	}

	## The study the learner needs before their own pace replaces `default_pace`.
	pace_days : U64
	pace_days = 3

	## Days to learn `needed` new lemmas at `per_day` a day (rounded up). They
	## count as known `settle_days` after the last is learned.
	days_to : U64, U64 -> U64
	days_to = |needed, per_day| if per_day == 0 0 else (needed + per_day - 1) // per_day

	## Words a day to learn `needed` lemmas in `days` days (rounded up).
	per_day_for : U64, U64 -> U64
	per_day_for = |needed, days| if days == 0 needed else (needed + days - 1) // days

	## How long a learned word takes to count as known: the gap between two
	## right answers that shows recall lasts.
	settle_days : U64
	settle_days = 14

	## The `count` most frequent lemmas of a work the learner still has to learn.
	next_words : Vocabulary, Dict(Str, Status), U64 -> List({ lemma : Str, count : U64, status : [Learning, Unseen] })
	next_words = |vocabulary, known, count|
		vocabulary.lemmas
			.keep_oks(
				|entry| match known.get(entry.lemma) {
					Ok(Known) | Ok(Learned) => Err({})
					Ok(Learning) => Ok({ lemma: entry.lemma, count: entry.count, status: Learning })
					Err(_) => Ok({ lemma: entry.lemma, count: entry.count, status: Unseen })
				},
			)
			.take_first(count)

	## `3 days`, `5 weeks`, `4 months`, `1.5 years`.
	duration : U64 -> Str
	duration = |days|
		if days == 0 {
			"now"
		} else if days < 14 {
			"${days.to_str()} ${if days == 1 "day" else "days"}"
		} else if days < 60 {
			"${((days + 3) // 7).to_str()} weeks"
		} else if days < 548 {
			"${((days + 15) // 30).to_str()} months"
		} else {
			"${FsrsMath.to_js_str(FsrsMath.round(days.to_f64() / 365.0 * 10.0) / 10.0)} years"
		}
}

day_ms : I64
day_ms = 86400000

## Learned, with right answers `settle_days` apart, and any word review card
## stable for as long.
durable : List({ at : I64, right : Bool }), Try(Words.Card, _) -> Bool
durable = |ordered, card| {
	rights = ordered.keep_if(|event| event.right)
	span = match (rights.first(), rights.last()) {
		(Ok(first), Ok(last)) => last.at - first.at
		_ => 0
	}
	stable = match card {
		Ok(found) => found.card.stability >= Reading.settle_days.to_f64()
		Err(_) => Bool.True
	}
	learned(ordered) and span >= Reading.settle_days.to_i64_wrap() * day_ms and stable
}

## Right on at least two separate days, and last answered right.
learned : List({ at : I64, right : Bool }) -> Bool
learned = |ordered| {
	last_right = match ordered.last() {
		Ok(event) => event.right
		Err(_) => Bool.False
	}
	days = ordered.keep_if(|event| event.right).map(|event| event.at // day_ms).fold(Set.empty(), |set, day| set.insert(day))
	last_right and days.len() >= 2
}

by_frequency : { lemma : Str, count : U64 }, { lemma : Str, count : U64 } -> [Before, Same, After]
by_frequency = |a, b|
	if a.count > b.count {
		Before
	} else if a.count < b.count {
		After
	} else {
		compare_bytes(a.lemma.to_utf8(), b.lemma.to_utf8(), 0)
	}

compare_i64 : I64, I64 -> [Before, Same, After]
compare_i64 = |a, b| if a < b Before else if a > b After else Same

compare_bytes : List(U8), List(U8), U64 -> [Before, Same, After]
compare_bytes = |a, b, at|
	match (a.get(at), b.get(at)) {
		(Err(_), Err(_)) => Same
		(Err(_), Ok(_)) => Before
		(Ok(_), Err(_)) => After
		(Ok(x), Ok(y)) => if x < y Before else if x > y After else compare_bytes(a, b, at + 1)
	}

## The code points of a string (its UTF-8 decoded; the corpus is valid UTF-8).
code_points : Str -> List(U32)
code_points = |text| decode(text.to_utf8(), 0, [])

decode : List(U8), U64, List(U32) -> List(U32)
decode = |bytes, at, out|
	match bytes.get(at) {
		Err(_) => out
		Ok(lead) => {
			width : U64
			width = if lead < 0x80 1 else if lead < 0xE0 2 else if lead < 0xF0 3 else 4
			first = lead.to_u32() % (if width == 1 128 else if width == 2 32 else if width == 3 16 else 8)
			point = continuation(bytes, at + 1, at + width, first)
			decode(bytes, at + width, out.append(point))
		}
	}

## Folds the continuation bytes from `at` up to `end` into `acc`, six bits each.
continuation : List(U8), U64, U64, U32 -> U32
continuation = |bytes, at, end, acc|
	if at >= end {
		acc
	} else {
		continuation(bytes, at + 1, end, acc * 64 + (bytes.get(at) ?? 0x80).to_u32() % 64)
	}

starts_uppercase : Str -> Bool
starts_uppercase = |form|
	match code_points(form).first() {
		Ok(point) => is_upper(point)
		Err(_) => Bool.False
	}

has_lowercase : Str -> Bool
has_lowercase = |form| code_points(form).any(is_lower)

## Greek and Latin capitals, including the precomposed capitals of Greek
## Extended (with breathings, accents and iota adscript).
is_upper : U32 -> Bool
is_upper = |p|
	(p >= 'A' and p <= 'Z')
	or p == 0x0386
	or (p >= 0x0388 and p <= 0x038F and p != 0x038B and p != 0x038D)
	or (p >= 0x0391 and p <= 0x03AB and p != 0x03A2)
	or (p >= 0x1F00 and p <= 0x1FAF and (p % 16) >= 8 and !(p >= 0x1F70 and p <= 0x1F7F))
	or (p >= 0x1FB8 and p <= 0x1FBC)
	or (p >= 0x1FC8 and p <= 0x1FCC)
	or (p >= 0x1FD8 and p <= 0x1FDB)
	or (p >= 0x1FE8 and p <= 0x1FEC)
	or (p >= 0x1FF8 and p <= 0x1FFC)

## Greek and Latin small letters (Greek Extended's letters that are not capitals).
is_lower : U32 -> Bool
is_lower = |p|
	(p >= 'a' and p <= 'z')
	or (p >= 0x03AC and p <= 0x03CE)
	or (p >= 0x1F00 and p <= 0x1FF7 and !is_upper(p) and !is_greek_mark(p))

## Spacing breathings and accents in Greek Extended, which are not letters.
is_greek_mark : U32 -> Bool
is_greek_mark = |p|
	p == 0x1FBD or (p >= 0x1FBF and p <= 0x1FC1) or (p >= 0x1FCD and p <= 0x1FCF) or (p >= 0x1FDD and p <= 0x1FDF) or (p >= 0x1FED and p <= 0x1FEF) or p == 0x1FFD or p == 0x1FFE

floor_div : I64, I64 -> I64
floor_div = |n, d| {
	q = n // d
	if n % d < 0 q - 1 else q
}

## Howard Hinnant's `days_from_civil` and `civil_from_days`, proleptic Gregorian.
days_from_civil : I64, I64, I64 -> I64
days_from_civil = |year, month, day| {
	y = if month <= 2 year - 1 else year
	era = floor_div(y, 400)
	yoe = y - era * 400
	mp = if month > 2 month - 3 else month + 9
	doy = (153 * mp + 2) // 5 + day - 1
	doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	era * 146097 + doe - 719468
}

civil : I64 -> { year : I64, month : I64, day : I64 }
civil = |days| {
	z = days + 719468
	era = floor_div(z, 146097)
	doe = z - era * 146097
	yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	mp = (5 * doy + 2) // 153
	day = doy - (153 * mp + 2) // 5 + 1
	month = if mp < 10 mp + 3 else mp - 9
	{ year: yoe + era * 400 + (if month <= 2 1 else 0), month, day }
}

two_digits : I64 -> Str
two_digits = |n| if n < 10 "0${n.to_str()}" else n.to_str()
