function ResolvePreviewEntry($Configuration,$Task,[string]$InstallRoot) {
 $id=[string]$Task.arguments.result_id;$hash=[string]$Task.arguments.expected_sha256;$projectId=[string]$Task.arguments.project_id
 if($id -notmatch '^[a-f0-9]{64}$' -or $hash -notmatch '^[a-f0-9]{64}$' -or $projectId -notmatch '^[a-f0-9]{32}$'){throw 'Preview selector invalid'}
 $project=@($Configuration.projects|Where-Object {$_.enabled -and $_.id -eq $projectId})
 if($project.Count -ne 1 -or $project[0].PSObject.Properties.Name -notcontains 'remote_open_enabled' -or -not $project[0].remote_open_enabled){throw 'Preview project launch permission denied'}
 $entries=@(GetResultCatalog $Configuration $InstallRoot|Where-Object {$_.project_id -eq $projectId -and $_.result_id -eq $id -and $_.sha256 -eq $hash -and $_.kind -eq 'godot'})
 if($entries.Count -ne 1){throw 'Preview result unknown or changed'}
 return $entries[0]
}
function CopyPreviewProject([string]$Source,[string]$Destination) {
 if(Test-Path -LiteralPath $Destination){throw 'Immutable preview destination exists'}
 $null=ResolveResultPath $Source 'project.godot'
 $files=@(Get-ChildItem -LiteralPath $Source -Recurse -Force)
 $size=0L;$count=0
 foreach($file in $files){
  if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Preview reparse point denied'}
  $relative=$file.FullName.Substring($Source.TrimEnd('\').Length+1)
  if($relative -match '(^|\\)(\.git|\.godot)(\\|$)'){continue}
  if(-not $file.PSIsContainer){$size+=$file.Length;$count++;if($size -gt 1GB -or $count -gt 10000){throw 'Preview snapshot quota'}}
 }
 [IO.Directory]::CreateDirectory($Destination)|Out-Null
 foreach($file in $files){
  $relative=$file.FullName.Substring($Source.TrimEnd('\').Length+1)
  if($relative -match '(^|\\)(\.git|\.godot)(\\|$)'){continue}
  $target=ResolveResultPath $Destination $relative
  # Recheck ancestry immediately before copying, including the source itself.
  $null=ResolveResultPath $Source $relative
  if($file.PSIsContainer){[IO.Directory]::CreateDirectory($target)|Out-Null}else{[IO.Directory]::CreateDirectory((Split-Path -Parent $target))|Out-Null;[IO.File]::Copy($file.FullName,$target,$false)}
 }
}
function CaptureGodotFeedback {
 $entry=ResolvePreviewEntry $cfg $job $PSScriptRoot
 $previewScript=GetInstalledTool 'capture_preview.gd'
 $root=SafePath (Join-Path $PSScriptRoot 'staging') $entry.project_id
 $destination=SafePath $root ('feedback-'+$job.job_id)
 CopyPreviewProject (Split-Path -Parent $entry.path) $destination
 WriteActiveState @{job_id=$job.job_id;action=$job.action;phase='Godot feedback import';progress=20}
 $import=RunTool $cfg.godot @('--headless','--path',$destination,'--editor','--quit') 'godot-feedback-import.log'
 WriteActiveState @{job_id=$job.job_id;action=$job.action;phase='Capture game viewport';progress=60}
 $runtime=RunTool $cfg.godot @('--path',$destination,'--rendering-method','gl_compatibility','--resolution','960x540','--script',$previewScript,'--',$out) 'godot-feedback-runtime.log'
 if($runtime.output -notmatch 'MAVKA_CAPTURE_OK'){throw 'Godot capture completion marker missing'}
 foreach($name in @('godot-preview.png','godot-feedback.json')){if(-not(Test-Path -LiteralPath (Join-Path $out $name))){throw ('Missing feedback '+$name)};Upload (Join-Path $out $name)}
 return @{project_id=$entry.project_id;result_id=$entry.result_id;input_sha256=$entry.sha256;import=$import;runtime=$runtime;feedback=(Get-Content (Join-Path $out 'godot-feedback.json') -Raw -Encoding UTF8|ConvertFrom-Json);original_preserved=$true}
}
