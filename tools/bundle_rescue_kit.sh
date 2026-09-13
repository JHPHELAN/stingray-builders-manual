#!/usr/bin/env bash
# Bundle Stormy's non-git rescue kit for Tier-4b off-site backup.
# See Chapter 20.6 of Stingray_Builders_Manual.txt.
#
# Runs on Stormy.  Bundles only material that is not already in
# GitHub (Tier 1).  The three .txt companion documents live on
# Hank Rearden (Windows workspace, OneDrive-synced) and in the
# JHPHELAN/stingray-builders-manual GitHub repo, so they are NOT
# included here.
#
# Usage (safe to invoke by absolute path from anywhere):
#     bash /home/ubuntu/stingray-builders-manual/tools/bundle_rescue_kit.sh
#     bash .../bundle_rescue_kit.sh --dry-run
#     bash .../bundle_rescue_kit.sh --out /some/other/dir
#
# Or once the alias in ~/.bash_aliases is set (Chapter 19.1):
#     rescue
#     rescue --dry-run
#
# Output:
#     $OUT_DIR/Stormy_Rescue_YYYY-MM-DD.tar.gz  (default: $HOME)

set -euo pipefail

DRY_RUN=0
OUT_DIR="$HOME"

while [[ "${1:-}" != "" ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --out)     shift; OUT_DIR="$1" ;;
        -h|--help)
            sed -n '2,20p' "$0"; exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

DATE_TAG="$(date +%F)"
OUT_TARBALL="${OUT_DIR}/Stormy_Rescue_${DATE_TAG}.tar.gz"
STAGE_DIR="$(mktemp -d -t stormyrescue.XXXXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT

# --- Content sources on Stormy ---
WAV_DIR="$HOME/wav/active"          # only the production clips
DOTFILES_DIR="$HOME/stingray-dotfiles"
ARTICUBOT_DIR="$HOME/robot_ws/src/articubot_one"
MAPS_DIR="$ARTICUBOT_DIR/assets/maps"
CONFIG_DIR="$ARTICUBOT_DIR/robots/stingray/config"

echo "Staging rescue kit in $STAGE_DIR"

copy_if_present() {
    local src="$1" dst="$2"
    if [[ -e "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
        echo "  + $src"
    else
        echo "  - $src (missing, skipping)"
    fi
}

# 1. WAV files (only Stormy-side file set that is NOT in git anywhere).
copy_if_present "$WAV_DIR" "$STAGE_DIR/wav"

# 2. Dotfiles snapshot from live (refreshed first if the helper exists).
if [[ -x "$DOTFILES_DIR/sync-from-live.sh" ]]; then
    echo "Refreshing dotfiles snapshot from live..."
    ( cd "$DOTFILES_DIR" && ./sync-from-live.sh ) || \
        echo "  ! sync-from-live.sh reported an error; snapshotting current tree anyway"
fi
copy_if_present "$DOTFILES_DIR" "$STAGE_DIR/stingray-dotfiles"

# 3. Maps (git-tracked, but bundled as belt-and-braces).
for pattern in "Stormy_merged.*" "Stormy_blueprint.*"; do
    for f in $MAPS_DIR/$pattern; do
        [[ -e "$f" ]] && copy_if_present "$f" "$STAGE_DIR/maps/$(basename "$f")"
    done
done

# 4. Live yaml configs (git-tracked, but bundled as belt-and-braces).
copy_if_present "$CONFIG_DIR" "$STAGE_DIR/config"

# 5. Manifest.
{
    echo "Stormy rescue kit"
    echo "Generated: $(date -Iseconds)"
    echo "Host:      $(hostname)"
    echo "Kernel:    $(uname -r)"
    echo
    echo "Source paths on Stormy:"
    printf "  wav        %s\n" "$WAV_DIR"
    printf "  dotfiles   %s\n" "$DOTFILES_DIR"
    printf "  maps       %s\n" "$MAPS_DIR"
    printf "  config     %s\n" "$CONFIG_DIR"
    echo
    echo "NOT included in this bundle (already off-site elsewhere):"
    echo "  Stingray_Builders_Manual.txt   - GitHub + Hank Rearden OneDrive"
    echo "  Stingray_Field_Notes.txt       - GitHub + Hank Rearden OneDrive"
    echo "  Stingray_Curation_Notes.txt    - GitHub + Hank Rearden OneDrive"
    echo "  articubot_one code             - JHPHELAN/articubot_one on GitHub"
    echo "  roboclaw_driver fork           - JHPHELAN/roboclaw_driver on GitHub"
    echo
    echo "Contents:"
    ( cd "$STAGE_DIR" && find . -type f -printf '  %p  (%s bytes)\n' | sort )
} > "$STAGE_DIR/MANIFEST.txt"

# --- Bundle ---
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo
    echo "DRY RUN - staged contents follow (no tarball written):"
    ( cd "$STAGE_DIR" && find . -type f | sort )
    echo
    echo "Would have written: $OUT_TARBALL"
    exit 0
fi

echo "Writing $OUT_TARBALL"
tar -czf "$OUT_TARBALL" -C "$STAGE_DIR" .

gzip -t "$OUT_TARBALL" && echo "gzip integrity OK"
ls -lh "$OUT_TARBALL"

# Auto-prune local rescue kits older than 28 days.  Kept short:
# the Dropbox side keeps the canonical 4-week window; the local
# Stormy copy only needs the most recent generation for
# quick-restore purposes.
echo
echo "Pruning local Stormy_Rescue_*.tar.gz older than 28 days from $OUT_DIR..."
find "$OUT_DIR" -maxdepth 1 -type f -name 'Stormy_Rescue_*.tar.gz' -mtime +28 -print -delete || true

echo
echo "Next: FileZilla $OUT_TARBALL to Hank Rearden's"
echo "      %USERPROFILE%\\Dropbox\\Stormy\\ folder.  Dropbox-side"
echo "      pruning is handled by hank_prune_dropbox.ps1 on Hank"
echo "      Rearden (see Chapter 20.6)."
