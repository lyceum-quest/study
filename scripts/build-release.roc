app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stdout
import AristosSite

# build-release production|staging|local
# Writes a self-contained static site to dist/aristos/<target>/<version>/ and its name to
# dist/aristos/<target>/latest. The app module (built by the build-signals task), bridge, and stylesheet get
# content-hashed names under assets/, and the roc-signals runtime files (fetched by build-signals) go together into
# assets/roc-signals.<hash>/, as runtime.mjs loads environment.mjs and worker.mjs beside it by name
# (served with a long immutable cache); index.html, config.json, preload/, and fonts/ keep fixed names (served no-cache,
# revalidated by ETag). config.json names the target's Lyceum account API.
main! = |args| {
	target = match args.map(OsStr.display) {
		[_, name] => Ok(name)
		_ => Err(Release("Usage: build-release production|staging|local"))
	}?
	api = AristosSite.account_api(target)?
	_ = require(Path.exists!(Path.utf8("preload/corpora.json"))?, "preload/corpora.json is missing; run the Kai preload task first")?
	_ = require(Path.exists!(Path.utf8("app.wasm"))? and Path.exists!(Path.utf8("runtime.mjs"))? and Path.exists!(Path.utf8("environment.mjs"))? and Path.exists!(Path.utf8("worker.mjs"))?, "app.wasm or a roc-signals runtime file is missing; run the Kai build-signals task first")?
	version = version!({})?
	_ = require(AristosSite.valid_version(version), "Unexpected release name ${version}")?
	root = AristosSite.dist(target)
	partial = "${root}/.${version}.partial"
	release = "${root}/${version}"
	_ = require(!Path.exists!(Path.utf8(release))?, "${release} already exists")?
	_ = if Path.exists!(Path.utf8(partial))? Path.delete_all!(Path.utf8(partial))? else {}
	Path.create_all!(Path.utf8("${partial}/assets"))?

	_ = copy!("app.wasm", "${partial}/assets/app.wasm")?
	_ = copy!("browser-bridge.js", "${partial}/assets/browser-bridge.js")?
	_ = copy!("styles.css", "${partial}/assets/styles.css")?
	app_module = hashed!(partial, "app", "wasm")?
	runtime = runtime!(partial)?
	bridge = hashed!(partial, "browser-bridge", "js")?
	styles = hashed!(partial, "styles", "css")?

	index = Path.read_utf8!(Path.utf8("index.html"))?
	_ = require(Str.contains(index, "\"/app.wasm\"") and Str.contains(index, "\"/runtime.mjs\"") and Str.contains(index, "\"/browser-bridge.js\"") and Str.contains(index, "\"/styles.css\""), "index.html no longer references /app.wasm, /runtime.mjs, /browser-bridge.js, and /styles.css")?
	rewritten = index
		.replace_each("\"/app.wasm\"", "\"/${app_module}\"")
		.replace_each("\"/runtime.mjs\"", "\"/${runtime}\"")
		.replace_each("\"/browser-bridge.js\"", "\"/${bridge}\"")
		.replace_each("\"/styles.css\"", "\"/${styles}\"")
	Path.write_utf8!(Path.utf8("${partial}/index.html"), rewritten)?
	Path.write_utf8!(Path.utf8("${partial}/config.json"), AristosSite.config_json(api))?
	_ = run!("cp", ["-R", "preload", "${partial}/preload"])?
	_ = run!("cp", ["-R", "fonts", "${partial}/fonts"])?
	# The What's new page fetches it; the published copy leaves out what the page hides.
	Path.write_utf8!(Path.utf8("${partial}/CHANGELOG.md"), public_changelog(Path.read_utf8!(Path.utf8("CHANGELOG.md"))?))?

	Path.rename!(Path.utf8(partial), Path.utf8(release))?
	Path.write_utf8!(Path.utf8("${root}/latest"), "${version}\n")?
	Stdout.line!("built ${release} (account API: ${if api == "" "none" else api})")
}

require = |condition, message| if condition Ok({}) else Err(Release(message))

run! = |program, args| {
	output = Cmd.new_str(program).args_str(args).exec_output!() ? |err| Release(Str.inspect(err))
	Ok(Str.trim(output.stdout_utf8))
}

# CHANGELOG.md without its HTML comments (release drafts) and ### Internal sections, as the What's new page shows
# it (packages/study/Changelog.roc), so the file the site serves holds nothing more.
public_changelog = |text| "${Str.join_with(keep_public(Str.split_on(text, "\n"), Bool.False, Bool.False, []), "\n")}\n"

keep_public = |lines, in_comment, internal, kept|
	match lines {
		[] => kept
		[line, .. as rest] => {
			trimmed = Str.trim(line)
			if in_comment or Str.starts_with(trimmed, "<!--") {
				keep_public(rest, !Str.contains(line, "-->"), internal, kept)
			} else if Str.starts_with(trimmed, "## ") or Str.starts_with(trimmed, "### ") {
				hidden = trimmed == "### Internal"
				keep_public(rest, Bool.False, hidden, if hidden kept else List.append(kept, line))
			} else if internal or (trimmed == "" and (List.last(kept) ?? "-") == "") {
				keep_public(rest, Bool.False, internal, kept)
			} else {
				keep_public(rest, Bool.False, Bool.False, List.append(kept, line))
			}
		}
	}

copy! = |source, destination| Path.write_bytes!(Path.utf8(destination), Path.read_bytes!(Path.utf8(source))?)

# Renames <dir>/assets/<name>.<ext> to assets/<name>.<first 16 hex digits of its SHA-256>.<ext>, the path
# index.html references.
hashed! = |dir, name, ext| {
	plain = "assets/${name}.${ext}"
	sum = run!("sha256sum", ["${dir}/${plain}"])?
	digest = Str.from_utf8(List.take_first(Str.to_utf8(sum), 16)) ?? ""
	_ = require(List.len(Str.to_utf8(digest)) == 16, "sha256sum gave no digest for ${plain}")?
	named = "assets/${name}.${digest}.${ext}"
	Path.rename!(Path.utf8("${dir}/${plain}"), Path.utf8("${dir}/${named}"))?
	Ok(named)
}

# UTC time and commit, marked -dirty when the working tree has changes: 20261012T153000Z-9971549-dirty.
version! = |{}| {
	time = run!("date", ["-u", "+%Y%m%dT%H%M%SZ"])?
	commit = run!("git", ["rev-parse", "--short=7", "HEAD"])?
	changes = run!("git", ["status", "--porcelain"])?
	Ok("${time}-${commit}${if changes == "" "" else "-dirty"}")
}

# Copies the runtime files into <dir>/assets/roc-signals.<first 16 hex digits of runtime.mjs's SHA-256>/ and returns
# the path of runtime.mjs there, which index.html references. runtime.mjs differs between roc-signals releases, so the
# directory's name changes whenever any of the files does.
runtime! = |dir| {
	sum = run!("sha256sum", ["runtime.mjs"])?
	digest = Str.from_utf8(List.take_first(Str.to_utf8(sum), 16)) ?? ""
	_ = require(List.len(Str.to_utf8(digest)) == 16, "sha256sum gave no digest for runtime.mjs")?
	folder = "assets/roc-signals.${digest}"
	Path.create_all!(Path.utf8("${dir}/${folder}"))?
	_ = copy!("runtime.mjs", "${dir}/${folder}/runtime.mjs")?
	_ = copy!("environment.mjs", "${dir}/${folder}/environment.mjs")?
	_ = copy!("worker.mjs", "${dir}/${folder}/worker.mjs")?
	Ok("${folder}/runtime.mjs")
}
