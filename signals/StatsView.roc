import pf.Engine exposing [Elem, In, Row, RowRef, State, Signal]
import pf.Html
import study.Corpus
import study.Review
import study.Route
import study.Stats
import study.Words
import Model
import AccountView
import Page

## The Progress page, ported from `viewStats`, `viewStatTile` and
## `viewColumnChart` in `src/Main.elm`: tiles of totals, daily charts of the
## last 30 days, progress by work, and the most-missed words and hardest
## passages, from the attempts, cards and word reviews in this browser (see
## Stats for the numbers).
StatsView := [].{

	view : State(Page.S, Model.Model) -> Elem(Page.S)
	view = |session|
		Engine.element(
			"main",
			[Engine.class("page stats-page")],
			[
				Engine.element(
					"section",
					[Engine.class("word-header")],
					[
						Html.p("Progress", "eyebrow"),
						Engine.element("h1", [], [Engine.text("Your progress")]),
					],
				),
				AccountView.panel(session),
				Engine.derive(session.signal().map(summary), |data| numbers(data)),
			],
		)
}

numbers : Signal(In(Page.S, Summary), Summary) -> Elem(In(Page.S, Summary))
numbers = |data|
			Html.div_attrs(
				[Engine.attr("style", "display: contents")],
				[
					Html.div(
						"stat-tiles",
						[
							tile(data, "Words known", |s| s.known.to_str(), Engine.const("Recalled right on days two weeks apart")),
							tile(data, "Words learned", |s| s.learned.to_str(), Engine.const("Right on two days; known after two weeks")),
							tile(data, "Words learning", |s| s.learning.to_str(), Engine.const("Answered, not yet learned")),
							tile(data, "Passages studied", |s| s.studied.to_str(), data.map(|s| "of ${s.passages.to_str()}")),
							tile(data, "Streak", |s| Model.counted(s.streak, "day", "days"), Engine.const("Days in a row with a review")),
							tile(data, "Right, last 7 days", |s| s.recent_right, data.map(|s| Model.counted(s.recent_total, "word answer", "word answers"))),
						],
					),
					Html.div(
						"chart-grid",
						[
							chart("Reviews per day", data.map(|s| s.reviews)),
							chart("New trouble words per day", data.map(|s| s.trouble)),
							chart("New passages per day", data.map(|s| s.new_passages)),
						],
					),
					Engine.element(
						"section",
						[Engine.class("word-section")],
						[
							Engine.element("h2", [], [Engine.text("By work")]),
							Html.div("work-progress", [Engine.each(data.map(|s| s.works), |work| work.id, work_row)]),
						],
					),
					Html.div(
						"stats-columns",
						[
							Engine.element(
								"section",
								[Engine.class("word-section")],
								[
									Engine.element("h2", [], [Engine.text("Most-missed words")]),
									Engine.when(
										data.map(|s| s.missed.is_empty()),
										|| Html.p("No missed words yet.", "muted"),
										|| table(["Word", "Missed", "Next review"], Engine.each(data.map(|s| s.missed), |word| word.lemma, missed_row)),
									),
								],
							),
							Engine.element(
								"section",
								[Engine.class("word-section")],
								[
									Engine.element("h2", [], [Engine.text("Hardest passages")]),
									Engine.when(
										data.map(|s| s.hard.is_empty()),
										|| Html.p("No missed answers yet.", "muted"),
										|| table(["Passage", "Wrong answers", "Attempts"], Engine.each(data.map(|s| s.hard), |hard| hard.key, hard_row)),
									),
								],
							),
						],
					),
				],
			)

## A day's column: its date, count, tooltip, height and, on the busiest day, its label.
Column : { key : Str, date : Str, count : Str, tip : Str, height : Str, peak : Str }

## One series of daily counts as columns (`viewColumnChart`).
Chart : { subtitle : Str, label : Str, peak : Str, first : Str, columns : List(Column), table : List(Column) }

WorkRow : { id : Str, title : Str, label : Str, width : Str, count : Str }

MissedRow : { lemma : Str, href : Str, name : Str, missed : Str, next : Str }

HardRow : { key : Str, href : Str, name : Str, wrong : Str, attempts : Str }

Summary : {
	known : U64,
	learned : U64,
	learning : U64,
	studied : U64,
	passages : U64,
	streak : U64,
	recent_right : Str,
	recent_total : U64,
	reviews : Chart,
	trouble : Chart,
	new_passages : Chart,
	works : List(WorkRow),
	missed : List(MissedRow),
	hard : List(HardRow),
}

summary : Model.Model -> Summary
summary = |model| {
	now = model.clock
	words = model.word_cards.values()
	statuses = Model.known_words(model).values()
	known = statuses.count_if(|status| status == Known)
	learned = statuses.count_if(|status| status == Learned)
	times = Stats.review_times(model.attempts, model.word_reviews)
	entries = model.entries.values()
	recent = Stats.recent_words(now, model.attempts, model.word_reviews)
	{
		known,
		learned,
		learning: statuses.count_if(|status| status == Learning),
		studied: model.entries.len(),
		passages: model.works.fold(0, |total, work| total + work.passages.len()),
		streak: Stats.streak(now, times).to_u64_wrap(),
		recent_right: Stats.recent_percent(recent),
		recent_total: recent.total,
		reviews: chart_data("Reviews per day", "Passages graded and word reviews, last 30 days", Stats.per_day(now, times)),
		trouble: chart_data("New trouble words per day", "Words first missed in a passage", Stats.per_day(now, words.map(|word| word.introduced_at))),
		new_passages: chart_data("New passages per day", "Passages studied for the first time", Stats.per_day(now, entries.map(|entry| entry.introduced_at))),
		works: model.works.map(
			|work| {
				total = work.passages.len()
				studied = entries.count_if(|entry| entry.work == work.id)
				{
					id: work.id,
					title: work.title,
					label: "${studied.to_str()} of ${total.to_str()} passages studied",
					width: Stats.css_percent(studied.to_i64_wrap(), total.max(1).to_i64_wrap()),
					count: "${studied.to_str()} / ${total.to_str()}",
				}
			},
		),
		missed: Stats.missed_words(model.word_cards).map(
			|word| {
				lemma: word.lemma,
				href: Route.to_path(Word(word.lemma)),
				name: Corpus.display_lemma(word.lemma),
				missed: "${word.misses.to_str()} of ${word.seen.to_str()}",
				next: if word.card.due <= now "now" else "in ${Review.interval_label(now, word.card.due)}",
			},
		),
		hard: Stats.hard_passages(model.attempts).map(
			|hard| {
				key: "${hard.work} ${hard.passage}",
				href: Route.to_path(Study(hard.work, hard.passage)),
				name: Model.passage_name(model, hard.work, hard.passage),
				wrong: hard.wrong.to_str(),
				attempts: hard.attempts.to_str(),
			},
		),
	}
}

chart_data : Str, Str, List(Stats.Day) -> Chart
chart_data = |title, subtitle, points| {
	peak = Stats.peak_count(points)
	peak_day = Stats.peak_day(points)
	total : I64
	total = points.fold(0, |sum, point| sum + point.count)
	columns = points.map(
		|point| {
			date = Stats.short_date(point.day)
			{
				key: point.day.to_str(),
				date,
				count: point.count.to_str(),
				tip: "${date}: ${point.count.to_str()}",
				height: "height: ${Stats.css_percent(point.count, peak.max(1))}",
				peak: if peak_day == Some(point.day) point.count.to_str() else "",
			}
		},
	)
	{
		subtitle: "${subtitle} · ${total.to_str()} in all",
		label: "${title}: ${total.to_str()} over 30 days, most on one day ${peak.to_str()}",
		peak: peak.to_str(),
		first: match columns.first() {
			Ok(column) => column.date
			Err(_) => ""
		},
		columns,
		table: columns.fold(List.with_capacity(columns.len()), |reversed, column| reversed.prepend(column)),
	}
}

tile : Signal(ctx, Summary), Str, (Summary -> Str), Signal(ctx, Str) -> Elem(ctx)
tile = |data, label, value, note|
	Html.div(
		"stat-tile",
		[
			Engine.element("span", [Engine.class("stat-tile-label")], [Engine.text(label)]),
			Html.span_s(data.map(value), [Engine.class("stat-tile-value"), Engine.test_id("tile-${label}")]),
			Html.span_s(note, [Engine.class("stat-tile-note")]),
		],
	)

## A single hue, so no legend; the busiest day is labelled, every day has a
## tooltip, and a table carries the values.
chart : Str, Signal(ctx, Chart) -> Elem(ctx)
chart = |title, data|
	Engine.element(
		"section",
		[Engine.class("column-chart")],
		[
			Engine.element("h3", [Engine.class("chart-title")], [Engine.text(title)]),
			Html.p_s(data.map(|c| c.subtitle), [Engine.class("chart-subtitle")]),
			Engine.element(
				"div",
				[Engine.class("chart-plot"), Engine.attr("role", "img"), Engine.attr_s("aria-label", data.map(|c| c.label))],
				[
					Html.span_s(data.map(|c| c.peak), [Engine.class("chart-tick")]),
					Html.div(
						"chart-columns",
						[
							Engine.each(
								data.map(|c| c.columns),
								|column| column.key,
								|row| Engine.element(
									"div",
									[Engine.class("chart-slot"), Engine.attr_s("data-tip", row.field(|column| column.tip)), Engine.attr("tabindex", "0")],
									[
										Engine.when(row.field(|column| column.peak != ""), || Html.span_s(row.field(|column| column.peak), [Engine.class("chart-peak")]), || Engine.text("")),
										Engine.element("div", [Engine.class("chart-column"), Engine.attr_s("style", row.field(|column| column.height))], []),
									],
								),
							),
						],
					),
				],
			),
			Html.div(
				"chart-axis",
				[
					Html.span_s(data.map(|c| c.first), []),
					Engine.element("span", [], [Engine.text("Today")]),
				],
			),
			Engine.element(
				"details",
				[Engine.class("chart-table")],
				[
					Engine.element("summary", [], [Engine.text("Show as table")]),
					table(
						["Day", "Count"],
						Engine.each(
							data.map(|c| c.table),
							|column| column.key,
							|row| Engine.element("tr", [], [cell(row.field(|column| column.date)), cell(row.field(|column| column.count))]),
						),
					),
				],
			),
		],
	)

table : List(Str), Elem(ctx) -> Elem(ctx)
table = |headings, rows|
	Engine.element(
		"table",
		[Engine.class("stats-table")],
		[
			Engine.element("thead", [], [Engine.element("tr", [], headings.map(|heading| Engine.element("th", [], [Engine.text(heading)])))]),
			Engine.element("tbody", [], [rows]),
		],
	)

cell : Signal(ctx, Str) -> Elem(ctx)
cell = |value| Engine.element("td", [], [Engine.text_s(value)])

link : Signal(ctx, Str), Signal(ctx, Str) -> Elem(ctx)
link = |href, label| Engine.element("a", [Engine.attr_s("href", href)], [Engine.text_s(label)])

work_row : RowRef(ctx, WorkRow) -> Elem(Row(ctx, WorkRow))
work_row = |row|
	Html.div(
		"work-progress-row",
		[
			Html.span_s(row.field(|work| work.title), [Engine.class("work-progress-title")]),
			Engine.element(
				"span",
				[Engine.class("progress-track"), Engine.attr("role", "img"), Engine.attr_s("aria-label", row.field(|work| work.label))],
				[Engine.element("span", [Engine.class("progress-fill"), Engine.attr_s("style", row.field(|work| "width: ${work.width}"))], [])],
			),
			Html.span_s(row.field(|work| work.count), [Engine.class("work-progress-count"), Engine.test_id_s(row.key().map(|id| "work-${id}"))]),
		],
	)

missed_row : RowRef(ctx, MissedRow) -> Elem(Row(ctx, MissedRow))
missed_row = |row|
	Engine.element(
		"tr",
		[],
		[
			Engine.element("td", [Engine.attr("lang", "grc")], [link(row.field(|word| word.href), row.field(|word| word.name))]),
			Engine.element("td", [Engine.test_id_s(row.key().map(|lemma| "missed-${lemma}"))], [Engine.text_s(row.field(|word| word.missed))]),
			Engine.element("td", [Engine.test_id_s(row.key().map(|lemma| "next-${lemma}"))], [Engine.text_s(row.field(|word| word.next))]),
		],
	)

hard_row : RowRef(ctx, HardRow) -> Elem(Row(ctx, HardRow))
hard_row = |row|
	Engine.element(
		"tr",
		[],
		[
			Engine.element("td", [], [link(row.field(|hard| hard.href), row.field(|hard| hard.name))]),
			Engine.element("td", [Engine.test_id_s(row.field(|hard| "wrong-${hard.name}"))], [Engine.text_s(row.field(|hard| hard.wrong))]),
			Engine.element("td", [Engine.test_id_s(row.field(|hard| "attempts-${hard.name}"))], [Engine.text_s(row.field(|hard| hard.attempts))]),
		],
	)
