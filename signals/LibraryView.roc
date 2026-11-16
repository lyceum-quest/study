import pf.Engine exposing [Elem, Row, RowRef, State, Signal]
import pf.Html
import fsrs.FsrsMath
import study.Corpus
import study.Library
import study.Reading
import study.Review
import study.Route
import study.Today
import Model
import Nav
import Page
import Update
import Workspace

## The home page, ported from `viewLibrary`, `viewTodayPanel` and
## `viewWorkRow` in `src/Main.elm`: today's session, the works being studied,
## and the library, searched and sorted.
LibraryView := [].{

	## One work as a row: its progress line, the label of its study button, and
	## its edition and sources (`has_sources` is false without a citation).
	## `position` counts from 1 down the list, for the specs.
	WorkRow : {
		id : Str,
		position : Str,
		title : Str,
		meta : Str,
		# How readable the work is (once the lemma index has loaded), and its goal page.
		reading : Str,
		goal_url : Str,
		action : Str,
		loading : Bool,
		edition : Str,
		has_sources : Bool,
		reader_url : Str,
		source_edition : Str,
		source_title : Str,
		source_url : Str,
		snapshot : Str,
		after_source : Str,
		annotations_url : Str,
		annotations : Str,
		after_annotations : Str,
	}

	view : State(Page.S, Model.Model) -> Elem(Page.S)
	view = |session| {
		model = session.signal()
		Engine.element(
			"main",
			[Engine.class("page library-page")],
			[
				today_panel(session),
				Engine.when(
					model.map(|m| !working_on(m).is_empty()),
					|| Engine.element(
						"section",
						[Engine.class("home-section"), Html.aria_label("Working on")],
						[Html.h2("Working on", ""), work_rows(session, "working", model.map(|m| rows(m, working_on(m))))],
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
									Page.act_value(session, |m, search| { ..m, search }),
								),
								Html.select(
									Engine.const("Sort the library"),
									model.map(|m| m.sort),
									[Engine.class("library-sort")],
									[Html.option("recent", "Recently studied"), Html.option("easiest", "Easiest first"), Html.option("title", "Title"), Html.option("short", "Shortest first")],
									Page.act_value(session, |m, sort| { ..m, sort }),
								),
							],
						),
						Engine.switch(
							model.map(|m| if m.works.is_empty() "loading" else if shown(m).is_empty() "none" else "works"),
							["loading", "none", "works"],
							|state| match state {
								"loading" => Html.p("Loading the library…", "muted")
								"none" => Html.p("No works match.", "muted")
								_ => work_rows(session, "library", model.map(|m| rows(m, shown(m))))
							},
						),
					],
				),
			],
		)
	}

	## "Today", and which works to study: all, or one at a time.
	today_head : State(Page.S, Model.Model) -> Elem(Page.S)
	today_head = |session| {
		model = session.signal()
		Html.div(
			"today-head",
			[
				Html.p("Today", "eyebrow"),
				Engine.element(
					"label",
					[Engine.class("today-scope")],
					[
						Engine.element("span", [], [Engine.text("Studying")]),
						Html.select(
							Engine.const("Works to study"),
							model.map(|m| Model.with_default(m.today_scope, all_works)),
							[],
							[
								Html.option(all_works, "All works"),
								Engine.each(model.map(|m| working_on(m).map(|work| { id: work.id, title: work.title })), |work| work.id, |row| Engine.element("option", [Engine.attr_s("value", row.key())], [Engine.text_s(row.field(|work| work.title))])),
							],
							Page.act_value(session, |m, work| Nav.set_today_scope(m, if work == all_works "" else work)),
						),
					],
				),
			],
		)
	}

	## What comes back later today in this mode, with a way to take it now.
	upcoming : State(Page.S, Model.Model), Today.Mode -> Elem(Page.S)
	upcoming = |session, mode| {
		model = session.signal()
		Engine.when(
			model.map(|m| next_due(m, mode) != None),
			|| Engine.element(
				"p",
				[Engine.class("today-summary")],
				[
					Engine.text_s(
						model.map(
							|m| match next_due(m, mode) {
								Some((item, due)) => "Next: ${Model.item_name(m, item)} comes back in ${Review.interval_label(m.clock, due)}. "
								None => ""
							},
						),
					),
					Page.button(
						"Review it now",
						"text-button",
						Page.act(
							session,
							|m| match next_due(m, mode) {
								Some((item, _)) => Nav.go(m, Model.item_path(mode, item))
								None => m
							},
						),
					),
				],
			),
			|| Html.p("Nothing else is due today.", "today-summary"),
		)
	}

	## Continues the session with more new passages than today's limit.
	learn_more_button : State(Page.S, Model.Model), Bool -> Elem(Page.S)
	learn_more_button = |session, primary|
		Html.button_s(
			session.signal().map(|m| "Learn ${Model.learn_more_step(m).to_str()} more →"),
			[Engine.class(if (primary) "primary-button" else "secondary-button"), Engine.attr("type", "button")],
			Page.act(session, Nav.learn_more),
		)
}

## Today's session across every work: what is waiting, and how to start it.
today_panel : State(Page.S, Model.Model) -> Elem(Page.S)
today_panel = |session| {
	model = session.signal()
	Engine.element(
		"section",
		[Engine.class("today-panel"), Html.aria_label("Today")],
		[
			LibraryView.today_head(session),
			Engine.element("h1", [Engine.class("today-title")], [Engine.text_s(model.map(today_title))]),
			Engine.switch(
				model.map(|m| if today_parts(m).is_empty() "caught-up" else "waiting"),
				["caught-up", "waiting"],
				|state| match state {
					"caught-up" =>
						Html.div_attrs(
							[],
							[
								LibraryView.upcoming(session, Everything),
								Engine.when(
									model.map(|m| Model.more_to_learn({ ..m, queue_mode: Bool.False, today_mode: None })),
									|| Html.div("today-actions", [LibraryView.learn_more_button(session, Bool.True)]),
									|| Engine.text(""),
								),
							],
						)
					_ =>
						Html.div_attrs(
							[],
							[
								Html.p_s(model.map(|m| "About ${Model.counted(minutes(m), "minute", "minutes")}. Reviews come first, then new passages."), [Engine.class("today-summary")]),
								Html.div(
									"today-actions",
									[
										Page.button("Start →", "primary-button", Page.act(session, |m| Nav.start_today(m, Everything))),
										Html.button_s(
											model.map(|m| "Words only · ${Model.today_plan(m).words.len().to_str()}"),
											[Engine.class("secondary-button"), Engine.attr("type", "button"), Html.disabled(model.map(|m| Model.today_plan(m).words.is_empty()))],
											Page.act(session, |m| Nav.start_today(m, WordsOnly)),
										),
										Html.button_s(
											model.map(|m| "Passages only · ${passage_count(m).to_str()}"),
											[Engine.class("secondary-button"), Engine.attr("type", "button"), Html.disabled(model.map(|m| passage_count(m) == 0))],
											Page.act(session, |m| Nav.start_today(m, PassagesOnly)),
										),
									],
								),
							],
						)
				},
			),
			Engine.when(
				model.map(|m| continue_at(m) != None),
				|| Engine.element(
					"p",
					[Engine.class("today-continue")],
					[
						Engine.text("Continue where you left off: "),
						Engine.element(
							"a",
							[Engine.attr_s("href", model.map(|m| match continue_at(m) { Some((work, ref)) => Route.to_path(Study(work.id, ref)) None => "#/" }))],
							[Engine.text_s(model.map(|m| match continue_at(m) { Some((work, ref)) => "${Model.passage_name(m, work.id, ref)} →" None => "" }))],
						),
					],
				),
				|| Engine.text(""),
			),
		],
	)
}

today_parts : Model.Model -> List(Str)
today_parts = |model| {
	today = Model.today_plan(model)
	words = today.words.len()
	due = today.due.len()
	fresh = today.new.len()
	[
		if words > 0 Ok("${Model.counted(words, "word", "words")} to review") else Err({}),
		if due > 0 Ok("${Model.counted(due, "passage", "passages")} to review") else Err({}),
		if fresh > 0 Ok(Model.counted(fresh, "new passage", "new passages")) else Err({}),
	].keep_oks(|part| part)
}

today_title : Model.Model -> Str
today_title = |model| {
	parts = today_parts(model)
	if parts.is_empty() "All caught up" else Str.join_with(parts, " · ")
}

passage_count : Model.Model -> U64
passage_count = |model| {
	today = Model.today_plan(model)
	today.due.len() + today.new.len()
}

## About 0.3 minutes a word and 2.5 a passage, at least one.
minutes : Model.Model -> U64
minutes = |model| {
	today = Model.today_plan(model)
	estimate = today.words.len().to_f64() * 0.3 + passage_count(model).to_f64() * 2.5
	(F64.to_i64_try(FsrsMath.round(estimate)) ?? 0).max(1).to_u64_wrap()
}

## Where "Continue where you left off" leads: the Today scope's work, else the
## work of the latest graded passage, at its saved passage.
continue_at : Model.Model -> [Some((Corpus.Work, Str)), None]
continue_at = |model| {
	work = match model.today_scope {
		Some(id) => Some(id)
		None => Today.last_work(model.attempts)
	}
	match work {
		Some(id) => match Model.entry_for(model, id) {
			Some(entry) => Some((entry, Corpus.saved_ref(entry, model.positions)))
			None => None
		}
		None => None
	}
}

activity : Model.Model -> Dict(Str, I64)
activity = |model| Library.last_activity(model.attempts, model.word_reviews.map(|review| { work: review.occurrence.work, at: review.at }))

## Studied works, most recent first, then ones opened (a saved position, or the Today scope).
working_on : Model.Model -> List(Corpus.Work)
working_on = |model| {
	opened = match model.today_scope {
		Some(work) => model.positions.keys().append(work)
		None => model.positions.keys()
	}
	Library.working_on(model.works, activity(model), opened)
}

shown : Model.Model -> List(Corpus.Work)
shown = |model| {
	coverage = if model.sort == "easiest" readings(model).map(|_, found| if found.tokens == 0 1000 else found.known_tokens * 1000 // found.tokens) else Dict.empty()
	Library.shown(model.works, activity(model), coverage, model.search, model.sort)
}

## How readable each work is at the learner's goal, once the lemma index has loaded.
readings : Model.Model -> Dict(Str, Reading.Standing)
readings = |model|
	match model.lemma_index {
		IndexLoaded(data) => {
			known = Model.known_words(model)
			data.vocabularies.map(|_, vocabulary| Reading.standing(vocabulary, known, model.reading_goals.coverage))
		}
		_ => Dict.empty()
	}

rows : Model.Model, List(Corpus.Work) -> List(LibraryView.WorkRow)
rows = |model, works| {
	found = readings(model)
	works.map_with_index(|work, index| work_row(model, found, work, index))
}

## `62% of words known · 340 to learn for 95%`.
reading_line : Model.Model, Dict(Str, Reading.Standing), Str -> Str
reading_line = |model, found, work|
	match found.get(work) {
		Ok(standing) => {
			goal = model.reading_goals.coverage.to_str()
			learn = if standing.needed == 0 "at your ${goal}% goal" else "${Model.counted(standing.needed, "word", "words")} to learn for ${goal}%"
			"${Reading.percent(standing).to_str()}% of words known · ${learn}"
		}
		Err(_) => ""
	}

work_row : Model.Model, Dict(Str, Reading.Standing), Corpus.Work, U64 -> LibraryView.WorkRow
work_row = |model, standings, work, index| {
	row = {
		id: work.id,
		position: (index + 1).to_str(),
		title: work.title,
		meta: Library.meta(model.clock, work, model.entries),
		reading: reading_line(model, standings, work.id),
		goal_url: Route.to_path(Goal(work.id)),
		action: if Library.progress(model.clock, work, model.entries).studied == 0 "Start →" else "Study →",
		loading: model.pending_route != None and model.requested_work == Some(work.id),
		edition: work.edition,
		has_sources: Bool.False,
		reader_url: "",
		source_edition: "",
		source_title: "",
		source_url: "",
		snapshot: "",
		after_source: "",
		annotations_url: "",
		annotations: "",
		after_annotations: "",
	}
	match work.citation {
		None => row
		Some(found) => {
			..row,
			has_sources: Bool.True,
			reader_url: found.text.reader_url,
			source_edition: found.text.edition,
			source_title: "${found.text.author}, ${found.text.title}",
			source_url: found.text.source_url,
			snapshot: "${found.text.repository} ${found.text.snapshot}",
			after_source: ", ${found.text.license}) · ",
			annotations_url: found.annotations.url,
			annotations: "${found.annotations.name} ${found.annotations.version}",
			after_annotations: " (${found.annotations.license}) · ${found.generated.name} ${found.generated.layers}, generated with ${found.generated.model} (${found.generated.license})",
		}
	}
}

## Works as compact rows: progress, Read and Study, and the edition and source
## credits on request. Test ids start with `section`: `<section>-<position>`
## for a row's title, `<section>:<work>` for its progress line, and `:read`
## and `:study` after that for its buttons.
work_rows : State(Page.S, Model.Model), Str, Signal(Page.S, List(LibraryView.WorkRow)) -> Elem(Page.S)
work_rows = |session, section, found|
	Html.div(
		"work-rows",
		[
			Engine.each(
				found,
				|work| work.id,
				|row| {
					id = row.key()
					loading = row.field(|work| work.loading)
					rows_session = session.lift_row()
					Html.div(
						"work-row",
						[
							Html.div(
								"work-row-main",
								[
									Engine.element("h3", [Engine.class("work-row-title"), Engine.test_id_s(row.field(|work| "${section}-${work.position}"))], [Engine.text_s(row.field(|work| work.title))]),
									Html.p_s(row.field(|work| work.meta), [Engine.class("work-row-meta"), Engine.test_id_s(id.map(|work| "${section}:${work}"))]),
									Engine.when(
										row.field(|work| work.reading != ""),
										|| Engine.element(
											"p",
											[Engine.class("work-row-reading")],
											[
												Html.span_s(row.field(|work| work.reading), [Engine.test_id_s(id.map(|work| "${section}:${work}:reading"))]),
												Engine.text(" · "),
												Engine.element("a", [Engine.attr_s("href", row.field(|work| work.goal_url)), Engine.test_id_s(id.map(|work| "${section}:${work}:goal"))], [Engine.text("Reading goal")]),
											],
										),
										|| Engine.text(""),
									),
									Engine.element(
										"details",
										[Engine.class("work-row-sources")],
										[
											Engine.element("summary", [], [Engine.text("Edition & sources")]),
											Html.p_s(row.field(|work| work.edition), [Engine.class("greek-subtitle")]),
											Engine.when(row.field(|work| work.has_sources), || sources(row), || Engine.text("")),
										],
									),
								],
							),
							Html.div(
								"work-row-actions",
								[
									Html.button(
										"Read",
										[Engine.class("secondary-button"), Engine.attr("type", "button"), Html.disabled(loading), Engine.test_id_s(id.map(|work| "${section}:${work}:read"))],
										rows_session.update_by(id, |m, work| Update.step(m, |x| Nav.go_route(x, Reader(work, None)))),
									),
									Html.button_s(
										row.field(|work| if work.loading "Loading…" else work.action),
										[Engine.class("primary-button"), Engine.attr("type", "button"), Html.disabled(loading), Engine.test_id_s(id.map(|work| "${section}:${work}:study"))],
										rows_session.update_by(id, |m, work| Update.step(m, |x| Nav.start_today_in(x, work))),
									),
								],
							),
						],
					)
				},
			),
		],
	)

## The compact attribution line of `src/Sources.elm`.
sources : RowRef(Page.S, LibraryView.WorkRow) -> Elem(Row(Page.S, LibraryView.WorkRow))
sources = |row|
	Engine.element(
		"p",
		[Engine.class("sources-line")],
		[
			Engine.element("span", [Engine.class("sources-label")], [Engine.text("Sources ")]),
			Page.external(row.field(|work| work.reader_url), row.field(|work| work.source_edition), row.field(|work| work.source_title)),
			Engine.text(" ("),
			Page.external(row.field(|work| work.source_url), row.field(|work| work.snapshot), Engine.const("TEI XML")),
			Engine.text_s(row.field(|work| work.after_source)),
			Page.external(row.field(|work| work.annotations_url), Engine.const("Tokenization, lemmas, morphology, and syntax"), row.field(|work| work.annotations)),
			Engine.text_s(row.field(|work| work.after_annotations)),
		],
	)

next_due : Model.Model, Today.Mode -> [Some((Today.Item, I64)), None]
next_due = |model, mode| Today.upcoming(model.clock, mode, model.today_scope, model.entries, model.word_cards)

## The "All works" choice of the Today scope (the Elm app's empty value).
## Workaround: roc-signals 0.5.0 removes an attribute set to "", so an
## option cannot have the value "" (it would fall back to its label); see
## https://github.com/lukewilliamboswell/roc-signals/issues/205 (open; roc-issues
## archive/RS-006-empty-attribute-values).
## A work id is never "*".
all_works : Str
all_works = "*"
