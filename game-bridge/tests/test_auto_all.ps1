$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'windows/approval.ps1')
$policy=[pscustomobject]@{enabled=$true;project_id=('a'*32);delay_seconds=5}
$cfg=[pscustomobject]@{project_id=('a'*32)}
$count=0
$actions=@('system.health','blender.version','godot.version','workspace.status','workspace.results','workspace.stage_revision','blender.scene.inspect','blender.render','blender.export_gltf','scripts.register','blender.run_approved_script','godot.tests.headless','godot.project.inspect','godot.project.import','godot.project.validate','godot.export','artifact.upload','files.push','files.pull','files.publish','pipeline.run','gui.blender.open','gui.godot.editor','gui.godot.run','godot.preview.capture')
foreach($action in $actions){
 $task=[pscustomobject]@{action=$action}
 if(-not(TestAutoApproval $policy $cfg $task $true $root)){throw ('Supported action denied '+$action)};$count++
}
foreach($case in @('disabled','revoked','foreign-policy','short-delay','long-delay','unknown','shell')){
 $policy.enabled=$true;$policy.project_id=$cfg.project_id;$policy.delay_seconds=5;$allowed=$true;$task.action='scripts.register'
 switch($case){'disabled'{$policy.enabled=$false};'revoked'{$allowed=$false};'foreign-policy'{$policy.project_id='b'*32};'short-delay'{$policy.delay_seconds=0};'long-delay'{$policy.delay_seconds=301};'unknown'{$task.action='unknown'};'shell'{$task.action='shell'}}
 if(TestAutoApproval $policy $cfg $task $allowed $root){throw ('Invalid policy accepted '+$case)};$count++
}
Write-Host ('PASS '+$count+' all-command automatic approval tests; handler validation remains separate')
