(test "Reading goals — each work's coverage in the library, the easiest first, and a work's goal and plan"
  (setup
    ; λόγος was glossed right 30 days ago and yesterday, so it is known. Demo
    ; is 1 λόγος and 3 εἰμί (25% known), Other 3 λόγος and 1 θεός (75%).
    ; 1762905600000 is 2025-11-12T00:00:00Z.
    (initial-location "/signals/"))
  (steps
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"}},{\"id\":\"other\",\"title\":\"Other Work\",\"path\":\"corpora/other.conllu\",\"unitsPath\":\"corpora/other.units.json\",\"passages\":[\"1\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Other edition\"}}]}")
    (run-effect 1)
    (stub-http "lemmas" :url "/preload/lemmas.json" :status 200 :body "{\"lemmas\":{\"λόγος\":[{\"work\":\"demo\",\"ref\":\"1.1\",\"position\":1,\"form\":\"λόγος\",\"gloss\":\"word\"},{\"work\":\"other\",\"ref\":\"1\",\"position\":2,\"form\":\"λόγος\",\"gloss\":\"word\"},{\"work\":\"other\",\"ref\":\"1\",\"position\":3,\"form\":\"λόγου\",\"gloss\":\"word\"},{\"work\":\"other\",\"ref\":\"1\",\"position\":4,\"form\":\"λόγῳ\",\"gloss\":\"word\"}],\"εἰμί\":[{\"work\":\"demo\",\"ref\":\"1.1\",\"position\":3,\"form\":\"ἦν\",\"gloss\":\"was\"},{\"work\":\"demo\",\"ref\":\"1.2\",\"position\":2,\"form\":\"ἐστιν\",\"gloss\":\"is\"},{\"work\":\"demo\",\"ref\":\"1.2\",\"position\":4,\"form\":\"ἦν\",\"gloss\":\"was\"}],\"θεός\":[{\"work\":\"other\",\"ref\":\"1\",\"position\":5,\"form\":\"θεὸς\",\"gloss\":\"God\"}]},\"passages\":{\"demo\":{\"1.1\":\"λόγος, ἦν\"},\"other\":{\"1\":\"λόγος\"}}}")
    (run-effect 2)
    (change (test-id "store") "{\"id\":\"progress:8\",\"ok\":true,\"value\":[{\"id\":\"attempt:demo:1.1:1760313600000\",\"type\":\"attempt\",\"work\":\"demo\",\"passage\":\"1.1\",\"sentenceId\":\"1.1\",\"sentenceText\":\"λόγος , ἦν\",\"startedAt\":1760313500000,\"finishedAt\":1760313600000,\"items\":[{\"key\":\"w:1\",\"kind\":\"word\",\"form\":\"λόγος\",\"lemma\":\"λόγος\",\"guess\":\"word\",\"reference\":\"word\",\"revealedEarly\":false,\"mark\":true}],\"rating\":\"good\"},{\"id\":\"attempt:demo:1.1:1762819200000\",\"type\":\"attempt\",\"work\":\"demo\",\"passage\":\"1.1\",\"sentenceId\":\"1.1\",\"sentenceText\":\"λόγος , ἦν\",\"startedAt\":1762819100000,\"finishedAt\":1762819200000,\"items\":[{\"key\":\"w:1\",\"kind\":\"word\",\"form\":\"λόγος\",\"lemma\":\"λόγος\",\"guess\":\"word\",\"reference\":\"word\",\"revealedEarly\":false,\"mark\":true}],\"rating\":\"good\"}],\"now\":1762905600000}")

    ; Each row says how much of the work the learner can read, and what the goal takes.
    (expect-text (test-id "library:demo:reading") "25% of words known · 1 word to learn for 95%")
    (expect-text (test-id "library:other:reading") "75% of words known · 1 word to learn for 95%")
    (expect-text (test-id "library-1") "Demo Work")
    (select-option (label "Sort the library") "easiest")
    (expect-text (test-id "library-1") "Other Work")
    (expect-text (test-id "library-2") "Demo Work")

    ; A work's goal page.
    (click (test-id "library:demo:goal"))
    (expect-current-location "/signals/#/demo/goal")
    (expect-text (role heading :name "Demo Work") "Demo Work")
    (expect-text (test-id "goal-percent") "25%")
    (expect-text (test-id "goal-needed") "Learn its 1 most frequent word you don't know yet to reach 95%.")
    (expect-text (test-id "goal-finish") "You'd know 95% of its words in about 3 weeks, around 4 Dec 2025.")
    (expect-text (role link :name "εἰμί") "εἰμί")

    ; Planning by words a day, then by a date; both are saved.
    (fill (label "New words a day") "20")
    (expect-text (test-id "goal-finish") "You'd know 95% of its words in about 3 weeks, around 4 Dec 2025.")
    (expect-text (role button :name "Use my pace") "Use my pace")
    (change (label "Target date") "2025-12-31")
    (expect-text (test-id "goal-by-date") "Learn about 1 new word a day to get there by 31 Dec 2025.")
    (select-option (label "Coverage goal") "98")
    (expect-text (test-id "goal-needed") "Learn its 1 most frequent word you don't know yet to reach 98%.")
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"save:12\",\"operation\":\"put\",\"store\":\"metadata\",\"value\":{\"key\":\"reading-goals\",\"value\":{\"coverage\":98,\"perDay\":20,\"targets\":{\"demo\":\"2025-12-31\"}}}}]")

    ; The Today panel keeps the dated goal in view.
    (click (role button :name "Home"))
    (expect-text (test-id "today-goal-demo") "Goal: Demo Work, 98% by 31 Dec 2025: about 1 new word a day, 1 to go.")
  )
)
