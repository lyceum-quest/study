import study.Route
import study.Study
import study.Today
import study.Tools
import json.JsonValue
import Model
import Nav
import Storage
import Store

## What follows every transition, as Elm's `update` wraps `updateModel` in
## `src/Main.elm`: a newly shown passage loads its saved draft, an edited
## draft is saved, the URL follows the model (replacing the history entry for
## changes that stay on the same page) and the reading position is saved with
## it, and the storage requests the transition queued leave as one batch.
Update := [].{

	## The app after `change`, for an event on the page.
	step : Model.Model, (Model.Model -> Model.Model) -> Model.Model
	step = |model, change| finish(model, change(model), Bool.False)

	## The app after the browser moved to `location` (back, forward, a link).
	located : Model.Model, Str -> Model.Model
	located = |model, location| finish(model, Nav.location_changed(model, location), Bool.True)

	## The URL the model shows: `#/…` with the page state in its query.
	path_for : Model.Model -> [Some(Str), None]
	path_for = |model|
		match (model.screen, base_path(model)) {
			(WorkspaceScreen, Some(path)) => Some("${path}${query_for(model)}")
			(TodayScreen, Some(path)) | (WordReviewScreen(_), Some(path)) => Some("${path}${today_query(model)}")
			(_, found) => found
		}
}

finish : Model.Model, Model.Model, Bool -> Model.Model
finish = |previous, updated, url_change| {
	followed = follow_passage(previous, updated)
	saved = save_draft(previous, followed)
	replace = url_change or (previous.screen == ReaderScreen and saved.screen == ReaderScreen) or base_path(previous) == base_path(saved)
	flush(sync_url(previous, saved, replace))
}

## A newly shown passage starts empty until its saved draft (if any) arrives.
follow_passage : Model.Model, Model.Model -> Model.Model
follow_passage = |previous, next|
	match Model.draft_key(next) {
		Some(key) if Model.draft_key(previous) != Some(key) => Storage.load_draft({ ..next, study: Study.empty_draft }, key)
		_ => next
	}

save_draft : Model.Model, Model.Model -> Model.Model
save_draft = |previous, next|
	match Model.draft_key(next) {
		Some(key) if Model.draft_key(previous) == Some(key) and previous.study != next.study =>
			Model.put_setting(next, "save", key, Study.encode_draft(next.study))
		_ => next
	}

sync_url : Model.Model, Model.Model, Bool -> Model.Model
sync_url = |previous, next, replace|
	match (next.pending_route, Update.path_for(next)) {
		(None, Some(path)) => {
			url = next.url
			navigated = url.serial != previous.url.serial
			if path == next.current_path and !navigated {
				next
			} else {
				# A transition that opened a URL keeps its new history entry, at the path the model settled on.
				push = if (navigated) url.push else !replace
				save_position({ ..next, current_path: path, url: { path, push, serial: previous.url.serial + 1 } })
			}
		}
		_ => next
	}

## Positions are saved as 1-based passage numbers, over those read at start.
save_position : Model.Model -> Model.Model
save_position = |model|
	match model.active {
		Some(work) if model.screen == WorkspaceScreen or model.screen == ReaderScreen => {
			saved = model.positions.insert(work.id, (model.sentence_index + 1).to_i64_wrap())
			Model.put_setting(model, "save", "positions", JsonValue.object(saved.to_list().map(|(id, n)| (id, JsonValue.int(n)))))
		}
		_ => model
	}

flush : Model.Model -> Model.Model
flush = |model|
	if model.requests.is_empty() {
		model
	} else {
		{ ..model, outbox: Store.batch(model.requests), requests: [] }
	}

base_path : Model.Model -> [Some(Str), None]
base_path = |model| {
	passage = Model.current_ref(model)
	match model.screen {
		LibraryScreen => Some(Route.to_path(Library))
		SettingsScreen => Some(Route.to_path(Settings))
		WorkspaceScreen => for_work(model, |work| Study(work, passage))
		ReaderScreen => for_work(model, |work| Reader(work, Some(passage)))
		TodayScreen => Some(Route.to_path(Today))
		WordScreen(lemma) => Some(Route.to_path(Word(lemma)))
		WordReviewScreen(lemma) => Some(Route.to_path(WordReview(lemma)))
		StatsScreen => Some(Route.to_path(Stats))
		WhatsNewScreen => Some(Route.to_path(WhatsNew))
	}
}

query_for : Model.Model -> Str
query_for = |model| {
	pairs = [
		match model.popup_word {
			Some(word) => Ok("word=${word.to_str()}")
			None => Err({})
		},
		if model.popup_word != None and model.popup_tab == SentenceTab Ok("tab=sentence") else Err({}),
		match model.active_module {
			Some(module_id) => Ok("tool=${Tools.module_key(module_id)}")
			None => Err({})
		},
		if (model.history_open) Ok("history=1") else Err({}),
		match model.history_attempt {
			Some(finished_at) => Ok("attempt=${finished_at.to_str()}")
			None => Err({})
		},
		if (model.queue_mode) Ok("queue=1") else Err({}),
		match model.today_mode {
			Some(mode) => Ok("today=${Today.mode_to_str(mode)}")
			None => Err({})
		},
	].keep_oks(|pair| pair)
	if pairs.is_empty() "" else "?${Str.join_with(pairs, "&")}"
}

today_query : Model.Model -> Str
today_query = |model|
	match model.today_mode {
		Some(mode) => "?today=${Today.mode_to_str(mode)}"
		None => ""
	}

for_work : Model.Model, (Str -> Route.Route) -> [Some(Str), None]
for_work = |model, to_route|
	match model.active {
		Some(work) => Some(Route.to_path(to_route(work.id)))
		None => None
	}
