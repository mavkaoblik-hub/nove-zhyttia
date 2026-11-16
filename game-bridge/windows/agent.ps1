param([string]$ConfigPath=(Join-Path $PSScriptRoot 'config.json'),[switch]$Once)
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'hash.ps1')
. (Join-Path $PSScriptRoot 'transfer.ps1')
. (Join-Path $PSScriptRoot 'approval.ps1')
. (Join-Path $PSScriptRoot 'results.ps1')
. (Join-Path $PSScriptRoot 'process-output.ps1')
. (Join-Path $PSScriptRoot 'pipeline.ps1')
. (Join-Path $PSScriptRoot 'scripts.ps1')
. (Join-Path $PSScriptRoot 'feedback.ps1')
$ErrorActionPreference='Stop'
$cfg=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($cfg.gateway -ne 'http://127.0.0.1:18774') { throw 'Only the local pinned SSH forwarding endpoint is permitted' }
$credential=Import-Clixml -LiteralPath (Join-Path $PSScriptRoot 'device.credential.xml')
$key=$credential.GetNetworkCredential().Password
$utf8=New-Object System.Text.UTF8Encoding($false)
function Journal([string]$Event,[string]$JobId='',[string]$Action='') {
 $line=@{at=[DateTime]::UtcNow.ToString('o');event=$Event;job_id=$JobId;action=$Action}|ConvertTo-Json -Compress
 [IO.File]::AppendAllText((Join-Path $PSScriptRoot 'logs\journal.jsonl'),$line+"`r`n",$utf8)
}
function IsCancelled {
 $file=Join-Path $PSScriptRoot 'CANCEL'
 return ((Test-Path -LiteralPath $file) -and (Get-Content -LiteralPath $file -Raw -Encoding UTF8).Trim() -eq $job.job_id)
}
function TestProjectAccess($Configuration) {
 $allowed=@($Configuration.projects|Where-Object {$_.enabled -and $_.id -eq $Configuration.project_id -and $_.path -eq $Configuration.source})
 return ($allowed.Count -eq 1 -and $Configuration.project_id -match '^[a-f0-9]{32}$')
}
function HashBytes([byte[]]$Bytes) { $s=[Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($s.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() } finally {$s.Dispose()} }
function Request([string]$Path,$Data,[string]$Method='POST') {
 $body=if($Method -eq 'GET'){''}else{ConvertTo-Json -InputObject $Data -Depth 20 -Compress}
 $bytes=$utf8.GetBytes($body);$stamp=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString();$nonce=[Guid]::NewGuid().ToString('N')
 $canonical=$Method+"`n"+$Path+"`n"+$stamp+"`n"+$nonce+"`n"+(HashBytes $bytes)
 $h=New-Object Security.Cryptography.HMACSHA256;$h.Key=$utf8.GetBytes($key)
 try {$sig=([BitConverter]::ToString($h.ComputeHash($utf8.GetBytes($canonical)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
 $headers=@{'X-Principal'=$cfg.principal;'X-Time'=$stamp;'X-Nonce'=$nonce;'X-Signature'=$sig}
 $params=@{Uri=($cfg.gateway+$Path);Method=$Method;Headers=$headers;TimeoutSec=15;UseBasicParsing=$true;MaximumRedirection=0}
 if($Method -ne 'GET'){$params.Body=$bytes;$params.ContentType='application/json; charset=utf-8'}
 $response=(Invoke-WebRequest @params).Content | ConvertFrom-Json
 [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'connection.json'),(@{heartbeat=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json),$utf8)
 return $response
}
function SafePath([string]$Root,[string]$Relative) {
 if([IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':')){throw 'Absolute path or ADS denied'}
 $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\');$full=[IO.Path]::GetFullPath((Join-Path $rootFull $Relative))
 if(-not $full.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Path escape'}
 $walk=$full
 while($walk){
  if(Test-Path -LiteralPath $walk){if((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point denied'}}
  $walk=Split-Path -Parent $walk
 }
 return $full
}
function Upload([string]$File) {
 $f=Get-Item -LiteralPath $File;if($f.Length -gt 8MB){throw 'Artifact exceeds 8 MiB'}
 $b=[IO.File]::ReadAllBytes($f.FullName)
 Request ('/v1/jobs/'+$job.job_id+'/artifacts') @{lease=$lease;name=$f.Name;sha256=(HashBytes $b);content=[Convert]::ToBase64String($b)} | Out-Null
}
function RunTool([string]$Exe,[string[]]$Arguments,[string]$LogName='tool.log') {
 AssertNoInteractiveConflict $Exe $Arguments $PSScriptRoot
 if(-not (Test-Path -LiteralPath $Exe -PathType Leaf)){throw 'Configured tool missing'}
 # Argument values are fixed or generated paths. Refuse quotes/newlines before Windows quoting.
 foreach($a in $Arguments){if($a -match '["\r\n]'){throw 'Unsafe argument'}}
 $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$Exe
 $psi.Arguments=(($Arguments|ForEach-Object {'"'+$_+'"'}) -join ' ')
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.WorkingDirectory=$out
 $psi.StandardOutputEncoding=$utf8;$psi.StandardErrorEncoding=$utf8
 $p=New-Object Diagnostics.Process;$p.StartInfo=$psi
 $null=$p.Start();$stdout=[MaVkaOutputReader]::DrainAsync($p.StandardOutput,48000);$stderr=[MaVkaOutputReader]::DrainAsync($p.StandardError,12000);$watch=[Diagnostics.Stopwatch]::StartNew();$last=0
 try {
  while(-not $p.WaitForExit(500)){
   if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'STOP')){throw 'Emergency stop'}
   if(IsCancelled){throw 'Local cancellation'}
   if($watch.Elapsed.TotalSeconds -gt $cfg.timeout_seconds){throw 'Tool timeout'}
   if($watch.Elapsed.TotalSeconds-$last -gt 10){
    $state=Request ('/v1/jobs/'+$job.job_id+'/progress') @{lease=$lease}
    if($state.state -ne 'running'){throw 'Cancelled or lease lost'};$last=$watch.Elapsed.TotalSeconds
   }
   if($p.WorkingSet64 -gt $cfg.max_memory_mb*1MB){throw 'Memory quota'}
  }
  $p.WaitForExit();$exit=$p.ExitCode
 }finally{if(-not $p.HasExited){$p.Kill();$p.WaitForExit()}}
 # Bounded artifact retention; tools themselves are trusted reviewed executables/scripts.
 $text=$stdout.Result+"`n"+$stderr.Result
 if($text.Length -gt 60000){$text=$text.Substring(0,60000)}
 [IO.File]::WriteAllText((Join-Path $out $LogName),$text,$utf8);Upload (Join-Path $out $LogName)
 if($exit -ne 0){throw ('Tool exit '+$exit)}
 if([IO.Path]::GetFileName($Exe) -like 'Godot*' -and (TestGodotError $text)){throw ('Godot reported an error; see '+$LogName)}
 return @{exit_code=$exit;elapsed_seconds=$watch.Elapsed.TotalSeconds;output=$text.Substring(0,[Math]::Min(3000,$text.Length))}
}
$mutex=New-Object Threading.Mutex($false,('Local\MaVkaGameBridge_'+$cfg.device_id))
if(-not $mutex.WaitOne(0)){throw 'Agent already running'}
try {
 do {
  if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'STOP')){break}
  try {
   $cfg=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
   Request '/v1/heartbeat' @{version='1.1.0'} | Out-Null
   [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'connection.json'),(@{heartbeat=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json),$utf8)
   $claim=Request '/v1/lease' @{}
   if($null -eq $claim.job){if($Once){break};Start-Sleep -Seconds 5;continue}
   $job=$claim.job;$lease=$claim.lease
   Journal 'leased' $job.job_id $job.action
   WriteActiveState @{job_id=$job.job_id;action=$job.action;phase='leased'}
   $receipt=SafePath (Join-Path $PSScriptRoot 'receipts') ($job.job_id+'.json')
   if(Test-Path -LiteralPath $receipt){throw 'Local receipt exists: refusing duplicate execution'}
   [IO.File]::WriteAllText($receipt,($job|ConvertTo-Json -Depth 20),$utf8)
   $out=SafePath (Join-Path $PSScriptRoot 'output') $job.job_id;New-Item -ItemType Directory -Path $out | Out-Null
   $result=@{};$state='succeeded';$approvalInfo=@{mode='not_required'}
   try {
    if($job.device_id -ne $cfg.device_id -or $job.expires_at -lt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()){throw 'Device or expiry mismatch'}
    if($job.revision_sha -notmatch '^[a-f0-9]{40}$'){throw 'Invalid revision'}
    if((Get-PSDrive -Name ([IO.Path]::GetPathRoot($out).Substring(0,1))).Free -lt 2GB){throw 'Disk reserve'}
    $safe=@('system.health','blender.version','godot.version','workspace.status','workspace.results')
    if($job.action -notin $safe){
     if(-not(TestProjectAccess $cfg)){throw 'Project access denied; enable/select the project in MaVka Game Bridge'}
     if($cfg.project_id -notmatch '^[a-f0-9]{32}$'){throw 'Project ID'}
     $stageRoot=SafePath (Join-Path $PSScriptRoot 'staging') $cfg.project_id
     New-Item -ItemType Directory -Force -Path $stageRoot|Out-Null
     $null=SafePath $cfg.source 'project.godot'
    }
    if($job.action -eq 'scripts.register'){
     $review=GetScriptReview $cfg $job $PSScriptRoot
     $job|Add-Member -NotePropertyName script_review -NotePropertyValue $review
     [IO.File]::WriteAllText($receipt,($job|ConvertTo-Json -Depth 20),$utf8)
    }
    if($job.approval_required -or $job.action -notin $safe){
     Write-Host ('Waiting for local approval: '+$job.job_id)
     $approvalInfo=WaitLocalApproval $receipt
    }
    $confirmed=Request ('/v1/jobs/'+$job.job_id+'/progress') @{lease=$lease}
    if($confirmed.state -ne 'running'){throw 'Cancelled before execution'}
    switch -Exact ($job.action) {
     'system.health' {$result=@{agent='1.1.0';powershell=$PSVersionTable.PSVersion.ToString();os=[Environment]::OSVersion.VersionString;blender_present=(Test-Path -LiteralPath $cfg.blender);godot_present=(Test-Path -LiteralPath $cfg.godot);free_bytes=(Get-PSDrive -Name ([IO.Path]::GetPathRoot($out).Substring(0,1))).Free}}
     'blender.version' {$result=RunTool $cfg.blender @('--background','--factory-startup','--disable-autoexec','--version')}
     'godot.version' {$result=RunTool $cfg.godot @('--version')}
     'workspace.status' {$access=TestProjectAccess $cfg;$present=$false;if($access){$present=Test-Path -LiteralPath (Join-Path $cfg.source 'project.godot')};$result=@{project_access=$access;source_project_present=$present}}
     'scripts.register' {$result=RegisterReviewedScript $cfg $job $PSScriptRoot $ConfigPath $review}
     'workspace.results' {$result=@{entries=@(GetResultCatalog $cfg $PSScriptRoot|ForEach-Object {@{result_id=$_.result_id;display=$_.display;kind=$_.kind;project_id=$_.project_id;sha256=$_.sha256}})}}
     'gui.blender.open' {$result=OpenRemoteResult 'blender'}
     'gui.godot.editor' {$result=OpenRemoteResult 'editor'}
     'gui.godot.run' {$result=OpenRemoteResult 'run'}
     'workspace.stage_revision' {
      $dest=SafePath $stageRoot $job.revision_sha
      if(Test-Path -LiteralPath $dest){throw 'Immutable staging already exists'}
      $project=@($cfg.projects|Where-Object {$_.id -eq $cfg.project_id})[0]
      if(($project.PSObject.Properties.Name -notcontains 'kind' -or $project.kind -ne 'assets') -and -not(Test-Path -LiteralPath (Join-Path $cfg.source 'project.godot'))){throw 'Source project.godot missing'}
      $files=@(Get-ChildItem -LiteralPath $cfg.source -Force -Recurse)
      if($files|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}){throw 'Source reparse point denied'}
      if(($files|Where-Object {-not $_.PSIsContainer}|Measure-Object Length -Sum).Sum -gt 1GB){throw 'Snapshot quota'}
      New-Item -ItemType Directory -Path $dest|Out-Null
      foreach($f in $files){$rel=$f.FullName.Substring($cfg.source.TrimEnd('\').Length+1);if($rel -match '(^|\\)(\.git|\.godot)(\\|$)'){continue};$target=SafePath $dest $rel;if($f.PSIsContainer){New-Item -ItemType Directory -Force -Path $target|Out-Null}else{Copy-Item -LiteralPath $f.FullName -Destination $target}}
      $manifest=@(Get-ChildItem -LiteralPath $dest -File -Recurse | ForEach-Object {@{path=$_.FullName.Substring($dest.Length+1);sha256=(Get-BridgeFileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
      [IO.File]::WriteAllText((Join-Path $dest 'bridge-snapshot.json'),($manifest|ConvertTo-Json -Depth 5),$utf8)
      $result=@{snapshot_sha256=(Get-BridgeFileHash -LiteralPath (Join-Path $dest 'bridge-snapshot.json')).Hash;note='Local snapshot; revision SHA is provenance label, not proof of Git tree equivalence'}
     }
     {$_ -in @('blender.render','blender.export_gltf')} {
      $script=Join-Path $PSScriptRoot 'smoke.py'
      if((Get-BridgeFileHash -LiteralPath $script).Hash.ToLowerInvariant() -ne $cfg.smoke_sha256){throw 'Script checksum mismatch'}
      $result=RunTool $cfg.blender @('--background','--factory-startup','--disable-autoexec','--python',$script,'--',$out)
      Upload (Join-Path $out 'smoke.png');Upload (Join-Path $out 'smoke.glb')
     }
     'blender.scene.inspect' {
      $stage=SafePath $stageRoot $job.revision_sha
      $scene=SafePath $stage ([string]$job.arguments.scene)
      if([IO.Path]::GetExtension($scene) -ne '.blend'){throw 'Expected staged .blend'}
      $script=Join-Path $PSScriptRoot 'inspect_scene.py'
      if((Get-BridgeFileHash -LiteralPath $script).Hash.ToLowerInvariant() -ne $cfg.inspect_sha256){throw 'Inspector checksum mismatch'}
      $result=RunTool $cfg.blender @('--background','--factory-startup','--disable-autoexec','--python',$script,'--',$scene,$out)
      Upload (Join-Path $out 'scene.json')
     }
     'files.push' {$result=PushProjectFiles}
     'files.pull' {$result=PullProjectFiles}
     'files.publish' {$result=PublishProjectFiles}
     'godot.preview.capture' {$result=CaptureGodotFeedback}
     'pipeline.run' {$result=RunDevelopmentPipeline}
     {$_ -in @('blender.run_approved_script','godot.tests.headless')} {
      $id=[string]$job.arguments.script_id
      $scripts=@($cfg.approved_scripts|Where-Object {$_.id -eq $id -and $_.project_id -eq $cfg.project_id -and $_.revision_sha -eq $job.revision_sha -and $_.action -eq $job.action})
      if($scripts.Count -ne 1){throw 'Script not locally allowlisted for exact revision/action'}
      $stage=SafePath $stageRoot $job.revision_sha;$script=SafePath $stage $scripts[0].relative_path
      if((Get-BridgeFileHash -LiteralPath $script).Hash.ToLowerInvariant() -ne $scripts[0].sha256){throw 'Approved script hash mismatch'}
      if($job.action -eq 'blender.run_approved_script'){
       if([IO.Path]::GetExtension($script) -ne '.py'){throw 'Python script required'}
       $result=RunTool $cfg.blender @('--background','--factory-startup','--disable-autoexec','--python',$script,'--',$out)
      }else{
       if([IO.Path]::GetExtension($script) -ne '.gd'){throw 'GDScript required'}
       $result=RunTool $cfg.godot @('--headless','--path',$stage,'--script',$script)
      }
     }
     'godot.export' {
      $preset=[string]$job.arguments.preset
      if($preset -notin @($cfg.export_presets)){throw 'Export preset not locally allowlisted'}
      $stage=SafePath $stageRoot $job.revision_sha
      $build=Join-Path $out 'build.exe'
      $result=RunTool $cfg.godot @('--headless','--path',$stage,'--export-release',$preset,$build)
      if(-not(Test-Path -LiteralPath $build)){throw 'Export produced no executable'}
      Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $out -File|Where-Object {$_.Extension -in @('.exe','.pck')}|ForEach-Object {$_.FullName}) -DestinationPath (Join-Path $out 'build.zip')
      Upload (Join-Path $out 'build.zip')
     }
     'artifact.upload' {
      $id=[string]$job.arguments.source_job_id;$name=[string]$job.arguments.name
      if($id -notmatch '^[a-zA-Z0-9_-]{1,80}$' -or $name -notmatch '^[a-zA-Z0-9_-]{1,80}\.(png|glb|gltf|log|json|txt|zip)$'){throw 'Artifact selector'}
      Upload (SafePath (Join-Path $PSScriptRoot 'output') ($id+'\'+$name))
      $result=@{uploaded=$name;source_job_id=$id}
     }
     {$_ -in @('godot.project.import','godot.project.validate','godot.project.inspect')} {
      $stage=SafePath $stageRoot $job.revision_sha
      $null=SafePath $stage 'project.godot'
      if(-not(Test-Path -LiteralPath (Join-Path $stage 'project.godot'))){throw 'Staging missing'}
      if($job.action -eq 'godot.project.inspect'){$result=@{project_sha256=(Get-BridgeFileHash -LiteralPath (Join-Path $stage 'project.godot')).Hash}}
      else{
       if($job.action -eq 'godot.project.import'){
        $modelId=[string]$job.arguments.model_job_id
        if($modelId -notmatch '^[a-zA-Z0-9_-]{1,80}$'){throw 'Model job ID'}
        $model=SafePath (Join-Path $PSScriptRoot 'output') ($modelId+'\smoke.glb')
        $target=SafePath $stage 'bridge-smoke.glb'
        if(Test-Path -LiteralPath $target){throw 'Import destination exists'}
        Copy-Item -LiteralPath $model -Destination $target
       }
       $result=RunTool $cfg.godot @('--headless','--path',$stage,'--editor','--quit')
      }
     }
     default {throw 'Action not enabled in this agent release; denied'}
    }
   }catch{$state=if($_.Exception.Message -eq 'Local cancellation'){'cancelled'}else{'failed'};$result=@{error=$_.Exception.Message}}
   $result['approval']=$approvalInfo
   $final=Request ('/v1/jobs/'+$job.job_id+'/result') @{lease=$lease;state=$state;result=$result}
   if($final.state -in @('cancelled','expired')){$state=$final.state}
   [IO.File]::WriteAllText((Join-Path $out 'result.json'),(@{state=$state;result=$result;project_id=$cfg.project_id}|ConvertTo-Json -Depth 10),$utf8)
   Write-Host ($job.job_id+' '+$state)
   Journal $state $job.job_id $job.action
   Remove-Item -LiteralPath (Join-Path $PSScriptRoot 'active.json') -Force -ErrorAction SilentlyContinue
  }catch{Write-Warning ('Bridge paused: '+$_.Exception.Message);if(-not $Once){Start-Sleep -Seconds 10}}
 }while(-not $Once)
}finally{$mutex.ReleaseMutex();$mutex.Dispose();$key=$null}
