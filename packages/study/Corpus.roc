import json.JsonValue

## A work's canonical passages from the preload, as the Elm app builds them
## (`src/Conllu.elm` and `src/Passage.elm`), with only the token fields review
## needs: the manifest entry (`corpora.json`), the OGA tokens (`<id>.conllu`),
## and the passages that regroup them by citation (`<id>.units.json`).
##
## A passage's tokens are numbered 1…n, as in the Elm app, because a passage
## can join tokens from two OGA sentences, whose own numbering restarts; word
## items are keyed by that number (`Study.word_key`).
Corpus := [].{

	Work : { id : Str, title : Str, path : Str, units_path : Str, passages : List(Str), edition : Str, citation : [Some(Citation), None] }

	## The citation the preload attaches to each work (`src/Sources.elm`): the
	## original edition, the Opera Graeca Adnotata annotation layer, and Lyceum
	## Study's generated layers.
	Citation : {
		text : { urn : Str, author : Str, title : Str, edition : Str, repository : Str, snapshot : Str, license : Str, reader_url : Str, source_url : Str },
		annotations : { name : Str, version : Str, url : Str, license : Str },
		generated : { name : Str, layers : Str, model : Str, license : Str },
	}

	Token : { tid : Str, form : Str, lemma : Str, gloss : Str, space_after : Bool }

	## `id` is the citation (`1.2`), `label` its display form (`1:2`), `text` the
	## Greek with the corpus's spacing.
	Passage : { id : Str, label : Str, text : Str, literal : Str, prose : Str, tokens : List(Token) }

	## The works of `corpora.json`. Works without a passages file are left out:
	## review needs canonical passages.
	works : Str -> Try(List(Work), Str)
	works = |manifest| {
		corpora = JsonValue.items(JsonValue.field(JsonValue.decode(manifest)?, "corpora")?)?
		corpora.map_try(
			|entry| Ok(
				{
					id: text(entry, "id")?,
					title: text(entry, "title")?,
					path: text(entry, "path")?,
					units_path: match JsonValue.field(entry, "unitsPath") {
						Ok(path) => JsonValue.as_str(path)?
						Err(_) => ""
					},
					passages: JsonValue.items(JsonValue.field(entry, "passages")?)?.map_try(JsonValue.as_str)?,
					edition: text(JsonValue.field(entry, "source")?, "edition")?,
					# As in the Elm app, an entry without a readable citation shows none.
					citation: match citation(entry) {
						Ok(found) => Some(found)
						Err(_) => None
					},
				},
			),
		).map_ok(|found| found.drop_if(|work| work.units_path == ""))
	}

	## The passages of `units` (a `units.json`) over the tokens of `conllu`.
	## Passages whose tokens are not all present are dropped.
	passages : Str, Str -> Try(List(Passage), Str)
	passages = |conllu, units| {
		by_tid = Dict.from_list(tokens(conllu).map(|token| (token.tid, token)))
		JsonValue.items(JsonValue.decode(units)?)?.map_try(
			|unit| {
				tids = JsonValue.items(JsonValue.field(unit, "tokens")?)?.map_try(JsonValue.as_str)?
				found = tids.keep_oks(|tid| by_tid.get(tid))
				Ok(
					if found.len() != tids.len() or found.is_empty() {
						None
					} else {
						Some(
							{
								id: text(unit, "ref")?,
								label: text(unit, "label")?,
								text: Str.join_with(found.map(|token| if (token.space_after) "${token.form} " else token.form), "").trim_end(),
								literal: text(unit, "literal")?,
								prose: text(unit, "prose")?,
								tokens: found,
							},
						)
					},
				)
			},
		).map_ok(|found| found.keep_oks(|passage| match passage {
			Some(p) => Ok(p)
			None => Err({})
		}))
	}
}

## The visible tokens of a CoNLL-U corpus, sentence by sentence. Multiword and
## empty-node rows are skipped, and OGA placeholder rows (elided or implied
## words, MISC starting `e_`) are left out, with spacing computed as if they
## were absent.
tokens : Str -> List(Corpus.Token)
tokens = |conllu| {
	sentences = conllu
		.replace_each("\r\n", "\n")
		.replace_each("\r", "\n")
		.split_on("\n")
		.fold(
			{ done: [], rows: [] },
			|state, line| {
				if line == "" {
					{ done: state.done.append(state.rows), rows: [] }
				} else if line.starts_with("#") {
					state
				} else {
					match line.split_on("\t") {
						[id, form, lemma, upos, _, _, _, _, _, misc] if is_number(id) and !misc.starts_with("e_") =>
							{ ..state, rows: state.rows.append({ form: field(form), lemma: field(lemma), upos, misc }) }
						_ => state
					}
				}
			},
		)
	sentences.done.append(sentences.rows).join_map(
		|rows| rows.map_with_index(
			|row, index| {
				fields = misc_fields(row.misc)
				next_is_punctuation = match rows.get(index + 1) {
					Ok(next) => next.upos == "PUNCT"
					Err(_) => Bool.False
				}
				{
					# OGA keys each token by `t_N` in the first MISC field; passages refer to it.
					tid: match row.misc.split_on("|") {
						[first, ..] if first.starts_with("t_") => first
						_ => ""
					},
					form: row.form,
					lemma: row.lemma,
					gloss: if row.upos == "PUNCT" "" else match fields.get("Gloss") {
						Ok(gloss) => gloss
						Err(_) => fields.get("gloss").ok_or("")
					},
					space_after: fields.get("SpaceAfter") != Ok("No") and !next_is_punctuation,
				}
			},
		),
	)
}

misc_fields : Str -> Dict(Str, Str)
misc_fields = |misc|
	if misc == "" or misc == "_" {
		Dict.empty()
	} else {
		misc.split_on("|").fold(
			Dict.empty(),
			|found, item| match item.split_on("=") {
				[key, .. as values] => found.insert(key, Str.join_with(values, "="))
				[] => found
			},
		)
	}

is_number : Str -> Bool
is_number = |id| id != "" and id.to_utf8().all(|byte| byte >= '0' and byte <= '9')

field : Str -> Str
field = |value| if value == "_" "" else value

text : JsonValue, Str -> Try(Str, Str)
text = |json, name| JsonValue.as_str(JsonValue.field(json, name)?)

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
