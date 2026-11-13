app [main!] {
	study: "../packages/study/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.0/2yhxoR7cZPSYbyUzPWULFw8AA6QEcdsgFNRmzu7pZbst.tar.zst",
}

import pf.Stdout
import study.Changelog

# Checks the Roc changelog parser (packages/study/Changelog.roc) with the cases
# of tests/ChangelogTest.elm. Prints a summary and the failures, and exits with
# 1 if any check fails.
main! = |_args| {
	parsed = Changelog.parse(sample)
	checks = [
		check(
			"versions with something to show, newest first",
			Str.inspect(parsed.map(|version| version.name)),
			Str.inspect(["Unreleased", "2026-10-13"]),
		),
		check(
			"sections and plain items; Internal and comments left out",
			Str.inspect(parsed.first().map_ok(|version| version.sections)),
			Str.inspect(Ok([{ title: "Added", items: ["A new text: see Romans and code, continued here."] }])),
		),
		check(
			"bullets under a version without a section",
			Str.inspect(parsed.drop_first(1).first().map_ok(|version| version.sections)),
			Str.inspect(Ok([{ title: "", items: ["First release."] }])),
		),
	]
	failed = checks.keep_if(|found| found.problem != "")
	Stdout.line!("${(checks.len() - failed.len()).to_str()}/${checks.len().to_str()} Changelog.parse")?
	for found in failed {
		Stdout.line!("\n${found.name}\n${found.problem}")?
	}
	if failed.is_empty() {
		Stdout.line!("All changelog checks pass.")?
		Ok({})
	} else {
		Err(Exit(1))
	}
}

# A named check; `problem` is "" when it passes.
Check : { name : Str, problem : Str }

# Values are compared as `Str.inspect` shows them, which is also the message.
check : Str, Str, Str -> Check
check = |name, actual, expected|
	if actual == expected {
		{ name, problem: "" }
	} else {
		{ name, problem: "  actual:   ${actual}\n  expected: ${expected}" }
	}

sample : Str
sample =
	\\# Changelog
	\\
	\\Intro.
	\\
	\\## [Unreleased]
	\\
	\\<!-- Draft
	\\- feat: not shown
	\\-->
	\\
	\\### Added
	\\
	\\- A **new** text: see [Romans](https://lyceum.quest/read/x) and `code`,
	\\  continued here.
	\\
	\\### Internal
	\\
	\\- Hidden.
	\\
	\\## [2026-10-13]
	\\
	\\- First release.
	\\
	\\## [2026-01-01]
	\\
	\\### Internal
	\\
	\\- Only internal.
	\\
