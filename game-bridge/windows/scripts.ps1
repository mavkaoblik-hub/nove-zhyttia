function GetScriptReview($Configuration,$Task,[string]$InstallRoot) {
 if($Task.arguments.script_id -notmatch '^[a-zA-Z0-9_-]{1,64}$'){throw 'Invalid script ID'}
 if($Task.arguments.action -notin @('blender.run_approved_script','godot.tests.headless')){throw 'Unsupported script action'}
 if($Task.revision_sha -notmatch '^[a-f0-9]{40}$' -or $Task.arguments.sha256 -notmatch '^[a-f0-9]{64}$'){throw 'Script revision/hash required'}
 $project=@($Configuration.projects|Where-Object {$_.enabled -and $_.id -eq $Configuration.project_id})
 if($project.Count -ne 1){throw 'Project not enabled'}
 $stage=ResolveResultPath (Join-Path $InstallRoot 'staging') ($Configuration.project_id+'\'+$Task.revision_sha)
 $file=ResolveResultPath $stage ([string]$Task.arguments.relative_path)
 $extension=if($Task.arguments.action -eq 'blender.run_approved_script'){'.py'}else{'.gd'}
 if([IO.Path]::GetExtension($file) -ne $extension){throw 'Script extension/action mismatch'}
 $item=Get-Item -LiteralPath $file -Force
 if($item.PSIsContainer -or $item.Length -gt 32768){throw 'Script review limit: 32 KiB'}
 if((Get-BridgeFileHash -LiteralPath $file).Hash -ne $Task.arguments.sha256){throw 'Script checksum mismatch'}
 $decoder=New-Object System.Text.UTF8Encoding($false,$true)
 $code=$decoder.GetString([IO.File]::ReadAllBytes($file))
 if($code.Contains([char]0)){throw 'Binary script denied'}
 return [pscustomobject]@{id=[string]$Task.arguments.script_id;project_id=$Configuration.project_id;revision_sha=$Task.revision_sha;action=[string]$Task.arguments.action;relative_path=[string]$Task.arguments.relative_path;sha256=[string]$Task.arguments.sha256;code=$code}
}
function RegisterReviewedScript($Configuration,$Task,[string]$InstallRoot,[string]$ConfigurationPath,$Review) {
 $current=GetScriptReview $Configuration $Task $InstallRoot
 if($current.code -cne $Review.code){throw 'Script changed after review'}
 $fresh=Get-Content -LiteralPath $ConfigurationPath -Raw -Encoding UTF8|ConvertFrom-Json
 if($fresh.project_id -ne $current.project_id -or @($fresh.projects|Where-Object {$_.enabled -and $_.id -eq $current.project_id}).Count -ne 1){throw 'Project permission changed'}
 $entry=$current|Select-Object id,project_id,revision_sha,action,relative_path,sha256
 $prior=@($fresh.approved_scripts|Where-Object {-not($_.id -eq $entry.id -and $_.project_id -eq $entry.project_id -and $_.revision_sha -eq $entry.revision_sha -and $_.action -eq $entry.action)})
 if($prior.Count -ge 100){throw 'Script registry quota'}
 $fresh.approved_scripts=@($prior)+@($entry)
 $temp=$ConfigurationPath+'.scripts.tmp';$backup=$ConfigurationPath+'.scripts-'+[Guid]::NewGuid().ToString('N')+'.backup'
 [IO.File]::WriteAllText($temp,($fresh|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($true)))
 [IO.File]::Replace($temp,$ConfigurationPath,$backup)
 return @{registered=$entry.id;project_id=$entry.project_id;sha256=$entry.sha256;execution_requires_separate_job=$true}
}
