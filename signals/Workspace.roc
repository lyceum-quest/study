import study.Corpus
import study.Study
import study.Tools
import Model

## Studying a passage, ported from the workspace branches of `updateModel` in
## `src/Main.elm`: moving between passages, the study tools and word popup,
## answering, revealing, the checkpoint and marking, and past attempts.
## Transitions that open another page (a rating in today's session, Today)
## are in Nav.
Workspace := [].{

	## Opens passage `index` of the open work in the workspace, closing what
	## belongs to the previous one.
	move_to : Model.Model, U64 -> Model.Model
	move_to = |model, index|
		if index >= model.passages.len() {
			model
		} else {
			{
				..model,
				screen: WorkspaceScreen,
				all_words: Bool.False,
				sentence_index: index,
				popup_word: None,
				history_open: Bool.False,
				history_attempt: None,
				notice: "",
				work_finished: Bool.False,
			}
		}

	## Choosing a passage by hand leaves today's review queue.
	browsing : Model.Model -> Model.Model
	browsing = |model| { ..model, queue_mode: Bool.False, queue_done: Bool.False, today_mode: None }

	previous : Model.Model -> Model.Model
	previous = |model| if model.sentence_index == 0 model else move_to(browsing(model), model.sentence_index - 1)

	next : Model.Model -> Model.Model
	next = |model| move_to(browsing(model), model.sentence_index + 1)

	## After a graded passage: the next one in today's queue, or in text order
	## when browsing; past the last passage of a work, say it is finished.
	advance : Model.Model -> Model.Model
	advance = |model|
		if model.queue_mode {
			first = match Model.today_queue(model) {
				Some(queue) => queue.due.concat(queue.new).first()
				None => Err(ListWasEmpty)
			}
			match first {
				Ok(passage) => {
					index = match Corpus.index_of_ref(passage, model.passages) {
						Some(found) => found
						None => model.sentence_index
					}
					move_to({ ..model, queue_done: Bool.False }, index)
				}
				Err(_) => { ..model, queue_done: Bool.True, popup_word: None, active_module: None }
			}
		} else if model.sentence_index + 1 < model.passages.len() {
			move_to(model, model.sentence_index + 1)
		} else {
			# The last passage of the work: say so, rather than showing it again with the answers cleared.
			{ ..model, work_finished: Bool.True, popup_word: None, active_module: None }
		}

	## Opens the first passage whose citation starts with `prefix` (`1` =
	## chapter 1, `1.2` = 1:2), in the reader or the workspace, whichever shows.
	jump_to_citation : Model.Model, Str -> Model.Model
	jump_to_citation = |model, prefix|
		match Corpus.citation_index(prefix, model.passages) {
			Some(index) =>
				if model.screen == ReaderScreen {
					{ ..model, sentence_index: index, reader_gloss: None }
				} else {
					move_to(browsing(model), index)
				}
			None => { ..model, notice: "No passage ${prefix} in ${Model.work_title(model)}." }
		}

	## `1:2`, `1 2`, `1,2`, or `43 §2` typed into the go-to box.
	go_to_citation : Model.Model, Str -> Model.Model
	go_to_citation = |model, typed| {
		citation = Corpus.normalize_citation(typed)
		if citation == "" model else jump_to_citation(model, citation)
	}

	# TOOLS AND POPUPS

	select_preset : Model.Model, Tools.Preset -> Model.Model
	select_preset = |model, preset| { ..model, preset, settings: Tools.settings_for_preset(preset, model.settings), active_module: None }

	toggle_module : Model.Model, Tools.ModuleId -> Model.Model
	toggle_module = |model, module_id| {
		mode = if Tools.module_mode(module_id, model.settings) == ModuleOff OnDemand else ModuleOff
		settings = Tools.set_module_mode(module_id, mode, model.settings)
		closed = model.active_module == Some(module_id) and Tools.module_mode(module_id, settings) == ModuleOff
		{ ..model, preset: CustomPreset, settings, active_module: if (closed) None else model.active_module }
	}

	open_module : Model.Model, Tools.ModuleId -> Model.Model
	open_module = |model, module_id| { ..model, active_module: Some(module_id), popup_word: None }

	close_workbench : Model.Model -> Model.Model
	close_workbench = |model| { ..model, active_module: None }

	## A word's popup opens on its Word tab; tapping the open word closes it.
	toggle_popup : Model.Model, U64 -> Model.Model
	toggle_popup = |model, token|
		if model.popup_word == Some(token) {
			close_popup(model)
		} else {
			{ ..model, popup_word: Some(token), popup_tab: WordTab }
		}

	close_popup : Model.Model -> Model.Model
	close_popup = |model| { ..model, popup_word: None }

	set_popup_tab : Model.Model, Model.PopupTab -> Model.Model
	set_popup_tab = |model, tab| { ..model, popup_tab: tab }

	set_all_words : Model.Model, Bool -> Model.Model
	set_all_words = |model, all_words| { ..model, all_words }

	# PAST ATTEMPTS

	open_history : Model.Model -> Model.Model
	open_history = |model| { ..model, history_open: Bool.True, history_attempt: None, popup_word: None, active_module: None }

	close_history : Model.Model -> Model.Model
	close_history = |model| { ..model, history_open: Bool.False, history_attempt: None }

	select_history_attempt : Model.Model, I64 -> Model.Model
	select_history_attempt = |model, finished_at| { ..model, history_attempt: if model.history_attempt == Some(finished_at) None else Some(finished_at) }

	# ANSWERING AND GRADING

	set_gloss : Model.Model, U64, Str -> Model.Model
	set_gloss = |model, token, gloss| edit_study(model, |draft| { ..draft, glosses: draft.glosses.insert(token, gloss) })

	set_literal : Model.Model, Str -> Model.Model
	set_literal = |model, literal| edit_study(model, |draft| { ..draft, literal })

	set_prose : Model.Model, Str -> Model.Model
	set_prose = |model, prose| edit_study(model, |draft| { ..draft, prose })

	## Revealing before submitting marks the item as assisted.
	reveal : Model.Model, Str -> Model.Model
	reveal = |model, key| edit_study(model, |draft| { ..draft, revealed: draft.revealed.insert(key) })

	submit : Model.Model -> Model.Model
	submit = |model| {
		study = model.study
		{ ..model, study: { ..study, submitted: Bool.True, updated_at: model.clock }, popup_word: None, active_module: None }
	}

	## Back to answering; the marks are cleared.
	reopen : Model.Model -> Model.Model
	reopen = |model| {
		study = model.study
		{ ..model, study: { ..study, submitted: Bool.False, marks: Dict.empty() } }
	}

	## Marking an item the way it is already marked unmarks it.
	mark : Model.Model, Str, Bool -> Model.Model
	mark = |model, key, right| {
		study = model.study
		marks = if study.marks.get(key) == Ok(right) study.marks.remove(key) else study.marks.insert(key, right)
		{ ..model, study: { ..study, marks, updated_at: model.clock } }
	}

	# VIEW DATA

	## The words asked this time: on a repeat, only those missed last time
	## (None asks every word).
	asked : Model.Model -> [Some(Set(Str)), None]
	asked = |model| Study.asked_words(model.all_words, last_attempt(model))

	last_attempt : Model.Model -> [Some(Study.Attempt), None]
	last_attempt = |model| Study.last_attempt(Model.active_id(model), Model.current_ref(model), model.attempts)

	## The items of the current passage in grading order.
	items : Model.Model -> List(Study.Item)
	items = |model| Study.study_items(Model.current_passage(model), model.study, model.settings, asked(model))

	current_attempts : Model.Model -> List(Study.Attempt)
	current_attempts = |model|
		match model.active {
			Some(work) => Study.passage_attempts(work.id, Model.current_ref(model), model.attempts)
			None => []
		}
}

## Answers can change only before the checkpoint; the first edit stamps when
## work on the passage began.
edit_study : Model.Model, (Study.Draft -> Study.Draft) -> Model.Model
edit_study = |model, change|
	if model.study.submitted {
		model
	} else {
		changed = change(model.study)
		started_at = if (changed.started_at == 0) model.clock else changed.started_at
		{ ..model, study: { ..changed, started_at, updated_at: model.clock } }
	}
