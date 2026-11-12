# Development rules

## Workflow

- Run project tooling through Kai tasks or workflows. Declare new tooling dependencies and runnable tasks in `Kaifile.roc`.
- Do not commit unless explicitly instructed. Never push, create an issue, or open a pull request.
- If asked why a problem occurs, explain it so the developer can fix it. Do not edit files unless asked.
- Use a subagent for self-contained work when one is available, preserving the main context for design discussions.
- When comments are added to a file for you to address, answer the questions without removing or rewriting those comments unless asked.

## Implementation

- Favor the smallest change that implements the requested behavior and respects the project boundaries in [`AGENTS.md`](../AGENTS.md).
- Keep application state, corpus parsing, validation, fetching, and business logic in Roc (the app in `signals/`, pure logic in packages under `packages/`). Keep project tooling in Roc. Restrict `browser-bridge.js` to mounting the app (with its credentials fetch) and narrow IndexedDB translation, and use the roc-signals runtime as released.
- Keep pure data transformations separate from side effects.
- Do not edit generated output in `.kai/`, `app.wasm`, `runtime.mjs`, `dist/`, or `preload/`; regenerate it through the corresponding Kai task or workflow.
- Use Roc's `\\` syntax for static multiline strings. Use `Str.join_with` only when interpolation or composition is required.
- Do not add tests unless explicitly asked to add a specific set or complete an already-started set.
- Do not create or modify documentation unless explicitly requested.
- Check every UI change in both light and dark mode (look at it rendered in each) before calling it done.

## Version control

- Use conventional commit subjects in the form `type: description`.
- Do not add a fix commit for defects introduced on the same feature branch; amend or reorganize the feature work instead.
- Keep commits independently useful and safe to merge. Prefer roughly +50/-50 lines per commit and avoid exceeding +500/-500 where possible.
- Preserve merge commits when rebasing or reorganizing history.

## Issues and pull requests

- Never create an issue or pull request on behalf of the user.
- If asked to prepare one, provide text for human review instead of submitting it.
