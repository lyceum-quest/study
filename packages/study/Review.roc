import fsrs.Fsrs
import fsrs.FsrsMath
import json.JsonValue
import Study

## Spaced review of studied passages with FSRS, ported from `src/Review.elm`.
##
## Each passage of a work becomes a card when its first attempt is graded. A
## work's queue for today is its due cards (most overdue first) followed by
## passages not yet studied, in text order, up to a daily limit of new passages.
## Cards are stored in the IndexedDB `progress` store in the Elm app's shape.
Review := [].{

	## A scheduled passage, keyed by its citation. `introduced_at` is when it was
	## first graded, for the daily new limit.
	Entry : { work : Str, passage : Str, card : Fsrs.Card, introduced_at : I64 }

	Queue : { due : List(Str), new : List(Str) }

	new_per_day_default : I64
	new_per_day_default = 10

	## ts-fsrs defaults: 90% target retention, learning steps 1m and 10m,
	## relearning step 10m, fuzz off.
	scheduler : Try(Fsrs.Scheduler, Str)
	scheduler = Fsrs.scheduler(Fsrs.default_config)

	entry_key : Str, Str -> Str
	entry_key = |work, passage| "card:${work}:${passage}"

	## Passage cards replayed from attempts, oldest first, each with the rating it
	## records, so a device that received another device's attempts reaches the
	## same cards. Attempts saved before ratings were recorded have none: for a
	## passage with such an attempt its stored card (written when it was graded) is
	## kept as the starting point and only rated attempts after its last review are
	## replayed; where no stored card exists (a newly synced device) they replay
	## with the rating suggested from their marks. Stored cards for passages with
	## no attempts are kept.
	cards : Dict(Str, Entry), List(Study.Attempt) -> Dict(Str, Entry)
	cards = |stored, attempts| {
		by_passage = attempts
			.sort_by(|attempt| attempt.finished_at)
			.fold(
				Dict.empty(),
				|groups, attempt| groups.update(
					entry_key(attempt.work, attempt.passage),
					|found| Ok(found.ok_or([]).append(attempt)),
				),
			)
		by_passage.fold(
			stored,
			|replayed, key, group| match replay(stored, key, group) {
				Some(entry) => replayed.insert(key, entry)
				None => replayed
			},
		)
	}

	## Days are UTC days, matching how FSRS counts elapsed days.
	start_of_day : I64 -> I64
	start_of_day = |now| now - modulo(now, 86400000)

	## Today's queue for a work whose passages, in text order, are `passages`
	## (citations).
	queue : I64, I64, Str, List(Str), Dict(Str, Entry) -> Queue
	queue = |now, new_per_day, work, passages, entries| {
		work_cards = entries.values().keep_if(|entry| entry.work == work)
		studied = Dict.from_list(work_cards.map(|entry| (entry.passage, {})))
		introduced_today = work_cards.count_if(|entry| entry.introduced_at >= start_of_day(now)).to_i64_wrap()
		new_slots = (new_per_day - introduced_today).max(0).to_u64_wrap()
		{
			# The Elm app's cards are ordered by key before this stable sort, so equal
			# due times keep key order there too.
			due: work_cards
				.keep_if(|entry| entry.card.due <= now)
				.sort_with(|a, b| match compare_i64(a.card.due, b.card.due) {
					Same => compare_text(entry_key(a.work, a.passage), entry_key(b.work, b.passage))
					order => order
				})
				.map(|entry| entry.passage),
			new: passages.drop_if(|passage| studied.contains(passage)).take_first(new_slots),
		}
	}

	## When the work's next card becomes due after now, if any.
	due_later : I64, Str, Dict(Str, Entry) -> [Some(I64), None]
	due_later = |now, work, entries|
		match entries.values().keep_if(|entry| entry.work == work and entry.card.due > now).map(|entry| entry.card.due).min() {
			Ok(due) => Some(due)
			Err(_) => None
		}

	## Reviews a passage (a new card on its first review) and returns its updated entry.
	schedule : I64, Fsrs.Rating, Str, Str, Dict(Str, Entry) -> Try(Entry, Str)
	schedule = |now, rating, work, passage, entries|
		schedule_entry(
			now,
			rating,
			work,
			passage,
			match entries.get(entry_key(work, passage)) {
				Ok(entry) => Some(entry)
				Err(_) => None
			},
		)

	## The outcome of each rating for the passage at `now`, as its card would be
	## scheduled (a new card if it has none).
	preview : I64, Str, Str, Dict(Str, Entry) -> Try(Fsrs.Outcomes, Str)
	preview = |now, work, passage, entries| {
		card = match entries.get(entry_key(work, passage)) {
			Ok(entry) => entry.card
			Err(_) => Fsrs.new_card(now)
		}
		Fsrs.preview(scheduler?, now, card)
	}

	## A suggested rating from the learner's own marks. Nothing marked counts as
	## Again; any wrong answer beyond a quarter of the marked items is Again; fewer
	## wrong answers, or early reveals with none wrong, are Hard; all right
	## unassisted is Good. Easy is left to the learner.
	suggest_rating : List(Study.Item) -> Fsrs.Rating
	suggest_rating = |items| {
		judged = items.keep_if(|item| item.mark != None)
		wrong = judged.count_if(|item| item.mark == Some(Bool.False))
		revealed = items.count_if(|item| item.revealed_early)
		if judged.is_empty() {
			Again
		} else if wrong * 4 > judged.len() {
			Again
		} else if wrong > 0 or revealed > 0 {
			Hard
		} else {
			Good
		}
	}

	## A short interval such as "1 min", "10 min", "4 h", "3 d", "2 mo", or "1 y".
	interval_label : I64, I64 -> Str
	interval_label = |now, due| {
		minutes = round((due - now).to_f64() / 60000.0).max(1.0)
		hours = minutes / 60.0
		days = hours / 24.0
		if minutes < 60.0 {
			"${whole_text(minutes)} min"
		} else if hours < 24.0 {
			"${whole_text(round(hours))} h"
		} else if days < 31.0 {
			"${whole_text(round(days))} d"
		} else if days < 365.0 {
			"${whole_text(round(days / 30.0))} mo"
		} else {
			"${whole_text(round(days / 365.0))} y"
		}
	}

	# ENCODING, as `Review.encodeEntry` and `Review.entryDecoder` in src/Review.elm.

	encode_entry : Entry -> JsonValue
	encode_entry = |entry| {
		card = entry.card
		JsonValue.object(
			[
				("id", JsonValue.str(entry_key(entry.work, entry.passage))),
				("type", JsonValue.str("card")),
				("work", JsonValue.str(entry.work)),
				("passage", JsonValue.str(entry.passage)),
				("introducedAt", JsonValue.int(entry.introduced_at)),
				("fsrs", JsonValue.str(Fsrs.fsrs_version)),
				(
					"card",
					JsonValue.object(
						[
							("due", JsonValue.int(card.due)),
							("stability", JsonValue.numeral(FsrsMath.to_js_str(card.stability))),
							("difficulty", JsonValue.numeral(FsrsMath.to_js_str(card.difficulty))),
							("elapsedDays", JsonValue.int(card.elapsed_days)),
							("scheduledDays", JsonValue.int(card.scheduled_days)),
							("learningSteps", JsonValue.int(card.learning_steps)),
							("reps", JsonValue.int(card.reps)),
							("lapses", JsonValue.int(card.lapses)),
							("state", JsonValue.str(state_name(card.state))),
							(
								"lastReview",
								match card.last_review {
									Some(time) => JsonValue.int(time)
									None => JsonValue.null
								},
							),
						],
					),
				),
			],
		)
	}

	## Only records written by `encode_entry` (or the Elm app) decode; attempts and
	## other rows in the progress store are `Err`.
	decode_entry : JsonValue -> Try(Entry, Str)
	decode_entry = |json| {
		if JsonValue.as_str(JsonValue.field(json, "type")?) != Ok("card") {
			return Err("not a card")
		}
		card = JsonValue.field(json, "card")?
		last_review = JsonValue.field(card, "lastReview")?
		Ok(
			{
				work: JsonValue.as_str(JsonValue.field(json, "work")?)?,
				passage: JsonValue.as_str(JsonValue.field(json, "passage")?)?,
				introduced_at: whole(json, "introducedAt")?,
				card: {
					due: whole(card, "due")?,
					stability: JsonValue.as_f64(JsonValue.field(card, "stability")?)?,
					difficulty: JsonValue.as_f64(JsonValue.field(card, "difficulty")?)?,
					elapsed_days: whole(card, "elapsedDays")?,
					scheduled_days: whole(card, "scheduledDays")?,
					learning_steps: whole(card, "learningSteps")?,
					reps: whole(card, "reps")?,
					lapses: whole(card, "lapses")?,
					state: state_from_name(JsonValue.as_str(JsonValue.field(card, "state")?)?)?,
					last_review: if JsonValue.is_null(last_review) None else Some(JsonValue.as_i64(last_review)?),
				},
			},
		)
	}
}

## One passage's attempts, oldest first, replayed over its stored card (see `cards`).
replay : Dict(Str, Review.Entry), Str, List(Study.Attempt) -> [Some(Review.Entry), None]
replay = |stored, key, group| {
	legacy = if group.any(|attempt| attempt.rating == None) {
		match stored.get(key) {
			Ok(entry) => Some(entry)
			Err(_) => None
		}
	} else {
		None
	}
	since = match legacy {
		Some(entry) => match entry.card.last_review {
			Some(time) => time
			None => 0
		}
		None => 0
	}
	apply = |rating, attempt, entry| match schedule_entry(attempt.finished_at, rating, attempt.work, attempt.passage, entry) {
		Ok(scheduled) => Some(scheduled)
		Err(_) => entry
	}
	group.fold(
		legacy,
		|entry, attempt| match (legacy, attempt.rating) {
			(Some(_), None) => entry
			(Some(_), Some(rating)) => if attempt.finished_at > since apply(rating, attempt, entry) else entry
			(None, Some(rating)) => apply(rating, attempt, entry)
			(None, None) => apply(Review.suggest_rating(attempt.items), attempt, entry)
		},
	)
}

schedule_entry : I64, Fsrs.Rating, Str, Str, [Some(Review.Entry), None] -> Try(Review.Entry, Str)
schedule_entry = |now, rating, work, passage, existing| {
	card = match existing {
		Some(entry) => entry.card
		None => Fsrs.new_card(now)
	}
	outcome = Fsrs.next(Review.scheduler?, now, rating, card)?
	Ok(
		{
			work,
			passage,
			card: outcome.card,
			introduced_at: match existing {
				Some(entry) => entry.introduced_at
				None => now
			},
		},
	)
}

state_name : Fsrs.State -> Str
state_name = |state|
	match state {
		New => "new"
		Learning => "learning"
		Review => "review"
		Relearning => "relearning"
	}

state_from_name : Str -> Try(Fsrs.State, Str)
state_from_name = |name|
	match name {
		"new" => Ok(New)
		"learning" => Ok(Learning)
		"review" => Ok(Review)
		"relearning" => Ok(Relearning)
		_ => Err("unknown card state ${name}")
	}

whole : JsonValue, Str -> Try(I64, Str)
whole = |json, name| JsonValue.as_i64(JsonValue.field(json, name)?)

## Elm's `modBy`: the remainder with the divisor's sign.
modulo : I64, I64 -> I64
modulo = |n, divisor| {
	remainder = n.rem_by(divisor)
	if remainder < 0 remainder + divisor else remainder
}

## JavaScript's `Math.round`, as Elm's `round` compiles to.
round : F64 -> F64
round = |x| FsrsMath.round(x)

whole_text : F64 -> Str
whole_text = |x| FsrsMath.to_js_str(x)

compare_i64 : I64, I64 -> [Before, Same, After]
compare_i64 = |a, b| if a < b Before else if a > b After else Same

## Byte order, which for these ASCII keys is the code unit order Elm compares by.
compare_text : Str, Str -> [Before, Same, After]
compare_text = |a, b| compare_bytes(a.to_utf8(), b.to_utf8(), 0)

compare_bytes : List(U8), List(U8), U64 -> [Before, Same, After]
compare_bytes = |a, b, at|
	match (a.get(at), b.get(at)) {
		(Err(_), Err(_)) => Same
		(Err(_), Ok(_)) => Before
		(Ok(_), Err(_)) => After
		(Ok(x), Ok(y)) => if x < y Before else if x > y After else compare_bytes(a, b, at + 1)
	}
