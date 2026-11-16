# One user application. Tray lifetime equals window lifetime; no Windows autostart.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference='Stop'
$appMutex=New-Object Threading.Mutex($false,'Local\MaVkaGameBridgeUI')
if(-not $appMutex.WaitOne(0)){[Windows.Forms.MessageBox]::Show('MaVka Game Bridge вже відкрита.')|Out-Null;$appMutex.Dispose();exit}
$script:process=$null;$script:closing=$false
$script:cfgPath=Join-Path $PSScriptRoot 'config.json'
$script:cfg=Get-Content -LiteralPath $script:cfgPath -Raw -Encoding UTF8|ConvertFrom-Json
$form=New-Object Windows.Forms.Form
$form.Text='MaVka Game Bridge';$form.Size=New-Object Drawing.Size(820,660);$form.StartPosition='CenterScreen'
$form.Icon=[Drawing.SystemIcons]::Application
$status=New-Object Windows.Forms.Label;$status.Text='Відключено';$status.SetBounds(15,15,760,25)
$connect=New-Object Windows.Forms.Button;$connect.Text='Підключити';$connect.SetBounds(15,45,150,32)
$disconnect=New-Object Windows.Forms.Button;$disconnect.Text='Відключити';$disconnect.SetBounds(175,45,150,32)
$stop=New-Object Windows.Forms.Button;$stop.Text='Зупинити завдання';$stop.SetBounds(335,45,180,32)
$approve=New-Object Windows.Forms.Button;$approve.Text='Переглянути завдання';$approve.SetBounds(525,45,250,32)
$label=New-Object Windows.Forms.Label;$label.Text='Проєкти: прапорець дозволяє доступ. Обраний рядок — активний проєкт. Зміни лише після відключення.';$label.SetBounds(15,90,760,35)
$projects=New-Object Windows.Forms.ListView;$projects.SetBounds(15,130,760,135);$projects.View='Details';$projects.CheckBoxes=$true;$projects.FullRowSelect=$true;$projects.MultiSelect=$false
$null=$projects.Columns.Add('Проєкт',190);$null=$projects.Columns.Add('Каталог',540)
foreach($p in $script:cfg.projects){$item=New-Object Windows.Forms.ListViewItem([string]$p.name);$null=$item.SubItems.Add([string]$p.path);$item.Checked=[bool]$p.enabled;$item.Tag=[string]$p.id;$null=$projects.Items.Add($item);if($p.id -eq $script:cfg.project_id){$item.Selected=$true}}
$add=New-Object Windows.Forms.Button;$add.Text='Додати проєкт';$add.SetBounds(15,275,170,30)
$save=New-Object Windows.Forms.Button;$save.Text='Зберегти доступ';$save.SetBounds(195,275,190,30)
$log=New-Object Windows.Forms.TextBox;$log.SetBounds(15,320,760,275);$log.Multiline=$true;$log.ReadOnly=$true;$log.ScrollBars='Both';$log.Font=New-Object Drawing.Font('Consolas',9)
$form.Controls.AddRange(@($status,$connect,$disconnect,$stop,$approve,$label,$projects,$add,$save,$log))
$tray=New-Object Windows.Forms.NotifyIcon;$tray.Icon=$form.Icon;$tray.Text='MaVka Game Bridge';$tray.Visible=$true
$menu=New-Object Windows.Forms.ContextMenuStrip
$openItem=$menu.Items.Add('Відкрити');$connectItem=$menu.Items.Add('Підключити');$disconnectItem=$menu.Items.Add('Відключити');$stopItem=$menu.Items.Add('Зупинити завдання');$exitItem=$menu.Items.Add('Вийти')
$tray.ContextMenuStrip=$menu
function AppLog([string]$event) {
 $line=@{at=[DateTime]::UtcNow.ToString('o');event=$event}|ConvertTo-Json -Compress
 [IO.File]::AppendAllText((Join-Path $PSScriptRoot 'logs\ui-journal.jsonl'),$line+"`r`n",[Text.UTF8Encoding]::new($false))
}
function ShowError($e){[Windows.Forms.MessageBox]::Show([string]$e,'MaVka Game Bridge')|Out-Null}
function ConnectBridge {
 try{
  if($script:process -and -not $script:process.HasExited){return}
  Remove-Item -LiteralPath (Join-Path $PSScriptRoot 'STOP') -Force -ErrorAction SilentlyContinue
  $pi=New-Object Diagnostics.ProcessStartInfo;$pi.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $pi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'start-bridge.ps1')+'"'
  $pi.UseShellExecute=$false;$pi.CreateNoWindow=$true
  $pi.RedirectStandardOutput=$true;$pi.RedirectStandardError=$true
  $script:process=New-Object Diagnostics.Process;$script:process.StartInfo=$pi;$null=$script:process.Start()
  $script:stdout=$script:process.StandardOutput.ReadToEndAsync();$script:stderr=$script:process.StandardError.ReadToEndAsync()
  AppLog 'connect_requested'
 }catch{ShowError $_.Exception.Message}
}
function DisconnectBridge {
 New-Item -ItemType File -Force -Path (Join-Path $PSScriptRoot 'STOP')|Out-Null
 AppLog 'disconnect_requested'
}
function StopJob {
 $p=Join-Path $PSScriptRoot 'active.json'
 if(Test-Path -LiteralPath $p){$j=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json
  if($j.job_id -match '^[a-zA-Z0-9_-]{1,80}$'){[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'CANCEL'),$j.job_id);AppLog ('cancel_requested '+$j.job_id)}
 }
}
$connect.Add_Click({ConnectBridge});$connectItem.Add_Click({ConnectBridge})
$disconnect.Add_Click({DisconnectBridge});$disconnectItem.Add_Click({DisconnectBridge})
$stop.Add_Click({StopJob});$stopItem.Add_Click({StopJob})
$open={ $form.Show();$form.WindowState='Normal';$form.Activate() };$openItem.Add_Click($open);$tray.Add_DoubleClick($open)
$exitItem.Add_Click({$form.Close()})
$add.Add_Click({
 $dialog=New-Object Windows.Forms.FolderBrowserDialog
 try{if($dialog.ShowDialog() -eq 'OK'){
  $path=[IO.Path]::GetFullPath($dialog.SelectedPath)
  if(-not(Test-Path -LiteralPath (Join-Path $path 'project.godot'))){throw 'У каталозі немає project.godot'}
  $item=New-Object Windows.Forms.ListViewItem((Split-Path -Leaf $path));$null=$item.SubItems.Add($path);$item.Tag=[Guid]::NewGuid().ToString('N');$item.Checked=$false;$null=$projects.Items.Add($item)
 }}catch{ShowError $_.Exception.Message}finally{$dialog.Dispose()}
})
$save.Add_Click({
 try{
  if($script:process -and -not $script:process.HasExited){throw 'Спочатку відключіть Bridge'}
  if($projects.SelectedItems.Count -ne 1){throw 'Оберіть активний проєкт'}
  $list=@();foreach($i in $projects.Items){$list+=@{id=[string]$i.Tag;name=$i.Text;path=$i.SubItems[1].Text;enabled=[bool]$i.Checked}}
  Copy-Item -LiteralPath $script:cfgPath -Destination ($script:cfgPath+'.previous') -Force
  $script:cfg.projects=$list;$script:cfg.project_id=[string]$projects.SelectedItems[0].Tag;$script:cfg.source=$projects.SelectedItems[0].SubItems[1].Text
  $script:cfg|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $script:cfgPath -Encoding UTF8
  AppLog ('project_access_changed '+(($list|ForEach-Object {$_.id+':'+$_.enabled})-join ','));$status.Text='Доступ збережено. Можна підключити.'
 }catch{ShowError $_.Exception.Message}
})
$approve.Add_Click({
 try{
  $a=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'active.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if($a.job_id -notmatch '^[a-zA-Z0-9_-]{1,80}$'){throw 'Некоректний ID'}
  $file=Join-Path $PSScriptRoot ('receipts\'+$a.job_id+'.json')
  $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
  $text=Get-Content -LiteralPath $file -Raw -Encoding UTF8
  if([Windows.Forms.MessageBox]::Show($text+"`r`nДозволити саме це завдання?",'Підтвердження','YesNo','Warning') -eq 'Yes'){
   $hash|Set-Content -LiteralPath (Join-Path $PSScriptRoot ('approvals\'+$a.job_id+'.sha256')) -Encoding ASCII;AppLog ('approved '+$a.job_id)
  }else{StopJob}
 }catch{ShowError $_.Exception.Message}
})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=1000
$timer.Add_Tick({
 try{
  $running=$script:process -and -not $script:process.HasExited
  $connect.Enabled=-not $running;$disconnect.Enabled=[bool]$running;$add.Enabled=-not $running;$save.Enabled=-not $running;$projects.Enabled=-not $running
  if($running){$status.Text='Агент запущений; зʼєднання перевіряється за heartbeat. Відключити — завершити роботу.'}elseif($script:process){$status.Text='Відключено (код '+$script:process.ExitCode+'). '+$script:stderr.Result}
  $connection=Join-Path $PSScriptRoot 'connection.json'
  if($running -and (Test-Path -LiteralPath $connection)){
   $last=Get-Content -LiteralPath $connection -Raw -Encoding UTF8|ConvertFrom-Json
   if(([DateTime]::UtcNow-[DateTime]::Parse($last.heartbeat).ToUniversalTime()).TotalSeconds -lt 30){$status.Text='Підключено до Oracle VM. Heartbeat: '+$last.heartbeat}
  }
  $lines=@();foreach($f in @('journal.jsonl','ui-journal.jsonl')){ $p=Join-Path $PSScriptRoot ('logs\'+$f);if(Test-Path -LiteralPath $p){$lines+=@(Get-Content -LiteralPath $p -Tail 100 -Encoding UTF8)}}
  $log.Text=($lines|Sort-Object)-join "`r`n"
 }catch{$status.Text=$_.Exception.Message}
})
$form.Add_Shown({$timer.Start();AppLog 'application_opened';ConnectBridge})
$form.Add_FormClosing({param($sender,$e)
 if($script:process -and -not $script:process.HasExited){
  DisconnectBridge
  if(-not $script:process.WaitForExit(20000)){$e.Cancel=$true;ShowError 'Агент ще завершує завдання. Зачекайте й закрийте вікно повторно.';return}
 }
 $timer.Stop();$tray.Visible=$false;AppLog 'application_closed'
})
try{[Windows.Forms.Application]::Run($form)}finally{$timer.Dispose();$tray.Dispose();$form.Dispose();if($script:process){$script:process.Dispose()};$appMutex.ReleaseMutex();$appMutex.Dispose()}
