# Yandex Metrica, as a desktop app

[Yandex Metrica](https://metrica.yandex.com) packaged with [Pake](https://github.com/tw93/Pake)
into a native window — the system webview, not a bundled browser, so the whole
thing is a few megabytes rather than a few hundred.

The window opens straight on the site list, weekly period, grouped by hour,
sorted by visits.

## Install

```bash
curl -fsSL https://get.rec.tools/metrica | bash
```

Linux and macOS. On Linux the script installs the `.deb` where `dpkg` exists and
falls back to the AppImage in `~/.local` where it does not. On Windows, download
the `.msi` from [the latest release](https://github.com/rdcstarr/pake-metrica/releases/latest).

The command is `pake-metrica` — Pake prefixes the Linux binary, and the AppImage
path is named to match so it is the same either way. The menu entry the `.deb`
writes reads lowercase, because a Debian package name has to be lowercase and the
entry takes its name from it.

## Signing in

Use your **Yandex ID** — the email or phone form on `passport.yandex.com`.

The **Google and X buttons do not work**: those providers refuse to authenticate
inside an embedded webview, and the redirect has nowhere to return to. This is a
property of the providers, not something the app can fix.

`passport.yandex.com` is listed in `safeDomain` precisely so the login stays
inside the window. Without it the app would hand the sign-in to the system
browser and never get the session back — see `scripts/check-config.mjs`, which
fails the build if that ever regresses.

## What builds, and where

| Platform | Format | Architecture |
| --- | --- | --- |
| Linux | `.deb`, `.AppImage` | x86_64 |
| macOS | `.dmg` | Apple Silicon |
| Windows | `.msi` | x64 |

Pushing a `v*` tag builds all three in GitHub Actions and publishes them to a
release. Every asset is renamed to a name that never changes, so
`releases/latest/download/metrica-linux-amd64.deb` is a permanent URL — that is
what lets `install.sh` skip `api.github.com` entirely, and with it the 60
requests per hour that unauthenticated callers get.

`workflow_dispatch` runs the same build without publishing, for when the workflow
itself is what changed.

## The app definition

Everything the app is lives in [`app.json`](app.json) — URL, window size, which
hosts stay inside the window. It follows [Pake's schema](https://raw.githubusercontent.com/tw93/Pake/main/schema/pake.schema.json),
so an editor with schema support will complete and validate it.

`safeDomain` **replaces** the set of URLs that stay in the app rather than adding
to it, which is why the app's own host is listed there alongside the login hosts.

## What this is not

Nothing here is signed or notarised: macOS needs the quarantine flag cleared
(the installer does it) and may still want a right-click → Open the first time,
and Windows shows a SmartScreen warning. There is no auto-update — reinstalling
with the same command is the update.
