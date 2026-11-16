$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'windows\hash.ps1')
. (Join-Path $root 'windows\transfer.ps1')
$utf8=New-Object Text.UTF8Encoding($false)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'windows\agent.ps1'),[ref]$tokens,[ref]$errors)
$node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'SafePath'},$true)
. ([ScriptBlock]::Create($node.Extent.Text))
$parent=Join-Path $root 'work';New-Item -ItemType Directory -Force -Path $parent|Out-Null
$temp=Join-Path $parent ('package-tests-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
$count=0
function MakeZip([string]$Name,[string]$Relative,[string]$Hash,[bool]$Link=$false) {
 $zip=Join-Path $temp ($Name+'.zip');$z=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
 try{
  $m=@{version=1;project_id=('a'*32);files=@(@{path=$Relative;size=3;sha256=$Hash})}|ConvertTo-Json -Depth 6 -Compress
  foreach($pair in @(@('manifest.json',$m),@(('files/'+$Relative),'abc'))){
   $e=$z.CreateEntry($pair[0]);if($Link -and $pair[0] -ne 'manifest.json'){$e.ExternalAttributes=-1577123840}
   $stream=$e.Open();try{$b=$utf8.GetBytes($pair[1]);$stream.Write($b,0,$b.Length)}finally{$stream.Dispose()}
  }
 }finally{$z.Dispose()}
 return $zip
}
try{
 $hash='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
 $valid=MakeZip 'valid' 'nested/test.tscn' $hash
 $dest=Join-Path $temp 'valid-out';New-Item -ItemType Directory -Path $dest|Out-Null
 if((ExpandVerifiedPackage $valid $dest ('a'*32)) -ne 1){throw 'Valid package rejected'};$count++
 if((Get-BridgeFileHash -LiteralPath (Join-Path $dest 'nested\test.tscn')).Hash -ne $hash){throw 'Roundtrip mismatch'};$count++
 $n=0
 foreach($bad in @('../escape.txt','C:/escape.txt','file.txt:ads','CON.txt','tail./a.txt','a.exe')){
  $n++;$z=MakeZip ('bad'+$n) $bad $hash;$d=Join-Path $temp ('bad-out'+$n);New-Item -ItemType Directory -Path $d|Out-Null
  $denied=$false;try{$null=ExpandVerifiedPackage $z $d ('a'*32)}catch{$denied=$true}
  if(-not $denied){throw ('Unsafe package accepted '+$bad)};$count++
 }
 foreach($case in @('hash','project','link')){
  $h=if($case -eq 'hash'){'0'*64}else{$hash};$z=MakeZip $case 'a.txt' $h ($case -eq 'link')
  $d=Join-Path $temp ($case+'-out');New-Item -ItemType Directory -Path $d|Out-Null
  $p=if($case -eq 'project'){'b'*32}else{'a'*32};$denied=$false
  try{$null=ExpandVerifiedPackage $z $d $p}catch{$denied=$true}
  if(-not $denied){throw ('Integrity test accepted '+$case)};$count++
 }
 Write-Host ('PASS '+$count+' package extraction/integrity tests')
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath($parent).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Test cleanup path denied'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
