(test "Review — without a work in the URL, the preload's works are listed"
  (setup
    (initial-location "/signals/"))
  (steps
    (stub-http "manifest" :url "/preload/corpora.json" :status 200 :body "{\"version\":1,\"corpora\":[{\"id\":\"demo\",\"title\":\"Demo Work\",\"path\":\"corpora/demo.conllu\",\"unitsPath\":\"corpora/demo.units.json\",\"passages\":[\"1.1\",\"1.2\"],\"source\":{\"edition\":\"Test edition\"}}]}")
    (run-effect 1)
    (expect-attr (role link :name "Demo Work") "href" "#/demo")
    (navigate "/signals/#/demo")
    (expect-pending-effects 2)
    (expect-text (text "Loading the passages and your progress…") "Loading the passages and your progress…")
  )
)
