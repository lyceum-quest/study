(test "Account — a supporter signs in, and a sync round brings another device's progress and theme"
  (setup
    (initial-location "/signals/#/stats"))
  (steps
    (change (test-id "store") "{\"id\":\"progress:8\",\"ok\":true,\"value\":[],\"now\":1762905600000}")
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    ; The release names its account API; the API says who is signed in.
    (stub-http "config" :url "/config.json" :status 200 :body "{\"accountApi\":\"https://api.test/\"}")
    (run-effect 2)
    (expect-text (text "Checking your Lyceum account…") "Checking your Lyceum account…")
    (stub-http "me" :url "https://api.test/api/me" :status 200 :body "{\"user\":{\"id\":7,\"handle\":\"brandon\",\"pro\":true,\"entitlements\":[\"sync\"]}}")
    (run-effect 3)
    (expect-text (text "Signed in to Lyceum as ") "Signed in to Lyceum as brandon.")
    (expect-attr (role link :name "brandon") "title" "Signed in as brandon · Not synced yet")
    (expect-absent (role link :name "Support") :never-drawn)
    ; The sync state is read once; the next tick syncs.
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"sync-state:10\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"sync-state\"}]")
    (change (test-id "store") "{\"id\":\"sync-state:10\",\"ok\":true,\"value\":null,\"now\":1762905600000}")
    (tick-interval 5000)
    (change (test-id "store") "{\"id\":\"settings:11\",\"ok\":true,\"value\":null,\"now\":1762905605000}")
    (tick-interval 5000)
    (expect-text (text "Syncing…") "Syncing…")
    (stub-http "sync" :url "https://api.test/api/sync" :status 200 :body "{\"records\":[{\"id\":\"attempt:demo:1.1:1762819200000\",\"type\":\"attempt\",\"updatedAt\":1762819200000,\"body\":{\"id\":\"attempt:demo:1.1:1762819200000\",\"type\":\"attempt\",\"work\":\"demo\",\"passage\":\"1.1\",\"sentenceId\":\"1.1\",\"sentenceText\":\"λόγος , ἦν\",\"startedAt\":1762819100000,\"finishedAt\":1762819200000,\"items\":[{\"key\":\"w:1\",\"kind\":\"word\",\"form\":\"λόγος\",\"lemma\":\"λόγος\",\"guess\":\"word\",\"reference\":\"word\",\"revealedEarly\":false,\"mark\":true},{\"key\":\"w:3\",\"kind\":\"word\",\"form\":\"ἦν\",\"lemma\":\"εἰμί\",\"guess\":\"is\",\"reference\":\"was\",\"revealedEarly\":false,\"mark\":false},{\"key\":\"prose\",\"kind\":\"prose\",\"form\":\"\",\"lemma\":\"\",\"guess\":\"\",\"reference\":\"There was the word\",\"revealedEarly\":false,\"mark\":null}],\"rating\":\"good\"}},{\"id\":\"meta:theme\",\"type\":\"setting\",\"updatedAt\":1762905000000,\"body\":\"light\"}],\"cursor\":12,\"more\":false}")
    (run-effect 4)
    (expect-attr (role button :name "Use dark theme") "aria-pressed" "false")
    (expect-text (test-id "tile-Passages studied") "1")
  )
)
