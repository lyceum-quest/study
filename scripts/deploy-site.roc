app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Sleep
import cli.Stderr
import cli.Stdout
import AristosSite

# deploy-site deploy production|staging [<version>]   (default: dist/aristos/<target>/latest)
# deploy-site rollback production|staging
#
# The host serves ARISTOS_DEPLOY_DIR/current, a symlink to releases/<version>. A deploy uploads the release to
# releases/.<version>.partial, checks it byte for byte, renames it into place, and swaps `current` to it with a
# rename, so visitors see either the old site or the new one. `previous` keeps the release it replaced, and
# every other release is removed. Rollback swaps `current` and `previous`. Both connect over SSH as a user who can
# write the directory (root, like deploy-lyceum-data) and then check the public site.
main! = |args| {
	(action, target, requested) = match args.map(OsStr.display) {
		[_, "deploy", t] => Ok((Deploy, t, ""))
		[_, "deploy", t, version] => Ok((Deploy, t, version))
		[_, "rollback", t] => Ok((Rollback, t, ""))
		_ => Err(Site("Usage: deploy-site deploy production|staging [<version>] | deploy-site rollback production|staging"))
	}?
	_ = require(target == "production" or target == "staging", "Deploy target must be production or staging")?
	_ = if target == "production" require((Env.var_str!("ARISTOS_DEPLOY_PRODUCTION") ?? "") == "1", "Production requires ARISTOS_DEPLOY_PRODUCTION=1")? else {}
	host_setting = setting!("ARISTOS_DEPLOY_HOST")
	_ = require(host_setting != "", "Set ARISTOS_DEPLOY_HOST (an SSH destination, e.g. root@lyceum-prod) in the environment or .env")?
	site_setting = setting!("ARISTOS_SITE_URL")
	checked = AristosSite.target(host_setting, if site_setting != "" site_setting else default_site_url(target)) ? |InvalidTarget(problem)| Site(problem)
	dir_setting = setting!("ARISTOS_DEPLOY_DIR")
	dir = if dir_setting == "" "/var/www/aristos" else Str.drop_suffix(dir_setting, "/")
	_ = require(Str.starts_with(dir, "/") and dir != "/" and AristosSite.valid_version(Str.replace_each(Str.drop_prefix(dir, "/"), "/", "_")), "ARISTOS_DEPLOY_DIR must be an absolute path of letters, digits, '.', '-', '_', and '/'")?
	match action {
		Deploy => deploy!(checked.host, dir, checked.url, target, requested)
		Rollback => rollback!(checked.host, dir, checked.url)
	}
}

default_site_url = |target| if target == "production" "https://study.lyceum.quest" else "https://study.internal.blu.cx"

deploy! = |host, dir, url, target, requested| {
	root = AristosSite.dist(target)
	version = if requested != "" requested else Str.trim(Path.read_utf8!(Path.utf8("${root}/latest")) ? |_| Site("No ${root}/latest; build a release with the Kai release workflow first"))
	_ = require(AristosSite.valid_version(version), "Invalid release name ${version}")?
	local = "${root}/${version}"
	config = Path.read_utf8!(Path.utf8("${local}/config.json")) ? |_| Site("${local} is not a complete release")
	index = Path.read_utf8!(Path.utf8("${local}/index.html"))?
	_ = require(Path.exists!(Path.utf8("${local}/preload/corpora.json"))?, "${local} has no preload/corpora.json")?
	_ = require(config == AristosSite.config_json(AristosSite.account_api(target)?), "${local}/config.json is not the ${target} configuration")?

	links = links!(host, dir)?
	_ = require(links.current != version, "${version} is already current on ${host}")?
	releases = "${dir}/releases"
	partial = "${releases}/.${version}.partial"
	_ = remote!(host, ["install", "-d", "-m", "0755", "--", dir, releases])?
	_ = remote!(host, ["test", "!", "-e", "${releases}/${version}"]) ? |_| Site("${releases}/${version} already exists on ${host}; releases are never overwritten (if it is the previous release, roll back to switch to it)")
	_ = remote!(host, ["rm", "-rf", "--", partial])?
	# Files are owned by the SSH user (root) and world-readable for the web server, whatever their local owner.
	_ = run!("rsync", ["-rlt", "--delete", "--no-owner", "--no-group", "--chmod=D0755,F0644", "${local}/", "${host}:${partial}/"])?
	differences = run!("rsync", ["-rlcn", "--delete", "--out-format=%n", "${local}/", "${host}:${partial}/"])?
	_ = require(differences == "", "Uploaded files differ from ${local}: ${differences}")?
	_ = remote!(host, ["mv", "-T", "--", partial, "${releases}/${version}"])?
	_ = point!(host, dir, "current", version)?
	_ = Stdout.line!("${host}:${dir}/current -> releases/${version}")?
	match verify!(url, config, index, 5) {
		Ok(_) => {
			_ = if links.current != "" point!(host, dir, "previous", links.current)? else {}
			_ = prune!(host, releases, [version, links.current])?
			Stdout.line!("Deployed Lyceum Study ${version} to ${url}/ (previous: ${if links.current == "" "none" else links.current})")
		}
		Err(problem) => {
			restored = if links.current != "" point!(host, dir, "current", links.current) else Ok({})
			Stderr.line!("Public check failed; restored current to ${if links.current == "" "nothing (first deploy)" else links.current}: ${Str.inspect(restored)}; kept ${releases}/${version}") ?? {}
			Err(problem)
		}
	}
}

rollback! = |host, dir, url| {
	links = links!(host, dir)?
	_ = require(links.previous != "", "No previous release on ${host}:${dir}")?
	config = remote_raw!(host, ["cat", "--", "${dir}/releases/${links.previous}/config.json"])?
	index = remote_raw!(host, ["cat", "--", "${dir}/releases/${links.previous}/index.html"])?
	_ = point!(host, dir, "current", links.previous)?
	_ = if links.current != "" point!(host, dir, "previous", links.current)? else {}
	_ = verify!(url, config, index, 5)?
	Stdout.line!("Rolled ${url}/ back to ${links.previous} (previous is now ${links.current})")
}

# The releases `current` and `previous` point at ("" when absent).
links! = |host, dir| {
	listed = remote!(host, ["find", dir, "-maxdepth", "1", "-type", "l", "(", "-name", "current", "-o", "-name", "previous", ")", "-printf", "%f %l\\n"]) ?? ""
	pairs = Str.split_on(listed, "\n").keep_oks(|line|
		match Str.split_on(Str.trim(line), " ") {
			[name, link] if Str.starts_with(link, "releases/") and AristosSite.valid_version(Str.drop_prefix(link, "releases/")) => Ok((name, Str.drop_prefix(link, "releases/")))
			_ => Err(NotALink)
		})
	find = |name| List.first(pairs.keep_if(|(found, _)| found == name)).map_ok(|(_, version)| version) ?? ""
	Ok({ current: find("current"), previous: find("previous") })
}

# Replaces the symlink <dir>/<name> by renaming a new one over it (atomic for readers).
point! = |host, dir, name, version| {
	_ = remote!(host, ["ln", "-sfn", "--", "releases/${version}", "${dir}/.${name}.new"])?
	_ = remote!(host, ["mv", "-T", "--", "${dir}/.${name}.new", "${dir}/${name}"])?
	Ok({})
}

prune! = |host, releases, keep| {
	listed = remote!(host, ["find", releases, "-mindepth", "1", "-maxdepth", "1", "-printf", "%f\\n"])?
	stale = Str.split_on(listed, "\n").keep_if(|name| name != "" and !List.contains(keep, name) and AristosSite.valid_version(Str.drop_prefix(name, ".")))
	if List.is_empty(stale) {
		Ok({})
	} else {
		_ = remote!(host, List.concat(["rm", "-rf", "--"], stale.map(|name| "${releases}/${name}")))?
		Stdout.line!("Removed old releases: ${Str.join_with(stale, ", ")}")
	}
}

# The public site serves exactly this release's config.json and index.html.
verify! = |url, config, index, attempts| {
	served_config = run_raw!("curl", ["--fail", "--silent", "--show-error", "--max-time", "15", "${url}/config.json"])
	served_index = run_raw!("curl", ["--fail", "--silent", "--show-error", "--max-time", "15", "${url}/"])
	match (served_config, served_index) {
		(Ok(c), Ok(i)) if c == config and i == index => Ok({})
		_ => if attempts <= 1 {
			Err(Site("${url}/ does not serve the new release: ${Str.inspect((served_config, served_index))}"))
		} else {
			Sleep.millis!(2000)
			verify!(url, config, index, attempts - 1)
		}
	}
}

require = |condition, message| if condition Ok({}) else Err(Site(message))

run_raw! = |program, args| {
	output = Cmd.new_str(program).args_str(args).exec_output!() ? |err| Site(Str.inspect(err))
	Ok(output.stdout_utf8)
}

run! = |program, args| Ok(Str.trim(run_raw!(program, args)?))

quote = |arg| "'${Str.replace_each(arg, "'", "'\\''")}'"

# SSH joins arguments into a remote command string: quote every word, not only paths.
remote_raw! = |host, args| run_raw!("ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=15", host, Str.join_with(args.map(quote), " ")])

remote! = |host, args| Ok(Str.trim(remote_raw!(host, args)?))

setting! = |key| AristosSite.setting(key, Env.var_str!(OsStr.from_str(key)) ?? "", Path.read_utf8!(Path.utf8(AristosSite.dotenv_path)) ?? "")
