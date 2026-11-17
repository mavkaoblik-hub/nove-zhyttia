param([Parameter(Mandatory=$true)][string]$JobId)
. (Join-Path $PSScriptRoot 'hash.ps1')
$ErrorActionPreference='Stop'
if($JobId -notmatch '^[a-zA-Z0-9_-]{1,80}$'){throw 'Job ID'}
$receipt=Join-Path $PSScriptRoot ('receipts\'+$JobId+'.json')
Get-Content -LiteralPath $receipt|Write-Host
if((Read-Host 'Type APPROVE to authorize this exact job') -cne 'APPROVE'){throw 'Not approved'}
(Get-BridgeFileHash -LiteralPath $receipt -Algorithm SHA256).Hash.ToLowerInvariant()|Set-Content -LiteralPath (Join-Path $PSScriptRoot ('approvals\'+$JobId+'.sha256')) -Encoding ASCII
