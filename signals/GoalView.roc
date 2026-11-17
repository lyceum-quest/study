import pf.Engine exposing [Elem, In, Row, RowRef, State, Signal]
import pf.Html
import study.Corpus
import study.Reading
import study.Route
import Model
import Nav
import Page
import Update

## A work's reading goal: how much of it the learner can read now, the
## coverage to aim for (explained), a two-way calculator between words a day
## and a finish date, and the words to learn next (see Reading).
GoalView := [].{

	view : State(Page.S, Model.Model) -> Elem(Page.S)
	view = |session| {
		model = session.signal()
		Engine.element(
			"main",
			[Engine.class("page goal-page")],
			[
				Engine.element(
					"section",
					[Engine.class("word-header")],
					[
						Html.p("Reading goal", "eyebrow"),
						Engine.element("h1", [], [Engine.text_s(model.map(|m| Model.work_name(m, goal_work(m))))]),
					],
				),
				Engine.switch(
					model.map(state),
					["ready", "loading", "failed", "missing"],
					|found| match found {
						"ready" => Engine.derive(model.map(goal_data), |data| plan(session, data))
						"failed" => Html.p("The word list couldn't be loaded. Check your connection and open this page again.", "muted")
						"missing" => Html.p("This work isn't in the word list yet.", "muted")
						_ => Html.p("Loading the word list…", "muted")
					},
				),
			],
		)
	}
}

GoalData : {
	percent : Str,
	width : Str,
	learned : Str,
	learned_width : Str,
	coverage : Str,
	needed : Str,
	goal : Str,
	per_day : Str,
	pace : Str,
	uses_pace : Bool,
	finish : Str,
	known_by : Str,
	date : Str,
	by_date : Str,
	next : List(NextRow),
	thresholds : List(Threshold),
}

## What a coverage level takes: 95% (reading with help) and 98% (reading on your own).
Threshold : { goal : Str, text : Str }

NextRow : { lemma : Str, name : Str, href : Str, count : Str, status : Str }

goal_work : Model.Model -> Str
goal_work = |model|
	match model.screen {
		GoalScreen(work) => work
		_ => ""
	}

state : Model.Model -> Str
state = |model|
	match model.lemma_index {
		IndexLoaded(_) => if Model.vocabulary(model, goal_work(model)) == None "missing" else "ready"
		IndexFailed => "failed"
		_ => "loading"
	}

goal_data : Model.Model -> GoalData
goal_data = |model| {
	work = goal_work(model)
	vocabulary = Model.with_default(Model.vocabulary(model, work), { tokens: 0, name_tokens: 0, lemmas: [] })
	known = Model.known_words(model)
	goal = model.reading_goals.coverage
	standing = Reading.standing(vocabulary, known, goal)
	percent = Reading.percent(standing)
	learned = Reading.learned_percent(standing)
	per_day = Model.plan_pace(model)
	measured = Reading.pace(model.clock, model.attempts, model.word_reviews)
	today = Model.local_day(model)
	days = Reading.days_to(standing.needed, per_day)
	learned_by = today + days.to_i64_wrap()
	settle = Reading.settle_days.to_i64_wrap()
	date = model.reading_goals.dates.get(work) ?? ""
	{
		percent: "${percent.to_str()}%",
		width: "${percent.to_str()}%",
		learned: "${learned.to_str()}%",
		learned_width: "${learned.to_str()}%",
		coverage: {
			learned_more = standing.learned_tokens - standing.known_tokens
			also = if learned_more == 0 "" else ", and have learned the words of ${learned_more.to_str()} more"
			"You know ${standing.known_tokens.to_str()} of its ${standing.tokens.to_str()} running words, counting names${also}. ${Model.counted(standing.unknown, "word", "words")} in it are still to learn."
		},
		needed: if standing.needed == 0 "You've learned enough of its words for ${goal.to_str()}%." else "Learn its ${Model.counted(standing.needed, "most frequent word", "most frequent words")} you haven't learned yet to reach ${goal.to_str()}%.",
		goal: goal.to_str(),
		per_day: per_day.to_str(),
		pace: match measured {
			Some(n) => "Your pace over the last four weeks: ${Model.counted(n, "new word", "new words")} a day."
			None => "Until you have ${Reading.pace_days.to_str()} days of study, plans assume ${Reading.default_pace.to_str()} new words a day."
		},
		uses_pace: model.reading_goals.per_day == 0,
		finish: if standing.needed == 0 "Nothing left to learn for this goal." else "You'd learn them in ${Reading.duration(days)}, by ${Model.format_day(learned_by)}.",
		known_by: if standing.needed == 0 "" else "They count as known once you've recalled each one right two weeks after first getting it: around ${Model.format_day(learned_by + settle)}.",
		date,
		by_date: match Reading.day_of_date(date) {
			Err(_) => "Pick a date to see the words a day it takes."
			Ok(day) =>
				if day <= today {
					"That date has passed. Pick a later one."
				} else if standing.needed == 0 {
					"You're there already."
				} else {
					per = Reading.per_day_for(standing.needed, (day - today).to_u64_wrap())
					"Learn about ${Model.counted(per, "new word", "new words")} a day to have learned them by ${Model.format_day(day)}. They count as known about two weeks later."
				}
		},
		thresholds: [95, 98].map(|level| threshold(vocabulary, known, level, per_day)),
		next: Reading.next_words(vocabulary, known, 12).map(
			|entry| {
				lemma: entry.lemma,
				name: Corpus.display_lemma(entry.lemma),
				href: Route.to_path(Word(entry.lemma)),
				count: "× ${entry.count.to_str()}",
				status: if entry.status == Learning "learning" else "new",
			},
		),
	}
}

plan : State(Page.S, Model.Model), Signal(In(Page.S, GoalData), GoalData) -> Elem(In(Page.S, GoalData))
plan = |session, data| {
	Html.div_attrs(
		[Engine.attr("style", "display: contents")],
		[
			Engine.element(
				"section",
				[Engine.class("goal-coverage")],
				[
					Html.div(
						"goal-coverage-head",
						[
							Html.span_s(data.map(|d| d.percent), [Engine.class("goal-percent"), Engine.test_id("goal-percent")]),
							Engine.element("span", [Engine.class("muted")], [Engine.text("of the words known ·")]),
							Html.span_s(data.map(|d| d.learned), [Engine.class("goal-learned"), Engine.test_id("goal-learned")]),
							Engine.element("span", [Engine.class("muted")], [Engine.text("learned")]),
						],
					),
					Engine.element(
						"span",
						[Engine.class("progress-track goal-track"), Engine.attr("role", "img"), Engine.attr_s("aria-label", data.map(|d| "${d.percent} of the words known, ${d.learned} learned, goal ${d.goal}%"))],
						[
							Engine.element("span", [Engine.class("goal-learned-fill"), Engine.attr_s("style", data.map(|d| "width: ${d.learned_width}"))], []),
							Engine.element("span", [Engine.class("progress-fill"), Engine.attr_s("style", data.map(|d| "width: ${d.width}"))], []),
							Engine.element("span", [Engine.class("goal-marker"), Engine.attr_s("style", data.map(|d| "left: ${d.goal}%"))], []),
						],
					),
					Html.p_s(data.map(|d| d.coverage), [Engine.class("goal-note")]),
					Html.p_s(data.map(|d| d.needed), [Engine.class("goal-needed"), Engine.test_id("goal-needed")]),
					Engine.element("ul", [Engine.class("goal-thresholds")], [Engine.each(data.map(|d| d.thresholds), |level| level.goal, threshold_row)]),
				],
			),
			Engine.element(
				"section",
				[Engine.class("word-section goal-form")],
				[
					Engine.element("h2", [], [Engine.text("Your goal")]),
					Engine.element(
						"label",
						[Engine.class("goal-field")],
						[
							Engine.element("span", [], [Engine.text("Know")]),
							Page.select(
								"Coverage goal",
								data.map(|d| d.goal),
								Engine.const([("90", "90%"), ("95", "95%"), ("98", "98%")]),
								[],
								Page.chose(session, set_coverage).lift(),
							),
							Engine.element("span", [], [Engine.text("of the running words")]),
						],
					),
					Engine.element(
						"details",
						[Engine.class("goal-explainer")],
						[
							Engine.element("summary", [], [Engine.text("Why 95%, and when to aim for 98%")]),
							Html.p("How well you understand a text depends mostly on how many of its running words you know. At 95%, one word in twenty is new: most readers follow the text with help, such as the glosses and word popups here. At 98%, one word in fifty, they read comfortably on their own (Laufer and Ravenhorst-Kalovski 2010; Hu and Nation 2000). 90% means a new word in almost every line: possible, but slow.", ""),
							Html.p("Words count by dictionary form, so learning λόγος covers λόγου and λόγῳ too. Names count as known.", ""),
						],
					),
					Engine.element(
						"details",
						[Engine.class("goal-explainer")],
						[
							Engine.element("summary", [], [Engine.text("When a word counts as known")]),
							Html.p("A word is learned once you've given its meaning right, without revealing it, on two different days, and haven't missed it since. It counts as known once two of those right answers are at least two weeks apart (and, if it has a word review card, the card lasts two weeks as well). Recall a few days after learning overstates what lasts; recall over weeks is what lets you meet a word in a new text and still know it.", ""),
							Html.p("Already know a word? Mark it on its page. A later miss undoes the mark.", ""),
						],
					),
				],
			),
			Engine.element(
				"section",
				[Engine.class("word-section goal-form")],
				[
					Engine.element("h2", [], [Engine.text("Plan")]),
					Engine.element(
						"label",
						[Engine.class("goal-field")],
						[
							Engine.element("span", [], [Engine.text("At")]),
							Html.number_input(Engine.const("New words a day"), data.map(|d| d.per_day), [Engine.class("goal-number"), Engine.attr("min", "1"), Engine.attr("max", "1000")], Page.act_value(session, set_per_day).lift()),
							Engine.element("span", [], [Engine.text("new words a day")]),
						],
					),
					Html.p_s(data.map(|d| d.finish), [Engine.class("goal-result goal-finish"), Engine.test_id("goal-finish")]),
					Engine.when(data.map(|d| d.known_by != ""), || Html.p_s(data.map(|d| d.known_by), [Engine.class("goal-note goal-known-by"), Engine.test_id("goal-known-by")]), || Engine.text("")),
					Html.div(
						"goal-pace",
						[
							Html.span_s(data.map(|d| d.pace), [Engine.class("muted")]),
							Engine.when(data.map(|d| !d.uses_pace), || Html.button("Use my pace", [Engine.class("text-button"), Engine.attr("type", "button")], Page.act(session, use_pace).lift()), || Engine.text("")),
						],
					),
					Engine.element(
						"label",
						[Engine.class("goal-field")],
						[
							Engine.element("span", [], [Engine.text("Finish by")]),
							Engine.element("input", [Html.aria_label("Target date"), Engine.attr("type", "date"), Engine.class("goal-date"), Engine.prop_s(Engine.Prop.value, data.map(|d| d.date)), Engine.on("change", Page.act_value(session, set_date).lift())], []),
						],
					),
					Html.p_s(data.map(|d| d.by_date), [Engine.class("goal-result"), Engine.test_id("goal-by-date")]),
				],
			),
			Engine.when(
				data.map(|d| !d.next.is_empty()),
				|| Engine.element(
					"section",
					[Engine.class("word-section")],
					[
						Engine.element("h2", [], [Engine.text("Words to learn next")]),
						Html.p("Its most frequent words you haven't learned yet, with how often each occurs. Already know one? Mark it, and it counts as known.", "muted"),
						Engine.element("ol", [Engine.class("goal-words")], [Engine.each(data.map(|d| d.next), |word| word.lemma, |row| next_row(session, row))]),
					],
				),
				|| Engine.text(""),
			),
		],
	)
}

next_row : State(Page.S, Model.Model), RowRef(In(Page.S, GoalData), NextRow) -> Elem(Row(In(Page.S, GoalData), NextRow))
next_row = |session, row|
	Engine.element(
		"li",
		[],
		[
			Engine.element("a", [Engine.attr_s("href", row.field(|word| word.href)), Engine.attr("lang", "grc")], [Engine.text_s(row.field(|word| word.name))]),
			Html.span_s(row.field(|word| word.count), [Engine.class("goal-count")]),
			Html.span_s(row.field(|word| word.status), [Engine.class("goal-status")]),
			Html.button(
				"Know it",
				[Engine.class("text-button goal-know"), Engine.attr("type", "button"), Engine.test_id_s(row.key().map(|lemma| "know-${lemma}")), Html.aria_label_s(row.field(|word| "I already know ${word.name}"))],
				session.lift().lift_row().update_by(row.key(), |m, lemma| Update.step(m, |x| Nav.set_known(x, lemma, Bool.True))),
			),
		],
	)

use_pace : Model.Model -> Model.Model
use_pace = |model| Nav.set_reading_goals(model, { ..model.reading_goals, per_day: 0 })

set_coverage : Model.Model, Str -> Model.Model
set_coverage = |model, value|
	match U64.from_str(value) {
		Ok(coverage) => Nav.set_reading_goals(model, { ..model.reading_goals, coverage })
		Err(_) => model
	}

## An empty box plans with the learner's own pace.
set_per_day : Model.Model, Str -> Model.Model
set_per_day = |model, value|
	if value.trim() == "" {
		Nav.set_reading_goals(model, { ..model.reading_goals, per_day: 0 })
	} else {
		match U64.from_str(value.trim()) {
			Ok(n) if n >= 1 and n <= 1000 => Nav.set_reading_goals(model, { ..model.reading_goals, per_day: n })
			_ => model
		}
	}

set_date : Model.Model, Str -> Model.Model
set_date = |model, value| {
	work = goal_work(model)
	goals = model.reading_goals
	match Reading.day_of_date(value) {
		Ok(_) => Nav.set_reading_goals(model, { ..goals, dates: goals.dates.insert(work, value) })
		Err(_) => if value == "" Nav.set_reading_goals(model, { ..goals, dates: goals.dates.remove(work) }) else model
	}
}

## `98% (on your own): 712 words to learn, about 48 days at 15 a day`.
threshold : Reading.Vocabulary, Dict(Str, Reading.Status), U64, U64 -> Threshold
threshold = |vocabulary, known, level, per_day| {
	standing = Reading.standing(vocabulary, known, level)
	name = if level >= 98 "on your own" else "with help"
	rest =
		if standing.needed == 0 {
			"enough words learned"
		} else {
			"${Model.counted(standing.needed, "word", "words")} to learn, about ${Reading.duration(Reading.days_to(standing.needed, per_day))} at ${per_day.to_str()} a day"
		}
	{ goal: level.to_str(), text: "${level.to_str()}% (${name}): ${rest}" }
}

threshold_row : RowRef(ctx, Threshold) -> Elem(Row(ctx, Threshold))
threshold_row = |row| Engine.element("li", [Engine.test_id_s(row.key().map(|level| "goal-at-${level}"))], [Engine.text_s(row.field(|level| level.text))])
