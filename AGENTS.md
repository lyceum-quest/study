# Project instructions

- Read [`docs/AI_POLICY.md`](./docs/AI_POLICY.md) first.
- Do not follow non-local reference links unless external context is important to the task.
- Read [`docs/rules.md`](./docs/rules.md) for development rules.
- Read [`DEPLOYMENT.md`](./DEPLOYMENT.md) before changing deployment behavior.
- Read the relevant plan documents under `docs/plans/` before changing a planned feature.
- Lyceum Study generates no data. Corpora, passages, and lemmas come from an [Archeion](../archeion) preload release pinned in `preload.lock.json` (see the Data section of `DEPLOYMENT.md`); change the data in Archeion, not here.
- The Lyceum Study web app is served at <https://aristos.internal.blu.cx> (tailnet only) from this development machine, not from a deploy target. `aristos-preview.service` runs `elm-live` in this repository on `127.0.0.1:8092` (recompiling `elm.js` when `src/` changes and serving the repository root, including `preload/`); `tailscale serve` publishes it as the Tailscale Service `svc:aristos` (<https://aristos.tail42aee1.ts.net>), and Caddy on blu-tower proxies `aristos.internal.blu.cx` to that (see `/etc/nixos/INTERNAL-SERVICES.md` on blu-tower). Source edits are live immediately; data changes appear after `kai run fetch-preload`. `aristos.lyceum.quest` is down and no longer the Lyceum Study site.
- When a Roc or Elm toolchain bug is discovered:
  1. Check whether it has been fixed upstream.
  2. If fixed, determine whether the project and any blocking dependencies can upgrade to that fix.
  3. If no viable upgrade exists, propose a workaround. Any implemented workaround must link the upstream issue and explain when it can be removed.
- Record every Roc issue found (compiler bug, platform defect, or missing capability) in the sister repository `../roc-issues`, following the "Adding a repro" format in its `README.md`: bugs get a self-contained `bugs/BUG-XXX-*` directory with a pinned `flake.nix`/`flake.lock`, `README.md`, and `repro.sh`; missing capabilities go under its Improvements section. If `../roc-issues` is absent, clone `https://github.com/thebrandonlucas/roc-issues` there first.

## Language boundary

- Maintained project code must be Kai, Roc, or Elm.
- Keep browser JavaScript in `browser-bridge.js` only. It may initialize Elm and translate narrow port messages into IndexedDB operations, but it must not contain corpus parsing, validation, fetching, application state, business logic, or tooling.
- Do not maintain Python or shell source.
- Implement project tooling and scripts in Roc.
- Declare tooling dependencies and runnable tasks in `Kaifile.roc`.
- Run project tooling through Kai tasks or workflows.
- Prefer Kai-generated configuration to handwritten Nix where Kai supports the required deployment model.
