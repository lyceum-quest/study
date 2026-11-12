## The app's routes, ported from `src/Route.elm`. Routes live in the URL
## fragment (`/#/luke/5?word=7`), so the static server only ever serves `/` and
## every link or reload works without a server-side fallback. Passages are
## addressed by their canonical citation, dotted (`1.2` for 1:2, `1.1.1` for a
## section).
Route := [].{

	Route : [
		Library,
		Settings,
		WorkLanding(Str),
		Study(Str, Str),
		Reader(Str, [Some(Str), None]),
		Word(Str),
		WordReview(Str),
		Stats,
		Today,
		WhatsNew,
	]

	## The route of a URL (or just its fragment), as elm/url parses the
	## fragment's path: empty segments are dropped, and a path that matches no
	## route is `Err`.
	from_url : Str -> Try(Route.Route, [NoRoute])
	from_url = |url| {
		segments = path_of(url).split_on("/").drop_if(|segment| segment == "")
		match segments {
			[] => Ok(Library)
			["settings"] => Ok(Settings)
			["stats"] => Ok(Stats)
			["today"] => Ok(Today)
			["whats-new"] => Ok(WhatsNew)
			["word", name] => Ok(Word(lemma(name)))
			["review", "word", name] => Ok(WordReview(lemma(name)))
			[work, "read", passage] => Ok(Reader(work, Some(passage)))
			[work, "read"] => Ok(Reader(work, None))
			[work, passage] => Ok(Study(work, passage))
			[work] => Ok(WorkLanding(work))
			_ => Err(NoRoute)
		}
	}

	## Page state (open popup, tab, tool) carried in the fragment's query
	## string. A pair that is not `key=value` or does not percent-decode is
	## skipped; a later key wins.
	query : Str -> Dict(Str, Str)
	query = |url|
		query_of(url).split_on("&").fold(
			Dict.empty(),
			|found, pair| match pair.split_on("=") {
				[key, value] => match (percent_decode(key), percent_decode(value)) {
					(Ok(k), Ok(v)) => found.insert(k, v)
					_ => found
				}
				_ => found
			},
		)

	to_path : Route.Route -> Str
	to_path = |route| {
		path = match route {
			Library => "/"
			Settings => "/settings"
			WorkLanding(work) => "/${work}"
			Study(work, passage) => "/${work}/${passage}"
			Word(name) => "/word/${percent_encode(name)}"
			WordReview(name) => "/review/word/${percent_encode(name)}"
			Stats => "/stats"
			WhatsNew => "/whats-new"
			Today => "/today"
			Reader(work, Some(passage)) => "/${work}/read/${passage}"
			Reader(work, None) => "/${work}/read"
		}
		"#${path}"
	}

	## `encodeURIComponent`, as Elm's `Url.percentEncode`.
	percent_encode : Str -> Str
	percent_encode = |text|
		Str.from_utf8_lossy(
			text.to_utf8().fold(
				[],
				|out, byte|
					if is_unreserved(byte) {
						out.append(byte)
					} else {
						out.concat(['%', hex_digit(byte // 16), hex_digit(byte % 16)])
					},
			),
		)

	## `decodeURIComponent`, as Elm's `Url.percentDecode`: `Err` for a malformed
	## escape or bytes that are not UTF-8.
	percent_decode : Str -> Try(Str, [BadEscape])
	percent_decode = |text| {
		bytes = text.to_utf8()
		decoded = decode_bytes(bytes, 0, [])?
		Str.from_utf8(decoded).map_err(|_| BadEscape)
	}
}

## The fragment of a URL without its query; "/" when there is no fragment.
path_of : Str -> Str
path_of = |url|
	match fragment_of(url).split_first("?") {
		Ok({ before, .. }) => before
		Err(_) => fragment_of(url)
	}

query_of : Str -> Str
query_of = |url|
	match fragment_of(url).split_first("?") {
		Ok({ after, .. }) => after
		Err(_) => ""
	}

fragment_of : Str -> Str
fragment_of = |url|
	match url.split_first("#") {
		Ok({ after, .. }) => after
		Err(_) => "/"
	}

## A lemma path segment, percent-decoded (lemmas are Greek).
lemma : Str -> Str
lemma = |raw| Route.percent_decode(raw) ?? raw

is_unreserved : U8 -> Bool
is_unreserved = |byte|
	(byte >= 'A' and byte <= 'Z')
	or (byte >= 'a' and byte <= 'z')
	or (byte >= '0' and byte <= '9')
	or [ '-', '_', '.', '!', '~', '*', '\'', '(', ')' ].contains(byte)

hex_digit : U8 -> U8
hex_digit = |n| if n < 10 '0' + n else 'A' + n - 10

decode_bytes : List(U8), U64, List(U8) -> Try(List(U8), [BadEscape])
decode_bytes = |bytes, at, out|
	match bytes.get(at) {
		Err(_) => Ok(out)
		Ok('%') => match (bytes.get(at + 1), bytes.get(at + 2)) {
			(Ok(high), Ok(low)) => match (hex_value(high), hex_value(low)) {
				(Ok(h), Ok(l)) => decode_bytes(bytes, at + 3, out.append(h * 16 + l))
				_ => Err(BadEscape)
			}
			_ => Err(BadEscape)
		}
		Ok(byte) => decode_bytes(bytes, at + 1, out.append(byte))
	}

hex_value : U8 -> Try(U8, [NotHex])
hex_value = |c|
	if c >= '0' and c <= '9' {
		Ok(c - '0')
	} else if c >= 'a' and c <= 'f' {
		Ok(c - 'a' + 10)
	} else if c >= 'A' and c <= 'F' {
		Ok(c - 'A' + 10)
	} else {
		Err(NotHex)
	}
