(test "Study — answering, the checkpoint, marking and a rating save an attempt and open the next passage"
  (setup
    ; A small work of two passages and empty storage. Storage results are the
    ; change events browser-bridge.js's <lyceum-store> sends; their "now" is the
    ; app's clock. 1762905600000 is 2025-11-12T00:00:00Z.
    (initial-location "/signals/#/demo/1.1"))
  (steps
    (expect-text (text "Loading the library…") "Loading the library…")
    ; At mount the app asks storage for what the Elm app reads at start.
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"theme:1\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"theme\"},{\"id\":\"reader-layers:2\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"reader-layers\"},{\"id\":\"positions:3\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"positions\"},{\"id\":\"settings:4\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"review-settings\"},{\"id\":\"scope:5\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"today-scope\"},{\"id\":\"progress:6\",\"operation\":\"getAll\",\"store\":\"progress\"}]")
    (change (test-id "store") "{\"id\":\"progress:6\",\"ok\":true,\"value\":[],\"now\":1762905600000}")
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (stub-http "corpus" :url "/preload/corpora/demo.conllu" :status 200 :body "# sent_id = 1\n1\tλόγος\tλόγος\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_1|gloss=word\n2\t,\t,\tu\tu--------\t_\t1\tAuxX\t_\tt_2|gloss=,\n3\tἦν\tεἰμί\tv\tv3siia---\t_\t0\tPRED\t_\tt_3|gloss=was\n\n# sent_id = 2\n1\tθεός\tθεός\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_4|gloss=God\n\n")
    (run-effect 2)
    (stub-http "units" :url "/preload/corpora/demo.units.json" :status 200 :body "[{\"ref\":\"1.1\",\"label\":\"1:1\",\"literal\":\"word, was\",\"prose\":\"There was the word\",\"tokens\":[\"t_1\",\"t_2\",\"t_3\"]},{\"ref\":\"1.2\",\"label\":\"1:2\",\"literal\":\"God\",\"prose\":\"God\",\"tokens\":[\"t_4\"]}]")
    (run-effect 3)
    ; The passage opens and asks for its saved draft.
    (expect-current-location "/signals/#/demo/1.1")
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"draft:7\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"draft:demo:1.1\"}]")
    (change (test-id "store") "{\"id\":\"draft:7\",\"ok\":true,\"value\":null,\"now\":1762905600000}")
    (expect-text (role button :name "λόγος,") "λόγος,")
    (fill (label "Your gloss for λόγος") "word")
    (fill (label "Your gloss for ἦν") "is")
    (expect-text (text "2 of 2 words") "2 of 2 words")
    (click (role button :name "Submit checkpoint →"))
    (expect-text (test-id "interval-Again") "1 min")
    (expect-text (test-id "interval-Good") "10 min")
    (click (test-id "right-w:1"))
    (click (test-id "wrong-w:3"))
    (expect-attr (role button :name "Again") "class" "rating-button is-suggested")
    (click (role button :name "Good"))
    ; The rating asks storage for the time, then saves the attempt, the card and
    ; the cleared draft in the Elm app's shapes, and opens the next passage.
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"rating:13\",\"operation\":\"get\",\"store\":\"progress\",\"key\":\"card:demo:1.1\"}]")
    (change (test-id "store") "{\"id\":\"rating:13\",\"ok\":true,\"value\":null,\"now\":1762905660000}")
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"save:14\",\"operation\":\"put\",\"store\":\"progress\",\"value\":{\"id\":\"attempt:demo:1.1:1762905660000\",\"type\":\"attempt\",\"work\":\"demo\",\"passage\":\"1.1\",\"sentenceId\":\"1.1\",\"sentenceText\":\"λόγος , ἦν\",\"startedAt\":1762905600000,\"finishedAt\":1762905660000,\"items\":[{\"key\":\"w:1\",\"kind\":\"word\",\"form\":\"λόγος\",\"lemma\":\"λόγος\",\"guess\":\"word\",\"reference\":\"word\",\"revealedEarly\":false,\"mark\":true},{\"key\":\"w:3\",\"kind\":\"word\",\"form\":\"ἦν\",\"lemma\":\"εἰμί\",\"guess\":\"is\",\"reference\":\"was\",\"revealedEarly\":false,\"mark\":false},{\"key\":\"prose\",\"kind\":\"prose\",\"form\":\"\",\"lemma\":\"\",\"guess\":\"\",\"reference\":\"There was the word\",\"revealedEarly\":false,\"mark\":null}],\"rating\":\"good\"}},{\"id\":\"save:15\",\"operation\":\"put\",\"store\":\"progress\",\"value\":{\"id\":\"card:demo:1.1\",\"type\":\"card\",\"work\":\"demo\",\"passage\":\"1.1\",\"introducedAt\":1762905660000,\"fsrs\":\"v5.4.2 using FSRS-6.0\",\"card\":{\"due\":1762906260000,\"stability\":2.3065,\"difficulty\":2.11810397,\"elapsedDays\":0,\"scheduledDays\":0,\"learningSteps\":1,\"reps\":1,\"lapses\":0,\"state\":\"learning\",\"lastReview\":1762905660000}}},{\"id\":\"save:16\",\"operation\":\"put\",\"store\":\"metadata\",\"value\":{\"key\":\"draft:demo:1.1\",\"value\":{\"glosses\":[],\"literal\":\"\",\"prose\":\"\",\"revealed\":[],\"submitted\":false,\"marks\":{},\"startedAt\":0,\"updatedAt\":0}}},{\"id\":\"draft:17\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"draft:demo:1.2\"},{\"id\":\"save:18\",\"operation\":\"put\",\"store\":\"metadata\",\"value\":{\"key\":\"positions\",\"value\":{\"demo\":2}}}]")
    (expect-current-location "/signals/#/demo/1.2")
    (expect-value (label "Your gloss for θεός") "")
    (click (role button :name "Previous passage (← or k)"))
    (expect-current-location "/signals/#/demo/1.1")
    (expect-text (role button :name "1 past attempt →") "1 past attempt →")
  )
)
