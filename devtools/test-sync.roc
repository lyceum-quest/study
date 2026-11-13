app [main!] {
	fsrs: "../packages/fsrs/main.roc",
	json: "../packages/json/main.roc",
	study: "../packages/study/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.0/2yhxoR7cZPSYbyUzPWULFw8AA6QEcdsgFNRmzu7pZbst.tar.zst",
}

import pf.Stdout
import json.JsonValue
import study.Sync

# The sync state and status lines (packages/study/Sync.roc), as
# tests/SyncTest.elm checks the Elm module. Prints a summary and the failures,
# and exits with 1 if any check fails.
main! = |_args| {
	checks = [
		state_survives_storage,
		new_account_starts_from_nothing,
		status_lines,
	]
	failed = checks.keep_if(|check| check.problem != "")
	Stdout.line!("${(checks.len() - failed.len()).to_str()}/${checks.len().to_str()} Sync")?
	if failed.is_empty() {
		Stdout.line!("All Sync checks pass.")?
		Ok({})
	} else {
		for check in failed {
			Stdout.line!("\n${check.name}\n${check.problem}")?
		}
		Err(Exit(1))
	}
}

# A named check; `problem` is "" when it passes.
Check : { name : Str, problem : Str }

expect_equal : Str, a, a -> Check where [a.is_eq : a, a -> Bool]
expect_equal = |name, actual, expected|
	if actual == expected {
		{ name, problem: "" }
	} else {
		{ name, problem: "${Str.inspect(actual)}\n/=\n${Str.inspect(expected)}" }
	}

state_survives_storage : Check
state_survives_storage = {
	state = {
		account: 7,
		cursor: 42,
		primed: Bool.True,
		sent: Set.from_list(["attempt:a", "wordreview:b"]),
		settings: Dict.from_list([("theme", { value: "\"dark\"", updated_at: 5 })]),
	}
	expect_equal(
		"the state survives storage",
		match JsonValue.decode(JsonValue.encode(Sync.encode_state(state))) {
			Ok(json) => Sync.decode_state(json)
			Err(message) => Err(message)
		},
		Ok(state),
	)
}

new_account_starts_from_nothing : Check
new_account_starts_from_nothing =
	expect_equal(
		"a new account starts from nothing",
		Sync.empty_state(3),
		{ account: 3, cursor: 0, primed: Bool.False, sent: Set.empty(), settings: Dict.empty() },
	)

status_lines : Check
status_lines =
	expect_equal(
		"status lines",
		[Synced(990000), Synced(1000000 - 5 * 60000), Offline, NeedsSupporter].map(|status| Sync.status_text(1000000, status)),
		["Synced just now", "Synced 5 min ago", "Offline: will sync when back online", "Sync is for Supporters"],
	)
