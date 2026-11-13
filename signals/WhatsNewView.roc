import pf.Engine exposing [Elem, State]
import pf.Html
import Model
import Page

## The What's new page, ported from `viewWhatsNew` and `viewChangelogVersion`
## in `src/Main.elm`: CHANGELOG.md, fetched when the page is first opened.
WhatsNewView := [].{

	view : State(Page.S, Model.Model) -> Elem(Page.S)
	view = |session| {
		model = session.signal()
		Engine.element(
			"section",
			[Engine.class("whats-new")],
			[
				Engine.element("h1", [], [Engine.text("What's new")]),
				Engine.switch(
					model.map(
						|m| match m.changelog {
							ChangelogLoaded(_) => "loaded"
							ChangelogFailed => "failed"
							_ => "loading"
						},
					),
					["loaded", "failed", "loading"],
					|found| match found {
						"loaded" =>
							Html.div_attrs(
								[Engine.attr("style", "display: contents")],
								[
									Html.p("New texts, features and fixes in Lyceum Study, newest first.", "whats-new-intro"),
									Engine.each(model.map(versions), |version| version.name, |row| version_view(row.field(|version| version))),
								],
							)
						"failed" => Engine.element("p", [], [Engine.text("The list of changes couldn't be loaded. Check your connection and open this page again.")])
						_ => Engine.element("p", [], [Engine.text("Loading…")])
					},
				),
			],
		)
	}
}

Version : { name : Str, sections : List({ key : Str, title : Str, items : List({ key : Str, text : Str }) }) }

versions : Model.Model -> List(Version)
versions = |model|
	match model.changelog {
		ChangelogLoaded(found) =>
			found.map(
				|version| {
					name: version.name,
					sections: version.sections.map_with_index(|section, index| { key: index.to_str(), title: section.title, items: section.items.map_with_index(|item, n| { key: n.to_str(), text: item }) }),
				},
			)
		_ => []
	}

version_view : Engine.Signal(ctx, Version) -> Elem(ctx)
version_view = |version|
	Engine.element(
		"article",
		[Engine.class("whats-new-version")],
		[
			Engine.element("h2", [], [Engine.text_s(version.map(|v| if v.name == "Unreleased" "Not yet released" else v.name))]),
			Engine.each(
				version.map(|v| v.sections),
				|section| section.key,
				|row| Engine.element(
					"div",
					[Engine.attr("style", "display: contents")],
					[
						Engine.when(row.field(|section| section.title != ""), || Engine.element("h3", [], [Engine.text_s(row.field(|section| section.title))]), || Engine.text("")),
						Engine.element("ul", [], [Engine.each(row.field(|section| section.items), |item| item.key, |item| Engine.element("li", [], [Engine.text_s(item.field(|i| i.text))]))]),
					],
				),
			),
		],
	)
