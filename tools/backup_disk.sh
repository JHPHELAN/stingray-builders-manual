#!/usr/bin/env bash
# Automated Tier-2 full-disk backup runner for Stormy.
# See Chapter 20.4 of Stingray_Builders_Manual.txt.
#
# Runs the whole Section A workflow in one command:
#   - sanity-check the mounted STORMYBAK HDD
#   - dd|gzip the boot partition, verify with gzip -t
#   - dd|gzip the root partition, verify with gzip -t
#   - append a row to BACKUPS.md, commit, push
#   - (--icloud)        scp both images to Hank Rearden's
#                       iCloudDrive\Stormy\ folder and reset Tier 4a stamp
#   - (--icloud-only)   skip dd|gzip; verify + upload today's ALREADY-EXISTING
#                       images (recovery from a failed --icloud run,
#                       or deferred Tier 4a upload)
#
# Usage (safe to invoke by absolute path from anywhere):
#     bash /home/ubuntu/stingray-builders-manual/tools/backup_disk.sh
#     bash .../backup_disk.sh --dry-run
#     bash .../backup_disk.sh --note "Quick text for the notes column"
#     bash .../backup_disk.sh --no-push          # skip git commit + push
#     bash .../backup_disk.sh --icloud           # also do Tier 4a upload
#     bash .../backup_disk.sh --icloud-only      # upload existing images only
#
# Or via alias (see Chapter 19.1):
#     alias diskbackup='bash /home/ubuntu/stingray-builders-manual/tools/backup_disk.sh'
#
# Prerequisites:
#   - STORMYBAK USB HDD is plugged in and mounted at /mnt/backup
#   - BACKUPS.md is tracked in a git checkout at $MANUAL_REPO_DIR
#   - Passwordless git push is configured (SSH key added to GitHub)
#   - For --icloud, passwordless SSH to `hankrearden` is configured
#     (see Chapter 20.6 install steps)
#
# Exit status:
#     0 = both partitions imaged, verified, and logged
#     1 = a step failed - see stderr; BACKUPS.md is NOT updated

set -euo pipefail

DRY_RUN=0
DO_PUSH=1
DO_ICLOUD=0
ICLOUD_ONLY=0
NOTE=""

while [[ "${1:-}" != "" ]]; do
    case "$1" in
        --dry-run)     DRY_RUN=1 ;;
        --no-push)     DO_PUSH=0 ;;
        --icloud)      DO_ICLOUD=1 ;;
        --icloud-only) DO_ICLOUD=1; ICLOUD_ONLY=1 ;;
        --note)        shift; NOTE="$1" ;;
        -h|--help)     sed -n '2,36p' "$0"; exit 0 ;;
        *)             echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# --- Configuration (edit if your layout differs) ---
BOOT_DEV="/dev/nvme0n1p1"
ROOT_DEV="/dev/nvme0n1p2"
MOUNT_POINT="/mnt/backup"
MANUAL_REPO_DIR="$HOME/stingray-builders-manual"
BACKUPS_MD="$MANUAL_REPO_DIR/BACKUPS.md"
DATE_TAG="$(date +%F)"
BOOT_IMG="$MOUNT_POINT/nvme_boot_${DATE_TAG}.img.gz"
ROOT_IMG="$MOUNT_POINT/nvme_root_${DATE_TAG}.img.gz"

# --- Sanity checks ---
say() { echo "==>" "$@"; }
die() { echo "ERROR:" "$@" >&2; exit 1; }

[[ -b "$BOOT_DEV" ]] || die "boot partition $BOOT_DEV missing"
[[ -b "$ROOT_DEV" ]] || die "root partition $ROOT_DEV missing"
mountpoint -q "$MOUNT_POINT" || die "$MOUNT_POINT is not mounted; plug in STORMYBAK and mount it first (see Ch 20.4 Section A4)"
[[ -d "$MANUAL_REPO_DIR/.git" ]] || die "no git checkout at $MANUAL_REPO_DIR (needed for BACKUPS.md automation)"
[[ -f "$BACKUPS_MD" ]] || die "BACKUPS.md not found at $BACKUPS_MD"

# Existing-image policy depends on mode.
if [[ "$ICLOUD_ONLY" -eq 1 ]]; then
    # --icloud-only: today's images must already exist; we reuse them.
    [[ -f "$BOOT_IMG" ]] || die "--icloud-only requires $BOOT_IMG to exist (run diskbackup without --icloud-only first)"
    [[ -f "$ROOT_IMG" ]] || die "--icloud-only requires $ROOT_IMG to exist (run diskbackup without --icloud-only first)"
elif [[ -f "$BOOT_IMG" || -f "$ROOT_IMG" ]]; then
    die "images already exist for $DATE_TAG at $MOUNT_POINT.  Move or delete them first, or use --icloud-only to just upload them."
fi

# Raw partition sizes (bytes) for the throughput calculation.
BOOT_RAW=$(sudo blockdev --getsize64 "$BOOT_DEV")
ROOT_RAW=$(sudo blockdev --getsize64 "$ROOT_DEV")

pretty_size() {
    # Format bytes as human-readable (base-10 for MB, base-2 for GiB threshold).
    local b=$1
    if (( b < 1024*1024*1024 )); then
        printf "%.0f MB" "$(echo "scale=2; $b/1048576" | bc)"
    else
        printf "%.1f GiB" "$(echo "scale=2; $b/1073741824" | bc)"
    fi
}
BOOT_RAW_H=$(pretty_size "$BOOT_RAW")
ROOT_RAW_H=$(pretty_size "$ROOT_RAW")

say "STORMYBAK mounted at $MOUNT_POINT"

if [[ "$ICLOUD_ONLY" -eq 1 ]]; then
    say "--icloud-only: reusing existing images (skipping dd|gzip and BACKUPS.md)"
    say "  $BOOT_IMG  ($(sudo stat -c %s "$BOOT_IMG" | numfmt --to=iec --suffix=B))"
    say "  $ROOT_IMG  ($(sudo stat -c %s "$ROOT_IMG" | numfmt --to=iec --suffix=B))"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        say "DRY RUN - would gzip -t both, then scp to hankrearden:iCloudDrive/Stormy/"
        exit 0
    fi
    say "gzip -t $BOOT_IMG"
    sudo gzip -t "$BOOT_IMG" || die "$BOOT_IMG failed gzip -t; refusing to upload a corrupt file"
    say "gzip -t $ROOT_IMG"
    sudo gzip -t "$ROOT_IMG" || die "$ROOT_IMG failed gzip -t; refusing to upload a corrupt file"
else

say "Boot: $BOOT_DEV -> $BOOT_IMG   ($BOOT_RAW_H raw)"
say "Root: $ROOT_DEV -> $ROOT_IMG   ($ROOT_RAW_H raw)"

if [[ "$DRY_RUN" -eq 1 ]]; then
    say "DRY RUN - would dd|gzip both partitions and append a row to BACKUPS.md"
    exit 0
fi

# --- Boot partition (~2 min) ---
say "Imaging boot partition..."
t_boot=$(date +%s)
sudo sh -c "dd if=$BOOT_DEV bs=4M conv=sync,noerror status=progress | gzip -1 > $BOOT_IMG"
sudo sync
dt_boot=$(( $(date +%s) - t_boot ))
say "gzip -t $BOOT_IMG"
sudo gzip -t "$BOOT_IMG"
BOOT_GZ_SIZE=$(sudo stat -c %s "$BOOT_IMG")
BOOT_GZ_H=$(pretty_size "$BOOT_GZ_SIZE")

# --- Root partition (~40 min) ---
say "Imaging root partition..."
t_root=$(date +%s)
sudo sh -c "dd if=$ROOT_DEV bs=4M conv=sync,noerror status=progress | gzip -1 > $ROOT_IMG"
sudo sync
dt_root=$(( $(date +%s) - t_root ))
say "gzip -t $ROOT_IMG"
sudo gzip -t "$ROOT_IMG"
ROOT_GZ_SIZE=$(sudo stat -c %s "$ROOT_IMG")
ROOT_GZ_H=$(pretty_size "$ROOT_GZ_SIZE")

# --- Throughput (root partition is the meaningful signal) ---
if (( dt_root > 0 )); then
    MB_PER_S=$(echo "scale=0; $ROOT_RAW / 1048576 / $dt_root" | bc)
else
    MB_PER_S="?"
fi

# --- Detect USB link speed of the adapter (best-effort) ---
LINK_SPEED="?"
if command -v lsusb >/dev/null 2>&1; then
    if sudo lsusb -t 2>/dev/null | grep -qE '5000M'; then
        LINK_SPEED="USB 3.0"
    elif sudo lsusb -t 2>/dev/null | grep -qE '480M'; then
        LINK_SPEED="USB 2.0"
    fi
fi

say "Boot: raw ${BOOT_RAW_H}, gz ${BOOT_GZ_H}, dt ${dt_boot}s"
say "Root: raw ${ROOT_RAW_H}, gz ${ROOT_GZ_H}, dt ${dt_root}s"
say "Throughput: ${MB_PER_S} MB/s (${LINK_SPEED})"

# --- Append row to BACKUPS.md and push ---
ROW="| $DATE_TAG | $BOOT_RAW_H / $BOOT_GZ_H     | $ROOT_RAW_H / $ROOT_GZ_H     | ${MB_PER_S} MB/s (${LINK_SPEED}) | \`gzip -t\` OK on both | ${NOTE} |"

say "Appending to BACKUPS.md:"
echo "$ROW"

# Append the row.  Assumes the file already has a header row + separator.
printf '%s\n' "$ROW" >> "$BACKUPS_MD"

if [[ "$DO_PUSH" -eq 1 ]]; then
    say "git add / commit / push in $MANUAL_REPO_DIR"
    ( cd "$MANUAL_REPO_DIR" && \
      git pull --rebase --quiet && \
      git add BACKUPS.md && \
      git commit -m "backup: Tier-2 image $DATE_TAG (${MB_PER_S} MB/s)" && \
      git push )
    say "BACKUPS.md pushed to origin"
else
    say "--no-push: skipped git commit/push.  Row is appended locally."
fi

fi  # end of "not --icloud-only" fresh-backup block

# --- Optional Tier 4a upload to Hank Rearden's iCloudDrive ---
if [[ "$DO_ICLOUD" -eq 1 ]]; then
    say "Tier 4a: uploading images to hankrearden:iCloudDrive/Stormy/"
    if ssh -o BatchMode=yes -o ConnectTimeout=5 hankrearden "exit 0" 2>/dev/null; then
        if scp -o BatchMode=yes -o ConnectTimeout=10 \
               "$BOOT_IMG" "$ROOT_IMG" hankrearden:iCloudDrive/Stormy/ ; then
            say "Uploaded.  iCloud will sync to cloud in the background (~15-30 min)."
            # Reset the Tier 4a stamp so backup_check.sh knows we're fresh.
            mkdir -p "$HOME/.stormy"
            touch "$HOME/.stormy/last_icloud_copy"
            say "Tier 4a stamp reset: $HOME/.stormy/last_icloud_copy"
        else
            echo "WARN: scp to hankrearden failed.  Images are local at $MOUNT_POINT;" >&2
            echo "      FileZilla them to %USERPROFILE%\\iCloudDrive\\Stormy\\ manually," >&2
            echo "      then run: touch $HOME/.stormy/last_icloud_copy" >&2
        fi
    else
        echo "WARN: hankrearden not reachable via passwordless SSH." >&2
        echo "      Images are local at $MOUNT_POINT; FileZilla them" >&2
        echo "      to %USERPROFILE%\\iCloudDrive\\Stormy\\ manually," >&2
        echo "      then run: touch $HOME/.stormy/last_icloud_copy" >&2
    fi
fi

say "Done."
