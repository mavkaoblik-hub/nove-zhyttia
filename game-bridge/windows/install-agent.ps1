param([Parameter(Mandatory=$true)][string]$PackageSha256,[string]$Destination=(Join-Path $env:LOCALAPPDATA 'MaVkaGameBridge'),[string]$DeviceId='dev-pc',[string]$SshKeyPath='',[string]$HostKeyAlias='')
function Get-BridgeFileHash {
 param([Parameter(Mandatory=$true)][string]$LiteralPath,[string]$Algorithm='SHA256')
 if($Algorithm -ne 'SHA256'){throw 'Only SHA256 is supported'}
 $stream=[IO.File]::OpenRead($LiteralPath);$sha=[Security.Cryptography.SHA256]::Create()
 try{return [pscustomobject]@{Hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}}
 finally{$sha.Dispose();$stream.Dispose()}
}

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($DeviceId -notmatch '^[a-zA-Z0-9_-]{1,60}$'){throw 'Device ID'}
if(Test-Path -LiteralPath $Destination){throw 'Destination exists; preserve it and follow update/rollback instructions'}
# Trust anchor must be copied from the independently delivered release checksum.
if((Get-BridgeFileHash -LiteralPath (Join-Path $PSScriptRoot 'manifest.json')).Hash.ToLowerInvariant() -ne $PackageSha256.ToLowerInvariant()){throw 'Manifest hash mismatch'}
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($f in $manifest){
 if($f.name -notmatch '^[a-zA-Z0-9_.-]+$'){throw 'Manifest path'}
 if((Get-BridgeFileHash -LiteralPath (Join-Path $PSScriptRoot $f.name)).Hash.ToLowerInvariant() -ne $f.sha256){throw ('Hash mismatch '+$f.name)}
}
$null=Get-Command ssh.exe -ErrorAction Stop
if(-not $SshKeyPath -or -not $HostKeyAlias){
 $pluginRoot=Join-Path $env:USERPROFILE '.codex\plugins\cache\created-by-me-remote\oracle-vm-work'
 $existing=Get-ChildItem -LiteralPath $pluginRoot -Filter 'mcp.json' -Recurse -File|Sort-Object LastWriteTime -Descending|Select-Object -First 1
 if(-not $existing){throw 'Existing Oracle plugin configuration not found; supply SshKeyPath and HostKeyAlias explicitly'}
 $connection=(Get-Content -LiteralPath $existing.FullName -Raw -Encoding UTF8|ConvertFrom-Json).mcpServers.'oracle-vm'
 if($connection.args -notcontains 'ubuntu@10.77.0.1'){throw 'Unexpected SSH destination; provide explicit approved connection parameters'}
 for($i=0;$i -lt $connection.args.Count;$i++){
  if(-not $SshKeyPath -and $connection.args[$i] -eq '-i'){$SshKeyPath=$connection.args[$i+1]}
  if(-not $HostKeyAlias -and $connection.args[$i] -like 'HostKeyAlias=*'){$HostKeyAlias=$connection.args[$i].Substring(13)}
 }
 if(-not $SshKeyPath -or -not $HostKeyAlias){throw 'Pinned SSH parameters not found'}
}
$sshArgs=@('-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o',('HostKeyAlias='+$HostKeyAlias))
if($SshKeyPath){$sshArgs+=@('-o','IdentitiesOnly=yes','-i',$SshKeyPath)}
# Owner explicitly runs this installer. Reuses existing pinned SSH identity over WireGuard.
$secretJson=& ssh.exe @sshArgs 'ubuntu@10.77.0.1' ('sudo /usr/bin/python3 /opt/mavka-game-bridge/current/enroll.py '+$DeviceId)
if($LASTEXITCODE -ne 0){throw 'Enrollment failed; no host key acceptance or new SSH credentials are installed'}
$enrollment=($secretJson -join "`n")|ConvertFrom-Json
New-Item -ItemType Directory -Path $Destination|Out-Null
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
$acl.AddAccessRule($rule);Set-Acl -LiteralPath $Destination -AclObject $acl
foreach($f in $manifest){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f.name) -Destination $Destination}
foreach($dir in @('receipts','approvals','output','staging','logs')){New-Item -ItemType Directory -Path (Join-Path $Destination $dir)|Out-Null}
$secure=ConvertTo-SecureString $enrollment.key -AsPlainText -Force
$cred=New-Object Management.Automation.PSCredential($enrollment.principal,$secure)
$cred|Export-Clixml -LiteralPath (Join-Path $Destination 'device.credential.xml')
$cfg=Get-Content -LiteralPath (Join-Path $Destination 'config.example.json') -Raw -Encoding UTF8|ConvertFrom-Json
$cfg.device_id=$DeviceId;$cfg.principal=$enrollment.principal
$cfg.ssh_key_path=$SshKeyPath;$cfg.ssh_host_key_alias=$HostKeyAlias
$cfg|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Destination 'config.json') -Encoding UTF8
$secretJson=$null;$enrollment=$null;$secure=$null
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
$shortcutPath=Join-Path $desktop 'MaVka Game Bridge.lnk'
if(Test-Path -LiteralPath $shortcutPath){throw 'Desktop shortcut exists; preserve it before installing'}
$shell=New-Object -ComObject WScript.Shell
$shortcut=$shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shortcut.Arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $Destination 'MaVka-Game-Bridge.ps1')+'"'
$shortcut.WorkingDirectory=$Destination;$shortcut.Description='MaVka Game Bridge';$shortcut.Save()
Write-Host 'Installed without Windows autostart. Open MaVka Game Bridge from the Desktop shortcut.'
