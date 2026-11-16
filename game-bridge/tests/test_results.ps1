$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'windows\hash.ps1')
. (Join-Path $root 'windows\results.ps1')
$parent=Join-Path $root 'work';New-Item -ItemType Directory -Force -Path $parent|Out-Null
$temp=Join-Path $parent ('result-tests-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
$count=0
try{
 $project='a'*32;$output=Join-Path $temp 'output\job-fixture';$stage=Join-Path $temp ('staging\'+$project+'\revision')
 New-Item -ItemType Directory -Force -Path $output,$stage|Out-Null
 [IO.File]::WriteAllText((Join-Path $output 'result.json'),('{"state":"succeeded","project_id":"'+$project+'"}'))
 [IO.File]::WriteAllText((Join-Path $output 'model.blend'),'fixture only, never executed')
 [IO.File]::WriteAllText((Join-Path $stage 'project.godot'),'config_version=5')
 $cfg=[pscustomobject]@{projects=@([pscustomobject]@{id=$project;name='Fixture';enabled=$true;remote_open_enabled=$true});blender='missing.exe';godot='missing.exe'}
 $catalog=@(GetResultCatalog $cfg $temp)
 if($catalog.Count -ne 2){throw 'Expected only the two owned result types'};$count++
 foreach($entry in $catalog){if($entry.result_id -notmatch '^[a-f0-9]{64}$'){throw 'Missing opaque result ID'};$count++}
 $entry=$catalog|Where-Object {$_.kind -eq 'blender'}
 $hash=$entry.sha256;$entry.sha256='0'*64;$denied=$false
 try{$null=StartResultTool $entry $cfg 'blender' $temp}catch{$denied=$true}
 if(-not $denied){throw 'Changed result accepted'};$count++;$entry.sha256=$hash
 $cfg.projects[0].enabled=$false;$denied=$false
 try{$null=StartResultTool $entry $cfg 'blender' $temp}catch{$denied=$true}
 if(-not $denied){throw 'Revoked project accepted'};$count++;$cfg.projects[0].enabled=$true
 $denied=$false;try{$null=ResolveResultPath $temp '..\escape.blend'}catch{$denied=$true}
 if(-not $denied){throw 'Result traversal accepted'};$count++
 [IO.File]::WriteAllText((Join-Path $temp 'active.json'),'{}');$denied=$false
 try{$null=StartResultTool $entry $cfg 'blender' $temp}catch{$denied=$true}
 if(-not $denied){throw 'Interactive/headless conflict accepted'};$count++
 Write-Host ('PASS '+$count+' result-catalog/launch-guard tests; no editor launched')
}finally{
 $full=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($parent).TrimEnd('\')+'\'
 if(-not $full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Cleanup path denied'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
