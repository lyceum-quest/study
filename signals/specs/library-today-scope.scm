(test "Library — a work opened from the Elm app's Today scope is being worked on"
  (setup
    (initial-location "/signals/#/"))
  (steps
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (change (test-id "store") "{\"id\":\"progress:1\",\"ok\":true,\"value\":[],\"now\":1762905600000}")
    (expect-absent (test-id "working-1"))
    (expect-text (test-id "library:demo") "2 passages · not started")
    (change (test-id "store") "{\"id\":\"scope:5\",\"ok\":true,\"value\":{\"key\":\"today-scope\",\"value\":\"demo\"},\"now\":1762905600000}")
    (expect-text (test-id "working-1") "Demo Work")
  )
)
