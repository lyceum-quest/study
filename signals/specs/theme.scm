(test "Theme — the Elm app's theme, toggled and saved where it keeps it"
  (setup
    (initial-location "/signals/#/"))
  (steps
    (expect-attr (role button :name "Use light theme") "aria-pressed" "true")
    (change (test-id "store") "{\"id\":\"theme:1\",\"ok\":true,\"value\":{\"key\":\"theme\",\"value\":\"light\"},\"now\":1762905600000}")
    (expect-attr (role button :name "Use dark theme") "aria-pressed" "false")
    (click (role button :name "Use dark theme"))
    (expect-attr (role button :name "Use light theme") "aria-pressed" "true")
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"save:10\",\"operation\":\"put\",\"store\":\"metadata\",\"value\":{\"key\":\"theme\",\"value\":\"dark\"}}]")
  )
)
