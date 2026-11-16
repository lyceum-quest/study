(test "Reader — a reader URL opens the work at its passage, with glosses, morphology and translations"
  (setup
    ; Three passages; empty storage, so every layer is on (see studying-a-passage.scm for the storage protocol).
    (initial-location "/signals/#/demo/read/1.2"))
  (steps
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"theme:1\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"theme\"},{\"id\":\"reader-layers:2\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"reader-layers\"},{\"id\":\"positions:3\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"positions\"},{\"id\":\"settings:4\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"review-settings\"},{\"id\":\"scope:5\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"today-scope\"},{\"id\":\"reading-goals:6\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"reading-goals\"},{\"id\":\"known-words:7\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"known-words\"},{\"id\":\"progress:8\",\"operation\":\"getAll\",\"store\":\"progress\"},{\"id\":\"cached-corpus:9\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"cached-corpus\"}]")
    (change (test-id "store") "{\"id\":\"progress:8\",\"ok\":true,\"value\":[],\"now\":1762905600000}")
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\",\"1.3\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (stub-http "corpus" :url "/preload/corpora/demo.conllu" :status 200 :body "# sent_id = 1\n1\tλόγος\tλόγος\tn\tn-s---mn-\tCase=n|Number=s|Gender=m\t0\tSBJ\t_\tt_1|gloss=word\n2\t,\t,\tu\tu--------\t_\t1\tAuxX\t_\tt_2|gloss=,\n3\tἦν\tεἰμί\tv\tv3siia---\t_\t0\tPRED\t_\tt_3|gloss=was\n\n# sent_id = 2\n1\tθεός\tθεός\tn\tn-s---mn-\t_\t0\tSBJ\t_\tt_4|gloss=God\n\n# sent_id = 3\n1\tἀρχῇ\tἀρχή\tn\tn-s---fd-\t_\t0\tADV\t_\tt_5|gloss=beginning\n\n")
    (run-effect 2)
    (stub-http "units" :url "/preload/corpora/demo.units.json" :status 200 :body "[{\"ref\":\"1.1\",\"label\":\"1:1\",\"literal\":\"word, was\",\"prose\":\"There was the word\",\"tokens\":[\"t_1\",\"t_2\",\"t_3\"]},{\"ref\":\"1.2\",\"label\":\"1:2\",\"literal\":\"God\",\"prose\":\"It was God\",\"tokens\":[\"t_4\"]},{\"ref\":\"1.3\",\"label\":\"1:3\",\"literal\":\"in beginning\",\"prose\":\"In the beginning\",\"tokens\":[\"t_5\"]}]")
    (run-effect 3)
    (expect-current-location "/signals/#/demo/read/1.2")
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"save:10\",\"operation\":\"put\",\"store\":\"metadata\",\"value\":{\"key\":\"cached-corpus\",\"value\":{\"entry\":{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"sentenceCount\":0,\"tokenCount\":0,\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"},\"citation\":null,\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\",\"1.3\"]},\"raw\":\"# sent_id = 1\\n1\\tλόγος\\tλόγος\\tn\\tn-s---mn-\\tCase=n|Number=s|Gender=m\\t0\\tSBJ\\t_\\tt_1|gloss=word\\n2\\t,\\t,\\tu\\tu--------\\t_\\t1\\tAuxX\\t_\\tt_2|gloss=,\\n3\\tἦν\\tεἰμί\\tv\\tv3siia---\\t_\\t0\\tPRED\\t_\\tt_3|gloss=was\\n\\n# sent_id = 2\\n1\\tθεός\\tθεός\\tn\\tn-s---mn-\\t_\\t0\\tSBJ\\t_\\tt_4|gloss=God\\n\\n# sent_id = 3\\n1\\tἀρχῇ\\tἀρχή\\tn\\tn-s---fd-\\t_\\t0\\tADV\\t_\\tt_5|gloss=beginning\\n\\n\",\"units\":\"[{\\\"ref\\\":\\\"1.1\\\",\\\"label\\\":\\\"1:1\\\",\\\"literal\\\":\\\"word, was\\\",\\\"prose\\\":\\\"There was the word\\\",\\\"tokens\\\":[\\\"t_1\\\",\\\"t_2\\\",\\\"t_3\\\"]},{\\\"ref\\\":\\\"1.2\\\",\\\"label\\\":\\\"1:2\\\",\\\"literal\\\":\\\"God\\\",\\\"prose\\\":\\\"It was God\\\",\\\"tokens\\\":[\\\"t_4\\\"]},{\\\"ref\\\":\\\"1.3\\\",\\\"label\\\":\\\"1:3\\\",\\\"literal\\\":\\\"in beginning\\\",\\\"prose\\\":\\\"In the beginning\\\",\\\"tokens\\\":[\\\"t_5\\\"]}]\"}}},{\"id\":\"draft:11\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"draft:demo:1.2\"}]")
    (change (test-id "store") "{\"id\":\"draft:11\",\"ok\":true,\"value\":null,\"now\":1762905600000}")
    (expect-document-title "Demo Work 1:2 · Lyceum Study")
    ; The reader has its own bar instead of the app's header.
    (expect-absent (label "Lyceum Study library"))
    (expect-text (text "1:2 · 2 / 3") "1:2 · 2 / 3")
    (expect-attr (test-id "passage-2") "class" "reader-sentence is-current")
    (expect-attr (test-id "passage-1") "class" "reader-sentence")
    ; Every passage of the work, each word with its punctuation, gloss and morphology.
    (expect-text (text "λόγος,") "λόγος,")
    (expect-text (text "nom sg m") "nom sg m")
    (expect-text (text "beginning") "beginning")
    (expect-text (text "There was the word") "There was the word")
    (expect-text (text "In the beginning") "In the beginning")
    (expect-absent (text "word, was"))
    (expect-attr (role button :name "Glosses") "aria-pressed" "true")
    (expect-attr (role button :name "Morphology") "aria-pressed" "true")
    (expect-attr (role button :name "Translation") "aria-pressed" "true")
  )
)
