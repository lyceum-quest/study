## A JSON value, for the FSRS fixtures in tests/fixtures/fsrs/ and the records
## the roc-signals app stores. Adapted from apo's package/JsonValue.roc
## (https://github.com/lyceum-quest/apo, MIT, Copyright (c) 2026 Lyceum): the
## same bounded decoder (size and depth; duplicate keys and trailing input are
## rejected), with accessors for numbers and a compact encoder.
JsonValue := [
	Object(List((Str, JsonValue))),
	Array(List(JsonValue)),
	String(Str),
	Number(Str),
	Boolean(Bool),
	Null,
].{
	max_bytes : U64
	max_bytes = 67108864

	max_depth : U64
	max_depth = 64

	decode : Str -> Try(JsonValue, Str)
	decode = |text| {
		bytes = text.to_utf8()
		if bytes.len() > max_bytes {
			return Err("JSON exceeds 64 MiB")
		}
		parsed = value(bytes, skip(bytes, 0), 0)?
		end = skip(bytes, parsed.next)
		if end != bytes.len() {
			return Err("trailing data at byte ${end.to_str()}")
		}
		Ok(parsed.json)
	}

	# Accessors. Errors name what was expected, for the fixture reader's messages.

	field : JsonValue, Str -> Try(JsonValue, Str)
	field = |json, name| match json {
		Object(pairs) => match pairs.keep_if(|(k, _)| k == name) {
			[(_, v), ..] => Ok(v)
			[] => Err("missing field \"${name}\"")
		}
		_ => Err("expected an object with field \"${name}\"")
	}

	fields : JsonValue -> List((Str, JsonValue))
	fields = |json| match json {
		Object(pairs) => pairs
		_ => []
	}

	items : JsonValue -> Try(List(JsonValue), Str)
	items = |json| match json {
		Array(values) => Ok(values)
		_ => Err("expected an array")
	}

	as_str : JsonValue -> Try(Str, Str)
	as_str = |json| match json {
		String(text) => Ok(text)
		_ => Err("expected a string")
	}

	## A number as JavaScript reads it: the nearest double.
	as_f64 : JsonValue -> Try(F64, Str)
	as_f64 = |json| match json {
		Number(text) => F64.from_str(text).map_err(|_| "expected a number, found ${text}")
		_ => Err("expected a number")
	}

	as_i64 : JsonValue -> Try(I64, Str)
	as_i64 = |json| match json {
		Number(text) => I64.from_str(text).map_err(|_| "expected an integer, found ${text}")
		_ => Err("expected an integer")
	}

	as_bool : JsonValue -> Try(Bool, Str)
	as_bool = |json| match json {
		Boolean(b) => Ok(b)
		_ => Err("expected a boolean")
	}

	is_null : JsonValue -> Bool
	is_null = |json| match json {
		Null => Bool.True
		_ => Bool.False
	}

	# Building and encoding: compact text, as JSON.stringify writes it. Numbers
	# are written as stored, so a float must arrive in JavaScript's notation
	# (FsrsMath.to_js_str) for the text to equal what JavaScript would write.

	object : List((Str, JsonValue)) -> JsonValue
	object = |entries| Object(entries)

	array : List(JsonValue) -> JsonValue
	array = |values| Array(values)

	str : Str -> JsonValue
	str = |text| String(text)

	int : I64 -> JsonValue
	int = |n| Number(n.to_str())

	numeral : Str -> JsonValue
	numeral = |text| Number(text)

	boolean : Bool -> JsonValue
	boolean = |b| Boolean(b)

	null : JsonValue
	null = Null

	encode : JsonValue -> Str
	encode = |json| match json {
		Object(entries) => {
			members = entries.map(|(name, member)| "${quote(name)}:${encode(member)}")
			"{${Str.join_with(members, ",")}}"
		}
		Array(values) => "[${Str.join_with(values.map(encode), ",")}]"
		String(text) => quote(text)
		Number(text) => text
		Boolean(b) => if (b) "true" else "false"
		Null => "null"
	}

	quote : Str -> Str
	quote = |text| {
		var $out = ['"']
		for byte in text.to_utf8() {
			$out = match byte {
				'"' => $out.concat(['\\', '"'])
				'\\' => $out.concat(['\\', '\\'])
				'\n' => $out.concat(['\\', 'n'])
				'\r' => $out.concat(['\\', 'r'])
				'\t' => $out.concat(['\\', 't'])
				_ => if byte < ' ' $out.concat(['\\', 'u', '0', '0', hex_digit(byte // 16), hex_digit(byte % 16)]) else $out.append(byte)
			}
		}
		Str.from_utf8($out.append('"')) ?? "\"\""
	}

	hex_digit : U8 -> U8
	hex_digit = |n| if n < 10 '0' + n else 'a' + n - 10

	# Decoding.

	skip : List(U8), U64 -> U64
	skip = |bytes, at| match bytes.get(at) {
		Ok(' ') | Ok('\n') | Ok('\r') | Ok('\t') => skip(bytes, at + 1)
		_ => at
	}

	value : List(U8), U64, U64 -> Try({ json : JsonValue, next : U64 }, Str)
	value = |bytes, at, depth| {
		if depth > max_depth {
			return Err("JSON nested deeper than ${max_depth.to_str()}")
		}
		match bytes.get(at) {
			Ok('{') => object_body(bytes, skip(bytes, at + 1), depth + 1, [])
			Ok('[') => array_body(bytes, skip(bytes, at + 1), depth + 1, [])
			Ok('"') => {
				s = string(bytes, at + 1)?
				Ok({ json: String(s.text), next: s.next })
			}
			Ok('t') => literal(bytes, at, "true", Boolean(Bool.True))
			Ok('f') => literal(bytes, at, "false", Boolean(Bool.False))
			Ok('n') => literal(bytes, at, "null", Null)
			Ok(_) => number(bytes, at)
			Err(_) => Err("unexpected end of JSON")
		}
	}

	literal : List(U8), U64, Str, JsonValue -> Try({ json : JsonValue, next : U64 }, Str)
	literal = |bytes, at, word, json| {
		want = word.to_utf8()
		if bytes.sublist({ start: at, len: want.len() }) == want {
			Ok({ json, next: at + want.len() })
		} else {
			Err("invalid literal at byte ${at.to_str()}")
		}
	}

	number : List(U8), U64 -> Try({ json : JsonValue, next : U64 }, Str)
	number = |bytes, at| {
		var $end = at
		while bytes.get($end).map_ok(is_number_byte) == Ok(Bool.True) {
			$end = $end + 1
		}
		text = Str.from_utf8(bytes.sublist({ start: at, len: $end - at })) ?? ""
		if text == "" or Dec.from_str(text).is_err() and F64.from_str(text).is_err() {
			Err("invalid number at byte ${at.to_str()}")
		} else {
			Ok({ json: Number(text), next: $end })
		}
	}

	is_number_byte : U8 -> Bool
	is_number_byte = |b| (b >= '0' and b <= '9') or b == '-' or b == '+' or b == '.' or b == 'e' or b == 'E'

	object_body : List(U8), U64, U64, List((Str, JsonValue)) -> Try({ json : JsonValue, next : U64 }, Str)
	object_body = |bytes, at, depth, found| {
		if bytes.get(at) == Ok('}') and found.is_empty() {
			return Ok({ json: Object(found), next: at + 1 })
		}
		if bytes.get(at) != Ok('"') {
			return Err("expected a key at byte ${at.to_str()}")
		}
		key = string(bytes, at + 1)?
		if found.any(|(k, _)| k == key.text) {
			return Err("duplicate key \"${key.text}\"")
		}
		colon = skip(bytes, key.next)
		if bytes.get(colon) != Ok(':') {
			return Err("expected ':' at byte ${colon.to_str()}")
		}
		v = value(bytes, skip(bytes, colon + 1), depth)?
		next = skip(bytes, v.next)
		collected = found.append((key.text, v.json))
		match bytes.get(next) {
			Ok(',') => object_body(bytes, skip(bytes, next + 1), depth, collected)
			Ok('}') => Ok({ json: Object(collected), next: next + 1 })
			_ => Err("expected ',' or '}' at byte ${next.to_str()}")
		}
	}

	array_body : List(U8), U64, U64, List(JsonValue) -> Try({ json : JsonValue, next : U64 }, Str)
	array_body = |bytes, at, depth, found| {
		if bytes.get(at) == Ok(']') and found.is_empty() {
			return Ok({ json: Array(found), next: at + 1 })
		}
		v = value(bytes, at, depth)?
		next = skip(bytes, v.next)
		collected = found.append(v.json)
		match bytes.get(next) {
			Ok(',') => array_body(bytes, skip(bytes, next + 1), depth, collected)
			Ok(']') => Ok({ json: Array(collected), next: next + 1 })
			_ => Err("expected ',' or ']' at byte ${next.to_str()}")
		}
	}

	string : List(U8), U64 -> Try({ text : Str, next : U64 }, Str)
	string = |bytes, start| {
		var $out = []
		var $at = start
		while Bool.True {
			match bytes.get($at) {
				Err(_) => return Err("unterminated string")
				Ok('"') => {
					text = Str.from_utf8($out) ?? return Err("invalid UTF-8 in string")
					return Ok({ text, next: $at + 1 })
				}
				Ok('\\') => {
					match bytes.get($at + 1) {
						Ok('"') => {
							$out = $out.append('"')
						}
						Ok('\\') => {
							$out = $out.append('\\')
						}
						Ok('/') => {
							$out = $out.append('/')
						}
						Ok('b') => {
							$out = $out.append(8)
						}
						Ok('f') => {
							$out = $out.append(12)
						}
						Ok('n') => {
							$out = $out.append('\n')
						}
						Ok('r') => {
							$out = $out.append('\r')
						}
						Ok('t') => {
							$out = $out.append('\t')
						}
						Ok('u') => {
							first = hex4(bytes, $at + 2)?
							if first >= 0xD800 and first <= 0xDBFF {
								if bytes.get($at + 6) != Ok('\\') or bytes.get($at + 7) != Ok('u') {
									return Err("unpaired surrogate")
								}
								second = hex4(bytes, $at + 8)?
								point = 0x10000 + (first - 0xD800) * 0x400 + (second - 0xDC00)
								$out = $out.concat(utf8(point))
								$at = $at + 6
							} else {
								$out = $out.concat(utf8(first))
							}
							$at = $at + 4
						}
						_ => return Err("invalid escape at byte ${$at.to_str()}")
					}
					$at = $at + 2
				}
				Ok(byte) => {
					if byte < ' ' {
						return Err("control character in string at byte ${$at.to_str()}")
					}
					$out = $out.append(byte)
					$at = $at + 1
				}
			}
		}
	}

	hex4 : List(U8), U64 -> Try(U32, Str)
	hex4 = |bytes, at| {
		var $n = 0
		for byte in bytes.sublist({ start: at, len: 4 }) {
			d = if byte >= '0' and byte <= '9' {
				byte - '0'
			} else if byte >= 'a' and byte <= 'f' {
				byte - 'a' + 10
			} else if byte >= 'A' and byte <= 'F' {
				byte - 'A' + 10
			} else {
				return Err("invalid \\u escape")
			}
			$n = $n * 16 + d.to_u32()
		}
		if bytes.sublist({ start: at, len: 4 }).len() != 4 {
			return Err("short \\u escape")
		}
		Ok($n)
	}

	utf8 : U32 -> List(U8)
	utf8 = |cp| {
		if cp < 0x80 {
			[cp.to_u8_wrap()]
		} else if cp < 0x800 {
			[(0xC0 + cp // 64).to_u8_wrap(), (0x80 + cp % 64).to_u8_wrap()]
		} else if cp < 0x10000 {
			[(0xE0 + cp // 4096).to_u8_wrap(), (0x80 + (cp // 64) % 64).to_u8_wrap(), (0x80 + cp % 64).to_u8_wrap()]
		} else {
			[(0xF0 + cp // 262144).to_u8_wrap(), (0x80 + (cp // 4096) % 64).to_u8_wrap(), (0x80 + (cp // 64) % 64).to_u8_wrap(), (0x80 + cp % 64).to_u8_wrap()]
		}
	}
}
