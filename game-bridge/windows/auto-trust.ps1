function GetAutoWorkspace($Configuration,$Task,[string]$InstallRoot) {
 $action=[string]$Task.action
 if($action -eq 'pipeline.run'){
  $p=@($Configuration.projects|Where-Object {$_.enabled -and $_.id -eq $Task.arguments.godot_project_id})
  if($p.Count -ne 1){throw 'Linked project denied'}
  return @{project_id=$p[0].id;path=$p[0].path}
 }
 if($action -eq 'godot.preview.capture'){$entry=ResolvePreviewEntry $Configuration $Task $InstallRoot;return @{project_id=$entry.project_id;path=(Split-Path -Parent $entry.path)}}
 if($action -in @('gui.godot.editor','gui.godot.run')){
  $p=@($Configuration.projects|Where-Object {$_.enabled -and $_.id -eq $Task.arguments.project_id -and $_.remote_open_enabled})
  if($p.Count -ne 1){throw 'Remote project denied'}
  $entry=@(GetResultCatalog $Configuration $InstallRoot|Where-Object {$_.kind -eq 'godot' -and $_.project_id -eq $p[0].id -and $_.result_id -eq $Task.arguments.result_id -and $_.sha256 -eq $Task.arguments.expected_sha256})
  if($entry.Count -ne 1){throw 'Changed result'}
  return @{project_id=$p[0].id;path=(Split-Path -Parent $entry[0].path)}
 }
 if($action -in @('godot.project.import','godot.project.validate','godot.export','godot.tests.headless')){
  if($Task.revision_sha -notmatch '^[a-f0-9]{40}$'){throw 'Revision'}
  $path=ResolveResultPath (Join-Path $InstallRoot 'staging') ($Configuration.project_id+'\'+$Task.revision_sha)
  return @{project_id=$Configuration.project_id;path=$path}
 }
 return $null
}
function GetAutoFingerprint([string]$Root) {
 $base=[IO.Path]::GetFullPath($Root).TrimEnd('\');$null=ResolveResultPath $base 'project.godot'
 if(-not(Test-Path -LiteralPath (Join-Path $base 'project.godot'))){throw 'Project missing'}
 $lines=New-Object 'Collections.Generic.List[string]';$size=0L
 foreach($f in @(Get-ChildItem -LiteralPath $base -Recurse -Force|Sort-Object FullName)){
  if($f.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Trust reparse denied'}
  $relative=$f.FullName.Substring($base.Length+1)
  if($relative -match '(^|\\)(\.git|\.godot)(\\|$)' -or $f.PSIsContainer){continue}
  $size+=$f.Length;if($size -gt 512MB -or $lines.Count -ge 10000){throw 'Trust scan quota'}
  $null=ResolveResultPath $base $relative
  $lines.Add($relative.Replace('\','/')+'|'+$f.Length+'|'+(Get-BridgeFileHash -LiteralPath $f.FullName).Hash)
 }
 $hash=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
}
function TestAutoWorkspaceTrust($Configuration,$Task,[string]$InstallRoot) {
 try{
  $workspace=GetAutoWorkspace $Configuration $Task $InstallRoot;if($null -eq $workspace){return $false}
  $file=Join-Path $InstallRoot 'auto-trust.json';if(-not(Test-Path -LiteralPath $file)){return $false}
  $fingerprint=GetAutoFingerprint $workspace.path
  $records=@(Get-Content -LiteralPath $file -Raw -Encoding UTF8|ConvertFrom-Json)
  return (@($records|Where-Object {$_.project_id -eq $workspace.project_id -and $_.path -eq $workspace.path -and $_.sha256 -eq $fingerprint}).Count -eq 1)
 }catch{return $false}
}
function SaveAutoWorkspaceTrust($Configuration,$Task,[string]$InstallRoot) {
 try{
  $workspace=GetAutoWorkspace $Configuration $Task $InstallRoot;if($null -eq $workspace){return}
  $fingerprint=GetAutoFingerprint $workspace.path
  $file=Join-Path $InstallRoot 'auto-trust.json';$records=@()
  if(Test-Path -LiteralPath $file){$records=@(Get-Content -LiteralPath $file -Raw -Encoding UTF8|ConvertFrom-Json)}
  $records=@($records|Where-Object {-not($_.project_id -eq $workspace.project_id -and $_.path -eq $workspace.path)}|Select-Object -Last 99)
  $records+=@{project_id=$workspace.project_id;path=$workspace.path;sha256=$fingerprint;approved_utc=[DateTime]::UtcNow.ToString('o')}
  $temp=$file+'.tmp';[IO.File]::WriteAllText($temp,(ConvertTo-Json -InputObject @($records) -Depth 8),(New-Object Text.UTF8Encoding($false)))
  if(Test-Path -LiteralPath $file){[IO.File]::Replace($temp,$file,($file+'.previous'))}else{[IO.File]::Move($temp,$file)}
 }catch{Write-Warning 'Workspace trust was not saved; next code-bearing job will require manual approval'}
}
