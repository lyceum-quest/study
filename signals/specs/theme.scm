(test "Review — the theme is the Elm app's, and saved where it keeps it"
  (setup
    (initial-location "/signals/#/demo"))
  (steps
    (change (test-id "store") "{\"id\":\"theme:3\",\"ok\":true,\"value\":{\"key\":\"theme\",\"value\":\"light\"},\"now\":1762905600000}")
    (expect-attr (role button :name "Use dark theme") "aria-pressed" "false")
    (click (role button :name "Use dark theme"))
    (expect-attr (role button :name "Use light theme") "aria-pressed" "true")
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"save:4\",\"operation\":\"put\",\"store\":\"metadata\",\"value\":{\"key\":\"theme\",\"value\":\"dark\"}}]")
  )
)
