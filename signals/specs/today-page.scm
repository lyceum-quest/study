(test "Today — with new passages left, today's page offers more"
  (setup
    (initial-location "/signals/#/today"))
  (steps
    (change (test-id "store") "{\"id\":\"progress:8\",\"ok\":true,\"value\":[],\"now\":1762905600000}")
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"name\":\"Test source\",\"url\":\"https://example.org\",\"commit\":\"abc\",\"license\":\"CC BY-SA 4.0\",\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (expect-text (role heading :name "More is ready") "More is ready")
    (expect-text (text "Today so far: 0 passages graded, 0 word reviews.") "Today so far: 0 passages graded, 0 word reviews.")
    (click (role button :name "Continue →"))
    (expect-current-location "/signals/#/demo/1.1?today=all")
  )
)
