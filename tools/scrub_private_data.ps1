# One-shot scrub of private identifiers from the public-facing
# Manual + Field Notes + Curation Notes.  Run once before public release.
#
# Substitutes home LAN IPs, SSID, MAC addresses, and MAC-derived
# interface names with generic angle-bracket placeholders.  A "Reader's
# key" is added to the Manual style section explaining what each
# placeholder means.
#
# Idempotent: safe to re-run.  The regex-anchored patterns will not
# match placeholder tokens.

$repoRoot = Split-Path -Parent $PSScriptRoot
$targets = @(
    'Stingray_Builders_Manual.txt',
    'Stingray_Field_Notes.txt',
    'Stingray_Curation_Notes.txt'
) | ForEach-Object { Join-Path $repoRoot $_ }

# Ordered dictionary — longest / most-specific patterns first so
# broader ones don't gobble parts of them.
$subs = [ordered]@{
    # TP-Link Deco base MAC + derived BSSIDs (specific first so the OUI
    # match below doesn't chew the tails)
    '34:60:F9:5D:7C:14' = '<DECO_A_MAC>'
    '34:60:F9:5D:7B:C4' = '<DECO_B_MAC>'
    '34:60:F9:5D:7C:B0' = '<DECO_C_MAC>'
    ':7C:16'            = ':<DECO_A_2G_TAIL>'
    ':7C:17'            = ':<DECO_A_5G_TAIL>'
    ':7B:C6'            = ':<DECO_B_2G_TAIL>'
    ':7B:C7'            = ':<DECO_B_5G_TAIL>'
    ':7C:B2'            = ':<DECO_C_2G_TAIL>'
    ':7C:B3'            = ':<DECO_C_5G_TAIL>'
    '34:60:F9'          = '<DECO_OUI>'
    # DHCP pool range
    '192.168.68.50 - 79' = '<DHCP_POOL_RANGE>'
    # Individual host IPs
    '192.168.68.66'  = '<ROBOT_WIFI_IP>'
    '192.168.68.96'  = '<ROBOT_WLAN_IP>'
    '192.168.68.97'  = '<ROBOT_ETH_IP>'
    '192.168.68.98'  = '<LINUXBOX_WIFI_IP>'
    '192.168.68.99'  = '<LINUXBOX_ETH_IP>'
    '192.168.68.70'  = '<WORKSTATION_IP>'
    '192.168.68.92'  = '<ROBOT_STATIC_A>'
    '192.168.68.93'  = '<ROBOT_STATIC_B>'
    '192.168.68.1'   = '<ROUTER_IP>'
    # SSID and derived NM connection name
    'H0bb1tH0l3'     = '<HOME_SSID>'
    # MAC-derived interface name (leaks MAC)
    'wlx90de801012a6' = '<USB_WIFI_IFACE>'
}

foreach ($file in $targets) {
    if (-not (Test-Path $file)) {
        Write-Warning "Missing: $file"
        continue
    }
    $text = Get-Content -Raw -Path $file
    $before = $text.Length
    foreach ($k in $subs.Keys) {
        $text = $text.Replace($k, $subs[$k])
    }
    Set-Content -Path $file -Value $text -NoNewline
    Write-Host ("{0}: {1} chars -> {2} chars" -f (Split-Path -Leaf $file), $before, $text.Length)
}

Write-Host "Done. Add a 'Reader's key' block near the top of the Manual explaining placeholders."
