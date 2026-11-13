import pf.Engine
import study.Account
import study.Sync
import Model
import Storage
import Store

## The optional Lyceum account and syncing progress with it, ported from the
## account and sync branches of `src/Main.elm` (`startSync`, `handleSynced`,
## `syncFailed`, `CheckAccount`, `SignOut`, `Tick`, `VisibilityChanged`); the
## rules themselves are in the Account and Sync packages.
##
## HTTP calls are issued by View's effect sites when a call's serial changes.
## They need the account's session cookie on another origin, which the
## roc-signals runtime does not send by itself; browser-bridge.js gives the
## runtime a fetch that includes credentials (see roc-signals#206, closed in
## favour of #218, which adds a credentials field to requests).
Syncing := [].{

	## The release's account API (`config.json`), asked for once the library
	## has loaded.
	receive_config : Model.Model, Engine.Res -> Model.Model
	receive_config = |model, res|
		match Account.config_result(response(res)) {
			Ok(Some(api)) => check_account({ ..model, account: Checking(api) })
			_ => model
		}

	## Asks the account API who is signed in.
	check_account : Model.Model -> Model.Model
	check_account = |model|
		match Account.api(model.account) {
			Some(api) => { ..model, account: Checking(api), account_checked_at: model.clock, session_call: call(model.session_call, Account.session_request(api)) }
			None => model
		}

	receive_session : Model.Model, Engine.Res -> Model.Model
	receive_session = |model, res|
		match Account.api(model.account) {
			Some(api) => {
				account = Account.session_result(api, response(res))
				checked = { ..model, account }
				# The sync state is read once, when an account that syncs is signed in.
				loading = match account {
					SignedIn(_, user) if Account.has_sync(user) and !model.sync_requested => Storage.load_sync_state(checked)
					_ => checked
				}
				start(loading)
			}
			None => model
		}

	sign_out : Model.Model -> Model.Model
	sign_out = |model|
		match Account.api(model.account) {
			Some(api) => { ..model, account: Checking(api), sign_out_call: call(model.sign_out_call, Account.sign_out_request(api)) }
			None => model
		}

	## Signed out (or not): ask again who is signed in.
	signed_out : Model.Model, Engine.Res -> Model.Model
	signed_out = |model, _| check_account(model)

	## Starts a sync round if this device syncs and none is running.
	start : Model.Model -> Model.Model
	start = |model|
		match Sync.start(model.clock, model.account, { busy: model.sync_busy, loaded: model.sync_loaded, state: model.sync }, local(model)) {
			NotSignedIn => { ..model, sync_due_at: 0 }
			NeedsSupporter => { ..model, sync_status: NeedsSupporter, sync_due_at: 0 }
			Wait => model
			Send(round) => { ..model, sync: round.state, sync_sent: round.outgoing, sync_busy: Bool.True, sync_status: Syncing, sync_due_at: 0, sync_call: call(model.sync_call, round.request) }
		}

	## A finished round: received records and settings merge in, cards replay,
	## and another round follows if the server has more.
	receive_sync : Model.Model, Engine.Res -> Model.Model
	receive_sync = |model, res|
		match Sync.response_result(response(res)) {
			Ok(answer) => {
				round = Sync.synced(model.sync, local(model), model.sync_sent, answer)
				applied = round.apply.fold(model, |m, (key, value)| Storage.apply_setting(m, key, value))
				merged = Model.send(
					{
						..applied,
						sync: round.state,
						attempts: round.attempts,
						word_reviews: round.word_reviews,
						entries: round.reviews,
						word_cards: round.word_cards,
						sync_sent: [],
						sync_busy: Bool.False,
						sync_status: Synced(model.clock),
					},
					round.writes.map(|write| ("save", |id| Store.put(id, write.store, write.value))),
				)
				if round.again start(merged) else merged
			}
			Err(failure) => {
				outcome = Sync.failed(failure)
				idle = { ..model, sync_busy: Bool.False, sync_sent: [], sync_status: outcome.status }
				# Signed out elsewhere: ask who is signed in.
				if outcome.check_account check_account(idle) else idle
			}
		}

	## Every few seconds: a sync that is due starts; an unreachable account is
	## asked again every five minutes.
	tick : Model.Model -> Model.Model
	tick = |model| {
		checked = match model.account {
			Unreachable(_) if model.clock - model.account_checked_at >= 5 * 60 * 1000 => check_account(model)
			_ => model
		}
		if Sync.due(checked.clock, checked.sync_due_at, checked.sync_status) start(checked) else checked
	}

	## The Engine request for a call (none before its first serial).
	requests : Model.Call -> List(Engine.Req)
	requests = |found|
		if found.serial == 0 {
			[]
		} else {
			request = found.request
			[Http({ method: request.method, url: request.url, headers: request.headers, body: request.body, timeout_ms: request.timeout_ms.to_u32_wrap() })]
		}
}

call : Model.Call, Account.HttpRequest -> Model.Call
call = |previous, request| { serial: previous.serial + 1, request }

## What sync sends and merges: the history and the settings that sync.
local : Model.Model -> Sync.Local
local = |model| {
	attempts: model.attempts,
	word_reviews: model.word_reviews,
	reviews: model.entries,
	settings: Sync.settings({ dark: model.dark, reader_layers: model.reader_layers, positions: model.positions, new_per_day: model.new_per_day, today_scope: model.today_scope }),
}

## An HTTP result as the Account package reads it.
response : Engine.Res -> Try(Account.HttpResponse, Account.HttpProblem)
response = |res|
	match res {
		Http(found) => Ok({ status: found.status, body: found.body })
		Timeout => Err(Timeout)
		_ => Err(NetworkError)
	}
