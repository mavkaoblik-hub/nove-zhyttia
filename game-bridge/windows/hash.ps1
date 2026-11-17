function Get-BridgeFileHash {
 param([Parameter(Mandatory=$true)][string]$LiteralPath,[string]$Algorithm='SHA256')
 if($Algorithm -ne 'SHA256'){throw 'Only SHA256 is supported'}
 $stream=[IO.File]::OpenRead($LiteralPath);$sha=[Security.Cryptography.SHA256]::Create()
 try{return [pscustomobject]@{Hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}}
 finally{$sha.Dispose();$stream.Dispose()}
}
