import pf.Engine exposing [Elem, Handler, In, Root, Row, RowRef, State, Val]
import pf.Html
import fsrs.Fsrs
import Session

## The library and review screens on roc-signals: the Elm app's home page
## (without its Today panel) and its study session for one work, with the same
## markup and stylesheet. The session is one state (Session);
## this module is its view and effect sites: the preload downloads, the
## `<lyceum-store>` element that carries storage requests and results (see
## Store), a clock refresh, and the URL.
ReviewApp := [].{
	S : In(Root, Session.Model)

	W : Row(S, Session.Word)

	program : Engine.Program
	program = Engine.program_boot({ storage_keys: [], max_inflight: 32 }, |boot| Engine.state(Session.init(boot.url), ReviewApp.page))

	page : State(S, Session.Model) -> Elem(S)
	page = |session| {
		model = session.val()
		Html.div_v(
			model.map(|m| if (m.dark) "app-shell dark-theme" else "app-shell light-theme"),
			[
				header(session),
				Engine.when(
					model.map(|m| m.notice != ""),
					|| Html.div_attrs(
						[Engine.class("notice"), Engine.attr("role", "status")],
						[
							Html.span_v(model.map(|m| m.notice), []),
							Html.button("×", [Engine.attr("type", "button"), Html.aria_label("Dismiss message")], session.update(|m| { ..m, notice: "" })),
						],
					),
					|| Engine.text(""),
				),
				Engine.switch(
					model.map(Session.phase_name),
					["loading", "choosing", "answering", "grading", "done", "failed"],
					|phase| match phase {
						"choosing" => library(session)
						"loading" => Engine.element("main", [Engine.class("page")], [Html.p_v(model.map(|m| if m.work == "" "Loading the library…" else "Loading the passages and your progress…"), [Engine.class("muted")])])
						"failed" => Engine.element("main", [Engine.class("page")], [Html.p_v(model.map(problem), [Engine.class("notice"), Engine.test_id("problem")])])
						_ => workspace(session, phase)
					},
				),
				Engine.element(
					"lyceum-store",
					[Engine.attr("hidden", "true"), Engine.test_id("store"), Engine.attr_v("data-request", model.map(|m| m.outbox)), Engine.on("change", session.set_value(Session.receive))],
					[],
				),
				Engine.watch(Engine.const("/preload/corpora.json"), download, session.on_result(|m, _, res| Session.receive_manifest(m, Engine.http_text(res)))),
				Engine.watch(model.map(Session.corpus_url), download, session.on_result(|m, url, res| Session.receive_corpus(m, url, Engine.http_text(res)))),
				Engine.watch(model.map(Session.units_url), download, session.on_result(|m, url, res| Session.receive_units(m, url, Engine.http_text(res)))),
				Engine.watch(
					Engine.const({}),
					|_| [Popstate, Interval(15000)],
					session.on_result(
						|m, _, res| match res {
							Location(url) => Session.navigate(m, url)
							Fired => Session.refresh_clock(m)
							_ => m
						},
					),
				),
			],
		)
	}
}

## A GET of a preload file, revalidated as the Elm app does; "" asks for nothing.
download : Str -> List(Engine.Req)
download = |url|
	if url == "" {
		[]
	} else {
		[Http({ method: "GET", url, headers: [("Cache-Control", "no-cache")], body: "", timeout_ms: 0 })]
	}

problem : Session.Model -> Str
problem = |model|
	match Session.phase(model) {
		Failed(text) => text
		_ => ""
	}

strong : Str -> Elem(ctx)
strong = |text| Engine.element("strong", [], [Engine.text(text)])

header : State(ReviewApp.S, Session.Model) -> Elem(ReviewApp.S)
header = |session| {
	dark = session.val().map(|m| m.dark)
	Engine.element(
		"header",
		[Engine.class("app-header")],
		[
			plain_link("brand-button", "#/", "Lyceum Study library", [Engine.element("span", [Engine.class("brand-word")], [Engine.text("Lyceum Study")])]),
			# Home is this app's library; Progress and What's new are still the Elm app's.
			Engine.element(
				"nav",
				[Engine.class("global-nav"), Html.aria_label("Primary navigation")],
				[
					Html.link("Home", "#/", [Engine.class_v(session.val().map(|m| if m.work == "" "global-nav-button is-active" else "global-nav-button"))]),
					Html.link("Progress", "/#/stats", [Engine.class("global-nav-button")]),
					Html.link("What's new", "/#/whats-new", [Engine.class("global-nav-button")]),
				],
			),
			Html.div(
				"header-actions",
				[
					Engine.element(
						"button",
						[
							Engine.class("theme-button"),
							Engine.attr("type", "button"),
							Html.aria_label_v(dark.map(theme_action)),
							Engine.attr_v("aria-pressed", dark.map(|d| if (d) "true" else "false")),
							Engine.attr_v("title", dark.map(theme_action)),
							Engine.on_click(session.update(Session.toggle_theme)),
						],
						[
							Html.span_v(dark.map(|d| if (d) "☀" else "☾"), [Engine.attr("aria-hidden", "true")]),
							Html.span_v(dark.map(|d| if (d) "Light" else "Dark"), [Engine.class("theme-label")]),
						],
					),
				],
			),
		],
	)
}

## A link where the Elm app has a button: the button's look, without link styling.
plain_link : Str, Str, Str, List(Elem(ctx)) -> Elem(ctx)
plain_link = |class, href, name, children| Engine.element("a", [Engine.class(class), Engine.attr("href", href), Engine.attr("style", "color: inherit; text-decoration: none"), Html.aria_label(name)], children)

theme_action : Bool -> Str
theme_action = |dark| if (dark) "Use light theme" else "Use dark theme"

## No work in the URL: the library page, as the Elm app's home without its
## Today panel. Read opens the Elm app's reader; Study opens this app's review.
library : State(ReviewApp.S, Session.Model) -> Elem(ReviewApp.S)
library = |session| {
	model = session.val()
	Engine.element(
		"main",
		[Engine.class("page library-page")],
		[
			Engine.when(
				model.map(|m| !Session.working_rows(m).is_empty()),
				|| Engine.element(
					"section",
					[Engine.class("home-section"), Html.aria_label("Working on")],
					[Html.h2("Working on", ""), work_rows("working", model.map(Session.working_rows))],
				),
				|| Engine.text(""),
			),
			Engine.element(
				"section",
				[Engine.class("home-section"), Html.aria_label("Library")],
				[
					Html.div(
						"library-head",
						[
							Html.h2("Library", ""),
							Html.text_input(
								Engine.const("Search the library"),
								"search",
								model.map(|m| m.search),
								[Engine.class("library-search"), Engine.attr("placeholder", "Search title, author, or edition")],
								session.set_value(Session.set_search),
							),
							Html.select(
								Engine.const("Sort the library"),
								model.map(|m| m.sort),
								[Engine.class("library-sort")],
								[Html.option("recent", "Recently studied"), Html.option("title", "Title"), Html.option("short", "Shortest first")],
								session.set_value(Session.set_sort),
							),
						],
					),
					Engine.when(
						model.map(|m| Session.library_rows(m).is_empty()),
						|| Html.p("No works match.", "muted"),
						|| work_rows("library", model.map(Session.library_rows)),
					),
				],
			),
		],
	)
}

## Works as compact rows: progress, Read and Study, and the edition and source
## credits on request. Test ids start with `section`: `<section>-<position>` for
## a row's title, `<section>:<work>` for its progress line, and `:read` and `:study` after that
## for its links.
work_rows : Str, Val(ReviewApp.S, List(Session.WorkRow)) -> Elem(ReviewApp.S)
work_rows = |section, rows|
	Html.div(
		"work-rows",
		[
			Engine.each(
				rows,
				|work| work.id,
				|row| {
					id = row.key()
					Html.div(
						"work-row",
						[
							Html.div(
								"work-row-main",
								[
									Engine.element("h3", [Engine.class("work-row-title"), Engine.test_id_v(row.field(|work| "${section}-${work.position}"))], [Engine.text_v(row.field(|work| work.title))]),
									Html.p_v(row.field(|work| work.meta), [Engine.class("work-row-meta"), Engine.test_id_v(id.map(|work| "${section}:${work}"))]),
									Engine.element(
										"details",
										[Engine.class("work-row-sources")],
										[
											Engine.element("summary", [], [Engine.text("Edition & sources")]),
											Html.p_v(row.field(|work| work.edition), [Engine.class("greek-subtitle")]),
											Engine.when(row.field(|work| work.has_sources), || sources(row), || Engine.text("")),
										],
									),
								],
							),
							Html.div(
								"work-row-actions",
								[
									Engine.element("a", [Engine.class("secondary-button"), Engine.attr_v("href", id.map(|work| "/#/${work}/read")), Engine.attr("style", "text-decoration: none"), Engine.test_id_v(id.map(|work| "${section}:${work}:read"))], [Engine.text("Read")]),
									Engine.element("a", [Engine.class("primary-button"), Engine.attr_v("href", id.map(|work| "#/${work}")), Engine.attr("style", "text-decoration: none"), Engine.test_id_v(id.map(|work| "${section}:${work}:study"))], [Engine.text_v(row.field(|work| work.action))]),
								],
							),
						],
					)
				},
			),
		],
	)

## The compact attribution line of `src/Sources.elm`.
sources : RowRef(ReviewApp.S, Session.WorkRow) -> Elem(Row(ReviewApp.S, Session.WorkRow))
sources = |row|
	Engine.element(
		"p",
		[Engine.class("sources-line")],
		[
			Engine.element("span", [Engine.class("sources-label")], [Engine.text("Sources ")]),
			external(row.field(|work| work.reader_url), row.field(|work| work.source_edition), row.field(|work| work.source_title)),
			Engine.text(" ("),
			external(row.field(|work| work.source_url), row.field(|work| work.snapshot), Engine.const("TEI XML")),
			Engine.text_v(row.field(|work| work.after_source)),
			external(row.field(|work| work.annotations_url), Engine.const("Tokenization, lemmas, morphology, and syntax"), row.field(|work| work.annotations)),
			Engine.text_v(row.field(|work| work.after_annotations)),
		],
	)

## A link to another site, in a new tab so the session stays open.
external : Val(ctx, Str), Val(ctx, Str), Val(ctx, Str) -> Elem(ctx)
external = |url, description, label|
	Engine.element("a", [Engine.attr_v("href", url), Engine.attr("target", "_blank"), Engine.attr("rel", "noopener"), Engine.attr_v("title", description)], [Engine.text_v(label)])

## The review of the open work: its context bar, the stage of the current
## phase, and the footer that moves between phases.
workspace : State(ReviewApp.S, Session.Model), Str -> Elem(ReviewApp.S)
workspace = |session, phase| {
	model = session.val()
	Engine.element(
		"main",
		[Engine.class("workspace-page")],
		[
			Html.div(
				"work-context-bar",
				[
					Html.div(
						"context-title",
						[
							plain_link("icon-button", "#/", "Back to library", [Engine.text("←")]),
							Html.div(
								"",
								[
									Html.span_v(model.map(Session.title), [Engine.class("context-work")]),
									Html.span_v(model.map(Session.passage_label), [Engine.class("context-division"), Engine.test_id("passage")]),
								],
							),
						],
					),
					if phase == "done" {
						Engine.text("")
					} else {
						Engine.element(
							"span",
							[Engine.class("queue-status")],
							[
								Html.span_v(model.map(Session.queue_kind), [Engine.class("queue-kind"), Engine.test_id("queue-kind")]),
								Html.span_v(model.map(Session.queue_left), [Engine.test_id("queue-left")]),
							],
						)
					},
				],
			),
			Html.div(
				"workspace-grid",
				[
					match phase {
						"answering" => answering(session)
						"grading" => grading(session)
						_ => done(session)
					},
				],
			),
			match phase {
				"answering" => Engine.element(
					"footer",
					[Engine.class("workspace-footer")],
					[
						Engine.element("span", [], []),
						Html.div("checkpoint-copy", [strong("Work on any section, in any order"), Engine.element("span", [], [Engine.text("Your answers stay on this page until you rate the passage.")])]),
						Html.button("Submit checkpoint →", [Engine.class("checkpoint-button"), Engine.attr("type", "button")], session.update(Session.submit)),
					],
				)
				"grading" => Engine.element(
					"footer",
					[Engine.class("workspace-footer")],
					[
						Html.button("← Keep working", [Engine.class("footer-side-button"), Engine.attr("type", "button")], session.update(Session.reopen)),
						Html.div(
							"checkpoint-copy",
							[
								Engine.element("strong", [], [Engine.text_v(model.map(Session.marked_count))]),
								Engine.element("span", [], [Engine.text("How well did you know it? The suggestion follows your marks.")]),
							],
						),
						Html.div("rating-buttons", [rating_button(session, Again, "Again"), rating_button(session, Hard, "Hard"), rating_button(session, Good, "Good"), rating_button(session, Easy, "Easy")]),
					],
				)
				_ => Engine.text("")
			},
		],
	)
}

## The passage to answer: a gloss under each word.
answering : State(ReviewApp.S, Session.Model) -> Elem(ReviewApp.S)
answering = |session| {
	model = session.val()
	Engine.element(
		"section",
		[Engine.class("reading-stage")],
		[
			Html.p("Write a gloss under each word, then submit the checkpoint to compare your answers with the reference.", "reading-instruction"),
			Html.div_attrs(
				[Engine.class("interlinear study-interlinear")],
				[
					Engine.each(
						model.map(Session.words),
						|word| word.key,
						|row| {
							number = row.field(|word| word.number)
							Html.div(
								"interlinear-word study-cell",
								[
									Engine.element(
										"span",
										[Engine.class("study-token-wrap")],
										[Html.span_v(row.field(|word| word.greek), [Engine.class("interlinear-greek study-cell-greek"), Engine.attr("lang", "grc")])],
									),
									Html.text_input(
										row.field(|word| "Your gloss for ${word.form}"),
										"text",
										row.field(|word| word.guess),
										[Engine.class("cell-input"), Engine.attr("autocomplete", "off"), Engine.attr("autocapitalize", "off")],
										session.lift_row().set_value_by(number, Session.set_gloss),
									),
								],
							)
						},
					),
				],
			),
			Html.div(
				"source-line",
				[
					Html.span_v(model.map(Session.edition), []),
					Html.span_v(model.map(|m| "${Session.words(m).len().to_str()} words"), []),
				],
			),
		],
	)
}

## Each answer beside the reference, for the learner to mark.
grading : State(ReviewApp.S, Session.Model) -> Elem(ReviewApp.S)
grading = |session|
	Engine.element(
		"section",
		[Engine.class("reading-stage grading-stage")],
		[
			Engine.element(
				"p",
				[Engine.class("reading-instruction")],
				[Engine.text("Compare each answer with the reference and mark it yourself. "), Engine.element("span", [], [Engine.text("Different wording can still be right.")])],
			),
			Html.div(
				"grading-legend",
				[Engine.element("span", [Engine.class("legend-reference")], [Engine.text("Reference")]), Engine.element("span", [Engine.class("legend-guess")], [Engine.text("Your answer")])],
			),
			Html.div(
				"interlinear",
				[
					Engine.each(
						session.val().map(Session.words),
						|word| word.key,
						|row| {
							key = row.key()
							guess = row.field(|word| word.guess)
							mark = row.field(|word| word.mark)
							Html.div(
								"interlinear-word",
								[
									Html.span_v(row.field(|word| word.greek), [Engine.class("interlinear-greek"), Engine.attr("lang", "grc")]),
									Html.span_v(row.field(|word| Session.display_gloss(word.reference)), [Engine.class("interlinear-reference")]),
									Html.span_v(guess.map(|text| if text.trim() == "" "—" else text), [Engine.class_v(guess.map(|text| if text.trim() == "" "interlinear-guess is-empty" else "interlinear-guess"))]),
									Html.div(
										"mark-buttons",
										[
											Html.button(
												"✓",
												[
													Engine.class_v(mark.map(|m| if m == "right" "mark-button is-right" else "mark-button")),
													Engine.attr("type", "button"),
													Html.aria_label("Mark right"),
													Engine.test_id_v(key.map(|k| "right-${k}")),
												],
												session.lift_row().update_by(key, |m, k| Session.mark(m, k, Bool.True)),
											),
											Html.button(
												"✗",
												[
													Engine.class_v(mark.map(|m| if m == "wrong" "mark-button is-wrong" else "mark-button")),
													Engine.attr("type", "button"),
													Html.aria_label("Mark wrong"),
													Engine.test_id_v(key.map(|k| "wrong-${k}")),
												],
												session.lift_row().update_by(key, |m, k| Session.mark(m, k, Bool.False)),
											),
										],
									),
								],
							)
						},
					),
				],
			),
		],
	)

## Finishing is choosing a rating: FSRS schedules the passage and the next one
## opens. Each button shows when the passage would come back with that rating.
rating_button : State(ReviewApp.S, Session.Model), Fsrs.Rating, Str -> Elem(ReviewApp.S)
rating_button = |session, rating, label| {
	model = session.val()
	Engine.element(
		"button",
		[
			Engine.class_v(model.map(|m| if Session.suggested(m) == rating "rating-button is-suggested" else "rating-button")),
			Engine.attr("type", "button"),
			Html.aria_label(label),
			Engine.on_click(session.update(|m| Session.rate(m, rating))),
		],
		[strong(label), Html.span_v(model.map(|m| Session.interval(m, rating)), [Engine.class("rating-interval"), Engine.test_id("interval-${label}")])],
	)
}

## Nothing left in today's queue for this work.
done : State(ReviewApp.S, Session.Model) -> Elem(ReviewApp.S)
done = |session| {
	model = session.val()
	Engine.element(
		"section",
		[Engine.class("reading-stage queue-done")],
		[
			Html.p_v(model.map(Session.title), [Engine.class("eyebrow")]),
			Html.h2("Done for today", ""),
			Html.p_v(model.map(Session.done_summary), [Engine.test_id("done-summary")]),
			Html.p_v(model.map(Session.done_next), [Engine.class("muted"), Engine.test_id("done-next")]),
			Html.div(
				"button-row",
				[
					Engine.when(
						model.map(|m| Session.due_now(m) > 0),
						|| Html.button("Review now →", [Engine.class("primary-button"), Engine.attr("type", "button")], session.update(Session.restart)),
						|| Engine.text(""),
					),
					Html.link("Back to library", "#/", [Engine.class("secondary-button")]),
				],
			),
		],
	)
}
