import pf.Engine exposing [Elem, Handler, Row, RowRef, State]
import pf.Html
import Model
import Page
import Reader
import Update
import WorkspaceView

## Reading a work, ported from `viewReader` and the views it uses in
## `src/Main.elm`: the reader's bar, its layer switches, and every passage of
## the work with its glosses, morphology and translation, or the Greek alone
## with a word's gloss on tap.
##
## Workaround: roc-signals 0.5.0 cannot measure layout or scroll
## (https://github.com/lukewilliamboswell/roc-signals/issues/204, closed in
## favour of #211, #213 and #214; roc-issues archive/RS-005-layout-measurement),
## so where the Elm app scrolls the current passage to the top of the reader,
## this one focuses it, which scrolls it into view. Scroll it like the Elm app
## once the app is on a release that has those.
ReaderView := [].{

	## `toggle_theme` and `theme_action` are the header's theme switch, which the reader's bar repeats.
	view : State(Page.S, Model.Model), Handler(Page.S), (Model.Model -> Str) -> Elem(Page.S)
	view = |session, toggle_theme, theme_action| {
		model = session.signal()
		Engine.element(
			"main",
			[Engine.class("reader-page")],
			[
				Engine.element(
					"header",
					[Engine.class("reader-bar")],
					[
						Html.button("←", [Engine.class("icon-button"), Engine.attr("type", "button"), Html.aria_label("Back to library")], Page.act(session, Reader.show_library)),
						Html.div(
							"reader-bar-title",
							[
								Html.span_s(model.map(Model.work_title), [Engine.class("context-work")]),
								Html.span_s(model.map(Reader.position), [Engine.class("reader-position")]),
							],
						),
						Html.button("‹", [Engine.class("icon-button reader-prev"), Engine.attr("type", "button"), Html.disabled(model.map(|m| m.sentence_index == 0)), Html.aria_label("Previous passage (k)")], step_by(session, -1)),
						WorkspaceView.citation_picker(session),
						Html.button("›", [Engine.class("icon-button reader-next"), Engine.attr("type", "button"), Html.disabled(model.map(|m| m.sentence_index + 1 >= m.passages.len())), Html.aria_label("Next passage (j)")], step_by(session, 1)),
						Engine.element(
							"button",
							[Engine.class("icon-button reader-theme"), Engine.attr("type", "button"), Html.aria_label_s(model.map(theme_action)), Engine.on_click(toggle_theme)],
							[Engine.text_s(model.map(|m| if m.dark "☀" else "☾"))],
						),
						Engine.element(
							"button",
							[Engine.class("secondary-button reader-study"), Engine.attr("type", "button"), Engine.on_click(Page.act(session, Reader.show_workspace))],
							[Engine.text("Study"), Engine.element("span", [Engine.class("wide-only")], [Engine.text(" this passage")])],
						),
					],
				),
				layers(session),
				Engine.element(
					"div",
					[Engine.attr("id", "reader-scroll"), Engine.class("reader-scroll")],
					[
						Engine.element(
							"article",
							[Engine.class("reader-text"), Engine.attr("lang", "grc")],
							[Engine.each(model.map(Reader.sentences), |sentence| sentence.key, |row| sentence_row(session, row))],
						),
						Engine.element(
							"div",
							[Engine.class("reader-end")],
							[Engine.text_s(model.map(|m| "End of ${Model.work_title(m)} in this edition.")), WorkspaceView.active_sources(session)],
						),
					],
				),
				# Brings the current passage into view when the reader opens and
				# whenever another passage becomes current (see the note above).
				Engine.watch(model.map(|m| m.sentence_index), |_| [Focus("reader-current")], Engine.ignore({})),
				# The focused passage goes with the reader; give the keys back to the shell (see View.page).
				Engine.on_cleanup("reader-focus", Engine.const({}), |_| [Focus("shell")]),
			],
		)
	}
}

## Switches for what the reader shows with each passage (`viewReaderLayers`).
layers : State(Page.S, Model.Model) -> Elem(Page.S)
layers = |session| {
	model = session.signal()
	toggle = |layer, label, on|
		Engine.element(
			"button",
			[
				Engine.class_s(model.map(|m| if on(m.reader_layers) "layer-toggle is-on" else "layer-toggle")),
				Engine.attr("type", "button"),
				Engine.attr_s("aria-pressed", model.map(|m| if on(m.reader_layers) "true" else "false")),
				Engine.on_click(Page.act(session, |m| Reader.toggle_layer(m, layer))),
			],
			[Engine.text(label)],
		)
	Engine.element(
		"div",
		[Engine.class("reader-layers"), Engine.attr("role", "group"), Html.aria_label("Show with the Greek")],
		[
			toggle(GlossLayer, "Glosses", |l| l.glosses),
			toggle(MorphologyLayer, "Morphology", |l| l.morphology),
			toggle(TranslationLayer, "Translation", |l| l.translation),
		],
	)
}

## One passage (`viewReaderSentence`). Only the current one carries the
## reference the reader focuses, so it is drawn by its own branch.
sentence_row : State(Page.S, Model.Model), RowRef(Page.S, Reader.Sentence) -> Elem(Row(Page.S, Reader.Sentence))
sentence_row = |session, row|
	Engine.element(
		"div",
		[Engine.attr("style", "display: contents")],
		[
			Engine.when(
				row.field(|sentence| sentence.current),
				|| sentence(session, row, [Engine.ref("reader-current")]),
				|| sentence(session, row, []),
			),
		],
	)

sentence : State(Page.S, Model.Model), RowRef(Page.S, Reader.Sentence), List(Engine.Attr(Row(Page.S, Reader.Sentence))) -> Elem(Row(Page.S, Reader.Sentence))
sentence = |session, row, extra| {
	rows = session.lift_row()
	Engine.element(
		"section",
		[
			Engine.attr_s("id", row.field(|s| "passage-${(s.index + 1).to_str()}")),
			Engine.test_id_s(row.field(|s| "passage-${(s.index + 1).to_str()}")),
			Engine.class_s(row.field(|s| if s.current "reader-sentence is-current" else "reader-sentence")),
			Engine.attr("tabindex", "-1"),
			Engine.attr("style", "outline: none"),
		].concat(extra),
		[
			Engine.element(
				"button",
				[
					Engine.class_s(row.field(|s| if s.revealed "reader-marker is-open" else "reader-marker")),
					Engine.attr("type", "button"),
					Engine.on_click(rows.update_by(row.field(|s| s.index), |m, index| Update.step(m, |x| Reader.toggle_translation(x, index)))),
					Html.aria_label_s(row.field(|s| "${s.label}: ${if s.revealed "hide" else "show"} translation")),
					Engine.attr_s("aria-expanded", row.field(|s| if s.revealed "true" else "false")),
				],
				[Engine.text_s(row.field(|s| s.label))],
			),
			Engine.when(
				row.field(|s| s.interlinear),
				|| Engine.element("div", [Engine.class("reader-interlinear")], [Engine.each(row.field(|s| s.words), |w| w.key, word)]),
				|| Engine.element("p", [Engine.class("reader-greek")], [Engine.each(row.field(|s| s.tokens), |t| t.key, |token_row| token(rows, token_row))]),
			),
			Engine.when(
				row.field(|s| s.translation),
				|| Engine.element(
					"div",
					[Engine.class("reader-translation"), Engine.attr("lang", "en")],
					[
						Engine.element("p", [], [Engine.text_s(row.field(|s| s.prose))]),
						Engine.when(row.field(|s| s.literal != ""), || Html.p_s(row.field(|s| s.literal), [Engine.class("reader-literal")]), || Engine.text("")),
					],
				),
				|| Engine.text(""),
			),
		],
	)
}

## A word with its following punctuation, and the gloss and morphology beneath it (`viewReaderWord`).
word : RowRef(Row(Page.S, Reader.Sentence), Reader.Word) -> Elem(Row(Row(Page.S, Reader.Sentence), Reader.Word))
word = |row|
	Engine.element(
		"span",
		[Engine.class("reader-word")],
		[
			Html.span_s(row.field(|w| w.greek), [Engine.class("reader-word-greek")]),
			Engine.when(row.field(|w| w.gloss != None), || Html.span_s(row.field(|w| Model.with_default(w.gloss, "")), [Engine.class("reader-word-gloss"), Engine.attr("lang", "en")]), || Engine.text("")),
			Engine.when(row.field(|w| w.morphology != None), || Html.span_s(row.field(|w| Model.with_default(w.morphology, "")), [Engine.class("reader-word-morph"), Engine.attr("lang", "en")]), || Engine.text("")),
		],
	)

## A token of the plain Greek, its gloss shown on tap (`viewReaderToken`).
token : State(Row(Page.S, Reader.Sentence), Model.Model), RowRef(Row(Page.S, Reader.Sentence), Reader.Token) -> Elem(Row(Row(Page.S, Reader.Sentence), Reader.Token))
token = |rows, row|
	Engine.element(
		"span",
		[Engine.attr("style", "display: contents")],
		[
			Engine.text_s(row.field(|t| if t.space " " else "")),
			Engine.element(
				"button",
				[
					Engine.class_s(row.field(|t| if t.open "reader-token is-open" else "reader-token")),
					Engine.attr("type", "button"),
					Engine.on_click(rows.lift_row().update_by(row.field(|t| (t.sentence, t.id)), |m, (sentence_index, id)| Update.step(m, |x| Reader.tap_token(x, sentence_index, id)))),
				],
				[
					Engine.text_s(row.field(|t| t.form)),
					Engine.when(
						row.field(|t| t.open),
						|| Html.span_s(row.field(|t| t.gloss), [Engine.class("reader-gloss"), Engine.attr("role", "tooltip"), Engine.attr("lang", "en")]),
						|| Engine.text(""),
					),
				],
			),
		],
	)

step_by : State(Page.S, Model.Model), I64 -> Handler(Page.S)
step_by = |session, delta| Page.act(session, |m| Reader.step(m, delta))
