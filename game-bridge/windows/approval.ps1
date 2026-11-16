function TestAutoApproval($Policy,$Configuration,$Task,[bool]$ProjectAllowed,[string]$ToolRoot) {
 if(-not $ProjectAllowed -or $null -eq $Policy -or -not $Policy.enabled -or $Policy.project_id -ne $Configuration.project_id){return $false}
 if($Policy.delay_seconds -lt 5 -or $Policy.delay_seconds -gt 300){return $false}
 # Never auto-approve file export/import/promotion, new code, builds, or arbitrary parameters.
 if($Task.action -eq 'workspace.stage_revision'){return $true}
 if($Task.action -in @('blender.render','blender.export_gltf')){
  return ((Get-BridgeFileHash -LiteralPath (Join-Path $ToolRoot 'smoke.py')).Hash -eq $Configuration.smoke_sha256)
 }
 return $false
}
function WriteActiveState($State,[string]$Path=(Join-Path $PSScriptRoot 'active.json')) {
 $temp=$Path+'.tmp'
 [IO.File]::WriteAllText($temp,($State|ConvertTo-Json -Depth 8),$utf8)
 if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,($Path+'.previous'))}else{[IO.File]::Move($temp,$Path)}
}
function WaitLocalApproval([string]$Receipt) {
 $approval=SafePath (Join-Path $PSScriptRoot 'approvals') ($job.job_id+'.sha256')
 $expected=HashBytes ([IO.File]::ReadAllBytes($Receipt));$manualDeadline=[DateTime]::UtcNow.AddMinutes(10)
 $countdown=$null;$lastDelay=0;$lastRenew=[DateTime]::MinValue;$mode='manual';$policyHash=$null
 while(-not(Test-Path -LiteralPath $approval)){
  if([DateTime]::UtcNow -gt $manualDeadline -or (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'STOP'))){throw 'Approval timeout/stopped'}
  if(IsCancelled){throw 'Local cancellation'}
  if(([DateTime]::UtcNow-$lastRenew).TotalSeconds -ge 10){
   $pending=Request ('/v1/jobs/'+$job.job_id+'/progress') @{lease=$lease}
   if($pending.state -ne 'running'){throw 'Cancelled'};$lastRenew=[DateTime]::UtcNow
  }
  $policy=$null;$policyPath=Join-Path $PSScriptRoot 'approval-policy.json'
  if(Test-Path -LiteralPath $policyPath){try{$policy=Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{$policy=$null}}
  $eligible=TestAutoApproval $policy $cfg $job (TestProjectAccess $cfg) $PSScriptRoot
  $remaining=$null
  if($eligible){
   if($null -eq $countdown -or $lastDelay -ne $policy.delay_seconds){$countdown=[DateTime]::UtcNow.AddSeconds($policy.delay_seconds);$lastDelay=$policy.delay_seconds}
   $remaining=[Math]::Max(0,[int][Math]::Ceiling(($countdown-[DateTime]::UtcNow).TotalSeconds))
   if($remaining -eq 0){
    $policyHash=(Get-BridgeFileHash -LiteralPath $policyPath).Hash
    $expected|Set-Content -LiteralPath $approval -Encoding ASCII
    $mode='automatic';Journal ('auto_approved_after_'+$lastDelay+'s') $job.job_id $job.action;break
   }
  }else{$countdown=$null;$lastDelay=0}
  WriteActiveState @{job_id=$job.job_id;action=$job.action;phase='awaiting_approval';auto_approval=$eligible;remaining_seconds=$remaining}
  Start-Sleep -Seconds 1
 }
 if((Get-Content -LiteralPath $approval -Raw -Encoding UTF8).Trim() -ne $expected){throw 'Approval hash mismatch'}
 WriteActiveState @{job_id=$job.job_id;action=$job.action;phase='running'}
 return @{mode=$mode;policy_sha256=$policyHash}
}
