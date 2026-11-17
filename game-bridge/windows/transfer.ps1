Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$transferExtensions=@('.blend','.blend1','.tscn','.tres','.gd','.py','.godot','.glb','.gltf','.png','.jpg','.jpeg','.svg','.log','.json','.txt','.wav','.ogg')
function AssertTransferPath([string]$Relative) {
 if([string]::IsNullOrWhiteSpace($Relative) -or $Relative.Length -gt 220 -or $Relative -match '[\x00-\x1f<>:"|?*]' -or [IO.Path]::IsPathRooted($Relative)){throw 'Invalid package path'}
 foreach($part in ($Relative -split '[\\/]')){
  if($part -in @('','.','..') -or $part -match '[. ]$' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$'){throw 'Reserved/traversal package path'}
 }
 if([IO.Path]::GetExtension($Relative).ToLowerInvariant() -notin $transferExtensions){throw 'File type not allowed'}
}
function KeepTransferAlive {
 if(IsCancelled){throw 'Local cancellation'}
 if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'STOP')){throw 'Emergency stop'}
 $s=Request ('/v1/jobs/'+$job.job_id+'/progress') @{lease=$lease}
 if($s.state -ne 'running'){throw 'Transfer cancelled or lease lost'}
}
function AddArchiveFile($Archive,[string]$Name,[string]$Source) {
 $entry=$Archive.CreateEntry($Name,[IO.Compression.CompressionLevel]::Optimal)
 $entry.LastWriteTime=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
 $inputStream=[IO.File]::OpenRead($Source);$outputStream=$entry.Open()
 try{$inputStream.CopyTo($outputStream)}finally{$outputStream.Dispose();$inputStream.Dispose()}
}
function PushProjectFiles([string]$OverrideRoot='',[string[]]$OverrideFiles=@()) {
 if([string]$job.arguments.project_id -ne $cfg.project_id){throw 'Transfer project mismatch'}
 $files=@(if($OverrideFiles.Count){$OverrideFiles}else{$job.arguments.files})
 if($files.Count -lt 1 -or $files.Count -gt 200){throw 'Select 1 to 200 files'}
 $root=$cfg.source
 if($OverrideRoot){if($OverrideRoot -ne $out){throw 'Internal package root'};$root=$OverrideRoot}
 elseif($job.arguments.PSObject.Properties.Name -contains 'scope'){
  if($job.arguments.scope -eq 'staging'){$root=SafePath $stageRoot $job.revision_sha}elseif($job.arguments.scope -ne 'source'){throw 'Transfer scope'}
 }
 $entries=@();$seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase);$total=0L
 foreach($relative in ($files|Sort-Object)){
  if($relative -isnot [string]){throw 'File path must be string'}
  AssertTransferPath $relative
  if(-not $seen.Add($relative.Replace('\','/'))){throw 'Duplicate package path'}
  $file=SafePath $root $relative;$info=Get-Item -LiteralPath $file
  if($info.PSIsContainer){throw 'Only explicit files can be transferred'}
  $total+=$info.Length;if($total -gt 256MB){throw 'Uncompressed package quota'}
  $entries+=@([ordered]@{path=$relative.Replace('\','/');size=[long]$info.Length;sha256=(Get-BridgeFileHash -LiteralPath $file).Hash;source=$file})
  KeepTransferAlive
 }
 $manifest=[ordered]@{version=1;project_id=$cfg.project_id;files=@($entries|ForEach-Object {[ordered]@{path=$_.path;size=$_.size;sha256=$_.sha256}})}
 $manifestPath=Join-Path $out 'transfer-manifest.json';[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 8 -Compress),$utf8)
 $zip=Join-Path $out 'transfer.zip';$archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
 try{AddArchiveFile $archive 'manifest.json' $manifestPath;foreach($entry in $entries){AddArchiveFile $archive ('files/'+$entry.path) $entry.source;KeepTransferAlive}}finally{$archive.Dispose()}
 $size=(Get-Item -LiteralPath $zip).Length;if($size -gt 256MB){throw 'Compressed package quota'}
 $digest=(Get-BridgeFileHash -LiteralPath $zip).Hash
 $endpoint='/v1/jobs/'+$job.job_id+'/transfer'
 $state=Request $endpoint @{lease=$lease;op='init';sha256=$digest;size=$size;device_id=$cfg.device_id;project_id=$cfg.project_id}
 if(-not $state.complete){
  $stream=[IO.File]::OpenRead($zip)
  try{$i=0;while($stream.Position -lt $stream.Length){
   $length=[int][Math]::Min(1MB,$stream.Length-$stream.Position);$buffer=New-Object byte[] $length;$read=0
   while($read -lt $length){$n=$stream.Read($buffer,$read,$length-$read);if($n -eq 0){throw 'Unexpected EOF'};$read+=$n}
   Request $endpoint @{lease=$lease;op='chunk';sha256=$digest;index=$i;chunk_sha256=(HashBytes $buffer);content=[Convert]::ToBase64String($buffer)}|Out-Null
   KeepTransferAlive;Start-Sleep -Milliseconds 150;$i++
  }}finally{$stream.Dispose()}
  Request $endpoint @{lease=$lease;op='complete';sha256=$digest}|Out-Null
 }
 return @{package_sha256=$digest;size=$size;file_count=$entries.Count;manifest_sha256=(Get-BridgeFileHash -LiteralPath $manifestPath).Hash}
}
function CopyBoundedStream($Source,$Target,[long]$Maximum) {
 $buffer=New-Object byte[] 65536;$count=0L
 while(($n=$Source.Read($buffer,0,$buffer.Length)) -gt 0){$count+=$n;if($count -gt $Maximum){throw 'Decompression quota'};$Target.Write($buffer,0,$n)}
 return $count
}
function ExpandVerifiedPackage([string]$Zip,[string]$Destination,[string]$ProjectId) {
 $archive=[IO.Compression.ZipFile]::OpenRead($Zip)
 try{
  if($archive.Entries.Count -gt 201){throw 'Archive entry quota'}
  $manifestEntry=$archive.GetEntry('manifest.json')
  if($null -eq $manifestEntry -or $manifestEntry.Length -gt 1MB){throw 'Package manifest missing/oversize'}
  $memory=New-Object IO.MemoryStream;$stream=$manifestEntry.Open()
  try{$null=CopyBoundedStream $stream $memory 1MB;$manifest=$utf8.GetString($memory.ToArray())|ConvertFrom-Json}finally{$stream.Dispose();$memory.Dispose()}
  if($manifest.version -ne 1 -or $manifest.project_id -ne $ProjectId){throw 'Manifest version/project mismatch'}
  $files=@($manifest.files)
  if($files.Count -lt 1 -or $files.Count -gt 200 -or $archive.Entries.Count -ne $files.Count+1){throw 'Manifest entry mismatch'}
  $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase);$total=0L
  foreach($file in $files){
   $relative=[string]$file.path;AssertTransferPath $relative
   if(-not $seen.Add($relative.Replace('\','/')) -or $file.sha256 -notmatch '^[a-f0-9]{64}$' -or $file.size -lt 0){throw 'Invalid manifest file'}
   $entry=$archive.GetEntry('files/'+$relative)
   if($null -eq $entry -or $entry.Length -ne $file.size -or (($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960 -or ($entry.ExternalAttributes -band 1024)){throw 'Archive file/link mismatch'}
   $total+=[long]$file.size;if($total -gt 256MB){throw 'Extracted size quota'}
   $target=SafePath $Destination $relative
   [IO.Directory]::CreateDirectory((Split-Path -Parent $target))|Out-Null
   $inputStream=$entry.Open();$outputStream=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
   try{$actual=CopyBoundedStream $inputStream $outputStream ([long]$file.size)}finally{$inputStream.Dispose();$outputStream.Dispose()}
   if($actual -ne $file.size -or (Get-BridgeFileHash -LiteralPath $target).Hash -ne $file.sha256){throw 'Extracted file integrity'}
  }
  [IO.File]::WriteAllText((Join-Path $Destination 'bridge-package-manifest.json'),($manifest|ConvertTo-Json -Depth 10),$utf8)
  return $files.Count
 }finally{$archive.Dispose()}
}
function PullProjectFiles {
 if([string]$job.arguments.project_id -ne $cfg.project_id){throw 'Transfer project mismatch'}
 $digest=[string]$job.arguments.package_sha256
 if($digest -notmatch '^[a-f0-9]{64}$'){throw 'Package SHA256'}
 $target=SafePath $stageRoot $job.revision_sha
 if(Test-Path -LiteralPath $target){throw 'Staging revision exists; no overwrite permitted'}
 $zip=Join-Path $out 'incoming.zip';$stream=[IO.File]::Open($zip,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
 try{
  $i=0;$size=0L
  do{
   $chunk=Request ('/v1/jobs/'+$job.job_id+'/transfer') @{lease=$lease;op='download';sha256=$digest;index=$i}
   if($chunk.sha256 -ne $digest -or $chunk.index -ne $i -or $chunk.size -gt 256MB -or $chunk.size -lt 1){throw 'Download metadata'}
   if($i -eq 0){$size=[long]$chunk.size}elseif($size -ne $chunk.size){throw 'Download size changed'}
   $raw=[Convert]::FromBase64String($chunk.content)
   if($raw.Length -ne [Math]::Min(1MB,$size-$stream.Position) -or (HashBytes $raw) -ne $chunk.chunk_sha256){throw 'Download chunk integrity'}
   $stream.Write($raw,0,$raw.Length);KeepTransferAlive;Start-Sleep -Milliseconds 150;$i++
  }while($stream.Position -lt $size)
 }finally{$stream.Dispose()}
 if((Get-BridgeFileHash -LiteralPath $zip).Hash -ne $digest){throw 'Download package integrity'}
 $unpack=Join-Path $out 'verified-package';New-Item -ItemType Directory -Path $unpack|Out-Null
 $count=ExpandVerifiedPackage $zip $unpack $cfg.project_id
 [IO.File]::WriteAllText((Join-Path $unpack 'bridge-package-sha256.txt'),$digest,$utf8)
 KeepTransferAlive
 [IO.Directory]::Move($unpack,$target)
 return @{package_sha256=$digest;file_count=$count;staging_revision=$job.revision_sha;source_modified=$false}
}
function PublishProjectFiles {
 if([string]$job.arguments.project_id -ne $cfg.project_id){throw 'Publish project mismatch'}
 $project=@($cfg.projects|Where-Object {$_.id -eq $cfg.project_id})[0]
 if($project.kind -ne 'assets' -or $project.output_subdirectory -cne 'V031'){throw 'Publish output prefix not locally approved'}
 $version=[string]$job.arguments.version_name
 if($version -notmatch '^[a-zA-Z0-9_-]{1,64}$'){throw 'Version directory name'}
 $stage=SafePath $stageRoot $job.revision_sha
 $digest=(Get-Content -LiteralPath (SafePath $stage 'bridge-package-sha256.txt') -Raw -Encoding UTF8).Trim()
 if($digest -notmatch '^[a-f0-9]{64}$' -or $digest -ne $job.arguments.package_sha256){throw 'Publish package binding'}
 $manifest=Get-Content -LiteralPath (SafePath $stage 'bridge-package-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($manifest.project_id -ne $cfg.project_id){throw 'Publish manifest project'}
 $target=SafePath $cfg.source ('V031\'+$version)
 if(Test-Path -LiteralPath $target){throw 'Output version exists: no overwrite permitted'}
 $parent=SafePath $cfg.source 'V031';[IO.Directory]::CreateDirectory($parent)|Out-Null
 $temp=SafePath $parent ('.pending-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($temp)|Out-Null
 foreach($entry in @($manifest.files)){
  AssertTransferPath $entry.path;$sourceFile=SafePath $stage $entry.path
  if((Get-BridgeFileHash -LiteralPath $sourceFile).Hash -ne $entry.sha256 -or (Get-Item -LiteralPath $sourceFile).Length -ne $entry.size){throw 'Staged file changed after verification'}
  $destination=SafePath $temp $entry.path;[IO.Directory]::CreateDirectory((Split-Path -Parent $destination))|Out-Null
  [IO.File]::Copy($sourceFile,$destination,$false);KeepTransferAlive
 }
 [IO.File]::WriteAllText((Join-Path $temp 'bridge-package-manifest.json'),($manifest|ConvertTo-Json -Depth 10),$utf8)
 KeepTransferAlive;[IO.Directory]::Move($temp,$target)
 return @{published_relative_path=('V031/'+$version);file_count=@($manifest.files).Count;package_sha256=$digest;overwritten_files=0}
}
