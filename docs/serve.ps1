# Aurum Gold web app - tiny local web server (no install needed). Started by start-webapp.bat.
$port = 8080
$root = [IO.Path]::GetFullPath((Split-Path -Parent $MyInvocation.MyCommand.Path)).TrimEnd('\') + '\'
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
try { $listener.Start() } catch {
  Write-Host "Port $port is already in use. Maybe the app is already running: open http://localhost:$port/"
  Start-Process "http://localhost:$port/"
  Read-Host "Press Enter to close"
  exit
}
Write-Host ""
Write-Host "  AURUM GOLD web app is running at  http://localhost:$port/"
Write-Host "  Keep this window open. Close it to stop the app."
Write-Host ""
Start-Process "http://localhost:$port/"
$types = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8';
            '.png' = 'image/png'; '.svg' = 'image/svg+xml'; '.json' = 'application/json'; '.ico' = 'image/x-icon'; '.webmanifest' = 'application/manifest+json' }
while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $res = $ctx.Response
  try {
    $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if ($path -eq '') { $path = 'index.html' }
    $file = [IO.Path]::GetFullPath((Join-Path $root $path))
    if ($file.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
      $bytes = [IO.File]::ReadAllBytes($file)
      $ext = [IO.Path]::GetExtension($file).ToLower()
      $res.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
      $res.Headers.Add('Cache-Control', 'no-store')
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else { $res.StatusCode = 404 }
  } catch { $res.StatusCode = 500 }
  $res.Close()
}
