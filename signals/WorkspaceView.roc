import pf.Engine exposing [Elem, Row, RowRef, State, Val]
import pf.Html
import fsrs.Fsrs
import fsrs.FsrsMath
import study.Corpus
import study.Review
import study.Route
import study.Study
import study.Tools
import Model
import Nav
import Page
import Update
import Workspace

## Studying a passage, ported from `viewWorkspace` and the views it uses in
## `src/Main.elm`: the context bar with passage navigation, the passage to
## answer (an interlinear of glosses, or the Greek alone) with word popups and
## study tools, the checkpoint's grading, past attempts, the ends of a queue
## or a work, and the footer that moves between them.
##
## Workaround: roc-signals 0.3.0 cannot measure layout, so the word popup
## opens in its natural place below the word (the Elm app measures it and
## moves it above or sideways to fit); see
## https://github.com/thebrandonlucas/roc-issues/tree/master/roc-signals/RS-005-layout-measurement.
WorkspaceView := [].{

	## One word of the passage to answer. `greek` carries the punctuation that
	## follows the word (interlinear) or is the token alone (passage view).
	Cell : {
		key : Str,
		id : U64,
		word_key : Str,
		greek : Str,
		form : Str,
		lemma : Str,
		gloss : Str,
		is_word : Bool,
		space : Bool,
		asked : Bool,
		repeat : Bool,
		open : Bool,
		revealed : Bool,
		guess : Str,
	}

	## One word at the checkpoint: its item, if it was asked.
	Graded : {
		key : Str,
		word_key : Str,
		greek : Str,
		asked : Bool,
		reference : Str,
		guess : Str,
		mark : Str,
		was_missed : Bool,
		revealed_early : Bool,
		last_time : [Some(Str), None],
		previous : Str,
	}

	view : State(Page.S, Model.Model) -> Elem(Page.S)
	view = |session| {
		model = session.val()
		Engine.element(
			"main",
			[Engine.class("workspace-page")],
			[
				context_bar(session),
				Html.div_v(
					model.map(|m| if show_tool(m) "workspace-grid has-workbench" else "workspace-grid"),
					[
						Engine.switch(
							model.map(stage),
							["queue-done", "work-finished", "history", "grading", "study"],
							|found| match found {
								"queue-done" => queue_done(session)
								"work-finished" => work_finished(session)
								"history" => history(session)
								"grading" => grading(session)
								_ => study_stage(session)
							},
						),
						Engine.when(model.map(show_tool), || tool_panel(session), || Engine.text("")),
					],
				),
				Engine.when(model.map(|m| !m.queue_done and !m.work_finished), || footer(session), || Engine.text("")),
			],
		)
	}
}

stage : Model.Model -> Str
stage = |model|
	if model.queue_done {
		"queue-done"
	} else if model.work_finished {
		"work-finished"
	} else if model.history_open {
		"history"
	} else if model.study.submitted {
		"grading"
	} else {
		"study"
	}

show_tool : Model.Model -> Bool
show_tool = |model| !model.study.submitted and !model.history_open and model.active_module != None

show_library : Model.Model -> Model.Model
show_library = |model| { ..model, screen: LibraryScreen, notice: "", popup_word: None }

show_settings : Model.Model -> Model.Model
show_settings = |model| { ..model, screen: SettingsScreen, notice: "", popup_word: None, confirm_clear: Bool.False }

context_bar : State(Page.S, Model.Model) -> Elem(Page.S)
context_bar = |session| {
	model = session.val()
	Html.div(
		"work-context-bar",
		[
			Html.div(
				"context-title",
				[
					Html.button("←", [Engine.class("icon-button"), Engine.attr("type", "button"), Html.aria_label("Back to library")], Page.act(session, show_library)),
					Html.div("", [Html.span_v(model.map(Model.work_title), [Engine.class("context-work")])]),
				],
			),
			Engine.when(
				model.map(|m| queue_status(m) != None),
				|| Engine.element(
					"span",
					[Engine.class("queue-status")],
					[
						Html.span_v(model.map(|m| Model.with_default(queue_status(m), { kind: "", left: "" }).kind), [Engine.class("queue-kind"), Engine.test_id("queue-kind")]),
						Html.span_v(model.map(|m| Model.with_default(queue_status(m), { kind: "", left: "" }).left), [Engine.test_id("queue-left")]),
					],
				),
				|| Engine.text(""),
			),
			Html.div(
				"context-actions",
				[
					Html.div(
						"passage-nav",
						[
							Html.button("‹", [Engine.class("icon-button"), Engine.attr("type", "button"), Html.disabled(model.map(|m| m.sentence_index == 0)), Html.aria_label("Previous passage (← or k)")], Page.act(session, Workspace.previous)),
							citation_picker(session),
							Html.button("›", [Engine.class("icon-button"), Engine.attr("type", "button"), Html.disabled(model.map(|m| m.sentence_index + 1 >= m.passages.len())), Html.aria_label("Next passage (→ or j)")], Page.act(session, Workspace.next)),
						],
					),
				],
			),
		],
	)
}

## In a work's queue: whether this passage is a review or new, and how many remain.
queue_status : Model.Model -> [Some({ kind : Str, left : Str }), None]
queue_status = |model|
	match (model.queue_mode and !model.queue_done, Model.today_queue(model)) {
		(Bool.True, Some(today)) => Some(
			{
				kind: if today.due.contains(Model.current_ref(model)) "Review" else "New",
				left: "${(today.due.len() + today.new.len()).to_str()} left today",
			},
		)
		_ => None
	}

## One select per citation level (Chapter/Verse, Book/Chapter/Section, …) and
## a go-to box accepting `1:2` or `1.2`.
citation_picker : State(Page.S, Model.Model) -> Elem(Page.S)
citation_picker = |session| {
	model = session.val()
	Html.div(
		"citation-picker",
		[
			Engine.each(
				model.map(levels),
				|level| level.name,
				|row| Engine.element(
					"label",
					[Engine.class("chapter-jump")],
					[
						Engine.element("span", [], [Engine.text_v(row.field(|level| level.name))]),
						Engine.element(
							"select",
							[
								Engine.attr_v("value", row.field(|level| level.current)),
								Engine.on("change", session.lift_row().set_value_by(row.field(|level| level.prefix), |m, prefix, value| Update.step(m, |x| Workspace.jump_to_citation(x, "${prefix}${value}")))),
							],
							[Engine.each(row.field(|level| level.choices), |choice| choice, |option| Engine.element("option", [Engine.attr_v("value", option.key())], [Engine.text_v(option.key())]))],
						),
					],
				),
			),
			Engine.element(
				"input",
				[
					Engine.class("citation-go"),
					Engine.attr_v("placeholder", model.map(|m| if Model.current_label(m).contains(":") "Go to 1:2" else "Go to 1.2")),
					Html.aria_label("Go to citation"),
					Engine.on("change", Page.act_value(session, Workspace.go_to_citation)),
					Engine.on("keydown", session.update(|m| m)),
				],
				[],
			),
		],
	)
}

levels : Model.Model -> List({ name : Str, prefix : Str, current : Str, choices : List(Str) })
levels = |model| {
	current = Corpus.parts(Model.current_ref(model))
	refs = model.passages.map(|passage| Corpus.parts(passage.id))
	names = Corpus.level_names(Model.current_label(model).contains(":"), Corpus.is_split(model.passages), Corpus.levels(model.passages))
	names.map_with_index(
		|name, level| {
			above = current.take_first(level)
			choices = refs
				.keep_if(|parts| parts.take_first(level) == above)
				.keep_oks(|parts| parts.get(level))
				.fold([], |found, value| if found.contains(value) found else found.append(value))
			{
				name,
				prefix: if above.is_empty() "" else "${Str.join_with(above, ".")}.",
				current: current.get(level) ?? "",
				choices,
			}
		},
	)
}

# STUDYING

study_stage : State(Page.S, Model.Model) -> Elem(Page.S)
study_stage = |session| {
	model = session.val()
	Engine.element(
		"section",
		[Engine.class("reading-stage")],
		[
			session_status(session),
			history_link(session),
			Engine.switch(
				model.map(instruction),
				["interlinear", "repeat-all", "repeat-some", "repeat-again", "passage"],
				|found| match found {
					"passage" => Engine.element("p", [Engine.class("reading-instruction")], [Engine.text("Tap a word to gloss it. "), Engine.element("span", [], [Engine.text("Answers stay hidden until you reveal them or submit.")])])
					"repeat-all" | "repeat-some" =>
						Engine.element(
							"p",
							[Engine.class("reading-instruction")],
							[
								Engine.text("Write a gloss under each word; tap a word for its lemma, the sentence, or to reveal it. "),
								Engine.element(
									"span",
									[],
									[
										Engine.text(if found == "repeat-all" "You got every word last time, so only the translation is asked. " else "Only the words you missed last time are asked. "),
										Page.button("Ask every word", "text-button", Page.act(session, |m| Workspace.set_all_words(m, Bool.True))),
									],
								),
							],
						)
					"repeat-again" =>
						Engine.element(
							"p",
							[Engine.class("reading-instruction")],
							[
								Engine.text("Write a gloss under each word; tap a word for its lemma, the sentence, or to reveal it. "),
								Page.button("Only words missed last time", "text-button", Page.act(session, |m| Workspace.set_all_words(m, Bool.False))),
							],
						)
					_ => Engine.element("p", [Engine.class("reading-instruction")], [Engine.text("Write a gloss under each word; tap a word for its lemma, the sentence, or to reveal it. ")])
				},
			),
			Engine.switch(
				model.map(|m| if interlinear(m) "interlinear" else "passage"),
				["interlinear", "passage"],
				|found| match found {
					"interlinear" => Html.div_attrs([Engine.class("interlinear study-interlinear")], [Engine.each(model.map(|m| cells(m, Bool.True)), |cell| cell.key, |row| study_cell(session, row))])
					_ => Html.div_attrs([Engine.class("greek-passage study-passage"), Engine.attr("lang", "grc")], [Engine.each(model.map(|m| cells(m, Bool.False)), |cell| cell.key, |row| study_token(session, row))])
				},
			),
			Html.div(
				"source-line",
				[
					Html.span_v(model.map(edition), []),
					Html.span_v(model.map(|m| "${Model.current_passage(m).tokens.count_if(|token| Study.is_word_token(token.form)).to_str()} words"), []),
				],
			),
			active_sources(session),
			tool_tray(session),
		],
	)
}

interlinear : Model.Model -> Bool
interlinear = |model| Tools.module_mode(GlossModule, model.settings) != ModuleOff

## Which instruction the passage shows: the gloss interlinear (on a repeat,
## asking only the words missed last time, or every word again), or the Greek alone.
instruction : Model.Model -> Str
instruction = |model|
	if !interlinear(model) {
		"passage"
	} else {
		match Workspace.asked(model) {
			Some(asked) => if asked.is_empty() "repeat-all" else "repeat-some"
			None => if Workspace.last_attempt(model) != None "repeat-again" else "interlinear"
		}
	}

## In today's session: how much is left.
session_status : State(Page.S, Model.Model) -> Elem(Page.S)
session_status = |session| {
	model = session.val()
	Engine.when(
		model.map(|m| m.today_mode != None),
		|| Html.p_v(
			model.map(
				|m| {
					today = Model.today_plan(m)
					scope = match m.today_scope {
						Some(work) => "${Model.work_name(m, work)} · "
						None => ""
					}
					"Today · ${scope}${Model.counted(today.words.len(), "word", "words")} · ${Model.counted(today.due.len() + today.new.len(), "passage", "passages")} left"
				},
			),
			[Engine.class("session-status")],
		),
		|| Engine.text(""),
	)
}

## The way into the passage's history; absent until the passage has been graded once.
history_link : State(Page.S, Model.Model) -> Elem(Page.S)
history_link = |session| {
	model = session.val()
	Engine.when(
		model.map(|m| !Workspace.current_attempts(m).is_empty()),
		|| Html.button_v(
			model.map(
				|m| {
					count = Workspace.current_attempts(m).len()
					"${count.to_str()} past ${Model.plural(count, "attempt", "attempts")} →"
				},
			),
			[Engine.class("history-link"), Engine.attr("type", "button")],
			Page.act(session, Workspace.open_history),
		),
		|| Engine.text(""),
	)
}

## The words of the current passage: grouped with their punctuation for the
## interlinear, or every token in order for the passage view.
cells : Model.Model, Bool -> List(WorkspaceView.Cell)
cells = |model, grouped| {
	passage = Model.current_passage(model)
	asked = Workspace.asked(model)
	cell = |token, greek, space| {
		word_key = Study.word_key(token.id)
		is_asked = Study.is_asked(asked, word_key)
		{
			key: token.id.to_str(),
			id: token.id,
			word_key,
			greek,
			form: token.form,
			lemma: token.lemma,
			gloss: token.gloss,
			is_word: Study.is_word_token(token.form),
			space,
			asked: is_asked,
			repeat: is_asked and asked != None,
			open: model.popup_word == Some(token.id),
			revealed: model.study.revealed.contains(word_key),
			guess: model.study.glosses.get(token.id) ?? "",
		}
	}
	if grouped {
		Study.group_words(passage.tokens).map(|(token, suffix)| cell(token, "${token.form}${suffix}", Bool.False))
	} else {
		passage.tokens.map_with_index(|token, index| cell(token, token.form, index > 0))
	}
}

## One word of the interlinear: the Greek (tap for the popup) and the
## learner's gloss beneath it; a word not asked on a repeat shows the Greek
## only (last time's gloss would give the translation away).
study_cell : State(Page.S, Model.Model), RowRef(Page.S, WorkspaceView.Cell) -> Elem(Row(Page.S, WorkspaceView.Cell))
study_cell = |session, row| {
	rows = session.lift_row()
	id = row.field(|cell| cell.id)
	Html.div_v(
		row.field(|cell| "interlinear-word study-cell${if cell.repeat " is-repeat" else ""}${if cell.asked "" else " is-settled"}"),
		[
			Engine.element(
				"span",
				[Engine.class("study-token-wrap")],
				[
					Engine.element(
						"button",
						[
							Engine.class_v(row.field(|cell| "interlinear-greek study-cell-greek${if cell.open " is-open" else ""}${if cell.revealed " is-revealed" else ""}")),
							Engine.attr("type", "button"),
							Engine.attr("lang", "grc"),
							Engine.attr_v("aria-expanded", row.field(|cell| if cell.open "true" else "false")),
							Engine.on_click(rows.update_by(id, |m, token| Update.step(m, |x| Workspace.toggle_popup(x, token)))),
						],
						[Engine.text_v(row.field(|cell| cell.greek))],
					),
					Engine.when(row.field(|cell| cell.open), || popup(session, row), || Engine.text("")),
				],
			),
			Engine.when(
				row.field(|cell| cell.asked),
				|| Html.text_input(
					row.field(|cell| "Your gloss for ${cell.form}"),
					"text",
					row.field(|cell| cell.guess),
					[Engine.class("cell-input"), Engine.attr("autocomplete", "off"), Engine.attr("autocapitalize", "off"), Engine.on("keydown", rows.update(|m| m))],
					rows.set_value_by(id, |m, token, gloss| Update.step(m, |x| Workspace.set_gloss(x, token, gloss))),
				),
				|| Engine.text(""),
			),
			Engine.when(row.field(|cell| cell.revealed), || Html.span_v(row.field(|cell| Corpus.display_gloss(cell.gloss)), [Engine.class("interlinear-reference")]), || Engine.text("")),
		],
	)
}

## One token of the passage view: punctuation stays attached to the word
## before it and is never a study target.
study_token : State(Page.S, Model.Model), RowRef(Page.S, WorkspaceView.Cell) -> Elem(Row(Page.S, WorkspaceView.Cell))
study_token = |session, row| {
	rows = session.lift_row()
	id = row.field(|cell| cell.id)
	Engine.element("span", [Engine.attr("style", "display: contents")], [study_token_body(rows, row, id, session)])
}

study_token_body : State(Row(Page.S, WorkspaceView.Cell), Model.Model), RowRef(Page.S, WorkspaceView.Cell), Val(Row(Page.S, WorkspaceView.Cell), U64), State(Page.S, Model.Model) -> Elem(Row(Page.S, WorkspaceView.Cell))
study_token_body = |rows, row, id, session| {
	Engine.when(
		row.field(|cell| cell.is_word),
		|| Engine.element(
			"span",
			[],
			[
				Engine.text_v(row.field(|cell| if cell.space " " else "")),
				Engine.element(
					"span",
					[Engine.class("study-token-wrap")],
					[
						Engine.element(
							"button",
							[
								Engine.class_v(row.field(|cell| "study-token${if cell.guess.trim() != "" " has-guess" else ""}${if cell.revealed " is-revealed" else ""}${if cell.open " is-open" else ""}")),
								Engine.attr("type", "button"),
								Engine.attr_v("aria-expanded", row.field(|cell| if cell.open "true" else "false")),
								Engine.on_click(rows.update_by(id, |m, token| Update.step(m, |x| Workspace.toggle_popup(x, token)))),
							],
							[Engine.text_v(row.field(|cell| cell.form))],
						),
						Engine.when(row.field(|cell| cell.open), || popup(session, row), || Engine.text("")),
					],
				),
			],
		),
		|| Html.span_v(row.field(|cell| cell.form), [Engine.class("study-punctuation")]),
	)
}

## A word's popup: its gloss (the Word tab) or the passage's translations
## (the Sentence tab), over a backdrop that closes it on phones.
popup : State(Page.S, Model.Model), RowRef(Page.S, WorkspaceView.Cell) -> Elem(Row(Page.S, WorkspaceView.Cell))
popup = |session, row| {
	rows = session.lift_row()
	model = session.val().lift_row()
	close = rows.update(|m| Update.step(m, Workspace.close_popup))
	Html.div_attrs(
		[],
		[
			Engine.element("span", [Engine.class("popup-backdrop"), Engine.attr("aria-hidden", "true"), Engine.on_click(close)], []),
			Html.div_attrs(
				[Engine.class("word-popup"), Engine.attr("role", "dialog"), Engine.attr("lang", "en"), Engine.on("click", rows.update(|m| m))],
				[
					Html.div(
						"popup-tabs",
						[
							Html.button("Word", [Engine.class_v(model.map(|m| if m.popup_tab == WordTab "popup-tab is-active" else "popup-tab")), Engine.attr("type", "button")], rows.update(|m| Update.step(m, |x| Workspace.set_popup_tab(x, WordTab)))),
							Html.button("Sentence", [Engine.class_v(model.map(|m| if m.popup_tab == SentenceTab "popup-tab is-active" else "popup-tab")), Engine.attr("type", "button")], rows.update(|m| Update.step(m, |x| Workspace.set_popup_tab(x, SentenceTab)))),
							Html.button("×", [Engine.class("popup-close"), Engine.attr("type", "button"), Html.aria_label("Close")], close),
						],
					),
					Engine.switch(
						model.map(|m| if m.popup_tab == WordTab "word" else "sentence"),
						["word", "sentence"],
						|tab| match tab {
							"word" => gloss_field(rows, row, Bool.True)
							_ =>
								Html.div(
									"popup-sentence",
									[
										# Prose is always offered here; literal only when that tool is on.
										Engine.when(model.map(|m| Tools.module_mode(LiteralModule, m.settings) != ModuleOff), || translation_field(rows, model, LiteralModule), || Engine.text("")),
										translation_field(rows, model, ProseModule),
									],
								)
						},
					),
				],
			),
		],
	)
}

## One word's gloss: the learner's answer and a deliberate reveal of the
## reference beside it (`heading` in the popup, with the lemma's page).
gloss_field : State(Row(Page.S, WorkspaceView.Cell), Model.Model), RowRef(Page.S, WorkspaceView.Cell), Bool -> Elem(Row(Page.S, WorkspaceView.Cell))
gloss_field = |rows, row, heading| {
	id = row.field(|cell| cell.id)
	Html.div(
		"gloss-field",
		[
			if heading {
				Engine.element(
					"p",
					[Engine.class("popup-form")],
					[
						Html.span_v(row.field(|cell| cell.form), [Engine.attr("lang", "grc")]),
						Engine.element("a", [Engine.class("muted popup-lemma"), Engine.attr("lang", "grc"), Engine.attr_v("href", row.field(|cell| Route.to_path(Word(cell.lemma))))], [Engine.text_v(row.field(|cell| "${Corpus.display_lemma(cell.lemma)} →"))]),
					],
				)
			} else {
				Html.span_v(row.field(|cell| cell.form), [Engine.class("gloss-row-form"), Engine.attr("lang", "grc")])
			},
			Html.text_input(
				row.field(|cell| "Your gloss for ${cell.form}"),
				"text",
				row.field(|cell| cell.guess),
				[Engine.class("gloss-input"), Engine.attr("placeholder", "Your gloss"), Engine.on("keydown", rows.update(|m| m))],
				rows.set_value_by(id, |m, token, gloss| Update.step(m, |x| Workspace.set_gloss(x, token, gloss))),
			),
			Engine.when(
				row.field(|cell| cell.revealed),
				|| Html.span_v(row.field(|cell| Corpus.display_gloss(cell.gloss)), [Engine.class("reference-answer")]),
				|| Html.button("Reveal", [Engine.class("reveal-button"), Engine.attr("type", "button"), Engine.attr("title", "Revealing before submitting marks this word as assisted")], rows.update_by(row.field(|cell| cell.word_key), |m, key| Update.step(m, |x| Workspace.reveal(x, key)))),
			),
		],
	)
}

edition : Model.Model -> Str
edition = |model|
	match model.active {
		Some(work) => work.source.edition
		None => ""
	}

## The open work's citation line (`src/Sources.elm`).
active_sources : State(Page.S, Model.Model) -> Elem(Page.S)
active_sources = |session| {
	model = session.val()
	citation = |m|
		match m.active {
			Some(work) => work.citation
			None => None
		}
	field = |pick|
		model.map(
			|m| match citation(m) {
				Some(found) => pick(found)
				None => ""
			},
		)
	Engine.when(
		model.map(|m| citation(m) != None),
		|| Engine.element(
			"p",
			[Engine.class("sources-line")],
			[
				Engine.element("span", [Engine.class("sources-label")], [Engine.text("Sources ")]),
				Page.external(field(|c| c.text.reader_url), field(|c| c.text.edition), field(|c| "${c.text.author}, ${c.text.title}")),
				Engine.text(" ("),
				Page.external(field(|c| c.text.source_url), field(|c| "${c.text.repository} ${c.text.snapshot}"), Engine.const("TEI XML")),
				Engine.text_v(field(|c| ", ${c.text.license}) · ")),
				Page.external(field(|c| c.annotations.url), Engine.const("Tokenization, lemmas, morphology, and syntax"), field(|c| "${c.annotations.name} ${c.annotations.version}")),
				Engine.text_v(field(|c| " (${c.annotations.license}) · ${c.generated.name} ${c.generated.layers}, generated with ${c.generated.model} (${c.generated.license})")),
			],
		),
		|| Engine.text(""),
	)
}

## A translation to write: the learner's draft and a deliberate reveal of the reference.
translation_field : State(ctx, Model.Model), Val(ctx, Model.Model), Tools.ModuleId -> Elem(ctx)
translation_field = |state, model, module_id| {
	literal = module_id == LiteralModule
	key = if (literal) Study.literal_key else Study.prose_key
	name = Tools.module_name(module_id)
	Html.div(
		"translation-field",
		[
			Engine.element("label", [Engine.class("field-label")], [Engine.text(name)]),
			Html.textarea(
				Engine.const(name),
				model.map(|m| if (literal) m.study.literal else m.study.prose),
				[Engine.attr("rows", "3"), Engine.attr("placeholder", "Your ${name.with_ascii_lowercased()}"), Engine.on("keydown", state.update(|m| m))],
				state.set_value(|m, text| Update.step(m, |x| if (literal) Workspace.set_literal(x, text) else Workspace.set_prose(x, text))),
			),
			Engine.when(
				model.map(|m| m.study.revealed.contains(key)),
				|| Html.p_v(model.map(|m| reference(m, literal)), [Engine.class("reference-answer")]),
				|| Html.button("Reveal", [Engine.class("reveal-button"), Engine.attr("type", "button"), Engine.attr("title", "Revealing before submitting marks this answer as assisted")], state.update(|m| Update.step(m, |x| Workspace.reveal(x, key)))),
			),
		],
	)
}

## The tools the learner chose, each with its progress on this passage.
tool_tray : State(Page.S, Model.Model) -> Elem(Page.S)
tool_tray = |session| {
	model = session.val()
	Engine.element(
		"section",
		[Engine.class("activity-area")],
		[
			Html.div("activity-heading", [Html.p("Tools", "eyebrow"), Page.button("Choose tools", "text-button", Page.act(session, show_settings))]),
			Html.div(
				"activity-tray",
				[
					Engine.each(
						model.map(|m| Tools.enabled_modules(m.settings).map(|module_id| { key: Tools.module_key(module_id), module_id, name: Tools.module_name(module_id), status: tool_status(m, module_id), active: m.active_module == Some(module_id) })),
						|tool| tool.key,
						|row| Engine.element(
							"button",
							[Engine.class_v(row.field(|tool| if tool.active "activity-chip is-active" else "activity-chip")), Engine.attr("type", "button"), Engine.on_click(session.lift_row().update_by(row.field(|tool| tool.module_id), |m, module_id| Update.step(m, |x| if x.active_module == Some(module_id) Workspace.close_workbench(x) else Workspace.open_module(x, module_id))))],
							[Engine.element("span", [Engine.class("chip-copy")], [Engine.element("strong", [], [Engine.text_v(row.field(|tool| tool.name))]), Html.span_v(row.field(|tool| tool.status), [])])],
						),
					),
				],
			),
		],
	)
}

tool_status : Model.Model, Tools.ModuleId -> Str
tool_status = |model, module_id| {
	draft_status = |text| if text.trim() == "" "Not started" else "Saved"
	match module_id {
		GlossModule => {
			words = Model.current_passage(model).tokens.keep_if(|token| Study.is_word_token(token.form))
			glossed = words.count_if(|token| (model.study.glosses.get(token.id) ?? "").trim() != "")
			"${glossed.to_str()} of ${words.len().to_str()} words"
		}
		LiteralModule => draft_status(model.study.literal)
		ProseModule => draft_status(model.study.prose)
	}
}

tool_panel : State(Page.S, Model.Model) -> Elem(Page.S)
tool_panel = |session| {
	model = session.val()
	Engine.element(
		"aside",
		[Engine.class("workbench")],
		[
			Html.div(
				"workbench-heading",
				[
					Engine.element("h2", [], [Engine.text_v(model.map(|m| active_tool(m, Tools.module_name)))]),
					Html.button("×", [Engine.class("close-workbench"), Engine.attr("type", "button"), Html.aria_label("Close tool")], Page.act(session, Workspace.close_workbench)),
				],
			),
			Engine.switch(
				model.map(|m| active_tool(m, Tools.module_key)),
				["gloss", "literal", "prose", ""],
				|key| match key {
					"gloss" => Html.div("gloss-list", [Engine.each(model.map(|m| cells(m, Bool.True)), |cell| cell.key, |row| gloss_field(session.lift_row(), row, Bool.False))])
					"literal" => translation_field(session, model, LiteralModule)
					"prose" => translation_field(session, model, ProseModule)
					_ => Engine.text("")
				},
			),
		],
	)
}

# THE CHECKPOINT

## After the checkpoint: the reference above the learner's answer under every
## word, with self-marking; words not asked this time show faded.
grading : State(Page.S, Model.Model) -> Elem(Page.S)
grading = |session| {
	model = session.val()
	Engine.element(
		"section",
		[Engine.class("reading-stage grading-stage")],
		[
			history_link(session),
			Engine.element("p", [Engine.class("reading-instruction")], [Engine.text("Compare each answer with the reference and mark it yourself. "), Engine.element("span", [], [Engine.text("Different wording can still be right.")])]),
			Html.div(
				"grading-legend",
				[
					Engine.element("span", [Engine.class("legend-reference")], [Engine.text("Reference")]),
					Engine.element("span", [Engine.class("legend-guess")], [Engine.text("Your answer")]),
					Engine.when(model.map(|m| !missed_last_time(m).is_empty()), || Engine.element("span", [Engine.class("legend-missed")], [Engine.text("Missed last time")]), || Engine.text("")),
				],
			),
			Engine.when(
				model.map(|m| !graded_words(m).is_empty()),
				|| Html.div("interlinear", [Engine.each(model.map(graded_words), |word| word.key, |row| graded_word(session, row))]),
				|| Engine.text(""),
			),
			Html.div(
				"grading-translations",
				[
					Engine.each(
						model.map(graded_translations),
						|item| item.key,
						|row| Html.div_v(
							row.field(|item| if item.was_missed "grading-card was-missed" else "grading-card"),
							[
								Engine.element("h3", [], [Engine.text_v(row.field(|item| item.greek))]),
								Html.p_v(row.field(|item| item.reference), [Engine.class("interlinear-reference")]),
								Html.p_v(row.field(|item| if item.guess.trim() == "" "No answer" else item.guess), [Engine.class_v(row.field(|item| if item.guess.trim() == "" "interlinear-guess is-empty" else "interlinear-guess"))]),
								Html.div("grading-card-actions", [mark_buttons(session, row), item_notes(row)]),
							],
						),
					),
				],
			),
		],
	)
}

missed_last_time : Model.Model -> Dict(Str, Str)
missed_last_time = |model| Study.missed_last_time(Model.active_id(model), Model.current_ref(model), model.attempts)

graded : Model.Model, Study.Item, Str, Str -> WorkspaceView.Graded
graded = |model, item, key, greek| {
	missed = missed_last_time(model)
	{
		key,
		word_key: item.key,
		greek,
		asked: Bool.True,
		reference: if item.kind == WordItem Corpus.display_gloss(item.reference) else item.reference,
		guess: item.guess,
		mark: match item.mark {
			Some(Bool.True) => "right"
			Some(Bool.False) => "wrong"
			None => ""
		},
		was_missed: missed.contains(item.key),
		revealed_early: item.revealed_early,
		last_time: match missed.get(item.key) {
			Ok(previous) => Some(previous)
			Err(_) => None
		},
		previous: "",
	}
}

## Every word stays in place; words not asked this time have no item.
graded_words : Model.Model -> List(WorkspaceView.Graded)
graded_words = |model| {
	items = Workspace.items(model)
	Study.group_words(Model.current_passage(model).tokens).map(
		|(token, suffix)| {
			key = Study.word_key(token.id)
			greek = "${token.form}${suffix}"
			match items.find_first(|item| item.key == key) {
				Ok(item) => graded(model, item, token.id.to_str(), greek)
				Err(_) => { key: token.id.to_str(), word_key: key, greek, asked: Bool.False, reference: "", guess: "", mark: "", was_missed: Bool.False, revealed_early: Bool.False, last_time: None, previous: Corpus.display_gloss(token.gloss) }
			}
		},
	)
}

graded_translations : Model.Model -> List(WorkspaceView.Graded)
graded_translations = |model|
	Workspace.items(model)
		.keep_if(|item| item.kind != WordItem)
		.map(|item| graded(model, item, item.key, if item.kind == LiteralItem "Literal translation" else "Prose translation"))

graded_word : State(Page.S, Model.Model), RowRef(Page.S, WorkspaceView.Graded) -> Elem(Row(Page.S, WorkspaceView.Graded))
graded_word = |session, row|
	Html.div_attrs([Engine.attr("style", "display: contents")], [graded_word_body(session, row)])

graded_word_body : State(Page.S, Model.Model), RowRef(Page.S, WorkspaceView.Graded) -> Elem(Row(Page.S, WorkspaceView.Graded))
graded_word_body = |session, row|
	Engine.when(
		row.field(|word| word.asked),
		|| Html.div_v(
			row.field(|word| if word.was_missed "interlinear-word was-missed" else "interlinear-word"),
			[
				Html.span_v(row.field(|word| word.greek), [Engine.class("interlinear-greek"), Engine.attr("lang", "grc")]),
				Html.span_v(row.field(|word| word.reference), [Engine.class("interlinear-reference")]),
				Html.span_v(row.field(|word| if word.guess.trim() == "" "—" else word.guess), [Engine.class_v(row.field(|word| if word.guess.trim() == "" "interlinear-guess is-empty" else "interlinear-guess"))]),
				mark_buttons(session, row),
				item_notes(row),
			],
		),
		|| Html.div(
			"interlinear-word is-settled",
			[
				Html.span_v(row.field(|word| word.greek), [Engine.class("interlinear-greek"), Engine.attr("lang", "grc")]),
				Html.span_v(row.field(|word| word.previous), [Engine.class("cell-previous")]),
				Html.button(
					"✗ Missed it",
					[Engine.class("missed-button"), Engine.attr("type", "button"), Engine.attr("title", "You weren't asked this word, but got it wrong: it will be asked next time")],
					session.lift_row().update_by(row.field(|word| word.word_key), |m, key| Update.step(m, |x| Workspace.mark(x, key, Bool.False))),
				),
			],
		),
	)

mark_buttons : State(Page.S, Model.Model), RowRef(Page.S, WorkspaceView.Graded) -> Elem(Row(Page.S, WorkspaceView.Graded))
mark_buttons = |session, row| {
	key = row.field(|word| word.word_key)
	rows = session.lift_row()
	Html.div(
		"mark-buttons",
		[
			Html.button(
				"✓",
				[Engine.class_v(row.field(|word| if word.mark == "right" "mark-button is-right" else "mark-button")), Engine.attr("type", "button"), Html.aria_label("Mark right"), Engine.test_id_v(key.map(|k| "right-${k}"))],
				rows.update_by(key, |m, k| Update.step(m, |x| Workspace.mark(x, k, Bool.True))),
			),
			Html.button(
				"✗",
				[Engine.class_v(row.field(|word| if word.mark == "wrong" "mark-button is-wrong" else "mark-button")), Engine.attr("type", "button"), Html.aria_label("Mark wrong"), Engine.test_id_v(key.map(|k| "wrong-${k}"))],
				rows.update_by(key, |m, k| Update.step(m, |x| Workspace.mark(x, k, Bool.False))),
			),
		],
	)
}

item_notes : RowRef(Page.S, WorkspaceView.Graded) -> Elem(Row(Page.S, WorkspaceView.Graded))
item_notes = |row|
	Engine.element(
		"span",
		[Engine.class("item-notes")],
		[
			Engine.when(row.field(|word| word.revealed_early), || Engine.element("span", [Engine.class("item-note")], [Engine.text("revealed")]), || Engine.text("")),
			Engine.when(
				row.field(|word| word.last_time != None),
				|| Engine.element(
					"span",
					[Engine.class("item-note missed-note"), Engine.attr_v("title", row.field(|word| "Last time: ${Model.with_default(word.last_time, "")}"))],
					[Engine.text_v(row.field(|word| last_note(Model.with_default(word.last_time, ""))))],
				),
				|| Engine.text(""),
			),
		],
	)

## Finishing is choosing a rating: FSRS schedules the passage and the next one
## opens. Each button shows when the passage would come back with that rating.
rating_buttons : State(Page.S, Model.Model) -> Elem(Page.S)
rating_buttons = |session|
	Html.div("rating-buttons", [rating_button(session, Again, "Again"), rating_button(session, Hard, "Hard"), rating_button(session, Good, "Good"), rating_button(session, Easy, "Easy")])

rating_button : State(Page.S, Model.Model), Fsrs.Rating, Str -> Elem(Page.S)
rating_button = |session, rating, label| {
	model = session.val()
	Engine.element(
		"button",
		[
			Engine.class_v(model.map(|m| if Review.suggest_rating(Workspace.items(m)) == rating "rating-button is-suggested" else "rating-button")),
			Engine.attr("type", "button"),
			Html.aria_label(label),
			Engine.on_click(Page.act(session, |m| Nav.rate(m, rating))),
		],
		[Page.strong(label), Html.span_v(model.map(|m| interval(m, rating)), [Engine.class("rating-interval"), Engine.test_id("interval-${label}")])],
	)
}

## When the current passage would come back with `rating`, at the clock.
interval : Model.Model, Fsrs.Rating -> Str
interval = |model, rating|
	match Review.preview(model.clock, Model.active_id(model), Model.current_ref(model), model.entries) {
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

footer : State(Page.S, Model.Model) -> Elem(Page.S)
footer = |session| {
	model = session.val()
	Engine.element(
		"footer",
		[Engine.class("workspace-footer")],
		[
			Engine.switch(
				model.map(|m| if m.history_open "history" else if m.study.submitted "grading" else "study"),
				["history", "grading", "study"],
				|found| match found {
					"history" =>
						Html.div_attrs(
							[Engine.attr("style", "display: contents")],
							[
								Engine.element("span", [], []),
								Html.div("checkpoint-copy", [Page.strong("Reviewing past attempts"), Engine.element("span", [], [Engine.text("Your current work on this passage is kept.")])]),
								Page.button("Back to current attempt →", "checkpoint-button", Page.act(session, Workspace.close_history)),
							],
						)
					"grading" =>
						Html.div_attrs(
							[Engine.attr("style", "display: contents")],
							[
								Page.button("← Keep working", "footer-side-button", Page.act(session, Workspace.reopen)),
								Html.div(
									"checkpoint-copy",
									[
										Engine.element("strong", [], [Engine.text_v(model.map(marked_count))]),
										Engine.element("span", [], [Engine.text("How well did you know it? The suggestion follows your marks.")]),
									],
								),
								rating_buttons(session),
							],
						)
					_ =>
						Html.div_attrs(
							[Engine.attr("style", "display: contents")],
							[
								Html.button("← Previous", [Engine.class("footer-side-button"), Engine.attr("type", "button"), Html.disabled(model.map(|m| m.sentence_index == 0))], Page.act(session, Workspace.previous)),
								Html.div("checkpoint-copy", [Page.strong("Work on any section, in any order"), Engine.element("span", [], [Engine.text("Answers save automatically in this browser.")])]),
								Page.button("Submit checkpoint →", "checkpoint-button", Page.act(session, Workspace.submit)),
							],
						)
				},
			),
		],
	)
}

# THE ENDS OF A QUEUE OR A WORK

## Nothing left in the work's queue today.
queue_done : State(Page.S, Model.Model) -> Elem(Page.S)
queue_done = |session| {
	model = session.val()
	Engine.element(
		"section",
		[Engine.class("reading-stage queue-done")],
		[
			Html.p_v(model.map(Model.work_title), [Engine.class("eyebrow")]),
			Html.h2("Done for today", ""),
			Html.p_v(model.map(done_summary), [Engine.test_id("done-summary")]),
			Html.p_v(model.map(done_next), [Engine.class("muted"), Engine.test_id("done-next")]),
			Html.div(
				"button-row",
				[
					Engine.when(model.map(|m| due_now(m) > 0), || Page.button("Review now →", "primary-button", Page.act(session, |m| Nav.start_today_in(m, Model.active_id(m)))), || Engine.text("")),
					Engine.when(model.map(Model.more_to_learn), || learn_more(session, model.map(|m| due_now(m) == 0)), || Engine.text("")),
					Page.button("Your progress", "secondary-button", Page.act(session, |m| Nav.go_route(m, Stats))),
					Page.button("Back to library", "secondary-button", Page.act(session, show_library)),
				],
			),
		],
	)
}

learn_more : State(Page.S, Model.Model), Val(Page.S, Bool) -> Elem(Page.S)
learn_more = |session, primary|
	Html.button_v(
		session.val().map(|m| "Learn ${Model.learn_more_step(m).to_str()} more →"),
		[Engine.class_v(primary.map(|p| if p "primary-button" else "secondary-button")), Engine.attr("type", "button")],
		Page.act(session, Nav.learn_more),
	)

## Short relearning steps fall due while the panel is open.
due_now : Model.Model -> U64
due_now = |model|
	match Model.today_queue(model) {
		Some(queue) => queue.due.len()
		None => 0
	}

done_summary : Model.Model -> Str
done_summary = |model| {
	today = model.attempts.keep_if(|attempt| attempt.work == Model.active_id(model) and attempt.finished_at >= Review.start_of_day(model.clock))
	summary = Study.stats(today)
	graded_text = "${today.len().to_str()}${Model.plural(today.len(), " passage", " passages")} graded today"
	if summary.judged > 0 "${graded_text}, ${percent(summary.right, summary.judged)} of marked answers right." else "${graded_text}."
}

done_next : Model.Model -> Str
done_next = |model| {
	due = due_now(model)
	limit = "New passages: up to ${model.new_per_day.to_str()} a day."
	match (due, Review.due_later(model.clock, Model.active_id(model), model.entries)) {
		(0, Some(time)) => "Next review due in ${Review.interval_label(model.clock, time)}. ${limit}"
		(0, None) => "No reviews scheduled yet. ${limit}"
		_ => "${due.to_str()}${Model.plural(due, " review is", " reviews are")} due now."
	}
}

## After grading the last passage of a work outside a session.
work_finished : State(Page.S, Model.Model) -> Elem(Page.S)
work_finished = |session| {
	model = session.val()
	Engine.element(
		"section",
		[Engine.class("reading-stage queue-done")],
		[
			Html.p_v(model.map(Model.work_title), [Engine.class("eyebrow")]),
			Engine.element("h2", [], [Engine.text_v(model.map(|m| "You've finished ${Model.work_title(m)}"))]),
			Html.p_v(
				model.map(
					|m| {
						due = due_now(m)
						match (due, Review.due_later(m.clock, Model.active_id(m), m.entries)) {
							(0, Some(time)) => "That was the last passage. Its next review is due in ${Review.interval_label(m.clock, time)}."
							(0, None) => "That was the last passage."
							_ => "That was the last passage. ${due.to_str()}${Model.plural(due, " review is", " reviews are")} due now."
						}
					},
				),
				[Engine.class("muted")],
			),
			Html.div(
				"button-row",
				[
					Html.button_v(model.map(|m| if due_now(m) > 0 "Review now →" else "Study this work →"), [Engine.class("primary-button"), Engine.attr("type", "button")], Page.act(session, |m| Nav.start_today_in(m, Model.active_id(m)))),
					Page.button("Your progress", "secondary-button", Page.act(session, |m| Nav.go_route(m, Stats))),
					Page.button("Back to library", "secondary-button", Page.act(session, show_library)),
				],
			),
		],
	)
}

percent : U64, U64 -> Str
percent = |part, whole| if whole == 0 "—" else "${(F64.to_i64_try(FsrsMath.round(part.to_f64() * 100.0 / whole.to_f64())) ?? 0).to_str()}%"

# PAST ATTEMPTS

## One attempt at the passage, compared with the one before it.
HistoryEntry : {
	key : Str,
	finished_at : I64,
	selected : Bool,
	date : Str,
	right : Str,
	wrong : Str,
	unmarked : Str,
	change : Str,
	missed : List(Chip),
	newly_missed : List(Chip),
	recovered : List(Chip),
	items : List(HistoryItem),
}

Chip : { key : Str, label : Str, lang : Str }

HistoryItem : { key : Str, class : Str, label : Str, lang : Str, reference : Str, guess : Str, guess_class : Str, mark : Str, revealed : Bool }

## Every finished attempt at the passage, newest first.
history : State(Page.S, Model.Model) -> Elem(Page.S)
history = |session| {
	model = session.val()
	Engine.element(
		"section",
		[Engine.class("reading-stage history-stage")],
		[
			Html.div(
				"history-heading",
				[
					Html.div("", [Html.p_v(model.map(|m| "${Model.work_title(m)} ${Model.current_label(m)}"), [Engine.class("eyebrow")]), Html.h2("Past attempts", "")]),
					Page.button("← Back to current attempt", "secondary-button", Page.act(session, Workspace.close_history)),
				],
			),
			Engine.when(model.map(|m| Workspace.current_attempts(m).is_empty()), || Html.p("No past attempts at this passage yet.", "muted"), || Engine.text("")),
			Engine.when(
				model.map(|m| Workspace.current_attempts(m).len() >= 2),
				|| Html.div(
					"history-trend",
					[
						Engine.element("p", [], [Engine.element("span", [Engine.class("muted")], [Engine.text("Right, oldest to newest: ")]), Engine.element("strong", [], [Engine.text_v(model.map(|m| trend(m, |t| t.right)))])]),
						Engine.element("p", [], [Engine.element("span", [Engine.class("muted")], [Engine.text("Wrong, oldest to newest: ")]), Engine.element("strong", [], [Engine.text_v(model.map(|m| trend(m, |t| t.wrong)))])]),
						Engine.when(
							model.map(|m| !missed_every_time(m).is_empty()),
							|| Engine.element("p", [], [Engine.element("span", [Engine.class("muted")], [Engine.text("Missed every time: ")]), chips(model.map(missed_every_time), Bool.False)]),
							|| Engine.text(""),
						),
					],
				),
				|| Engine.text(""),
			),
			Engine.element(
				"ol",
				[Engine.class("history-list")],
				[Engine.each(model.map(history_entries), |entry| entry.key, |row| history_entry(session, row))],
			),
		],
	)
}

trend : Model.Model, (Study.Tally -> U64) -> Str
trend = |model, pick| Str.join_with(Workspace.current_attempts(model).fold([], |older, attempt| older.prepend(attempt)).map(|attempt| pick(Study.tally(attempt)).to_str()), " → ")

missed_every_time : Model.Model -> List(Chip)
missed_every_time = |model| {
	attempts = Workspace.current_attempts(model)
	if attempts.len() < 2 {
		[]
	} else {
		latest = match attempts.first() {
			Ok(attempt) => Study.missed(attempt)
			Err(_) => []
		}
		latest
			.keep_if(|item| attempts.all(|attempt| Study.missed(attempt).any(|other| other.key == item.key)))
			.map(chip)
	}
}

chip : Study.Item -> Chip
chip = |item| { key: item.key, label: item_label(item), lang: item_lang(item) }

item_label : Study.Item -> Str
item_label = |item|
	match item.kind {
		WordItem => item.form
		LiteralItem => "Literal translation"
		ProseItem => "Prose translation"
	}

item_lang : Study.Item -> Str
item_lang = |item| if item.kind == WordItem "grc" else "en"

history_entries : Model.Model -> List(HistoryEntry)
history_entries = |model| {
	attempts = Workspace.current_attempts(model)
	attempts.map_with_index(
		|attempt, index| {
			counts = Study.tally(attempt)
			missed = Study.missed(attempt)
			older = attempts.get(index + 1)
			change = |label, now, before|
				if now == before {
					Err({})
				} else if now > before {
					Ok("+${(now - before).to_str()} ${label}")
				} else {
					Ok("−${(before - now).to_str()} ${label}")
				}
			previous_missed = match older {
				Ok(previous) => Study.missed(previous)
				Err(_) => []
			}
			{
				key: attempt.finished_at.to_str(),
				finished_at: attempt.finished_at,
				selected: model.history_attempt == Some(attempt.finished_at),
				date: Model.format_date(model, attempt.finished_at),
				right: "${counts.right.to_str()} right",
				wrong: "${counts.wrong.to_str()} wrong",
				unmarked: if counts.unmarked == 0 "" else "${counts.unmarked.to_str()} unmarked",
				change: match older {
					Ok(previous) => {
						before = Study.tally(previous)
						changes = [change("right", counts.right, before.right), change("wrong", counts.wrong, before.wrong)].keep_oks(|found| found)
						if changes.is_empty() "Same as the attempt before" else "${Str.join_with(changes, ", ")} since the attempt before"
					}
					Err(_) => "First attempt"
				},
				missed: missed.map(chip),
				newly_missed: if older.is_err() [] else missed.keep_if(|item| !previous_missed.any(|other| other.key == item.key)).map(chip),
				recovered: previous_missed.keep_if(|item| !missed.any(|other| other.key == item.key)).map(chip),
				items: attempt.items.map(
					|item| {
						empty = item.guess.trim() == ""
						{
							key: item.key,
							class: "history-item${if item.mark == Some(Bool.True) " is-right" else ""}${if item.mark == Some(Bool.False) " is-wrong" else ""}",
							label: item_label(item),
							lang: item_lang(item),
							reference: if item.kind == WordItem Corpus.display_gloss(item.reference) else item.reference,
							guess: if (empty) "—" else item.guess,
							guess_class: if (empty) "interlinear-guess is-empty" else "interlinear-guess",
							mark: match item.mark {
								Some(Bool.True) => "✓ right"
								Some(Bool.False) => "✗ wrong"
								None => "unmarked"
							},
							revealed: item.revealed_early,
						}
					},
				),
			}
		},
	)
}

history_entry : State(Page.S, Model.Model), RowRef(Page.S, HistoryEntry) -> Elem(Row(Page.S, HistoryEntry))
history_entry = |session, row|
	Engine.element(
		"li",
		[Engine.class_v(row.field(|entry| if entry.selected "history-entry is-selected" else "history-entry"))],
		[
			Engine.element(
				"button",
				[
					Engine.class("history-summary"),
					Engine.attr("type", "button"),
					Engine.attr_v("aria-expanded", row.field(|entry| if entry.selected "true" else "false")),
					Engine.on_click(session.lift_row().update_by(row.field(|entry| entry.finished_at), |m, at| Update.step(m, |x| Workspace.select_history_attempt(x, at)))),
				],
				[
					Html.span_v(row.field(|entry| entry.date), [Engine.class("history-date")]),
					Engine.element(
						"span",
						[Engine.class("history-counts")],
						[
							Html.span_v(row.field(|entry| entry.right), [Engine.class("count-right")]),
							Html.span_v(row.field(|entry| entry.wrong), [Engine.class("count-wrong")]),
							Engine.when(row.field(|entry| entry.unmarked != ""), || Html.span_v(row.field(|entry| entry.unmarked), [Engine.class("muted")]), || Engine.text("")),
						],
					),
					Html.span_v(row.field(|entry| entry.change), [Engine.class("history-change")]),
				],
			),
			Html.div(
				"history-missed",
				[
					Engine.when(
						row.field(|entry| entry.missed.is_empty()),
						|| Engine.element("span", [Engine.class("muted")], [Engine.text("Nothing marked wrong.")]),
						|| Engine.element("span", [], [Engine.element("span", [Engine.class("muted")], [Engine.text("Missed: ")]), chips(row.field(|entry| entry.missed), Bool.False)]),
					),
				],
			),
			Engine.when(
				row.field(|entry| !entry.newly_missed.is_empty() or !entry.recovered.is_empty()),
				|| Html.div(
					"history-missed",
					[
						Engine.when(row.field(|entry| !entry.newly_missed.is_empty()), || Engine.element("span", [], [Engine.element("span", [Engine.class("muted")], [Engine.text("Newly missed: ")]), chips(row.field(|entry| entry.newly_missed), Bool.False)]), || Engine.text("")),
						Engine.when(row.field(|entry| !entry.recovered.is_empty()), || Engine.element("span", [], [Engine.element("span", [Engine.class("muted")], [Engine.text("No longer missed: ")]), chips(row.field(|entry| entry.recovered), Bool.True)]), || Engine.text("")),
					],
				),
				|| Engine.text(""),
			),
			Engine.when(
				row.field(|entry| entry.selected),
				|| Html.div(
					"history-detail",
					[
						Engine.each(
							row.field(|entry| entry.items),
							|item| item.key,
							|item| Html.div_v(
								item.field(|found| found.class),
								[
									Html.span_v(item.field(|found| found.label), [Engine.class("history-item-label"), Engine.attr_v("lang", item.field(|found| found.lang))]),
									Html.span_v(item.field(|found| found.reference), [Engine.class("interlinear-reference")]),
									Html.span_v(item.field(|found| found.guess), [Engine.class_v(item.field(|found| found.guess_class))]),
									Engine.element(
										"span",
										[Engine.class("history-mark")],
										[
											Engine.text_v(item.field(|found| found.mark)),
											Engine.when(item.field(|found| found.revealed), || Engine.element("span", [Engine.class("item-note")], [Engine.text("revealed")]), || Engine.text("")),
										],
									),
								],
							),
						),
					],
				),
				|| Engine.text(""),
			),
		],
	)

chips : Val(ctx, List(Chip)), Bool -> Elem(ctx)
chips = |found, recovered|
	Engine.element(
		"span",
		[Engine.class(if (recovered) "history-chips is-recovered" else "history-chips")],
		[Engine.each(found, |item| item.key, |row| Html.span_v(row.field(|item| item.label), [Engine.class("history-chip"), Engine.attr_v("lang", row.field(|item| item.lang))]))],
	)

active_tool : Model.Model, (Tools.ModuleId -> Str) -> Str
active_tool = |model, describe|
	match model.active_module {
		Some(module_id) => describe(module_id)
		None => ""
	}

reference : Model.Model, Bool -> Str
reference = |model, literal| {
	passage = Model.current_passage(model)
	if (literal) passage.literal else passage.prose
}

last_note : Str -> Str
last_note = |previous| "last: ${if previous.trim() == "" "—" else previous}"

marked_count : Model.Model -> Str
marked_count = |model| {
	found = Workspace.items(model)
	"${found.count_if(|item| item.mark != None).to_str()} of ${found.len().to_str()} marked"
}
