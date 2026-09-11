# Open in Sheets

Double-click a CSV on your Mac and it opens as a real Google Sheet in your browser.
No `sheets.new`, no File > Import, no Replace/Insert dialog.

This is a free equivalent of the $9 [CSVtoSheets](https://csvtosheets.com/) app,
built from the same three ingredients it uses.

---

## Setup

### 1. Install rclone

`rclone` does the Google authentication so you don't need a Google Cloud project.

```
brew install rclone
```

(No Homebrew? Get it at https://brew.sh first.)

### 2. Run the installer

```
./install.sh
```

It installs the script, builds the Mac app, and registers it with macOS.
Re-running it is safe — it only overwrites its own files.

### 3. Connect your Google account (once)

```
rclone config create gdrive drive scope=drive.file
```

Your browser opens. Two things you'll see:

- **"Google hasn't verified this app"** — expected. This is rclone's own OAuth
  client, not something in this package. Click **Advanced** > **Go to rclone (unsafe)**.
- **A permission screen** saying it can access *"only the specific Google Drive files
  you use with this app."* That's the `drive.file` scope: it can create Sheets and
  read back the ones it made, but it **cannot see the rest of your Drive**.

Click **Allow**. Done forever — the token refreshes silently after this.

### 4. Make it your default for CSVs

In Finder: right-click any `.csv` > **Get Info** > **"Open with:"** > **Open in Sheets**
> **Change All…**

---

## Using it

**Double-click any CSV.** A notification says "Uploading…", then a Chrome tab opens
with your data as a Google Sheet.

### Worked example

You download `orders-august.csv` from a reporting tool into `~/Downloads`.
Double-click it. Two seconds later Chrome opens a Sheet called
**"orders-august 2026-09-10 1615"**, columns already split, ready to edit.

Open the same file again next week and you get a *second* Sheet — it never silently
overwrites edits you made in the first one.

### From the terminal

```
~/bin/csv2sheet somefile.csv
```

Add `~/bin` to your `PATH` and it's just `csv2sheet somefile.csv`.

### Opening a CSV somewhere else, just once

Right-click > **Open With** > Numbers / Excel. One-off; your default stays put.

---

## Where things go

Every Sheet lands in a Drive folder called **"CSV to Sheets"**. Worth clearing it out
occasionally or it will pile up.

---

## Configuration

Environment variables, set them before running or edit the top of `~/bin/csv2sheet`:

| Variable | Default | What it does |
|---|---|---|
| `CSV2SHEET_REMOTE` | `gdrive` | rclone remote name |
| `CSV2SHEET_FOLDER` | `CSV to Sheets` | Drive folder to upload into |
| `CSV2SHEET_NAME_MODE` | `timestamp` | `timestamp` = new Sheet each time. `plain` = reuse one Sheet per filename (overwrites) |
| `CSV2SHEET_BROWSER` | `Google Chrome` | Which browser opens the Sheet |

---

## How it works

Three pieces, same design as the paid app:

1. **`Open in Sheets.app`** — an AppleScript droplet whose `Info.plist` declares it a
   handler for `.csv`/`.tsv`. That's what lets macOS hand it a double-clicked file.
2. **`~/bin/csv2sheet`** — uploads the file to Drive *with conversion enabled*, so
   Google returns a native Sheet rather than a stored CSV.
3. It reads the new Sheet's ID back and opens
   `https://docs.google.com/spreadsheets/d/<id>/edit`.

Your files go straight from your Mac to Google. Nothing passes through any third party.

The installer **builds** the app on your machine rather than shipping a prebuilt one —
a downloaded `.app` gets quarantined by Gatekeeper and nags about an unidentified
developer. Compiling locally avoids that entirely.

---

## Known issues

### ⚠️ rclone's shared client ID is being retired during 2026

Uploads will eventually start failing with authentication errors. This is not a bug in
this package — Google is retiring the shared OAuth client that rclone ships with.

**Fix when it happens:** create your own OAuth client ID
(https://rclone.org/drive/#making-your-own-client-id) and add it to the remote:

```
rclone config update gdrive client_id YOUR_ID client_secret YOUR_SECRET
```

Bonus: doing this also removes the "unverified app" warning from step 3, since you'd
be trusting your own client.

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

**"No rclone remote named gdrive yet"** — step 3 hasn't been done.

**"can't convert .csv to a document with a different export filetype (.xlsx)"** — rclone
needs `--drive-import-formats` and `--drive-export-formats` to match. The script already
does this; you'd only hit it running rclone by hand.

**Uploads but no Sheet opens** — check the "CSV to Sheets" folder in Drive. If the file
is there, the problem is the ID lookup, not the upload.

**Nothing happens on double-click** — confirm the default is actually set (Get Info),
then re-run `./install.sh` to re-register the app with Launch Services.

---

## Uninstalling

```
rm -rf ~/Applications/"Open in Sheets.app"
rm -f ~/bin/csv2sheet
rclone config delete gdrive     # revokes nothing; also visit
                                # https://myaccount.google.com/permissions
```
