(test "Review — grading a card through each rating advances the queue"
  (setup
    ; Two passages of a small work, and empty storage. Storage results are the
    ; change events browser-bridge.js's <lyceum-store> sends; their "now" is the
    ; app's clock. 1762905600000 is 2025-11-12T00:00:00Z.
    (initial-location "/signals/#/demo"))
  (steps
    (expect-text (text "Loading the passages and your progress…") "Loading the passages and your progress…")
    ; At mount the app asks storage for the progress store and two settings.
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"progress:1\",\"operation\":\"getAll\",\"store\":\"progress\"},{\"id\":\"settings:2\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"review-settings\"},{\"id\":\"theme:3\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"theme\"}]")
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (stub-http "corpus" :url "/preload/corpora/demo.conllu" :status 200 :body "# sent_id = 1\n1\tλόγος\tλόγος\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_1|gloss=word\n2\t,\t,\tu\tu--------\t_\t1\tAuxX\t_\tt_2|gloss=,\n3\tἦν\tεἰμί\tv\tv3siia---\t_\t0\tPRED\t_\tt_3|gloss=was\n\n# sent_id = 2\n1\tθεός\tθεός\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_4|gloss=God\n\n")
    (run-effect 2)
    (stub-http "units" :url "/preload/corpora/demo.units.json" :status 200 :body "[{\"ref\":\"1.1\",\"label\":\"1:1\",\"literal\":\"word, was\",\"prose\":\"There was the word\",\"tokens\":[\"t_1\",\"t_2\",\"t_3\"]},{\"ref\":\"1.2\",\"label\":\"1:2\",\"literal\":\"God\",\"prose\":\"God\",\"tokens\":[\"t_4\"]}]")
    (run-effect 3)
    (change (test-id "store") "{\"id\":\"progress:1\",\"ok\":true,\"value\":[],\"now\":1762905600000}")
    (change (test-id "store") "{\"id\":\"settings:2\",\"ok\":true,\"value\":null,\"now\":1762905600000}")
    (change (test-id "store") "{\"id\":\"theme:3\",\"ok\":true,\"value\":null,\"now\":1762905600000}")

    ; Passage 1:1 is new. Again: one of two marked answers wrong.
    (expect-text (test-id "passage") "1:1")
    (expect-text (test-id "queue-kind") "New")
    (expect-text (test-id "queue-left") "2 left today")
    (fill (label "Your gloss for λόγος") "word")
    (fill (label "Your gloss for ἦν") "is")
    (click (role button :name "Submit checkpoint →"))
    (expect-text (test-id "interval-Again") "1 min")
    (expect-text (test-id "interval-Hard") "6 min")
    (expect-text (test-id "interval-Good") "10 min")
    (expect-text (test-id "interval-Easy") "8 d")
    (click (test-id "right-w:1"))
    (click (test-id "wrong-w:3"))
    (expect-text (text "2 of 2 marked") "2 of 2 marked")
    (expect-attr (role button :name "Again") "class" "rating-button is-suggested")
    (click (role button :name "Again"))
    ; The rating asks storage for the time, then saves the attempt, the card and
    ; the passage's cleared draft in the Elm app's shapes.
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"rating:4\",\"operation\":\"get\",\"store\":\"progress\",\"key\":\"card:demo:1.1\"}]")
    (change (test-id "store") "{\"id\":\"rating:4\",\"ok\":true,\"value\":null,\"now\":1762905660000}")
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"save:5\",\"operation\":\"put\",\"store\":\"progress\",\"value\":{\"id\":\"attempt:demo:1.1:1762905660000\",\"type\":\"attempt\",\"work\":\"demo\",\"passage\":\"1.1\",\"sentenceId\":\"1.1\",\"sentenceText\":\"λόγος , ἦν\",\"startedAt\":1762905600000,\"finishedAt\":1762905660000,\"items\":[{\"key\":\"w:1\",\"kind\":\"word\",\"form\":\"λόγος\",\"lemma\":\"λόγος\",\"guess\":\"word\",\"reference\":\"word\",\"revealedEarly\":false,\"mark\":true},{\"key\":\"w:3\",\"kind\":\"word\",\"form\":\"ἦν\",\"lemma\":\"εἰμί\",\"guess\":\"is\",\"reference\":\"was\",\"revealedEarly\":false,\"mark\":false}],\"rating\":\"again\"}},{\"id\":\"save:6\",\"operation\":\"put\",\"store\":\"progress\",\"value\":{\"id\":\"card:demo:1.1\",\"type\":\"card\",\"work\":\"demo\",\"passage\":\"1.1\",\"introducedAt\":1762905660000,\"fsrs\":\"v5.4.2 using FSRS-6.0\",\"card\":{\"due\":1762905720000,\"stability\":0.212,\"difficulty\":6.4133,\"elapsedDays\":0,\"scheduledDays\":0,\"learningSteps\":0,\"reps\":1,\"lapses\":0,\"state\":\"learning\",\"lastReview\":1762905660000}}},{\"id\":\"save:7\",\"operation\":\"put\",\"store\":\"metadata\",\"value\":{\"key\":\"draft:demo:1.1\",\"value\":{\"glosses\":[],\"literal\":\"\",\"prose\":\"\",\"revealed\":[],\"submitted\":false,\"marks\":{},\"startedAt\":0,\"updatedAt\":0}}}]")

    ; Passage 1:2 is new; 1:1 comes back in a minute. Hard, with nothing marked.
    (expect-text (test-id "passage") "1:2")
    (expect-text (test-id "queue-kind") "New")
    (expect-text (test-id "queue-left") "1 left today")
    (click (role button :name "Submit checkpoint →"))
    (expect-text (text "0 of 1 marked") "0 of 1 marked")
    (expect-attr (role button :name "Again") "class" "rating-button is-suggested")
    (click (role button :name "Hard"))
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"rating:8\",\"operation\":\"get\",\"store\":\"progress\",\"key\":\"card:demo:1.2\"}]")
    (change (test-id "store") "{\"id\":\"rating:8\",\"ok\":true,\"value\":null,\"now\":1762905720000}")

    ; 1:1 is due again. Good, everything marked right.
    (expect-text (test-id "passage") "1:1")
    (expect-text (test-id "queue-kind") "Review")
    (expect-text (test-id "queue-left") "1 left today")
    (expect-value (label "Your gloss for λόγος") "")
    (click (role button :name "Submit checkpoint →"))
    (click (test-id "right-w:1"))
    (click (test-id "right-w:3"))
    (expect-attr (role button :name "Good") "class" "rating-button is-suggested")
    (click (role button :name "Good"))
    (change (test-id "store") "{\"id\":\"rating:12\",\"ok\":true,\"value\":null,\"now\":1762905780000}")

    ; Nothing is due: the queue is done until 1:2 comes back.
    (expect-text (role heading :name "Done for today") "Done for today")
    (expect-text (test-id "done-summary") "3 passages graded today, 75% of marked answers right.")
    (expect-text (test-id "done-next") "Next review due in 5 min. New passages: up to 10 a day.")
    (expect-absent (role button :name "Review now →"))

    ; The clock is refreshed every 15 seconds; once 1:2 is due it can be reviewed. Easy.
    (tick-interval 15000)
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"settings:16\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"review-settings\"}]")
    (change (test-id "store") "{\"id\":\"settings:16\",\"ok\":true,\"value\":null,\"now\":1762906080000}")
    (expect-text (test-id "done-next") "1 review is due now.")
    (click (role button :name "Review now →"))
    (expect-text (test-id "passage") "1:2")
    (expect-text (test-id "queue-kind") "Review")
    (click (role button :name "Submit checkpoint →"))
    (click (role button :name "Easy"))
    (change (test-id "store") "{\"id\":\"rating:17\",\"ok\":true,\"value\":null,\"now\":1762906090000}")
    (expect-text (role heading :name "Done for today") "Done for today")
    (expect-text (test-id "done-summary") "4 passages graded today, 75% of marked answers right.")
  )
)
