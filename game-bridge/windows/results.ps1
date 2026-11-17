function ResolveResultPath([string]$Root,[string]$Relative) {
 if([IO.Path]::IsPathRooted($Relative) -or $Relative -match '[:\r\n]'){throw 'Invalid result path'}
 $base=[IO.Path]::GetFullPath($Root).TrimEnd('\');$file=[IO.Path]::GetFullPath((Join-Path $base $Relative))
 if(-not $file.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Result path escape'}
 $walk=$file
 while($walk){if(Test-Path -LiteralPath $walk){if((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Result reparse point'}};$walk=Split-Path -Parent $walk}
 return $file
}
function GetResultCatalog($Configuration,[string]$InstallRoot) {
 $catalog=@();$allowed=@($Configuration.projects|Where-Object {$_.enabled})
 $output=Join-Path $InstallRoot 'output'
 foreach($folder in @(Get-ChildItem -LiteralPath $output -Directory|Sort-Object LastWriteTime -Descending|Select-Object -First 100)){
  $report=ResolveResultPath $output ($folder.Name+'\result.json')
  if(-not(Test-Path -LiteralPath $report)){continue}
  try{$result=Get-Content -LiteralPath $report -Raw -Encoding UTF8|ConvertFrom-Json}catch{continue}
  if($result.state -ne 'succeeded' -or $result.PSObject.Properties.Name -notcontains 'project_id' -or $result.project_id -notin @($allowed.id)){continue}
  foreach($f in @(Get-ChildItem -LiteralPath $folder.FullName -File -Filter '*.blend')){
   $path=ResolveResultPath $output ($folder.Name+'\'+$f.Name)
   $catalog+=@{display=('Blender / '+$folder.Name+' / '+$f.Name);kind='blender';path=$path;project_id=$result.project_id;sha256=(Get-BridgeFileHash -LiteralPath $path).Hash}
  }
 }
 foreach($project in $allowed){
  $root=ResolveResultPath (Join-Path $InstallRoot 'staging') $project.id
  if(-not(Test-Path -LiteralPath $root)){continue}
  foreach($revision in @(Get-ChildItem -LiteralPath $root -Directory|Sort-Object LastWriteTime -Descending|Select-Object -First 30)){
   $godot=ResolveResultPath $root ($revision.Name+'\project.godot')
   if(Test-Path -LiteralPath $godot){$catalog+=@{display=('Godot / '+$project.name+' / '+$revision.Name);kind='godot';path=$godot;project_id=$project.id;sha256=(Get-BridgeFileHash -LiteralPath $godot).Hash}}
   foreach($f in @(Get-ChildItem -LiteralPath $revision.FullName -File -Filter '*.blend')){
    $path=ResolveResultPath $root ($revision.Name+'\'+$f.Name)
    $catalog+=@{display=('Blender staging / '+$project.name+' / '+$f.Name);kind='blender';path=$path;project_id=$project.id;sha256=(Get-BridgeFileHash -LiteralPath $path).Hash}
   }
  }
 }
 foreach($entry in $catalog){
  $relative=$entry.path.Substring([IO.Path]::GetFullPath($InstallRoot).TrimEnd('\').Length+1).Replace('\','/')
  $h=[Security.Cryptography.SHA256]::Create()
  try{$entry.result_id=([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($entry.project_id+'|'+$entry.kind+'|'+$relative)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
 }
 return $catalog
}
function StartResultTool($Entry,$Configuration,[string]$Mode,[string]$InstallRoot,[switch]$FromAgent) {
 if(($Entry.kind -eq 'blender' -and [IO.Path]::GetExtension($Entry.path) -ne '.blend') -or ($Entry.kind -eq 'godot' -and [IO.Path]::GetFileName($Entry.path) -ne 'project.godot')){throw 'Unexpected result file type'}
 if($Entry.project_id -notin @($Configuration.projects|Where-Object {$_.enabled}|ForEach-Object {$_.id})){throw 'Project access revoked'}
 $path=[IO.Path]::GetFullPath($Entry.path)
 $owned=$false
 foreach($root in @((Join-Path $InstallRoot 'output'),(Join-Path $InstallRoot 'staging'))){
  $base=[IO.Path]::GetFullPath($root).TrimEnd('\')+'\'
  if($path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){$null=ResolveResultPath $root $path.Substring($base.Length);$owned=$true}
 }
 if(-not $owned -or (Get-BridgeFileHash -LiteralPath $path).Hash -ne $Entry.sha256){throw 'Result location/hash changed; refresh the list'}
 if(-not $FromAgent -and (Test-Path -LiteralPath (Join-Path $InstallRoot 'active.json'))){throw 'Wait until the active job finishes before opening an interactive tool'}
 if($Entry.kind -eq 'blender' -and $Mode -eq 'blender'){$exe=$Configuration.blender;$toolArgs=@('--disable-autoexec',$path)}
 elseif($Entry.kind -eq 'godot' -and $Mode -in @('editor','run')){
  $exe=$Configuration.godot -replace '_console\.exe$','.exe'
  if(-not(Test-Path -LiteralPath $exe)){$exe=$Configuration.godot}
  $toolArgs=@('--path',(Split-Path -Parent $path));if($Mode -eq 'editor'){$toolArgs=@('--editor')+$toolArgs}
 }else{throw 'Result/tool mismatch'}
 foreach($a in $toolArgs){if($a -match '["\r\n]'){throw 'Invalid tool argument'}}
 $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=$exe;$info.Arguments=(($toolArgs|ForEach-Object {'"'+$_+'"'}) -join ' ')
 $info.UseShellExecute=$false;$info.CreateNoWindow=$false;$info.WindowStyle='Normal';$info.WorkingDirectory=Split-Path -Parent $path
 $process=New-Object Diagnostics.Process;$process.StartInfo=$info;$null=$process.Start()
 $record=@{pid=$process.Id;started_utc=$process.StartTime.ToUniversalTime().ToString('o');kind=$Entry.kind;workspace=(Split-Path -Parent $path);project_id=$Entry.project_id}
 $state=Join-Path $InstallRoot 'opened-tools.json';$previous=@()
 if(Test-Path -LiteralPath $state){try{$previous=@(Get-Content -LiteralPath $state -Raw -Encoding UTF8|ConvertFrom-Json)}catch{}}
 @($previous+$record)|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $state -Encoding UTF8
 return $process.Id
}
function OpenRemoteResult([string]$Mode) {
 $id=[string]$job.arguments.result_id;$hash=[string]$job.arguments.expected_sha256;$projectId=[string]$job.arguments.project_id
 if($id -notmatch '^[a-f0-9]{64}$' -or $hash -notmatch '^[a-f0-9]{64}$'){throw 'Result identifier/hash'}
 $project=@($cfg.projects|Where-Object {$_.id -eq $projectId -and $_.enabled})
 if($project.Count -ne 1 -or $project[0].PSObject.Properties.Name -notcontains 'remote_open_enabled' -or -not $project[0].remote_open_enabled){throw 'Remote result opening not locally enabled for this project'}
 $entries=@(GetResultCatalog $cfg $PSScriptRoot|Where-Object {$_.result_id -eq $id -and $_.project_id -eq $projectId -and $_.sha256 -eq $hash})
 if($entries.Count -ne 1){throw 'Unknown or changed result'}
 $pidValue=StartResultTool $entries[0] $cfg $Mode $PSScriptRoot -FromAgent
 Journal ('remote_opened_'+$Mode) $job.job_id $job.action
 return @{result_id=$id;sha256=$hash;mode=$Mode;process_id=$pidValue}
}
function AssertNoInteractiveConflict([string]$Exe,[string[]]$Arguments,[string]$InstallRoot) {
 $state=Join-Path $InstallRoot 'opened-tools.json';if(-not(Test-Path -LiteralPath $state)){return}
 $records=@(Get-Content -LiteralPath $state -Raw -Encoding UTF8|ConvertFrom-Json)
 foreach($record in $records){
  try{$p=[Diagnostics.Process]::GetProcessById([int]$record.pid);$alive=$p.StartTime.ToUniversalTime().ToString('o') -eq $record.started_utc}catch{$alive=$false}
  if(-not $alive){continue}
  if($record.kind -eq 'blender' -and [IO.Path]::GetFileName($Exe) -eq 'blender.exe'){throw 'Close the Blender window opened by Bridge before starting a headless Blender job'}
  $i=[Array]::IndexOf($Arguments,'--path')
  if($record.kind -eq 'godot' -and $i -ge 0 -and $record.workspace -eq $Arguments[$i+1]){throw 'This staging project is open in Godot; close it or use a new isolated revision'}
 }
}
