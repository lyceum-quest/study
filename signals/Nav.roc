import fsrs.Fsrs
import json.JsonValue
import study.Changelog
import study.Corpus
import study.Review
import study.Route
import study.Study
import study.Today
import study.Tools
import study.Words
import Model
import Store
import Workspace

## Routes, loading the library and works, and the transitions that open
## another page, ported from `applyRoute`, `showRoute`, `requestWork`,
## `handleManifest`, `handleFetchedCorpus`, `goToday` and the rating branches
## of `src/Main.elm`.
##
## As in the Elm app, the URL follows the model (see Update). Opening a URL
## (`go`) applies its route at once, as the Elm app's `pushUrl` and the
## `UrlChanged` that follows it do.
Nav := [].{

	## The app at the URL `location`, asking storage for what the Elm app reads at start.
	init : Str -> Model.Model
	init = |location| {
		model = Model.send(
			Model.empty(location),
			[
				("theme", |id| Store.get(id, "metadata", "theme")),
				("reader-layers", |id| Store.get(id, "metadata", "reader-layers")),
				("positions", |id| Store.get(id, "metadata", "positions")),
				("settings", |id| Store.get(id, "metadata", "review-settings")),
				("scope", |id| Store.get(id, "metadata", "today-scope")),
				("progress", |id| Store.get_all(id, "progress")),
				("cached-corpus", |id| Store.get(id, "metadata", "cached-corpus")),
			],
		)
		apply_route(model, route_of(location))
	}

	## The browser moved to `location` (back, forward, a link).
	location_changed : Model.Model, Str -> Model.Model
	location_changed = |model, location| {
		path = Model.url_path(location)
		if path == model.current_path {
			model
		} else {
			apply_route({ ..model, current_path: path, query: Route.query(location) }, route_of(location))
		}
	}

	## Opens `path` (`#/…`) as a new history entry.
	go : Model.Model, Str -> Model.Model
	go = |model, path| {
		opened = location_changed(model, path)
		url = opened.url
		{ ..opened, current_path: path, url: { path, push: Bool.True, serial: url.serial + 1 } }
	}

	go_route : Model.Model, Route.Route -> Model.Model
	go_route = |model, route| go(model, Route.to_path(route))

	apply_route : Model.Model, Route.Route -> Model.Model
	apply_route = |model, route|
		match route {
			Library => { ..model, screen: LibraryScreen, pending_route: None }
			Settings => { ..model, screen: SettingsScreen, pending_route: None }
			Today => { ..model, screen: TodayScreen, pending_route: None, today_mode: Some(query_mode(model)) }
			Stats => { ..model, screen: StatsScreen, pending_route: None }
			WhatsNew => {
				changelog = match model.changelog {
					ChangelogLoaded(_) => model.changelog
					_ => ChangelogLoading
				}
				{ ..model, screen: WhatsNewScreen, pending_route: None, changelog }
			}
			Word(name) => {
				lemma_index = match model.lemma_index {
					IndexLoaded(_) => model.lemma_index
					_ => IndexLoading
				}
				{ ..model, screen: WordScreen(name), pending_route: None, lemma_index }
			}
			WordReview(name) => {
				word_answer = if model.screen == WordReviewScreen(name) model.word_answer else { guess: "", revealed: Bool.False }
				today_mode = match model.query.get("today") {
					Ok(mode) => Some(Today.mode_from_str(mode))
					Err(_) => None
				}
				{ ..model, screen: WordReviewScreen(name), pending_route: None, today_mode, word_answer }
			}
			# The work's saved passage. Unlike the Elm app (which then loops,
			# freezing the tab), a work opened before the library has loaded
			# waits for it.
			WorkLanding(work) =>
				match Model.entry_for(model, work) {
					Some(entry) => replace_route(model, Study(work, Corpus.saved_ref(entry, model.positions)))
					None =>
						if model.manifest_loaded {
							replace_route(model, Study(work, ""))
						} else {
							{ ..model, pending_route: Some(route) }
						}
				}
			Study(work, _) | Reader(work, _) =>
				if model.corpus_ready and Model.active_id(model) == work {
					show_route(model, route)
				} else {
					request_work(model, work, route)
				}
		}

	# LOADING

	receive_manifest : Model.Model, Try(Str, _) -> Model.Model
	receive_manifest = |model, result|
		match result {
			Ok(text) => match Corpus.manifest(text) {
				Ok(works) => {
					loaded = { ..model, works, manifest_loaded: Bool.True }
					# A work URL opened before the library arrived loads now.
					match model.pending_route {
						Some(route) if !model.corpus_ready => apply_route(loaded, route)
						_ => loaded
					}
				}
				Err(_) => model
			}
			Err(_) => model
		}

	## The preload files of the work being opened, `""` for none, with a serial
	## so a work asked for again downloads again.
	corpus_request : Model.Model -> { conllu : Str, units : Str, serial : U64 }
	corpus_request = |model| {
		none = { conllu: "", units: "", serial: model.fetch_serial }
		match model.requested_work {
			Some(id) if model.network_work != id =>
				match Model.entry_for(model, id) {
					Some(work) => { conllu: "/preload/${work.path}", units: if work.units_path == "" "" else "/preload/${work.units_path}", serial: model.fetch_serial }
					None => none
				}
			_ => none
		}
	}

	receive_conllu : Model.Model, Str, Try(Str, _) -> Model.Model
	receive_conllu = |model, url, result|
		if url != corpus_request(model).conllu {
			model
		} else {
			match result {
				Ok(text) => install({ ..model, fetched_conllu: Some(text) })
				Err(_) => download_failed(model)
			}
		}

	receive_units : Model.Model, Str, Try(Str, _) -> Model.Model
	receive_units = |model, url, result|
		if url != corpus_request(model).units {
			model
		} else {
			match result {
				Ok(text) => install({ ..model, fetched_units: Some(text) })
				Err(_) => download_failed(model)
			}
		}

	# TODAY

	## Opens the session's next item: a word review or a passage, in any work;
	## with nothing due, today's page.
	go_today : Model.Model, Today.Mode -> Model.Model
	go_today = |model, mode| {
		path = match Today.next(mode, Model.today_plan(model)) {
			Some(item) => Model.item_path(mode, item)
			None => "${Route.to_path(Today)}?today=${Today.mode_to_str(mode)}"
		}
		go({ ..model, today_mode: Some(mode) }, path)
	}

	start_today : Model.Model, Today.Mode -> Model.Model
	start_today = |model, mode| go_today({ ..model, today_mode: Some(mode), queue_mode: Bool.False, queue_done: Bool.False }, mode)

	## Today's session in one work (a work's Study button).
	start_today_in : Model.Model, Str -> Model.Model
	start_today_in = |model, work| {
		scoped = save_today_scope({ ..model, today_scope: Some(work), today_mode: Some(Everything), queue_mode: Bool.False, queue_done: Bool.False })
		go_today(scoped, Everything)
	}

	set_today_scope : Model.Model, Str -> Model.Model
	set_today_scope = |model, work| save_today_scope({ ..model, today_scope: if work == "" None else Some(work) })

	## More new passages today, staying in the session: reviews that come due
	## still come first, and the new passages are the next unseen ones.
	learn_more : Model.Model -> Model.Model
	learn_more = |model| {
		day = Review.start_of_day(model.clock)
		already = if model.extra_new.day == day model.extra_new.count else 0
		more = { ..model, extra_new: { day, count: already + Model.learn_more_step(model) } }
		in_queue = model.queue_mode and model.screen != TodayScreen and model.screen != LibraryScreen
		if in_queue {
			Workspace.advance({ ..more, queue_done: Bool.False })
		} else {
			mode = Model.with_default(model.today_mode, Everything)
			go_today({ ..more, today_mode: Some(mode) }, mode)
		}
	}

	# RATING

	## Rate the current passage. It is scheduled when storage answers with the
	## time (`finish_rating`); further ratings wait for it.
	rate : Model.Model, Fsrs.Rating -> Model.Model
	rate = |model, rating|
		match (model.pending_rating, model.active) {
			(None, Some(work)) => {
				key = Review.entry_key(work.id, Model.current_ref(model))
				Model.send({ ..model, pending_rating: Some(rating) }, [("rating", |id| Store.get(id, "progress", key))])
			}
			_ => model
		}

	## Schedules the pending rating at the clock storage just reported,
	## records the attempt and card (and clears the passage's draft), then
	## moves on: in today's session to its next item, else to the next passage.
	finish_rating : Model.Model -> Model.Model
	finish_rating = |model|
		match (model.pending_rating, model.active) {
			(Some(rating), Some(work)) => {
				now = model.clock
				passage = Model.current_passage(model)
				attempt = Study.build_attempt(now, rating, work.id, passage, model.study, Workspace.items(model))
				scheduled = Review.schedule(now, rating, work.id, passage.id, model.entries)
				attempts = model.attempts.prepend(attempt)
				recorded = {
					..model,
					pending_rating: None,
					attempts,
					entries: match scheduled {
						Ok(entry) => model.entries.insert(Review.entry_key(work.id, passage.id), entry)
						Err(_) => model.entries
					},
					word_cards: Words.cards(attempts, model.word_reviews),
					study: Study.empty_draft,
					all_words: Bool.False,
				}
				saved = Model.send(
					recorded,
					[("save", |id| Store.put(id, "progress", Study.encode_attempt(attempt)))]
						.concat(
							match scheduled {
								Ok(entry) => [("save", |id| Store.put(id, "progress", Review.encode_entry(entry)))]
								Err(_) => []
							},
						)
						.append(("save", |id| Store.put(id, "metadata", Store.setting(Study.draft_key(work.id, passage.id), Study.encode_draft(Study.empty_draft))))),
				)
				# The draft just saved empty is not saved again by Update.
				moved = match model.today_mode {
					Some(mode) => go_today(saved, mode)
					None => Workspace.advance(saved)
				}
				{ ..moved, notice: "", sync_due_at: now + 3000 }
			}
			_ => { ..model, pending_rating: None }
		}

	## Rate the word under review, once storage reports the time (any read
	## carries it; the theme is a small one).
	rate_word : Model.Model, Fsrs.Rating -> Model.Model
	rate_word = |model, rating|
		match (model.screen, model.pending_word_rating) {
			(WordReviewScreen(lemma), None) => Model.send({ ..model, pending_word_rating: Some((lemma, rating)) }, [("word-rating", |id| Store.get(id, "metadata", "theme"))])
			_ => model
		}

	finish_word_rating : Model.Model -> Model.Model
	finish_word_rating = |model|
		match model.pending_word_rating {
			Some((lemma, rating)) =>
				match model.word_cards.get(lemma) {
					Ok(word) => {
						now = model.clock
						context = Model.review_context(model, word)
						review = { lemma, at: now, rating, occurrence: { ..context, guess: model.word_answer.guess } }
						reviews = model.word_reviews.prepend(review)
						recorded = Model.send(
							{ ..model, pending_word_rating: None, word_reviews: reviews, word_cards: Words.cards(model.attempts, reviews), word_answer: { guess: "", revealed: Bool.False } },
							[("save", |id| Store.put(id, "progress", Words.encode_review(review)))],
						)
						moved = match model.today_mode {
							Some(mode) => go_today(recorded, mode)
							None => go_route(recorded, Word(lemma))
						}
						{ ..moved, notice: "", sync_due_at: now + 3000 }
					}
					Err(_) => { ..model, pending_word_rating: None }
				}
			None => model
		}

	## The work the Elm app or this one cached at its last download
	## (`{"entry", "raw", "units"}`), shown at once if it is the one being
	## opened; the download goes on and replaces it.
	receive_cached : Model.Model, JsonValue -> Model.Model
	receive_cached = |model, value| {
		found = JsonValue.field(value, "value") ?? JsonValue.null
		cached = match JsonValue.field(found, "entry") {
			Ok(entry) => match (Corpus.decode_work(entry), JsonValue.field(found, "raw")) {
				(Ok(work), Ok(raw)) => match JsonValue.as_str(raw) {
					Ok(conllu) => Ok({ work, conllu, units: JsonValue.as_str(JsonValue.field(found, "units") ?? JsonValue.str("")) ?? "" })
					Err(_) => Err(NoCache)
				}
				_ => Err(NoCache)
			}
			Err(_) => Err(NoCache)
		}
		match cached {
			Ok({ work, conllu, units }) if model.requested_work == Some(work.id) and !model.corpus_ready and model.network_work != work.id =>
				match Corpus.parse_work(work, conllu, units) {
					Ok(parsed) => show_pending({ ..model, notice: "", active: Some(work), passages: parsed.sentences, corpus_ready: Bool.True, sentence_index: 0, study: Study.empty_draft, popup_word: None, reader_gloss: None, reader_revealed: Set.empty() })
					Err(_) => model
				}
			_ => model
		}
	}

	receive_lemma_index : Model.Model, Try(Str, _) -> Model.Model
	receive_lemma_index = |model, result| {
		lemma_index = match result {
			Ok(text) => match decode_lemma_data(text) {
				Ok(data) => IndexLoaded(data)
				Err(_) => IndexFailed
			}
			Err(_) => IndexFailed
		}
		{ ..model, lemma_index }
	}

	receive_changelog : Model.Model, Try(Str, _) -> Model.Model
	receive_changelog = |model, result|
		match result {
			Ok(text) => { ..model, changelog: ChangelogLoaded(Changelog.parse(text)) }
			Err(_) => { ..model, changelog: ChangelogFailed }
		}

	set_new_per_day : Model.Model, Str -> Model.Model
	set_new_per_day = |model, value|
		match I64.from_str(value) {
			Ok(new_per_day) => Model.put_setting({ ..model, new_per_day }, "save", "review-settings", JsonValue.object([("newPerDay", JsonValue.int(new_per_day))]))
			Err(_) => model
		}
}

route_of : Str -> Route.Route
route_of = |location| Route.from_url(location) ?? Library

## Replaces the URL with `route` (the Elm app's `replaceUrl` and the
## `UrlChanged` that follows it).
replace_route : Model.Model, Route.Route -> Model.Model
replace_route = |model, route| {
	path = Route.to_path(route)
	routed = Nav.apply_route({ ..model, current_path: path, query: Dict.empty() }, route)
	url = routed.url
	{ ..routed, current_path: path, url: { path, push: url.push, serial: url.serial + 1 } }
}

query_mode : Model.Model -> Today.Mode
query_mode = |model|
	match model.query.get("today") {
		Ok(mode) => Today.mode_from_str(mode)
		Err(_) => Everything
	}

save_today_scope : Model.Model -> Model.Model
save_today_scope = |model| Model.put_setting(model, "save", "today-scope", JsonValue.str(Model.with_default(model.today_scope, "")))

route_work : Route.Route -> [Some(Str), None]
route_work = |route|
	match route {
		Study(work, _) | Reader(work, _) => Some(work)
		_ => None
	}

## Opens the route of an open work: its passage in the workspace or the reader.
show_route : Model.Model, Route.Route -> Model.Model
show_route = |model, route| {
	settled = { ..model, pending_route: None }
	match route {
		Study(work, passage) => {
			index = index_for(model, work, passage)
			moved = if index == settled.sentence_index settled else Workspace.move_to(settled, index)
			apply_query({ ..moved, screen: WorkspaceScreen, work_finished: Bool.False })
		}
		Reader(work, passage) => { ..settled, screen: ReaderScreen, sentence_index: index_for(model, work, Model.with_default(passage, "")), reader_gloss: None }
		_ => settled
	}
}

## Restores the popup, its tab, the open tool and the session from the URL's query.
apply_query : Model.Model -> Model.Model
apply_query = |model| {
	query = model.query
	{
		..model,
		popup_word: match query_number(query, "word") {
			Some(n) if n >= 0 => Some(n.to_u64_wrap())
			_ => None
		},
		popup_tab: if query.get("tab") == Ok("sentence") SentenceTab else WordTab,
		active_module: match query.get("tool") {
			Ok(key) => Tools.module_from_key(key)
			Err(_) => None
		},
		history_open: query.get("history") == Ok("1"),
		history_attempt: query_number(query, "attempt"),
		queue_mode: query.get("queue") == Ok("1"),
		today_mode: match query.get("today") {
			Ok(mode) => Some(Today.mode_from_str(mode))
			Err(_) => None
		},
	}
}

request_work : Model.Model, Str, Route.Route -> Model.Model
request_work = |model, work, route| {
	waiting = { ..model, requested_work: Some(work), pending_route: Some(route), fetched_conllu: None, fetched_units: None, fetch_serial: model.fetch_serial + 1 }
	if !model.manifest_loaded {
		# receive_manifest resumes this request once the library arrives.
		waiting
	} else {
		match Model.entry_for(model, work) {
			Some(entry) => {
				# A work without a passages file has no units to wait for.
				units = if entry.units_path == "" Some("") else None
				{ ..waiting, notice: "Loading ${entry.title}…", fetched_units: units }
			}
			None => { ..model, screen: LibraryScreen, pending_route: None, notice: "No work named “${work}” is bundled." }
		}
	}
}

## Both files of the requested work have arrived: parse and open it.
install : Model.Model -> Model.Model
install = |model|
	match (model.requested_work, model.fetched_conllu, model.fetched_units) {
		(Some(id), Some(conllu), Some(units)) =>
			match Model.entry_for(model, id) {
				Some(entry) =>
					match Corpus.parse_work(entry, conllu, units) {
						Ok(parsed) => {
							fresh = Model.put_setting({ ..model, fetched_conllu: None, fetched_units: None, network_work: id }, "save", "cached-corpus", JsonValue.object([("entry", Corpus.encode_work(entry)), ("raw", JsonValue.str(conllu)), ("units", JsonValue.str(units))]))
							# A fresh download of the work already shown from the cache keeps the reader's place.
							if model.corpus_ready and Model.active_id(model) == id {
								last = parsed.sentences.len().max(1) - 1
								return { ..fresh, active: Some(entry), passages: parsed.sentences, sentence_index: model.sentence_index.min(last) }
							}
							installed = {
								..fresh,
								notice: "",
								active: Some(entry),
								passages: parsed.sentences,
								corpus_ready: Bool.True,
								sentence_index: 0,
								study: Study.empty_draft,
								popup_word: None,
								reader_gloss: None,
								reader_revealed: Set.empty(),
							}
							show_pending(installed)
						}
						Err(problem) => { ..model, fetched_conllu: None, fetched_units: None, pending_route: None, notice: "${entry.title} could not be parsed: ${problem}" }
					}
				None => model
			}
		_ => model
	}

show_pending : Model.Model -> Model.Model
show_pending = |model|
	match model.pending_route {
		Some(route) if model.corpus_ready and route_work(route) == Some(Model.active_id(model)) => show_route(model, route)
		_ => model
	}

download_failed : Model.Model -> Model.Model
download_failed = |model| {
	title = match model.requested_work {
		Some(id) => Model.work_name(model, id)
		None => "The work"
	}
	{ ..model, pending_route: None, fetched_conllu: None, fetched_units: None, notice: "${title} could not be downloaded. Try again." }
}

## `preload/lemmas.json`: every occurrence of each lemma and the text of
## every passage, for word pages.
decode_lemma_data : Str -> Try(Model.LemmaData, Str)
decode_lemma_data = |text| {
	json = JsonValue.decode(text)?
	lemmas = JsonValue.fields(JsonValue.field(json, "lemmas")?).map_try(|(lemma, found)| Ok((lemma, JsonValue.items(found)?.map_try(occurrence)?)))?
	passages = JsonValue.fields(JsonValue.field(json, "passages")?).map_try(|(work, refs)| Ok((work, Dict.from_list(JsonValue.fields(refs).map_try(|(ref, passage)| Ok((ref, JsonValue.as_str(passage)?)))?))))?
	Ok({ lemmas: Dict.from_list(lemmas), passages: Dict.from_list(passages) })
}

## The passage of `ref` in the open work; a citation that is not one of its
## passages (e.g. an old bookmark) opens the saved position.
index_for : Model.Model, Str, Str -> U64
index_for = |model, work, ref|
	match Corpus.index_of_ref(ref, model.passages) {
		Some(index) => index
		None => {
			saved = (model.positions.get(work) ?? 1) - 1
			last = model.passages.len().to_i64_wrap() - 1
			saved.min(last).max(0).to_u64_wrap()
		}
	}

query_number : Dict(Str, Str), Str -> [Some(I64), None]
query_number = |query, key|
	match query.get(key) {
		Ok(text) => match I64.from_str(text) {
			Ok(n) => Some(n)
			Err(_) => None
		}
		Err(_) => None
	}

occurrence : JsonValue -> Try(Model.Occurrence, Str)
occurrence = |item|
	Ok({ work: field_str(item, "work")?, ref: field_str(item, "ref")?, position: JsonValue.as_i64(JsonValue.field(item, "position")?)?, form: field_str(item, "form")?, gloss: field_str(item, "gloss")? })

field_str : JsonValue, Str -> Try(Str, Str)
field_str = |item, name| JsonValue.as_str(JsonValue.field(item, name)?)
