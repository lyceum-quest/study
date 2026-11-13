import json.JsonValue

## The storage protocol between this app and the `<lyceum-store>` element that
## browser-bridge.js defines, which runs the requests on the Elm app's IndexedDB
## database ("aristos", stores `corpora`, `metadata` and `progress`).
##
## A request batch is the element's `data-request` attribute: a JSON array of
## messages in the shape the Elm app's `storageRequest` port sends,
## `{"id", "operation": "get"|"put"|"getAll"|"clear", "store", "key"?, "value"?}`.
## The element performs each message when the attribute changes, so every batch
## must carry fresh ids (an equal attribute value is never written again).
##
## Each result arrives as a `change` event on the element, whose `value` is the
## JSON of `storageResponse` plus the time it finished:
## `{"id", "ok", "value", "now"}`, with `value` the record (`get`, `null` when
## absent), the list of records (`getAll`), the stored record (`put`) or `null`
## (`clear`, or a failure). `now` is `Date.now()`, the app's only wall clock, and
## `offset` the browser's UTC offset in minutes (east positive), the fixed
## zone Elm's `Time.here` gives; `offset` may be absent (then 0).
##
## Workaround: roc-signals 0.3.0 has only local storage, so IndexedDB is reached
## through this custom element
## (https://github.com/lukewilliamboswell/roc-signals/issues/201; roc-issues
## archive/RS-002-asynchronous-storage). roc-signals 0.4.0 added typed ports
## (`Port.call`), which can replace it once the app is on 0.4.0 or later.
Store := [].{

	Response : { id : Str, ok : Bool, value : JsonValue, now : I64, offset : I64 }

	get : Str, Str, Str -> JsonValue
	get = |id, store, key| message(id, "get", store, [("key", JsonValue.str(key))])

	get_all : Str, Str -> JsonValue
	get_all = |id, store| message(id, "getAll", store, [])

	put : Str, Str, JsonValue -> JsonValue
	put = |id, store, record| message(id, "put", store, [("value", record)])

	## Deletes every record of `store`.
	clear : Str, Str -> JsonValue
	clear = |id, store| message(id, "clear", store, [])

	## A `metadata` record: the Elm app keeps settings as `{"key", "value"}`.
	setting : Str, JsonValue -> JsonValue
	setting = |key, value| JsonValue.object([("key", JsonValue.str(key)), ("value", value)])

	batch : List(JsonValue) -> Str
	batch = |messages| JsonValue.encode(JsonValue.array(messages))

	response : Str -> Try(Response, Str)
	response = |payload| {
		json = JsonValue.decode(payload)?
		Ok(
			{
				id: JsonValue.as_str(JsonValue.field(json, "id")?)?,
				ok: JsonValue.as_bool(JsonValue.field(json, "ok")?)?,
				value: JsonValue.field(json, "value")?,
				now: JsonValue.as_i64(JsonValue.field(json, "now")?)?,
				offset: match JsonValue.field(json, "offset") {
					Ok(minutes) => JsonValue.as_i64(minutes)?
					Err(_) => 0
				},
			},
		)
	}
}

message : Str, Str, Str, List((Str, JsonValue)) -> JsonValue
message = |id, operation, store, rest|
	JsonValue.object([("id", JsonValue.str(id)), ("operation", JsonValue.str(operation)), ("store", JsonValue.str(store))].concat(rest))
