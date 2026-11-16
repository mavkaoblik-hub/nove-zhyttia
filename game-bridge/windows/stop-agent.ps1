$ErrorActionPreference='Stop'
New-Item -ItemType File -Force -Path (Join-Path $PSScriptRoot 'STOP')|Out-Null
Write-Host 'Stop requested. Running tool is stopped by the agent polling loop. Remove STOP to permit a later manual restart.'
