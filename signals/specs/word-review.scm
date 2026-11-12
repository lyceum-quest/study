(test "Words — a word missed in a passage is reviewed there and rated"
  (setup
    ; Yesterday ἦν (εἰμί) in Demo 1:1 was marked wrong, which gives it a card.
    (initial-location "/signals/#/review/word/%CE%B5%E1%BC%B0%CE%BC%CE%AF"))
  (steps
    (change (test-id "store") "{\"id\":\"progress:6\",\"ok\":true,\"value\":[{\"id\":\"attempt:demo:1.1:1762819200000\",\"type\":\"attempt\",\"work\":\"demo\",\"passage\":\"1.1\",\"sentenceId\":\"1.1\",\"sentenceText\":\"λόγος , ἦν\",\"startedAt\":1762819100000,\"finishedAt\":1762819200000,\"items\":[{\"key\":\"w:1\",\"kind\":\"word\",\"form\":\"λόγος\",\"lemma\":\"λόγος\",\"guess\":\"word\",\"reference\":\"word\",\"revealedEarly\":false,\"mark\":true},{\"key\":\"w:3\",\"kind\":\"word\",\"form\":\"ἦν\",\"lemma\":\"εἰμί\",\"guess\":\"is\",\"reference\":\"was\",\"revealedEarly\":false,\"mark\":false},{\"key\":\"prose\",\"kind\":\"prose\",\"form\":\"\",\"lemma\":\"\",\"guess\":\"\",\"reference\":\"There was the word\",\"revealedEarly\":false,\"mark\":null}],\"rating\":\"good\"}],\"now\":1762905600000}")
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (expect-text (text "Word · Demo Work 1.1") "Word · Demo Work 1.1")
    (expect-text (text "εἰμί") "εἰμί")
    (fill (label "Meaning of ἦν") "be")
    (click (role button :name "Show answer"))
    (expect-text (text "Reviewed 1 time, missed 1. Your answer there: is") "Reviewed 1 time, missed 1. Your answer there: is")
    (click (role button :name "Good"))
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"word-rating:8\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"theme\"}]")
    (change (test-id "store") "{\"id\":\"word-rating:8\",\"ok\":true,\"value\":null,\"now\":1762905660000}")
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"save:9\",\"operation\":\"put\",\"store\":\"progress\",\"value\":{\"id\":\"wordreview:εἰμί:1762905660000\",\"type\":\"wordreview\",\"lemma\":\"εἰμί\",\"at\":1762905660000,\"rating\":\"good\",\"occurrence\":{\"work\":\"demo\",\"passage\":\"1.1\",\"position\":3,\"form\":\"ἦν\",\"gloss\":\"was\",\"text\":\"λόγος , ἦν\",\"guess\":\"be\"}}}]")
    (expect-current-location "/signals/#/word/%CE%B5%E1%BC%B0%CE%BC%CE%AF")
  )
)
