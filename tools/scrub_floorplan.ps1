# Room-name scrub pass across all three .txt files.  Called after
# the private-data scrub.  Substitutes specific room names with
# generic descriptors where the context is a concrete floorplan
# reference (Deco unit location, pose table, WiFi survey, nav
# tuning example).
#
# Deliberately leaves narrative / biographical mentions alone
# ("study bookshelf" as scene-setting in Ch 1 is not floorplan
# disclosure).
#
# Idempotent: safe to re-run.

$repoRoot = Split-Path -Parent $PSScriptRoot
$targets = @(
    'Stingray_Curation_Notes.txt'   # already-scrubbed files re-scan is fine
) | ForEach-Object { Join-Path $repoRoot $_ }

# Concrete floorplan-binding substitutions.  Word-boundary based
# to avoid clobbering narrative uses of the word "study".
$patterns = @(
    # WiFi-survey rows (Chunk 17 area)
    @{ p = 'Study, on desk';           r = 'Room A, on desk' }
    @{ p = 'Study, floor';             r = 'Room A, floor' }
    @{ p = 'Study door';               r = 'Room A door' }
    @{ p = 'Hallway near stairs';      r = 'Central hallway (near stairs)' }
    @{ p = 'Hallway near dining';      r = 'Central hallway (near dining)' }
    @{ p = 'Kitchen entry';            r = 'Room D entry' }
    @{ p = 'Kitchen back door';        r = 'Room D back door' }
    # Deco unit locations
    @{ p = '(?<=Study\s{7,})';         r = ''; type = 'skip' }  # header table col
    @{ p = 'Study       <DECO_A_MAC>'; r = 'Node A     <DECO_A_MAC>' }
    @{ p = 'Sewing      <DECO_B_MAC> \(upstairs, over living\)';
       r = 'Node B     <DECO_B_MAC> (upstairs)' }
    @{ p = 'Breakfast   <DECO_C_MAC> \(moved from Master Closet';
       r = 'Node C     <DECO_C_MAC> (relocated 2026.07.10' }
    # Room-tied navigation example poses (Ch 14 / 6 mapping)
    @{ p = 'dock \(study\)';           r = 'dock (Room A)' }
    @{ p = 'bedroom door';             r = 'a bedroom door' }
    @{ p = 'inside bedroom';           r = 'inside a bedroom' }
    # Nav-tuning environmental references
    @{ p = 'kitchen island';           r = 'a feature-poor open area' }
    @{ p = 'the kitchen';              r = 'an open kitchen-like area' }
    @{ p = 'hall table';               r = 'a hallway feature' }
    # Bedroom numbering only in floorplan context
    @{ p = 'bedroom 2 and\s*(\r?\n\s+)bedroom 3 closet doors';
       r = 'two closet doors' }
    @{ p = 'French doors \(study,';    r = 'French doors (Room A,' }
)

foreach ($file in $targets) {
    if (-not (Test-Path $file)) { Write-Warning "Missing: $file"; continue }
    $text = Get-Content -Raw -Path $file
    $before = $text.Length
    foreach ($sub in $patterns) {
        if ($sub.type -eq 'skip') { continue }
        $text = [regex]::Replace($text, $sub.p, $sub.r)
    }
    Set-Content -Path $file -Value $text -NoNewline
    Write-Host ("{0}: {1} -> {2} chars" -f (Split-Path -Leaf $file), $before, $text.Length)
}
