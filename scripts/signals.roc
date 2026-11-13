app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.0/2yhxoR7cZPSYbyUzPWULFw8AA6QEcdsgFNRmzu7pZbst.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	json: "../packages/json/main.roc",
}

import pf.Cmd
import pf.Http
import pf.OsStr
import pf.Path
import pf.Stdout
import http.Request
import json.JsonValue

# signals.roc build|specs
#
# build: the app (signals/) as the files index.html loads beside browser-bridge.js and styles.css: its wasm32 module
# (app.wasm) and the roc-signals runtime pinned by URL and SHA-256 in signals/runtime.lock.json (runtime.mjs,
# downloaded once, checked every build, never edited), both generated at the repository root, which serves the app
# with preload/ and fonts/. The release build bundles the same two files.
#
# specs: builds the app's native spec runner (dist/signals-specs/review-specs) and runs signals/specs/*.scm with it.

runner = "dist/signals-specs/review-specs"

main! = |args| {
	match args.map(OsStr.display) {
		["build"] => build!({})
		["specs"] => specs!({})
		_ => Err(Usage("Usage: signals.roc build|specs"))
	}
}

build! = |{}| {
	roc!(["build", "--target=wasm32", "--opt=size", "signals/main.roc", "--output=app.wasm"])?
	runtime!({})?
	Stdout.line!("built app.wasm and runtime.mjs")
}

## The pinned runtime.mjs, downloaded unless the copy there already matches the pin.
runtime! = |{}| {
	{ url, pinned } = pin(Path.read_utf8!(Path.unix("signals/runtime.lock.json"))?) ? |message| Lock("signals/runtime.lock.json: ${message}")
	target = Path.unix("runtime.mjs")
	present = if Path.exists!(target)? sha256(Path.read_bytes!(target)?) == pinned else Bool.False
	if present {
		Ok({})
	} else {
		response = Http.send!(Request.from_method(GET).with_uri(url), { max_redirects: 5 })?
		body = response.body()
		digest = sha256(body)
		if response.status() != 200 {
			Err(Fetch("${url} answered ${response.status().to_str()}"))
		} else if digest != pinned {
			Err(Fetch("${url} has SHA-256 ${digest}, but signals/runtime.lock.json pins ${pinned}"))
		} else {
			Path.write_bytes!(target, body)
		}
	}
}

pin : Str -> Try({ url : Str, pinned : Str }, Str)
pin = |text| {
	lock = JsonValue.decode(text)?
	Ok({ url: JsonValue.as_str(JsonValue.field(lock, "url")?)?, pinned: JsonValue.as_str(JsonValue.field(lock, "sha256")?)? })
}

specs! = |{}| {
	Path.create_all!(Path.unix("dist/signals-specs"))?
	# With the dev backend, as roc-signals 0.5.0's own `signals.roc test` builds it: seconds rather than minutes.
	roc!(["build", "--target=x64musl", "--opt=dev", "signals/main.roc", "--output=${runner}"])?
	found = Path.list!(Path.unix("signals/specs"))?
		.map(|path| path.display())
		.keep_if(|path| path.ends_with(".scm"))
	call!(runner, found.sort_with(compare))
}

roc! = |args| call!("roc", args)

# Runs a program with the terminal inherited; a non-zero exit is an error.
call! = |program, args| {
	output = Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).inherit_stdio().run!()?
	match output.status {
		Exited(0) => Ok({})
		_ => Err(Failed("${program} ${Str.join_with(args, " ")}: ${Str.inspect(output.status)}"))
	}
}

sha256 = |bytes| Crypto.SHA256.hash(bytes).to_hex()

# Byte order, so the specs run in the same order everywhere.
compare = |a, b| compare_bytes(a.to_utf8(), b.to_utf8(), 0)

compare_bytes = |a, b, at|
	match (a.get(at), b.get(at)) {
		(Err(_), Err(_)) => Same
		(Err(_), Ok(_)) => Before
		(Ok(_), Err(_)) => After
		(Ok(x), Ok(y)) => if x < y Before else if x > y After else compare_bytes(a, b, at + 1)
	}
