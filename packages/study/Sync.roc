import fsrs.FsrsMath
import json.JsonValue
import Account
import Reading
import Review
import Study
import Words

## Cross-device sync through the Lyceum account (`POST /api/sync`; see "Sync
## contract" in the unified Lyceum plan), ported from `src/Sync.elm` and the
## pure parts of the sync functions in `src/Main.elm` (`syncedSettings`,
## `syncOutgoing`, `startSync`, `handleSynced`, `applyReceived`, `syncFailed`).
##
## History records (attempts and word reviews) never change, so devices exchange
## them and keep the union; cards are replayed from the merged history. Settings
## (theme, reader layers, positions, review settings, today's scope, reading
## goals, words marked known) can change: the newest edit wins. Drafts in
## progress stay on their device.
##
## The state remembers which account it belongs to, the server cursor, whether
## the first exchange is done, the history records the server already has, and
## the last synced value of each setting, so only new records and changed
## settings are sent. A device's first exchange only downloads settings, so a new
## device's defaults never overwrite the account's choices; a setting this device
## never synced takes the account's value.
##
## The app does the effects: it sends `Account.HttpRequest`s (with credentials,
## as the Elm app's `Http.riskyRequest` does; see `Account`), performs the
## storage `Write`s, and applies received settings to its model.
##
Sync := [].{

	State : {
		account : I64,
		cursor : I64,
		primed : Bool,
		sent : Set(Str),
		settings : Dict(Str, Setting),
	}

	## A setting as last synced: its encoded value (compact JSON text) and when it
	## was edited.
	Setting : { value : Str, updated_at : I64 }

	Status : [NotSyncing, Syncing, Synced(I64), Offline, NeedsSupporter, Failed]

	## A record to send: history records are immutable, settings (`meta:<key>`)
	## mutable.
	Outgoing : { id : Str, kind : Str, mutable : Bool, updated_at : I64, body : JsonValue }

	Received : { id : Str, kind : Str, updated_at : I64, body : JsonValue }

	Response : { records : List(Received), cursor : I64, more : Bool }

	## What sync reads from the app's model. `settings` are the synced settings
	## as they are now (`settings` below).
	Local : {
		attempts : List(Study.Attempt),
		word_reviews : List(Words.Review),
		reviews : Dict(Str, Review.Entry),
		settings : List((Str, JsonValue)),
	}

	## The values `settings` encodes, from the app's model.
	SettingsModel : {
		dark : Bool,
		reader_layers : { glosses : Bool, morphology : Bool, translation : Bool },
		positions : Dict(Str, I64),
		new_per_day : I64,
		today_scope : [Some(Str), None],
		reading_goals : Reading.Goals,
		known_marks : Dict(Str, I64),
	}

	## A put into an IndexedDB store, as `storagePut id store value` in the Elm app.
	Write : { id : Str, store : Str, value : JsonValue }

	## What `start` decided. On `Send` the app keeps `state`, marks a round busy
	## with status `Syncing`, and sends `request`, keeping `outgoing` for
	## `synced`. The Elm app also clears its pending sync time (`syncDueAt`) in
	## every case except `Wait`.
	Start : [
		NotSignedIn,
		NeedsSupporter,
		Wait,
		Send({ state : State, outgoing : List(Outgoing), request : Account.HttpRequest }),
	]

	## A finished round: the new state (already in `writes`), the merged history
	## and the passage and word cards replayed from it, the received settings to
	## apply in order (as the Elm `applySetting`; see `merge_positions`), the
	## storage writes, and whether another round should start right away (`start`
	## again). The app also ends the round with status `Synced(now)`.
	Synced : {
		state : State,
		attempts : List(Study.Attempt),
		word_reviews : List(Words.Review),
		reviews : Dict(Str, Review.Entry),
		word_cards : Dict(Str, Words.Card),
		apply : List((Str, JsonValue)),
		writes : List(Write),
		again : Bool,
	}

	empty_state : I64 -> State
	empty_state = |account| { account, cursor: 0, primed: Bool.False, sent: Set.empty(), settings: Dict.empty() }

	## At most this many records go up in a round.
	page_size : U64
	page_size = 500

	## One round: send `records`, receive everything newer than the cursor (at
	## most a page; `more` asks for another).
	request : Str, State, List(Outgoing) -> Account.HttpRequest
	request = |origin, state, records| {
		method: "POST",
		url: "${origin}/api/sync",
		headers: [Account.client_header, ("Content-Type", "application/json")],
		# The text the Elm app's `Http.jsonBody` sends (see `json_text`).
		body: json_text(
			JsonValue.object(
				[
					("app", JsonValue.str("aristos")),
					("since", JsonValue.int(state.cursor)),
					("records", JsonValue.array(records.map(encode_outgoing))),
				],
			),
		),
		timeout_ms: 30000,
	}

	## The server's answer to `request`, or why there is none.
	response_result : Try(Account.HttpResponse, Account.HttpProblem) -> Try(Response, Account.Failure)
	response_result = |result| {
		json = Account.json_body(result)?
		decode_response(json).map_err(|message| BadBody(message))
	}

	encode_state : State -> JsonValue
	encode_state = |state|
		JsonValue.object(
			[
				("account", JsonValue.int(state.account)),
				("cursor", JsonValue.int(state.cursor)),
				("primed", JsonValue.boolean(state.primed)),
				("sent", JsonValue.array(state.sent.to_list().sort_with(compare_text).map(JsonValue.str))),
				(
					"settings",
					JsonValue.object(
						state.settings
							.to_list()
							.sort_with(|(a, _), (b, _)| compare_text(a, b))
							.map(
								|(key, setting)| (
									key,
									JsonValue.object(
										[
											("value", JsonValue.str(setting.value)),
											("updatedAt", JsonValue.int(setting.updated_at)),
										],
									),
								),
							),
					),
				),
			],
		)

	## States saved before `primed` existed have finished their first exchange.
	decode_state : JsonValue -> Try(State, Str)
	decode_state = |json| {
		sent = JsonValue.items(JsonValue.field(json, "sent")?)?.map_try(JsonValue.as_str)?
		stored = as_object(JsonValue.field(json, "settings")?)?.map_try(
			|(key, setting)| Ok(
				(
					key,
					{
						value: JsonValue.as_str(JsonValue.field(setting, "value")?)?,
						updated_at: whole_number(JsonValue.field(setting, "updatedAt")?)?,
					},
				),
			),
		)?
		Ok(
			{
				account: whole_number(JsonValue.field(json, "account")?)?,
				cursor: whole_number(JsonValue.field(json, "cursor")?)?,
				primed: match JsonValue.field(json, "primed") {
					Ok(found) => JsonValue.as_bool(found) ?? Bool.True
					Err(_) => Bool.True
				},
				sent: Set.from_list(sent),
				settings: Dict.from_list(stored),
			},
		)
	}

	## The status line, given the current time.
	status_text : I64, Status -> Str
	status_text = |now, status|
		match status {
			NotSyncing => "Not synced yet"
			Syncing => "Syncing\u(2026)"
			Synced(at) =>
				if now - at < 60000 {
					"Synced just now"
				} else if now - at < 3600000 {
					"Synced ${((now - at) // 60000).to_str()} min ago"
				} else {
					"Synced over an hour ago"
				}
			Offline => "Offline: will sync when back online"
			NeedsSupporter => "Sync is for Supporters"
			Failed => "Couldn't sync: will try again"
		}

	## Whether a round is due at `now` (the Elm app's `Tick`): a rating waits a
	## few seconds (`due_at`, 0 for none) so a burst of them goes up together;
	## otherwise every few minutes.
	due : I64, I64, Status -> Bool
	due = |now, due_at, status|
		(due_at > 0 and now >= due_at)
		or (
			match status {
				Synced(at) => now - at > 3 * 60 * 1000
				_ => Bool.False
			}
		)

	## Settings that sync, as stored in the metadata store (the newest edit wins).
	## Drafts stay on their device. Main.elm's `syncedSettings`.
	settings : SettingsModel -> List((Str, JsonValue))
	settings = |model| [
		("theme", JsonValue.str(if model.dark "dark" else "light")),
		(
			"reader-layers",
			JsonValue.object(
				[
					("glosses", JsonValue.boolean(model.reader_layers.glosses)),
					("morphology", JsonValue.boolean(model.reader_layers.morphology)),
					("translation", JsonValue.boolean(model.reader_layers.translation)),
				],
			),
		),
		("positions", encode_positions(model.positions)),
		("review-settings", JsonValue.object([("newPerDay", JsonValue.int(model.new_per_day))])),
		(
			"today-scope",
			JsonValue.str(
				match model.today_scope {
					Some(scope) => scope
					None => ""
				},
			),
		),
		("reading-goals", Reading.encode_goals(model.reading_goals)),
		("known-words", Reading.encode_marks(model.known_marks)),
	]

	## Records the server doesn't have yet: history it hasn't acknowledged, and
	## settings changed since they last synced (stamped `now`), at most a page.
	## Main.elm's `syncOutgoing`.
	outgoing : I64, State, Local -> List(Outgoing)
	outgoing = |now, state, local| {
		attempts = local.attempts
			.drop_if(|attempt| state.sent.contains(attempt.id))
			.map(|attempt| { id: attempt.id, kind: "attempt", mutable: Bool.False, updated_at: attempt.finished_at, body: Study.encode_attempt(attempt) })
		word_reviews = local.word_reviews
			.drop_if(|review| state.sent.contains(Words.review_key(review)))
			.map(|review| { id: Words.review_key(review), kind: "wordreview", mutable: Bool.False, updated_at: review.at, body: Words.encode_review(review) })
		# Not before the first exchange: a new device's defaults must not overwrite
		# the account's settings.
		changed = if state.primed {
			local.settings
				.drop_if(|(key, value)| synced_value(state, key) == Some(json_text(value)))
				.map(|(key, value)| { id: "meta:${key}", kind: "setting", mutable: Bool.True, updated_at: now, body: value })
		} else {
			[]
		}
		changed.concat(attempts).concat(word_reviews).take_first(page_size)
	}

	## Syncs with the signed-in account if it includes sync and no round is
	## running (`busy`) and the stored state has loaded (`loaded`). Another
	## account on this device starts over: its whole history goes up and comes
	## down. Main.elm's `startSync`.
	start : I64, Account, { busy : Bool, loaded : Bool, state : State }, Local -> Start
	start = |now, account, round, local|
		match account {
			SignedIn(origin, user) =>
				if !Account.has_sync(user) {
					NeedsSupporter
				} else if round.busy or !round.loaded {
					Wait
				} else {
					state = if round.state.account == user.id round.state else empty_state(user.id)
					sending = outgoing(now, state, local)
					Send({ state, outgoing: sending, request: request(origin, state, sending) })
				}
			_ => NotSignedIn
		}

	## A finished round: what was sent is now on the server; received records
	## merge in; passage cards replay from the merged history. Another round
	## follows when the server has more, records are still waiting, or this was
	## the first exchange (after it, local setting edits go up). Main.elm's
	## `handleSynced` and `applyReceived`.
	synced : State, Local, List(Outgoing), Response -> Synced
	synced = |state, local, sent, response| {
		acknowledged = sent.fold(
			state,
			|acc, record|
				if record.mutable {
					{ ..acc, settings: acc.settings.insert(drop_meta(record.id), { value: json_text(record.body), updated_at: record.updated_at }) }
				} else {
					{ ..acc, sent: acc.sent.insert(record.id) }
				},
		)
		start_merge = {
			state: acknowledged,
			attempts: local.attempts,
			word_reviews: local.word_reviews,
			settings: local.settings,
			apply: [],
			writes: [],
		}
		merged = response.records.fold(start_merge, |acc, record| receive(acc, record))
		next_state = { ..merged.state, cursor: response.cursor, primed: Bool.True }
		{
			state: next_state,
			attempts: merged.attempts,
			word_reviews: merged.word_reviews,
			reviews: Review.cards(local.reviews, merged.attempts),
			word_cards: Words.cards(merged.attempts, merged.word_reviews),
			apply: merged.apply,
			# The Elm app saves the state first, then the received records, newest first.
			writes: [state_write(next_state)].concat(merged.writes.rev()),
			again: response.more or sent.len() >= page_size or !state.primed,
		}
	}

	## The sync state's row in the metadata store.
	state_write : State -> Write
	state_write = |state| {
		id: "save-sync-state",
		store: "metadata",
		value: JsonValue.object([("key", JsonValue.str("sync-state")), ("value", encode_state(state))]),
	}

	## Positions from another device merge into this device's (theirs win for the
	## same work), as the Elm `applySetting` does; other settings are read as if
	## loaded from storage. Unreadable positions change nothing.
	merge_positions : Dict(Str, I64), JsonValue -> Dict(Str, I64)
	merge_positions = |positions, received|
		match decode_positions(received) {
			Ok(theirs) => positions.insert_all(theirs)
			Err(_) => positions
		}

	## The status after a failed round, and whether to ask `/api/me` again (a 401:
	## signed out elsewhere). Main.elm's `syncFailed`; the round is no longer busy.
	failed : Account.Failure -> { status : Status, check_account : Bool }
	failed = |failure|
		match failure {
			BadStatus(402) => { status: NeedsSupporter, check_account: Bool.False }
			BadStatus(401) => { status: NotSyncing, check_account: Bool.True }
			NetworkError => { status: Offline, check_account: Bool.False }
			Timeout => { status: Offline, check_account: Bool.False }
			_ => { status: Failed, check_account: Bool.False }
		}
}

Merge : {
	state : Sync.State,
	attempts : List(Study.Attempt),
	word_reviews : List(Words.Review),
	settings : List((Str, JsonValue)),
	apply : List((Str, JsonValue)),
	writes : List(Sync.Write),
}

## Merges one received record: new history is kept (and stored); a newer setting
## replaces the local one unless the local one has an edit that hasn't synced yet
## (it is newer and will go up next). Records that don't decode are skipped.
receive : Merge, Sync.Received -> Merge
receive = |acc, record| {
	known = { ..acc, state: { ..acc.state, sent: acc.state.sent.insert(record.id) } }
	match record.kind {
		"attempt" =>
			match Study.decode_attempt(record.body) {
				Ok(attempt) =>
					if acc.attempts.any(|existing| existing.id == attempt.id) {
						known
					} else {
						{
							..known,
							attempts: acc.attempts.prepend(attempt),
							writes: acc.writes.append({ id: "sync-attempt", store: "progress", value: record.body }),
						}
					}
				Err(_) => acc
			}
		"wordreview" =>
			match Words.decode_review(record.body) {
				Ok(review) =>
					if acc.word_reviews.any(|existing| Words.review_key(existing) == Words.review_key(review)) {
						known
					} else {
						{
							..known,
							word_reviews: acc.word_reviews.prepend(review),
							writes: acc.writes.append({ id: "sync-word-review", store: "progress", value: record.body }),
						}
					}
				Err(_) => acc
			}
		"setting" => {
			key = drop_meta(record.id)
			synced = match acc.state.settings.get(key) {
				Ok(setting) => Some(setting)
				Err(_) => None
			}
			current = match acc.settings.find_first(|(name, _)| name == key) {
				Ok((_, value)) => Some(json_text(value))
				Err(_) => None
			}
			edited_here = current != synced_value(acc.state, key)
			newer = match synced {
				Some(setting) => record.updated_at > setting.updated_at
				None => Bool.True
			}
			if current != None and (synced == None or (newer and !edited_here)) {
				{
					..acc,
					state: {
						..acc.state,
						settings: acc.state.settings.insert(key, { value: json_text(record.body), updated_at: record.updated_at }),
					},
					# What the app's setting reads as once applied, for a later
					# record of the same key in this round.
					settings: acc.settings.map(
						|(name, value)|
							if name != key {
								(name, value)
							} else if key == "positions" {
								(name, encode_positions(Sync.merge_positions(decode_positions(value) ?? Dict.empty(), record.body)))
							} else {
								(name, record.body)
							},
					),
					apply: acc.apply.append((key, record.body)),
					writes: acc.writes.append(
						{
							id: "sync-${key}",
							store: "metadata",
							value: JsonValue.object([("key", JsonValue.str(key)), ("value", record.body)]),
						},
					),
				}
			} else {
				acc
			}
		}
		_ => acc
	}
}

encode_outgoing : Sync.Outgoing -> JsonValue
encode_outgoing = |record|
	JsonValue.object(
		[
			("id", JsonValue.str(record.id)),
			("type", JsonValue.str(record.kind)),
			("mutable", JsonValue.boolean(record.mutable)),
			("updatedAt", JsonValue.int(record.updated_at)),
			("body", record.body),
		],
	)

decode_response : JsonValue -> Try(Sync.Response, Str)
decode_response = |json| {
	records = JsonValue.items(JsonValue.field(json, "records")?)?.map_try(
		|record| Ok(
			{
				id: JsonValue.as_str(JsonValue.field(record, "id")?)?,
				kind: JsonValue.as_str(JsonValue.field(record, "type")?)?,
				updated_at: whole_number(JsonValue.field(record, "updatedAt")?)?,
				body: JsonValue.field(record, "body")?,
			},
		),
	)?
	Ok(
		{
			records,
			cursor: whole_number(JsonValue.field(json, "cursor")?)?,
			more: match JsonValue.field(json, "more") {
				Ok(found) => JsonValue.as_bool(found) ?? Bool.False
				Err(_) => Bool.False
			},
		},
	)
}

## The Elm `Encode.dict identity Encode.int`: keys in order.
encode_positions : Dict(Str, I64) -> JsonValue
encode_positions = |positions|
	JsonValue.object(
		positions
			.to_list()
			.sort_with(|(a, _), (b, _)| compare_text(a, b))
			.map(|(work, position)| (work, JsonValue.int(position))),
	)

decode_positions : JsonValue -> Try(Dict(Str, I64), Str)
decode_positions = |json|
	Ok(Dict.from_list(as_object(json)?.map_try(|(work, position)| Ok((work, whole_number(position)?)))?))

synced_value : Sync.State, Str -> [Some(Str), None]
synced_value = |state, key|
	match state.settings.get(key) {
		Ok(setting) => Some(setting.value)
		Err(_) => None
	}

## Elm's `String.dropLeft 5` for `meta:<key>` ids.
drop_meta : Str -> Str
drop_meta = |id| id.drop_first_bytes(5) ?? ""

## Compact JSON text as the Elm app's `Encode.encode 0` (`JSON.stringify`)
## writes it, for setting values (compared and stored) and request bodies:
## numbers in JavaScript's notation (a value received as `2.0` is written
## `2`) and integer-like object keys first, in numeric order.
json_text : JsonValue -> Str
json_text = |value| JsonValue.encode(canonical(value))

canonical : JsonValue -> JsonValue
canonical = |json|
	match as_object(json) {
		Ok(entries) => {
			indexed = entries.keep_if(|(key, _)| array_index(key).is_ok())
			JsonValue.object(
				indexed
					.sort_by(|(key, _)| array_index(key) ?? 0)
					.concat(entries.drop_if(|(key, _)| array_index(key).is_ok()))
					.map(|(key, member)| (key, canonical(member))),
			)
		}
		Err(_) =>
			match JsonValue.items(json) {
				Ok(values) => JsonValue.array(values.map(canonical))
				Err(_) =>
					match JsonValue.as_f64(json) {
						Ok(x) => JsonValue.numeral(FsrsMath.to_js_str(x))
						Err(_) => json
					}
			}
	}

## A key JavaScript orders as an array index: a canonical whole number below
## 2^32 - 1.
array_index : Str -> Try(U64, [NotIndex])
array_index = |key|
	match U64.from_str(key) {
		Ok(n) => if n < 4294967295 and n.to_str() == key Ok(n) else Err(NotIndex)
		Err(_) => Err(NotIndex)
	}

## Elm's `Json.Decode.int`: any JSON number that is a whole number.
whole_number : JsonValue -> Try(I64, Str)
whole_number = |json|
	match JsonValue.as_i64(json) {
		Ok(n) => Ok(n)
		Err(message) => {
			x = JsonValue.as_f64(json).map_err(|_| message)?
			match F64.floor_to_i64_try(x) {
				Ok(n) => if n.to_f64() == x and x.abs() <= 9007199254740991.0 Ok(n) else Err(message)
				Err(_) => Err(message)
			}
		}
	}

## Byte order, which for ASCII keys is the code unit order Elm sorts by.
compare_text : Str, Str -> [Before, Same, After]
compare_text = |a, b| compare_bytes(a.to_utf8(), b.to_utf8(), 0)

compare_bytes : List(U8), List(U8), U64 -> [Before, Same, After]
compare_bytes = |a, b, at|
	match (a.get(at), b.get(at)) {
		(Err(_), Err(_)) => Same
		(Err(_), Ok(_)) => Before
		(Ok(_), Err(_)) => After
		(Ok(x), Ok(y)) => if x < y Before else if x > y After else compare_bytes(a, b, at + 1)
	}

as_object : JsonValue -> Try(List((Str, JsonValue)), Str)
as_object = |json|
	match json {
		Object(entries) => Ok(entries)
		_ => Err("expected an object")
	}
