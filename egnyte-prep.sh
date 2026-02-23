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

# ─── Welcome ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║         Egnyte Upload Preparation Tool               ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "This tool prepares a folder for upload to Egnyte by:"
echo -e "  ${GREEN}1.${RESET} Removing macOS/Windows junk files (.DS_Store, Thumbs.db, etc.)"
echo -e "  ${GREEN}2.${RESET} Removing temp files that Egnyte would reject"
echo -e "  ${GREEN}3.${RESET} Renaming files/folders with illegal characters"
echo -e "  ${GREEN}4.${RESET} Fixing names that start/end with spaces or periods"
echo -e "  ${GREEN}5.${RESET} Warning about paths that exceed Egnyte limits"
echo ""

# ─── Get target path ─────────────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
    TARGET_PATH="$1"
else
    echo -e "${CYAN}Enter the path to the folder you want to prepare.${RESET}"
    echo -e "${DIM}Tip: You can drag and drop a folder from Finder into this window.${RESET}"
    echo ""
    read -r -p "Path: " TARGET_PATH
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
    echo -e "${RED}Error: '$TARGET_PATH' is not a valid directory.${RESET}"
    exit 1
fi

echo ""
echo -e "${BOLD}Target folder:${RESET} $TARGET_PATH"

# Count files/folders
TOTAL_FILES=$(find "$TARGET_PATH" -type f 2>/dev/null | wc -l | tr -d ' ')
TOTAL_DIRS=$(find "$TARGET_PATH" -type d 2>/dev/null | wc -l | tr -d ' ')
echo -e "${DIM}Found $TOTAL_FILES files and $TOTAL_DIRS folders${RESET}"
echo ""

# ─── Set up log file ─────────────────────────────────────────────────────────
LOG_FILE="$TARGET_PATH/egnyte-prep-log_$(date +%Y%m%d_%H%M%S).txt"

# ─── Dry run or execute? ─────────────────────────────────────────────────────
echo -e "${YELLOW}Choose a mode:${RESET}"
echo -e "  ${BOLD}1)${RESET} Preview  — show what would change (no files modified)"
echo -e "  ${BOLD}2)${RESET} Execute  — make the changes"
echo ""
read -r -p "Enter 1 or 2: " MODE_CHOICE

DRY_RUN=true
if [[ "$MODE_CHOICE" == "2" ]]; then
    DRY_RUN=false
    echo ""
    echo -e "${YELLOW}Are you sure? This will modify files in:${RESET}"
    echo -e "  $TARGET_PATH"
    read -r -p "Type 'yes' to confirm: " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo -e "${RED}Aborted.${RESET}"
        exit 0
    fi
fi

if $DRY_RUN; then
    echo ""
    log "${CYAN}═══ PREVIEW MODE (no changes will be made) ═══${RESET}"
else
    echo ""
    log "${GREEN}═══ EXECUTING CHANGES ═══${RESET}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 1: Remove junk and temp files
# ═══════════════════════════════════════════════════════════════════════════════
log "${BOLD}Phase 1: Removing junk and temp files${RESET}"
log "${DIM}────────────────────────────────────────${RESET}"

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

for pattern in "${JUNK_PATTERNS[@]}"; do
    while IFS= read -r -d '' file; do
        log "  ${RED}REMOVE${RESET} $file"
        if ! $DRY_RUN; then
            rm -rf "$file"
        fi
        ((FILES_REMOVED++))
    done < <(find "$TARGET_PATH" -name "$pattern" -print0 2>/dev/null)
done

# macOS resource fork files (._*)
while IFS= read -r -d '' file; do
    log "  ${RED}REMOVE${RESET} $file ${DIM}(resource fork)${RESET}"
    if ! $DRY_RUN; then
        rm -f "$file"
    fi
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" -name "._*" -type f -print0 2>/dev/null)

# Egnyte-rejected temp file patterns
# Files starting with .~ or ~$
while IFS= read -r -d '' file; do
    log "  ${RED}REMOVE${RESET} $file ${DIM}(temp file)${RESET}"
    if ! $DRY_RUN; then
        rm -f "$file"
    fi
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" \( -name ".~*" -o -name '~$*' -o -name '~*.$$$' \) -type f -print0 2>/dev/null)

# Files ending with .tmp, .ac$, .sv$
while IFS= read -r -d '' file; do
    basename=$(basename "$file")
    # Skip legitimate .tmp files that user might want — only remove Office temp patterns
    if [[ "$basename" =~ ^\~ ]] || [[ "$basename" =~ ^\.~ ]]; then
        log "  ${RED}REMOVE${RESET} $file ${DIM}(temp file)${RESET}"
        if ! $DRY_RUN; then
            rm -f "$file"
        fi
        ((FILES_REMOVED++))
    fi
done < <(find "$TARGET_PATH" \( -name "*.tmp" -o -name '*.ac$' -o -name '*.sv$' \) -type f -print0 2>/dev/null)

# AutoCAD lock files
while IFS= read -r -d '' file; do
    log "  ${RED}REMOVE${RESET} $file ${DIM}(lock file)${RESET}"
    if ! $DRY_RUN; then
        rm -f "$file"
    fi
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" \( -name "*.dwl" -o -name "*.dwl1" -o -name "*.dwl2" \) -type f -print0 2>/dev/null)

# Spotlight index files
while IFS= read -r -d '' file; do
    log "  ${RED}REMOVE${RESET} $file ${DIM}(spotlight index)${RESET}"
    if ! $DRY_RUN; then
        rm -rf "$file"
    fi
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" -name ".spotlight-*" -print0 2>/dev/null)

# Egnyte internal metadata patterns
while IFS= read -r -d '' file; do
    log "  ${RED}REMOVE${RESET} $file ${DIM}(egnyte metadata)${RESET}"
    if ! $DRY_RUN; then
        rm -f "$file"
    fi
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" \( -name "*._attribs_" -o -name "*._rights_" -o -name "*._egn_" -o -name "*_egnmeta" -o -name "_egn_.*" \) -type f -print0 2>/dev/null)

# SMB delete markers
while IFS= read -r -d '' file; do
    log "  ${RED}REMOVE${RESET} $file ${DIM}(smb marker)${RESET}"
    if ! $DRY_RUN; then
        rm -f "$file"
    fi
    ((FILES_REMOVED++))
done < <(find "$TARGET_PATH" -name ".smbdelete*" -type f -print0 2>/dev/null)

if [[ $FILES_REMOVED -eq 0 ]]; then
    log "  ${GREEN}No junk files found.${RESET}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 2: Rename files/folders with illegal characters
# ═══════════════════════════════════════════════════════════════════════════════
log "${BOLD}Phase 2: Fixing illegal characters in names${RESET}"
log "${DIM}────────────────────────────────────────────────${RESET}"

# Egnyte prohibited characters: \ / " : < > | * ?
# We process deepest paths first (bottom-up) so renames don't break parent paths

sanitize_name() {
    local name="$1"
    local original="$name"

    # Replace prohibited characters with underscore: \ / " : < > | * ?
    # Note: / can't appear in filenames on macOS, but handle it anyway
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

# Process files first (bottom-up by depth)
while IFS= read -r -d '' filepath; do
    dir=$(dirname "$filepath")
    basename=$(basename "$filepath")
    newname=$(sanitize_name "$basename")

    if [[ "$basename" != "$newname" ]]; then
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

        log "  ${YELLOW}RENAME${RESET} $basename"
        log "      ${GREEN}→${RESET} $newname"
        log "      ${DIM}in: $dir${RESET}"

        if ! $DRY_RUN; then
            mv "$filepath" "$newpath"
        fi
        ((FILES_RENAMED++))
    fi
done < <(find "$TARGET_PATH" -type f -print0 2>/dev/null | sort -rz)

# Process directories (bottom-up so children are renamed before parents)
while IFS= read -r -d '' dirpath; do
    [[ "$dirpath" == "$TARGET_PATH" ]] && continue

    parent=$(dirname "$dirpath")
    basename=$(basename "$dirpath")
    newname=$(sanitize_name "$basename")

    # Also check for folder names Egnyte rejects outright
    if [[ "$newname" == ".data" ]] || [[ "$newname" == ".tmp" ]]; then
        newname="_${newname}"
    fi

    if [[ "$basename" != "$newname" ]]; then
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

        log "  ${YELLOW}RENAME DIR${RESET} $basename"
        log "         ${GREEN}→${RESET} $newname"
        log "         ${DIM}in: $parent${RESET}"

        if ! $DRY_RUN; then
            mv "$dirpath" "$newpath"
        fi
        ((DIRS_RENAMED++))
    fi
done < <(find "$TARGET_PATH" -type d -print0 2>/dev/null | sort -rz)

if [[ $FILES_RENAMED -eq 0 ]] && [[ $DIRS_RENAMED -eq 0 ]]; then
    log "  ${GREEN}All names are Egnyte-compatible.${RESET}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 3: Check path length limits
# ═══════════════════════════════════════════════════════════════════════════════
log "${BOLD}Phase 3: Checking path length limits${RESET}"
log "${DIM}───────────────────────────────────────${RESET}"
log "${DIM}Egnyte limits: 245 chars per name, 5000 chars total path${RESET}"
log "${DIM}Office files: 215 chars max for full path${RESET}"
echo ""

OFFICE_EXTS="doc|docx|xls|xlsx|xlsm|ppt|pptx|rtf"

while IFS= read -r -d '' filepath; do
    # Get path relative to target (this is what Egnyte sees)
    relpath="${filepath#$TARGET_PATH/}"
    basename=$(basename "$filepath")
    namelen=${#basename}
    pathlen=${#relpath}

    # Check component length (245 char limit)
    if [[ $namelen -gt 245 ]]; then
        log "  ${RED}TOO LONG (name)${RESET} ${namelen} chars — $basename"
        log "      ${DIM}$relpath${RESET}"
        ((WARNINGS++))
    fi

    # Check total path length (5000 char limit)
    if [[ $pathlen -gt 5000 ]]; then
        log "  ${RED}TOO LONG (path)${RESET} ${pathlen} chars — $relpath"
        ((WARNINGS++))
    fi

    # Check Office file path limit (215 chars)
    ext="${basename##*.}"
    ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    if [[ "$ext_lower" =~ ^($OFFICE_EXTS)$ ]] && [[ $pathlen -gt 215 ]]; then
        log "  ${YELLOW}OFFICE WARNING${RESET} ${pathlen} chars (limit 215) — $basename"
        log "      ${DIM}$relpath${RESET}"
        ((WARNINGS++))
    fi
done < <(find "$TARGET_PATH" \( -type f -o -type d \) -print0 2>/dev/null)

if [[ $WARNINGS -eq 0 ]]; then
    log "  ${GREEN}All paths are within Egnyte limits.${RESET}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 4: Check for empty folders
# ═══════════════════════════════════════════════════════════════════════════════
log "${BOLD}Phase 4: Empty folders${RESET}"
log "${DIM}───────────────────────${RESET}"

EMPTY_COUNT=0
while IFS= read -r -d '' dir; do
    if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
        log "  ${DIM}EMPTY${RESET} $dir"
        ((EMPTY_COUNT++))
    fi
done < <(find "$TARGET_PATH" -type d -print0 2>/dev/null)

if [[ $EMPTY_COUNT -gt 0 ]]; then
    log "  ${DIM}Found $EMPTY_COUNT empty folder(s). Egnyte may skip these.${RESET}"
    if ! $DRY_RUN; then
        echo ""
        read -r -p "Remove empty folders? (y/n): " REMOVE_EMPTY
        if [[ "$REMOVE_EMPTY" == "y" ]]; then
            find "$TARGET_PATH" -type d -empty -delete 2>/dev/null
            log "  ${GREEN}Empty folders removed.${RESET}"
        fi
    fi
else
    log "  ${GREEN}No empty folders.${RESET}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
log "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
log "${BOLD}║                     Summary                          ║${RESET}"
log "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

if $DRY_RUN; then
    log "  ${CYAN}MODE: Preview only (no changes made)${RESET}"
else
    log "  ${GREEN}MODE: Changes applied${RESET}"
fi

log "  Files removed:    ${BOLD}$FILES_REMOVED${RESET}"
log "  Files renamed:    ${BOLD}$FILES_RENAMED${RESET}"
log "  Folders renamed:  ${BOLD}$DIRS_RENAMED${RESET}"
log "  Warnings:         ${BOLD}$WARNINGS${RESET}"
echo ""

if $DRY_RUN && [[ $((FILES_REMOVED + FILES_RENAMED + DIRS_RENAMED)) -gt 0 ]]; then
    log "${YELLOW}To apply these changes, run the script again and choose Execute.${RESET}"
    echo ""
fi

if [[ -n "$LOG_FILE" ]] && ! $DRY_RUN; then
    log "${DIM}Log saved to: $LOG_FILE${RESET}"
    echo ""
fi

log "${GREEN}Done! Your folder is ready for Egnyte upload.${RESET}"
echo ""
