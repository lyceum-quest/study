import fsrs.Fsrs
import json.JsonValue
import Review
import Study

## Spaced review of words, one card per lemma (see `Review` for passages),
## ported from `src/Words.elm`.
##
## A word card is not stored: it is replayed through FSRS from the learner's
## history, in time order, so attempts made before word cards existed count and
## cards can never disagree with the history.
##
## Words and passages are tracked separately. Recall inside a passage is helped
## by its context (the encoding-specificity principle), so a word answered right
## there is weak evidence that the learner knows it alone, while a word missed
## even with that help is strong evidence that they do not. So a passage only
## ever counts against a word: a word marked wrong or revealed before the
## checkpoint gets a card if it has none (its first miss introduces it) and an
## Again review. Words answered right in passages never get cards; otherwise
## only word reviews move a word's schedule.
Words := [].{

	## Where a word was met: the passage, the token's position in it
	## (`Study.word_key`), the form, its reference gloss, the passage text, and
	## the learner's answer there.
	Occurrence : { work : Str, passage : Str, position : I64, form : Str, gloss : Str, text : Str, guess : Str }

	## A word review: the learner recalled the lemma's meaning in one occurrence
	## and rated it. Stored in the IndexedDB `progress` store.
	Review : { lemma : Str, at : I64, rating : Fsrs.Rating, occurrence : Occurrence }

	## A lemma's schedule and history. `context` is the occurrence to quiz on
	## next: the latest one missed, else the latest seen. `forms` are the
	## inflected forms met, most recent first. `works` holds the latest
	## occurrence in each work where the word was missed or reviewed, for
	## studying one work at a time.
	Card : {
		lemma : Str,
		card : Fsrs.Card,
		introduced_at : I64,
		last_at : I64,
		seen : I64,
		misses : I64,
		forms : List(Str),
		context : Occurrence,
		missed_context : Bool,
		works : Dict(Str, Occurrence),
	}

	review_key : Review -> Str
	review_key = |review| "wordreview:${review.lemma}:${review.at.to_str()}"

	## Due word cards, most overdue first.
	due : I64, Dict(Str, Card) -> List(Card)
	due = |now, all|
		# Elm's `Dict.values` is in lemma order before its stable sort by due time.
		all
			.values()
			.keep_if(|word| word.card.due <= now)
			.sort_with(|a, b| match compare_i64(a.card.due, b.card.due) {
				Same => compare_text(a.lemma, b.lemma)
				order => order
			})

	## Known for now: in review with at least three weeks' stability, as Anki
	## calls a card mature.
	is_mature : Card -> Bool
	is_mature = |word| word.card.state == Review and word.card.stability >= 21.0

	## Every lemma's card, from all finished attempts and word reviews.
	cards : List(Study.Attempt), List(Review) -> Dict(Str, Card)
	cards = |attempts, reviews|
		sort_by(attempts.join_map(attempt_events).concat(reviews), |a, b| compare_i64(a.at, b.at))
			.fold(Dict.empty(), apply)

	## The occurrence to quiz a word in: when studying one work (`scope`), its
	## latest occurrence there. Ported from `reviewContext` in `src/Main.elm`.
	review_context : [Some(Str), None], Card -> Occurrence
	review_context = |scope, word|
		match scope {
			Some(work) => word.works.get(work).ok_or(word.context)
			None => word.context
		}

	# ENCODING, as `Words.encodeReview` and `Words.reviewDecoder` in src/Words.elm.

	encode_review : Review -> JsonValue
	encode_review = |review| {
		occurrence = review.occurrence
		JsonValue.object(
			[
				("id", JsonValue.str(review_key(review))),
				("type", JsonValue.str("wordreview")),
				("lemma", JsonValue.str(review.lemma)),
				("at", JsonValue.int(review.at)),
				("rating", JsonValue.str(Study.rating_name(review.rating))),
				(
					"occurrence",
					JsonValue.object(
						[
							("work", JsonValue.str(occurrence.work)),
							("passage", JsonValue.str(occurrence.passage)),
							("position", JsonValue.int(occurrence.position)),
							("form", JsonValue.str(occurrence.form)),
							("gloss", JsonValue.str(occurrence.gloss)),
							("text", JsonValue.str(occurrence.text)),
							("guess", JsonValue.str(occurrence.guess)),
						],
					),
				),
			],
		)
	}

	## Only records written by `encode_review` (or the Elm app) decode; other
	## rows in the progress store are `Err`.
	decode_review : JsonValue -> Try(Review, Str)
	decode_review = |json| {
		if text(json, "type")? != "wordreview" {
			return Err("not a word review")
		}
		occurrence = JsonValue.field(json, "occurrence")?
		Ok(
			{
				lemma: text(json, "lemma")?,
				at: whole(json, "at")?,
				rating: Study.rating_from_name(text(json, "rating")?)?,
				occurrence: {
					work: text(occurrence, "work")?,
					passage: text(occurrence, "passage")?,
					position: whole(occurrence, "position")?,
					form: text(occurrence, "form")?,
					gloss: text(occurrence, "gloss")?,
					text: text(occurrence, "text")?,
					guess: text(occurrence, "guess")?,
				},
			},
		)
	}
}

## One Again per lemma the learner missed or revealed in the attempt; words
## answered right are not reviews. In lemma order, as Elm's `Dict.values`.
attempt_events : Study.Attempt -> List(Words.Review)
attempt_events = |attempt|
	attempt.items
		.keep_oks(
			|item| match (item.kind, item_rating(item), position_of(item.key)) {
				(WordItem, Some(rating), Some(position)) if usable_lemma(item.lemma) =>
					Ok(
						{
							lemma: item.lemma,
							at: attempt.finished_at,
							rating,
							occurrence: {
								work: attempt.work,
								passage: attempt.passage,
								position,
								form: item.form,
								gloss: item.reference,
								text: attempt.sentence_text,
								guess: item.guess,
							},
						},
					)
				_ => Err({})
			},
		)
		.fold(
			Dict.empty(),
			|worst, event| match worst.get(event.lemma) {
				Ok(prior) if rating_rank(event.rating) >= rating_rank(prior.rating) => worst
				_ => worst.insert(event.lemma, event)
			},
		)
		.values()
		.sort_with(|a, b| compare_text(a.lemma, b.lemma))

item_rating : Study.Item -> [Some(Fsrs.Rating), None]
item_rating = |item| if item.mark == Some(Bool.False) or item.revealed_early Some(Again) else None

## The token number of a word item's key `w:<n>`, read as Elm's `String.toInt`
## reads it (an optional sign, then ASCII digits only).
position_of : Str -> [Some(I64), None]
position_of = |key| {
	if !key.starts_with("w:") {
		return None
	}
	bytes = key.to_utf8().drop_first(2)
	sign = match bytes.first() {
		Ok('-') => -1
		_ => 1
	}
	digits = match bytes.first() {
		Ok('+') | Ok('-') => bytes.drop_first(1)
		_ => bytes
	}
	if digits.is_empty() or !digits.all(|byte| byte >= '0' and byte <= '9') {
		None
	} else {
		Some(sign * digits.fold(0, |total, byte| 10 * total + (byte - '0').to_i64()))
	}
}

usable_lemma : Str -> Bool
usable_lemma = |lemma| lemma.trim() != "" and lemma != "_"

rating_rank : Fsrs.Rating -> U8
rating_rank = |rating|
	match rating {
		Again => 0
		Hard => 1
		Good => 2
		Easy => 3
	}

apply : Dict(Str, Words.Card), Words.Review -> Dict(Str, Words.Card)
apply = |all, event| {
	existing = all.get(event.lemma)
	prior = match existing {
		Ok(word) => word.card
		Err(_) => Fsrs.new_card(event.at)
	}
	scheduled = next_card(event, prior).ok_or(prior)
	missed = event.rating == Again
	occurrence = event.occurrence
	updated = match existing {
		Ok(word) => {
			..word,
			card: scheduled,
			last_at: event.at,
			seen: word.seen + 1,
			misses: if missed word.misses + 1 else word.misses,
			forms: [occurrence.form].concat(word.forms.drop_if(|form| form == occurrence.form)),
			context: if missed or !word.missed_context occurrence else word.context,
			missed_context: missed or word.missed_context,
			works: word.works.insert(occurrence.work, occurrence),
		}
		Err(_) => {
			lemma: event.lemma,
			card: scheduled,
			introduced_at: event.at,
			last_at: event.at,
			seen: 1,
			misses: if missed 1 else 0,
			forms: [occurrence.form],
			context: occurrence,
			missed_context: missed,
			works: Dict.single(occurrence.work, occurrence),
		}
	}
	all.insert(event.lemma, updated)
}

## The card after the event's review; `Err` only if the scheduler is invalid,
## where the Elm app keeps the prior card.
next_card : Words.Review, Fsrs.Card -> Try(Fsrs.Card, Str)
next_card = |event, prior| Ok(Fsrs.next(Review.scheduler?, event.at, event.rating, prior)?.card)

text : JsonValue, Str -> Try(Str, Str)
text = |json, name| JsonValue.as_str(JsonValue.field(json, name)?)

whole : JsonValue, Str -> Try(I64, Str)
whole = |json, name| JsonValue.as_i64(JsonValue.field(json, name)?)

## A stable sort: equal items keep their order, as Elm's `List.sortBy` does.
sort_by : List(a), (a, a -> [Before, Same, After]) -> List(a)
sort_by = |items, order|
	items
		.map_with_index(|item, index| { item, index })
		.sort_with(
			|a, b| match order(a.item, b.item) {
				Same => compare_u64(a.index, b.index)
				found => found
			},
		)
		.map(|found| found.item)

compare_i64 : I64, I64 -> [Before, Same, After]
compare_i64 = |a, b| if a < b Before else if a > b After else Same

compare_u64 : U64, U64 -> [Before, Same, After]
compare_u64 = |a, b| if a < b Before else if a > b After else Same

## Byte order, which for UTF-8 is code point order; Elm compares UTF-16 code
## units, which differs only past the Basic Multilingual Plane.
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
