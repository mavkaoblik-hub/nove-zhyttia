param([Parameter(Mandatory=$true)][string]$PackageSha256,[string]$Destination=(Join-Path $env:LOCALAPPDATA 'MaVkaGameBridge'))
$ErrorActionPreference='Stop'
function TrustedHash([string]$File){$s=[IO.File]::OpenRead($File);$h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash($s))).Replace('-','').ToLowerInvariant()}finally{$s.Dispose();$h.Dispose()}}
if([IO.Path]::GetFullPath($PSScriptRoot) -eq [IO.Path]::GetFullPath($Destination)){throw 'Run updater from the separate verified release package'}
if((TrustedHash (Join-Path $PSScriptRoot 'manifest.json')) -ne $PackageSha256.ToLowerInvariant()){throw 'Manifest integrity'}
$files=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($file in $files){
 if($file.name -notmatch '^[a-zA-Z0-9_.-]+$' -or $file.name -in @('config.json','approval-policy.json','device.credential.xml','active.json','STOP','EXIT')){throw 'Protected local state in package'}
 if((TrustedHash (Join-Path $PSScriptRoot $file.name)) -ne $file.sha256){throw 'Package file integrity'}
}
New-Item -ItemType File -Force -Path (Join-Path $Destination 'EXIT')|Out-Null
New-Item -ItemType File -Force -Path (Join-Path $Destination 'STOP')|Out-Null
$mutex=New-Object Threading.Mutex($false,'Local\MaVkaGameBridgeUI');$deadline=[DateTime]::UtcNow.AddSeconds(45);$acquired=$false
try{while(-not($acquired=$mutex.WaitOne(0))){if([DateTime]::UtcNow -gt $deadline){throw 'Close the older Bridge window, then retry update'};Start-Sleep -Seconds 1}}finally{if($acquired){$mutex.ReleaseMutex()};$mutex.Dispose()}
$cfg=Get-Content -LiteralPath (Join-Path $Destination 'config.json') -Raw -Encoding UTF8|ConvertFrom-Json
$agentMutex=New-Object Threading.Mutex($false,('Local\MaVkaGameBridge_'+$cfg.device_id))
try{if(-not $agentMutex.WaitOne(0)){throw 'Agent still stopping; no files changed'};$agentMutex.ReleaseMutex()}finally{$agentMutex.Dispose()}
$backup=Join-Path $Destination ('code-backup-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8));New-Item -ItemType Directory -Path $backup|Out-Null
Copy-Item -LiteralPath (Join-Path $Destination 'config.json') -Destination $backup
$changed=@();$created=@()
try{
 foreach($file in $files){
  $target=Join-Path $Destination $file.name
  if(Test-Path -LiteralPath $target){Copy-Item -LiteralPath $target -Destination $backup}else{$created+=$target}
  $changed+=$file.name;Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file.name) -Destination $target -Force
 }
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Destination (Join-Path $Destination 'manifest.json') -Force
 foreach($file in $files){if((TrustedHash (Join-Path $Destination $file.name)) -ne $file.sha256){throw 'Installed hash mismatch'}}
}catch{
 foreach($name in $changed){$saved=Join-Path $backup $name;if(Test-Path -LiteralPath $saved){Copy-Item -LiteralPath $saved -Destination (Join-Path $Destination $name) -Force}}
 foreach($newFile in $created){if(Test-Path -LiteralPath $newFile){Remove-Item -LiteralPath $newFile -Force}}
 throw
}
Remove-Item -LiteralPath (Join-Path $Destination 'EXIT') -Force -ErrorAction SilentlyContinue
$exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Start-Process -FilePath $exe -ArgumentList ('-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $Destination 'MaVka-Game-Bridge.ps1')+'"') -WindowStyle Hidden
Write-Host 'Bridge updated; previous code retained. Project permissions and credential preserved.'
