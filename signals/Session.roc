import fsrs.Fsrs
import fsrs.FsrsMath
import json.JsonValue
import study.Corpus
import study.Review
import study.Study
import Store

## The review screen's state and every transition over it, in pure Roc; the
## view and effect sites are in ReviewApp.
##
## A session reviews one work (`#/<work>` in the URL) through today's queue,
## as the Elm app's study session does: its due passages, most overdue first,
## then new ones up to the daily limit. Each passage is answered (a gloss under
## every word), submitted, marked against the reference, and rated; the rating
## schedules it with FSRS and saves the attempt and card where the Elm app
## keeps them.
##
## Storage requests leave through `outbox` (see Store) and their results come
## back through `receive`. They carry the only wall clock the app has, so a
## rating first asks for the passage's stored card and is scheduled when that
## answer arrives, at its time, and a timer asks again every 15 seconds.
## Workaround: roc-signals 0.3.0 gives apps no clock
## (https://github.com/thebrandonlucas/roc-issues/tree/master/roc-signals/RS-001-wall-clock-time);
## take the time from the platform once it does.
Session := [].{

	Phase : [Loading, Choosing, Answering, Grading, Done, Failed(Str)]

	Draft : { glosses : Dict(U64, Str), submitted : Bool, marks : Dict(Str, Bool), started_at : I64 }

	Model : {
		work : Str,
		works : List(Corpus.Work),
		manifest_loaded : Bool,
		conllu : [Some(Str), None],
		units : [Some(Str), None],
		passages : List(Corpus.Passage),
		entries : Dict(Str, Review.Entry),
		attempts : List(Study.Attempt),
		progress_loaded : Bool,
		settings_loaded : Bool,
		new_per_day : I64,
		dark : Bool,
		clock : I64,
		current : Str,
		opened : Bool,
		draft : Draft,
		rating : [Some(Fsrs.Rating), None],
		outbox : Str,
		serial : U64,
		problem : Str,
		notice : Str,
	}

	## One word of the current passage as the view shows it: the Greek with the
	## punctuation that follows it, the learner's gloss, the reference gloss and
	## the learner's mark (`right`, `wrong` or empty).
	Word : { key : Str, number : U64, greek : Str, form : Str, guess : Str, reference : Str, mark : Str }

	## The session for the URL `location` (path, query and hash), asking storage
	## for the progress store and the settings the screen uses.
	init : Str -> Model
	init = |location| {
		model = {
			work: work_of(location),
			works: [],
			manifest_loaded: Bool.False,
			conllu: None,
			units: None,
			passages: [],
			entries: Dict.empty(),
			attempts: [],
			progress_loaded: Bool.False,
			settings_loaded: Bool.False,
			new_per_day: Review.new_per_day_default,
			dark: Bool.True,
			clock: 0,
			current: "",
			opened: Bool.False,
			draft: empty_draft,
			rating: None,
			outbox: "",
			serial: 1,
			problem: "",
			notice: "",
		}
		send(
			model,
			[
				("progress", |id| Store.get_all(id, "progress")),
				("settings", |id| Store.get(id, "metadata", "review-settings")),
				("theme", |id| Store.get(id, "metadata", "theme")),
			],
		)
	}

	## The work a location names: `#/<work>`, or "" for the list of works.
	work_of : Str -> Str
	work_of = |location|
		match location.split_first("#/") {
			Ok({ after, .. }) => match after.split_on("/") {
				[work, ..] => match work.split_on("?") {
					[id, ..] => id
					[] => ""
				}
				[] => ""
			}
			Err(_) => ""
		}

	phase : Model -> Phase
	phase = |model| {
		ready = model.manifest_loaded and model.progress_loaded and model.settings_loaded and !model.passages.is_empty()
		if model.problem != "" {
			Failed(model.problem)
		} else if model.work == "" {
			if (model.manifest_loaded) Choosing else Loading
		} else if !ready {
			Loading
		} else if model.current == "" {
			Done
		} else if model.draft.submitted {
			Grading
		} else {
			Answering
		}
	}

	## The view's name for a phase, the cases of its `switch`.
	phase_name : Model -> Str
	phase_name = |model|
		match phase(model) {
			Loading => "loading"
			Choosing => "choosing"
			Answering => "answering"
			Grading => "grading"
			Done => "done"
			Failed(_) => "failed"
		}

	# LOADING

	## The preload files the work needs, once the manifest names them.
	corpus_url : Model -> Str
	corpus_url = |model| work_path(model, |work| work.path)

	units_url : Model -> Str
	units_url = |model| work_path(model, |work| work.units_path)

	receive_manifest : Model, Try(Str, _) -> Model
	receive_manifest = |model, result|
		match result {
			Ok(manifest) => match Corpus.works(manifest) {
				Ok(works) => {
					known = model.work == "" or works.any(|work| work.id == model.work)
					settle({ ..model, works, manifest_loaded: Bool.True, problem: if (known) model.problem else "This preload has no work “${model.work}”." })
				}
				Err(problem) => { ..model, problem: "The preload manifest could not be read: ${problem}" }
			}
			Err(_) => { ..model, problem: "The preload manifest could not be downloaded. Reload to try again." }
		}

	receive_corpus : Model, Str, Try(Str, _) -> Model
	receive_corpus = |model, url, result|
		if url != corpus_url(model) {
			model
		} else {
			match result {
				Ok(text) => parse_passages({ ..model, conllu: Some(text) })
				Err(_) => { ..model, problem: "${title(model)} could not be downloaded. Reload to try again." }
			}
		}

	receive_units : Model, Str, Try(Str, _) -> Model
	receive_units = |model, url, result|
		if url != units_url(model) {
			model
		} else {
			match result {
				Ok(text) => parse_passages({ ..model, units: Some(text) })
				Err(_) => { ..model, problem: "${title(model)} could not be downloaded. Reload to try again." }
			}
		}

	## A storage result, routed by the purpose its id starts with.
	receive : Model, Str -> Model
	receive = |model, payload|
		match Store.response(payload) {
			Err(problem) => { ..model, notice: "Storage answered something unexpected: ${problem}" }
			Ok(response) => {
				timed = { ..model, clock: response.now }
				purpose = match response.id.split_first(":") {
					Ok({ before, .. }) => before
					Err(_) => response.id
				}
				if !response.ok {
					when_failed(timed, purpose)
				} else {
					match purpose {
						"progress" => settle(receive_progress(timed, response.value))
						"settings" => settle(receive_settings(timed, response.value))
						"theme" => receive_theme(timed, response.value)
						"rating" => finish_rating(timed)
						_ => timed
					}
				}
			}
		}

	## Asks storage for the time again (the review settings, which the Elm app
	## may have changed meanwhile), so intervals and due cards follow the clock.
	refresh_clock : Model -> Model
	refresh_clock = |model| send(model, [("settings", |id| Store.get(id, "metadata", "review-settings"))])

	# ANSWERING AND GRADING

	set_gloss : Model, U64, Str -> Model
	set_gloss = |model, number, gloss| {
		draft = model.draft
		started_at = if (draft.started_at == 0) model.clock else draft.started_at
		{ ..model, draft: { ..draft, glosses: draft.glosses.insert(number, gloss), started_at } }
	}

	submit : Model -> Model
	submit = |model| {
		draft = model.draft
		{ ..model, draft: { ..draft, submitted: Bool.True } }
	}

	## Back to answering; the marks are cleared, as the Elm app's "Keep working" does.
	reopen : Model -> Model
	reopen = |model| {
		draft = model.draft
		{ ..model, draft: { ..draft, submitted: Bool.False, marks: Dict.empty() } }
	}

	## Marking an item the way it is already marked unmarks it.
	mark : Model, Str, Bool -> Model
	mark = |model, key, right| {
		draft = model.draft
		marks = if draft.marks.get(key) == Ok(right) draft.marks.remove(key) else draft.marks.insert(key, right)
		{ ..model, draft: { ..draft, marks } }
	}

	## Rate the current passage. The rating is scheduled when storage answers
	## with the time (see `finish_rating`); further ratings wait for it.
	rate : Model, Fsrs.Rating -> Model
	rate = |model, rating|
		if model.rating != None or model.current == "" {
			model
		} else {
			key = Review.entry_key(model.work, model.current)
			send({ ..model, rating: Some(rating) }, [("rating", |id| Store.get(id, "progress", key))])
		}

	## Today's queue again, from the done panel ("Review now").
	restart : Model -> Model
	restart = |model| open_next(model)

	## The theme the Elm app also uses, saved where it keeps it.
	toggle_theme : Model -> Model
	toggle_theme = |model| {
		dark = !model.dark
		send({ ..model, dark }, [("save", |id| Store.put(id, "metadata", Store.setting("theme", JsonValue.str(if (dark) "dark" else "light"))))])
	}

	## The work a new location names; its passages load afresh.
	navigate : Model, Str -> Model
	navigate = |model, location| {
		work = work_of(location)
		if work == model.work {
			model
		} else {
			known = work == "" or !model.manifest_loaded or model.works.any(|found| found.id == work)
			{
				..model,
				work,
				conllu: None,
				units: None,
				passages: [],
				current: "",
				opened: Bool.False,
				draft: empty_draft,
				rating: None,
				problem: if (known) "" else "This preload has no work “${work}”.",
			}
		}
	}

	# VIEW DATA

	title : Model -> Str
	title = |model|
		match model.works.find_first(|work| work.id == model.work) {
			Ok(work) => work.title
			Err(_) => model.work
		}

	edition : Model -> Str
	edition = |model|
		match model.works.find_first(|work| work.id == model.work) {
			Ok(work) => work.edition
			Err(_) => ""
		}

	passage : Model -> [Some(Corpus.Passage), None]
	passage = |model|
		match model.passages.find_first(|found| found.id == model.current) {
			Ok(found) => Some(found)
			Err(_) => None
		}

	passage_label : Model -> Str
	passage_label = |model|
		match passage(model) {
			Some(found) => found.label
			None => ""
		}

	## The current passage's words, each with the punctuation that follows it.
	words : Model -> List(Word)
	words = |model|
		match passage(model) {
			None => []
			Some(found) => found.tokens.fold_with_index(
				[],
				|grouped, token, index| {
					number = index + 1
					if Study.is_word_token(token.form) {
						key = Study.word_key(number)
						grouped.append(
							{
								key,
								number,
								greek: token.form,
								form: token.form,
								guess: model.draft.glosses.get(number).ok_or(""),
								reference: token.gloss,
								mark: match model.draft.marks.get(key) {
									Ok(Bool.True) => "right"
									Ok(Bool.False) => "wrong"
									Err(_) => ""
								},
							},
						)
					} else {
						match grouped.last() {
							Ok(word) => grouped.drop_last(1).append({ ..word, greek: "${word.greek}${token.form}" })
							Err(_) => grouped
						}
					}
				},
			)
		}

	## The items an attempt at the current passage records: one per word.
	items : Model -> List(Study.Item)
	items = |model|
		words(model).map(
			|word| {
				key: word.key,
				kind: WordItem,
				form: word.form,
				lemma: lemma_of(model, word.number),
				guess: word.guess,
				reference: word.reference,
				revealed_early: Bool.False,
				mark: match word.mark {
					"right" => Some(Bool.True)
					"wrong" => Some(Bool.False)
					_ => None
				},
			},
		)

	queue : Model -> Review.Queue
	queue = |model| Review.queue(model.clock, model.new_per_day, model.work, model.passages.map(|found| found.id), model.entries)

	## "Review" or "New", for the current passage.
	queue_kind : Model -> Str
	queue_kind = |model| if queue(model).due.contains(model.current) "Review" else "New"

	queue_left : Model -> Str
	queue_left = |model| {
		today = queue(model)
		"${(today.due.len() + today.new.len()).to_str()} left today"
	}

	marked_count : Model -> Str
	marked_count = |model| {
		found = words(model)
		"${found.count_if(|word| word.mark != "").to_str()} of ${found.len().to_str()} marked"
	}

	suggested : Model -> Fsrs.Rating
	suggested = |model| Review.suggest_rating(items(model))

	## When the current passage would come back with `rating`, at the session's clock.
	interval : Model, Fsrs.Rating -> Str
	interval = |model, rating|
		match Review.preview(model.clock, model.work, model.current, model.entries) {
			Ok(outcomes) => {
				outcome = match rating {
					Again => outcomes.again
					Hard => outcomes.hard
					Good => outcomes.good
					Easy => outcomes.easy
				}
				Review.interval_label(model.clock, outcome.card.due)
			}
			Err(_) => ""
		}

	## The done panel's summary of today's attempts at this work.
	done_summary : Model -> Str
	done_summary = |model| {
		today = model.attempts.keep_if(|attempt| attempt.work == model.work and attempt.finished_at >= Review.start_of_day(model.clock))
		tally = Study.marked(today)
		graded = "${today.len().to_str()}${plural(today.len(), " passage", " passages")} graded today"
		if tally.judged > 0 "${graded}, ${percent(tally.right, tally.judged)} of marked answers right." else "${graded}."
	}

	due_now : Model -> U64
	due_now = |model| queue(model).due.len()

	done_next : Model -> Str
	done_next = |model| {
		due = due_now(model)
		limit = "New passages: up to ${model.new_per_day.to_str()} a day."
		match (due, Review.due_later(model.clock, model.work, model.entries)) {
			(0, Some(time)) => "Next review due in ${Review.interval_label(model.clock, time)}. ${limit}"
			(0, None) => "No reviews scheduled yet. ${limit}"
			_ => "${due.to_str()}${plural(due, " review is", " reviews are")} due now."
		}
	}

	display_gloss : Str -> Str
	display_gloss = |gloss| if gloss == "" "—" else gloss.replace_each("-", " ")
}

empty_draft : Session.Draft
empty_draft = { glosses: Dict.empty(), submitted: Bool.False, marks: Dict.empty(), started_at: 0 }

## Issue storage requests as one batch, numbering their ids `<purpose>:<n>`.
## A transition calls this at most once: a later batch replaces the outbox.
send : Session.Model, List((Str, (Str -> JsonValue))) -> Session.Model
send = |model, requests| {
	messages = requests.map_with_index(|(purpose, build), index| build("${purpose}:${(model.serial + index).to_str()}"))
	{ ..model, outbox: Store.batch(messages), serial: model.serial + requests.len() }
}

work_path : Session.Model, (Corpus.Work -> Str) -> Str
work_path = |model, path_of|
	match model.works.find_first(|work| work.id == model.work) {
		Ok(work) => "/preload/${path_of(work)}"
		Err(_) => ""
	}

parse_passages : Session.Model -> Session.Model
parse_passages = |model|
	match (model.conllu, model.units) {
		(Some(conllu), Some(units)) => match Corpus.passages(conllu, units) {
			Ok([]) => { ..model, problem: "${Session.title(model)} has no passages." }
			Ok(passages) => settle({ ..model, passages, conllu: None, units: None })
			Err(problem) => { ..model, problem: "${Session.title(model)} could not be read: ${problem}" }
		}
		_ => model
	}

## The progress store holds both finished attempts and review cards; the cards
## are replayed from the attempts as the Elm app does (`Review.cards`).
receive_progress : Session.Model, JsonValue -> Session.Model
receive_progress = |model, value| {
	records = JsonValue.items(value) ?? []
	attempts = records.keep_oks(Study.decode_attempt)
	stored = Dict.from_list(records.keep_oks(Review.decode_entry).map(|entry| (Review.entry_key(entry.work, entry.passage), entry)))
	{ ..model, attempts, entries: Review.cards(stored, attempts), progress_loaded: Bool.True }
}

## `{"key": "review-settings", "value": {"newPerDay": n}}`, or null before the
## learner changed it.
receive_settings : Session.Model, JsonValue -> Session.Model
receive_settings = |model, value| {
	new_per_day = match JsonValue.field(value, "value") {
		Ok(settings) => match JsonValue.field(settings, "newPerDay") {
			Ok(n) => JsonValue.as_i64(n) ?? model.new_per_day
			Err(_) => model.new_per_day
		}
		Err(_) => model.new_per_day
	}
	{ ..model, new_per_day, settings_loaded: Bool.True }
}

receive_theme : Session.Model, JsonValue -> Session.Model
receive_theme = |model, value|
	match JsonValue.field(value, "value") {
		Ok(theme) => match JsonValue.as_str(theme) {
			Ok("light") => { ..model, dark: Bool.False }
			Ok("dark") => { ..model, dark: Bool.True }
			_ => model
		}
		Err(_) => model
	}

## A failed read leaves the default in place; a failed rating can be retried.
when_failed : Session.Model, Str -> Session.Model
when_failed = |model, purpose|
	match purpose {
		"progress" => { ..model, problem: "Your progress could not be read from this browser's storage." }
		"settings" => settle({ ..model, settings_loaded: Bool.True })
		"rating" => { ..model, rating: None, notice: "The rating could not be saved. Try again." }
		"save" => { ..model, notice: "Something could not be saved in this browser's storage." }
		_ => model
	}

## Opens the first passage of today's queue once everything has loaded.
settle : Session.Model -> Session.Model
settle = |model| {
	ready = model.manifest_loaded and model.progress_loaded and model.settings_loaded and !model.passages.is_empty()
	if !ready or model.opened or model.problem != "" model else open_next(model)
}

## The first passage of today's queue at the clock, or none (the done panel).
open_next : Session.Model -> Session.Model
open_next = |model| {
	today = Session.queue(model)
	{ ..model, current: today.due.concat(today.new).first() ?? "", draft: empty_draft, opened: Bool.True }
}

## Schedule the pending rating at the clock storage just reported, record the
## attempt and card as the Elm app does (and clear its draft of the passage),
## then open the next passage in today's queue.
finish_rating : Session.Model -> Session.Model
finish_rating = |model|
	match (model.rating, Session.passage(model)) {
		(Some(rating), Some(current)) => {
			now = model.clock
			attempt = {
				id: "attempt:${model.work}:${current.id}:${now.to_str()}",
				work: model.work,
				passage: current.id,
				sentence_id: current.id,
				sentence_text: current.text,
				started_at: if (model.draft.started_at == 0) now else model.draft.started_at,
				finished_at: now,
				items: Session.items(model),
				rating: Some(rating),
			}
			match Review.schedule(now, rating, model.work, current.id, model.entries) {
				Ok(entry) => {
					recorded = {
						..model,
						attempts: model.attempts.prepend(attempt),
						entries: model.entries.insert(Review.entry_key(model.work, current.id), entry),
						rating: None,
						current: "",
						notice: "",
					}
					saved = send(
						recorded,
						[
							("save", |id| Store.put(id, "progress", Study.encode_attempt(attempt))),
							("save", |id| Store.put(id, "progress", Review.encode_entry(entry))),
							("save", |id| Store.put(id, "metadata", Store.setting("draft:${model.work}:${current.id}", Study.empty_draft))),
						],
					)
					open_next(saved)
				}
				Err(problem) => { ..model, rating: None, notice: "The passage could not be scheduled: ${problem}" }
			}
		}
		_ => { ..model, rating: None }
	}

lemma_of : Session.Model, U64 -> Str
lemma_of = |model, number|
	match Session.passage(model) {
		Some(found) => match found.tokens.get(number - 1) {
			Ok(token) => token.lemma
			Err(_) => ""
		}
		None => ""
	}

plural : U64, Str, Str -> Str
plural = |count, one, many| if count == 1 one else many

percent : U64, U64 -> Str
percent = |part, whole| if whole == 0 "—" else "${FsrsMath.to_js_str(FsrsMath.round(part.to_f64() * 100.0 / whole.to_f64()))}%"
