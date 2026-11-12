(test "Review — with nothing due and no new passages allowed, the queue is done"
  (setup
    ; The learner set new passages to 0 a day, and has no cards yet.
    (initial-location "/signals/#/demo"))
  (steps
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (stub-http "corpus" :url "/preload/corpora/demo.conllu" :status 200 :body "# sent_id = 1\n1\tλόγος\tλόγος\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_1|gloss=word\n2\t,\t,\tu\tu--------\t_\t1\tAuxX\t_\tt_2|gloss=,\n3\tἦν\tεἰμί\tv\tv3siia---\t_\t0\tPRED\t_\tt_3|gloss=was\n\n# sent_id = 2\n1\tθεός\tθεός\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_4|gloss=God\n\n")
    (run-effect 2)
    (stub-http "units" :url "/preload/corpora/demo.units.json" :status 200 :body "[{\"ref\":\"1.1\",\"label\":\"1:1\",\"literal\":\"word, was\",\"prose\":\"There was the word\",\"tokens\":[\"t_1\",\"t_2\",\"t_3\"]},{\"ref\":\"1.2\",\"label\":\"1:2\",\"literal\":\"God\",\"prose\":\"God\",\"tokens\":[\"t_4\"]}]")
    (run-effect 3)
    (change (test-id "store") "{\"id\":\"progress:1\",\"ok\":true,\"value\":[],\"now\":1762905600000}")
    (change (test-id "store") "{\"id\":\"settings:2\",\"ok\":true,\"value\":{\"key\":\"review-settings\",\"value\":{\"newPerDay\":0}},\"now\":1762905600000}")
    (expect-text (role heading :name "Done for today") "Done for today")
    (expect-text (test-id "done-summary") "0 passages graded today.")
    (expect-text (test-id "done-next") "No reviews scheduled yet. New passages: up to 0 a day.")
    (expect-absent (role button :name "Review now →"))
    (expect-absent (test-id "queue-left"))
    (expect-visible (role link :name "Back to library"))
  )
)
