function GetInstalledTool([string]$Name) {
 if($Name -notin @('pipeline_scene.py','bridge_preview.gd','capture_preview.gd')){throw 'Unknown built-in pipeline tool'}
 $manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $entry=@($manifest|Where-Object {$_.name -eq $Name});$path=Join-Path $PSScriptRoot $Name
 if($entry.Count -ne 1 -or (Get-BridgeFileHash -LiteralPath $path).Hash -ne $entry[0].sha256){throw 'Installed pipeline tool integrity'}
 return $path
}
function RunDevelopmentPipeline {
 if($job.arguments.project_id -ne $cfg.project_id){throw 'Pipeline project mismatch'}
 $inputId=[string]$job.arguments.input_result_id;$inputHash=[string]$job.arguments.expected_sha256
 $entries=@(GetResultCatalog $cfg $PSScriptRoot|Where-Object {$_.result_id -eq $inputId -and $_.sha256 -eq $inputHash -and $_.project_id -eq $cfg.project_id -and $_.kind -eq 'blender'})
 if($entries.Count -ne 1){throw 'Unknown or changed pipeline input'}
 $godotId=[string]$job.arguments.godot_project_id
 $game=@($cfg.projects|Where-Object {$_.enabled -and $_.id -eq $godotId})
 if($game.Count -ne 1 -or $godotId -notmatch '^[a-f0-9]{32}$'){throw 'Godot project access not enabled'}
 $null=SafePath $game[0].path 'project.godot'
 if(-not(Test-Path -LiteralPath (Join-Path $game[0].path 'project.godot'))){throw 'Linked Godot project missing'}
 $angle=0.0;if($job.arguments.PSObject.Properties.Name -contains 'camera_angle_degrees'){$angle=[double]$job.arguments.camera_angle_degrees}
 if([double]::IsNaN($angle) -or [double]::IsInfinity($angle) -or $angle -lt -180 -or $angle -gt 180){throw 'Camera angle range'}
 $script=GetInstalledTool 'pipeline_scene.py';$preview=GetInstalledTool 'bridge_preview.gd'
 $argsFile=Join-Path $out 'pipeline-args.json'
 [IO.File]::WriteAllText($argsFile,(@{input=$entries[0].path;output=$out;angle_degrees=$angle}|ConvertTo-Json),$utf8)
 WriteActiveState @{job_id=$job.job_id;action=$job.action;phase='Blender render and GLB';progress=10}
 $blender=RunTool $cfg.blender @('--background','--factory-startup','--disable-autoexec','--python',$script,'--',$argsFile) 'blender.log'
 foreach($name in @('model.blend','model.glb','render.png')){if(-not(Test-Path -LiteralPath (Join-Path $out $name))){throw ('Pipeline result missing '+$name)}}
 Upload (Join-Path $out 'render.png');Upload (Join-Path $out 'model.glb')
 WriteActiveState @{job_id=$job.job_id;action=$job.action;phase='Isolated Godot project';progress=50}
 $gameRoot=SafePath (Join-Path $PSScriptRoot 'staging') $godotId;[IO.Directory]::CreateDirectory($gameRoot)|Out-Null
 $gameStage=SafePath $gameRoot ('pipeline-'+$job.job_id)
 if(Test-Path -LiteralPath $gameStage){throw 'Pipeline staging already exists'}
 [IO.Directory]::CreateDirectory($gameStage)|Out-Null
 $total=0L
 foreach($file in @(Get-ChildItem -LiteralPath $game[0].path -Recurse -Force)){
  if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Godot source reparse point'}
  $relative=$file.FullName.Substring($game[0].path.TrimEnd('\').Length+1)
  if($relative -match '(^|\\)(\.git|\.godot)(\\|$)'){continue}
  $target=SafePath $gameStage $relative
  if($file.PSIsContainer){[IO.Directory]::CreateDirectory($target)|Out-Null}else{
   $total+=$file.Length;if($total -gt 1GB){throw 'Godot source snapshot quota'}
   [IO.File]::Copy($file.FullName,$target,$false)
  }
 }
 [IO.File]::Copy((Join-Path $out 'model.glb'),(Join-Path $gameStage 'bridge-model.glb'),$false)
 [IO.File]::Copy($preview,(Join-Path $gameStage 'bridge-preview.gd'),$false)
 $scene="[gd_scene load_steps=3 format=3]`n`n[ext_resource type=`"PackedScene`" path=`"res://bridge-model.glb`" id=`"1`"]`n[ext_resource type=`"Script`" path=`"res://bridge-preview.gd`" id=`"2`"]`n`n[node name=`"BridgePreview`" type=`"Node3D`"]`nscript = ExtResource(`"2`")`n`n[node name=`"Model`" parent=`".`" instance=ExtResource(`"1`")]`n"
 [IO.File]::WriteAllText((Join-Path $gameStage 'bridge-preview.tscn'),$scene,$utf8)
 $projectFile=Join-Path $gameStage 'project.godot';$projectText=[IO.File]::ReadAllText($projectFile)
 if($projectText -match '(?m)^run/main_scene='){$projectText=[regex]::Replace($projectText,'(?m)^run/main_scene=.*$','run/main_scene="res://bridge-preview.tscn"')}
 elseif($projectText.Contains('[application]')){$projectText=$projectText.Replace('[application]',"[application]`nrun/main_scene=`"res://bridge-preview.tscn`"")}
 else{$projectText+="`n[application]`nrun/main_scene=`"res://bridge-preview.tscn`"`n"}
 [IO.File]::WriteAllText($projectFile,$projectText,$utf8)
 KeepTransferAlive
 WriteActiveState @{job_id=$job.job_id;action=$job.action;phase='Godot import';progress=70}
 $import=RunTool $cfg.godot @('--headless','--path',$gameStage,'--editor','--quit') 'godot-import.log'
 WriteActiveState @{job_id=$job.job_id;action=$job.action;phase='Godot runtime check';progress=85}
 $runtime=RunTool $cfg.godot @('--headless','--path',$gameStage,'--quit-after','2') 'godot-runtime.log'
 WriteActiveState @{job_id=$job.job_id;action=$job.action;phase='Return verified package';progress=95}
 $package=PushProjectFiles $out @('model.blend','model.glb','render.png','scene-report.json','blender.log','godot-import.log','godot-runtime.log')
 return @{blender=$blender;godot_import=$import;godot_runtime=$runtime;package=$package;godot_project_id=$godotId;godot_staging_revision=('pipeline-'+$job.job_id);geometry_modified=$false;original_preserved=$true}
}
