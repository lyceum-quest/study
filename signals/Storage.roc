import json.JsonValue
import study.Review
import study.Study
import study.Sync
import study.Words
import Model
import Nav
import Store

## Storage results, ported from `handleStorageResponse` of `src/Main.elm`:
## each is routed by the purpose its id starts with (`<purpose>:<n>`, see
## Model.send), and every one sets the clock.
Storage := [].{

	receive : Model.Model, Str -> Model.Model
	receive = |model, payload|
		match Store.response(payload) {
			Err(problem) => { ..model, notice: "Storage answered something unexpected: ${problem}" }
			Ok(response) => {
				timed = { ..model, clock: response.now, offset: response.offset }
				purpose = match response.id.split_first(":") {
					Ok({ before, .. }) => before
					Err(_) => response.id
				}
				if !response.ok {
					failed(timed, purpose)
				} else {
					value = response.value
					match purpose {
						"progress" => progress(timed, value)
						"draft" => draft(timed, value)
						"theme" => theme(timed, value)
						"reader-layers" => reader_layers(timed, value)
						"positions" => positions(timed, value)
						"settings" => settings(timed, value)
						"scope" => scope(timed, value)
						"sync-state" => sync_state(timed, value)
						"cached-corpus" => Nav.receive_cached(timed, value)
						"rating" => Nav.finish_rating(timed)
						"word-rating" => Nav.finish_word_rating(timed)
						_ => timed
					}
				}
			}
		}

	## Asks storage for the time (the review settings, which the Elm app may
	## change meanwhile), so intervals and due cards follow the clock.
	refresh_clock : Model.Model -> Model.Model
	refresh_clock = |model| Model.send(model, [("settings", |id| Store.get(id, "metadata", "review-settings"))])

	## A setting received from sync (`applySetting`): positions join those here
	## (received ones win); the others apply as if read from storage.
	apply_setting : Model.Model, Str, JsonValue -> Model.Model
	apply_setting = |model, key, value| {
		record = JsonValue.object([("key", JsonValue.str(key)), ("value", value)])
		match key {
			"positions" => { ..model, positions: Sync.merge_positions(model.positions, value) }
			"theme" => theme(model, record)
			"reader-layers" => reader_layers(model, record)
			"review-settings" => settings(model, record)
			"today-scope" => scope(model, record)
			_ => model
		}
	}

	## The sync state, read once when an account that syncs signs in.
	load_sync_state : Model.Model -> Model.Model
	load_sync_state = |model| Model.send({ ..model, sync_requested: Bool.True }, [("sync-state", |id| Store.get(id, "metadata", "sync-state"))])

	## The current passage's saved draft, asked for when the passage opens.
	load_draft : Model.Model, Str -> Model.Model
	load_draft = |model, key| Model.send(model, [("draft", |id| Store.get(id, "metadata", key))])
}

## A failed read leaves the default in place, as in the Elm app; a failed
## rating can be retried.
failed : Model.Model, Str -> Model.Model
failed = |model, purpose|
	match purpose {
		"rating" => { ..model, pending_rating: None, notice: "The rating could not be saved. Try again." }
		"word-rating" => { ..model, pending_word_rating: None, notice: "The rating could not be saved. Try again." }
		"save" => { ..model, notice: "Something could not be saved in this browser's storage." }
		"sync-state" => { ..model, sync_loaded: Bool.True, sync_due_at: 1 }
		_ => model
	}

## The progress store holds finished attempts, review cards and word reviews;
## passage cards are replayed from the attempts (`Review.cards`).
progress : Model.Model, JsonValue -> Model.Model
progress = |model, value| {
	records = JsonValue.items(value) ?? []
	attempts = records.keep_oks(Study.decode_attempt)
	word_reviews = records.keep_oks(Words.decode_review)
	stored = Dict.from_list(records.keep_oks(Review.decode_entry).map(|entry| (Review.entry_key(entry.work, entry.passage), entry)))
	{
		..model,
		attempts,
		word_reviews,
		word_cards: Words.cards(attempts, word_reviews),
		entries: Review.cards(stored, attempts),
		progress_loaded: Bool.True,
	}
}

## `{"key": "draft:<work>:<ref>", "value": <draft>}`, used only if it is still
## the open passage's.
draft : Model.Model, JsonValue -> Model.Model
draft = |model, value| {
	key = match JsonValue.field(value, "key") {
		Ok(found) => JsonValue.as_str(found) ?? ""
		Err(_) => ""
	}
	if Some(key) != Model.draft_key(model) {
		model
	} else {
		match JsonValue.field(value, "value") {
			Ok(stored) => match Study.decode_draft(stored) {
				Ok(found) => { ..model, study: Study.resumable(model.clock, found) }
				Err(_) => model
			}
			Err(_) => model
		}
	}
}

theme : Model.Model, JsonValue -> Model.Model
theme = |model, value|
	match setting_str(value) {
		Ok("light") => { ..model, dark: Bool.False }
		Ok("dark") => { ..model, dark: Bool.True }
		_ => model
	}

reader_layers : Model.Model, JsonValue -> Model.Model
reader_layers = |model, value| {
	decoded = match JsonValue.field(value, "value") {
		Ok(layers) => match (flag(layers, "glosses"), flag(layers, "morphology"), flag(layers, "translation")) {
			(Ok(glosses), Ok(morphology), Ok(translation)) => Ok({ glosses, morphology, translation })
			_ => Err(Invalid)
		}
		Err(_) => Err(Invalid)
	}
	match decoded {
		Ok(layers) => { ..model, reader_layers: layers }
		Err(_) => model
	}
}

## Stored positions join those already set this session.
positions : Model.Model, JsonValue -> Model.Model
positions = |model, value|
	match JsonValue.field(value, "value") {
		Ok(stored) => {
			found = JsonValue.fields(stored).keep_oks(|(work, position)| JsonValue.as_i64(position).map_ok(|n| (work, n)))
			{ ..model, positions: found.fold(model.positions, |all, (work, n)| if all.contains(work) all else all.insert(work, n)) }
		}
		Err(_) => model
	}

## `{"key": "review-settings", "value": {"newPerDay": n}}`, or null.
settings : Model.Model, JsonValue -> Model.Model
settings = |model, value|
	match JsonValue.field(value, "value") {
		Ok(stored) => match JsonValue.field(stored, "newPerDay") {
			Ok(n) => match JsonValue.as_i64(n) {
				Ok(new_per_day) => { ..model, new_per_day }
				Err(_) => model
			}
			Err(_) => model
		}
		Err(_) => model
	}

scope : Model.Model, JsonValue -> Model.Model
scope = |model, value|
	match setting_str(value) {
		Ok(work) => { ..model, today_scope: if work == "" None else Some(work) }
		Err(_) => model
	}

setting_str : JsonValue -> Try(Str, Str)
setting_str = |value| JsonValue.as_str(JsonValue.field(value, "value")?)

flag : JsonValue, Str -> Try(Bool, Str)
flag = |layers, name| JsonValue.as_bool(JsonValue.field(layers, name)?)

## `{"key": "sync-state", "value": <state>}`, or null on a device that never
## synced; the next tick syncs.
sync_state : Model.Model, JsonValue -> Model.Model
sync_state = |model, value| {
	state = match JsonValue.field(value, "value") {
		Ok(stored) => Sync.decode_state(stored) ?? model.sync
		Err(_) => model.sync
	}
	{ ..model, sync: state, sync_loaded: Bool.True, sync_due_at: 1 }
}
