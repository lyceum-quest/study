import pf.Engine exposing [Elem, State]
import pf.Html
import study.Account
import study.Route
import study.Sync
import Model
import Page
import Syncing

## The optional Lyceum account, ported from `viewAccountButton`,
## `viewSupportLink` and `viewAccountPanel` in `src/Main.elm`: shown only when
## the release names an account API (config.json).
AccountView := [].{

	## Sign-in in the header, or the signed-in handle (with the sync status).
	button : State(Page.S, Model.Model) -> Elem(Page.S)
	button = |session| {
		model = session.val()
		Engine.switch(
			model.map(account_state),
			["signed-out", "signed-in", "none"],
			|found| match found {
				"signed-out" =>
					Engine.element(
						"a",
						[Engine.class("account-button"), Engine.attr_v("href", model.map(login_href))],
						[Engine.text("Sign in"), Engine.element("span", [Engine.class("account-label")], [Engine.text(" to sync")])],
					)
				"signed-in" =>
					Engine.element(
						"a",
						[Engine.class("account-button"), Engine.attr("href", Route.to_path(Stats)), Engine.attr_v("title", model.map(signed_in_title))],
						[Html.span_v(model.map(handle), [Engine.class("account-handle")])],
					)
				_ => Engine.text("")
			},
		)
	}

	## Support Lyceum, on Lyceum's own site (the account API's origin;
	## lyceum.quest without one), in a new tab so the session stays open.
	## Supporters don't see it.
	support_link : State(Page.S, Model.Model) -> Elem(Page.S)
	support_link = |session| {
		model = session.val()
		Engine.when(
			model.map(|m| !supporter(m)),
			|| Engine.element(
				"a",
				[Engine.class("global-nav-button"), Engine.attr_v("href", model.map(|m| "${origin(m)}/pricing")), Engine.attr("target", "_blank"), Engine.attr("rel", "noopener"), Engine.attr("title", "Support Lyceum")],
				[Engine.text("Support")],
			),
			|| Engine.text(""),
		)
	}

	## The account panel on the Progress page.
	panel : State(Page.S, Model.Model) -> Elem(Page.S)
	panel = |session| {
		model = session.val()
		Engine.switch(
			model.map(panel_state),
			["checking", "unreachable", "signed-out", "synced", "supporter", "none"],
			|found| match found {
				"checking" => section([Html.p("Checking your Lyceum account…", "muted")])
				"unreachable" => section([Html.p("Your Lyceum account can't be reached right now. Progress is saved on this device.", "muted")])
				"signed-out" =>
					section(
						[
							Engine.element("p", [], [Engine.text("Progress is saved on this device only. Sign in with a Lyceum account to sync it across devices.")]),
							Engine.element("a", [Engine.class("primary-button"), Engine.attr_v("href", model.map(login_href))], [Engine.text("Sign in to sync")]),
						],
					)
				"synced" =>
					section(
						[
							signed_in_line(session),
							Html.p_v(model.map(|m| Sync.status_text(m.clock, m.sync_status)), [Engine.class("muted sync-status")]),
							Html.button("Sync now", [Engine.class("secondary-button"), Engine.attr("type", "button"), Html.disabled(model.map(|m| m.sync_busy))], Page.act(session, Syncing.start)),
							Page.button("Sign out", "secondary-button", Page.act(session, Syncing.sign_out)),
						],
					)
				"supporter" =>
					section(
						[
							signed_in_line(session),
							Html.p("Progress is saved on this device. Syncing it across your devices comes with supporting Lyceum.", "muted"),
							Engine.element("a", [Engine.class("secondary-button"), Engine.attr_v("href", model.map(|m| "${origin(m)}/pricing"))], [Engine.text("Support Lyceum")]),
							Page.button("Sign out", "secondary-button", Page.act(session, Syncing.sign_out)),
						],
					)
				_ => Engine.text("")
			},
		)
	}
}

section : List(Elem(ctx)) -> Elem(ctx)
section = |children| Engine.element("section", [Engine.class("account-panel")], children)

signed_in_line : State(Page.S, Model.Model) -> Elem(Page.S)
signed_in_line = |session|
	Engine.element(
		"p",
		[],
		[Engine.text("Signed in to Lyceum as "), Html.span_v(session.val().map(handle), [Engine.class("account-handle")]), Engine.text(".")],
	)

account_state : Model.Model -> Str
account_state = |model|
	match model.account {
		SignedOut(_, _) => "signed-out"
		SignedIn(_, _) => "signed-in"
		_ => "none"
	}

panel_state : Model.Model -> Str
panel_state = |model|
	match model.account {
		Checking(_) => "checking"
		Unreachable(_) => "unreachable"
		SignedOut(_, _) => "signed-out"
		SignedIn(_, user) => if Account.has_sync(user) "synced" else "supporter"
		NotConfigured => "none"
	}

handle : Model.Model -> Str
handle = |model|
	match model.account {
		SignedIn(_, user) => user.handle
		_ => ""
	}

signed_in_title : Model.Model -> Str
signed_in_title = |model|
	match model.account {
		SignedIn(_, user) => if Account.has_sync(user) "Signed in as ${user.handle} · ${Sync.status_text(model.clock, model.sync_status)}" else "Signed in as ${user.handle}"
		_ => ""
	}

supporter : Model.Model -> Bool
supporter = |model|
	match model.account {
		SignedIn(_, user) => user.pro
		_ => Bool.False
	}

origin : Model.Model -> Str
origin = |model| Model.with_default(Account.api(model.account), "https://lyceum.quest")

## Sign-in, returning to this page.
login_href : Model.Model -> Str
login_href = |model|
	match model.account {
		SignedOut(_, login_url) => Account.login_href(login_url, "${model.app_url}${model.current_path}")
		_ => ""
	}
