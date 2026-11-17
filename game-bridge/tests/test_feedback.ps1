$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'windows/hash.ps1')
. (Join-Path $root 'windows/results.ps1')
. (Join-Path $root 'windows/feedback.ps1')
$temp=Join-Path $env:TEMP ('bridge-feedback-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try{
 $source=Join-Path $temp 'source';$dest=Join-Path $temp 'copy'
 New-Item -ItemType Directory -Path (Join-Path $source '.git'),(Join-Path $source '.godot') -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $source 'project.godot'),'config_version=5')
 [IO.File]::WriteAllText((Join-Path $source '.git/private'),'excluded')
 [IO.File]::WriteAllText((Join-Path $source '.godot/cache'),'excluded')
 CopyPreviewProject $source $dest
 if(-not(Test-Path (Join-Path $dest 'project.godot')) -or (Test-Path (Join-Path $dest '.git')) -or (Test-Path (Join-Path $dest '.godot'))){throw 'Snapshot exclusion failed'}
 $count=1;$denied=$false;try{CopyPreviewProject $source $dest}catch{$denied=$true};if(-not $denied){throw 'Snapshot overwritten'};$count++
 $script:projectId='a'*32;$script:resultId='b'*64;$script:resultHash='c'*64
 function GetResultCatalog($c,$r){return @{project_id=$script:projectId;result_id=$script:resultId;sha256=$script:resultHash;kind='godot';path='fixture'}}
 $cfg=[pscustomobject]@{projects=@([pscustomobject]@{id=$script:projectId;enabled=$true;remote_open_enabled=$true})}
 $task=[pscustomobject]@{arguments=[pscustomobject]@{project_id=$script:projectId;result_id=$script:resultId;expected_sha256=$script:resultHash}}
 $null=ResolvePreviewEntry $cfg $task $temp;$count++
 foreach($case in @('project','hash','permission','disabled','identifier')){
  $task.arguments.project_id=$script:projectId;$task.arguments.expected_sha256=$script:resultHash;$task.arguments.result_id=$script:resultId;$cfg.projects[0].enabled=$true;$cfg.projects[0].remote_open_enabled=$true
  switch($case){'project'{$task.arguments.project_id='d'*32};'hash'{$task.arguments.expected_sha256='e'*64};'permission'{$cfg.projects[0].remote_open_enabled=$false};'disabled'{$cfg.projects[0].enabled=$false};'identifier'{$task.arguments.result_id='..\escape'}}
  $denied=$false;try{$null=ResolvePreviewEntry $cfg $task $temp}catch{$denied=$true};if(-not $denied){throw ('Feedback scope accepted: '+$case)};$count++
 }
 Write-Host ('PASS '+$count+' feedback scope/snapshot tests')
}finally{if($temp -notlike (Join-Path $env:TEMP 'bridge-feedback-test-*')){throw 'Cleanup denied'};Remove-Item -LiteralPath $temp -Force -Recurse}
