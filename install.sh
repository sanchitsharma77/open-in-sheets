#!/bin/bash
#
# Installer for "Open in Sheets" — double-click a CSV, get a Google Sheet.
# Safe to re-run; it overwrites its own files and touches nothing else.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HOME/Applications/Open in Sheets.app"
say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()  { printf '  ✓ %s\n' "$1"; }
no()  { printf '  ✗ %s\n' "$1"; }

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

say "3. Building the Mac app"
mkdir -p "$HOME/Applications"
rm -rf "$APP"
osacompile -o "$APP" "$HERE/OpenInSheets.applescript" || { no "osacompile failed"; exit 1; }

PL="$APP/Contents/Info.plist"
P=/usr/libexec/PlistBuddy
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
$P -c "Set :CFBundleIdentifier com.local.openinsheets" "$PL" 2>/dev/null \
  || $P -c "Add :CFBundleIdentifier string com.local.openinsheets" "$PL"
plutil -lint "$PL" >/dev/null || { no "Info.plist is malformed"; exit 1; }
codesign --force --sign - "$APP" >/dev/null 2>&1
ok "built $APP"

say "4. Registering it as a CSV handler"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREG" -f "$APP" && ok "registered with Launch Services"

say "5. Google account"
if rclone listremotes 2>/dev/null | grep -qx "gdrive:"; then
  ok "already connected (rclone remote 'gdrive' exists)"
else
  no "not connected yet. Run this once:"
  echo
  echo "      rclone config create gdrive drive scope=drive.file"
  echo
  echo "    It opens your browser. On the 'unverified app' screen click"
  echo "    Advanced > Go to rclone (unsafe), then Allow."
fi

say "Done."
cat <<'NEXT'
  Last step, in Finder:
    right-click any .csv > Get Info > "Open with:" > Open in Sheets > Change All...

  Then double-click any CSV and it opens as a Google Sheet in Chrome.
NEXT
