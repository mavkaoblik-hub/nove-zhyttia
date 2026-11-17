param([switch]$RemoveData)
$ErrorActionPreference='Stop'
$uiMutex=New-Object Threading.Mutex($false,'Local\MaVkaGameBridgeUI')
if(-not $uiMutex.WaitOne(0)){throw 'Close MaVka Game Bridge window before uninstalling'}
$uiMutex.ReleaseMutex();$uiMutex.Dispose()
& (Join-Path $PSScriptRoot 'stop-agent.ps1')
$cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8|ConvertFrom-Json
$m=New-Object Threading.Mutex($false,('Local\MaVkaGameBridge_'+$cfg.device_id))
if(-not $m.WaitOne(0)){throw 'Agent is stopping. Retry uninstall after it exits.'}
$m.ReleaseMutex();$m.Dispose()
Remove-Item -LiteralPath (Join-Path $PSScriptRoot 'device.credential.xml') -Force -ErrorAction SilentlyContinue
$shortcutPath=Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'MaVka Game Bridge.lnk'
if(Test-Path -LiteralPath $shortcutPath){
 $shell=New-Object -ComObject WScript.Shell;$link=$shell.CreateShortcut($shortcutPath)
 if($link.Arguments.Contains((Join-Path $PSScriptRoot 'MaVka-Game-Bridge.ps1'))){Remove-Item -LiteralPath $shortcutPath -Force}
}
if($RemoveData){
 $expected=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'MaVkaGameBridge'))
 if([IO.Path]::GetFullPath($PSScriptRoot) -ne $expected){throw 'Automatic deletion only allowed for the default installation directory'}
 if((Get-ChildItem -LiteralPath $expected -Force -Recurse|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint})){throw 'Reparse point; deletion denied'}
 Set-Location $env:TEMP;Remove-Item -LiteralPath $expected -Recurse -Force
}
Write-Host 'Credential removed. Revoke the device on Oracle too. No service, task, firewall or registry entry was installed.'
