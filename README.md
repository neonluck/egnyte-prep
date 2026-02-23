# Egnyte Prep

Prepare files and folders on your Mac for upload to Egnyte. Cleans junk files, fixes illegal characters, and warns about path length issues — so your uploads don't silently fail.

## What it does

1. **Removes junk files** — `.DS_Store`, `._` resource forks, `Thumbs.db`, `__MACOSX`, temp files, and other system files that Egnyte rejects
2. **Fixes illegal characters** — replaces `\ : " < > | * ?` with underscores
3. **Fixes bad names** — strips leading/trailing spaces and trailing periods
4. **Checks path lengths** — warns about names over 245 characters and Office files over the 215-character limit
5. **Finds empty folders** — Egnyte skips empty folders, so you can remove them

Always runs in **Preview mode first** so you can see exactly what will change before anything is modified.

---

## Option A: Double-click (easiest)

1. Click the green **Code** button above, then **Download ZIP**
2. Unzip the folder
3. Double-click **`Egnyte Prep.command`**
4. If macOS blocks it: right-click the file → **Open** → click **Open** in the dialog

That's it. Terminal will open and walk you through it.

## Option B: Install as a command

Paste this into Terminal (it will ask for your Mac password):

```bash
sudo curl -fsSL https://raw.githubusercontent.com/neonluck/egnyte-prep/main/egnyte-prep.sh -o /usr/local/bin/egnyte-prep && sudo chmod +x /usr/local/bin/egnyte-prep
```

Then run it anytime:

```bash
egnyte-prep /path/to/your/folder
```

Or just type `egnyte-prep` and it will ask for the path (you can drag a folder from Finder).

---

## Usage

```
$ egnyte-prep /Volumes/MyDrive/ProjectFolder

╔══════════════════════════════════════════════════════╗
║         Egnyte Upload Preparation Tool               ║
╚══════════════════════════════════════════════════════╝

This tool prepares a folder for upload to Egnyte by:
  1. Removing macOS/Windows junk files (.DS_Store, Thumbs.db, etc.)
  2. Removing temp files that Egnyte would reject
  3. Renaming files/folders with illegal characters
  4. Fixing names that start/end with spaces or periods
  5. Warning about paths that exceed Egnyte limits

Target folder: /Volumes/MyDrive/ProjectFolder
Found 1,247 files and 83 folders

Choose a mode:
  1) Preview  — show what would change (no files modified)
  2) Execute  — make the changes
```

**Tip:** You can drag and drop a folder from Finder into the Terminal window when it asks for a path.

## What gets removed

| File | Why |
|------|-----|
| `.DS_Store`, `._*` | macOS metadata — breaks on other platforms |
| `__MACOSX` | Resource fork folder created by macOS zip |
| `.Spotlight-V100`, `.fseventsd`, `.Trashes` | macOS system indexes |
| `Thumbs.db`, `desktop.ini` | Windows metadata |
| `~$*.docx`, `.~*` | Office/app temp files |
| `*.dwl`, `*.dwl2` | AutoCAD lock files |
| `.smbdelete*` | SMB file share markers |

## What gets fixed

| Character / Issue | Egnyte blocks it? | Script fixes it? | How |
|---|---|---|---|
| `\` backslash | Yes | Yes | Replaced with `_` |
| `/` forward slash | Yes | N/A | macOS already prevents this in file names |
| `:` colon | Yes | Yes | Replaced with `_` |
| `"` double quote | Yes | Yes | Replaced with `_` |
| `<` `>` angle brackets | Yes | Yes | Replaced with `_` |
| `\|` pipe | Yes | Yes | Replaced with `_` |
| `*` asterisk | Yes | Yes | Replaced with `_` |
| `?` question mark | Yes | Yes | Replaced with `_` |
| Trailing periods (e.g., `file.`) | Yes | Yes | Stripped from end of name |
| Leading/trailing spaces | Yes | Yes | Stripped from name |
| Name longer than 245 characters | Yes | Warned | You'll need to shorten manually |
| Path longer than 5,000 characters | Yes | Warned | Move to a shorter folder path |
| Office file path longer than 215 characters | Yes | Warned | Shorten path or file name |

Source: [Egnyte — Unsupported Characters and File Types](https://helpdesk.egnyte.com/hc/en-us/articles/201637074-Unsupported-Characters-and-File-Types)

## Requirements

- macOS (tested on macOS 13+)
- No dependencies — uses only built-in macOS tools

## License

MIT
