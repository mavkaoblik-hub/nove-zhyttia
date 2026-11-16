if(-not ('MaVkaOutputReader' -as [type])){
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
public static class MaVkaOutputReader {
 public static async Task<string> DrainAsync(StreamReader reader, int limit) {
  var text = new StringBuilder();
  var buffer = new char[4096];
  int read;
  while ((read = await reader.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false)) > 0) {
   int keep = Math.Min(read, Math.Max(0, limit - text.Length));
   if (keep > 0) text.Append(buffer, 0, keep);
  }
  return text.ToString();
 }
}
'@
}
function TestGodotError([string]$Text){return ($Text -match '(?m)(SCRIPT ERROR:|ERROR:|Parse Error:)')}
