(test "Library — the works being studied, then the library, searched and sorted"
  (setup
    ; Three works. Yesterday the Elm app graded Demo 1:2 (its attempt and card,
    ; due again now); later a word of Other was reviewed; Solo was only opened
    ; (it has a saved position). 1762905600000 is 2025-11-12T00:00:00Z.
    (initial-location "/signals/"))
  (steps
    (expect-text (text "Loading the library…") "Loading the library…")
    ; At mount the app asks storage for what the Elm app reads at start.
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"theme:1\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"theme\"},{\"id\":\"reader-layers:2\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"reader-layers\"},{\"id\":\"positions:3\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"positions\"},{\"id\":\"settings:4\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"review-settings\"},{\"id\":\"scope:5\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"today-scope\"},{\"id\":\"progress:6\",\"operation\":\"getAll\",\"store\":\"progress\"}]")
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"},\"citation\":{\"text\":{\"urn\":\"urn:demo\",\"author\":\"Test Author\",\"title\":\"Demo\",\"edition\":\"Test edition\",\"repository\":\"Test/repo\",\"snapshot\":\"1.0\",\"license\":\"CC BY-SA 4.0\",\"readerUrl\":\"https://example.org/demo\",\"sourceUrl\":\"https://example.org/demo.xml\"},\"annotations\":{\"name\":\"Opera Graeca Adnotata\",\"version\":\"v0.2.0\",\"url\":\"https://example.org/oga\",\"license\":\"CC BY-SA 4.0\"},\"generated\":{\"name\":\"Aristos\",\"layers\":\"glosses\",\"model\":\"a model\",\"license\":\"CC BY-SA 4.0\"}}},{\"id\":\"other\",\"title\":\"Other Work\",\"path\":\"corpora/other.conllu\",\"unitsPath\":\"corpora/other.units.json\",\"passages\":[\"1\",\"2\",\"3\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Other edition\"}},{\"id\":\"solo\",\"title\":\"Solo Work\",\"path\":\"corpora/solo.conllu\",\"unitsPath\":\"corpora/solo.units.json\",\"passages\":[\"1\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Solo edition\"}}]}")
    (run-effect 1)
    (change (test-id "store") "{\"id\":\"progress:6\",\"ok\":true,\"value\":[{\"id\":\"attempt:demo:1.2:1762819200000\",\"type\":\"attempt\",\"work\":\"demo\",\"passage\":\"1.2\",\"sentenceId\":\"1.2\",\"sentenceText\":\"θεός\",\"startedAt\":1762819100000,\"finishedAt\":1762819200000,\"items\":[{\"key\":\"w:1\",\"kind\":\"word\",\"form\":\"θεός\",\"lemma\":\"θεός\",\"guess\":\"God\",\"reference\":\"God\",\"revealedEarly\":false,\"mark\":true}],\"rating\":\"good\"},{\"id\":\"card:demo:1.2\",\"type\":\"card\",\"work\":\"demo\",\"passage\":\"1.2\",\"introducedAt\":1762819200000,\"fsrs\":\"v5.4.2 using FSRS-6.0\",\"card\":{\"due\":1762819800000,\"stability\":2.3065,\"difficulty\":2.11810397,\"elapsedDays\":0,\"scheduledDays\":0,\"learningSteps\":1,\"reps\":1,\"lapses\":0,\"state\":\"learning\",\"lastReview\":1762819200000}},{\"id\":\"wordreview:λόγος:1762900000000\",\"type\":\"wordreview\",\"lemma\":\"λόγος\",\"at\":1762900000000,\"rating\":\"good\",\"occurrence\":{\"work\":\"other\",\"passage\":\"2\",\"position\":1,\"form\":\"λόγος\",\"gloss\":\"word\",\"text\":\"λόγος\",\"guess\":\"word\"}}],\"now\":1762905600000}")
    (change (test-id "store") "{\"id\":\"positions:3\",\"ok\":true,\"value\":{\"key\":\"positions\",\"value\":{\"solo\":1}},\"now\":1762905600000}")
    (change (test-id "store") "{\"id\":\"scope:5\",\"ok\":true,\"value\":null,\"now\":1762905600000}")

    ; Working on: studied works, most recent first, then opened ones.
    (expect-text (test-id "working-1") "Other Work")
    (expect-text (test-id "working-2") "Demo Work")
    (expect-text (test-id "working-3") "Solo Work")
    (expect-text (test-id "working:demo") "1 of 2 passages studied · 1 due")
    (expect-text (test-id "working:other") "3 passages · not started")
    (expect-text (test-id "working:demo:study") "Study →")
    (expect-text (test-id "working:other:study") "Start →")

    ; The library: recently studied first, then by title.
    (expect-text (test-id "library-1") "Other Work")
    (expect-text (test-id "library-2") "Demo Work")
    (expect-text (test-id "library-3") "Solo Work")
    (expect-text (test-id "library:solo") "1 passage · not started")
    (select-option (label "Sort the library") "title")
    (expect-text (test-id "library-1") "Demo Work")
    (expect-text (test-id "library-2") "Other Work")
    (select-option (label "Sort the library") "short")
    (expect-text (test-id "library-1") "Solo Work")
    (expect-text (test-id "library-3") "Other Work")

    ; The search matches the citation's author too, ignoring case.
    (fill (label "Search the library") "test AUTHOR")
    (expect-text (test-id "library-1") "Demo Work")
    (expect-absent (test-id "library-2"))
    (fill (label "Search the library") "nothing like it")
    (expect-text (text "No works match.") "No works match.")

    ; Study starts today's session in the work, at its due review, and saves the scope.
    (click (test-id "working:demo:study"))
    (expect-current-location "/signals/#/demo/1.2?today=all")
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"save:7\",\"operation\":\"put\",\"store\":\"metadata\",\"value\":{\"key\":\"today-scope\",\"value\":\"demo\"}}]")
  )
)
