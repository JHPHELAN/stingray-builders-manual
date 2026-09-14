#!/usr/bin/env bash
# Verify the integrity of a Tier-2 backup image pair on STORMYBAK.
# Chapter 20.4 companion to backup_disk.sh.
#
# Runs four independent integrity checks against a
# nvme_{boot,root}_DATE.img.gz pair, optionally cross-checking SHA-256
# against the Tier 4a copies on Hank Rearden's iCloudDrive.
#
# Usage:
#     bash /home/ubuntu/stingray-builders-manual/tools/verify_images.sh
#     bash .../verify_images.sh 2026-09-07                # verify a specific date
#     bash .../verify_images.sh --local-only              # skip iCloud cross-check
#     bash .../verify_images.sh 2026-09-07 --local-only
#     bash .../verify_images.sh --latest                  # newest pair on the HDD
#
# Alias (see Chapter 19.1):
#     alias verify='bash /home/ubuntu/stingray-builders-manual/tools/verify_images.sh'
#
# Checks (in order):
#   1. gzip -t  on nvme_boot_DATE.img.gz    (~5 sec)
#   2. gzip -t  on nvme_root_DATE.img.gz    (~3-15 min, depends on adapter)
#   3. sha256   local + Tier 4a compare     (~3-4 min for root)
#   4. fsck.exfat -n on /dev/sda1           (~15 sec, requires unmount)
#
# Exit status:
#     0 = all checks passed
#     1 = one or more checks failed

# NOTE: `-e` intentionally omitted - we want to run all checks even if
# earlier ones fail so the final report is complete.
set -uo pipefail

MOUNT_POINT="/mnt/backup"
BLOCK_DEV="/dev/sda1"
ICLOUD_HOST="hankrearden"
# cmd.exe-style path for the remote certutil hash.
ICLOUD_DIR='%USERPROFILE%\iCloudDrive\Stormy'

DATE_TAG="$(date +%F)"
USE_LATEST=0
DO_REMOTE=1

while [[ "${1:-}" != "" ]]; do
    case "$1" in
        --local-only) DO_REMOTE=0 ;;
        --latest)     USE_LATEST=1 ;;
        -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
        20[0-9][0-9]-[0-1][0-9]-[0-3][0-9]) DATE_TAG="$1" ;;
        *)            echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

say()  { printf "==> %s\n" "$*"; }
ok()   { printf "[OK]    %s\n" "$*"; }
warn() { printf "[WARN]  %s\n" "$*" >&2; }
fail() { printf "[FAIL]  %s\n" "$*" >&2; FAIL=1; }
FAIL=0

# Trigger x-systemd.automount if configured
ls "$MOUNT_POINT" >/dev/null 2>&1 || true
findmnt -t exfat "$MOUNT_POINT" >/dev/null 2>&1 \
    || { echo "ERROR: STORMYBAK is not mounted at $MOUNT_POINT (see Ch 20.4 A1)" >&2; exit 2; }

if [[ "$USE_LATEST" -eq 1 ]]; then
    LATEST=$(ls -1 "$MOUNT_POINT"/nvme_root_*.img.gz 2>/dev/null | sort | tail -1)
    [[ -n "$LATEST" ]] || { echo "ERROR: no nvme_root_*.img.gz files under $MOUNT_POINT" >&2; exit 2; }
    DATE_TAG=$(basename "$LATEST" | sed 's/^nvme_root_\(.*\)\.img\.gz$/\1/')
    say "--latest resolved to $DATE_TAG"
fi

BOOT_IMG="$MOUNT_POINT/nvme_boot_${DATE_TAG}.img.gz"
ROOT_IMG="$MOUNT_POINT/nvme_root_${DATE_TAG}.img.gz"
[[ -f "$BOOT_IMG" ]] || { echo "ERROR: $BOOT_IMG does not exist" >&2; exit 2; }
[[ -f "$ROOT_IMG" ]] || { echo "ERROR: $ROOT_IMG does not exist" >&2; exit 2; }

say "verify Tier-2 backup for $DATE_TAG"
echo

# --- 1 & 2. gzip -t ---
say "gzip -t (byte-level integrity)"
if gzip -t "$BOOT_IMG" 2>&1; then ok "gzip -t nvme_boot_${DATE_TAG}.img.gz"; else fail "gzip -t nvme_boot_${DATE_TAG}.img.gz"; fi
if gzip -t "$ROOT_IMG" 2>&1; then ok "gzip -t nvme_root_${DATE_TAG}.img.gz"; else fail "gzip -t nvme_root_${DATE_TAG}.img.gz"; fi
echo

# --- 3. sha256 local + remote cross-check ---
say "sha256 of local images"
LOCAL_HASH_BOOT=$(sha256sum "$BOOT_IMG" | awk '{print $1}')
LOCAL_HASH_ROOT=$(sha256sum "$ROOT_IMG" | awk '{print $1}')
say "  boot: $LOCAL_HASH_BOOT"
say "  root: $LOCAL_HASH_ROOT"

if [[ "$DO_REMOTE" -eq 1 ]]; then
    say "sha256 of Tier 4a copies on $ICLOUD_HOST (via certutil)"
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$ICLOUD_HOST" "exit 0" 2>/dev/null; then
        REMOTE_HASH_BOOT=$(ssh -o BatchMode=yes "$ICLOUD_HOST" \
            "certutil -hashfile \"${ICLOUD_DIR}\\nvme_boot_${DATE_TAG}.img.gz\" SHA256" 2>/dev/null \
            | tr -d '[:space:]\r' | grep -Eio '[0-9a-f]{64}' | head -1 | tr 'A-Z' 'a-z')
        REMOTE_HASH_ROOT=$(ssh -o BatchMode=yes "$ICLOUD_HOST" \
            "certutil -hashfile \"${ICLOUD_DIR}\\nvme_root_${DATE_TAG}.img.gz\" SHA256" 2>/dev/null \
            | tr -d '[:space:]\r' | grep -Eio '[0-9a-f]{64}' | head -1 | tr 'A-Z' 'a-z')
        if [[ -z "$REMOTE_HASH_BOOT" || -z "$REMOTE_HASH_ROOT" ]]; then
            fail "could not fetch remote hash (Tier 4a file missing on $ICLOUD_HOST?)"
        else
            say "  boot: $REMOTE_HASH_BOOT"
            say "  root: $REMOTE_HASH_ROOT"
            [[ "$LOCAL_HASH_BOOT" == "$REMOTE_HASH_BOOT" ]] \
                && ok "sha256 boot local == iCloud" \
                || fail "sha256 boot local != iCloud"
            [[ "$LOCAL_HASH_ROOT" == "$REMOTE_HASH_ROOT" ]] \
                && ok "sha256 root local == iCloud" \
                || fail "sha256 root local != iCloud"
        fi
    else
        warn "$ICLOUD_HOST not reachable via passwordless SSH; skipping remote cross-check"
    fi
else
    say "--local-only: skipping remote cross-check"
fi
echo

# --- 4. fsck.exfat -n ---
say "fsck.exfat -n on $BLOCK_DEV (read-only structural scan)"
# fsck.exfat wants the filesystem unmounted.  With x-systemd.automount this is
# safe - subsequent access to $MOUNT_POINT will trigger a fresh mount.
sudo umount "$MOUNT_POINT" 2>/dev/null || true
FSCK_LOG=$(mktemp)
if sudo fsck.exfat -n "$BLOCK_DEV" 2>&1 | tee "$FSCK_LOG"; then
    if grep -q ": clean\." "$FSCK_LOG"; then
        ok "fsck.exfat: clean"
    else
        fail "fsck.exfat reported an inconsistency"
    fi
else
    fail "fsck.exfat exited nonzero"
fi
rm -f "$FSCK_LOG"
# Re-touch to re-trigger automount so caller finds the drive available
ls "$MOUNT_POINT" >/dev/null 2>&1 || true
echo

# --- Summary ---
if [[ "$FAIL" -eq 0 ]]; then
    echo "VERIFY PASSED - $DATE_TAG backup is intact end-to-end"
    exit 0
else
    echo "VERIFY FAILED - see [FAIL] lines above" >&2
    exit 1
fi
