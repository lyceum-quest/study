import fsrs.Fsrs
import json.JsonValue
import Corpus
import Tools

## Study attempts, ported from `src/Study.elm`: drafts in progress, self-graded
## attempts, their ratings, and statistics over them, in the records the Elm
## app keeps in IndexedDB (drafts in `metadata` as `draft:<work>:<ref>`,
## attempts in `progress`), so either app reads what the other wrote. Also the
## functions of `src/Main.elm` that build an attempt's items from a passage and
## its draft.
##
## A passage has one item per word (keyed `w:<token number>`) plus the literal
## and prose translations. Items revealed before the checkpoint are recorded as
## such and excluded from unassisted statistics.
Study := [].{

	## An unfinished attempt at one passage, saved as the learner works so a
	## refresh restores it. `glosses` are keyed by token number, `revealed` and
	## `marks` by item key.
	Draft : {
		glosses : Dict(U64, Str),
		literal : Str,
		prose : Str,
		revealed : Set(Str),
		submitted : Bool,
		marks : Dict(Str, Bool),
		started_at : I64,
		updated_at : I64,
	}

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

	WordStat : { lemma : Str, wrong : U64, judged : U64 }

	Stats : {
		attempts : U64,
		judged : U64,
		right : U64,
		unassisted_judged : U64,
		unassisted_right : U64,
		struggles : List(WordStat),
	}

	Tally : { right : U64, wrong : U64, unmarked : U64 }

	empty_draft : Draft
	empty_draft = {
		glosses: Dict.empty(),
		literal: "",
		prose: "",
		revealed: Set.empty(),
		submitted: Bool.False,
		marks: Dict.empty(),
		started_at: 0,
		updated_at: 0,
	}

	word_key : U64 -> Str
	word_key = |token_number| "w:${token_number.to_str()}"

	literal_key : Str
	literal_key = "literal"

	prose_key : Str
	prose_key = "prose"

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

	## Keys the learner marked wrong in their most recent finished attempt at this
	## passage, with what they answered.
	missed_last_time : Str, Str, List(Attempt) -> Dict(Str, Str)
	missed_last_time = |work, passage, attempts|
		match passage_attempts(work, passage, attempts).first() {
			Ok(attempt) => Dict.from_list(missed(attempt).map(|item| (item.key, item.guess)))
			Err(_) => Dict.empty()
		}

	## Finished attempts at one passage, newest first; attempts finished at the
	## same time keep their order, as Elm's stable `List.sortBy`.
	passage_attempts : Str, Str, List(Attempt) -> List(Attempt)
	passage_attempts = |work, passage, attempts|
		attempts
			.keep_if(|attempt| attempt.work == work and attempt.passage == passage)
			.sort_by_reversed(|attempt| attempt.finished_at)

	## Items the learner marked wrong.
	missed : Attempt -> List(Item)
	missed = |attempt| attempt.items.keep_if(|item| item.mark == Some(Bool.False))

	tally : Attempt -> Tally
	tally = |attempt| {
		right: attempt.items.count_if(|item| item.mark == Some(Bool.True)),
		wrong: attempt.items.count_if(|item| item.mark == Some(Bool.False)),
		unmarked: attempt.items.count_if(|item| item.mark == None),
	}

	## Judged items over `attempts`, those not revealed early, and the twelve
	## lemmas most often marked wrong (ties by lemma).
	stats : List(Attempt) -> Stats
	stats = |attempts| {
		judged = attempts.join_map(|attempt| attempt.items).keep_if(|item| item.mark != None)
		unassisted = judged.drop_if(|item| item.revealed_early)
		word_totals = judged
			.keep_if(|item| item.kind == WordItem)
			.fold(
				Dict.empty(),
				|totals, item| totals.update(
					item.lemma,
					|current| {
						(wrong, count) = current ?? (0, 0)
						Ok((if item.mark == Some(Bool.False) wrong + 1 else wrong, count + 1))
					},
				),
			)
		{
			attempts: attempts.len(),
			judged: judged.len(),
			right: judged.count_if(|item| item.mark == Some(Bool.True)),
			unassisted_judged: unassisted.len(),
			unassisted_right: unassisted.count_if(|item| item.mark == Some(Bool.True)),
			struggles: word_totals
				.to_list()
				.map(|(lemma, (wrong, count))| { lemma, wrong, judged: count })
				.keep_if(|stat| stat.wrong > 0)
				# Lemmas are distinct, so this total order equals the Elm's stable sort of the lemma-ordered Dict.
				.sort_with(|a, b| if a.wrong > b.wrong Before else if a.wrong < b.wrong After else compare_text(a.lemma, b.lemma))
				.take_first(12),
		}
	}

	# BUILDING ATTEMPTS, from `src/Main.elm`

	## A draft submitted over 30 minutes ago reopens unsubmitted, its marks
	## cleared (`resumable`).
	resumable : I64, Draft -> Draft
	resumable = |now, draft|
		if draft.submitted and now - draft.updated_at > 30 * 60 * 1000 {
			{ ..draft, submitted: Bool.False, marks: Dict.empty() }
		} else {
			draft
		}

	## Pairs each word with the punctuation that follows it (`groupWords`).
	## Punctuation before the first word is dropped.
	group_words : List(Corpus.Token) -> List((Corpus.Token, Str))
	group_words = |tokens|
		tokens.fold(
			[],
			|groups, token|
				if is_word_token(token.form) {
					groups.append((token, ""))
				} else {
					match groups.last() {
						Ok((word, suffix)) => groups.drop_last(1).append((word, "${suffix}${token.form}"))
						Err(_) => groups
					}
				},
		)

	## The learner's last finished attempt at `passage` (a citation) of `work`
	## (`lastAttempt`).
	last_attempt : Str, Str, List(Attempt) -> [Some(Attempt), None]
	last_attempt = |work, passage, attempts|
		match passage_attempts(work, passage, attempts).first() {
			Ok(attempt) => Some(attempt)
			Err(_) => None
		}

	## Word keys to ask on a repeat: those missed or revealed early last time.
	## `None` asks every word: a first attempt (`last` is None), or the learner
	## chose every word (`all_words`) (`askedWords`).
	asked_words : Bool, [Some(Attempt), None] -> [Some(Set(Str)), None]
	asked_words = |all_words, last|
		match (all_words, last) {
			(Bool.False, Some(attempt)) => Some(
				Set.from_list(
					attempt.items
						.keep_if(|item| item.kind == WordItem and (item.mark == Some(Bool.False) or item.revealed_early))
						.map(|item| item.key),
				),
			)
			_ => None
		}

	is_asked : [Some(Set(Str)), None], Str -> Bool
	is_asked = |asked, key|
		match asked {
			Some(keys) => keys.contains(key)
			None => Bool.True
		}

	## The items of `passage` in grading order: each word (punctuation excluded),
	## then the translations the learner worked on or has enabled (`studyItems`;
	## `asked` is `asked_words`).
	study_items : Corpus.Passage, Draft, Tools.ModuleSettings, [Some(Set(Str)), None] -> List(Item)
	study_items = |passage, draft, settings, asked| {
		item = |key, kind, form, lemma, guess, reference| {
			key,
			kind,
			form,
			lemma,
			guess,
			reference,
			revealed_early: draft.revealed.contains(key),
			mark: match draft.marks.get(key) {
				Ok(right) => Some(right)
				Err(_) => None
			},
		}
		words = if Tools.module_mode(GlossModule, settings) != ModuleOff or !draft.glosses.is_empty() {
			passage.tokens
				.keep_if(|token| is_word_token(token.form))
				# A word not asked joins the attempt once the learner reveals it or marks it missed in grading.
				.keep_if(|token| is_asked(asked, word_key(token.id)) or draft.marks.contains(word_key(token.id)) or draft.revealed.contains(word_key(token.id)))
				.map(|token| item(word_key(token.id), WordItem, token.form, token.lemma, draft.glosses.get(token.id) ?? "", token.gloss))
		} else {
			[]
		}
		literal = if Tools.module_mode(LiteralModule, settings) != ModuleOff or draft.literal != "" {
			[item(literal_key, LiteralItem, "", "", draft.literal, passage.literal)]
		} else {
			[]
		}
		prose = if Tools.module_mode(ProseModule, settings) != ModuleOff or draft.prose != "" {
			[item(prose_key, ProseItem, "", "", draft.prose, passage.prose)]
		} else {
			[]
		}
		words.concat(literal).concat(prose)
	}

	## A finished attempt at `passage` of `work`, rated `rating` at `now`, with
	## `items` (`study_items`) (`buildAttempt`).
	build_attempt : I64, Fsrs.Rating, Str, Corpus.Passage, Draft, List(Item) -> Attempt
	build_attempt = |now, rating, work, passage, draft, items| {
		id: "attempt:${work}:${passage.id}:${now.to_str()}",
		work,
		passage: passage.id,
		sentence_id: passage.id,
		sentence_text: passage.text,
		started_at: if draft.started_at == 0 now else draft.started_at,
		finished_at: now,
		items,
		rating: Some(rating),
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

	# DRAFTS, as `Study.encodeDraft` and `Study.draftDecoder`. Glosses, revealed
	# keys and marks are written in key order, as the Elm `Dict` and `Set` list
	# them, so the text equals what the Elm app writes.

	encode_draft : Draft -> JsonValue
	encode_draft = |draft|
		JsonValue.object(
			[
				("glosses", JsonValue.array(draft.glosses.to_list().sort_by(|(id, _)| id).map(|(id, gloss)| JsonValue.array([JsonValue.int(id.to_i64_wrap()), JsonValue.str(gloss)])))),
				("literal", JsonValue.str(draft.literal)),
				("prose", JsonValue.str(draft.prose)),
				("revealed", JsonValue.array(draft.revealed.to_list().sort_with(compare_text).map(JsonValue.str))),
				("submitted", JsonValue.boolean(draft.submitted)),
				("marks", JsonValue.object(draft.marks.to_list().sort_with(|(a, _), (b, _)| compare_text(a, b)).map(|(key, right)| (key, JsonValue.boolean(right))))),
				("startedAt", JsonValue.int(draft.started_at)),
				("updatedAt", JsonValue.int(draft.updated_at)),
			],
		)

	## A draft as the Elm app or `encode_draft` wrote it; `updatedAt` is 0 where
	## missing or invalid, as in drafts saved before it was recorded.
	decode_draft : JsonValue -> Try(Draft, Str)
	decode_draft = |json| {
		glosses = JsonValue.items(JsonValue.field(json, "glosses")?)?.map_try(
			|pair| {
				values = JsonValue.items(pair)?
				id = JsonValue.as_i64(values.get(0) ?? return Err("expected a gloss's token number"))?
				gloss = JsonValue.as_str(values.get(1) ?? return Err("expected a gloss"))?
				# Workaround: the Elm `Dict Int` would accept a negative token number, which no token has; a U64 key cannot.
				if id < 0 {
					return Err("expected a token number, found ${id.to_str()}")
				}
				Ok((id.to_u64_wrap(), gloss))
			},
		)?
		revealed = JsonValue.items(JsonValue.field(json, "revealed")?)?.map_try(JsonValue.as_str)?
		marks_json = JsonValue.field(json, "marks")?
		if !JsonValue.encode(marks_json).starts_with("{") {
			return Err("expected an object of marks")
		}
		marks = JsonValue.fields(marks_json).map_try(|(key, right)| Ok((key, JsonValue.as_bool(right)?)))?
		Ok(
			{
				glosses: Dict.from_list(glosses),
				literal: text(json, "literal")?,
				prose: text(json, "prose")?,
				revealed: Set.from_list(revealed),
				submitted: JsonValue.as_bool(JsonValue.field(json, "submitted")?)?,
				marks: Dict.from_list(marks),
				started_at: whole(json, "startedAt")?,
				updated_at: whole(json, "updatedAt") ?? 0,
			},
		)
	}

	## The key a passage's draft is stored under in the `metadata` store.
	draft_key : Str, Str -> Str
	draft_key = |work, ref| "draft:${work}:${ref}"
}

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
