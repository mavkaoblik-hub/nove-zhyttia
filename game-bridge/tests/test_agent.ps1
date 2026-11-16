$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$count=0
. (Join-Path $root 'windows\hash.ps1')
$hashTemp=Join-Path $PSScriptRoot ('hash-'+[Guid]::NewGuid().ToString('N')+'.txt')
try{
 [IO.File]::WriteAllBytes($hashTemp,[Text.Encoding]::ASCII.GetBytes('abc'))
 if((Get-BridgeFileHash -LiteralPath $hashTemp).Hash -ne 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'){throw 'SHA256 known-answer test failed'};$count++
}finally{Remove-Item -LiteralPath $hashTemp -Force}
Get-ChildItem -LiteralPath (Join-Path $root 'windows') -Filter '*.ps1'|ForEach-Object {
 $tokens=$null;$errors=$null
 [Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)|Out-Null
 if($errors){throw ($errors|Out-String)};$count++
}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'windows\agent.ps1'),[ref]$tokens,[ref]$errors)
# Only the locally authored path validator is loaded; agent/network loop is never started.
$node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'SafePath'},$true)
. ([ScriptBlock]::Create($node.Extent.Text))
$accessNode=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'TestProjectAccess'},$true)
. ([ScriptBlock]::Create($accessNode.Extent.Text))
$config=@{source='C:\Game';project_id=('a'*32);projects=@(@{id=('a'*32);path='C:\Game';enabled=$false})}
if(TestProjectAccess $config){throw 'Disabled project accepted'};$count++
$config.projects[0].enabled=$true
if(-not(TestProjectAccess $config)){throw 'Allowed project denied'};$count++
$config.source='C:\Other'
if(TestProjectAccess $config){throw 'Unlisted source accepted'};$count++
$config.source='C:\Game';$config.project_id='other'
if(TestProjectAccess $config){throw 'Unlisted project ID accepted'};$count++
$testParent=Join-Path (Split-Path -Parent (Split-Path -Parent $root)) 'work'
$temp=Join-Path $testParent ('bridge-tests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try {
 $good=SafePath $temp 'nested\a.png'
 if(-not $good.StartsWith($temp+'\')){throw 'Valid path failed'};$count++
 foreach($bad in @('..\escape','C:\Windows\win.ini','a.txt:stream','..\sibling\x')){
  $denied=$false;try{$null=SafePath $temp $bad}catch{$denied=$true}
  if(-not $denied){throw ('Traversal accepted: '+$bad)};$count++
 }
 try{New-Item -ItemType Junction -Path (Join-Path $temp 'junction') -Target $testParent|Out-Null}catch{Write-Warning 'SKIP junction creation: environment denied it';Write-Host ('PASS '+$count+' checks; junction NOT TESTED');return}
 $denied=$false;try{$null=SafePath $temp 'junction\escape.txt'}catch{$denied=$true}
 if(-not $denied){throw 'Junction accepted'};$count++
 Remove-Item -LiteralPath (Join-Path $temp 'junction') -Force
}finally{
 # Only remove the empty known test directory; never recursively traverse a junction.
 if(Test-Path -LiteralPath (Join-Path $temp 'junction')){Remove-Item -LiteralPath (Join-Path $temp 'junction') -Force}
 Remove-Item -LiteralPath $temp -Force
}
Write-Host ('PASS '+$count+' parser/path checks; PowerShell '+$PSVersionTable.PSVersion)
