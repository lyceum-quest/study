(test "Settings — the stored daily limit of new passages, changed and saved as the Elm app saves it"
  (setup
    (initial-location "/signals/#/settings"))
  (steps
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"theme:1\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"theme\"},{\"id\":\"reader-layers:2\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"reader-layers\"},{\"id\":\"positions:3\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"positions\"},{\"id\":\"settings:4\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"review-settings\"},{\"id\":\"scope:5\",\"operation\":\"get\",\"store\":\"metadata\",\"key\":\"today-scope\"},{\"id\":\"progress:6\",\"operation\":\"getAll\",\"store\":\"progress\"}]")
    (expect-value (label "New passages per day") "10")
    (change (test-id "store") "{\"id\":\"settings:4\",\"ok\":true,\"value\":{\"key\":\"review-settings\",\"value\":{\"newPerDay\":5}},\"now\":1762905600000}")
    (expect-value (label "New passages per day") "5")
    (select-option (label "New passages per day") "20")
    (expect-value (label "New passages per day") "20")
    (expect-attr (test-id "store") "data-request" "[{\"id\":\"save:7\",\"operation\":\"put\",\"store\":\"metadata\",\"value\":{\"key\":\"review-settings\",\"value\":{\"newPerDay\":20}}}]")
    ; Without an open work the page waits for one.
    (click (role button :name "Back to study →"))
    (expect-text (test-id "notice") "The local corpus is still loading.")
    (expect-current-location "/signals/#/settings")
  )
)
