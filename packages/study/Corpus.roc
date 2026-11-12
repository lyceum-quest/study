import json.JsonValue

## A work's text from the preload, as the Elm app reads it: the manifest
## entries of `corpora.json` (`ManifestEntry` in `src/Main.elm`), the OGA
## sentences of `<id>.conllu` (`src/Conllu.elm`), and the canonical passages of
## `<id>.units.json` that regroup them by citation (`src/Passage.elm`), with the
## small citation helpers of `src/Main.elm` that the workspace and reader use.
##
## A passage is the Elm app's `Conllu.Sentence`: its id is the citation (`1.2`)
## and its label the display citation (`1:2`, the Elm `verse`). A passage's
## tokens are numbered 1…n, as in the Elm app, because a passage can join
## tokens from two OGA sentences, whose own numbering restarts; word items are
## keyed by that number (`Study.word_key`).
Corpus := [].{

	## Where a corpus comes from (`Conllu.CorpusSource`).
	Source : { name : Str, url : Str, commit : Str, license : Str, edition : Str }

	## A manifest entry. Counts are 0, `units_path` "" and `passages` [] where the
	## entry has none, as the Elm decoder defaults them for entries cached by
	## earlier builds. `edition` repeats `source.edition`.
	Work : {
		id : Str,
		title : Str,
		path : Str,
		sentence_count : I64,
		token_count : I64,
		source : Source,
		citation : [Some(Citation), None],
		units_path : Str,
		passages : List(Str),
		edition : Str,
	}

	## The citation the preload attaches to each work (`src/Sources.elm`): the
	## original edition, the Opera Graeca Adnotata annotation layer, and Lyceum
	## Study's generated layers.
	Citation : {
		text : { urn : Str, author : Str, title : Str, edition : Str, repository : Str, snapshot : Str, license : Str, reader_url : Str, source_url : Str },
		annotations : { name : Str, version : Str, url : Str, license : Str },
		generated : { name : Str, layers : Str, model : Str, license : Str },
	}

	## `summary` is the FEATS column; the rest are single features from it.
	Morphology : { summary : Str, case : Str, number : Str, gender : Str }

	## A CoNLL-U word row (`Conllu.CorpusToken`). `tid` is OGA's `t_N` token key
	## (or ""), `head` the dependency head (0 for the root or `_`), and an
	## underscore field is "".
	Token : {
		id : U64,
		tid : Str,
		form : Str,
		lemma : Str,
		upos : Str,
		morphology : Morphology,
		head : I64,
		relation : Str,
		gloss : Str,
		space_after : Bool,
	}

	## A passage or OGA sentence (`Conllu.Sentence`). `id` is the citation (`1.2`),
	## `label` its display form (`1:2`), `chapter` the first citation level, and
	## `text` the Greek with the corpus's spacing. OGA placeholder rows (elided or
	## implied words) are kept apart from the visible `tokens`.
	Passage : {
		id : Str,
		label : Str,
		chapter : I64,
		text : Str,
		literal : Str,
		prose : Str,
		tokens : List(Token),
		placeholders : List(Token),
	}

	## A parsed corpus (`Conllu.Corpus`): its OGA sentences, or its passages once
	## regrouped by `from_units`.
	Parsed : { source : Source, sentences : List(Passage) }

	## A canonical passage of `<id>.units.json` (`Passage.Unit`): its citation,
	## display label, the OGA token ids it spans, and its translations.
	Unit : { ref : Str, label : Str, tokens : List(Str), prose : Str, literal : Str }

	# MANIFEST

	## The works of `corpora.json`, as `manifestDecoder`; a manifest of another
	## version than 1 is `Err`, as `handleManifest` ignores it.
	manifest : Str -> Try(List(Work), Str)
	manifest = |text_json| {
		json = JsonValue.decode(text_json)?
		version = JsonValue.as_i64(JsonValue.field(json, "version")?)?
		corpora = JsonValue.items(JsonValue.field(json, "corpora")?)?.map_try(work)?
		if version != 1 {
			return Err("unsupported manifest version ${version.to_str()}")
		}
		Ok(corpora)
	}

	## The works of `corpora.json` that have canonical passages: review needs them.
	works : Str -> Try(List(Work), Str)
	works = |manifest_json| manifest(manifest_json).map_ok(|found| found.drop_if(|entry| entry.units_path == ""))

	# CONLL-U, as `Conllu.parse`

	## The sentences of a CoNLL-U corpus. Multiword and empty-node rows are
	## skipped; a row without 10 tab-separated columns, an invalid head, or a
	## corpus without sentences is `Err`.
	parse : Source, Str -> Try(Parsed, Str)
	parse = |source, raw| {
		var $metadata = Dict.empty()
		var $rows = []
		var $sentences = []
		for line in raw.replace_each("\r\n", "\n").replace_each("\r", "\n").split_on("\n") {
			if line == "" {
				match finish_sentence($metadata, $rows, $sentences.len())? {
					Some(sentence) => {
						$sentences = $sentences.append(sentence)
						$metadata = Dict.empty()
					}
					# As in the Elm app, metadata before an empty sentence carries over.
					None => {}
				}
				$rows = []
			} else if line.starts_with("#") {
				$metadata = insert_metadata(line, $metadata)
			} else {
				$rows = $rows.append(parse_row(line)?)
			}
		}
		match finish_sentence($metadata, $rows, $sentences.len())? {
			Some(sentence) => {
				$sentences = $sentences.append(sentence)
			}
			None => {}
		}
		if $sentences.is_empty() {
			return Err("Corpus contains no sentences")
		}
		Ok({ source, sentences: $sentences })
	}

	# PASSAGES, as `src/Passage.elm`

	## A `units.json` file (`Passage.unitsDecoder`).
	decode_units : Str -> Try(List(Unit), Str)
	decode_units = |units_json|
		JsonValue.items(JsonValue.decode(units_json)?)?.map_try(
			|unit| Ok(
				{
					ref: text(unit, "ref")?,
					label: text(unit, "label")?,
					tokens: JsonValue.items(JsonValue.field(unit, "tokens")?)?.map_try(JsonValue.as_str)?,
					prose: text(unit, "prose")?,
					literal: text(unit, "literal")?,
				},
			),
		)

	## Rebuilds a parsed corpus as its passages. Passages whose tokens are not all
	## present are dropped.
	from_units : List(Unit), Parsed -> Parsed
	from_units = |units, parsed| {
		by_tid = Dict.from_list(parsed.sentences.join_map(|sentence| sentence.tokens).map(|token| (token.tid, token)))
		{
			..parsed,
			sentences: units.keep_oks(
				|unit| {
					found = unit.tokens.keep_oks(|tid| by_tid.get(tid))
					if found.len() != unit.tokens.len() or found.is_empty() {
						Err(Incomplete)
					} else {
						tokens = found.map_with_index(|token, index| { ..token, id: index + 1 })
						Ok(
							{
								id: unit.ref,
								label: unit.label,
								chapter: match parts(unit.ref) {
									[first, ..] => elm_to_int(first) ?? 1
									[] => 1
								},
								text: spaced(tokens),
								literal: unit.literal,
								prose: unit.prose,
								tokens,
								placeholders: [],
							},
						)
					}
				},
			),
		}
	}

	## A work's sentences regrouped into its canonical passages; a work without a
	## passages file (`units` "") keeps its sentences (`parseWork`).
	parse_work : Work, Str, Str -> Try(Parsed, Str)
	parse_work = |entry, conllu, units| {
		parsed = parse(entry.source, conllu)?
		if units == "" {
			Ok(parsed)
		} else {
			Ok(from_units(decode_units(units)?, parsed))
		}
	}

	## The passages of `units` (a `units.json`) over the sentences of `conllu`.
	passages : Str, Str -> Try(List(Passage), Str)
	passages = |conllu, units| {
		parsed = parse({ name: "", url: "", commit: "", license: "", edition: "" }, conllu)?
		Ok(from_units(decode_units(units)?, parsed).sentences)
	}

	## Citation levels of a ref: `1.2` -> ["1", "2"]. A unit split at its
	## sentences adds its part number as a level: `43~2` (Stephanus page 43, §2)
	## -> ["43", "2"].
	parts : Str -> List(Str)
	parts = |ref| ref.replace_each("~", ".").split_on(".")

	## Whether the work's canonical units are split into numbered parts (every ref
	## has a `~n`).
	is_split : List(Passage) -> Bool
	is_split = |found| !found.is_empty() and found.all(|passage| passage.id.contains("~"))

	levels : List(Passage) -> U64
	levels = |found|
		match found.first() {
			Ok(passage) => parts(passage.id).len()
			Err(_) => 1
		}

	## Names for the picker's selects, by citation depth; split works end with a
	## `§` level.
	level_names : Bool, Bool, U64 -> List(Str)
	level_names = |bible, split, depth|
		if split {
			# The Elm `depth - 1` goes negative for a depth of 0, naming no levels.
			(if depth == 2 ["Page"] else if depth == 0 [] else level_names(bible, Bool.False, depth - 1)).append("§")
		} else {
			unsplit_names(bible, depth)
		}

	unsplit_names : Bool, U64 -> List(Str)
	unsplit_names = |bible, depth|
		match (bible, depth) {
			(Bool.True, 2) => ["Chapter", "Verse"]
			(_, 2) => ["Book", "Line"]
			(_, 3) => ["Book", "Chapter", "Section"]
			_ => List.repeat("Part", depth)
		}

	# CITATIONS, from `src/Main.elm`

	## The Elm app's stand-in while no corpus is loaded (`fallbackSentence`).
	missing : Passage
	missing = { id: "missing", label: "1", chapter: 1, text: "No corpus loaded.", literal: "", prose: "", tokens: [], placeholders: [] }

	## The passage at `index`, or `missing` (`currentSentence`).
	passage_at : List(Passage), U64 -> Passage
	passage_at = |found, index| found.get(index) ?? missing

	## The index of the passage citing `ref` (`indexOfRef`).
	index_of_ref : Str, List(Passage) -> [Some(U64), None]
	index_of_ref = |ref, found|
		match found.find_first_index(|passage| passage.id == ref) {
			Ok(index) => Some(index)
			Err(_) => None
		}

	## The first passage whose citation starts with `prefix` (`1` = chapter 1,
	## `1.2` = 1:2), as `jumpToCitation` finds it.
	citation_index : Str, List(Passage) -> [Some(U64), None]
	citation_index = |prefix, found| {
		wanted = parts(prefix)
		match found.find_first_index(|passage| parts(passage.id).take_first(wanted.len()) == wanted) {
			Ok(index) => Some(index)
			Err(_) => None
		}
	}

	## `1:2`, `1 2`, `1,2`, or `43 §2` typed into the go-to box -> `1.2` or `43.2`
	## (`normalizeCitation`).
	normalize_citation : Str -> Str
	normalize_citation = |typed| {
		dotted = [":", " ", ",", "\u(00A7)"].fold(typed.trim(), |found, mark| found.replace_each(mark, "."))
		Str.join_with(dotted.split_on(".").drop_if(|level| level == ""), ".")
	}

	## A citation as the work prints it: `1:66` for the Bible, `1.2.1` for
	## sections, `43 §2` for a split page (`refLabel`; `library` is the manifest's
	## works).
	ref_label : List(Work), Str, Str -> Str
	ref_label = |library, work_id, ref| {
		bible = match library.find_first(|entry| entry.id == work_id) {
			Ok({ citation: Some(found), .. }) => found.text.urn.contains("tlg0031.") or found.text.urn.contains("tlg0527.")
			_ => Bool.False
		}
		(base, part) = match ref.split_on("~") {
			[unit, number] => (unit, " \u(00A7)${number}")
			_ => (ref, "")
		}
		found_levels = base.split_on(".")
		shown = if bible and found_levels.len() >= 2 {
			"${Str.join_with(found_levels.take_first(found_levels.len() - 1), ".")}:${found_levels.last() ?? ""}"
		} else {
			base
		}
		"${shown}${part}"
	}

	## The passage the learner last had open in a work (positions are saved as
	## 1-based passage indexes), or its first (`savedRef`).
	saved_ref : Work, Dict(Str, I64) -> Str
	saved_ref = |entry, positions| {
		first = entry.passages.first() ?? "1"
		match positions.get(entry.id) {
			Ok(position) if position >= 1 => entry.passages.get((position - 1).to_u64_wrap()) ?? first
			_ => first
		}
	}

	## A gloss as the workspace shows it: hyphens joining an English phrase become
	## spaces, and a missing gloss is a dash (`displayGloss`).
	display_gloss : Str -> Str
	display_gloss = |gloss| if gloss == "" "\u(2014)" else gloss.replace_each("-", " ")

	## OGA numbers homographs (`λέγω3`); the number is kept in keys but not shown
	## (`displayLemma`).
	display_lemma : Str -> Str
	display_lemma = |lemma| {
		bytes = lemma.to_utf8()
		var $end = bytes.len()
		while $end > 0 and is_digit(bytes.get($end - 1) ?? 0) {
			$end = $end - 1
		}
		if $end == 0 lemma else Str.from_utf8(bytes.take_first($end)) ?? lemma
	}
}

## A CoNLL-U row before it becomes a token.
Row : { id : Str, form : Str, lemma : Str, upos : Str, feats : Str, head : Str, relation : Str, misc : Str }

work : JsonValue -> Try(Corpus.Work, Str)
work = |entry| {
	id = text(entry, "id")?
	path = text(entry, "path")?
	source = corpus_source(JsonValue.field(entry, "source")?)?
	Ok(
		{
			id,
			title: text(entry, "title") ?? id,
			path,
			sentence_count: whole(entry, "sentenceCount") ?? 0,
			token_count: whole(entry, "tokenCount") ?? 0,
			source,
			# As in the Elm app, an entry without a readable citation shows none.
			citation: match citation(entry) {
				Ok(found) => Some(found)
				Err(_) => None
			},
			units_path: text(entry, "unitsPath") ?? "",
			passages: strings(entry, "passages") ?? [],
			edition: source.edition,
		},
	)
}

corpus_source : JsonValue -> Try(Corpus.Source, Str)
corpus_source = |json|
	Ok(
		{
			name: text(json, "name")?,
			url: text(json, "url")?,
			commit: text(json, "commit")?,
			license: text(json, "license")?,
			edition: text(json, "edition")?,
		},
	)

insert_metadata : Str, Dict(Str, Str) -> Dict(Str, Str)
insert_metadata = |line, metadata|
	match line.drop_prefix("#").split_on("=") {
		[key, .. as values] if !values.is_empty() => metadata.insert(key.trim(), Str.join_with(values, "=").trim())
		_ => metadata
	}

parse_row : Str -> Try(Row, Str)
parse_row = |line|
	match line.split_on("\t") {
		[id, form, lemma, upos, _, feats, head, relation, _, misc] => Ok({ id, form, lemma, upos, feats, head, relation, misc })
		_ => Err("Invalid CoNLL-U row: expected 10 tab-separated columns")
	}

## The sentence of the rows read since the last blank line, or None when it has
## no word rows.
finish_sentence : Dict(Str, Str), List(Row), U64 -> Try([Some(Corpus.Passage), None], Str)
finish_sentence = |metadata, all_rows, count| {
	rows = all_rows.keep_if(|row| is_number(row.id))
	if rows.is_empty() {
		return Ok(None)
	}
	tokens = tokens_from_rows(rows.drop_if(is_placeholder))?
	placeholders = tokens_from_rows(rows.keep_if(is_placeholder))?
	sentence_id = first_metadata(metadata, ["sent_id", "sentence_id"])
	citation_id = first_metadata(metadata, ["citation", "cts_urn"])
	reference = first_reference(rows, citation_id, sentence_id)
	sent_id = metadata.get("sent_id") ?? ""
	stable_id = if sent_id != "" {
		sent_id
	} else if citation_id != "" and sentence_id != "" {
		"${citation_id}-s${sentence_id}"
	} else {
		sentence_id
	}
	Ok(
		Some(
			{
				id: if stable_id == "" "sentence-${(count + 1).to_str()}" else stable_id,
				label: if reference == "" sentence_id else reference,
				# A sentence number is not a citation; corpora without references form one division.
				chapter: if reference == sentence_id 1 else chapter_from_reference(reference),
				text: match metadata.get("text") {
					Ok(found) if found != "" => found
					_ => spaced(tokens)
				},
				literal: first_metadata(metadata, ["text_en_literal", "literal_translation"]),
				prose: first_metadata(metadata, ["text_en", "prose_translation"]),
				tokens,
				placeholders,
			},
		),
	)
}

## OGA adds rows for elided or implied words (forms like `[0]`, MISC starting
## `e_`). They are kept apart from the visible tokens so no view shows, glosses,
## counts, or grades them, and spacing is computed as if they were absent.
is_placeholder : Row -> Bool
is_placeholder = |row| row.misc.starts_with("e_")

## The first invalid row's error, in row order.
tokens_from_rows : List(Row) -> Try(List(Corpus.Token), Str)
tokens_from_rows = |rows| rows.map_with_index(|row, index| (row, rows.get(index + 1))).map_try(|(row, next)| token_from_row(row, next))

token_from_row : Row, Try(Row, _) -> Try(Corpus.Token, Str)
token_from_row = |row, next| {
	token_id = match elm_to_int(row.id) {
		Ok(found) => found.to_u64_wrap()
		Err(_) => return Err("Invalid token ID ${row.id}")
	}
	head = parse_head(row.id, row.head)?
	features = parse_fields(row.feats)
	misc = parse_fields(row.misc)
	next_is_punctuation = match next {
		Ok(next_row) => next_row.upos == "PUNCT"
		Err(_) => Bool.False
	}
	Ok(
		{
			id: token_id,
			# OGA keys each token by `t_N` in the first MISC field; canonical passages refer to it.
			tid: match row.misc.split_on("|") {
				[first, ..] if first.starts_with("t_") => first
				_ => ""
			},
			form: normalized_field(row.form),
			lemma: normalized_field(row.lemma),
			upos: normalized_field(row.upos),
			morphology: {
				summary: normalized_field(row.feats),
				case: features.get("Case") ?? "",
				number: features.get("Number") ?? "",
				gender: features.get("Gender") ?? "",
			},
			head,
			relation: normalized_field(row.relation),
			gloss: if row.upos == "PUNCT" "" else match misc.get("Gloss") {
				Ok(gloss) => gloss
				Err(_) => misc.get("gloss") ?? ""
			},
			space_after: misc.get("SpaceAfter") != Ok("No") and !next_is_punctuation,
		},
	)
}

parse_head : Str, Str -> Try(I64, Str)
parse_head = |token_id, head|
	if head == "_" {
		Ok(0)
	} else {
		elm_to_int(head).map_err(|_| "Token ${token_id} has an invalid dependency head")
	}

## Elm's `String.toInt`: an optional sign and ASCII digits. Unlike the Elm
## app's JavaScript numbers, a value beyond I64 is `Err`.
elm_to_int : Str -> Try(I64, [NotAnInt])
elm_to_int = |found| {
	bytes = found.to_utf8()
	(negative, digits) = match bytes {
		['-', .. as rest] => (Bool.True, rest)
		['+', .. as rest] => (Bool.False, rest)
		_ => (Bool.False, bytes)
	}
	if digits.is_empty() or !digits.all(is_digit) {
		return Err(NotAnInt)
	}
	magnitude = I64.from_str(Str.from_utf8(digits) ?? "").map_err(|_| NotAnInt)?
	Ok(if negative -magnitude else magnitude)
}

## `Key=Value|…` fields; a later key wins, and a field without `=` has the
## value "".
parse_fields : Str -> Dict(Str, Str)
parse_fields = |serialized|
	if serialized == "" or serialized == "_" {
		Dict.empty()
	} else {
		serialized.split_on("|").fold(
			Dict.empty(),
			|found, item| match item.split_on("=") {
				[key, .. as values] => found.insert(key, Str.join_with(values, "="))
				[] => found
			},
		)
	}

## The sentence's citation: the first row's `Ref`, else the citation's last
## `:` level, else the sentence number.
first_reference : List(Row), Str, Str -> Str
first_reference = |rows, citation_id, sentence_id| {
	misc_reference = match rows.first() {
		Ok(row) => parse_fields(row.misc).get("Ref") ?? ""
		Err(_) => ""
	}
	citation_reference = citation_id.split_on(":").last() ?? ""
	if misc_reference != "" {
		misc_reference
	} else if citation_reference != "" {
		citation_reference
	} else {
		sentence_id
	}
}

## The first run of digits in the reference's last `:` level, or 1.
chapter_from_reference : Str -> I64
chapter_from_reference = |reference| {
	local = reference.split_on(":").last() ?? reference
	var $digits = []
	for byte in local.to_utf8() {
		if is_digit(byte) {
			$digits = $digits.append(byte)
		} else if !$digits.is_empty() {
			break
		}
	}
	elm_to_int(Str.from_utf8($digits) ?? "") ?? 1
}

first_metadata : Dict(Str, Str), List(Str) -> Str
first_metadata = |metadata, keys| keys.keep_oks(|key| metadata.get(key)).drop_if(|value| value == "").first() ?? ""

## The tokens' forms with the corpus's spacing.
spaced : List(Corpus.Token) -> Str
spaced = |tokens| Str.join_with(tokens.map(|token| if (token.space_after) "${token.form} " else token.form), "").trim_end()

is_digit : U8 -> Bool
is_digit = |byte| byte >= '0' and byte <= '9'

is_number : Str -> Bool
is_number = |id| id != "" and id.to_utf8().all(is_digit)

normalized_field : Str -> Str
normalized_field = |value| if value == "_" "" else value

text : JsonValue, Str -> Try(Str, Str)
text = |json, name| JsonValue.as_str(JsonValue.field(json, name)?)

whole : JsonValue, Str -> Try(I64, Str)
whole = |json, name| JsonValue.as_i64(JsonValue.field(json, name)?)

strings : JsonValue, Str -> Try(List(Str), Str)
strings = |json, name| JsonValue.items(JsonValue.field(json, name)?)?.map_try(JsonValue.as_str)

citation : JsonValue -> Try(Corpus.Citation, Str)
citation = |entry| {
	found = JsonValue.field(entry, "citation")?
	source = JsonValue.field(found, "text")?
	annotations = JsonValue.field(found, "annotations")?
	generated = JsonValue.field(found, "generated")?
	Ok(
		{
			text: {
				urn: text(source, "urn")?,
				author: text(source, "author")?,
				title: text(source, "title")?,
				edition: text(source, "edition")?,
				repository: text(source, "repository")?,
				snapshot: text(source, "snapshot")?,
				license: text(source, "license")?,
				reader_url: text(source, "readerUrl")?,
				source_url: text(source, "sourceUrl")?,
			},
			annotations: {
				name: text(annotations, "name")?,
				version: text(annotations, "version")?,
				url: text(annotations, "url")?,
				license: text(annotations, "license")?,
			},
			generated: {
				name: text(generated, "name")?,
				layers: text(generated, "layers")?,
				model: text(generated, "model")?,
				license: text(generated, "license")?,
			},
		},
	)
}
