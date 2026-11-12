app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst",
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
# build: the review screen on roc-signals (signals/) as a static page in dist/signals/: its wasm32 module
# (review.wasm), the roc-signals runtime pinned by URL and SHA-256 in signals/runtime.lock.json (downloaded once,
# checked every build, never edited), signals/index.html, browser-bridge.js, and styles.css. The page shares the Elm
# app's IndexedDB database only from the same origin, so serve it beside the Elm app, as the repository root does
# (/dist/signals/), with preload/ and fonts/ at the root.
#
# specs: builds the review screen's native spec runner (dist/signals-specs/review-specs) and runs
# signals/specs/*.scm with it.
site = "dist/signals"

runner = "dist/signals-specs/review-specs"

main! = |args| {
	match args.map(OsStr.display) {
		["build"] => build!({})
		["specs"] => specs!({})
		_ => Err(Usage("Usage: signals.roc build|specs"))
	}
}

build! = |{}| {
	Path.create_all!(Path.unix(site))?
	roc!(["build", "--target=wasm32", "signals/main.roc", "--output=${site}/review.wasm"])?
	runtime!({})?
	for file in [("signals/index.html", "index.html"), ("browser-bridge.js", "browser-bridge.js"), ("styles.css", "styles.css")] {
		(source, name) = file
		Path.write_bytes!(Path.unix("${site}/${name}"), Path.read_bytes!(Path.unix(source))?)?
	}
	Stdout.line!("built ${site}/")
}

## The pinned runtime.mjs in dist/signals/, downloaded unless the copy there already matches the pin.
runtime! = |{}| {
	{ url, pinned } = pin(Path.read_utf8!(Path.unix("signals/runtime.lock.json"))?) ? |message| Lock("signals/runtime.lock.json: ${message}")
	target = Path.unix("${site}/runtime.mjs")
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
	roc!(["build", "--target=x64musl", "signals/main.roc", "--output=${runner}"])?
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
