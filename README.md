# Open in Sheets

Double-click a CSV on your Mac and it opens as a real Google Sheet in your browser.
No `sheets.new`, no File > Import, no Replace/Insert dialog.

It opens in **whatever your default browser currently is** — change the default in
System Settings and this follows it, no reconfiguring.

This is a free equivalent of the $9 [CSVtoSheets](https://csvtosheets.com/) app,
built from the same three ingredients it uses.

---

## Setup

```
brew install rclone      # what talks to Google Drive
./setup.sh               # everything else, interactively
```

`setup.sh` installs the script, connects a Google account (or reuses one you've
already connected), builds the Mac app, and offers to make it the default for CSVs.
Re-running it is safe.

If you'd rather do it by hand, `./install.sh` does the build steps only and prints
what's still missing.

### About the Google sign-in

The upload needs **one** Google login of its own. rclone can't borrow the session
from whatever browser profile you're in — it authenticates separately. One login is
enough though: every Sheet is created in that account's Drive, and opens in your
current default browser.

On the sign-in you'll see:

- **"Google hasn't verified this app"** — expected. This is rclone's own OAuth
  client, not something in this package. Click **Advanced** > **Go to rclone (unsafe)**.
- **A permission screen** saying it can access *"only the specific Google Drive files
  you use with this app."* That's the `drive.file` scope: it can create Sheets and
  read back the ones it made, but it **cannot see the rest of your Drive**.

Click **Allow**. Done forever — the token refreshes silently after this.

---

## Using it

**Double-click any CSV.** A notification says "Uploading…", then your default browser
opens with the data as a Google Sheet.

### Worked example

You download `orders-august.csv` from a reporting tool into `~/Downloads`.
Double-click it. Two seconds later a Sheet called
**"orders-august 2026-09-10 1615"** opens, columns already split, ready to edit.

Open the same file again next week and you get a *second* Sheet — it never silently
overwrites edits you made in the first one.

### From the terminal

```
~/bin/csv2sheet somefile.csv
csv2sheet --doctor          # check everything is wired up
csv2sheet --list            # show configured accounts
```

Add `~/bin` to your `PATH` and it's just `csv2sheet somefile.csv`.

### Opening a CSV somewhere else, just once

Right-click > **Open With** > Numbers / Excel. One-off; your default stays put.

---

## More than one Google account

Optional. Most people want one. If you do want Sheets to land in different Drives
depending on the file, add each account in `~/.config/csv2sheet/accounts.conf`:

```
Work|gdrive_work|you@company.com
Personal|gdrive_personal|you@gmail.com
```

| Field | What it's for |
|---|---|
| Label | what you pick in the chooser, and the name of its droplet |
| remote | the rclone remote holding that account's credentials |
| email | passed to Google as `?authuser=` so the Sheet opens as the right account when several are signed in |

`./setup.sh` writes these for you. After that:

- **Double-click** asks which account to use.
- **Right-click > Open With > "Open in Sheets (Work)"** skips the prompt.
- `csv2sheet --account Work file.csv` from the terminal.

The `email` field matters: without it, a Sheet owned by one account can land on
"You need access" when your browser is active as a different one.

---

## Where things go

Every Sheet lands in a Drive folder called **"CSV to Sheets"**. Worth clearing out
occasionally or it will pile up.

---

## Configuration

Environment variables, set them before running or edit the top of `~/bin/csv2sheet`:

| Variable | Default | What it does |
|---|---|---|
| `CSV2SHEET_ACCOUNT` | — | account label to use, skips the chooser |
| `CSV2SHEET_REMOTE` | `gdrive` | rclone remote, when not using `accounts.conf` |
| `CSV2SHEET_FOLDER` | `CSV to Sheets` | Drive folder to upload into |
| `CSV2SHEET_NAME_MODE` | `timestamp` | `timestamp` = new Sheet each time. `plain` = reuse one Sheet per filename (overwrites) |
| `CSV2SHEET_BROWSER` | *(your default browser)* | pin a specific browser instead, e.g. `Google Chrome` |

---

## How it works

Three pieces, same design as the paid app:

1. **`Open in Sheets.app`** — an AppleScript droplet whose `Info.plist` declares it a
   handler for `.csv`/`.tsv`. That's what lets macOS hand it a double-clicked file.
2. **`~/bin/csv2sheet`** — uploads the file to Drive *with conversion enabled*, so
   Google returns a native Sheet rather than a stored CSV.
3. It reads the new Sheet's ID back and hands
   `https://docs.google.com/spreadsheets/d/<id>/edit` to `open`, which routes it to
   your current default browser.

Your files go straight from your Mac to Google. Nothing passes through any third party.

The installer **builds** the app on your machine rather than shipping a prebuilt one —
a downloaded `.app` gets quarantined by Gatekeeper and nags about an unidentified
developer. Compiling locally avoids that entirely.

### Checking a Sheet really converted

`rclone lsjson` reports Google-native files using their *export* format, so a real
Sheet shows up as `name.xlsx`. That's not a stored xlsx — the giveaway is `"Size": -1`,
which only Google-native files have. A stored CSV reports its true byte size.

---

## Known issues

### ⚠️ rclone's shared client ID is being retired during 2026

Uploads will eventually start failing with authentication errors — rclone already
prints a NOTICE about this on every run. This is not a bug in this package; Google is
retiring the shared OAuth client that rclone ships with.

**Fix when it happens:** create your own OAuth client ID
(https://rclone.org/drive/#making-your-own-client-id) and add it to the remote:

```
rclone config update gdrive client_id YOUR_ID client_secret YOUR_SECRET
```

Bonus: doing this also removes the "unverified app" warning from the sign-in, since
you'd be trusting your own client.

### Only CSV and TSV

No `.xls` / `.xlsx` yet. rclone can convert those too — it needs the extension handling
in `csv2sheet` extended.

### Token storage

The Google token sits in `~/.config/rclone/rclone.conf` as plain text, readable by
anything running as you. The paid app keeps its token in the Apple Keychain, which is
better hardened. If that matters to you, tighten it with `chmod 600
~/.config/rclone/rclone.conf` — a partial improvement, not a fix.

---

## Troubleshooting

Start with `csv2sheet --doctor` — it checks rclone, every configured account and its
token, the droplets, the CSV default handler, your default browser and your `PATH`,
and names whatever is wrong.

**"No rclone remote named gdrive yet"** — run `./setup.sh`.

**A remote exists but every upload fails** — it was probably created without
completing the browser step, so it has no token. `rclone config show <name>` will show
no `token =` line. `setup.sh` spots these and offers to delete them.

**"can't convert .csv to a document with a different export filetype (.xlsx)"** — rclone
needs `--drive-import-formats` and `--drive-export-formats` to match. The script already
does this; you'd only hit it running rclone by hand.

**Uploads but no Sheet opens** — check the "CSV to Sheets" folder in Drive. If the file
is there, the problem is the ID lookup, not the upload.

**Sheet opens on "You need access"** — your browser is active as a different Google
account than the one that owns it. Add the `email` field for that account in
`accounts.conf` so the link carries `?authuser=`.

**Nothing happens on double-click** — confirm the default is actually set (Get Info),
then re-run `./install.sh` to re-register the app with Launch Services.

---

## Uninstalling

```
rm -rf ~/Applications/"Open in Sheets.app" ~/Applications/"Open in Sheets ("*").app"
rm -f ~/bin/csv2sheet
rm -rf ~/.config/csv2sheet
rclone config delete gdrive     # revokes nothing; also visit
                                # https://myaccount.google.com/permissions
```
