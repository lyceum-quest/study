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
				"elmPackages.elm",
				"elmPackages.elm-live",
				"elmPackages.elm-test",
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
	# The newer Roc compiler that roc-signals 0.3.0 tracks, for the pure Roc packages under packages/ and their tests.
	Environment(
		"signals",
		[
			Tools([
				"coreutils",
				"rocpkgs.nightly-2026-11-07-ad3a5d2",
			]),
			Overlays(["roc"]),
		],
	),
	Shell("default", [Use("dev")]),
	Shell("signals", [Use("signals")]),

	# Type-checks the Roc FSRS package (packages/fsrs/), a port of src/Fsrs.elm.
	Task("check-fsrs-roc", [Use("signals"), Run(["roc", "check", "packages/fsrs/main.roc"])]),

	# Runs the Roc FSRS package against tests/fixtures/fsrs/*.json, as tests/FsrsTest.elm does for the Elm port.
	Task("test-fsrs-roc", [Use("signals"), Run(["roc", "devtools/test-fsrs.roc"])]),

	# Checks the Roc ports of src/Words.elm and src/Today.elm (word cards, word review records, today's plan).
	Task("test-words-today", [Use("signals"), Run(["roc", "devtools/test-words-today.roc"])]),

	# Runs tests/ChangelogTest.elm's cases against the Roc port of src/Changelog.elm.
	Task("test-changelog", [Use("signals"), Run(["roc", "devtools/test-changelog.roc"])]),

	# Runs tests/SyncTest.elm's and tests/ReviewCardsTest.elm's cases against the Roc ports of src/Sync.elm and src/Review.elm.
	Task("test-sync", [Use("signals"), Run(["roc", "devtools/test-sync.roc"])]),

	Task("test-review-cards", [Use("signals"), Run(["roc", "devtools/test-review-cards.roc"])]),

	# Type-checks the port to roc-signals (signals/: the Elm library and review screens) and its build script.
	Task("check-signals", [Use("signals"), Run(["roc", "check", "signals/main.roc"])]),

	Task("check-signals-tool", [Use("signals"), Run(["roc", "check", "scripts/signals.roc"])]),

	# Builds the port as a static page in dist/signals/ with the pinned roc-signals runtime
	# (signals/runtime.lock.json). It shares the Elm app's IndexedDB only when served from the same origin, as from the
	# repository root at /dist/signals/.
	Task("build-signals", [Use("signals"), Run(["roc", "scripts/signals.roc", "build"])]),

	# Runs the port's specs (signals/specs/*.scm) with its native spec runner. Their Chrome replay needs a
	# checkout of roc-signals at the release tag (roc-issues roc-signals/RS-003-browser-spec-runner-in-release).
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

	# Embeds tests/fixtures/fsrs/*.json in the generated tests/FsrsFixtures.elm.
	Task("generate-fsrs-fixtures", [Use("dev"), Run(["roc", "devtools/generate-fsrs-fixtures.roc"])]),

	Task("check-fsrs-fixtures-tool", [Use("dev"), Run(["roc", "check", "devtools/generate-fsrs-fixtures.roc"])]),

	# Runs the Elm tests (the FSRS port against ts-fsrs and fsrs-rs fixtures).
	Task("test-elm", [Use("dev"), Run(["elm-test"])]),

	Workflow(
		"test-fsrs",
		[
			RunTask("generate-fsrs-fixtures", []),
			RunTask("test-elm", []),
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

	# kai workflow release (production) or release-staging: fetch the pinned preload/ and bundle a release for deploy-site.
	Workflow(
		"release",
		[
			RunTask("check-fetch-preload-tool", []),
			RunTask("check-release-tool", []),
			RunTask("check-browser-boundary-tool", []),
			RunTask("check-deploy-site-tool", []),
			RunTask("fetch-preload", []),
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
			RunTask("check-browser-boundary", []),
			RunTask("bundle", ["staging"]),
		],
	),
])
