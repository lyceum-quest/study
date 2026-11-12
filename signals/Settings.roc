import study.Study
import Model
import Store

## The study tools page's transitions, ported from the `ShowWorkspace`,
## `ClearSavedData`, `CancelClearSavedData` and `ConfirmClearSavedData`
## branches of `updateModel` in `src/Main.elm`. Choosing a preset or a tool is
## in Workspace, the daily limit in Nav.
Settings := [].{

	## Back to the open passage, once its work has loaded.
	show_workspace : Model.Model -> Model.Model
	show_workspace = |model|
		if model.corpus_ready {
			{ ..model, screen: WorkspaceScreen, notice: "" }
		} else {
			{ ..model, notice: "The local corpus is still loading." }
		}

	ask_clear : Model.Model -> Model.Model
	ask_clear = |model| { ..model, confirm_clear: Bool.True }

	cancel_clear : Model.Model -> Model.Model
	cancel_clear = |model| { ..model, confirm_clear: Bool.False }

	## Deletes the progress and metadata stores and forgets what they held.
	## Account sync is not ported yet: the Elm app also resets the sync state
	## here and, when signed in with sync, says the account's progress comes back.
	confirm_clear : Model.Model -> Model.Model
	confirm_clear = |model|
		Model.send(
			{
				..model,
				attempts: [],
				entries: Dict.empty(),
				word_reviews: [],
				word_cards: Dict.empty(),
				study: Study.empty_draft,
				positions: Dict.empty(),
				confirm_clear: Bool.False,
				notice: "Saved study data cleared from this device.",
			},
			[
				("clear", |id| Store.clear(id, "progress")),
				("clear", |id| Store.clear(id, "metadata")),
			],
		)
}
