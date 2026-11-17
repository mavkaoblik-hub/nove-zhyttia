function GetMcpMaintenanceArguments($Configuration,[string]$Operation) {
 if($Operation -notin @('status','reset')){throw 'Unsupported MCP maintenance operation'}
 if(-not $Configuration.ssh_key_path -or -not $Configuration.ssh_host_key_alias){throw 'Configured pinned SSH connection required'}
 $arguments=@('-T','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o',('HostKeyAlias='+$Configuration.ssh_host_key_alias),'-o','IdentitiesOnly=yes','-o','ConnectTimeout=8','-o','ServerAliveInterval=5','-o','ServerAliveCountMax=2','-i',[string]$Configuration.ssh_key_path,'ubuntu@10.77.0.1',('sudo -n python3 /opt/oracle-vm-work/maintenance/mcp_sessions_admin.py '+$Operation))
 foreach($argument in $arguments){if($argument -match '["\r\n]'){throw 'Unsafe SSH argument'}}
 return $arguments
}
function StartMcpMaintenance($Configuration,[string]$Operation) {
 $arguments=GetMcpMaintenanceArguments $Configuration $Operation
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=(Get-Command ssh.exe -ErrorAction Stop).Source
 $info.Arguments=(($arguments|ForEach-Object {'"'+$_+'"'}) -join ' ')
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $info.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
 $info.StandardErrorEncoding=$info.StandardOutputEncoding
 $process=New-Object Diagnostics.Process;$process.StartInfo=$info;$null=$process.Start()
 return @{process=$process;stdout=[MaVkaOutputReader]::DrainAsync($process.StandardOutput,16000);stderr=[MaVkaOutputReader]::DrainAsync($process.StandardError,4000);watch=[Diagnostics.Stopwatch]::StartNew();operation=$Operation}
}
function ReceiveMcpMaintenance($Task) {
 if(-not $Task.process.HasExited){
  if($Task.watch.Elapsed.TotalSeconds -gt 45){$Task.process.Kill();throw 'MCP maintenance timed out; refresh status before retrying reset'}
  return $null
 }
 $Task.process.WaitForExit()
 $text=$Task.stdout.GetAwaiter().GetResult()
 if($Task.process.ExitCode -ne 0){
  try{$failure=$text|ConvertFrom-Json;if($failure.error){throw ('MCP: '+$failure.error)}}catch{if($_.Exception.Message -like 'MCP: *'){throw}}
  throw ('SSH maintenance failed: '+$Task.stderr.GetAwaiter().GetResult())
 }
 $data=$text|ConvertFrom-Json
 if(-not $data.ok -or $data.operation -ne $Task.operation -or [int]$data.current -lt 0 -or [int]$data.limit -lt 1){throw 'Invalid MCP maintenance response'}
 return $data
}
function ClearBridgeJournal([string]$InstallRoot) {
 $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
 $logs=ResolveResultPath $root 'logs'
 $archive=ResolveResultPath $logs ('archive\'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
 [IO.Directory]::CreateDirectory($archive)|Out-Null
 $moved=0
 foreach($name in @('journal.jsonl','ui-journal.jsonl')){
  $file=ResolveResultPath $logs $name;$destination=ResolveResultPath $archive $name
  for($attempt=0;$attempt -lt 5;$attempt++){
   try{if([IO.File]::Exists($file)){[IO.File]::Move($file,$destination);$moved++};break}
   catch{if($attempt -eq 4){throw};Start-Sleep -Milliseconds 100}
  }
 }
 return @{archive=$archive;files=$moved}
}
