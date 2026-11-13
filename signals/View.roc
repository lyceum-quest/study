import pf.Engine exposing [Elem, State]
import pf.Html
import json.JsonValue
import study.Route
import Model
import Nav
import Page
import Storage
import Update
import Reader
import ReaderView
import Workspace
import AccountView
import Syncing
import study.Account
import LibraryView
import WorkspaceView
import WordsView
import WhatsNewView
import StatsView
import SettingsView

## The page, ported from `view` and `viewAppHeader` in `src/Main.elm`, and the
## app's effect sites: the preload downloads, the `<lyceum-store>` element
## that carries storage requests and results (see Store), the URL, the
## document title, and a clock refresh.
View := [].{

	program : Engine.Program
	program = Engine.program_boot({ storage_keys: [], max_inflight: 32 }, |boot| Engine.state(Update.step(Nav.init(boot.url), |m| m), View.page))

	page : State(Page.S, Model.Model) -> Elem(Page.S)
	page = |session| {
		model = session.signal()
		# Workaround: roc-signals 0.5.0 delivers key events only to elements of
		# the app, not the document, so the shell takes focus (and keeps it on
		# clicks inside it) to receive the workspace's shortcuts; text fields
		# stop their own keys. See
		# https://github.com/lukewilliamboswell/roc-signals/issues/203 (roc-issues
		# archive/RS-004-document-key-events), closed in favour of roc-signals#212,
		# which delivers keys at the document; drop this once the app is on a
		# release that has it.
		Engine.element(
			"div",
			[
				Engine.class_s(model.map(|m| "app-shell ${if m.dark "dark-theme" else "light-theme"}${if m.screen == ReaderScreen " is-reading" else ""}")),
				Engine.attr("tabindex", "-1"),
				Engine.attr("style", "outline: none"),
				Engine.ref("shell"),
				Engine.on("keydown", Page.act_value(session, shortcut)),
			],
			[
				# The reader has its own bar.
				Engine.when(model.map(|m| m.screen != ReaderScreen), || header(session), || Engine.text("")),
				Engine.when(
					model.map(|m| m.notice != ""),
					|| Html.div_attrs(
						[Engine.class("notice"), Engine.attr("role", "status")],
						[
							Html.span_s(model.map(|m| m.notice), [Engine.test_id("notice")]),
							Html.button("×", [Engine.attr("type", "button"), Html.aria_label("Dismiss message")], Page.act(session, |m| { ..m, notice: "" })),
						],
					),
					|| Engine.text(""),
				),
				Engine.switch(
					model.map(screen_name),
					["library", "workspace", "reader", "loading", "today", "word", "word-review", "whats-new", "stats", "settings"],
					|found| match found {
						"library" => LibraryView.view(session)
						"today" => WordsView.today_page(session)
						"word" => WordsView.word_page(session)
						"word-review" => WordsView.word_review(session)
						"whats-new" => WhatsNewView.view(session)
						"stats" => StatsView.view(session)
						"settings" => SettingsView.view(session)
						"workspace" => WorkspaceView.view(session)
						"reader" => ReaderView.view(session, Page.act(session, toggle_theme), theme_action)
						"loading" => Engine.element("main", [Engine.class("page")], [Html.p("Loading…", "muted")])
						_ => Engine.text("")
					},
				),
				Engine.element(
					"lyceum-store",
					[Engine.attr("hidden", "true"), Engine.test_id("store"), Engine.attr_s("data-request", model.map(|m| m.outbox)), Engine.on("change", Page.act_value(session, Storage.receive))],
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
					|_| [Popstate, Interval(5000), VisibilityChanges, Focus("shell")],
					session.on_result(
						|m, _, res| match res {
							Location(url) => Update.located(m, url)
							Fired => Update.step(m, |x| Syncing.tick(Storage.refresh_clock(x)))
							Visible(Bool.True) => Update.step(m, Syncing.start)
							_ => m
						},
					),
				),
				Engine.watch(model.map(|m| m.url), |url| if url.serial == 0 [] else if url.push [Push(url.path)] else [Replace(url.path)], session.on_result(|m, _, _| m)),
				Engine.watch(model.map(Model.document_title), |title| [Title(title)], session.on_result(|m, _, _| m)),
				# The account API (config.json) once the library has loaded, then its calls.
				Engine.watch(model.map(|m| m.manifest_loaded), |loaded| if loaded Syncing.requests({ serial: 1, request: Account.config_request }) else [], session.on_result(|m, _, res| Update.step(m, |x| Syncing.receive_config(x, res)))),
				Engine.watch(model.map(|m| m.session_call), Syncing.requests, session.on_result(|m, _, res| Update.step(m, |x| Syncing.receive_session(x, res)))),
				Engine.watch(model.map(|m| m.sign_out_call), Syncing.requests, session.on_result(|m, _, res| Update.step(m, |x| Syncing.signed_out(x, res)))),
				Engine.watch(model.map(|m| m.sync_call), Syncing.requests, session.on_result(|m, _, res| Update.step(m, |x| Syncing.receive_sync(x, res)))),
				Engine.watch(model.map(|m| if m.lemma_index == IndexLoading "/preload/lemmas.json" else ""), download, session.on_result(|m, _, res| Update.step(m, |x| Nav.receive_lemma_index(x, Engine.http_text(res))))),
				Engine.watch(model.map(|m| if m.changelog == ChangelogLoading "/CHANGELOG.md" else ""), download, session.on_result(|m, _, res| Update.step(m, |x| Nav.receive_changelog(x, Engine.http_text(res))))),
			],
		)
	}
}

## A GET of a preload file, revalidated as the Elm app does; "" asks for nothing.
download : Str -> List(Engine.Request)
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
		TodayScreen => "today"
		WordScreen(_) => "word"
		WordReviewScreen(_) => "word-review"
		WhatsNewScreen => "whats-new"
		StatsScreen => "stats"
		SettingsScreen => "settings"
		WorkspaceScreen => if model.corpus_ready "workspace" else "loading"
		ReaderScreen => if model.corpus_ready "reader" else "loading"
	}

## The workspace's keyboard shortcuts (`handleShortcut`).
shortcut : Model.Model, Str -> Model.Model
shortcut = |model, key|
	match (model.screen, key) {
		(WorkspaceScreen, "ArrowLeft") | (WorkspaceScreen, "k") => Workspace.previous(model)
		(WorkspaceScreen, "ArrowRight") | (WorkspaceScreen, "j") => Workspace.next(model)
		(ReaderScreen, "ArrowLeft") | (ReaderScreen, "k") => Reader.step(model, -1)
		(ReaderScreen, "ArrowRight") | (ReaderScreen, "j") => Reader.step(model, 1)
		(ReaderScreen, "Escape") => Reader.escape(model)
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

header : State(Page.S, Model.Model) -> Elem(Page.S)
header = |session| {
	model = session.signal()
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
					nav_button(session, "Home", |m| m.screen == LibraryScreen or m.screen == TodayScreen, |m| Nav.go_route(m, Library)),
					nav_button(session, "Progress", |m| m.screen == StatsScreen, |m| Nav.go_route(m, Stats)),
					AccountView.support_link(session),
					nav_button(session, "What's new", |m| m.screen == WhatsNewScreen, |m| Nav.go_route(m, WhatsNew)),
					Engine.when(
						model.map(|m| m.active != None),
						|| Html.div_attrs(
							[Engine.attr("style", "display: contents")],
							[
								nav_button(session, "Read", |_| Bool.False, |m| Nav.go_route(m, Reader(Model.active_id(m), Some(Model.current_ref(m))))),
								nav_button(session, "Study", |m| m.screen == WorkspaceScreen or m.screen == SettingsScreen, |m| Nav.start_today_in(m, Model.active_id(m))),
							],
						),
						|| Engine.text(""),
					),
				],
			),
			Html.div(
				"header-actions",
				[
					AccountView.button(session),
					Engine.element(
						"button",
						[
							Engine.class("theme-button"),
							Engine.attr("type", "button"),
							Html.aria_label_s(model.map(theme_action)),
							Engine.attr_s("aria-pressed", model.map(|m| if m.dark "true" else "false")),
							Engine.attr_s("title", model.map(theme_action)),
							Engine.on_click(Page.act(session, toggle_theme)),
						],
						[
							Html.span_s(model.map(|m| if m.dark "☀" else "☾"), [Engine.attr("aria-hidden", "true")]),
							Html.span_s(model.map(|m| if m.dark "Light" else "Dark"), [Engine.class("theme-label")]),
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


nav_button : State(Page.S, Model.Model), Str, (Model.Model -> Bool), (Model.Model -> Model.Model) -> Elem(Page.S)
nav_button = |session, label, active, change|
	Html.button(label, [Engine.class_s(session.signal().map(|m| if active(m) "global-nav-button is-active" else "global-nav-button")), Engine.attr("type", "button")], Page.act(session, change))
