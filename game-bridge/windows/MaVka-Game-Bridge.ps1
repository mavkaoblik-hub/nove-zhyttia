. (Join-Path $PSScriptRoot 'hash.ps1')
# One user application. Tray lifetime equals window lifetime; no Windows autostart.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'results.ps1')
. (Join-Path $PSScriptRoot 'process-output.ps1')
. (Join-Path $PSScriptRoot 'maintenance.ps1')
$ErrorActionPreference='Stop'
$appMutex=New-Object Threading.Mutex($false,'Local\MaVkaGameBridgeUI')
if(-not $appMutex.WaitOne(0)){[Windows.Forms.MessageBox]::Show('MaVka Game Bridge вже відкрита.')|Out-Null;$appMutex.Dispose();exit}
$script:process=$null;$script:closing=$false
$script:cfgPath=Join-Path $PSScriptRoot 'config.json'
$script:cfg=Get-Content -LiteralPath $script:cfgPath -Raw -Encoding UTF8|ConvertFrom-Json
$form=New-Object Windows.Forms.Form
$form.Text='MaVka Game Bridge';$form.Size=New-Object Drawing.Size(820,720);$form.StartPosition='CenterScreen'
$form.MinimumSize=New-Object Drawing.Size(820,720)
$form.Icon=[Drawing.SystemIcons]::Application
$status=New-Object Windows.Forms.Label;$status.Text='Відключено';$status.SetBounds(15,15,760,25)
$connect=New-Object Windows.Forms.Button;$connect.Text='Підключити';$connect.SetBounds(15,45,150,32)
$disconnect=New-Object Windows.Forms.Button;$disconnect.Text='Відключити';$disconnect.SetBounds(175,45,150,32)
$stop=New-Object Windows.Forms.Button;$stop.Text='Зупинити завдання';$stop.SetBounds(335,45,180,32)
$approve=New-Object Windows.Forms.Button;$approve.Text='Переглянути завдання';$approve.SetBounds(525,45,250,32)
$auto=New-Object Windows.Forms.CheckBox;$auto.Text='Автосхвалення всіх команд';$auto.SetBounds(15,90,340,25)
$delayLabel=New-Object Windows.Forms.Label;$delayLabel.Text='Затримка, с:';$delayLabel.SetBounds(365,93,110,22)
$delay=New-Object Windows.Forms.NumericUpDown;$delay.Minimum=5;$delay.Maximum=300;$delay.Value=15;$delay.SetBounds(480,90,65,25)
$countdownLabel=New-Object Windows.Forms.Label;$countdownLabel.SetBounds(560,93,215,25);$countdownLabel.Anchor='Top,Right'
$progress=New-Object Windows.Forms.ProgressBar;$progress.SetBounds(15,117,760,8);$progress.Anchor='Top,Left,Right';$progress.Visible=$false
$policyPath=Join-Path $PSScriptRoot 'approval-policy.json'
if(Test-Path -LiteralPath $policyPath){try{$policy=Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8|ConvertFrom-Json;if($policy.project_id -eq $script:cfg.project_id){$auto.Checked=[bool]$policy.enabled;$delay.Value=[Math]::Max(5,[Math]::Min(300,[int]$policy.delay_seconds))}}catch{}}
$label=New-Object Windows.Forms.Label;$label.Text='Проєкти: прапорець дозволяє доступ. Обраний рядок — активний проєкт. Зміни лише після відключення.';$label.SetBounds(15,130,760,35)
$projects=New-Object Windows.Forms.ListView;$projects.SetBounds(15,170,760,135);$projects.View='Details';$projects.CheckBoxes=$true;$projects.FullRowSelect=$true;$projects.MultiSelect=$false
$null=$projects.Columns.Add('Проєкт',190);$null=$projects.Columns.Add('Каталог',540)
foreach($p in $script:cfg.projects){$item=New-Object Windows.Forms.ListViewItem([string]$p.name);$null=$item.SubItems.Add([string]$p.path);$item.Checked=[bool]$p.enabled;$item.Tag=[string]$p.id;$null=$projects.Items.Add($item);if($p.id -eq $script:cfg.project_id){$item.Selected=$true}}
$add=New-Object Windows.Forms.Button;$add.Text='Додати проєкт';$add.SetBounds(15,315,170,30)
$save=New-Object Windows.Forms.Button;$save.Text='Зберегти доступ';$save.SetBounds(195,315,190,30)
$log=New-Object Windows.Forms.TextBox;$log.SetBounds(15,360,760,295);$log.Multiline=$true;$log.ReadOnly=$true;$log.ScrollBars='Both';$log.Font=New-Object Drawing.Font('Consolas',9)
$log.WordWrap=$false;$log.Anchor='Top,Bottom,Left,Right'
$projects.Anchor='Top,Left,Right';$label.Anchor='Top,Left,Right';$status.Anchor='Top,Left,Right';$approve.Anchor='Top,Right'
$form.Controls.AddRange(@($status,$connect,$disconnect,$stop,$approve,$auto,$delayLabel,$delay,$countdownLabel,$progress,$label,$projects,$add,$save,$log))
$tabs=New-Object Windows.Forms.TabControl;$tabs.SetBounds(15,360,760,295);$tabs.Anchor='Top,Bottom,Left,Right'
$journalTab=New-Object Windows.Forms.TabPage;$journalTab.Text='Журнал'
$renderTab=New-Object Windows.Forms.TabPage;$renderTab.Text='Рендери'
$detailsTab=New-Object Windows.Forms.TabPage;$detailsTab.Text='Результат і помилки'
$log.Dock='Fill';$journalTab.Controls.Add($log)
$imageChoice=New-Object Windows.Forms.ComboBox;$imageChoice.Dock='Top';$imageChoice.DropDownStyle='DropDownList'
$picture=New-Object Windows.Forms.PictureBox;$picture.Dock='Fill';$picture.SizeMode='Zoom';$picture.BackColor=[Drawing.Color]::FromArgb(28,28,28)
$renderTab.Controls.Add($picture);$renderTab.Controls.Add($imageChoice)
$details=New-Object Windows.Forms.TextBox;$details.Dock='Fill';$details.Multiline=$true;$details.ReadOnly=$true;$details.ScrollBars='Both';$details.WordWrap=$false;$details.Font=New-Object Drawing.Font('Consolas',10)
$detailsTab.Controls.Add($details)
$openTab=New-Object Windows.Forms.TabPage;$openTab.Text='Відкрити результат'
$resultChoice=New-Object Windows.Forms.ComboBox;$resultChoice.Dock='Top';$resultChoice.DropDownStyle='DropDownList'
$resultButtons=New-Object Windows.Forms.FlowLayoutPanel;$resultButtons.Dock='Top';$resultButtons.Height=80
$refreshResults=New-Object Windows.Forms.Button;$refreshResults.Text='Оновити список';$refreshResults.Width=150
$openBlender=New-Object Windows.Forms.Button;$openBlender.Text='Відкрити в Blender';$openBlender.Width=180
$openGodot=New-Object Windows.Forms.Button;$openGodot.Text='Редактор Godot';$openGodot.Width=150
$runGodot=New-Object Windows.Forms.Button;$runGodot.Text='Запустити Godot';$runGodot.Width=160
$resultButtons.Controls.AddRange(@($refreshResults,$openBlender,$openGodot,$runGodot))
$remoteOpen=New-Object Windows.Forms.CheckBox;$remoteOpen.Text='Дозволити відкриття результатів з чату для активного проєкту';$remoteOpen.Width=650
$currentProject=@($script:cfg.projects|Where-Object {$_.id -eq $script:cfg.project_id})[0]
if($currentProject.PSObject.Properties.Name -contains 'remote_open_enabled'){$remoteOpen.Checked=[bool]$currentProject.remote_open_enabled}
$resultButtons.Controls.Add($remoteOpen)
$remoteOpen.Add_CheckedChanged({
 try{if($script:process -and -not $script:process.HasExited){throw 'Спочатку відключіть Bridge для зміни дозволу'}
  $script:cfg=Get-Content -LiteralPath $script:cfgPath -Raw -Encoding UTF8|ConvertFrom-Json
  $p=@($script:cfg.projects|Where-Object {$_.id -eq $script:cfg.project_id})[0]
  $p|Add-Member -NotePropertyName remote_open_enabled -NotePropertyValue ([bool]$remoteOpen.Checked) -Force
  $script:cfg|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $script:cfgPath -Encoding UTF8
  AppLog ('remote_open_permission_changed '+$p.id+'='+$remoteOpen.Checked)
 }catch{ShowError $_.Exception.Message}
})
$openNote=New-Object Windows.Forms.Label;$openNote.Dock='Fill';$openNote.Text='Відкриваються лише результати та staging дозволених проєктів. Blender запускається без autoexec. Godot виконує код обраного staging-проєкту. Оригінали не підміняються.'
$openTab.Controls.Add($openNote);$openTab.Controls.Add($resultButtons);$openTab.Controls.Add($resultChoice)
$maintenanceTab=New-Object Windows.Forms.TabPage;$maintenanceTab.Text='Обслуговування'
$maintenanceButtons=New-Object Windows.Forms.FlowLayoutPanel;$maintenanceButtons.Dock='Top';$maintenanceButtons.Height=80
$refreshSessions=New-Object Windows.Forms.Button;$refreshSessions.Text='Оновити лічильник';$refreshSessions.Width=180;$refreshSessions.Height=32
$resetSessions=New-Object Windows.Forms.Button;$resetSessions.Text='Скинути сесії та лічильник';$resetSessions.Width=240;$resetSessions.Height=32
$clearJournal=New-Object Windows.Forms.Button;$clearJournal.Text='Очистити журнал';$clearJournal.Width=170;$clearJournal.Height=32
$maintenanceButtons.Controls.AddRange(@($refreshSessions,$resetSessions,$clearJournal))
$sessionLabel=New-Object Windows.Forms.Label;$sessionLabel.Dock='Fill';$sessionLabel.Padding=New-Object Windows.Forms.Padding(10);$sessionLabel.Text="MCP-сесії: ще не перевірено.`r`nНатисніть «Оновити лічильник».`r`n`r`nСкидання очищує лише хмарні MCP-сесії та їхній лічильник. Працює через SSH навіть при SESSION_LIMIT. Завдання гри й VPN не перезапускаються.`r`nЖурнал архівується; файли результатів і журнали самих завдань зберігаються."
$maintenanceTab.Controls.Add($sessionLabel);$maintenanceTab.Controls.Add($maintenanceButtons)
$tabs.TabPages.AddRange(@($journalTab,$renderTab,$detailsTab,$openTab,$maintenanceTab));$form.Controls.Add($tabs)
$script:maintenanceJob=$null
function BeginMaintenance([string]$Operation) {
 try{
  if($script:maintenanceJob){return}
  $configuration=Get-Content -LiteralPath $script:cfgPath -Raw -Encoding UTF8|ConvertFrom-Json
  $script:maintenanceJob=StartMcpMaintenance $configuration $Operation
  $refreshSessions.Enabled=$false;$resetSessions.Enabled=$false
  $sessionLabel.Text=if($Operation -eq 'reset'){'Скидання MCP-сесій через SSH...'}else{'Отримання лічильника MCP-сесій через SSH...'}
  AppLog ('mcp_'+$Operation+'_requested')
 }catch{$sessionLabel.Text=$_.Exception.Message;AppLog ('mcp_'+$Operation+'_failed')}
}
$refreshSessions.Add_Click({BeginMaintenance 'status'})
$resetSessions.Add_Click({BeginMaintenance 'reset'})
$clearJournal.Add_Click({
 try{$saved=ClearBridgeJournal $PSScriptRoot;$log.Clear();AppLog 'journal_cleared';$sessionLabel.Text='Журнал очищено. Архів: '+$saved.archive}
 catch{$sessionLabel.Text='Не вдалося очистити журнал: '+$_.Exception.Message}
})
$script:resultEntries=@{}
$refreshResults.Add_Click({
 try{$script:resultEntries=@{};$resultChoice.Items.Clear()
  foreach($entry in @(GetResultCatalog $script:cfg $PSScriptRoot)){$script:resultEntries[$entry.display]=$entry;$null=$resultChoice.Items.Add($entry.display)}
  if($resultChoice.Items.Count){$resultChoice.SelectedIndex=0}
 }catch{ShowError $_.Exception.Message}
})
function OpenChosenResult([string]$Mode) {
 try{
  $entry=$script:resultEntries[[string]$resultChoice.SelectedItem];if(-not $entry){throw 'Оберіть результат зі списку'}
  $question=if($Mode -eq 'blender'){'Відкрити цю копію в Blender без autoexec?'}else{'Відкрити staging у Godot? Код цього проєкту може виконуватися.'}
  if([Windows.Forms.MessageBox]::Show(($question+"`r`n"+$entry.path),'Відкрити результат','YesNo','Question') -ne 'Yes'){return}
  $pidValue=StartResultTool $entry $script:cfg $Mode $PSScriptRoot;AppLog ('opened_result '+$Mode+' pid='+$pidValue)
 }catch{ShowError $_.Exception.Message}
}
$openBlender.Add_Click({OpenChosenResult 'blender'});$openGodot.Add_Click({OpenChosenResult 'editor'});$runGodot.Add_Click({OpenChosenResult 'run'})
$script:imageFiles=@{};$script:lastOutputScan=[DateTime]::MinValue
$imageChoice.Add_SelectedIndexChanged({
 try{
  $path=$script:imageFiles[[string]$imageChoice.SelectedItem]
  if(-not $path){return}
  $file=Get-Item -LiteralPath $path;if($file.Length -gt 16MB){throw 'Зображення перевищує 16 MiB'}
  $stream=[IO.File]::OpenRead($path)
  try{$rawImage=[Drawing.Image]::FromStream($stream);try{$newImage=$rawImage.Clone()}finally{$rawImage.Dispose()}}finally{$stream.Dispose()}
  $old=$picture.Image;$picture.Image=$newImage;if($old){$old.Dispose()}
 }catch{$details.Text=$_.Exception.Message;$tabs.SelectedTab=$detailsTab}
})
$tray=New-Object Windows.Forms.NotifyIcon;$tray.Icon=$form.Icon;$tray.Text='MaVka Game Bridge';$tray.Visible=$true
$menu=New-Object Windows.Forms.ContextMenuStrip
$openItem=$menu.Items.Add('Відкрити');$connectItem=$menu.Items.Add('Підключити');$disconnectItem=$menu.Items.Add('Відключити');$stopItem=$menu.Items.Add('Зупинити завдання');$exitItem=$menu.Items.Add('Вийти')
$tray.ContextMenuStrip=$menu
function AppLog([string]$event) {
 $line=@{at=[DateTime]::UtcNow.ToString('o');event=$event}|ConvertTo-Json -Compress
 [IO.File]::AppendAllText((Join-Path $PSScriptRoot 'logs\ui-journal.jsonl'),$line+"`r`n",[Text.UTF8Encoding]::new($false))
}
function ShowError($e){[Windows.Forms.MessageBox]::Show([string]$e,'MaVka Game Bridge')|Out-Null}
function SaveApprovalPolicy {
 @{enabled=[bool]$auto.Checked;project_id=$script:cfg.project_id;delay_seconds=[int]$delay.Value}|ConvertTo-Json|Set-Content -LiteralPath $policyPath -Encoding UTF8
 AppLog ('approval_policy_changed enabled='+$auto.Checked+' delay='+$delay.Value)
}
$auto.Add_CheckedChanged({SaveApprovalPolicy});$delay.Add_ValueChanged({SaveApprovalPolicy})
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
  $item=New-Object Windows.Forms.ListViewItem((Split-Path -Leaf $path));$null=$item.SubItems.Add($path);$item.Tag=[Guid]::NewGuid().ToString('N');$item.Checked=$false;$null=$projects.Items.Add($item)
 }}catch{ShowError $_.Exception.Message}finally{$dialog.Dispose()}
})
$save.Add_Click({
 try{
  if($script:process -and -not $script:process.HasExited){throw 'Спочатку відключіть Bridge'}
  if($projects.SelectedItems.Count -ne 1){throw 'Оберіть активний проєкт'}
  $script:cfg=Get-Content -LiteralPath $script:cfgPath -Raw -Encoding UTF8|ConvertFrom-Json
  $list=@();foreach($i in $projects.Items){
   $kind=if(Test-Path -LiteralPath (Join-Path $i.SubItems[1].Text 'project.godot')){'godot'}else{'assets'}
   $prior=@($script:cfg.projects|Where-Object {$_.id -eq [string]$i.Tag})
   $item=@{id=[string]$i.Tag;name=$i.Text;path=$i.SubItems[1].Text;enabled=[bool]$i.Checked;kind=$kind;remote_open_enabled=$false;output_subdirectory=''}
   if($prior.Count){foreach($field in @('remote_open_enabled','output_subdirectory')){if($prior[0].PSObject.Properties.Name -contains $field){$item[$field]=$prior[0].$field}}}
   $list+=$item
  }
  Copy-Item -LiteralPath $script:cfgPath -Destination ($script:cfgPath+'.previous') -Force
  $script:cfg.projects=$list;$script:cfg.project_id=[string]$projects.SelectedItems[0].Tag;$script:cfg.source=$projects.SelectedItems[0].SubItems[1].Text
  $script:cfg|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $script:cfgPath -Encoding UTF8
  $auto.Checked=$false;SaveApprovalPolicy
  AppLog ('project_access_changed '+(($list|ForEach-Object {$_.id+':'+$_.enabled})-join ','));$status.Text='Доступ збережено. Можна підключити.'
 }catch{ShowError $_.Exception.Message}
})
$approve.Add_Click({
 try{
  $activeFile=Join-Path $PSScriptRoot 'active.json'
  if(-not(Test-Path -LiteralPath $activeFile)){$status.Text='Немає активного завдання. Завершені дії показані в журналі.';return}
  $a=Get-Content -LiteralPath $activeFile -Raw -Encoding UTF8|ConvertFrom-Json
  if($a.job_id -notmatch '^[a-zA-Z0-9_-]{1,80}$'){throw 'Некоректний ID'}
  $file=Join-Path $PSScriptRoot ('receipts\'+$a.job_id+'.json')
  $hash=(Get-BridgeFileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
  $text=Get-Content -LiteralPath $file -Raw -Encoding UTF8
  $receiptObject=$text|ConvertFrom-Json
  $decision=$false
  if($receiptObject.action -eq 'scripts.register'){
   $reviewForm=New-Object Windows.Forms.Form;$reviewForm.Text='Дозвіл на код: лише цей проєкт, версія та SHA-256';$reviewForm.Size=New-Object Drawing.Size(900,700);$reviewForm.StartPosition='CenterParent'
   $code=New-Object Windows.Forms.TextBox;$code.Multiline=$true;$code.ReadOnly=$true;$code.ScrollBars='Both';$code.WordWrap=$false;$code.Dock='Fill';$code.Font=New-Object Drawing.Font('Consolas',10)
   $code.Text="Код виконується з правами вашого користувача Windows. Перевірте його перед дозволом.`r`n"+($receiptObject.script_review|ConvertTo-Json -Depth 8)+"`r`n`r`n----- CODE -----`r`n"+$receiptObject.script_review.code
   $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Bottom';$buttons.Height=45
   $yes=New-Object Windows.Forms.Button;$yes.Text='Дозволити код';$yes.Width=150;$yes.DialogResult='Yes'
   $no=New-Object Windows.Forms.Button;$no.Text='Відхилити';$no.DialogResult='No';$buttons.Controls.AddRange(@($yes,$no));$reviewForm.Controls.AddRange(@($code,$buttons));$reviewForm.CancelButton=$no
   try{$decision=($reviewForm.ShowDialog($form) -eq 'Yes')}finally{$reviewForm.Dispose()}
  }else{$decision=([Windows.Forms.MessageBox]::Show($text+"`r`nДозволити саме це завдання?",'Підтвердження','YesNo','Warning') -eq 'Yes')}
  if($decision){
   $hash|Set-Content -LiteralPath (Join-Path $PSScriptRoot ('approvals\'+$a.job_id+'.sha256')) -Encoding ASCII;AppLog ('approved '+$a.job_id)
  }else{StopJob}
 }catch{ShowError $_.Exception.Message}
})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=1000
$timer.Add_Tick({
 try{
  $exitRequest=Join-Path $PSScriptRoot 'EXIT'
  if(Test-Path -LiteralPath $exitRequest){Remove-Item -LiteralPath $exitRequest -Force;$form.Close();return}
  if($script:maintenanceJob){
   try{
    $answer=ReceiveMcpMaintenance $script:maintenanceJob
    if($answer){
     $sessionLabel.Text='MCP-сесії: '+$answer.current+' / '+$answer.limit+"`r`nСтворено після останнього скидання: "+$answer.created_since_reset+"`r`nКоманд виконується: "+$answer.active_calls+"`r`nОновлено: "+[DateTime]::Now.ToString('dd.MM.yyyy HH:mm:ss')
     AppLog ('mcp_'+$script:maintenanceJob.operation+'_succeeded current='+$answer.current+' total='+$answer.created_since_reset)
     $script:maintenanceJob.process.Dispose();$script:maintenanceJob=$null
    }
   }catch{$sessionLabel.Text=$_.Exception.Message;AppLog 'mcp_maintenance_failed';$script:maintenanceJob.process.Dispose();$script:maintenanceJob=$null}
   if(-not $script:maintenanceJob){$refreshSessions.Enabled=$true;$resetSessions.Enabled=$true}
  }
  $running=$script:process -and -not $script:process.HasExited
  if(([DateTime]::UtcNow-$script:lastOutputScan).TotalSeconds -ge 5){
   $script:lastOutputScan=[DateTime]::UtcNow
   $folders=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'output') -Directory|Sort-Object LastWriteTime -Descending|Select-Object -First 100)
   foreach($folder in $folders){
    foreach($file in @(Get-ChildItem -LiteralPath $folder.FullName -File|Where-Object {$_.Extension -in @('.png','.jpg','.jpeg')})){
     $name=$folder.Name+'/'+$file.Name
     if(-not $script:imageFiles.ContainsKey($name)){$script:imageFiles[$name]=$file.FullName;$null=$imageChoice.Items.Add($name)}
    }
   }
   if($imageChoice.SelectedIndex -lt 0 -and $imageChoice.Items.Count -gt 0){$imageChoice.SelectedIndex=0}
   $latest=@($folders|ForEach-Object {$r=Join-Path $_.FullName 'result.json';if(Test-Path -LiteralPath $r){Get-Item -LiteralPath $r}}|Sort-Object LastWriteTime -Descending|Select-Object -First 1)
   if($latest.Count){$details.Text=Get-Content -LiteralPath $latest[0].FullName -Raw -Encoding UTF8}
  }
  $connect.Enabled=-not $running;$disconnect.Enabled=[bool]$running;$add.Enabled=-not $running;$save.Enabled=-not $running;$projects.Enabled=-not $running
  $remoteOpen.Enabled=-not $running
  $hasActive=Test-Path -LiteralPath (Join-Path $PSScriptRoot 'active.json')
  $approve.Enabled=$hasActive;$stop.Enabled=$hasActive
  $approve.Text=if($hasActive){'Переглянути завдання'}else{'Немає активного завдання'}
  $countdownLabel.Text=''
  $progress.Visible=$hasActive
  if($hasActive){
   try{$active=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'active.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($active.PSObject.Properties.Name -contains 'remaining_seconds' -and $null -ne $active.remaining_seconds){$countdownLabel.Text='Автосхвалення: '+$active.remaining_seconds+' с'}
    elseif($active.PSObject.Properties.Name -contains 'phase'){$countdownLabel.Text=$active.phase}
    if($active.PSObject.Properties.Name -contains 'progress'){$progress.Style='Blocks';$progress.Value=[Math]::Max(0,[Math]::Min(100,[int]$active.progress))}else{$progress.Style='Marquee'}
    $done=Join-Path $PSScriptRoot ('approvals\'+$active.job_id+'.sha256')
    if(Test-Path -LiteralPath $done){$approve.Enabled=$false;$approve.Text='Завдання виконується'}
   }catch{}
  }
  if($running){$status.Text='Агент запущений; зʼєднання перевіряється за heartbeat. Відключити — завершити роботу.'}elseif($script:process){$status.Text='Відключено (код '+$script:process.ExitCode+'). '+$script:stderr.Result}
  $connection=Join-Path $PSScriptRoot 'connection.json'
  if($running -and (Test-Path -LiteralPath $connection)){
   $last=Get-Content -LiteralPath $connection -Raw -Encoding UTF8|ConvertFrom-Json
   if(([DateTime]::UtcNow-[DateTime]::Parse($last.heartbeat).ToUniversalTime()).TotalSeconds -lt 30){$status.Text='Підключено до Oracle VM. Останній звʼязок: '+[DateTime]::Parse($last.heartbeat).ToLocalTime().ToString('dd.MM.yyyy HH:mm:ss')}
  }
  $lines=@();foreach($f in @('journal.jsonl','ui-journal.jsonl')){ $p=Join-Path $PSScriptRoot ('logs\'+$f);if(Test-Path -LiteralPath $p){$lines+=@(Get-Content -LiteralPath $p -Tail 100 -Encoding UTF8)}}
  $events=@($lines|ForEach-Object {try{$_|ConvertFrom-Json}catch{}}|Sort-Object at)
  $names=@{application_opened='Програму відкрито';application_closed='Програму закрито';connect_requested='Підключення';disconnect_requested='Відключення';project_access_changed='Змінено доступ до проєктів';leased='Завдання отримано';succeeded='Успішно';failed='Помилка';cancelled='Скасовано';approved='Дозволено';cancel_requested='Запит на зупинку'}
  $display=@($events|ForEach-Object {
   $event=[string]$_.event;$key=($event -split ' ')[0];$name=if($names.ContainsKey($key)){$names[$key]}else{$event}
   $action=if($_.PSObject.Properties.Name -contains 'action'){[string]$_.action}else{''}
   $id=if($_.PSObject.Properties.Name -contains 'job_id'){[string]$_.job_id}else{''}
   ([DateTime]::Parse($_.at).ToLocalTime().ToString('dd.MM HH:mm:ss'))+' | '+$name+' | '+$action+' '+$id
  })
  $text=$display -join "`r`n"
  if($log.Text -ne $text){$log.Text=$text;$log.SelectionStart=$log.TextLength;$log.ScrollToCaret()}
 }catch{$status.Text=$_.Exception.Message}
})
$form.Add_Shown({
 if(-not $script:closing){
  $script:closing=$true
  # Hidden console startup can hide the first native window. Re-show the form explicitly.
  $form.Hide();$form.Show();$form.WindowState='Normal';$form.Activate()
  $timer.Start();AppLog 'application_opened';ConnectBridge
 }
})
$form.Add_FormClosing({param($sender,$e)
 if($script:process -and -not $script:process.HasExited){
  DisconnectBridge
  if(-not $script:process.WaitForExit(20000)){$e.Cancel=$true;ShowError 'Агент ще завершує завдання. Зачекайте й закрийте вікно повторно.';return}
 }
 if($script:maintenanceJob){if(-not $script:maintenanceJob.process.HasExited){$script:maintenanceJob.process.Kill()};$script:maintenanceJob.process.Dispose();$script:maintenanceJob=$null}
 $timer.Stop();$tray.Visible=$false;AppLog 'application_closed'
})
try{[Windows.Forms.Application]::Run($form)}finally{if($picture.Image){$picture.Image.Dispose()};$timer.Dispose();$tray.Dispose();$form.Dispose();if($script:process){$script:process.Dispose()};$appMutex.ReleaseMutex();$appMutex.Dispose()}
