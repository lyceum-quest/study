app [main!] {
	fsrs: "../packages/fsrs/main.roc",
	json: "../packages/json/main.roc",
	study: "../packages/study/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.Path
import pf.Stdout
import json.JsonValue
import study.Corpus
import study.Study
import study.Tools

# The corpus parser, citation helpers and study records (packages/study/
# Corpus.roc, Study.roc, Tools.roc) against small literal inputs, with
# expectations read from src/Conllu.elm, src/Passage.elm, src/Study.elm and
# src/Main.elm; then every work of preload/corpora.json, whose counts must
# match the manifest's. Prints a summary and the failures, and exits with 1 if
# any check fails.
main! = |_args| {
	preload = preload_checks!({})
	groups = [
		("CoNLL-U parsing", parsing),
		("passages", passage_checks),
		("manifest", manifest_checks),
		("citation helpers", citation_checks),
		("drafts and attempts", study_checks),
		("study tools", tools_checks),
		("preload works", preload),
	]
	var $failures = []
	for (title, checks) in groups {
		failed = checks.keep_if(|check| check.problem != "")
		Stdout.line!("${(checks.len() - failed.len()).to_str()}/${checks.len().to_str()} ${title}")?
		$failures = $failures.concat(failed)
	}
	if $failures.is_empty() {
		Stdout.line!("All corpus checks pass.")?
		Ok({})
	} else {
		for check in $failures {
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

source : Corpus.Source
source = { name: "OGA", url: "u", commit: "c", license: "l", edition: "e" }

# Four sentences: a cited one with a multiword row, an empty node, a
# placeholder, punctuation and a signed head; one cited by its first row's
# `Ref`, with `text` metadata containing `=`; one whose `sent_id` carried over
# from a sentence without word rows (CRLF line endings); and one without
# metadata.
conllu_lf : Str
conllu_lf =
	\\# sent_id = s1
	\\# citation = urn:cts:greekLit:tlg0031.tlg003:3.1
	\\# newdoc
	\\# text_en = In the beginning
	\\1-2	Ἐνἀρχῇ	_	_	_	_	_	_	_	_
	\\1	Ἐν	ἐν	ADP	_	_	+2	case	_	t_1|Gloss=in
	\\2	ἀρχῇ	ἀρχή	NOUN	_	Case=Dat|Gender=Fem|Number=Sing	0	root	_	t_2|Gloss=beginning
	\\2.1	ἦν	_	_	_	_	_	_	_	_
	\\3	[0]	εἰμί	VERB	_	_	2	cop	_	e_1
	\\4	,	,	PUNCT	_	_	2	punct	_	t_3|Gloss=comma
	\\5	ἦν	εἰμί	VERB	_	Mood=Ind|Number=Sing	_	_	_	t_4|gloss=was|SpaceAfter=No
	\\
	\\# sentence_id = 7
	\\# citation = urn:x:4.2
	\\# text = Custom text = with equals
	\\# literal_translation = lit
	\\1	λόγος	λόγος	NOUN	_	_	-1	nsubj	_	t_5|Ref=4.3|Gloss=a=b
	\\2	.	.	PUNCT	_	_	1	punct	_	t_6
	\\
	\\# sent_id = carried
	\\
	\\# text_en = second
	\\1	καί	καί	CCONJ	_	_	0	root	_	t_9
	\\
	\\1	τέλος	_	NOUN	_	_	0	root	_	_
	\\

conllu : Str
conllu = conllu_lf.replace_each("# sent_id = carried\n\n", "# sent_id = carried\r\n\r\n")

no_morphology : Corpus.Morphology
no_morphology = { summary: "", case: "", number: "", gender: "" }

token : U64, Str, Str, Str, Str -> Corpus.Token
token = |id, tid, form, lemma, upos| { id, tid, form, lemma, upos, morphology: no_morphology, head: 0, relation: "", gloss: "", space_after: Bool.True }

en : Corpus.Token
en = { ..token(1, "t_1", "Ἐν", "ἐν", "ADP"), head: 2, relation: "case", gloss: "in" }

arche : Corpus.Token
arche = {
	..token(2, "t_2", "ἀρχῇ", "ἀρχή", "NOUN"),
	morphology: { summary: "Case=Dat|Gender=Fem|Number=Sing", case: "Dat", number: "Sing", gender: "Fem" },
	relation: "root",
	gloss: "beginning",
	# The next visible token is punctuation; the placeholder between is ignored.
	space_after: Bool.False,
}

comma : Corpus.Token
comma = { ..token(4, "t_3", ",", ",", "PUNCT"), head: 2, relation: "punct" }

en_ : Corpus.Token
en_ = { ..token(5, "t_4", "ἦν", "εἰμί", "VERB"), morphology: { summary: "Mood=Ind|Number=Sing", case: "", number: "Sing", gender: "" }, gloss: "was", space_after: Bool.False }

logos : Corpus.Token
logos = { ..token(1, "t_5", "λόγος", "λόγος", "NOUN"), head: -1, relation: "nsubj", gloss: "a=b", space_after: Bool.False }

stop : Corpus.Token
stop = { ..token(2, "t_6", ".", ".", "PUNCT"), head: 1, relation: "punct" }

kai : Corpus.Token
kai = { ..token(1, "t_9", "καί", "καί", "CCONJ"), relation: "root" }

telos : Corpus.Token
telos = { ..token(1, "", "τέλος", "", "NOUN"), relation: "root" }

sentences : List(Corpus.Passage)
sentences = [
	{
		id: "s1",
		label: "3.1",
		chapter: 3,
		text: "Ἐν ἀρχῇ, ἦν",
		literal: "",
		prose: "In the beginning",
		tokens: [en, arche, comma, en_],
		placeholders: [{ ..token(3, "", "[0]", "εἰμί", "VERB"), head: 2, relation: "cop" }],
	},
	{ id: "urn:x:4.2-s7", label: "4.3", chapter: 4, text: "Custom text = with equals", literal: "lit", prose: "", tokens: [logos, stop], placeholders: [] },
	{ id: "carried", label: "carried", chapter: 1, text: "καί", literal: "", prose: "second", tokens: [kai], placeholders: [] },
	{ id: "sentence-4", label: "", chapter: 1, text: "τέλος", literal: "", prose: "", tokens: [telos], placeholders: [] },
]

parsing : List(Check)
parsing = [
	expect_equal("sentences, tokens and placeholders", Corpus.parse(source, conllu), Ok({ source, sentences })),
	expect_equal("a row without 10 columns", Corpus.parse(source, "1\tx\tx\tX\t_\t_\t0\troot\t_"), Err("Invalid CoNLL-U row: expected 10 tab-separated columns")),
	expect_equal("a multiword row without 10 columns", Corpus.parse(source, "1-2\tx\t_\t_\t_\t_\t_\t_\t_\n1\tx\tx\tX\t_\t_\t0\troot\t_\t_"), Err("Invalid CoNLL-U row: expected 10 tab-separated columns")),
	expect_equal("an invalid head", Corpus.parse(source, "1\tx\tx\tX\t_\t_\t0\troot\t_\t_\n2\ty\ty\tY\t_\t_\t1x\tdep\t_\t_"), Err("Token 2 has an invalid dependency head")),
	expect_equal("a sign alone is no head", Corpus.parse(source, "1\tx\tx\tX\t_\t_\t-\troot\t_\t_"), Err("Token 1 has an invalid dependency head")),
	expect_equal("only metadata", Corpus.parse(source, "# sent_id = 1\n# text = x\n\n"), Err("Corpus contains no sentences")),
	expect_equal("only skipped rows", Corpus.parse(source, "1-2\tx\t_\t_\t_\t_\t_\t_\t_\t_\n"), Err("Corpus contains no sentences")),
	expect_equal(
		"a sentence number is not a citation",
		Corpus.parse(source, "# sent_id = 12\n1\tx\tx\tX\t_\t_\t0\troot\t_\t_").map_ok(|parsed| parsed.sentences.map(|s| (s.id, s.label, s.chapter))),
		Ok([("12", "12", 1)]),
	),
	expect_equal(
		"a chapter is the first digits of the last `:` level",
		Corpus.parse(source, "# citation = a:b:ch12v3\n1\tx\tx\tX\t_\t_\t0\troot\t_\t_").map_ok(|parsed| parsed.sentences.map(|s| (s.id, s.label, s.chapter))),
		Ok([("sentence-1", "ch12v3", 12)]),
	),
]

units : Str
units =
	\\[
	\\  {"ref": "3.1", "label": "3:1", "tokens": ["t_1", "t_2", "t_3"], "prose": "P", "literal": "L", "extra": 1},
	\\  {"ref": "3.2~1", "label": "3:2 §1", "tokens": ["t_4", "t_5", "t_6"], "prose": "", "literal": ""},
	\\  {"ref": "x", "label": "x", "tokens": ["t_1", "t_404"], "prose": "", "literal": ""},
	\\  {"ref": "y", "label": "y", "tokens": [], "prose": "", "literal": ""},
	\\  {"ref": "abc", "label": "abc", "tokens": ["t_9"], "prose": "", "literal": ""}
	\\]

passages : List(Corpus.Passage)
passages = [
	{ id: "3.1", label: "3:1", chapter: 3, text: "Ἐν ἀρχῇ,", literal: "L", prose: "P", tokens: [en, arche, { ..comma, id: 3 }], placeholders: [] },
	# Tokens of two sentences, renumbered.
	{ id: "3.2~1", label: "3:2 §1", chapter: 3, text: "ἦνλόγος.", literal: "", prose: "", tokens: [{ ..en_, id: 1 }, { ..logos, id: 2 }, { ..stop, id: 3 }], placeholders: [] },
	{ id: "abc", label: "abc", chapter: 1, text: "καί", literal: "", prose: "", tokens: [kai], placeholders: [] },
]

work : Corpus.Work
work = {
	id: "w",
	title: "W",
	path: "corpora/w.conllu",
	sentence_count: 4,
	token_count: 8,
	source,
	citation: None,
	units_path: "corpora/w.units.json",
	passages: ["3.1", "3.2~1", "abc"],
	edition: "e",
}

passage_checks : List(Check)
passage_checks = [
	expect_equal("passages from units", Corpus.passages(conllu, units), Ok(passages)),
	expect_equal("a work with units", Corpus.parse_work(work, conllu, units), Ok({ source, sentences: passages })),
	expect_equal("a work without units keeps its sentences", Corpus.parse_work(work, conllu, ""), Ok({ source, sentences })),
	expect_equal("a unit without a label", Corpus.passages(conllu, "[{\"ref\": \"1\", \"tokens\": [], \"prose\": \"\", \"literal\": \"\"}]").is_err(), Bool.True),
	expect_equal("the corpus is read before the units", Corpus.passages("", "nonsense"), Err("Corpus contains no sentences")),
	expect_equal("parts", ["1.2", "43~2", "1", ""].map(Corpus.parts), [["1", "2"], ["43", "2"], ["1"], [""]]),
	expect_equal("split", (Corpus.is_split(passages), Corpus.is_split([]), Corpus.is_split(passages.drop_first(1).take_first(1))), (Bool.False, Bool.False, Bool.True)),
	expect_equal("levels", (Corpus.levels(passages), Corpus.levels([]), Corpus.levels(passages.drop_first(1))), (2, 1, 3)),
	expect_equal(
		"level names",
		[(Bool.True, Bool.False, 2), (Bool.False, Bool.False, 2), (Bool.True, Bool.False, 3), (Bool.False, Bool.False, 1), (Bool.False, Bool.False, 4), (Bool.False, Bool.True, 2), (Bool.True, Bool.True, 3), (Bool.False, Bool.True, 4), (Bool.False, Bool.True, 1)]
			.map(|(bible, split, depth)| Corpus.level_names(bible, split, depth)),
		[["Chapter", "Verse"], ["Book", "Line"], ["Book", "Chapter", "Section"], ["Part"], ["Part", "Part", "Part", "Part"], ["Page", "§"], ["Chapter", "Verse", "§"], ["Book", "Chapter", "Section", "§"], ["§"]],
	),
]

manifest : Str
manifest =
	\\{"version": 1, "lemmasPath": "lemmas.json", "corpora": [
	\\  {"id": "w", "title": "W", "path": "corpora/w.conllu", "sentenceCount": 4, "tokenCount": 8, "unitsPath": "corpora/w.units.json",
	\\   "passages": ["3.1", "3.2~1", "abc"], "source": {"name": "OGA", "url": "u", "commit": "c", "license": "l", "edition": "e"}},
	\\  {"id": "bible", "title": 7, "path": "corpora/b.conllu", "sentenceCount": "many", "passages": "none",
	\\   "source": {"name": "OGA", "url": "u", "commit": "c", "license": "l", "edition": "e"},
	\\   "citation": {"text": {"urn": "urn:cts:greekLit:tlg0031.tlg003", "author": "NT", "title": "Luke", "edition": "WH", "repository": "r", "snapshot": "s", "license": "l", "readerUrl": "ru", "sourceUrl": "su"},
	\\     "annotations": {"name": "OGA", "version": "0.2", "url": "au", "license": "al"}, "generated": {"name": "LS", "layers": "glosses", "model": "m", "license": "gl"}}}
	\\]}

bible : Corpus.Work
bible = {
	id: "bible",
	title: "bible",
	path: "corpora/b.conllu",
	sentence_count: 0,
	token_count: 0,
	source,
	citation: Some(
		{
			text: { urn: "urn:cts:greekLit:tlg0031.tlg003", author: "NT", title: "Luke", edition: "WH", repository: "r", snapshot: "s", license: "l", reader_url: "ru", source_url: "su" },
			annotations: { name: "OGA", version: "0.2", url: "au", license: "al" },
			generated: { name: "LS", layers: "glosses", model: "m", license: "gl" },
		},
	),
	units_path: "",
	passages: [],
	edition: "e",
}

manifest_checks : List(Check)
manifest_checks = [
	expect_equal("entries, with defaults for what is missing or invalid", Corpus.manifest(manifest), Ok([work, bible])),
	expect_equal("works with passages", Corpus.works(manifest), Ok([work])),
	expect_equal("another version", Corpus.manifest(manifest.replace_each("\"version\": 1", "\"version\": 2")).is_err(), Bool.True),
	expect_equal("an entry without a source", Corpus.manifest("{\"version\": 1, \"corpora\": [{\"id\": \"w\", \"path\": \"p\"}]}").is_err(), Bool.True),
]

citation_checks : List(Check)
citation_checks = [
	expect_equal("go-to box", [" 1:2 ", "43 §2", "1,,2.", "", "1.2"].map(Corpus.normalize_citation), ["1.2", "43.2", "1.2", "", "1.2"]),
	expect_equal("jump to a citation prefix", ["3", "3.2", "3.1", "4", "", "abc"].map(|prefix| Corpus.citation_index(prefix, passages)), [Some(0), Some(1), Some(0), None, None, Some(2)]),
	expect_equal("index of a ref", ["abc", "3.2", "3.1"].map(|ref| Corpus.index_of_ref(ref, passages)), [Some(2), None, Some(0)]),
	expect_equal(
		"citation labels",
		[("bible", "1.66"), ("bible", "1~2"), ("bible", "1.2~3"), ("w", "43~2"), ("w", "1.2.1"), ("w", "1~2~3"), ("unknown", "1.2")].map(|(id, ref)| Corpus.ref_label([work, bible], id, ref)),
		["1:66", "1 §2", "1:2 §3", "43 §2", "1.2.1", "1~2~3", "1.2"],
	),
	expect_equal(
		"saved positions",
		[Dict.from_list([("w", 2)]), Dict.from_list([("w", 0)]), Dict.from_list([("w", 9)]), Dict.empty()].map(|positions| Corpus.saved_ref(work, positions)),
		["3.2~1", "3.1", "3.1", "3.1"],
	),
	expect_equal("a work without passages starts at 1", Corpus.saved_ref(bible, Dict.empty()), "1"),
	expect_equal("glosses", ["", "in-the-beginning"].map(Corpus.display_gloss), ["—", "in the beginning"]),
	expect_equal("lemmas", ["λέγω3", "λέγω12", "12", "a1b2", ""].map(Corpus.display_lemma), ["λέγω", "λέγω", "12", "a1b", ""]),
	expect_equal("the passage shown", (Corpus.passage_at(passages, 2).id, Corpus.passage_at(passages, 3).id, Corpus.passage_at([], 0).text), ("abc", "missing", "No corpus loaded.")),
	expect_equal(
		"words with their punctuation",
		Study.group_words([{ ..stop, id: 0 }, en, arche, comma, stop]).map(|(word, suffix)| (word.form, suffix)),
		[("Ἐν", ""), ("ἀρχῇ", ",.")],
	),
]

# The Elm app's `Encode.encode 0 (Study.encodeDraft draft)`.
draft_json : Str
draft_json = "{\"glosses\":[[1,\"in\"],[3,\"was\"]],\"literal\":\"\",\"prose\":\"my prose\",\"revealed\":[\"literal\",\"w:2\"],\"submitted\":true,\"marks\":{\"literal\":false,\"w:1\":true},\"startedAt\":5,\"updatedAt\":9}"

draft : Study.Draft
draft = {
	glosses: Dict.from_list([(1, "in"), (3, "was")]),
	literal: "",
	prose: "my prose",
	revealed: Set.from_list(["literal", "w:2"]),
	submitted: Bool.True,
	marks: Dict.from_list([("literal", Bool.False), ("w:1", Bool.True)]),
	started_at: 5,
	updated_at: 9,
}

# The Elm app's `Encode.encode 0 (Study.encodeAttempt attempt)`.
attempt_json : Str
attempt_json = "{\"id\":\"attempt:w:3.1:100\",\"type\":\"attempt\",\"work\":\"w\",\"passage\":\"3.1\",\"sentenceId\":\"3.1\",\"sentenceText\":\"Ἐν ἀρχῇ,\",\"startedAt\":5,\"finishedAt\":100,\"items\":[{\"key\":\"w:1\",\"kind\":\"word\",\"form\":\"Ἐν\",\"lemma\":\"ἐν\",\"guess\":\"in\",\"reference\":\"in\",\"revealedEarly\":false,\"mark\":true},{\"key\":\"w:2\",\"kind\":\"word\",\"form\":\"ἀρχῇ\",\"lemma\":\"ἀρχή\",\"guess\":\"\",\"reference\":\"beginning\",\"revealedEarly\":true,\"mark\":null},{\"key\":\"prose\",\"kind\":\"prose\",\"form\":\"\",\"lemma\":\"\",\"guess\":\"my prose\",\"reference\":\"P\",\"revealedEarly\":false,\"mark\":null}],\"rating\":\"good\"}"

item : Str, Study.ItemKind, Str, [Some(Bool), None] -> Study.Item
item = |key, kind, lemma, mark| { key, kind, form: "", lemma, guess: "", reference: "", revealed_early: Bool.False, mark }

attempt_at : Str, I64, List(Study.Item) -> Study.Attempt
attempt_at = |passage, finished_at, items| { id: "attempt:w:${passage}:${finished_at.to_str()}", work: "w", passage, sentence_id: passage, sentence_text: "", started_at: 0, finished_at, items, rating: None }

study_checks : List(Check)
study_checks = {
	asked = Some(Set.from_list(["w:1"]))
	items = Study.study_items(passages.first() ?? Corpus.missing, draft, Tools.read_settings, asked)
	attempt = Study.build_attempt(100, Good, "w", passages.first() ?? Corpus.missing, draft, items)
	older = attempt_at("3.1", 50, [item("w:1", WordItem, "a", Some(Bool.False)), item("w:2", WordItem, "b", Some(Bool.True)), { ..item("w:3", WordItem, "c", Some(Bool.True)), revealed_early: Bool.True }, item("literal", LiteralItem, "", Some(Bool.False))])
	same_time = attempt_at("3.1", 50, [item("w:1", WordItem, "a", None)])
	newer = attempt_at("3.1", 80, [{ ..item("w:1", WordItem, "a", Some(Bool.False)), guess: "x" }, item("w:4", WordItem, "a", None)])
	other = attempt_at("abc", 90, [item("w:1", WordItem, "z", Some(Bool.False))])
	history = [older, same_time, other, newer]
	[
		expect_equal("a draft decodes", decode_draft(draft_json), Ok(draft)),
		expect_equal("a draft encodes as the Elm app's", JsonValue.encode(Study.encode_draft({ ..draft, glosses: Dict.from_list([(3, "was"), (1, "in")]), marks: Dict.from_list([("w:1", Bool.True), ("literal", Bool.False)]) })), draft_json),
		expect_equal(
			"the empty draft",
			JsonValue.encode(Study.encode_draft(Study.empty_draft)),
			"{\"glosses\":[],\"literal\":\"\",\"prose\":\"\",\"revealed\":[],\"submitted\":false,\"marks\":{},\"startedAt\":0,\"updatedAt\":0}",
		),
		expect_equal(
			"a draft without updatedAt",
			decode_draft("{\"glosses\":[],\"literal\":\"\",\"prose\":\"\",\"revealed\":[\"a\",\"a\"],\"submitted\":false,\"marks\":{},\"startedAt\":3}"),
			Ok({ ..Study.empty_draft, revealed: Set.from_list(["a"]), started_at: 3 }),
		),
		expect_equal("marks must be an object", decode_draft(draft_json.replace_each("{\"literal\":false,\"w:1\":true}", "[]")).is_err(), Bool.True),
		expect_equal("a gloss needs its token number", decode_draft(draft_json.replace_each("[1,\"in\"]", "[\"in\"]")).is_err(), Bool.True),
		expect_equal("the draft key", Study.draft_key("w", "3.1"), "draft:w:3.1"),
		expect_equal(
			"items: asked, revealed or marked words, then translations worked on or enabled",
			items,
			[
				{ key: "w:1", kind: WordItem, form: "Ἐν", lemma: "ἐν", guess: "in", reference: "in", revealed_early: Bool.False, mark: Some(Bool.True) },
				{ key: "w:2", kind: WordItem, form: "ἀρχῇ", lemma: "ἀρχή", guess: "", reference: "beginning", revealed_early: Bool.True, mark: None },
				{ key: "prose", kind: ProseItem, form: "", lemma: "", guess: "my prose", reference: "P", revealed_early: Bool.False, mark: None },
			],
		),
		expect_equal(
			"no items with tools off and nothing written",
			Study.study_items(passages.first() ?? Corpus.missing, Study.empty_draft, { gloss: ModuleOff, literal: ModuleOff, prose: ModuleOff }, None),
			[],
		),
		expect_equal(
			"every word and both translations when intensive",
			Study.study_items(passages.first() ?? Corpus.missing, Study.empty_draft, Tools.intensive_settings, None).map(|found| found.key),
			["w:1", "w:2", "literal", "prose"],
		),
		expect_equal("an attempt encodes as the Elm app's", JsonValue.encode(Study.encode_attempt(attempt)), attempt_json),
		expect_equal("an attempt decodes", decode_attempt(attempt_json), Ok(attempt)),
		expect_equal("an attempt without a draft start starts now", Study.build_attempt(100, Good, "w", Corpus.missing, Study.empty_draft, []).started_at, 100),
		expect_equal("words to ask again", Study.asked_words(Bool.False, Some(older)), Some(Set.from_list(["w:1", "w:3"]))),
		expect_equal("every word", (Study.asked_words(Bool.True, Some(older)), Study.asked_words(Bool.False, None)), (None, None)),
		expect_equal("asked", (Study.is_asked(asked, "w:1"), Study.is_asked(asked, "w:2"), Study.is_asked(None, "w:2")), (Bool.True, Bool.False, Bool.True)),
		expect_equal("attempts at a passage, newest first and stable", Study.passage_attempts("w", "3.1", history), [newer, older, same_time]),
		expect_equal("the last attempt", (Study.last_attempt("w", "abc", history), Study.last_attempt("w", "zz", history)), (Some(other), None)),
		expect_equal("missed last time", Study.missed_last_time("w", "3.1", history), Dict.from_list([("w:1", "x")])),
		expect_equal("a tally", Study.tally(older), { right: 2, wrong: 2, unmarked: 0 }),
		expect_equal(
			"statistics",
			Study.stats(history),
			{
				attempts: 4,
				judged: 6,
				right: 2,
				unassisted_judged: 5,
				unassisted_right: 1,
				struggles: [{ lemma: "a", wrong: 2, judged: 2 }, { lemma: "z", wrong: 1, judged: 1 }],
			},
		),
		expect_equal(
			"a draft submitted over 30 minutes ago reopens",
			(Study.resumable(9 + 1800001, draft), Study.resumable(9 + 1800000, draft)),
			({ ..draft, submitted: Bool.False, marks: Dict.empty() }, draft),
		),
	]
}

decode_draft : Str -> Try(Study.Draft, Str)
decode_draft = |text| Study.decode_draft(JsonValue.decode(text)?)

decode_attempt : Str -> Try(Study.Attempt, Str)
decode_attempt = |text| Study.decode_attempt(JsonValue.decode(text)?)

tools_checks : List(Check)
tools_checks = [
	expect_equal("presets", [ReadPreset, AssistedPreset, IntensivePreset, CustomPreset].map(|preset| Tools.enabled_modules(Tools.settings_for_preset(preset, Tools.read_settings))), [[GlossModule], [GlossModule, ProseModule], [GlossModule, LiteralModule, ProseModule], [GlossModule]]),
	expect_equal("set a module", Tools.set_module_mode(LiteralModule, OnDemand, Tools.read_settings), { gloss: OnDemand, literal: OnDemand, prose: ModuleOff }),
	expect_equal("module keys", ["gloss", "literal", "prose", "x"].map(Tools.module_from_key), [Some(GlossModule), Some(LiteralModule), Some(ProseModule), None]),
	expect_equal("module names", [GlossModule, LiteralModule, ProseModule].map(|module_id| "${Tools.module_key(module_id)}=${Tools.module_name(module_id)}"), ["gloss=Glosses", "literal=Literal translation", "prose=Prose translation"]),
]

# Every work of the preload parses, with the manifest's counts: its passages,
# OGA sentences, and visible tokens.
preload_checks! : {} => List(Check)
preload_checks! = |{}| {
	match read!("preload/corpora.json") {
		Err(problem) => [{ name: "the manifest", problem }]
		Ok(manifest_json) =>
			match Corpus.manifest(manifest_json) {
				Err(problem) => [{ name: "the manifest", problem }]
				Ok(entries) => {
					var $checks = []
					for entry in entries {
						passage_count = passage_count_of(manifest_json, entry.id) ?? -1
						check = match (read!("preload/${entry.path}"), read!("preload/${entry.units_path}")) {
							(Ok(raw), Ok(units_json)) =>
								match (Corpus.parse(entry.source, raw), Corpus.parse_work(entry, raw, units_json)) {
									(Ok(parsed), Ok(regrouped)) =>
										expect_equal(
											"${entry.id} counts",
											(regrouped.sentences.len().to_i64_wrap(), parsed.sentences.len().to_i64_wrap(), parsed.sentences.map(|s| s.tokens.len()).sum().to_i64_wrap(), regrouped.sentences.map(|passage| passage.id)),
											(passage_count, entry.sentence_count, entry.token_count, entry.passages),
										)
									(Err(problem), _) | (_, Err(problem)) => { name: entry.id, problem }
								}
							_ => { name: entry.id, problem: "cannot read its files" }
						}
						$checks = $checks.append(check)
					}
					$checks
				}
			}
	}
}

# The manifest's `passageCount` for a work, which `Corpus.Work` leaves out.
passage_count_of : Str, Str -> Try(I64, Str)
passage_count_of = |manifest_json, id| {
	corpora = JsonValue.items(JsonValue.field(JsonValue.decode(manifest_json)?, "corpora")?)?
	entry = corpora.find_first(|json| (JsonValue.field(json, "id") ?? JsonValue.null).as_str() == Ok(id)).map_err(|_| "no work ${id}")?
	JsonValue.as_i64(JsonValue.field(entry, "passageCount")?)
}

read! : Str => Try(Str, Str)
read! = |path| Path.read_utf8!(Path.utf8(path)).map_err(|_| "cannot read ${path}")
