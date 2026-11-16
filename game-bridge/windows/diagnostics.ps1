param([string]$OutputPath=(Join-Path $PSScriptRoot 'diagnostics.json'))
$ErrorActionPreference='Stop'
$paths=@{blender='C:\Program Files\Blender Foundation\Blender 5.3\blender.exe';godot='C:\РУДИЧИК\Godot\Godot_v4.7.2-stable_win64.exe';godot_console='C:\РУДИЧИК\Godot\Godot_v4.7.2-stable_win64_console.exe';project='C:\РУДИЧИК\Godot\NoveZhyttia\project.godot'}
$r=@{powershell=$PSVersionTable.PSVersion.ToString();paths=@{};free_c_bytes=(Get-PSDrive C).Free;gpu=@(Get-CimInstance Win32_VideoController|Select-Object Name,DriverVersion);commands=@{}}
foreach($k in $paths.Keys){$r.paths[$k]=@{exists=(Test-Path -LiteralPath $paths[$k]);version=$null}}
foreach($k in @('blender','godot_console')){if($r.paths[$k].exists){$r.paths[$k].version=(& $paths[$k] --version 2>&1|Select-Object -First 5)-join "`n";$r.paths[$k].exit_code=$LASTEXITCODE}}
foreach($c in @('git.exe','python.exe','ssh.exe')){$v=Get-Command $c -ErrorAction SilentlyContinue;$r.commands[$c]=@{found=($null -ne $v);windowsapps_stub=($null -ne $v -and $v.Source -like '*Microsoft\WindowsApps*')}}
$r.gpu_render='NOT TESTED; fixture uses CPU. GPU/VRAM requires separate Blender driver test.'
$r|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host ('Read-only diagnostics saved: '+$OutputPath)
