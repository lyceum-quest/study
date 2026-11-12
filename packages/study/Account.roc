import json.JsonValue

## The optional Lyceum account, ported from `src/Account.elm` (see
## `docs/dev_guide/auth-pattern.md`, "Apps on subdomains", in the Lyceum website).
##
## `/config.json`, written into each release, names the account API's origin;
## without one Lyceum Study shows no sign-in. Sign-in happens on Lyceum's own
## pages: Lyceum Study only asks `/api/me` who is signed in (sending the shared
## session cookie) and links to Lyceum's login page with a `return` URL. A
## Supporter's progress syncs through it (see `Sync`).
##
## HTTP is the app's: each call is a plain `HttpRequest` to send, and a function
## that reads what came back into the result the Elm handler produced. The Elm
## app sends the account API calls (`/api/me`, `/api/logout`, `/api/sync`) with
## `Http.riskyRequest`, that is with credentials, so the session cookie goes
## along; the roc-signals runtime cannot do that yet, which the app must solve.
Account := [
	NotConfigured,
	Checking(Str),
	SignedOut(Str, Str),
	SignedIn(Str, User),
	Unreachable(Str),
].{

	## Only the fields Lyceum documents for apps.
	User : { id : I64, handle : Str, pro : Bool, entitlements : List(Str) }

	## A request for the app to send. `timeout_ms` is the Elm request's timeout
	## (0 for none).
	HttpRequest : { method : Str, url : Str, headers : List((Str, Str)), body : Str, timeout_ms : U64 }

	## What came back, if anything did.
	HttpResponse : { status : U16, body : Str }

	## Why no response came back.
	HttpProblem : [NetworkError, Timeout]

	## Elm's `Http.Error`, as far as these calls can fail: a status outside 2xx,
	## no response, or a body that does not decode.
	Failure : [BadStatus(U16), NetworkError, Timeout, BadBody(Str)]

	## The account API origin, once the config has named one.
	api : Account -> [Some(Str), None]
	api = |account|
		match account {
			NotConfigured => None
			Checking(origin) => Some(origin)
			SignedOut(origin, _) => Some(origin)
			SignedIn(origin, _) => Some(origin)
			Unreachable(origin) => Some(origin)
		}

	## Sent with every API call; state-changing calls from an app origin are
	## refused without it.
	client_header : (Str, Str)
	client_header = ("X-Lyceum-Client", "aristos/1")

	## `GET /config.json`, uncached.
	config_request : HttpRequest
	config_request = {
		method: "GET",
		url: "/config.json",
		headers: [("Cache-Control", "no-cache")],
		body: "",
		timeout_ms: 0,
	}

	## `Ok(None)` when the config names no account API. A missing or unreadable
	## `config.json` (the local preview without one) is an error, which callers
	## treat the same way.
	config_result : Try(HttpResponse, HttpProblem) -> Try([Some(Str), None], Failure)
	config_result = |result| {
		json = json_body(result)?
		origin = match JsonValue.field(json, "accountApi") {
			Ok(found) => match JsonValue.as_str(found) {
				Ok(text) => drop_trailing_slash(text.trim())
				Err(_) => ""
			}
			Err(_) => ""
		}
		Ok(if origin == "" None else Some(origin))
	}

	## `GET <origin>/api/me` with credentials.
	session_request : Str -> HttpRequest
	session_request = |origin| {
		method: "GET",
		url: "${origin}/api/me",
		headers: [client_header],
		body: "",
		timeout_ms: 15000,
	}

	## Who is signed in; any failure (offline, blocked, server down) is `Unreachable`.
	session_result : Str, Try(HttpResponse, HttpProblem) -> Account
	session_result = |origin, result|
		match json_body(result) {
			Ok(json) => match decode_me(origin, json) {
				Ok(account) => account
				Err(_) => Unreachable(origin)
			}
			Err(_) => Unreachable(origin)
		}

	## `POST <origin>/api/logout` with credentials; the caller asks `/api/me`
	## again whatever the result.
	sign_out_request : Str -> HttpRequest
	sign_out_request = |origin| {
		method: "POST",
		url: "${origin}/api/logout",
		headers: [client_header],
		body: "",
		timeout_ms: 15000,
	}

	## Lyceum's login page, returning to `return_url` (which must be on an origin
	## Lyceum allows) after sign-in.
	login_href : Str, Str -> Str
	login_href = |login_url, return_url| {
		separator = if login_url.contains("?") "&" else "?"
		"${login_url}${separator}return=${percent_encode(return_url)}"
	}

	## Whether the signed-in account includes sync (a Supporter feature).
	has_sync : User -> Bool
	has_sync = |user| user.entitlements.contains("sync")

	## The body of a 2xx response as JSON, as Elm's `Http.expectJson` reads it.
	json_body : Try(HttpResponse, HttpProblem) -> Try(JsonValue, Failure)
	json_body = |result|
		match result {
			Err(NetworkError) => Err(NetworkError)
			Err(Timeout) => Err(Timeout)
			Ok(response) =>
				if response.status < 200 or response.status > 299 {
					Err(BadStatus(response.status))
				} else {
					JsonValue.decode(response.body).map_err(|message| BadBody(message))
				}
		}
}

## `{"user": {...}}` signed in, `{"user": null, "login_url": ...}` signed out.
decode_me : Str, JsonValue -> Try(Account, Str)
decode_me = |origin, json| {
	user = JsonValue.field(json, "user")?
	if JsonValue.is_null(user) {
		Ok(SignedOut(origin, JsonValue.as_str(JsonValue.field(json, "login_url")?)?))
	} else {
		pro = match JsonValue.field(user, "pro") {
			Ok(found) => JsonValue.as_bool(found) ?? Bool.False
			Err(_) => Bool.False
		}
		entitlements = match JsonValue.field(user, "entitlements") {
			Ok(found) => match JsonValue.items(found) {
				Ok(values) => values.map_try(JsonValue.as_str) ?? []
				Err(_) => []
			}
			Err(_) => []
		}
		Ok(
			SignedIn(
				origin,
				{
					id: whole_number(JsonValue.field(user, "id")?)?,
					handle: JsonValue.as_str(JsonValue.field(user, "handle")?)?,
					pro,
					entitlements,
				},
			),
		)
	}
}

drop_trailing_slash : Str -> Str
drop_trailing_slash = |value| if value.ends_with("/") value.drop_suffix("/") else value

## Elm's `Url.percentEncode` (JavaScript's `encodeURIComponent`): every UTF-8
## byte except the unreserved ASCII characters as `%XX`.
percent_encode : Str -> Str
percent_encode = |text| {
	var $out = []
	for byte in text.to_utf8() {
		$out = if is_unreserved(byte) $out.append(byte) else $out.concat(['%', hex_digit(byte // 16), hex_digit(byte % 16)])
	}
	Str.from_utf8($out) ?? ""
}

is_unreserved : U8 -> Bool
is_unreserved = |b|
	(b >= 'A' and b <= 'Z')
	or (b >= 'a' and b <= 'z')
	or (b >= '0' and b <= '9')
	or [
		'-',
		'_',
		'.',
		'!',
		'~',
		'*',
		'\'',
		'(',
		')',
	].contains(b)

hex_digit : U8 -> U8
hex_digit = |n| if n < 10 '0' + n else 'A' + n - 10

## Elm's `Json.Decode.int`: any JSON number that is a whole number, so `5.0`
## and `1e3` decode as they do in the Elm app.
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
