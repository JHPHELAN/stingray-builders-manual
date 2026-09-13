#!/usr/bin/env bash
# Daily backup status check for Stormy.
# See Chapter 20.6 of Stingray_Builders_Manual.txt.
#
# Reports the age of each backup tier, warns when any are stale,
# and (optionally) generates the Tier-4b rescue kit for you.
#
# Usage (safe to invoke by absolute path from anywhere):
#     bash /home/ubuntu/stingray-builders-manual/tools/backup_check.sh
#     bash .../backup_check.sh --prune          # delete Tier 4b tarballs > 28 days
#     bash .../backup_check.sh --json           # machine-readable output only
#
# Or via alias (see Chapter 19.1):
#     backup
#
# When a WARN row tells you the rescue kit is stale, generate a new
# one with the separate `rescue` command (which invokes
# bundle_rescue_kit.sh).  The two verbs are deliberately non-overlapping:
#   backup   = status report + prune
#   rescue   = generate the Tier-4b tarball
#
# Exit status:
#     0 = every tier fresh
#     1 = at least one tier is stale or missing
#     2 = script usage error

set -euo pipefail

# --- Freshness thresholds (days).  Adjust here if cadence changes. ---
TIER1_WARN_DAYS=2      # daily commits per Ch 20.1
TIER2_WARN_DAYS=8      # weekly HDD image per Ch 20.4
TIER4A_WARN_DAYS=32    # monthly iCloud copy per Ch 20.6
TIER4B_WARN_DAYS=8     # weekly Dropbox rescue kit per Ch 20.6

# --- Where to look ---
ARTICUBOT_DIR="$HOME/robot_ws/src/articubot_one"
DOTFILES_DIR="$HOME/stingray-dotfiles"
STORMYBAK_MOUNT="/mnt/backup"
STATE_DIR="$HOME/.stormy"
TIER4A_STATE="$STATE_DIR/last_icloud_copy"
RESCUE_DIR="$HOME"                          # where bundle_rescue_kit.sh writes

DO_PRUNE=0
JSON_ONLY=0

while [[ "${1:-}" != "" ]]; do
    case "$1" in
        --prune)  DO_PRUNE=1 ;;
        --json)   JSON_ONLY=1 ;;
        -h|--help)
            sed -n '2,30p' "$0"; exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

mkdir -p "$STATE_DIR"

# --- Helpers ---
days_since_epoch()  { echo $(( $(date +%s) / 86400 )); }
days_since_file()   {
    [[ -e "$1" ]] || { echo -1; return; }
    local file_epoch mtime_days now_days
    file_epoch=$(stat -c %Y "$1")
    mtime_days=$(( file_epoch / 86400 ))
    now_days=$(days_since_epoch)
    echo $(( now_days - mtime_days ))
}
status_line() {
    local tier="$1" msg="$2" state="$3"
    if [[ "$JSON_ONLY" -eq 1 ]]; then
        JSON_ROWS+=("\"$tier\": {\"state\": \"$state\", \"detail\": \"$msg\"}")
    else
        case "$state" in
            OK)    printf "  \e[32m[OK]\e[0m    %-8s %s\n" "$tier" "$msg" ;;
            WARN)  printf "  \e[33m[WARN]\e[0m  %-8s %s\n" "$tier" "$msg" ;;
            FAIL)  printf "  \e[31m[FAIL]\e[0m  %-8s %s\n" "$tier" "$msg" ;;
        esac
    fi
}

JSON_ROWS=()
OVERALL_STATE=0

# --- Tier 1: uncommitted / unpushed state in the main git repos ---
check_git_repo() {
    local repo="$1" tier="$2"
    if [[ ! -d "$repo/.git" ]]; then
        status_line "$tier" "no repo at $repo" FAIL
        OVERALL_STATE=1
        return
    fi
    local dirty ahead last_commit_epoch days
    dirty=$(git -C "$repo" status --porcelain | wc -l)
    ahead=$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
    last_commit_epoch=$(git -C "$repo" log -1 --format=%ct 2>/dev/null || echo 0)
    days=$(( ($(date +%s) - last_commit_epoch) / 86400 ))
    if [[ "$dirty" -gt 0 || "$ahead" -gt 0 ]]; then
        status_line "$tier" "$repo: $dirty uncommitted, $ahead unpushed (last commit ${days}d ago) - run: cd $repo && git add -A && git commit -m '...' && git push" WARN
        OVERALL_STATE=1
    elif (( days > TIER1_WARN_DAYS )); then
        status_line "$tier" "$repo: clean, but last commit ${days}d ago (>${TIER1_WARN_DAYS}d) - if you have local work, commit and push it" WARN
        OVERALL_STATE=1
    else
        status_line "$tier" "$repo: clean, last commit ${days}d ago" OK
    fi
}
check_git_repo "$ARTICUBOT_DIR" "Tier1"
check_git_repo "$DOTFILES_DIR"  "Tier1"

# --- Tier 2: latest STORMYBAK image if the HDD is currently mounted ---
if mountpoint -q "$STORMYBAK_MOUNT"; then
    latest_boot=$(ls -1t "$STORMYBAK_MOUNT"/nvme_root_*.img.gz 2>/dev/null | head -n1 || true)
    if [[ -n "${latest_boot:-}" ]]; then
        days=$(days_since_file "$latest_boot")
        if (( days > TIER2_WARN_DAYS )); then
            status_line "Tier2" "$latest_boot is ${days}d old (>${TIER2_WARN_DAYS}d) - run Chapter 20.4 Section A on this HDD" WARN
            OVERALL_STATE=1
        else
            status_line "Tier2" "$latest_boot is ${days}d old" OK
        fi
    else
        status_line "Tier2" "STORMYBAK mounted but no nvme_root_*.img.gz found - run Chapter 20.4 Section A" FAIL
        OVERALL_STATE=1
    fi
else
    status_line "Tier2" "STORMYBAK not mounted - plug in the HDD and rerun 'backup' to check age" WARN
fi

# --- Tier 4a: iCloud monthly (tracked via state stamp file) ---
if [[ -e "$TIER4A_STATE" ]]; then
    days=$(days_since_file "$TIER4A_STATE")
    if (( days > TIER4A_WARN_DAYS )); then
        status_line "Tier4a" "iCloud copy stamp is ${days}d old (>${TIER4A_WARN_DAYS}d) - FileZilla the latest STORMYBAK img.gz pair to Hank Rearden's %USERPROFILE%\\iCloudDrive\\Stormy\\, then on Stormy run: touch $TIER4A_STATE" WARN
        OVERALL_STATE=1
    else
        status_line "Tier4a" "iCloud copy stamp is ${days}d old" OK
    fi
else
    status_line "Tier4a" "no stamp file - do the first iCloud copy (Ch 20.6 Tier 4a workflow), then run: mkdir -p $STATE_DIR && touch $TIER4A_STATE" WARN
    OVERALL_STATE=1
fi

# --- Tier 4b: latest local Stormy_Rescue tarball ---
latest_rescue=$(ls -1t "$RESCUE_DIR"/Stormy_Rescue_*.tar.gz 2>/dev/null | head -n1 || true)
if [[ -n "${latest_rescue:-}" ]]; then
    days=$(days_since_file "$latest_rescue")
    if (( days > TIER4B_WARN_DAYS )); then
        status_line "Tier4b" "$latest_rescue is ${days}d old (>${TIER4B_WARN_DAYS}d) - run: rescue" WARN
        OVERALL_STATE=1
    else
        status_line "Tier4b" "$latest_rescue is ${days}d old" OK
    fi
else
    status_line "Tier4b" "no Stormy_Rescue_*.tar.gz in $RESCUE_DIR - run: rescue" WARN
    OVERALL_STATE=1
fi

# --- Optional actions ---
if [[ "$DO_PRUNE" -eq 1 ]]; then
    echo
    echo "Pruning Stormy_Rescue_*.tar.gz older than 28 days from $RESCUE_DIR..."
    find "$RESCUE_DIR" -maxdepth 1 -type f -name 'Stormy_Rescue_*.tar.gz' -mtime +28 -print -delete
fi

if [[ "$JSON_ONLY" -eq 1 ]]; then
    printf '{ %s }\n' "$(IFS=,; echo "${JSON_ROWS[*]}")"
fi

exit "$OVERALL_STATE"
