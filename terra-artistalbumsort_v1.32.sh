# =============================================================================
# TeRRaDude Artist album sorted for Archive (Recursive)
# =============================================================================
# Version: 1.32 FiNAL
# Date: 2026-01-09
# Author: TeRRaDuDe
#
# Changelog:
# - 1.16: Fixed artist name parsing to prevent release-title contamination
#          Ft/Feat removed, numeric artist folder optional, sandbox/logging retained
# - 1.17: Proper VA / VariousArtiest root mapping (bypassing alphabet folder)
# - 1.19: DJ / Dj trailing underscores removed
# - 1.29: Sandbox preview moves logged in MUSICSORTARCH log
# - 1.30: Additional VA handling for releases starting with "VA-" but not VariousArtiest,
#          optional numeric artist mapping preserved, full Ft/Feat cleanup, code structure fully retained
# - 1.31: Added optional recursive scanning of UNSORTED_DIR subdirectories
# - 1.32: FIX: always move releases to BASE_DIR, not relative UNSORTED subpaths
#
# Compatible:
#   Debian 12 and above
#
# Note:
#  Please take note that these scripts come without instructions on how to set
#  them up, it is sole responsibility of the end user to understand the scripts
#  function before executing them. If you do not know how to execute them, then
#  please don't use them. They come with no warranty should any damage happen due
#  to the improper settings and execution of these scripts (missing data, etc).
#
# =============================================================================


BASE_DIR="/glftpd/site/ARCHiVE/MUSiC"          # Directory where the archive wil be created
UNSORTED_DIR="/glftpd/site/MP3/"               # Directory of music before sorting
DUP_DIR="$BASE_DIR/DUPLICATES"                 # Here you will find in your archive directory DUPES
LOG_FILE="/glftpd/ftp-data/logs/storttoarchive-test.log" 
EXCLUDE_PATHS=("/PRE" "/GROUPS") 
SANDBOX_MODE=true                              # true = do not move (only log simulation) | false = it will created and move stuff
VA_DIR_NAME="VA"                               # Optional setting to have Various Artitst in "/VA" or "/VariousArtiest" instead of "/V"
NUMERIC_TO_FOLDER="0-9"                        # Optional to have numeric albums 1 directory "/0-9" | leave empty to disable numeric-artist folder
RECURSIVE_UNSORTED=false                       # false = scan only one directory | true = scan all subdirectories under UNSORTED_DIR


#========================== END OF CONFIG ========================================
##################################################################################
#=================================================================================
# Logging function
log() {
    local section="$1"
    local directory="$2"
    echo "`date "+%a %b %e %T %Y"` MUSICSORTARCH: \"$section\" \"$directory\"" >> "$LOG_FILE"
}

log_done() {
    echo "`date "+%a %b %e %T %Y"` MUSICSORTDONE: \"$1\"" >> "$LOG_FILE"
}

# Check if path is excluded
is_excluded() {
    local path="$1"
    for excl in "${EXCLUDE_PATHS[@]}"; do
        if [[ "$path" == *"$excl"* ]]; then
            return 0
        fi
    done
    return 1
}

# Extract artist name from release
get_artist() {
    local release="$1"

    # Strip enclosing parentheses around artist name
    if [[ "$release" == \(*\)* ]]; then
        local artist="${release#\(}"
        artist="${artist%%\)*}"
        echo "$artist"
        return
    fi

    # ===== VA detection (case-insensitive) =====
    if [[ "$release" =~ ^([Vv][Aa]|V\.A\.|Various[_-]?Artists?|Various[_-]?Artiest)([^A-Za-z0-9].*|$) ]]; then
        echo "$VA_DIR_NAME"
        return
    fi

    # Handle DJ / Dj prefix
    if [[ "$release" =~ ^(DJ[_-][A-Za-z0-9_]+|Dj[_-][A-Za-z0-9_]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi

    # Handle Van_ prefix
    if [[ "$release" =~ ^(Van_[A-Za-z0-9_]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi

    # Handle numeric artist prefixes (0-9, 2-4_Grooves, etc.)
    if [[ "$release" =~ ^([0-9]+[-_0-9]*[A-Za-z_]*) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi

    # Generic multiword artist: take everything before first dash only
    if [[ "$release" =~ ^([^-]+) ]]; then
        local artist="${BASH_REMATCH[1]}"
        artist="${artist%_}" # remove trailing underscore if present
        echo "$artist"
        return
    fi

    # Fallback
    echo "Unknown"
}

# Normalize artist name (CamelCase + underscores), but only artist part
normalize_artist() {
    local input="$1"

    # lowercase
    input=$(echo "$input" | tr '[:upper:]' '[:lower:]')

    # remove brackets
    input=$(echo "$input" | sed -E 's/[\(\)\[\]\{\}]//g')

    # replace non-alphanumeric with _
    input=$(echo "$input" | sed -E 's/[^a-z0-9]+/_/g')

    # collapse multiple underscores
    input=$(echo "$input" | sed -E 's/_+/_/g')

    # trim leading/trailing _
    input=$(echo "$input" | sed -E 's/^_|_$//g')

    # Remove Ft / Feat / Featuring if at the end
    input=$(echo "$input" | sed -E 's/(_|-)(Ft|ft|Feat|feat|Featuring|featuring|Vs|VS|vs|Pres|pres|Presents|presents|f|With|with|X)(_|$).*//')

    # Capitalize each word
    IFS="_" read -r -a parts <<< "$input"
    output=""
    for part in "${parts[@]}"; do
        first=$(echo "$part" | cut -c1 | tr '[:lower:]' '[:upper:]')
        rest=$(echo "$part" | cut -c2-)
        output+="${first}${rest}_"
    done

    # remove trailing underscore
    output="${output%_}"

    echo "$output"
}

# Determine paths to scan
if [[ "$RECURSIVE_UNSORTED" == true ]]; then
    # Use find to traverse all subdirectories
    mapfile -t release_paths < <(find "$UNSORTED_DIR" -mindepth 1 -type d)
else
    release_paths=("$UNSORTED_DIR"/*)
fi

# Main loop
processed=0
for release_path in "${release_paths[@]}"; do
    [[ ! -d "$release_path" ]] && continue
    release_name=$(basename "$release_path")

    # Skip excluded paths
    is_excluded "$release_path" && continue

    # Determine artist
    artist=$(get_artist "$release_name")

    # Normalize and cleanup
    artist="${artist%_}"
    artist=$(normalize_artist "$artist")

    # ===== VA / VA- releases mapping =====
    if [[ "$artist" == "$VA_DIR_NAME" || "$release_name" =~ ^VA[-_] ]]; then
        artist_dir="$BASE_DIR/$VA_DIR_NAME"
    else
        # Optional numeric bucket
        if [[ "$NUMERIC_TO_FOLDER" != "" && "$artist" =~ ^[0-9] ]]; then
            first_char="$NUMERIC_TO_FOLDER"
        else
            first_char="${artist:0:1}"
        fi
        artist_dir="$BASE_DIR/$first_char/$artist"
    fi

    if [[ "$SANDBOX_MODE" == false ]]; then
        mkdir -p "$artist_dir"
        chmod 777 "$artist_dir"

        if [[ -d "$artist_dir/$release_name" ]]; then
            mkdir -p "$DUP_DIR"
            mv "$release_path" "$DUP_DIR/"
        else
            mv "$release_path" "$artist_dir/"
        fi
    else
        # Dry-run: preview move to log file
        echo "`date "+%a %b %e %T %Y"` MUSICSORTARCH: [PREVIEW MOVE] \"$release_path\" --> \"$artist_dir/$release_name\"" >> "$LOG_FILE"
    fi

    log "$artist" "$release_path"
    processed=$((processed + 1))
done

log_done "$processed releases processed and archived"
exit 0
