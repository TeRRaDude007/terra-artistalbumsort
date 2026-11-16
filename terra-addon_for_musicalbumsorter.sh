#!/bin/bash
###############################################################################
# TeRRaDude Music Directory Cleanup 
#
# Version: 1.3.0
# Platform: Debian 13
#
# Description: 
#   Addon for terra-artistalbumsort_XXX.sh script to turn after this.
#   Organizes music album directories under the correct main artist directory.
#   Supports ALBUMS root directories and category directories such as:
#   _0-9, 0-9, _A, A, B, C, VA, etc.
#  
#
# Features:
#   - Case-insensitive artist matching
#   - Dots, spaces and underscores treated as equivalent
#   - Existing artist directory spelling is preserved
#   - New artist directories use canonical title-case spelling
#   - Handles "_-_" artist/release separators
#   - Handles normal hyphen artist/release separators
#   - Handles three-digit artist prefixes
#   - Handles "_And_" artist matching
#   - Matches existing artist prefixes, longest match first
#   - Duplicate album directories are renamed, never overwritten
#   - Empty source directories are moved to cleanup directory
#   - SANDBOX_MODE for safe testing
#
# Version history:
#   1.3.0 - Added case-insensitive matching and canonical artist naming
#           Added dot/space/underscore normalization
#           Improved three-digit artist matching
#           Improved existing artist prefix matching
#   1.2.3 - Previous matching and cleanup functionality
#
###############################################################################

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------

ALBUMS_DIR="/glftpd/site/ARCHiVE/ALBUMS"

CLEANUP_DIR_NAME="_Cleaned_Music_Directorys"

LOG_FILE="/glftpd/ftp-data/logs/music_cleanup.log"

SANDBOX_MODE=true
DIR_PERMISSIONS="777"

# ---------------------------------------------------------------------------
# INTERNAL VARIABLES / END OF CONIG
# ---------------------------------------------------------------------------

TOTAL_SCANNED=0
TOTAL_MATCHED=0
TOTAL_MOVED=0
TOTAL_CREATED=0
TOTAL_DUPLICATES=0
TOTAL_SKIPPED=0
TOTAL_CLEANED=0

NORMALIZED_ARTIST=""
CANONICAL_ARTIST=""
MAIN_ARTIST=""
MAIN_ARTIST_PATH=""
ALBUM_MATCH_NAME=""
ALLOW_CREATE=0

# ---------------------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------------------

log_message()
{
    local MESSAGE="$1"
    local TIMESTAMP

    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$TIMESTAMP] $MESSAGE"

    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$TIMESTAMP] $MESSAGE" >> "$LOG_FILE"
}

is_category_directory()
{
    local DIR_NAME
    DIR_NAME=$(basename "$1")

    [[ "$DIR_NAME" =~ ^_?[A-Za-z]$ ]] && return 0
    [[ "$DIR_NAME" =~ ^_?0-9$ ]] && return 0
    [[ "${DIR_NAME,,}" == "va" ]] && return 0

    return 1
}

normalize_artist_name()
{
    local NAME="$1"

    NAME="${NAME,,}"
    NAME="${NAME//./_}"
    NAME="${NAME// /_}"

    while [[ "$NAME" == *"__"* ]]; do
        NAME="${NAME//__/_}"
    done

    NAME="${NAME#_}"
    NAME="${NAME%_}"

    NORMALIZED_ARTIST="$NAME"
}

canonical_artist_name()
{
    local NAME="$1"
    local TOKEN
    local RESULT=""

    normalize_artist_name "$NAME"
    NAME="$NORMALIZED_ARTIST"

    local IFS="_"

    for TOKEN in $NAME; do
        [[ -z "$TOKEN" ]] && continue

        TOKEN="${TOKEN,,}"
        TOKEN="${TOKEN^}"

        [[ -n "$RESULT" ]] && RESULT+="_"
        RESULT+="$TOKEN"
    done

    CANONICAL_ARTIST="$RESULT"
}

find_existing_artist()
{
    local SCOPE="$1"
    local SEARCH_NAME="$2"
    local DIR
    local DIR_NAME
    local SEARCH_NORMALIZED

    MAIN_ARTIST_PATH=""

    normalize_artist_name "$SEARCH_NAME"
    SEARCH_NORMALIZED="$NORMALIZED_ARTIST"

    for DIR in "$SCOPE"/*/; do
        [[ -d "$DIR" ]] || continue

        DIR_NAME=$(basename "$DIR")

        [[ "$DIR_NAME" == "$CLEANUP_DIR_NAME" ]] && continue

        if [[ "$SCOPE" == "$ALBUMS_DIR" ]] &&
           is_category_directory "$DIR_NAME"; then
            continue
        fi

        normalize_artist_name "$DIR_NAME"

        if [[ "$NORMALIZED_ARTIST" == "$SEARCH_NORMALIZED" ]]; then
            MAIN_ARTIST="$DIR_NAME"
            MAIN_ARTIST_PATH="${DIR%/}"
            return 0
        fi
    done

    return 1
}

is_album_directory()
{
    local ALBUM_NAME="$1"
    local MATCH_NAME="$2"
    local ALBUM_NORMALIZED
    local MATCH_NORMALIZED
    local REMAINDER

    normalize_artist_name "$ALBUM_NAME"
    ALBUM_NORMALIZED="$NORMALIZED_ARTIST"

    normalize_artist_name "$MATCH_NAME"
    MATCH_NORMALIZED="$NORMALIZED_ARTIST"

    [[ -z "$MATCH_NORMALIZED" ]] && return 1

    [[ "$ALBUM_NORMALIZED" == "$MATCH_NORMALIZED" ]] && return 0

    if [[ "$ALBUM_NORMALIZED" == "$MATCH_NORMALIZED"* ]]; then
        REMAINDER="${ALBUM_NORMALIZED#"$MATCH_NORMALIZED"}"

        [[ "$REMAINDER" == _* ]] && return 0
    fi

    return 1
}

find_main_artist()
{
    local SCOPE="$1"
    local SOURCE_NAME="$2"
    local PREFIX=""
    local DIR
    local DIR_NAME
    local DIR_NORMALIZED
    local SOURCE_NORMALIZED
    local BEST_MATCH=""
    local BEST_LENGTH=0
    local CURRENT_LENGTH

    MAIN_ARTIST=""
    MAIN_ARTIST_PATH=""
    ALBUM_MATCH_NAME="$SOURCE_NAME"
    ALLOW_CREATE=0

    if [[ "$SOURCE_NAME" == *"_-"* ]]; then
        PREFIX="${SOURCE_NAME%%_-_*}"

        if [[ -n "$PREFIX" ]]; then
            if find_existing_artist "$SCOPE" "$PREFIX"; then
                return 0
            fi

            canonical_artist_name "$PREFIX"
            MAIN_ARTIST="$CANONICAL_ARTIST"
            ALLOW_CREATE=1
            return 0
        fi
    fi

    if [[ "$SOURCE_NAME" == *"-"* ]]; then
        PREFIX="${SOURCE_NAME%%-*}"

        if [[ -n "$PREFIX" ]]; then
            if find_existing_artist "$SCOPE" "$PREFIX"; then
                return 0
            fi

            canonical_artist_name "$PREFIX"
            MAIN_ARTIST="$CANONICAL_ARTIST"
            ALLOW_CREATE=1
            return 0
        fi
    fi

    if [[ "$SOURCE_NAME" =~ ^([0-9]{3})_ ]]; then
        PREFIX="${BASH_REMATCH[1]}"
        ALBUM_MATCH_NAME="$PREFIX"

        if find_existing_artist "$SCOPE" "$PREFIX"; then
            return 0
        fi

        MAIN_ARTIST="$PREFIX"
        ALLOW_CREATE=1
        return 0
    fi

    if [[ "$SOURCE_NAME" =~ ^(.*)_[Aa][Nn][Dd]_ ]]; then
        PREFIX="${BASH_REMATCH[1]}"

        if [[ -n "$PREFIX" ]]; then
            if find_existing_artist "$SCOPE" "$PREFIX"; then
                return 0
            fi

            canonical_artist_name "$PREFIX"
            MAIN_ARTIST="$CANONICAL_ARTIST"
            ALLOW_CREATE=1
            return 0
        fi
    fi

    normalize_artist_name "$SOURCE_NAME"
    SOURCE_NORMALIZED="$NORMALIZED_ARTIST"

    for DIR in "$SCOPE"/*/; do
        [[ -d "$DIR" ]] || continue

        DIR_NAME=$(basename "$DIR")

        [[ "$DIR_NAME" == "$CLEANUP_DIR_NAME" ]] && continue

        if [[ "$SCOPE" == "$ALBUMS_DIR" ]] &&
           is_category_directory "$DIR_NAME"; then
            continue
        fi

        normalize_artist_name "$DIR_NAME"
        DIR_NORMALIZED="$NORMALIZED_ARTIST"

        [[ -z "$DIR_NORMALIZED" ]] && continue

        if [[ "$SOURCE_NORMALIZED" == "$DIR_NORMALIZED"_* ]]; then
            CURRENT_LENGTH=${#DIR_NORMALIZED}

            if (( CURRENT_LENGTH > BEST_LENGTH )); then
                BEST_LENGTH=$CURRENT_LENGTH
                BEST_MATCH="$DIR_NAME"
            fi
        fi
    done

    if [[ -n "$BEST_MATCH" ]]; then
        MAIN_ARTIST="$BEST_MATCH"
        MAIN_ARTIST_PATH="$SCOPE/$BEST_MATCH"
        return 0
    fi

    return 1
}

create_main_artist()
{
    local DESTINATION="$1"

    if [[ "$SANDBOX_MODE" == true ]]; then
        log_message "SANDBOX: WOULD CREATE ARTIST DIRECTORY: $DESTINATION"
        return 0
    fi

    if mkdir -m "$DIR_PERMISSIONS" -p "$DESTINATION"; then
        chmod "$DIR_PERMISSIONS" "$DESTINATION"
        log_message "CREATED ARTIST DIRECTORY: $DESTINATION"
        ((TOTAL_CREATED++))
        return 0
    fi

    log_message "ERROR: COULD NOT CREATE ARTIST DIRECTORY: $DESTINATION"
    return 1
}

get_destination()
{
    local DEST_DIR="$1"
    local ALBUM_NAME="$2"
    local DESTINATION="$DEST_DIR/$ALBUM_NAME"
    local COUNTER=1

    while [[ -e "$DESTINATION" ]]; do
        DESTINATION="$DEST_DIR/${ALBUM_NAME}__DUPLICATE_${COUNTER}"
        ((COUNTER++))
    done

    echo "$DESTINATION"
}

cleanup_source_directory()
{
    local SOURCE_DIR="$1"
    local SCOPE="$2"
    local CLEANUP_DIR="$SCOPE/$CLEANUP_DIR_NAME"
    local SOURCE_NAME
    local DESTINATION
    local COUNTER=1

    [[ -d "$SOURCE_DIR" ]] || return 0

    if [[ -n "$(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        return 0
    fi

    SOURCE_NAME=$(basename "$SOURCE_DIR")

    if [[ "$SANDBOX_MODE" == true ]]; then
        log_message "SANDBOX: WOULD MOVE EMPTY DIRECTORY TO CLEANUP: $SOURCE_DIR"
        ((TOTAL_CLEANED++))
        return 0
    fi

    mkdir -m "$DIR_PERMISSIONS" -p "$CLEANUP_DIR"
    chmod "$DIR_PERMISSIONS" "$CLEANUP_DIR"

    DESTINATION="$CLEANUP_DIR/$SOURCE_NAME"

    while [[ -e "$DESTINATION" ]]; do
        DESTINATION="$CLEANUP_DIR/${SOURCE_NAME}__${COUNTER}"
        ((COUNTER++))
    done

    if mv "$SOURCE_DIR" "$DESTINATION"; then
        chmod "$DIR_PERMISSIONS" "$DESTINATION"
        log_message "MOVED EMPTY DIRECTORY TO CLEANUP: $DESTINATION"
        ((TOTAL_CLEANED++))
    else
        log_message "ERROR: COULD NOT MOVE EMPTY DIRECTORY: $SOURCE_DIR"
    fi
}

process_artist()
{
    local SCOPE="$1"
    local SOURCE_DIR="$2"
    local SOURCE_NAME
    local ALBUM_DIR
    local ALBUM_NAME
    local DESTINATION
    local MATCH_COUNT=0
    local MOVED_COUNT=0

    SOURCE_NAME=$(basename "$SOURCE_DIR")

    ((TOTAL_SCANNED++))

    [[ "$SOURCE_NAME" == "$CLEANUP_DIR_NAME" ]] && return 0

    if ! find_main_artist "$SCOPE" "$SOURCE_NAME"; then
        log_message "NO MAIN ARTIST FOUND: $SOURCE_NAME"
        ((TOTAL_SKIPPED++))
        return 0
    fi

    log_message "SOURCE DIRECTORY: $SOURCE_NAME"
    log_message "EXPECTED MAIN ARTIST: $MAIN_ARTIST"
    log_message "ALBUM MATCH PREFIX: $ALBUM_MATCH_NAME"

    for ALBUM_DIR in "$SOURCE_DIR"/*/; do
        [[ -d "$ALBUM_DIR" ]] || continue

        ALBUM_NAME=$(basename "$ALBUM_DIR")

        if is_album_directory "$ALBUM_NAME" "$ALBUM_MATCH_NAME"; then
            ((MATCH_COUNT++))
        fi
    done

    if (( MATCH_COUNT == 0 )); then
        log_message "NO MATCHING ALBUMS FOUND: $SOURCE_NAME"
        ((TOTAL_SKIPPED++))
        return 0
    fi

    ((TOTAL_MATCHED+=MATCH_COUNT))

    if [[ -z "$MAIN_ARTIST_PATH" ]]; then
        MAIN_ARTIST_PATH="$SCOPE/$MAIN_ARTIST"

        if [[ "$ALLOW_CREATE" -ne 1 ]]; then
            log_message "ERROR: ARTIST DIRECTORY NOT FOUND: $MAIN_ARTIST_PATH"
            return 1
        fi

        create_main_artist "$MAIN_ARTIST_PATH" || return 1
    fi

    if [[ "$SOURCE_DIR" == "$MAIN_ARTIST_PATH" ]]; then
        log_message "SOURCE IS ALREADY MAIN ARTIST DIRECTORY: $SOURCE_NAME"
        return 0
    fi

    for ALBUM_DIR in "$SOURCE_DIR"/*/; do
        [[ -d "$ALBUM_DIR" ]] || continue

        ALBUM_NAME=$(basename "$ALBUM_DIR")

        if ! is_album_directory "$ALBUM_NAME" "$ALBUM_MATCH_NAME"; then
            continue
        fi

        DESTINATION=$(get_destination "$MAIN_ARTIST_PATH" "$ALBUM_NAME")

        if [[ "$DESTINATION" != "$MAIN_ARTIST_PATH/$ALBUM_NAME" ]]; then
            ((TOTAL_DUPLICATES++))
            log_message "DUPLICATE FOUND: $ALBUM_NAME"
            log_message "DUPLICATE DESTINATION: $DESTINATION"
        fi

        if [[ "$SANDBOX_MODE" == true ]]; then
            log_message "SANDBOX: WOULD MOVE: $ALBUM_DIR"
            log_message "SANDBOX: WOULD MOVE TO: $DESTINATION"
            ((MOVED_COUNT++))
            continue
        fi

        if mv "$ALBUM_DIR" "$DESTINATION"; then
            log_message "MOVED ALBUM: $ALBUM_NAME"
            log_message "DESTINATION: $DESTINATION"
            ((TOTAL_MOVED++))
            ((MOVED_COUNT++))
        else
            log_message "ERROR: FAILED TO MOVE: $ALBUM_DIR"
        fi
    done

    if (( MOVED_COUNT > 0 )); then
        cleanup_source_directory "$SOURCE_DIR" "$SCOPE"
    fi
}

process_scope()
{
    local SCOPE="$1"
    local SOURCE_DIR
    local SOURCE_NAME

    [[ -d "$SCOPE" ]] || return 0

    log_message "============================================================"
    log_message "SCANNING SCOPE: $SCOPE"
    log_message "============================================================"

    for SOURCE_DIR in "$SCOPE"/*/; do
        [[ -d "$SOURCE_DIR" ]] || continue

        SOURCE_NAME=$(basename "$SOURCE_DIR")

        [[ "$SOURCE_NAME" == "$CLEANUP_DIR_NAME" ]] && continue

        if [[ "$SCOPE" == "$ALBUMS_DIR" ]] &&
           is_category_directory "$SOURCE_NAME"; then
            continue
        fi

        process_artist "$SCOPE" "${SOURCE_DIR%/}"
    done
}

main()
{
    local DIR
    local DIR_NAME

    if [[ ! -d "$ALBUMS_DIR" ]]; then
        echo "ERROR: ALBUMS DIRECTORY DOES NOT EXIST: $ALBUMS_DIR"
        exit 1
    fi

    log_message "============================================================"
    log_message "MUSIC DIRECTORY CLEANUP STARTED"
    log_message "VERSION: 1.3.0"
    log_message "ALBUMS DIRECTORY: $ALBUMS_DIR"
    log_message "SANDBOX MODE: $SANDBOX_MODE"
    log_message "============================================================"

    DIR_NAME=$(basename "$ALBUMS_DIR")

    if is_category_directory "$DIR_NAME"; then
        process_scope "$ALBUMS_DIR"
    else
        process_scope "$ALBUMS_DIR"

        for DIR in "$ALBUMS_DIR"/*/; do
            [[ -d "$DIR" ]] || continue

            DIR_NAME=$(basename "$DIR")

            if is_category_directory "$DIR_NAME"; then
                process_scope "${DIR%/}"
            fi
        done
    fi

    log_message "============================================================"
    log_message "MUSIC DIRECTORY CLEANUP FINISHED"
    log_message "============================================================"
    log_message "TOTAL DIRECTORIES SCANNED: $TOTAL_SCANNED"
    log_message "TOTAL ALBUMS MATCHED: $TOTAL_MATCHED"
    log_message "TOTAL ALBUMS MOVED: $TOTAL_MOVED"
    log_message "TOTAL ARTIST DIRECTORIES CREATED: $TOTAL_CREATED"
    log_message "TOTAL DUPLICATES FOUND: $TOTAL_DUPLICATES"
    log_message "TOTAL DIRECTORIES SKIPPED: $TOTAL_SKIPPED"
    log_message "TOTAL EMPTY DIRECTORIES CLEANED: $TOTAL_CLEANED"
    log_message "============================================================"
}

main "$@"

