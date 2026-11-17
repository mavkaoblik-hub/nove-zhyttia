param([switch]$Once)
$ErrorActionPreference='Stop'
$cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8|ConvertFrom-Json
$arguments=@('-N','-T','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o',('HostKeyAlias='+$cfg.ssh_host_key_alias),'-o','ExitOnForwardFailure=yes','-o','ServerAliveInterval=15','-o','ServerAliveCountMax=2','-L','127.0.0.1:18774:10.77.0.1:18773')
if($cfg.ssh_key_path){$arguments+=@('-o','IdentitiesOnly=yes','-i',$cfg.ssh_key_path)}
$arguments+='ubuntu@10.77.0.1'
foreach($a in $arguments){if($a -match '["\r\n]'){throw 'Unsafe SSH argument'}}
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=(Get-Command ssh.exe -ErrorAction Stop).Source
$info.Arguments=(($arguments|ForEach-Object {'"'+$_+'"'}) -join ' ')
$info.UseShellExecute=$false;$info.CreateNoWindow=$true
$transport=New-Object Diagnostics.Process;$transport.StartInfo=$info
$null=$transport.Start()
try{
 Start-Sleep -Seconds 2
 if($transport.HasExited){throw 'Pinned SSH forwarding failed; agent not started'}
 Write-Host 'MaVka Game Bridge: one agent, SSH transport over existing WireGuard. Ctrl+C or stop-agent.ps1 to stop.'
 & (Join-Path $PSScriptRoot 'agent.ps1') -Once:$Once
}finally{if(-not $transport.HasExited){$transport.Kill();$transport.WaitForExit()};$transport.Dispose()}
