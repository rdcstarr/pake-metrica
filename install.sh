#!/usr/bin/env bash
#
# Yandex Metrica desktop app — installer for Linux and macOS.
#   curl -fsSL https://get.rec.tools/metrica | bash
#
# Downloads from the latest GitHub release through a permanent /latest/download
# URL, so this script never calls api.github.com and never meets its 60 requests
# per hour limit for unauthenticated callers.
#
# Windows is not covered here: fetch the .msi from the releases page instead.

set -euo pipefail

REPO="rdcstarr/pake-metrica"
BASE="https://github.com/${REPO}/releases/latest/download"
RELEASES="https://github.com/${REPO}/releases/latest"

say()  { printf '\033[36m==\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mxx\033[0m %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required."

# The script is delivered on stdin, so nothing here may prompt.
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

os="$(uname -s)"
arch="$(uname -m)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# GitHub answers /releases/latest with a redirect: to /releases/tag/<version>
# when a release exists, and to the bare /releases list when none does. That
# yields the published version without api.github.com and its 60 requests per
# hour — printed before anything is downloaded, because "it installed but I
# still have the old version" is otherwise invisible until the app is open.
published_version() {
  local latest
  latest="$(curl -sI --proto '=https' -o /dev/null -w '%{redirect_url}' "$RELEASES" || true)"
  case "$latest" in
    */releases/tag/*) printf '%s' "${latest##*/}" ;;
    *) printf '' ;;
  esac
}

diagnose() {
  local asset="$1" latest
  latest="$(curl -sI --proto '=https' -o /dev/null -w '%{redirect_url}' "$RELEASES" || true)"

  case "$latest" in
    */releases/tag/*)
      die "Release ${latest##*/} has no asset named ${asset} — nothing is published for ${os} ${arch}. See ${RELEASES}"
      ;;
    *)
      die "No release has been published yet. If a build is still running it will appear at ${RELEASES} when it finishes: https://github.com/${REPO}/actions"
      ;;
  esac
}

fetch() {
  curl -fL --proto '=https' --tlsv1.2 --progress-bar -o "$2" "$1" || diagnose "$(basename "$1")"
}

install_deb() {
  say "Downloading the .deb package"
  fetch "${BASE}/metrica-linux-amd64.deb" "${TMP}/metrica.deb"
  say "Installing (dpkg may ask for your password)"
  $SUDO dpkg -i "${TMP}/metrica.deb" || $SUDO apt-get -f install -y
  say "Installed. Launch it from your applications menu, or run: pake-metrica"
}

install_appimage() {
  local bin="${HOME}/.local/bin/pake-metrica"
  local desktop="${HOME}/.local/share/applications/pake-metrica.desktop"
  local icon="${HOME}/.local/share/icons/hicolor/512x512/apps/pake-metrica.png"

  say "No dpkg here — installing the AppImage into ~/.local"
  fetch "${BASE}/metrica-linux-amd64.AppImage" "${TMP}/metrica.AppImage"
  install -Dm755 "${TMP}/metrica.AppImage" "$bin"

  mkdir -p "$(dirname "$icon")"
  curl -fsSL --proto '=https' -o "$icon" \
    "https://raw.githubusercontent.com/${REPO}/main/icons/metrica.png" || warn "Could not fetch the icon."

  mkdir -p "$(dirname "$desktop")"
  cat > "$desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Metrica
Comment=Yandex Metrica in a standalone window
Exec=${bin}
Icon=pake-metrica
Categories=Network;Office;
Terminal=false
DESKTOP

  command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$(dirname "$desktop")" >/dev/null 2>&1 || true

  case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) warn "~/.local/bin is not on your PATH — the menu entry works, the 'pake-metrica' command will not." ;;
  esac
  say "Installed to ${bin}"
}

install_macos() {
  say "Downloading the .dmg"
  fetch "${BASE}/metrica-macos-arm64.dmg" "${TMP}/metrica.dmg"

  local mount app name
  mount="${TMP}/mnt"

  # Naming the mount point removes the need to parse hdiutil's output for it,
  # which is both fragile and the format Apple has started deprecating. Its
  # stderr is kept rather than shown: on a healthy run it is only the
  # deprecation notice, and on a failure it is the whole explanation.
  if ! hdiutil attach -nobrowse -readonly -mountpoint "$mount" "${TMP}/metrica.dmg" >/dev/null 2>"${TMP}/attach.err"; then
    if [ -s "${TMP}/attach.err" ]; then cat "${TMP}/attach.err" >&2; fi
    die "Could not mount the disk image."
  fi
  [ -d "$mount" ] || die "Disk image mounted nowhere."

  app="$(find "$mount" -maxdepth 1 -name '*.app' -print -quit)"
  if [ -z "$app" ]; then hdiutil detach "$mount" -quiet >/dev/null 2>&1 || true; die "No .app inside the disk image."; fi
  name="$(basename "$app")"

  say "Copying ${name} to /Applications"
  rm -rf "/Applications/${name}" 2>/dev/null || $SUDO rm -rf "/Applications/${name}"
  cp -R "$app" /Applications/ 2>/dev/null || $SUDO cp -R "$app" /Applications/
  hdiutil detach "$mount" -quiet >/dev/null 2>&1 || true

  # The binary is not signed or notarised, so Gatekeeper would refuse it outright.
  xattr -dr com.apple.quarantine "/Applications/${name}" 2>/dev/null \
    || $SUDO xattr -dr com.apple.quarantine "/Applications/${name}" 2>/dev/null \
    || warn "Could not clear the quarantine flag — open the app with right-click → Open the first time."

  say "Installed. Open it from /Applications."
}

VERSION="$(published_version)"
if [ -z "$VERSION" ]; then
  die "No release has been published yet. If a build is still running it will appear at ${RELEASES} when it finishes: https://github.com/${REPO}/actions"
fi
say "Installing ${VERSION} for ${os} ${arch}"

case "$os" in
  Linux)
    [ "$arch" = "x86_64" ] || die "Only x86_64 Linux builds are published; this machine is ${arch}. See ${RELEASES}"
    if command -v dpkg >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
      install_deb
    else
      install_appimage
    fi
    ;;
  Darwin)
    case "$arch" in
      arm64) install_macos ;;
      *) die "Only Apple Silicon builds are published; this Mac is ${arch}. See ${RELEASES}" ;;
    esac
    ;;
  *)
    die "Unsupported system: ${os}. On Windows, download the .msi from ${RELEASES}"
    ;;
esac

echo
say "Sign in with your Yandex ID — the Google and X buttons do not work inside an embedded webview."
