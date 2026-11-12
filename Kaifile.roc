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
