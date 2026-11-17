app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout

# Raised from 4096 when the bridge gained the roc-signals storage element (<lyceum-store>).
max_bridge_bytes = 4608

# The roc-signals runtime files (runtime.mjs and the environment.mjs and worker.mjs it loads beside it) are the only
# other JavaScript the page loads. They are never kept in the repository: the build-signals task downloads the files
# signals/runtime.lock.json pins to the repository root and checks their SHA-256, and built copies must still match
# those pins.

main! = |_args| {
	bridge = Path.read_utf8!("browser-bridge.js")?
	index = Path.read_utf8!("index.html")?
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
	} else if List.any(forbidden_bridge_terms, |term| Str.contains(bridge, term)) {
		fail!("browser-bridge.js contains an operation reserved for Roc")
	} else if Str.contains(index, "<script>") or Str.contains(index, "<script\n") {
		fail!("index.html contains inline JavaScript")
	} else if List.len(Str.split_on(index, "<script")) != 2 or !Str.contains(index, "<script src=\"/browser-bridge.js\"></script>") or !Str.contains(index, "data-runtime=\"/runtime.mjs\"") {
		fail!("index.html must load only the browser bridge, which mounts the pinned roc-signals runtime")
	} else if !runtime_pinned {
		fail!("the roc-signals runtime files are not the ones signals/runtime.lock.json pins; run the Kai build-signals task")
	} else {
		Stdout.line!("browser boundary OK: one ${List.len(Str.to_utf8(bridge)).to_str()}-byte bridge")
	}
}

runtime_matches_pin! = |{}| {
	lock : { release : Str, files : List({ name : Str, url : Str, sha256 : Str }) }
	lock = Json.parse(Path.read_utf8!("signals/runtime.lock.json")?)?
	files_match!(lock.files)
}

# Each pinned file present at the repository root matches its pin (absent ones are fetched by build-signals).
files_match! = |files|
	match files {
		[] => Ok(Bool.True)
		[file, .. as rest] =>
			if Path.exists!(Path.utf8(file.name))? {
				sum = Cmd.new("sha256sum").args(["--", OsStr.from_str(file.name)]).exec_output!()?
				if List.first(Str.split_on(sum.stdout_utf8, " ")) == Ok(file.sha256) files_match!(rest) else Ok(Bool.False)
			} else {
				files_match!(rest)
			}
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
