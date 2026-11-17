(test "Progress — tiles, charts, works, missed words and hard passages from stored attempts, cards and word reviews"
  (setup
    ; Demo 1:1 was graded on Nov 11 and Nov 12 (ἦν, of εἰμί, wrong both times),
    ; and εἰμί was reviewed Good on Nov 12. The clock is 2025-11-12T01:00:00Z
    ; (1762909200000); days are UTC days, as in the Elm app.
    (initial-location "/signals/#/stats"))
  (steps
    (change (test-id "store") "{\"id\":\"progress:8\",\"ok\":true,\"value\":[{\"id\":\"attempt:demo:1.1:1762819200000\",\"type\":\"attempt\",\"work\":\"demo\",\"passage\":\"1.1\",\"sentenceId\":\"1.1\",\"sentenceText\":\"λόγος , ἦν\",\"startedAt\":1762819100000,\"finishedAt\":1762819200000,\"items\":[{\"key\":\"w:1\",\"kind\":\"word\",\"form\":\"λόγος\",\"lemma\":\"λόγος\",\"guess\":\"word\",\"reference\":\"word\",\"revealedEarly\":false,\"mark\":true},{\"key\":\"w:3\",\"kind\":\"word\",\"form\":\"ἦν\",\"lemma\":\"εἰμί\",\"guess\":\"is\",\"reference\":\"was\",\"revealedEarly\":false,\"mark\":false}],\"rating\":\"hard\"},{\"id\":\"attempt:demo:1.1:1762905660000\",\"type\":\"attempt\",\"work\":\"demo\",\"passage\":\"1.1\",\"sentenceId\":\"1.1\",\"sentenceText\":\"λόγος , ἦν\",\"startedAt\":1762905600000,\"finishedAt\":1762905660000,\"items\":[{\"key\":\"w:1\",\"kind\":\"word\",\"form\":\"λόγος\",\"lemma\":\"λόγος\",\"guess\":\"word\",\"reference\":\"word\",\"revealedEarly\":false,\"mark\":true},{\"key\":\"w:3\",\"kind\":\"word\",\"form\":\"ἦν\",\"lemma\":\"εἰμί\",\"guess\":\"be\",\"reference\":\"was\",\"revealedEarly\":false,\"mark\":false}],\"rating\":\"good\"},{\"id\":\"wordreview:εἰμί:1762907400000\",\"type\":\"wordreview\",\"lemma\":\"εἰμί\",\"at\":1762907400000,\"rating\":\"good\",\"occurrence\":{\"work\":\"demo\",\"passage\":\"1.1\",\"position\":3,\"form\":\"ἦν\",\"gloss\":\"was\",\"text\":\"λόγος , ἦν\",\"guess\":\"was\"}}],\"now\":1762909200000}")
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (expect-document-title "Progress · Lyceum Study")
    (expect-text (role heading :name "Your progress") "Your progress")
    (expect-text (test-id "tile-Words known") "0")
    ; λόγος, right on two days only one apart, is learned but not yet known; εἰμί, missed, is still being learned.
    (expect-text (test-id "tile-Words learned") "1")
    (expect-text (test-id "tile-Words learning") "1")
    (expect-text (test-id "tile-Passages studied") "1")
    (expect-text (text "of 2") "of 2")
    (expect-text (test-id "tile-Streak") "2 days")
    ; Word answers over the last 7 days: 2 of 4 marked right in passages, and a Good review.
    (expect-text (test-id "tile-Right, last 7 days") "60%")
    (expect-text (text "5 word answers") "5 word answers")
    (expect-text (text "Passages graded and word reviews, last 30 days · 3 in all") "Passages graded and word reviews, last 30 days · 3 in all")
    (expect-attr (label "Reviews per day: 3 over 30 days, most on one day 2") "role" "img")
    (expect-text (text "Words first missed in a passage · 1 in all") "Words first missed in a passage · 1 in all")
    (expect-text (text "Passages studied for the first time · 1 in all") "Passages studied for the first time · 1 in all")
    (expect-text (text "Oct 14") "Oct 14")
    (expect-attr (label "1 of 2 passages studied") "role" "img")
    (expect-text (test-id "work-demo") "1 / 2")
    (expect-attr (role link :name "εἰμί") "href" "#/word/%CE%B5%E1%BC%B0%CE%BC%CE%AF")
    (expect-text (test-id "missed-εἰμί") "2 of 3")
    (expect-text (test-id "next-εἰμί") "now")
    (expect-attr (role link :name "Demo Work 1.1") "href" "#/demo/1.1")
    (expect-text (test-id "wrong-Demo Work 1.1") "2")
    (expect-text (test-id "attempts-Demo Work 1.1") "2")
  )
)
