# Prune Stormy rescue kits older than 28 days from Hank Rearden's
# Dropbox\Stormy\ folder.  See Chapter 20.6 of the Builder's Manual.
#
# Usage:
#   .\hank_prune_dropbox.ps1              # dry-run, prints what would go
#   .\hank_prune_dropbox.ps1 -Apply       # actually delete
#
# Schedule (one-time, on Hank Rearden):
#   Task Scheduler -> Create Basic Task
#     Name:    Prune Stormy Dropbox
#     Trigger: Weekly, Sunday 03:00
#     Action:  Start a program
#              Program:   powershell.exe
#              Arguments: -NoProfile -ExecutionPolicy Bypass -File
#                         "%USERPROFILE%\path\to\hank_prune_dropbox.ps1" -Apply
#
# Files matched:   %USERPROFILE%\Dropbox\Stormy\Stormy_Rescue_YYYY-MM-DD.tar.gz
# Retention:       28 days by default (override with -Days N)

[CmdletBinding()]
param(
    [switch]$Apply,
    [int]$Days = 28
)

$DropboxDir = Join-Path $env:USERPROFILE 'Dropbox\Stormy'

if (-not (Test-Path $DropboxDir)) {
    Write-Warning "Dropbox folder not found: $DropboxDir"
    exit 1
}

$cutoff = (Get-Date).AddDays(-$Days)

$victims = Get-ChildItem -Path $DropboxDir -Filter 'Stormy_Rescue_*.tar.gz' -File `
    | Where-Object { $_.LastWriteTime -lt $cutoff }

if ($victims.Count -eq 0) {
    Write-Host "Nothing to prune. Newest kit in $DropboxDir is fresh (< $Days days)."
    exit 0
}

Write-Host "Rescue kits older than $Days days (cutoff $($cutoff.ToString('yyyy-MM-dd'))):"
$victims | ForEach-Object {
    "{0,-40}  {1}  {2:N1} MB" -f $_.Name, $_.LastWriteTime.ToString('yyyy-MM-dd'), ($_.Length / 1MB) `
        | Write-Host
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "DRY RUN.  Re-run with -Apply to actually delete."
    exit 0
}

$victims | Remove-Item -Force
Write-Host ""
Write-Host "Deleted $($victims.Count) file(s)."
