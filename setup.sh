#!/bin/bash
#
# setup.sh — first-run onboarding for Open in Sheets.
#
# Walks you through it end to end: installs rclone if missing, connects a Google
# account (or reuses one that's already connected), builds the droplets, and
# offers to make them the default for CSVs. Safe to re-run — it adds accounts
# rather than replacing them, and skips anything already done.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${CSV2SHEET_CONF:-$HOME/.config/csv2sheet/accounts.conf}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()   { printf '  \033[31m✗\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ask()  { local p="$1" d="${2:-}" r; read -r -p "  $p${d:+ [$d]}: " r </dev/tty; printf '%s' "${r:-$d}"; }
yes()  { local r; r="$(ask "$1 (y/n)" "${2:-y}")"; case "$r" in [Yy]*) return 0 ;; *) return 1 ;; esac; }

# A remote is only usable if rclone stored an OAuth token for it. A remote left
# behind by a mistyped command exists but can never upload, so check for the
# token rather than just the name.
remote_ok() {
  rclone config show "$1" 2>/dev/null | grep -q '^token = '
}

printf '\n'
bold "Open in Sheets — setup"
printf 'Double-click a CSV, get a Google Sheet, opened in your default browser.\n'

# ---------------------------------------------------------------- 1. rclone
step "1. rclone"
command -v rclone >/dev/null 2>&1 || export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if command -v rclone >/dev/null 2>&1; then
  ok "installed: $(command -v rclone)"
else
  no "rclone is not installed — it's what talks to Google Drive."
  if command -v brew >/dev/null 2>&1; then
    if yes "Install it now with Homebrew?"; then
      brew install rclone || { no "brew install failed"; exit 1; }
      ok "installed"
    else
      echo "    Install it yourself, then re-run:  brew install rclone"; exit 1
    fi
  else
    echo "    Install Homebrew from https://brew.sh, then:  brew install rclone"; exit 1
  fi
fi

# ------------------------------------------------------- 2. existing accounts
step "2. What's already set up"
mkdir -p "$(dirname "$CONF")"
[ -f "$CONF" ] || : >"$CONF"

LABELS=(); REMOTES=(); EMAILS=()
read_conf() {
  LABELS=(); REMOTES=(); EMAILS=()
  local line l r e
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
}
read_conf

if [ "${#LABELS[@]}" -eq 0 ]; then
  warn "no accounts listed yet"
else
  for i in "${!LABELS[@]}"; do
    if remote_ok "${REMOTES[$i]}"; then
      ok "${LABELS[$i]} → ${REMOTES[$i]} ${EMAILS[$i]:+(${EMAILS[$i]})}"
    else
      no "${LABELS[$i]} → ${REMOTES[$i]} is not connected (no token)"
    fi
  done
fi

# Flag remotes that exist but were never authorised — e.g. left behind by a
# mistyped `rclone config create` that swallowed extra words as config keys.
for r in $(rclone listremotes 2>/dev/null | sed 's/:$//'); do
  if ! remote_ok "$r"; then
    warn "rclone remote '$r' exists but has no token — it can't upload."
    if yes "    Delete the broken '$r' remote?" "y"; then
      rclone config delete "$r" && ok "deleted '$r'"
    fi
  fi
done

# ---------------------------------------------------------- 3. Google account
# The upload needs one Google login of its own — rclone cannot borrow the
# session from whatever browser profile you happen to be in. But one login is
# enough: every Sheet is created there, and opens in your current default
# browser whichever that is.
step "3. Google account"

in_conf() {
  local r="$1" i
  for i in "${!REMOTES[@]}"; do [ "${REMOTES[$i]}" = "$r" ] && return 0; done
  return 1
}

# Adopt a login that's already connected, rather than making you authorise again.
adopt_remote() {
  local remote="$1" label email
  label="$(ask "Short name for '$remote'" "Default")"
  [ -n "$label" ] || label="Default"
  email="$(ask "Its Google address (optional, press Return to skip)")"
  printf '%s|%s|%s\n' "$label" "$remote" "$email" >>"$CONF"
  ok "using the existing '$remote' login as \"$label\""
  read_conf
}

connect_new() {
  local label email remote i
  label="$(ask "Short name for this account (e.g. Work, Personal)")"
  [ -n "$label" ] || { no "needs a name"; return 1; }
  for i in "${!LABELS[@]}"; do
    [ "${LABELS[$i]}" = "$label" ] && { no "\"$label\" is already configured"; return 1; }
  done
  email="$(ask "Its Google address")"

  remote="gdrive_$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g; s/__*/_/g; s/_$//')"
  i=2
  while rclone listremotes 2>/dev/null | grep -qx "${remote}:"; do
    remote="${remote}${i}"; i=$((i+1))
  done

  printf '\n'
  echo "  Your browser will open. Two screens to expect:"
  echo "    1. \"Google hasn't verified this app\" -> Advanced -> Go to rclone (unsafe)"
  echo "    2. A permission screen -> Allow"
  echo "  Sign in as ${email:-that account}, not whichever one is already active."
  printf '\n'
  read -r -p "  Press Return to open the browser... " _ </dev/tty

  if ! rclone config create "$remote" drive scope=drive.file || ! remote_ok "$remote"; then
    no "authorisation didn't complete — nothing was saved"
    rclone config delete "$remote" >/dev/null 2>&1
    return 1
  fi
  printf '%s|%s|%s\n' "$label" "$remote" "$email" >>"$CONF"
  ok "connected: $label -> $remote"
  read_conf
}

if [ "${#LABELS[@]}" -eq 0 ]; then
  adopted=0
  for r in $(rclone listremotes 2>/dev/null | sed 's/:$//'); do
    remote_ok "$r" || continue
    in_conf "$r" && continue
    ok "found an account already connected: '$r'"
    if yes "    Use it? (no new sign-in needed)" "y"; then
      adopt_remote "$r"; adopted=1; break
    fi
  done
  if [ "$adopted" -eq 0 ]; then
    warn "nothing connected yet — one sign-in is needed to upload"
    connect_new || true
  fi
else
  ok "already configured — nothing to connect"
fi

# Extra accounts are optional. One is enough unless you want Sheets to land in
# a different Drive depending on the file.
if yes "Add another Google account? (optional, one is usually enough)" "n"; then
  while : ; do
    connect_new || true
    yes "Add another?" "n" || break
  done
fi

read_conf
if [ "${#LABELS[@]}" -eq 0 ]; then
  no "No account configured — nothing to build yet."
  echo "    Re-run ./setup.sh when you're ready."
  exit 1
fi

# ------------------------------------------------------------- 4. build apps
step "4. Building the apps"
"$HERE/install.sh" | sed 's/^/  /'

# -------------------------------------------------------- 5. default handler
step "5. Make it the default for CSVs"
if command -v duti >/dev/null 2>&1; then
  if yes "Set \"Open in Sheets\" as the default for .csv and .tsv?"; then
    duti -s com.local.openinsheets public.comma-separated-values-text all 2>/dev/null
    duti -s com.local.openinsheets public.tab-separated-values-text all 2>/dev/null
    duti -s com.local.openinsheets csv all 2>/dev/null
    duti -s com.local.openinsheets tsv all 2>/dev/null
    ok "set — double-clicking a CSV now opens it in Sheets"
  fi
else
  warn "duti isn't installed, so this one step has to be manual:"
  echo "      Finder → right-click any .csv → Get Info → \"Open with:\""
  echo "      → Open in Sheets → Change All…"
  echo
  echo "    Or:  brew install duti  and re-run ./setup.sh to have it done for you."
fi

step "Done"
cat <<'NEXT'
  double-click a CSV        uploads and opens it in your default browser
  csv2sheet --doctor        check everything is wired up
  csv2sheet --list          show configured accounts
  csv2sheet file.csv        from the terminal (~/bin/csv2sheet)

  With more than one account configured, double-clicking asks which to use,
  and "Open in Sheets (Label)" under right-click > Open With skips the prompt.
NEXT
