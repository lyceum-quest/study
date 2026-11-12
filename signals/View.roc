import pf.Engine exposing [Elem, State]
import pf.Html
import json.JsonValue
import study.Route
import Model
import Nav
import Page
import Storage
import Update
import Workspace
import LibraryView
import WorkspaceView

## The page, ported from `view` and `viewAppHeader` in `src/Main.elm`, and the
## app's effect sites: the preload downloads, the `<lyceum-store>` element
## that carries storage requests and results (see Store), the URL, the
## document title, and a clock refresh.
View := [].{

	program : Engine.Program
	program = Engine.program_boot({ storage_keys: [], max_inflight: 32 }, |boot| Engine.state(Update.step(Nav.init(boot.url), |m| m), View.page))

	page : State(Page.S, Model.Model) -> Elem(Page.S)
	page = |session| {
		model = session.val()
		# Workaround: roc-signals 0.3.0 delivers key events only to elements of
		# the app, not the document, so the shell takes focus (and keeps it on
		# clicks inside it) to receive the workspace's shortcuts; text fields
		# stop their own keys. See
		# https://github.com/thebrandonlucas/roc-issues/tree/master/roc-signals/RS-004-document-key-events.
		Engine.element(
			"div",
			[
				Engine.class_v(model.map(|m| if m.dark "app-shell dark-theme" else "app-shell light-theme")),
				Engine.attr("tabindex", "-1"),
				Engine.attr("style", "outline: none"),
				Engine.ref("shell"),
				Engine.on("keydown", Page.act_value(session, shortcut)),
			],
			[
				header(session),
				Engine.when(
					model.map(|m| m.notice != ""),
					|| Html.div_attrs(
						[Engine.class("notice"), Engine.attr("role", "status")],
						[
							Html.span_v(model.map(|m| m.notice), [Engine.test_id("notice")]),
							Html.button("×", [Engine.attr("type", "button"), Html.aria_label("Dismiss message")], Page.act(session, |m| { ..m, notice: "" })),
						],
					),
					|| Engine.text(""),
				),
				Engine.switch(
					model.map(screen_name),
					["library", "workspace", "loading", "elm"],
					|found| match found {
						"library" => LibraryView.view(session)
						"workspace" => WorkspaceView.view(session)
						"loading" => Engine.element("main", [Engine.class("page")], [Html.p("Loading…", "muted")])
						_ => elm_page(session)
					},
				),
				Engine.element(
					"lyceum-store",
					[Engine.attr("hidden", "true"), Engine.test_id("store"), Engine.attr_v("data-request", model.map(|m| m.outbox)), Engine.on("change", Page.act_value(session, Storage.receive))],
					[],
				),
				Engine.watch(Engine.const("/preload/corpora.json"), download, session.on_result(|m, _, res| Update.step(m, |x| Nav.receive_manifest(x, Engine.http_text(res))))),
				Engine.watch(
					model.map(|m| { req = Nav.corpus_request(m)
						{ url: req.conllu, serial: req.serial } }),
					|req| download(req.url),
					session.on_result(|m, req, res| Update.step(m, |x| Nav.receive_conllu(x, req.url, Engine.http_text(res)))),
				),
				Engine.watch(
					model.map(|m| { req = Nav.corpus_request(m)
						{ url: req.units, serial: req.serial } }),
					|req| download(req.url),
					session.on_result(|m, req, res| Update.step(m, |x| Nav.receive_units(x, req.url, Engine.http_text(res)))),
				),
				Engine.watch(
					Engine.const({}),
					|_| [Popstate, Interval(5000), Focus("shell")],
					session.on_result(
						|m, _, res| match res {
							Location(url) => Update.located(m, url)
							Fired => Update.step(m, Storage.refresh_clock)
							_ => m
						},
					),
				),
				Engine.watch(model.map(|m| m.url), |url| if url.serial == 0 [] else if url.push [Push(url.path)] else [Replace(url.path)], session.on_result(|m, _, _| m)),
				Engine.watch(model.map(Model.document_title), |title| [Title(title)], session.on_result(|m, _, _| m)),
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

screen_name : Model.Model -> Str
screen_name = |model|
	match model.screen {
		LibraryScreen => "library"
		WorkspaceScreen => if model.corpus_ready "workspace" else "loading"
		_ => "elm"
	}

## The workspace's keyboard shortcuts (`handleShortcut`).
shortcut : Model.Model, Str -> Model.Model
shortcut = |model, key|
	match (model.screen, key) {
		(WorkspaceScreen, "ArrowLeft") | (WorkspaceScreen, "k") => Workspace.previous(model)
		(WorkspaceScreen, "ArrowRight") | (WorkspaceScreen, "j") => Workspace.next(model)
		(WorkspaceScreen, "Escape") =>
			if model.history_open {
				Workspace.close_history(model)
			} else if model.popup_word != None {
				Workspace.close_popup(model)
			} else {
				Workspace.close_workbench(model)
			}
		_ => model
	}

## A page still served by the Elm app, beside this one on the same origin.
elm_page : State(Page.S, Model.Model) -> Elem(Page.S)
elm_page = |session|
	Engine.element(
		"main",
		[Engine.class("page")],
		[
			Engine.element(
				"p",
				[Engine.class("muted")],
				[Engine.text("This page is still in the Elm app. "), Engine.element("a", [Engine.attr_v("href", session.val().map(|m| "/${m.current_path}"))], [Engine.text("Open it there →")])],
			),
		],
	)

header : State(Page.S, Model.Model) -> Elem(Page.S)
header = |session| {
	model = session.val()
	nav_button = |label, active, change|
		Html.button(label, [Engine.class_v(model.map(|m| if active(m) "global-nav-button is-active" else "global-nav-button")), Engine.attr("type", "button")], Page.act(session, change))
	Engine.element(
		"header",
		[Engine.class("app-header")],
		[
			Engine.element(
				"button",
				[
					Engine.class("brand-button"),
					Engine.attr("type", "button"),
					Html.aria_label("Lyceum Study library"),
					Engine.on_click(Page.act(session, |m| { ..m, screen: LibraryScreen, notice: "", popup_word: None })),
				],
				[Engine.element("span", [Engine.class("brand-word")], [Engine.text("Lyceum Study")])],
			),
			Engine.element(
				"nav",
				[Engine.class("global-nav"), Html.aria_label("Primary navigation")],
				[
					nav_button("Home", |m| m.screen == LibraryScreen or m.screen == TodayScreen, |m| Nav.go_route(m, Library)),
					nav_button("Progress", |m| m.screen == StatsScreen, |m| Nav.go_route(m, Stats)),
					# Supporters don't see it; without an account API it points at lyceum.quest.
					Engine.element("a", [Engine.class("global-nav-button"), Engine.attr("href", "https://lyceum.quest/pricing"), Engine.attr("target", "_blank"), Engine.attr("rel", "noopener"), Engine.attr("title", "Support Lyceum")], [Engine.text("Support")]),
					nav_button("What's new", |m| m.screen == WhatsNewScreen, |m| Nav.go_route(m, WhatsNew)),
					Engine.when(
						model.map(|m| m.active != None),
						|| Html.div_attrs(
							[Engine.attr("style", "display: contents")],
							[
								nav_button("Read", |_| Bool.False, |m| Nav.go_route(m, Reader(Model.active_id(m), Some(Model.current_ref(m))))),
								nav_button("Study", |m| m.screen == WorkspaceScreen or m.screen == SettingsScreen, |m| Nav.start_today_in(m, Model.active_id(m))),
							],
						),
						|| Engine.text(""),
					),
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
							Html.aria_label_v(model.map(theme_action)),
							Engine.attr_v("aria-pressed", model.map(|m| if m.dark "true" else "false")),
							Engine.attr_v("title", model.map(theme_action)),
							Engine.on_click(Page.act(session, toggle_theme)),
						],
						[
							Html.span_v(model.map(|m| if m.dark "☀" else "☾"), [Engine.attr("aria-hidden", "true")]),
							Html.span_v(model.map(|m| if m.dark "Light" else "Dark"), [Engine.class("theme-label")]),
						],
					),
				],
			),
		],
	)
}

theme_action : Model.Model -> Str
theme_action = |model| if model.dark "Use light theme" else "Use dark theme"

## The theme the Elm app also uses, saved where it keeps it.
toggle_theme : Model.Model -> Model.Model
toggle_theme = |model| {
	dark = !model.dark
	Model.put_setting({ ..model, dark }, "save", "theme", JsonValue.str(if (dark) "dark" else "light"))
}
