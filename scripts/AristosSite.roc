# Static Lyceum Study releases (scripts/build-release.roc) and their deployment (scripts/deploy-site.roc).
# A release is dist/aristos/<target>/<version>/; dist/aristos/<target>/latest names the newest one.
AristosSite :: [].{

	# The Lyceum account API each target's config.json names. Lyceum Study shows sign-in only when it has one,
	# so a local release ({}) behaves as before accounts existed.
	account_api : Str -> Try(Str, [Release(Str), ..])
	account_api = |target|
		match target {
			"production" => Ok("https://lyceum.quest")
			"staging" => Ok("https://lyceum.internal.blu.cx")
			"local" => Ok("")
			_ => Err(Release("unknown target ${target}: expected production, staging, or local"))
		}

	config_json : Str -> Str
	config_json = |api| if api == "" "{}\n" else "{\"accountApi\":\"${api}\"}\n"

	dist : Str -> Str
	dist = |target| "dist/aristos/${target}"

	# Release names reach ssh, rsync, and rm -rf on the host: letters, digits, '.', '-', and '_' only, never
	# starting with '.' (in-progress uploads do).
	valid_version : Str -> Bool
	valid_version = |version| {
		bytes = Str.to_utf8(version)
		!List.is_empty(bytes) and !Str.starts_with(version, ".") and List.all(bytes, |byte| (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or (byte >= 48 and byte <= 57) or List.contains([45, 46, 95], byte))
	}

	dotenv_path : Str
	dotenv_path = ".env"

	# A setting from the environment (`environment`, "" when unset) or else the repository's git-ignored .env (`dotenv`,
	# its contents; see .env.example).
	setting : Str, Str, Str -> Str
	setting = |key, environment, dotenv| if Str.trim(environment) != "" Str.trim(environment) else dotenv_value(Str.split_on(dotenv, "\n"), key, "")

	# The host reaches ssh and rsync as an argument (`host:path`), so it must not look like an option or a path.
	target : Str, Str -> Try({ host : Str, url : Str }, [InvalidTarget(Str), ..])
	target = |host, url| {
		bytes = Str.to_utf8(host)
		at_signs = List.len(List.keep_if(bytes, |byte| byte == 64))
		host_ok = !List.is_empty(bytes) and !Str.starts_with(host, "-") and at_signs <= 1 and List.all(bytes, |byte| (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or (byte >= 48 and byte <= 57) or List.contains([45, 46, 64, 95], byte))
		url_ok = (Str.starts_with(url, "http://") or Str.starts_with(url, "https://")) and List.all(Str.to_utf8(url), |byte| byte > 32 and byte < 127 and byte != 34 and byte != 39)
		if !host_ok {
			Err(InvalidTarget("invalid SSH host: ${host}"))
		} else if !url_ok {
			Err(InvalidTarget("invalid site URL: ${url}"))
		} else {
			Ok({ host, url: if Str.ends_with(url, "/") Str.drop_suffix(url, "/") else url })
		}
	}

	# `KEY=value` lines, optionally `export`ed or quoted; `#` comments. The last assignment wins, as in a shell.
	dotenv_value = |lines, key, found|
		match lines {
			[] => found
			[line, .. as rest] => {
				trimmed = Str.trim(Str.drop_prefix(Str.trim(line), "export "))
				match Str.split_on(trimmed, "=") {
					[left, .. as value] if !Str.starts_with(trimmed, "#") and Str.trim(left) == key =>
						dotenv_value(rest, key, unquote(Str.trim(Str.join_with(value, "="))))
					_ => dotenv_value(rest, key, found)
				}
			}
		}

	unquote = |value| {
		bytes = Str.to_utf8(value)
		match (List.first(bytes), List.last(bytes)) {
			(Ok(first), Ok(last)) if List.len(bytes) >= 2 and first == last and (first == 34 or first == 39) =>
				Str.from_utf8(List.drop_last(List.drop_first(bytes, 1), 1)) ?? value
			_ => value
		}
	}
}
