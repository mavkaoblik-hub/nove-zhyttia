$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'windows/hash.ps1')
. (Join-Path $root 'windows/results.ps1')
. (Join-Path $root 'windows/maintenance.ps1')
$temp=Join-Path $env:TEMP ('bridge-maintenance-test-'+[Guid]::NewGuid().ToString('N'))
$count=0
try{
 New-Item -ItemType Directory -Path (Join-Path $temp 'logs'),(Join-Path $temp 'output') -Force|Out-Null
 foreach($name in @('journal.jsonl','ui-journal.jsonl')){[IO.File]::WriteAllText((Join-Path $temp ('logs/'+$name)),('{"event":"fixture"}'+"`n"))}
 [IO.File]::WriteAllText((Join-Path $temp 'output/result.json'),'preserved')
 [IO.File]::WriteAllText((Join-Path $temp 'logs/other-audit.jsonl'),'preserved')
 $saved=ClearBridgeJournal $temp
 if($saved.files -ne 2){throw 'Expected two journal archives'};$count++
 foreach($name in @('journal.jsonl','ui-journal.jsonl')){
  if(Test-Path (Join-Path $temp ('logs/'+$name))){throw 'Journal not cleared'}
  if([IO.File]::ReadAllText((Join-Path $saved.archive $name)) -notmatch 'fixture'){throw 'Archive incomplete'};$count++
 }
 if([IO.File]::ReadAllText((Join-Path $temp 'output/result.json')) -ne 'preserved' -or [IO.File]::ReadAllText((Join-Path $temp 'logs/other-audit.jsonl')) -ne 'preserved'){throw 'Unrelated file changed'};$count++
 [IO.File]::AppendAllText((Join-Path $temp 'logs/journal.jsonl'),'new event')
 $second=ClearBridgeJournal $temp;if($second.archive -eq $saved.archive -or $second.files -ne 1){throw 'Repeated clear overwrote history'};$count++
 $cfg=[pscustomobject]@{ssh_key_path='C:\Keys With Space\owner.key';ssh_host_key_alias='pinned-host'}
 foreach($operation in @('status','reset')){
  $a=@(GetMcpMaintenanceArguments $cfg $operation)
  if($a -notcontains 'StrictHostKeyChecking=yes' -or $a -notcontains 'BatchMode=yes' -or $a -notcontains 'HostKeyAlias=pinned-host' -or $a[-1] -cne ('sudo -n python3 /opt/oracle-vm-work/maintenance/mcp_sessions_admin.py '+$operation)){throw 'SSH maintenance boundary changed'};$count++
 }
 foreach($operation in @('shell','reset; reboot','')){$denied=$false;try{$null=GetMcpMaintenanceArguments $cfg $operation}catch{$denied=$true};if(-not $denied){throw 'Unknown maintenance accepted'};$count++}
 $cfg.ssh_host_key_alias="bad`nvalue";$denied=$false;try{$null=GetMcpMaintenanceArguments $cfg 'reset'}catch{$denied=$true};if(-not $denied){throw 'Injected SSH parameter accepted'};$count++
 Write-Host ('PASS '+$count+' journal archive and pinned maintenance tests')
}finally{if($temp -notlike (Join-Path $env:TEMP 'bridge-maintenance-test-*')){throw 'Cleanup denied'};Remove-Item -LiteralPath $temp -Force -Recurse}
