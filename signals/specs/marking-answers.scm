(test "Review — marks follow the learner and the suggestion follows the marks"
  (setup
    (initial-location "/signals/#/demo"))
  (steps
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (stub-http "corpus" :url "/preload/corpora/demo.conllu" :status 200 :body "# sent_id = 1\n1\tλόγος\tλόγος\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_1|gloss=word\n2\t,\t,\tu\tu--------\t_\t1\tAuxX\t_\tt_2|gloss=,\n3\tἦν\tεἰμί\tv\tv3siia---\t_\t0\tPRED\t_\tt_3|gloss=was\n\n# sent_id = 2\n1\tθεός\tθεός\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_4|gloss=God\n\n")
    (run-effect 2)
    (stub-http "units" :url "/preload/corpora/demo.units.json" :status 200 :body "[{\"ref\":\"1.1\",\"label\":\"1:1\",\"literal\":\"word, was\",\"prose\":\"There was the word\",\"tokens\":[\"t_1\",\"t_2\",\"t_3\"]},{\"ref\":\"1.2\",\"label\":\"1:2\",\"literal\":\"God\",\"prose\":\"God\",\"tokens\":[\"t_4\"]}]")
    (run-effect 3)
    (change (test-id "store") "{\"id\":\"progress:1\",\"ok\":true,\"value\":[],\"now\":1762905600000}")
    (change (test-id "store") "{\"id\":\"settings:2\",\"ok\":true,\"value\":null,\"now\":1762905600000}")
    (fill (label "Your gloss for λόγος") "word")
    (click (role button :name "Submit checkpoint →"))
    ; Each word shows its reference beside the answer; an empty answer is a dash.
    (expect-text (text "was") "was")
    (expect-text (text "—") "—")
    (expect-text (text "0 of 2 marked") "0 of 2 marked")
    (expect-attr (role button :name "Again") "class" "rating-button is-suggested")
    (click (test-id "right-w:1"))
    (click (test-id "right-w:3"))
    (expect-attr (test-id "right-w:3") "class" "mark-button is-right")
    (expect-attr (role button :name "Good") "class" "rating-button is-suggested")
    ; Marking a word the way it is marked unmarks it.
    (click (test-id "right-w:3"))
    (expect-attr (test-id "right-w:3") "class" "mark-button")
    (expect-text (text "1 of 2 marked") "1 of 2 marked")
    ; Keep working returns to the answers, keeping them and clearing the marks.
    (click (role button :name "← Keep working"))
    (expect-value (label "Your gloss for λόγος") "word")
    (click (role button :name "Submit checkpoint →"))
    (expect-text (text "0 of 2 marked") "0 of 2 marked")
  )
)
