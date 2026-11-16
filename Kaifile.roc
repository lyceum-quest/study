app [kaifile] {
	pf: platform "https://github.com/thebrandonlucas/kai/releases/download/v0.0.10/9jXNkEdEWZ3cyQqHMLyTenLr4Xj5nEJT48UwnU8AxPCp.tar.zst",
	std: "https://github.com/thebrandonlucas/kai/releases/download/v0.0.10/std-CJKhhQ3UzajxpUqUKcpv2cwHGJpXQ8qPRiHKL5prqK2y.tar.zst",
}

import std.Std

kaifile = Std.kaifile([
	Name("aristos"),
	Overlay("roc", "github:roc-lang/roc-overlay"),
	Environment(
		"dev",
		[
			Tools([
				"bashInteractive",
				"coreutils",
				"curl",
				"gh",
				"git",
				"gnugrep",
				"gnutar",
				"openssh",
				"rocpkgs.nightly-2026-09-19-d025939",
				"rsync",
				"zstd",
			]),
			Overlays(["roc"]),
		],
	),
	# The Roc compiler for roc-signals 0.5.0, for the app (signals/), its packages under packages/, and their tests.
	# The nightly the 0.5.0 release was built and tested with; its native spec runner crashes when built with
	# nightly-2026-11-10.
	Environment(
		"signals",
		[
			Tools([
				"coreutils",
				"rocpkgs.nightly-2026-11-11-7679cc5",
			]),
			Overlays(["roc"]),
		],
	),
	Shell("default", [Use("dev")]),
	Shell("signals", [Use("signals")]),

	# Type-checks the FSRS package (packages/fsrs/).
	Task("check-fsrs-roc", [Use("signals"), Run(["roc", "check", "packages/fsrs/main.roc"])]),

	# Runs the FSRS package against the ts-fsrs and fsrs-rs reference outputs in tests/fixtures/fsrs/*.json.
	Task("test-fsrs-roc", [Use("signals"), Run(["roc", "devtools/test-fsrs.roc"])]),

	# Checks word cards, word review records and today's plan (packages/study/Words.roc and Today.roc).
	Task("test-words-today", [Use("signals"), Run(["roc", "devtools/test-words-today.roc"])]),

	# Checks reading goals: names, coverage, known words and pace (packages/study/Reading.roc).
	Task("test-reading", [Use("signals"), Run(["roc", "devtools/test-reading.roc"])]),

	# Checks the CHANGELOG.md parser for the What's new page (packages/study/Changelog.roc).
	Task("test-changelog", [Use("signals"), Run(["roc", "devtools/test-changelog.roc"])]),

	# Check syncing with the account (packages/study/Sync.roc) and replaying review cards from attempts (Review.roc).
	Task("test-sync", [Use("signals"), Run(["roc", "devtools/test-sync.roc"])]),

	Task("test-review-cards", [Use("signals"), Run(["roc", "devtools/test-review-cards.roc"])]),

	# Checks corpus parsing over the real preload, citations, drafts and attempts (packages/study/Corpus.roc and Study.roc).
	Task("test-corpus", [Use("signals"), Run(["roc", "devtools/test-corpus.roc"])]),

	# Type-checks the app (signals/, on roc-signals) and its build script.
	Task("check-signals", [Use("signals"), Run(["roc", "check", "signals/main.roc"])]),

	Task("check-signals-tool", [Use("signals"), Run(["roc", "check", "scripts/signals.roc"])]),

	# Builds the app module (app.wasm) and fetches the pinned roc-signals runtime (runtime.mjs, see
	# signals/runtime.lock.json) at the repository root, where index.html loads them.
	Task("build-signals", [Use("signals"), Run(["roc", "scripts/signals.roc", "build"])]),

	# Runs the app's specs (signals/specs/*.scm) with its native spec runner. Their Chrome replay needs a
	# checkout of roc-signals at the release tag (lukewilliamboswell/roc-signals#202; roc-issues
	# archive/RS-003-browser-spec-runner-in-release).
	Task("test-signals", [Use("signals"), Run(["roc", "scripts/signals.roc", "specs"])]),

	Workflow(
		"signals",
		[
			RunTask("check-signals-tool", []),
			RunTask("check-signals", []),
			RunTask("test-signals", []),
			RunTask("build-signals", []),
		],
	),

	# Replaces preload/ with the Archeion preload release pinned in preload.lock.json (checked by SHA-256). Archeion
	# generates and releases the data; see its PIPELINE.md.
	Task("fetch-preload", [Use("dev"), Run(["roc", "scripts/fetch-preload.roc"])]),

	Task("check-fetch-preload-tool", [Use("dev"), Run(["roc", "check", "scripts/fetch-preload.roc"])]),

	Task("check-release-tool", [Use("dev"), Run(["roc", "check", "scripts/build-release.roc"])]),

	Task("check-browser-boundary-tool", [Use("dev"), Run(["roc", "check", "scripts/check-browser-boundary.roc"])]),

	Task("check-browser-boundary", [Use("dev"), Run(["roc", "scripts/check-browser-boundary.roc"])]),

	# kai run bundle -- production|staging|local
	# Builds dist/aristos/<target>/<version>/ from the current preload/ (see DEPLOYMENT.md); the release workflows
	# fetch the pinned preload/ first.
	Task("bundle", [Use("dev"), Run(["roc", "scripts/build-release.roc"])]),

	Task("check-deploy-site-tool", [Use("dev"), Run(["roc", "check", "scripts/deploy-site.roc"])]),

	# kai run deploy-site -- production|staging [<version>]   (default: the newest bundle for that target)
	# Needs ARISTOS_DEPLOY_HOST (see .env.example); production also needs ARISTOS_DEPLOY_PRODUCTION=1.
	Task("deploy-site", [Use("dev"), Run(["roc", "scripts/deploy-site.roc", "deploy"])]),

	# kai run rollback-site -- production|staging   (swaps the host's current and previous releases)
	Task("rollback-site", [Use("dev"), Run(["roc", "scripts/deploy-site.roc", "rollback"])]),

	# kai workflow release (production) or release-staging: fetch the pinned preload/, build the app, and bundle a release
	# for deploy-site.
	Workflow(
		"release",
		[
			RunTask("check-fetch-preload-tool", []),
			RunTask("check-release-tool", []),
			RunTask("check-browser-boundary-tool", []),
			RunTask("check-deploy-site-tool", []),
			RunTask("fetch-preload", []),
			RunTask("build-signals", []),
			RunTask("check-browser-boundary", []),
			RunTask("bundle", ["production"]),
		],
	),

	Workflow(
		"release-staging",
		[
			RunTask("check-fetch-preload-tool", []),
			RunTask("check-release-tool", []),
			RunTask("check-browser-boundary-tool", []),
			RunTask("check-deploy-site-tool", []),
			RunTask("fetch-preload", []),
			RunTask("build-signals", []),
			RunTask("check-browser-boundary", []),
			RunTask("bundle", ["staging"]),
		],
	),
])
