import fsrs.Fsrs
import json.JsonValue

## Finished study attempts, ported from the parts of `src/Study.elm` the review
## screen uses: their items, ratings, statistics, and the records the Elm app
## keeps in the IndexedDB `progress` store, so either app reads what the other
## wrote.
##
## A passage has one item per word (keyed `w:<token number>`) plus the literal
## and prose translations. Items revealed before the checkpoint are recorded as
## such and excluded from unassisted statistics.
Study := [].{

	ItemKind : [WordItem, LiteralItem, ProseItem]

	## One graded item of a finished attempt. `mark` is the learner's own judgement.
	Item : {
		key : Str,
		kind : ItemKind,
		form : Str,
		lemma : Str,
		guess : Str,
		reference : Str,
		revealed_early : Bool,
		mark : [Some(Bool), None],
	}

	## `rating` is None in attempts saved before ratings were recorded.
	Attempt : {
		id : Str,
		work : Str,
		passage : Str,
		sentence_id : Str,
		sentence_text : Str,
		started_at : I64,
		finished_at : I64,
		items : List(Item),
		rating : [Some(Fsrs.Rating), None],
	}

	word_key : U64 -> Str
	word_key = |token_number| "w:${token_number.to_str()}"

	## Punctuation is attached to the preceding word, never a word to gloss. Judged
	## by the characters, not the tag: OGA tags some words as punctuation (Luke
	## 1:66 Τί).
	is_word_token : Str -> Bool
	is_word_token = |form| form != "" and punctuation.fold(form, |rest, mark| rest.replace_each(mark, "")) != ""

	## Marked items and how many of them were marked right, over `attempts`.
	marked : List(Attempt) -> { judged : U64, right : U64 }
	marked = |attempts| {
		items = attempts.join_map(|attempt| attempt.items)
		{
			judged: items.count_if(|item| item.mark != None),
			right: items.count_if(|item| item.mark == Some(Bool.True)),
		}
	}

	rating_name : Fsrs.Rating -> Str
	rating_name = |rating|
		match rating {
			Again => "again"
			Hard => "hard"
			Good => "good"
			Easy => "easy"
		}

	rating_from_name : Str -> Try(Fsrs.Rating, Str)
	rating_from_name = |name|
		match name {
			"again" => Ok(Again)
			"hard" => Ok(Hard)
			"good" => Ok(Good)
			"easy" => Ok(Easy)
			_ => Err("unknown rating ${name}")
		}

	# ENCODING, as `Study.encodeAttempt` and `Study.attemptDecoder` in src/Study.elm.

	encode_attempt : Attempt -> JsonValue
	encode_attempt = |attempt| {
		rating = match attempt.rating {
			Some(r) => [("rating", JsonValue.str(rating_name(r)))]
			None => []
		}
		JsonValue.object(
			[
				("id", JsonValue.str(attempt.id)),
				("type", JsonValue.str("attempt")),
				("work", JsonValue.str(attempt.work)),
				("passage", JsonValue.str(attempt.passage)),
				("sentenceId", JsonValue.str(attempt.sentence_id)),
				("sentenceText", JsonValue.str(attempt.sentence_text)),
				("startedAt", JsonValue.int(attempt.started_at)),
				("finishedAt", JsonValue.int(attempt.finished_at)),
				("items", JsonValue.array(attempt.items.map(encode_item))),
			].concat(rating),
		)
	}

	## Only records written by `encode_attempt` (or the Elm app) decode; review
	## cards and other rows in the progress store are `Err`.
	decode_attempt : JsonValue -> Try(Attempt, Str)
	decode_attempt = |json| {
		if text(json, "type") != Ok("attempt") {
			return Err("not an attempt")
		}
		items = JsonValue.items(JsonValue.field(json, "items")?)?.map_try(decode_item)?
		rating = match JsonValue.field(json, "rating") {
			Ok(name) => Some(rating_from_name(JsonValue.as_str(name)?)?)
			Err(_) => None
		}
		Ok(
			{
				id: text(json, "id")?,
				work: text(json, "work")?,
				passage: text(json, "passage")?,
				sentence_id: text(json, "sentenceId")?,
				sentence_text: text(json, "sentenceText")?,
				started_at: whole(json, "startedAt")?,
				finished_at: whole(json, "finishedAt")?,
				items: items.drop_if(is_placeholder_item),
				rating,
			},
		)
	}

	## The Elm app's empty draft (`Study.encodeDraft Study.emptyDraft`), written
	## over a passage's draft once it is graded, as the Elm app does.
	empty_draft : JsonValue
	empty_draft = JsonValue.object(
		[
			("glosses", JsonValue.array([])),
			("literal", JsonValue.str("")),
			("prose", JsonValue.str("")),
			("revealed", JsonValue.array([])),
			("submitted", JsonValue.boolean(Bool.False)),
			("marks", JsonValue.object([])),
			("startedAt", JsonValue.int(0)),
			("updatedAt", JsonValue.int(0)),
		],
	)
}

punctuation : List(Str)
punctuation = [".", ",", ";", ":", "!", "?", "\u(00B7)", "\u(0387)", "\u(037E)", "(", ")", "[", "]", "\u(00AB)", "\u(00BB)", "\u(201C)", "\u(201D)", "\u(2018)", "\u(2019)", "\u(2014)", "\u(2013)", "'", "\""]

kind_name : Study.ItemKind -> Str
kind_name = |kind|
	match kind {
		WordItem => "word"
		LiteralItem => "literal"
		ProseItem => "prose"
	}

encode_item : Study.Item -> JsonValue
encode_item = |item|
	JsonValue.object(
		[
			("key", JsonValue.str(item.key)),
			("kind", JsonValue.str(kind_name(item.kind))),
			("form", JsonValue.str(item.form)),
			("lemma", JsonValue.str(item.lemma)),
			("guess", JsonValue.str(item.guess)),
			("reference", JsonValue.str(item.reference)),
			("revealedEarly", JsonValue.boolean(item.revealed_early)),
			("mark", match item.mark {
				Some(right) => JsonValue.boolean(right)
				None => JsonValue.null
			}),
		],
	)

decode_item : JsonValue -> Try(Study.Item, Str)
decode_item = |json| {
	mark_json = JsonValue.field(json, "mark")?
	Ok(
		{
			key: text(json, "key")?,
			kind: match text(json, "kind")? {
				"literal" => LiteralItem
				"prose" => ProseItem
				_ => WordItem
			},
			form: text(json, "form")?,
			lemma: text(json, "lemma")?,
			guess: text(json, "guess")?,
			reference: text(json, "reference")?,
			revealed_early: JsonValue.as_bool(JsonValue.field(json, "revealedEarly")?)?,
			mark: if JsonValue.is_null(mark_json) None else Some(JsonValue.as_bool(mark_json)?),
		},
	)
}

## Attempts saved before OGA placeholder rows were hidden may hold a graded
## `[0]`; it is dropped so it is never shown or counted.
is_placeholder_item : Study.Item -> Bool
is_placeholder_item = |item| {
	bytes = item.form.to_utf8()
	if item.kind != WordItem or bytes.len() < 2 or bytes.first() != Ok('[') or bytes.last() != Ok(']') {
		Bool.False
	} else {
		bytes.drop_first(1).take_first(bytes.len() - 2).all(|byte| byte >= '0' and byte <= '9')
	}
}

text : JsonValue, Str -> Try(Str, Str)
text = |json, name| JsonValue.as_str(JsonValue.field(json, name)?)

whole : JsonValue, Str -> Try(I64, Str)
whole = |json, name| JsonValue.as_i64(JsonValue.field(json, name)?)
