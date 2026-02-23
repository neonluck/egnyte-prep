#!/bin/bash
# egnyte-prep.sh — Prepare files and folders for Egnyte upload
# Cleans illegal characters, removes junk/temp files, fixes naming issues
# Reference: https://helpdesk.egnyte.com/hc/en-us/articles/201637074

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
WHITE='\033[1;37m'

# ─── Counters ─────────────────────────────────────────────────────────────────
FILES_REMOVED=0
FILES_RENAMED=0
DIRS_RENAMED=0
WARNINGS=0

# ─── Logging ──────────────────────────────────────────────────────────────────
LOG_FILE=""

log() {
    echo -e "$1"
    if [[ -n "$LOG_FILE" ]]; then
        echo -e "$1" | sed 's/\x1B\[[0-9;]*m//g' >> "$LOG_FILE"
    fi
}

# Helper: pause for user to read
pause() {
    echo ""
    read -r -p "  Press Enter to continue..." _
    echo ""
}

# Helper: show a step header with explanation
step_header() {
    local step_num="$1"
    local title="$2"
    local total="$3"
    echo ""
    log "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    log "  ${BOLD}Step ${step_num} of ${total}: ${title}${RESET}"
    log "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# ─── Clear screen and welcome ────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo ""
echo -e "  ${BOLD}${WHITE}Egnyte Prep${RESET}"
echo -e "  ${DIM}Prepare your files for Egnyte upload${RESET}"
echo ""
echo -e "  ${DIM}────────────────────────────────────────────────────${RESET}"
echo ""
echo -e "  ${BOLD}What is this?${RESET}"
echo -e "  Egnyte is picky about file names. If your files have certain"
echo -e "  characters or names, they'll silently fail to upload — you won't"
echo -e "  get an error, they just won't appear on Egnyte."
echo ""
echo -e "  This tool scans a folder and fixes those issues ${BOLD}before${RESET} you upload."
echo ""
echo -e "  ${BOLD}What it does:${RESET}"
echo -e "  ${GREEN}Step 1${RESET}  Removes hidden junk files (like .DS_Store) that your Mac"
echo -e "          creates automatically. These aren't your files — they're"
echo -e "          invisible system files that clutter up Egnyte."
echo ""
echo -e "  ${GREEN}Step 2${RESET}  Fixes file names that contain characters Egnyte doesn't"
echo -e "          allow (like colons, quotes, or angle brackets)."
echo ""
echo -e "  ${GREEN}Step 3${RESET}  Checks if any file names or paths are too long for Egnyte."
echo ""
echo -e "  ${GREEN}Step 4${RESET}  Finds empty folders that Egnyte would skip."
echo ""
echo -e "  ${BOLD}Is it safe?${RESET}"
echo -e "  Yes! It will ${BOLD}always show you a preview first${RESET} before making any"
echo -e "  changes. Nothing is modified until you say so."
echo ""
echo -e "  ${DIM}────────────────────────────────────────────────────${RESET}"
echo ""

# ─── Get target path ─────────────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
    TARGET_PATH="$1"
else
    echo -e "  ${BOLD}Where are your files?${RESET}"
    echo ""
    echo -e "  Enter the path to the folder you want to clean up."
    echo ""
    echo -e "  ${CYAN}Tip: You can drag a folder from Finder directly into this${RESET}"
    echo -e "  ${CYAN}window instead of typing the path.${RESET}"
    echo ""
    read -r -p "  Folder path: " TARGET_PATH
fi

# Strip quotes that Finder drag-and-drop sometimes adds
TARGET_PATH="${TARGET_PATH%\"}"
TARGET_PATH="${TARGET_PATH#\"}"
TARGET_PATH="${TARGET_PATH%\'}"
TARGET_PATH="${TARGET_PATH#\'}"

# Remove backslash escapes from Finder drag-and-drop (e.g., "My\ Folder" → "My Folder")
TARGET_PATH="${TARGET_PATH//\\/}"

# Trim leading/trailing whitespace
TARGET_PATH="$(echo -e "${TARGET_PATH}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

# Resolve to absolute path
if [[ ! "$TARGET_PATH" = /* ]]; then
    TARGET_PATH="$(cd "$TARGET_PATH" 2>/dev/null && pwd)"
fi

# Validate
if [[ ! -d "$TARGET_PATH" ]]; then
    echo ""
    echo -e "  ${RED}Hmm, that doesn't look like a valid folder.${RESET}"
    echo ""
    echo -e "  You entered: $TARGET_PATH"
    echo ""
    echo -e "  ${DIM}Make sure the folder exists and try again.${RESET}"
    echo -e "  ${DIM}Tip: Drag the folder from Finder into Terminal — that way${RESET}"
    echo -e "  ${DIM}you don't have to type the path manually.${RESET}"
    echo ""
    exit 1
fi

echo ""
echo -e "  ${DIM}────────────────────────────────────────────────────${RESET}"
echo ""

# Count files/folders
TOTAL_FILES=$(find "$TARGET_PATH" -type f 2>/dev/null | wc -l | tr -d ' ')
TOTAL_DIRS=$(find "$TARGET_PATH" -type d 2>/dev/null | wc -l | tr -d ' ')

echo -e "  ${BOLD}Folder:${RESET}  $(basename "$TARGET_PATH")"
echo -e "  ${BOLD}Path:${RESET}    $TARGET_PATH"
echo -e "  ${BOLD}Contains:${RESET} $TOTAL_FILES files in $TOTAL_DIRS folders"
echo ""

# ─── Set up log file ─────────────────────────────────────────────────────────
LOG_FILE="$TARGET_PATH/egnyte-prep-log_$(date +%Y%m%d_%H%M%S).txt"

# ─── Scanning phase (always preview first) ───────────────────────────────────
echo -e "  ${CYAN}Scanning your folder now...${RESET}"
echo -e "  ${DIM}This is just a preview — nothing will be changed yet.${RESET}"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: Remove junk and temp files
# ═══════════════════════════════════════════════════════════════════════════════
step_header "1" "Hidden Junk Files" "4"

log "  ${DIM}Your Mac (and Windows PCs) create invisible files like .DS_Store${RESET}"
log "  ${DIM}in every folder. These aren't your documents — they're system${RESET}"
log "  ${DIM}files that can cause problems on Egnyte.${RESET}"
echo ""

# macOS junk
JUNK_PATTERNS=(
    ".DS_Store"
    "._.DS_Store"
    ".Spotlight-V100"
    ".Trashes"
    ".fseventsd"
    "__MACOSX"
    ".TemporaryItems"
    ".VolumeIcon.icns"
    ".com.apple.timemachine.donotpresent"
    ".AppleDouble"
    ".LSOverride"
    ".DocumentRevisions-V100"
)

# Windows junk
JUNK_PATTERNS+=(
    "Thumbs.db"
    "Thumbs.db:encryptable"
    "ehthumbs.db"
    "ehthumbs_vista.db"
    "desktop.ini"
    '$RECYCLE.BIN'
    "System Volume Information"
)

JUNK_FILES=()

for pattern in "${JUNK_PATTERNS[@]}"; do
    while IFS= read -r -d '' file; do
        JUNK_FILES+=("$file")
        relpath="${file#$TARGET_PATH/}"
        case "$pattern" in
            .DS_Store|._.DS_Store)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Mac folder metadata${RESET}" ;;
            .Spotlight-V100)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Mac search index${RESET}" ;;
            .Trashes)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Mac trash data${RESET}" ;;
            .fseventsd)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Mac file system events${RESET}" ;;
            __MACOSX)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Mac zip artifact${RESET}" ;;
            .TemporaryItems)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Mac temp data${RESET}" ;;
            .VolumeIcon.icns)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Drive icon file${RESET}" ;;
            .com.apple.timemachine.donotpresent)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Time Machine marker${RESET}" ;;
            .AppleDouble|.LSOverride)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Mac system file${RESET}" ;;
            .DocumentRevisions-V100)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Mac version history${RESET}" ;;
            Thumbs.db|Thumbs.db:encryptable|ehthumbs.db|ehthumbs_vista.db)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Windows thumbnail cache${RESET}" ;;
            desktop.ini)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Windows folder settings${RESET}" ;;
            '$RECYCLE.BIN')
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Windows recycle bin${RESET}" ;;
            "System Volume Information")
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Windows system data${RESET}" ;;
            *)
                log "  ${RED}x${RESET}  ${relpath}  ${DIM}— System junk${RESET}" ;;
        esac
        ((FILES_REMOVED++))
    done < <(find "$TARGET_PATH" -name "$pattern" -print0 2>/dev/null)
done

# macOS resource fork files (._*)
while IFS= read -r -d '' file; do
    JUNK_FILES+=("$file")
    relpath="${file#$TARGET_PATH/}"
    log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Mac resource fork (hidden copy)${RESET}"
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" -name "._*" -type f -print0 2>/dev/null)

# Egnyte-rejected temp file patterns
while IFS= read -r -d '' file; do
    JUNK_FILES+=("$file")
    relpath="${file#$TARGET_PATH/}"
    log "  ${RED}x${RESET}  ${relpath}  ${DIM}— App temp/lock file${RESET}"
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" \( -name ".~*" -o -name '~$*' -o -name '~*.$$$' \) -type f -print0 2>/dev/null)

# Files ending with .tmp, .ac$, .sv$ (only Office temp patterns)
while IFS= read -r -d '' file; do
    basename_f=$(basename "$file")
    if [[ "$basename_f" =~ ^\~ ]] || [[ "$basename_f" =~ ^\.~ ]]; then
        JUNK_FILES+=("$file")
        relpath="${file#$TARGET_PATH/}"
        log "  ${RED}x${RESET}  ${relpath}  ${DIM}— App temp file${RESET}"
        ((FILES_REMOVED++))
    fi
done < <(find "$TARGET_PATH" \( -name "*.tmp" -o -name '*.ac$' -o -name '*.sv$' \) -type f -print0 2>/dev/null)

# AutoCAD lock files
while IFS= read -r -d '' file; do
    JUNK_FILES+=("$file")
    relpath="${file#$TARGET_PATH/}"
    log "  ${RED}x${RESET}  ${relpath}  ${DIM}— AutoCAD lock file${RESET}"
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" \( -name "*.dwl" -o -name "*.dwl1" -o -name "*.dwl2" \) -type f -print0 2>/dev/null)

# Spotlight index files
while IFS= read -r -d '' file; do
    JUNK_FILES+=("$file")
    relpath="${file#$TARGET_PATH/}"
    log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Spotlight index${RESET}"
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" -name ".spotlight-*" -print0 2>/dev/null)

# Egnyte internal metadata patterns
while IFS= read -r -d '' file; do
    JUNK_FILES+=("$file")
    relpath="${file#$TARGET_PATH/}"
    log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Egnyte metadata artifact${RESET}"
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" \( -name "*._attribs_" -o -name "*._rights_" -o -name "*._egn_" -o -name "*_egnmeta" -o -name "_egn_.*" \) -type f -print0 2>/dev/null)

# SMB delete markers
while IFS= read -r -d '' file; do
    JUNK_FILES+=("$file")
    relpath="${file#$TARGET_PATH/}"
    log "  ${RED}x${RESET}  ${relpath}  ${DIM}— Network share marker${RESET}"
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" -name ".smbdelete*" -type f -print0 2>/dev/null)

if [[ $FILES_REMOVED -eq 0 ]]; then
    log "  ${GREEN}No junk files found — your folder is clean!${RESET}"
else
    echo ""
    log "  ${YELLOW}Found $FILES_REMOVED junk file(s) to remove.${RESET}"
    log "  ${DIM}These are all invisible system files, not your documents.${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Fix illegal characters in names
# ═══════════════════════════════════════════════════════════════════════════════
step_header "2" "File Name Problems" "4"

log "  ${DIM}Egnyte doesn't allow these characters in file names:${RESET}"
log "  ${DIM}${BOLD}  \\  :  \"  <  >  |  *  ?${RESET}"
log "  ${DIM}Files also can't start or end with spaces, or end with periods.${RESET}"
log "  ${DIM}Any bad characters get replaced with an underscore ( _ ).${RESET}"
echo ""

sanitize_name() {
    local name="$1"

    # Replace prohibited characters with underscore: \ / " : < > | * ?
    name=$(echo "$name" | sed 's/[\\:\"<>|*?]/_/g')

    # Remove leading/trailing spaces
    name=$(echo "$name" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

    # Remove trailing periods (Egnyte rejects these)
    name=$(echo "$name" | sed 's/\.*$//')

    # If name became empty after sanitization, use a fallback
    if [[ -z "$name" ]]; then
        name="_renamed_$(date +%s)"
    fi

    echo "$name"
}

RENAME_LIST=()

# Process files (bottom-up by depth)
while IFS= read -r -d '' filepath; do
    dir=$(dirname "$filepath")
    basename_f=$(basename "$filepath")
    newname=$(sanitize_name "$basename_f")

    if [[ "$basename_f" != "$newname" ]]; then
        newpath="$dir/$newname"
        # Handle collision
        if [[ -e "$newpath" ]] && [[ "$filepath" != "$newpath" ]]; then
            counter=1
            ext=""
            stem="$newname"
            if [[ "$newname" =~ \. ]]; then
                ext=".${newname##*.}"
                stem="${newname%.*}"
            fi
            while [[ -e "$dir/${stem}_${counter}${ext}" ]]; do
                ((counter++))
            done
            newname="${stem}_${counter}${ext}"
            newpath="$dir/$newname"
        fi

        RENAME_LIST+=("$filepath|$newpath")

        # Explain what's wrong with the name
        reason=""
        if echo "$basename_f" | grep -q '[\\:\"<>|*?]'; then
            reason="has illegal character(s)"
        elif [[ "$basename_f" =~ ^[[:space:]] ]] || [[ "$basename_f" =~ [[:space:]]$ ]]; then
            reason="starts or ends with a space"
        elif [[ "$basename_f" =~ \.$ ]]; then
            reason="ends with a period"
        fi

        log "  ${YELLOW}~${RESET}  ${basename_f}"
        log "     ${GREEN}>${RESET}  ${newname}  ${DIM}— ${reason}${RESET}"

        ((FILES_RENAMED++))
    fi
done < <(find "$TARGET_PATH" -type f -print0 2>/dev/null | sort -rz)

# Process directories (bottom-up so children are renamed before parents)
while IFS= read -r -d '' dirpath; do
    [[ "$dirpath" == "$TARGET_PATH" ]] && continue

    parent=$(dirname "$dirpath")
    basename_d=$(basename "$dirpath")
    newname=$(sanitize_name "$basename_d")

    # Also check for folder names Egnyte rejects outright
    if [[ "$newname" == ".data" ]] || [[ "$newname" == ".tmp" ]]; then
        newname="_${newname}"
    fi

    if [[ "$basename_d" != "$newname" ]]; then
        newpath="$parent/$newname"
        # Handle collision
        if [[ -d "$newpath" ]] && [[ "$dirpath" != "$newpath" ]]; then
            counter=1
            while [[ -d "${newpath}_${counter}" ]]; do
                ((counter++))
            done
            newname="${newname}_${counter}"
            newpath="$parent/$newname"
        fi

        RENAME_LIST+=("$dirpath|$newpath")

        reason=""
        if echo "$basename_d" | grep -q '[\\:\"<>|*?]'; then
            reason="has illegal character(s)"
        elif [[ "$basename_d" =~ ^[[:space:]] ]] || [[ "$basename_d" =~ [[:space:]]$ ]]; then
            reason="starts or ends with a space"
        elif [[ "$basename_d" =~ \.$ ]]; then
            reason="ends with a period"
        fi

        log "  ${YELLOW}~${RESET}  ${basename_d}/  ${DIM}(folder)${RESET}"
        log "     ${GREEN}>${RESET}  ${newname}/  ${DIM}— ${reason}${RESET}"

        ((DIRS_RENAMED++))
    fi
done < <(find "$TARGET_PATH" -type d -print0 2>/dev/null | sort -rz)

if [[ $FILES_RENAMED -eq 0 ]] && [[ $DIRS_RENAMED -eq 0 ]]; then
    log "  ${GREEN}All file names are already Egnyte-compatible!${RESET}"
else
    echo ""
    TOTAL_RENAMES=$((FILES_RENAMED + DIRS_RENAMED))
    log "  ${YELLOW}Found $TOTAL_RENAMES name(s) that need fixing.${RESET}"
    log "  ${DIM}The files will be renamed, not deleted. Your content is safe.${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: Check path length limits
# ═══════════════════════════════════════════════════════════════════════════════
step_header "3" "Path Length Check" "4"

log "  ${DIM}Egnyte has limits on how long file names and paths can be:${RESET}"
log "  ${DIM}  - File/folder name: max 245 characters${RESET}"
log "  ${DIM}  - Full path: max 5,000 characters${RESET}"
log "  ${DIM}  - Microsoft Office files: max 215 characters for full path${RESET}"
echo ""

OFFICE_EXTS="doc|docx|xls|xlsx|xlsm|ppt|pptx|rtf"

while IFS= read -r -d '' filepath; do
    relpath="${filepath#$TARGET_PATH/}"
    basename_f=$(basename "$filepath")
    namelen=${#basename_f}
    pathlen=${#relpath}

    # Check component length (245 char limit)
    if [[ $namelen -gt 245 ]]; then
        shortname="${basename_f:0:50}...${basename_f: -20}"
        log "  ${RED}!${RESET}  ${shortname}"
        log "     ${DIM}Name is ${namelen} characters (max 245). You'll need to shorten this manually.${RESET}"
        ((WARNINGS++))
    fi

    # Check total path length (5000 char limit)
    if [[ $pathlen -gt 5000 ]]; then
        log "  ${RED}!${RESET}  ${basename_f}"
        log "     ${DIM}Full path is ${pathlen} characters (max 5,000). Move to a shorter folder path.${RESET}"
        ((WARNINGS++))
    fi

    # Check Office file path limit (215 chars)
    ext="${basename_f##*.}"
    ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    if [[ "$ext_lower" =~ ^($OFFICE_EXTS)$ ]] && [[ $pathlen -gt 215 ]]; then
        log "  ${YELLOW}!${RESET}  ${basename_f}"
        log "     ${DIM}Office file path is ${pathlen} characters (max 215). May not open correctly from Egnyte.${RESET}"
        ((WARNINGS++))
    fi
done < <(find "$TARGET_PATH" \( -type f -o -type d \) -print0 2>/dev/null)

if [[ $WARNINGS -eq 0 ]]; then
    log "  ${GREEN}All paths are within Egnyte's limits!${RESET}"
else
    echo ""
    log "  ${YELLOW}Found $WARNINGS path length issue(s).${RESET}"
    log "  ${DIM}These need to be fixed manually by shortening the file/folder names.${RESET}"
    log "  ${DIM}The tool can't rename them automatically because it doesn't know${RESET}"
    log "  ${DIM}what short name you'd prefer.${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: Check for empty folders
# ═══════════════════════════════════════════════════════════════════════════════
step_header "4" "Empty Folders" "4"

log "  ${DIM}Egnyte skips empty folders during upload. If you need those${RESET}"
log "  ${DIM}folders to exist on Egnyte, add a placeholder file to them.${RESET}"
echo ""

EMPTY_DIRS=()
while IFS= read -r -d '' dir; do
    if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
        relpath="${dir#$TARGET_PATH/}"
        EMPTY_DIRS+=("$dir")
        log "  ${DIM}o${RESET}  ${relpath}/  ${DIM}— empty${RESET}"
    fi
done < <(find "$TARGET_PATH" -type d -print0 2>/dev/null)

EMPTY_COUNT=${#EMPTY_DIRS[@]}
if [[ $EMPTY_COUNT -gt 0 ]]; then
    echo ""
    log "  ${DIM}Found $EMPTY_COUNT empty folder(s).${RESET}"
else
    log "  ${GREEN}No empty folders found!${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Results & Decision
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo ""
log "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
log "  ${BOLD}Scan Complete — Here's What We Found${RESET}"
log "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

TOTAL_ACTIONS=$((FILES_REMOVED + FILES_RENAMED + DIRS_RENAMED))

if [[ $TOTAL_ACTIONS -eq 0 ]] && [[ $WARNINGS -eq 0 ]] && [[ $EMPTY_COUNT -eq 0 ]]; then
    log "  ${GREEN}Your folder is already Egnyte-ready! Nothing to fix.${RESET}"
    echo ""
    log "  ${DIM}You can go ahead and upload to Egnyte.${RESET}"
    echo ""
    # Clean up empty log file
    rm -f "$LOG_FILE" 2>/dev/null
    exit 0
fi

if [[ $FILES_REMOVED -gt 0 ]]; then
    log "  ${RED}x${RESET}  ${BOLD}$FILES_REMOVED junk file(s)${RESET} to remove  ${DIM}(invisible system files, not your documents)${RESET}"
fi
if [[ $FILES_RENAMED -gt 0 ]] || [[ $DIRS_RENAMED -gt 0 ]]; then
    log "  ${YELLOW}~${RESET}  ${BOLD}$((FILES_RENAMED + DIRS_RENAMED)) name(s)${RESET} to fix  ${DIM}(illegal characters replaced with underscores)${RESET}"
fi
if [[ $WARNINGS -gt 0 ]]; then
    log "  ${RED}!${RESET}  ${BOLD}$WARNINGS path(s)${RESET} too long  ${DIM}(need manual shortening — see above)${RESET}"
fi
if [[ $EMPTY_COUNT -gt 0 ]]; then
    log "  ${DIM}o${RESET}  ${BOLD}$EMPTY_COUNT empty folder(s)${RESET}  ${DIM}(Egnyte will skip these)${RESET}"
fi

echo ""

if [[ $TOTAL_ACTIONS -eq 0 ]]; then
    log "  ${DIM}Nothing to fix automatically. See warnings above for manual fixes.${RESET}"
    echo ""
    rm -f "$LOG_FILE" 2>/dev/null
    exit 0
fi

echo -e "  ${BOLD}What would you like to do?${RESET}"
echo ""
echo -e "  ${BOLD}1)${RESET}  ${GREEN}Fix it${RESET} — apply all the changes listed above"
echo -e "  ${BOLD}2)${RESET}  ${YELLOW}Cancel${RESET} — don't change anything, I'll do it myself"
echo ""
read -r -p "  Enter 1 or 2: " ACTION_CHOICE

if [[ "$ACTION_CHOICE" != "1" ]]; then
    echo ""
    log "  ${YELLOW}No changes made.${RESET} Your files are exactly as they were."
    echo ""
    log "  ${DIM}You can run this tool again anytime.${RESET}"
    rm -f "$LOG_FILE" 2>/dev/null
    echo ""
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Apply changes
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
log "  ${CYAN}Applying changes...${RESET}"
echo ""

# Remove junk files
if [[ ${#JUNK_FILES[@]} -gt 0 ]]; then
    for file in "${JUNK_FILES[@]}"; do
        rm -rf "$file" 2>/dev/null
    done
    log "  ${GREEN}Removed $FILES_REMOVED junk file(s).${RESET}"
fi

# Apply renames
APPLIED_RENAMES=0
if [[ ${#RENAME_LIST[@]} -gt 0 ]]; then
    for entry in "${RENAME_LIST[@]}"; do
        oldpath="${entry%%|*}"
        newpath="${entry##*|}"
        if [[ -e "$oldpath" ]]; then
            mv "$oldpath" "$newpath" 2>/dev/null && ((APPLIED_RENAMES++))
        fi
    done
    log "  ${GREEN}Renamed $APPLIED_RENAMES file/folder name(s).${RESET}"
fi

# Handle empty folders
if [[ $EMPTY_COUNT -gt 0 ]]; then
    echo ""
    echo -e "  ${BOLD}About those empty folders:${RESET}"
    echo -e "  ${BOLD}1)${RESET}  Remove them"
    echo -e "  ${BOLD}2)${RESET}  Leave them as they are"
    echo ""
    read -r -p "  Enter 1 or 2: " EMPTY_CHOICE
    if [[ "$EMPTY_CHOICE" == "1" ]]; then
        find "$TARGET_PATH" -type d -empty -delete 2>/dev/null
        log "  ${GREEN}Removed $EMPTY_COUNT empty folder(s).${RESET}"
    else
        log "  ${DIM}Empty folders left as-is.${RESET}"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Done!
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo ""
log "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
log "  ${GREEN}${BOLD}All done!${RESET}"
log "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

if [[ $FILES_REMOVED -gt 0 ]]; then
    log "  ${GREEN}Removed${RESET}  $FILES_REMOVED invisible junk files"
fi
if [[ $APPLIED_RENAMES -gt 0 ]]; then
    log "  ${GREEN}Renamed${RESET}  $APPLIED_RENAMES files/folders with illegal characters"
fi
if [[ $WARNINGS -gt 0 ]]; then
    echo ""
    log "  ${YELLOW}Note:${RESET}  $WARNINGS file(s) have paths that are too long."
    log "  ${DIM}  These need to be shortened manually before uploading.${RESET}"
    log "  ${DIM}  Scroll up to see which ones.${RESET}"
fi

echo ""
log "  Your folder is ready to upload to Egnyte."
echo ""
log "  ${DIM}A log of everything that was changed has been saved to:${RESET}"
log "  ${DIM}$LOG_FILE${RESET}"
echo ""
log "  ${DIM}Questions? Contact your IT team or visit:${RESET}"
log "  ${DIM}https://helpdesk.egnyte.com/hc/en-us/articles/201637074${RESET}"
echo ""
