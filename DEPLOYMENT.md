# Lyceum Study deployment

Live preview: <https://aristos.internal.blu.cx> (tailnet only), served from the
development machine by `aristos-preview.service` (`elm-live` on
`127.0.0.1:8092` in the repository root). It needs no deployment: source edits
recompile automatically and `kai run fetch-preload` installs the pinned data. The committed
`config.json` points the preview's "Sign in to sync" at the staging account API,
`https://lyceum.internal.blu.cx`; while that is unreachable Lyceum Study only notes it
on the Progress page.

## study.lyceum.quest

Lyceum Study is published as a static site on the Lyceum production host, whose
Caddy serves `ARISTOS_DEPLOY_DIR/current` (default `/var/www/aristos/current`)
at `study.lyceum.quest`. The vhost is declared in the Lyceum website's
`flake.nix` (`services.lyceum.staticSites`); deploying Lyceum Study never rebuilds
the host.

### Release

```sh
kai workflow release            # production: account API https://lyceum.quest
kai workflow release-staging    # staging: https://lyceum.internal.blu.cx
kai run bundle -- local         # no account API: no sign-in UI
```

The workflows check the tools, fetch the pinned `preload/` (see "Data" below),
check the browser boundary,
and run `scripts/build-release.roc <target>`, which writes a self-contained
site to `dist/aristos/<target>/<version>/` (version
`<UTC time>-<commit>[-dirty]`) and its name to `dist/aristos/<target>/latest`:

- `index.html`, rewritten to load the assets below;
- `assets/elm.<hash>.js` (`elm make --optimize`, not minified),
  `assets/browser-bridge.<hash>.js`, `assets/styles.<hash>.css`, named by the
  first 16 hex digits of their SHA-256;
- `config.json`: `{"accountApi": "<origin>"}`, or `{}` for `local`;
- `preload/`, copied as fetched.

Caching: files under `assets/` never change under a name, so Caddy serves them
`Cache-Control: public, max-age=31536000, immutable`. Everything else
(`index.html`, `config.json`, `preload/`) keeps a fixed name and is served
`no-cache`, so browsers revalidate it (ETag/Last-Modified) on every load.

### Deploy

Settings come from the environment or `.env` (see `.env.example`):
`ARISTOS_DEPLOY_HOST` (SSH destination, required; root, like the Lyceum data
deploy), `ARISTOS_DEPLOY_DIR` (default `/var/www/aristos`), and
`ARISTOS_SITE_URL` (checked after the swap; default
`https://study.lyceum.quest` for production and
`https://study.internal.blu.cx` for staging). Production also needs
`ARISTOS_DEPLOY_PRODUCTION=1`, read only from the environment.

```sh
ARISTOS_DEPLOY_PRODUCTION=1 kai run deploy-site -- production             # newest production bundle
ARISTOS_DEPLOY_PRODUCTION=1 kai run deploy-site -- production <version>   # a specific one
```

Staging is the Lyceum staging microVM on blu-tower, at
`https://study.internal.blu.cx` (tailnet only; signs in through
`https://lyceum.internal.blu.cx`):

```sh
kai workflow release-staging
ARISTOS_DEPLOY_HOST=root@lyceum-staging.tail42aee1.ts.net kai run deploy-site -- staging
```

`scripts/deploy-site.roc` checks the local release (complete, and its
`config.json` matches the target), uploads it with rsync to
`releases/.<version>.partial` (owned by the SSH user, world-readable), compares
it with the local copy by checksum, renames it to `releases/<version>`, and
points `current` at it by renaming a new symlink over the old one, so visitors
get either the whole old site or the whole new one. It then requires
`ARISTOS_SITE_URL` to serve the new `index.html` and `config.json`; if it does
not, `current` is put back. On success `previous` points at the release it
replaced and every other release is removed. Deploys take no lock: run one at a
time.

### Roll back

```sh
ARISTOS_DEPLOY_PRODUCTION=1 kai run rollback-site -- production
ARISTOS_DEPLOY_HOST=root@lyceum-staging.tail42aee1.ts.net kai run rollback-site -- staging
```

Swaps `current` and `previous` (so running it again rolls forward) and checks
the site. Releases already on the host are never overwritten, so to
return to the release you rolled back from, roll back again rather than
redeploying it.

## Data

Lyceum Study generates no data. `preload/` (corpora, passages, and the lemma index)
is an [Archeion](https://github.com/lyceum-quest/archeion) release pinned by
URL and SHA-256 in `preload.lock.json`; `kai run fetch-preload` replaces
`preload/` with it after checking the checksum. To update the data, release a
new preload from Archeion (`kai workflow preload-release`; see its
`PIPELINE.md`) and change the pin. `ARISTOS_PRELOAD_ARCHIVE=<path>` tries a
local archive (still checked against the pin) before it is published.
