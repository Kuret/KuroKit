# Links the addon folder into the WoW AddOns folder (a directory junction, no admin needed).
# Edits in this repo are then live in game after /reload.
#   pwsh tools\link.ps1            create the link
#   pwsh tools\link.ps1 -Remove    remove the link (only the link, never the repo files)
param(
    [string]$WowAddOns = 'C:\Games\World of Warcraft\_forever_\Interface\AddOns',
    [switch]$Remove
)
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '..\KuroKit' | Resolve-Path
$link = Join-Path $WowAddOns 'KuroKit'

if (Test-Path $link) {
    $item = Get-Item $link -Force
    if ($item.LinkType -ne 'Junction') { throw "$link exists and is not a junction; refusing to touch it." }
    if ($Remove) {
        $item.Delete()   # removes the junction itself, not the target's contents
        "Removed link $link"
        return
    }
    "Already linked: $link -> $($item.Target)"
    return
}
if ($Remove) { "No link at $link"; return }

New-Item -ItemType Junction -Path $link -Target $source | Out-Null
"Linked $link -> $source"
