import pf.Engine exposing [Elem, State, Val]
import pf.Html
import fsrs.FsrsMath
import study.Corpus
import study.Study
import study.Tools
import Model
import Nav
import Page
import Settings
import Workspace

## The study tools page, ported from `viewSettings`, `viewPresetCard`,
## `viewModuleSetting`, `viewProgress` and `corpusCoverage` in
## `src/Main.elm`: the presets, each tool with how much of the open work
## supports it, the daily limit of new passages, a summary of the attempts,
## and clearing what this browser saved.
SettingsView := [].{

	view : State(Page.S, Model.Model) -> Elem(Page.S)
	view = |session| {
		model = session.val()
		Engine.element(
			"main",
			[Engine.class("page settings-page")],
			[
				Engine.element(
					"section",
					[Engine.class("settings-intro compact-intro")],
					[
						Engine.element(
							"div",
							[],
							[
								Html.p_v(model.map(Model.work_title), [Engine.class("eyebrow")]),
								Engine.element("h1", [], [Engine.text("Study tools")]),
							],
						),
						Page.button("Back to study →", "primary-button open-workspace-button", Page.act(session, Settings.show_workspace)),
					],
				),
				Engine.element(
					"section",
					[Engine.class("setting-block")],
					[
						Html.div(
							"preset-grid",
							[
								preset_card(session, ReadPreset, "Read", "Glosses only, one word at a time.", "≈ 4 min / passage"),
								preset_card(session, AssistedPreset, "Assisted", "Glosses and a prose translation.", "≈ 8 min / passage"),
								preset_card(session, IntensivePreset, "Intensive", "Glosses and both translations.", "≈ 12 min / passage"),
								preset_card(session, CustomPreset, "Custom", "Your own choice of tools.", "Variable"),
							],
						),
					],
				),
				Engine.element(
					"section",
					[Engine.class("module-settings")],
					[
						module_setting(
							session,
							GlossModule,
							"Glosses",
							"Gloss words one at a time from the word popup, then compare with the imported gloss.",
							|c| "${c.glossed.to_str()} of ${c.tokens.to_str()} words",
							" · imported",
						),
						module_setting(
							session,
							LiteralModule,
							"Literal translation",
							"Expose the structure in your own words, then compare.",
							|c| "${c.literal.to_str()} of ${c.sentences.to_str()} sentences",
							" · aligned reference",
						),
						module_setting(
							session,
							ProseModule,
							"Prose translation",
							"State the meaning naturally, then compare.",
							|c| "${c.prose.to_str()} of ${c.sentences.to_str()} sentences",
							" · aligned reference",
						),
					],
				),
				progress(session),
			],
		)
	}
}

## How much of the open work each tool covers (`corpusCoverage`). Before a
## work has loaded, the Elm app's placeholder corpus of one empty passage.
Coverage : { tokens : U64, glossed : U64, sentences : U64, literal : U64, prose : U64 }

coverage : Model.Model -> Coverage
coverage = |model| {
	passages = if model.passages.is_empty() [Corpus.missing] else model.passages
	tokens = passages.join_map(|passage| passage.tokens)
	{
		tokens: tokens.len(),
		glossed: tokens.count_if(|token| token.gloss != ""),
		sentences: passages.len(),
		literal: passages.count_if(|passage| passage.literal != ""),
		prose: passages.count_if(|passage| passage.prose != ""),
	}
}

## The open work's source, which the tools' material comes from.
provenance : Model.Model -> Str
provenance = |model|
	match model.active {
		Some(work) => work.source.name
		None => ""
	}

preset_card : State(Page.S, Model.Model), Tools.Preset, Str, Str, Str -> Elem(Page.S)
preset_card = |session, target, title, description, budget| {
	selected = session.val().map(|m| m.preset == target)
	Engine.element(
		"button",
		[
			Engine.class_v(selected.map(|yes| if yes "preset-card is-selected" else "preset-card")),
			Engine.attr("type", "button"),
			Engine.on_click(Page.act(session, |m| Workspace.select_preset(m, target))),
			Html.flag("aria-pressed", selected),
		],
		[
			Html.span_v(selected.map(|yes| if yes "✓" else ""), [Engine.class("preset-check"), Engine.attr("aria-hidden", "true")]),
			Engine.element("span", [Engine.class("preset-title")], [Engine.text(title)]),
			Engine.element("span", [Engine.class("preset-description")], [Engine.text(description)]),
			Engine.element("span", [Engine.class("preset-budget")], [Engine.text(budget)]),
		],
	)
}

module_setting : State(Page.S, Model.Model), Tools.ModuleId, Str, Str, (Coverage -> Str), Str -> Elem(Page.S)
module_setting = |session, module_id, title, description, covered, source| {
	model = session.val()
	enabled = model.map(|m| Tools.module_mode(module_id, m.settings) != ModuleOff)
	Engine.element(
		"div",
		[Engine.class_v(enabled.map(|yes| if yes "module-row is-enabled" else "module-row"))],
		[
			Html.div("module-toggle-wrap", [Html.checkbox(Engine.const("Enable ${title}"), enabled, [], Page.act(session, |m| Workspace.toggle_module(m, module_id)))]),
			Html.div(
				"module-copy",
				[
					Html.div(
						"module-title-line",
						[
							Engine.element("h3", [], [Engine.text(title)]),
							Html.span_v(model.map(|m| covered(coverage(m))), [Engine.class("coverage-badge")]),
						],
					),
					Engine.element("p", [], [Engine.text(description)]),
					Html.span_v(model.map(|m| "${provenance(m)}${source}"), [Engine.class("provenance")]),
				],
			),
		],
	)
}

## The daily limit, the attempts' summary and clearing saved data (`viewProgress`).
progress : State(Page.S, Model.Model) -> Elem(Page.S)
progress = |session| {
	model = session.val()
	summary = model.map(|m| Study.stats(m.attempts))
	Engine.element(
		"section",
		[Engine.class("progress-settings")],
		[
			Engine.element(
				"label",
				[Engine.class("new-per-day")],
				[
					Engine.element("span", [], [Engine.text("New passages per day")]),
					Engine.element(
						"select",
						[
							Html.aria_label("New passages per day"),
							Engine.attr_v("value", model.map(|m| m.new_per_day.to_str())),
							Engine.on("change", Page.act_value(session, Nav.set_new_per_day)),
						],
						[Html.option("3", "3"), Html.option("5", "5"), Html.option("10", "10"), Html.option("15", "15"), Html.option("20", "20"), Html.option("30", "30")],
					),
					Engine.element("span", [Engine.class("muted")], [Engine.text("Reviews that are due are never capped.")]),
				],
			),
			Html.div(
				"progress-heading",
				[
					Engine.element("h2", [], [Engine.text("Your progress")]),
					Engine.element("span", [Engine.class("muted")], [Engine.text("Saved only in this browser.")]),
				],
			),
			Html.div(
				"progress-stats",
				[
					stat(summary.map(|s| s.attempts.to_str()), "graded attempts", "graded-attempts"),
					stat(summary.map(|s| s.judged.to_str()), "answers marked", "answers-marked"),
					stat(summary.map(|s| percent(s.right, s.judged)), "marked right", "marked-right"),
					stat(summary.map(|s| percent(s.unassisted_right, s.unassisted_judged)), "right without reveals", "right-without-reveals"),
				],
			),
			Engine.when(
				summary.map(|s| s.struggles.is_empty()),
				|| Html.p("Words you mark wrong will be listed here.", "muted"),
				|| Html.div(
					"struggles",
					[
						Engine.element("h3", [], [Engine.text("Words you miss most")]),
						Engine.element(
							"div",
							[Engine.class("struggle-list"), Engine.attr("lang", "grc")],
							[
								Engine.each(
									summary.map(|s| s.struggles),
									|word| word.lemma,
									|row| Engine.element(
										"span",
										[Engine.class("struggle")],
										[
											Engine.text_v(row.key()),
											Html.span_v(row.field(|word| "${word.wrong.to_str()} / ${word.judged.to_str()} wrong"), [Engine.class("struggle-count"), Engine.attr("lang", "en"), Engine.test_id_v(row.key().map(|lemma| "struggle-${lemma}"))]),
										],
									),
								),
							],
						),
					],
				),
			),
			Engine.when(
				model.map(|m| m.confirm_clear),
				# With account sync (not ported yet), the Elm app says the synced progress stays in the account.
				|| Html.div(
					"clear-data",
					[
						Engine.element("span", [], [Engine.text("Delete all attempts, drafts, and reading positions saved in this browser?")]),
						Page.button("Delete saved data", "danger-button", Page.act(session, Settings.confirm_clear)),
						Page.button("Cancel", "secondary-button", Page.act(session, Settings.cancel_clear)),
					],
				),
				|| Html.div("clear-data", [Page.button("Clear saved data…", "secondary-button", Page.act(session, Settings.ask_clear))]),
			),
		],
	)
}

## `75%`, rounded as JavaScript rounds; `—` with nothing to count.
percent : U64, U64 -> Str
percent = |part, whole| if whole == 0 "—" else "${(F64.to_i64_try(FsrsMath.round(part.to_f64() * 100.0 / whole.to_f64())) ?? 0).to_str()}%"

stat : Val(ctx, Str), Str, Str -> Elem(ctx)
stat = |value, label, id|
	Html.div(
		"progress-stat",
		[
			Html.span_v(value, [Engine.class("progress-value"), Engine.test_id(id)]),
			Engine.element("span", [Engine.class("muted")], [Engine.text(label)]),
		],
	)
