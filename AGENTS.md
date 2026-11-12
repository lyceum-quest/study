# Project instructions

- Read [`docs/AI_POLICY.md`](./docs/AI_POLICY.md) first.
- Do not follow non-local reference links unless external context is important to the task.
- Read [`docs/rules.md`](./docs/rules.md) for development rules.
- Read [`DEPLOYMENT.md`](./DEPLOYMENT.md) before changing deployment behavior.
- Read the relevant plan documents under `docs/plans/` before changing a planned feature.
- Lyceum Study generates no data. Corpora, passages, and lemmas come from an [Archeion](../archeion) preload release pinned in `preload.lock.json` (see the Data section of `DEPLOYMENT.md`); change the data in Archeion, not here.
- The Lyceum Study web app is a static page: `index.html` at the repository root loads `browser-bridge.js`, which mounts the app module `app.wasm` with the roc-signals runtime `runtime.mjs`. `kai run build-signals` generates both at the root (about ten minutes; never run two Roc builds at once), so any static server on the repository root serves the app with its `preload/`. The working tree is previewed at <https://study-signals.internal.blu.cx> (tailnet only), a copy refreshed from blu-tower; build first, then say there is something new to look at. Staging is <https://study.internal.blu.cx>, deployed only on the owner's go (see `DEPLOYMENT.md`). Data changes appear after `kai run fetch-preload`. `aristos.internal.blu.cx` and `aristos.lyceum.quest` are retired.
- When a Roc toolchain bug is discovered:
  1. Check whether it has been fixed upstream.
  2. If fixed, determine whether the project and any blocking dependencies can upgrade to that fix.
  3. If no viable upgrade exists, propose a workaround. Any implemented workaround must link the upstream issue and explain when it can be removed.
- Record every Roc issue found (compiler bug, platform defect, or missing capability) in the sister repository `../roc-issues`, following the "Adding a repro" format in its `README.md`: bugs get a self-contained `bugs/BUG-XXX-*` directory with a pinned `flake.nix`/`flake.lock`, `README.md`, and `repro.sh`; missing capabilities go under its Improvements section. If `../roc-issues` is absent, clone `https://github.com/thebrandonlucas/roc-issues` there first.

## Language boundary

- Maintained project code must be Kai or Roc.
- Lyceum Study is a Roc app on the [roc-signals](https://github.com/lukewilliamboswell/roc-signals) platform (`signals/`, ported from an Elm app that git history keeps). Put pure Roc logic in packages under `packages/`.
- Keep browser JavaScript in `browser-bridge.js` and the roc-signals runtime only. Use the runtime as released and never edit it. `browser-bridge.js` may mount the app, hand the runtime a `fetch` that adds credentials (so the account API on another origin gets its session cookie; roc-issues RS-008), and translate narrow storage messages from the app's `<lyceum-store>` element into IndexedDB operations, but it must not contain corpus parsing, validation, any other fetching, application state, business logic, or tooling. `kai run check-browser-boundary` enforces this.
- Do not maintain Python or shell source.
- Implement project tooling and scripts in Roc.
- Declare tooling dependencies and runnable tasks in `Kaifile.roc`.
- Run project tooling through Kai tasks or workflows.
- Prefer Kai-generated configuration to handwritten Nix where Kai supports the required deployment model.
