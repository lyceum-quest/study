(test "Study — the work cached at its last download opens at once, then the download replaces it"
  (setup
    (initial-location "/signals/#/demo/1.2"))
  (steps
    (change (test-id "store") "{\"id\":\"progress:8\",\"ok\":true,\"value\":[],\"now\":1762905600000}")
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (change (test-id "store") "{\"id\":\"cached-corpus:9\",\"ok\":true,\"value\":{\"key\":\"cached-corpus\",\"value\":{\"entry\":{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"sentenceCount\":0,\"tokenCount\":0,\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"},\"citation\":null,\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"]},\"raw\":\"# sent_id = 1\\n1\\tλόγος\\tλόγος\\tn\\tn-s---mn-\\t_\\t0\\tSBJ\\t_\\tt_1|gloss=word\\n2\\t,\\t,\\tu\\tu--------\\t_\\t1\\tAuxX\\t_\\tt_2|gloss=,\\n3\\tἦν\\tεἰμί\\tv\\tv3siia---\\t_\\t0\\tPRED\\t_\\tt_3|gloss=was\\n\\n# sent_id = 2\\n1\\tθεός\\tθεός\\tn\\tn-s---mn-\\t_\\t0\\tSBJ\\t_\\tt_4|gloss=God\\n\\n\",\"units\":\"[{\\\"ref\\\":\\\"1.1\\\",\\\"label\\\":\\\"1:1\\\",\\\"literal\\\":\\\"word, was\\\",\\\"prose\\\":\\\"There was the word\\\",\\\"tokens\\\":[\\\"t_1\\\",\\\"t_2\\\",\\\"t_3\\\"]},{\\\"ref\\\":\\\"1.2\\\",\\\"label\\\":\\\"1:2\\\",\\\"literal\\\":\\\"God\\\",\\\"prose\\\":\\\"God\\\",\\\"tokens\\\":[\\\"t_4\\\"]}]\"}},\"now\":1762905600000}")
    (expect-text (role button :name "θεός") "θεός")
    (expect-current-location "/signals/#/demo/1.2")
    ; The download goes on (with the account config).
    (expect-pending-effects 3)
    (stub-http "corpus" :url "/preload/corpora/demo.conllu" :status 200 :body "# sent_id = 1\n1\tλόγος\tλόγος\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_1|gloss=word\n2\t,\t,\tu\tu--------\t_\t1\tAuxX\t_\tt_2|gloss=,\n3\tἦν\tεἰμί\tv\tv3siia---\t_\t0\tPRED\t_\tt_3|gloss=was\n\n# sent_id = 2\n1\tθεός\tθεός\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_4|gloss=God\n\n")
    (run-effect 2)
    (stub-http "units" :url "/preload/corpora/demo.units.json" :status 200 :body "[{\"ref\":\"1.1\",\"label\":\"1:1\",\"literal\":\"word, was\",\"prose\":\"There was the word\",\"tokens\":[\"t_1\",\"t_2\",\"t_3\"]},{\"ref\":\"1.2\",\"label\":\"1:2\",\"literal\":\"God\",\"prose\":\"God\",\"tokens\":[\"t_4\"]}]")
    (run-effect 3)
    (expect-text (role button :name "θεός") "θεός")
    (expect-current-location "/signals/#/demo/1.2")
  )
)
