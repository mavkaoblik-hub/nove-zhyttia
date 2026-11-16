$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'windows/hash.ps1')
. (Join-Path $root 'windows/results.ps1')
. (Join-Path $root 'windows/scripts.ps1')
$temp=Join-Path $env:TEMP ('bridge-script-tests-'+[Guid]::NewGuid().ToString('N'))
$pidValue='a'*32;$rev='b'*40;$stage=Join-Path $temp ('staging\'+$pidValue+'\'+$rev)
New-Item -ItemType Directory -Path $stage -Force|Out-Null
try{
 $file=Join-Path $stage 'test.py';[IO.File]::WriteAllText($file,'print("review fixture only")')
 $cfg=[pscustomobject]@{project_id=$pidValue;projects=@([pscustomobject]@{id=$pidValue;enabled=$true});approved_scripts=@()}
 $task=[pscustomobject]@{revision_sha=$rev;arguments=[pscustomobject]@{script_id='fixture';action='blender.run_approved_script';relative_path='test.py';sha256=(Get-BridgeFileHash $file).Hash}}
 $review=GetScriptReview $cfg $task $temp
 $config=Join-Path $temp 'config.json';$cfg|ConvertTo-Json -Depth 8|Set-Content $config -Encoding UTF8
 $null=RegisterReviewedScript $cfg $task $temp $config $review
 $saved=Get-Content $config -Raw -Encoding UTF8|ConvertFrom-Json
 if($saved.approved_scripts.Count -ne 1 -or $saved.approved_scripts[0].project_id -ne $pidValue){throw 'Registry scope lost'}
 $count=1
 foreach($case in @('hash','escape','action','disabled','changed')){
  $task.arguments.sha256=$review.sha256;$task.arguments.relative_path='test.py';$task.arguments.action=$review.action;$cfg.projects[0].enabled=$true
  switch($case){'hash'{$task.arguments.sha256='0'*64};'escape'{$task.arguments.relative_path='..\test.py'};'action'{$task.arguments.action='shell.exec'};'disabled'{$cfg.projects[0].enabled=$false};'changed'{[IO.File]::WriteAllText($file,'changed')}}
  $denied=$false;try{$null=RegisterReviewedScript $cfg $task $temp $config $review}catch{$denied=$true}
  if(-not $denied){throw ('Unsafe registration accepted: '+$case)};$count++
 }
 Write-Host ('PASS '+$count+' script registry tests; no script executed')
}finally{if($temp -notlike (Join-Path $env:TEMP 'bridge-script-tests-*')){throw 'Cleanup denied'};Remove-Item -LiteralPath $temp -Recurse -Force}
