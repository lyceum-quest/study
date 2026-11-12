app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.Cmd
import pf.Path
import pf.Stderr
import pf.Stdout

# Raised from 4096 when the bridge gained the roc-signals storage element (<lyceum-store>) beside the Elm ports.
max_bridge_bytes = 4608

# The roc-signals runtime is the only other JavaScript a page loads. It is never kept in the repository: the
# build-signals task downloads the release signals/runtime.lock.json pins into dist/signals/ and checks its SHA-256,
# and a built copy must still match that pin.
runtime_path = "dist/signals/runtime.mjs"

main! = |_args| {
	bridge = Path.read_utf8!("browser-bridge.js")?
	index = Path.read_utf8!("index.html")?
	signals_page = Path.read_utf8!("signals/index.html")?
	runtime_pinned = runtime_matches_pin!({})?
	listed = Cmd.new("git")
		.args(["ls-files", "--cached", "--others", "--exclude-standard", "--", "*.js", "*.mjs", "*.cjs"])
		.exec_output!()?
	candidates = listed.stdout_utf8
		.split_on("\n")
		.keep_if(|path| path != "")
	existing = existing_files!(candidates)?
	forbidden_listed = Cmd.new("git")
		.args(["ls-files", "--cached", "--others", "--exclude-standard", "--", "*.py", "*.sh"])
		.exec_output!()?
	forbidden_candidates = forbidden_listed.stdout_utf8
		.split_on("\n")
		.keep_if(|path| path != "")
	forbidden_existing = existing_files!(forbidden_candidates)?

	if !List.is_empty(forbidden_existing) {
		fail!("maintained Python or shell source is forbidden; found ${Str.inspect(forbidden_existing)}")
	} else if existing != ["browser-bridge.js"] {
		fail!("maintained JavaScript must be exactly browser-bridge.js; found ${Str.inspect(existing)}")
	} else if List.len(Str.to_utf8(bridge)) > max_bridge_bytes {
		fail!("browser-bridge.js exceeds the explicit ${max_bridge_bytes.to_str()}-byte architecture limit")
	} else if List.any(forbidden_bridge_terms, |term| Str.contains(Str.replace_each(bridge, credentials_fetch, ""), term)) {
		fail!("browser-bridge.js contains an operation reserved for Elm or Roc")
	} else if Str.contains(index, "<script>") or Str.contains(index, "<script\n") {
		fail!("index.html contains inline JavaScript")
	} else if List.len(Str.split_on(index, "<script")) != 3 {
		fail!("index.html must contain exactly two external script elements")
	} else if !Str.contains(index, "<script src=\"/elm.js\"></script>") or !Str.contains(index, "<script src=\"/browser-bridge.js\"></script>") {
		fail!("index.html must load only the generated Elm bundle and browser bridge")
	} else if Str.contains(signals_page, "<script>") or Str.contains(signals_page, "<script\n") {
		fail!("signals/index.html contains inline JavaScript")
	} else if List.len(Str.split_on(signals_page, "<script")) != 2 or !Str.contains(signals_page, "<script src=\"browser-bridge.js\"></script>") or !Str.contains(signals_page, "data-runtime=\"./runtime.mjs\"") {
		fail!("signals/index.html must load only the browser bridge, which mounts the pinned roc-signals runtime")
	} else if !runtime_pinned {
		fail!("${runtime_path} is not the roc-signals runtime signals/runtime.lock.json pins; run the Kai build-signals task")
	} else {
		Stdout.line!("browser boundary OK: one ${List.len(Str.to_utf8(bridge)).to_str()}-byte bridge")
	}
}

runtime_matches_pin! = |{}|
	if Path.exists!(Path.utf8(runtime_path))? {
		lock : { release : Str, url : Str, sha256 : Str }
		lock = Json.parse(Path.read_utf8!("signals/runtime.lock.json")?)?
		sum = Cmd.new("sha256sum").args(["--", "dist/signals/runtime.mjs"]).exec_output!()?
		Ok(List.first(Str.split_on(sum.stdout_utf8, " ")) == Ok(lock.sha256))
	} else {
		Ok(Bool.True)
	}

existing_files! = |paths|
	match paths {
		[] => Ok([])
		[path, .. as rest] => {
			remaining = existing_files!(rest)?
			if Path.exists!(Path.utf8(path))? {
				Ok(List.prepend(remaining, path))
			} else {
				Ok(remaining)
			}
		}
	}

## The one fetch the bridge may contain: the fetch it gives the roc-signals
## runtime, which only adds credentials for the account API (the runtime cannot
## ask for them; roc-issues RS-008). It makes no request of its own.
credentials_fetch = "const withCredentials = (url, init) => fetch(url, Object.assign({}, init, { credentials: \"include\" }));"

forbidden_bridge_terms = [
	"fetch(",
	"XMLHttpRequest",
	"localStorage",
	"corpora.json",
	"parseConllu",
	"sentenceIndex",
	"attemptCount",
]

fail! = |message| {
	Stderr.line!(message)?
	Err(Exit(1))
}
