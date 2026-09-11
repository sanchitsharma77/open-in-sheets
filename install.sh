#!/bin/bash
#
# Installer for "Open in Sheets" — double-click a CSV, get a Google Sheet.
# Safe to re-run; it overwrites its own files and touches nothing else.
#
# Builds one droplet per Google account listed in ~/.config/csv2sheet/accounts.conf,
# plus a generic "Open in Sheets.app" that asks which account to use.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${CSV2SHEET_CONF:-$HOME/.config/csv2sheet/accounts.conf}"
APPDIR="$HOME/Applications"
say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()  { printf '  ✓ %s\n' "$1"; }
no()  { printf '  ✗ %s\n' "$1"; }
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

say "1. Checking rclone"
if ! command -v rclone >/dev/null 2>&1; then
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
fi
if command -v rclone >/dev/null 2>&1; then
  ok "rclone found: $(command -v rclone)"
else
  no "rclone is not installed."
  echo "    Install it first:  brew install rclone"
  echo "    (No Homebrew? Get it at https://brew.sh)"
  exit 1
fi

say "2. Installing the csv2sheet script"
mkdir -p "$HOME/bin"
cp "$HERE/csv2sheet" "$HOME/bin/csv2sheet"
chmod +x "$HOME/bin/csv2sheet"
ok "installed to ~/bin/csv2sheet"

say "3. Accounts"
if [ ! -f "$CONF" ]; then
  mkdir -p "$(dirname "$CONF")"
  cat >"$CONF" <<'SAMPLE'
# One line per Google account:  Label|rclone-remote|email
#
#   Label   what you pick in the chooser, and the name of its droplet
#   remote  the rclone remote holding that account's credentials
#   email   passed to Google as ?authuser= so the Sheet opens as the right
#           account when you're signed into several at once
#
# Connect each account once:
#   rclone config create <remote> drive scope=drive.file
#
# Then uncomment/edit lines below and re-run ./install.sh
#
# Work|gdrive_work|you@company.com
# Personal|gdrive_personal|you@gmail.com
SAMPLE
  ok "wrote a starter config to $CONF"
else
  ok "using $CONF"
fi

# Parse the config into parallel arrays.
LABELS=(); REMOTES=(); EMAILS=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%$'\r'}"
  case "$line" in ''|'#'*) continue ;; esac
  IFS='|' read -r l r e <<<"$line"
  l="$(printf '%s' "${l:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  r="$(printf '%s' "${r:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  e="$(printf '%s' "${e:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -n "$l" ] && [ -n "$r" ] || continue
  LABELS+=("$l"); REMOTES+=("$r"); EMAILS+=("$e")
done <"$CONF"

if [ "${#LABELS[@]}" -eq 0 ]; then
  no "no accounts configured yet — building the generic droplet only"
else
  for i in "${!LABELS[@]}"; do
    ok "${LABELS[$i]}  →  ${REMOTES[$i]}  ${EMAILS[$i]:+(${EMAILS[$i]})}"
  done
fi

# build_droplet <app name> <account label or empty> <bundle id suffix>
build_droplet() {
  local name="$1" label="$2" idsuffix="$3"
  local app="$APPDIR/$name.app"
  local src="$HERE/OpenInSheets.applescript"
  local tmp="" tmpdir=""

  if [ -n "$label" ]; then
    tmpdir="$(mktemp -d -t openinsheets)"
    tmp="$tmpdir/OpenInSheets.applescript"
    # Bake the account into this droplet's copy of the script.
    /usr/bin/python3 - "$src" "$tmp" "$label" <<'PY'
import sys
src, dst, label = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src).read()
text = text.replace('property accountLabel : ""',
                    'property accountLabel : "%s"' % label.replace('\\', '\\\\').replace('"', '\\"'), 1)
open(dst, "w").write(text)
PY
    src="$tmp"
  fi

  rm -rf "$app"
  osacompile -o "$app" "$src" || { no "osacompile failed for $name"; [ -n "$tmpdir" ] && rm -rf "$tmpdir"; return 1; }
  [ -n "$tmpdir" ] && rm -rf "$tmpdir"

  local PL="$app/Contents/Info.plist"
  local P=/usr/libexec/PlistBuddy
  $P -c "Delete :CFBundleDocumentTypes" "$PL" 2>/dev/null
  $P -c "Add :CFBundleDocumentTypes array" "$PL"
  $P -c "Add :CFBundleDocumentTypes:0 dict" "$PL"
  $P -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string 'Comma-Separated Values'" "$PL"
  $P -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor" "$PL"
  $P -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate" "$PL"
  $P -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" "$PL"
  $P -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string public.comma-separated-values-text" "$PL"
  $P -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:1 string public.tab-separated-values-text" "$PL"
  $P -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:2 string public.delimited-values-text" "$PL"
  $P -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$PL"
  $P -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:0 string csv" "$PL"
  $P -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:1 string tsv" "$PL"
  $P -c "Set :CFBundleIdentifier com.local.openinsheets${idsuffix}" "$PL" 2>/dev/null \
    || $P -c "Add :CFBundleIdentifier string com.local.openinsheets${idsuffix}" "$PL"
  plutil -lint "$PL" >/dev/null || { no "Info.plist is malformed for $name"; return 1; }
  codesign --force --sign - "$app" >/dev/null 2>&1
  "$LSREG" -f "$app" >/dev/null 2>&1
  ok "built $app"
}

SEEN_SLUGS=()
say "4. Building the Mac apps"
mkdir -p "$APPDIR"
build_droplet "Open in Sheets" "" ""

# A droplet per account, so right-click > Open With picks the account directly.
for i in "${!LABELS[@]}"; do
  label="${LABELS[$i]}"
  # Slugify the label into something safe for a bundle identifier.
  slug="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
  [ -n "$slug" ] || slug="acct$i"
  # Distinct labels can collapse to the same slug; a duplicate bundle id would
  # make Launch Services treat two droplets as one app.
  case " ${SEEN_SLUGS[*]-} " in *" $slug "*) slug="${slug}${i}" ;; esac
  SEEN_SLUGS+=("$slug")
  build_droplet "Open in Sheets ($label)" "$label" ".$slug"
done

say "5. Google accounts"
missing=0
if [ "${#LABELS[@]}" -eq 0 ]; then
  no "none configured — edit $CONF, then re-run ./install.sh"
else
  for i in "${!LABELS[@]}"; do
    if rclone listremotes 2>/dev/null | grep -qx "${REMOTES[$i]}:"; then
      ok "${LABELS[$i]}: remote '${REMOTES[$i]}' exists"
    else
      no "${LABELS[$i]}: no remote '${REMOTES[$i]}' yet — run:"
      echo "      rclone config create ${REMOTES[$i]} drive scope=drive.file"
      missing=1
    fi
  done
  [ "$missing" -eq 1 ] && echo "
    Each one opens your browser. On the 'unverified app' screen click
    Advanced > Go to rclone (unsafe), then Allow. Sign in as that account."
fi

say "Done."
cat <<'NEXT'
  Set the double-click default, in Finder:
    right-click any .csv > Get Info > "Open with:" > Open in Sheets > Change All...

  Then:
    double-click a CSV        -> asks which account, opens in your default browser
    right-click > Open With   -> pick "Open in Sheets (Label)" to skip the prompt
    csv2sheet --list          -> show configured accounts
    csv2sheet --account Work file.csv
NEXT
