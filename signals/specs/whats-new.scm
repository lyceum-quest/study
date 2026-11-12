(test "What's new — the changelog, newest first, without internal notes"
  (setup
    (initial-location "/signals/#/whats-new"))
  (steps
    (expect-text (text "Loading…") "Loading…")
    (stub-http "changelog" :url "/CHANGELOG.md" :status 200 :body "# Changelog\n\n## [Unreleased]\n\n### Added\n\n- A **new** text.\n\n### Internal\n\n- Refactoring.\n\n## [2026-11-04]\n\n- A fix.\n")
    (run-effect 2)
    (expect-text (role heading :name "Not yet released") "Not yet released")
    (expect-text (role heading :name "Added") "Added")
    (expect-text (text "A new text.") "A new text.")
    (expect-absent (text "Refactoring."))
    (expect-text (role heading :name "2026-11-04") "2026-11-04")
  )
)
