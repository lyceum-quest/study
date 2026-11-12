(test "Review — the Elm app's attempts and cards set today's queue"
  (setup
    ; Yesterday the Elm app graded 1:2 Good (its attempt and card), so 1:2 is due
    ; now and comes before the new 1:1. The card is replayed from the attempt.
    (initial-location "/signals/#/demo"))
  (steps
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (stub-http "corpus" :url "/preload/corpora/demo.conllu" :status 200 :body "# sent_id = 1\n1\tλόγος\tλόγος\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_1|gloss=word\n2\t,\t,\tu\tu--------\t_\t1\tAuxX\t_\tt_2|gloss=,\n3\tἦν\tεἰμί\tv\tv3siia---\t_\t0\tPRED\t_\tt_3|gloss=was\n\n# sent_id = 2\n1\tθεός\tθεός\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_4|gloss=God\n\n")
    (run-effect 2)
    (stub-http "units" :url "/preload/corpora/demo.units.json" :status 200 :body "[{\"ref\":\"1.1\",\"label\":\"1:1\",\"literal\":\"word, was\",\"prose\":\"There was the word\",\"tokens\":[\"t_1\",\"t_2\",\"t_3\"]},{\"ref\":\"1.2\",\"label\":\"1:2\",\"literal\":\"God\",\"prose\":\"God\",\"tokens\":[\"t_4\"]}]")
    (run-effect 3)
    (change (test-id "store") "{\"id\":\"progress:1\",\"ok\":true,\"value\":[{\"id\":\"attempt:demo:1.2:1762819200000\",\"type\":\"attempt\",\"work\":\"demo\",\"passage\":\"1.2\",\"sentenceId\":\"1.2\",\"sentenceText\":\"θεός\",\"startedAt\":1762819100000,\"finishedAt\":1762819200000,\"items\":[{\"key\":\"w:1\",\"kind\":\"word\",\"form\":\"θεός\",\"lemma\":\"θεός\",\"guess\":\"God\",\"reference\":\"God\",\"revealedEarly\":false,\"mark\":true}],\"rating\":\"good\"},{\"id\":\"card:demo:1.2\",\"type\":\"card\",\"work\":\"demo\",\"passage\":\"1.2\",\"introducedAt\":1762819200000,\"fsrs\":\"v5.4.2 using FSRS-6.0\",\"card\":{\"due\":1762819800000,\"stability\":2.3065,\"difficulty\":2.11810397,\"elapsedDays\":0,\"scheduledDays\":0,\"learningSteps\":1,\"reps\":1,\"lapses\":0,\"state\":\"learning\",\"lastReview\":1762819200000}},{\"id\":\"wordreview:x\",\"type\":\"wordreview\"}],\"now\":1762905600000}")
    (change (test-id "store") "{\"id\":\"settings:2\",\"ok\":true,\"value\":null,\"now\":1762905600000}")
    (expect-text (test-id "passage") "1:2")
    (expect-text (test-id "queue-kind") "Review")
    (expect-text (test-id "queue-left") "2 left today")
    (click (role button :name "Submit checkpoint →"))
    (expect-text (test-id "interval-Again") "1 min")
    (expect-text (test-id "interval-Good") "7 d")
  )
)
