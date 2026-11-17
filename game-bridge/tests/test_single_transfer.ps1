Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'windows/hash.ps1')
. (Join-Path $root 'windows/results.ps1')
. (Join-Path $root 'windows/transfer.ps1')
function SafePath($r,$p){ResolveResultPath $r $p}
function IsCancelled{return $false}
function Request($p,$d){return @{state='running';complete=$true}}
$utf8=New-Object Text.UTF8Encoding($false)
$temp=Join-Path $env:TEMP ('bridge-single-file-'+[Guid]::NewGuid().ToString('N'))
$source=Join-Path $temp 'source';$out=Join-Path $temp 'output'
New-Item -ItemType Directory -Path $source,$out -Force|Out-Null
try{
 [IO.File]::WriteAllText((Join-Path $source 'fixture.gd'),'extends SceneTree')
 $cfg=[pscustomobject]@{project_id=('a'*32);source=$source;device_id='test'}
 $job=[pscustomobject]@{job_id='test';arguments=[pscustomobject]@{project_id=$cfg.project_id;scope='source';files=@('fixture.gd')}}
 $lease='fixture'
 $result=PushProjectFiles
 if($result.file_count -ne 1 -or $result.package_sha256 -notmatch '^[a-f0-9]{64}$'){throw 'Single file transfer failed'}
 Write-Host 'PASS single-file transfer packaging under StrictMode; no network request made'
}finally{if($temp -notlike (Join-Path $env:TEMP 'bridge-single-file-*')){throw 'Cleanup denied'};Remove-Item -LiteralPath $temp -Force -Recurse}
