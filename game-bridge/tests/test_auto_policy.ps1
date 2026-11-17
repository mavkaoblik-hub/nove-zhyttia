$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach($name in @('hash.ps1','results.ps1','approval.ps1','auto-trust.ps1')){. (Join-Path $root ('windows/'+$name))}
$temp=Join-Path $env:TEMP ('bridge-auto-test-'+[Guid]::NewGuid().ToString('N'))
$id='a'*32;$revision='b'*40;$stage=Join-Path $temp ('staging\'+$id+'\'+$revision)
New-Item -ItemType Directory -Path $stage -Force|Out-Null
$count=0
function Check($Value,[string]$Label){if(-not $Value){throw $Label};$script:count++}
try{
 [IO.File]::WriteAllText((Join-Path $stage 'project.godot'),'config_version=5')
 [IO.File]::WriteAllText((Join-Path $stage 'test.gd'),'extends SceneTree')
 $policy=[pscustomobject]@{enabled=$true;project_id=$id;delay_seconds=5}
 $cfg=[pscustomobject]@{project_id=$id;projects=@([pscustomobject]@{id=$id;enabled=$true;remote_open_enabled=$true});approved_scripts=@()}
 $task=[pscustomobject]@{action='files.push';revision_sha=$revision;arguments=[pscustomobject]@{project_id=$id;script_id='test'}}
 foreach($action in @('files.push','files.pull','files.publish','gui.blender.open','workspace.stage_revision','godot.project.inspect')){
  $task.action=$action;Check (TestAutoApproval $policy $cfg $task $true $temp) ('Allowed action denied '+$action)
 }
 $task.action='files.push';$task.arguments.project_id='c'*32;Check (-not(TestAutoApproval $policy $cfg $task $true $temp)) 'Foreign transfer accepted';$task.arguments.project_id=$id
 foreach($action in @('scripts.register','shell','unknown','godot.project.validate')){$task.action=$action;Check (-not(TestAutoApproval $policy $cfg $task $true $temp)) ('New code accepted '+$action)}
 $task.action='godot.project.validate';SaveAutoWorkspaceTrust $cfg $task $temp
 Check (TestAutoApproval $policy $cfg $task $true $temp) 'Reviewed workspace denied'
 [IO.File]::WriteAllText((Join-Path $stage 'test.gd'),'changed code')
 Check (-not(TestAutoApproval $policy $cfg $task $true $temp)) 'Changed workspace accepted'
 $task.action='godot.tests.headless';$cfg.approved_scripts=@([pscustomobject]@{id='test';project_id=$id;revision_sha=$revision;action=$task.action;relative_path='test.gd';sha256=(Get-BridgeFileHash (Join-Path $stage 'test.gd')).Hash})
 Check (-not(TestAutoApproval $policy $cfg $task $true $temp)) 'Script with changed project accepted'
 SaveAutoWorkspaceTrust $cfg $task $temp;Check (TestAutoApproval $policy $cfg $task $true $temp) 'Reviewed script/workspace denied'
 [IO.File]::WriteAllText((Join-Path $stage 'test.gd'),'tampered')
 Check (-not(TestAutoApproval $policy $cfg $task $true $temp)) 'Tampered script accepted'
 $task.action='files.pull';$policy.enabled=$false;Check (-not(TestAutoApproval $policy $cfg $task $true $temp)) 'Disabled timer accepted';$policy.enabled=$true
 Check (-not(TestAutoApproval $policy $cfg $task $false $temp)) 'Revoked project accepted'
 $policy.delay_seconds=0;Check (-not(TestAutoApproval $policy $cfg $task $true $temp)) 'Zero timer accepted';$policy.delay_seconds=5
 $policy.project_id='d'*32;Check (-not(TestAutoApproval $policy $cfg $task $true $temp)) 'Wrong project policy accepted'
 Write-Host ('PASS '+$count+' expanded automatic approval tests')
}finally{if($temp -notlike (Join-Path $env:TEMP 'bridge-auto-test-*')){throw 'Cleanup denied'};Remove-Item -LiteralPath $temp -Force -Recurse}
