# Canary preflight - run this INSIDE the prepared VM (or as the canary Windows
# user) before any live Codex call.
#
# The script is READ-ONLY. It creates nothing and deletes nothing, including the
# bench repository: if a bench already exists it is only inspected, otherwise
# that check is skipped.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File canary-preflight.ps1
#
# Paste the whole output back for review. Nothing secret is printed: file
# contents, clipboard contents and credentials are never shown - only whether a
# path is reachable and whether a known marker is visible.
#
# Clipboard check: on the HOST, copy exactly this marker before running:
#   CLC_HOST_CLIPBOARD_PROBE_20261026

$ErrorActionPreference = 'SilentlyContinue'
$pass = 0; $fail = 0; $warn = 0
function Ok($t)   { $script:pass++; Write-Output "  PASS  $t" }
function Bad($t)  { $script:fail++; Write-Output "  FAIL  $t" }
function Warn($t) { $script:warn++; Write-Output "  WARN  $t" }

Write-Output "=== Canary preflight ==="
Write-Output ("host            : {0}" -f $env:COMPUTERNAME)
Write-Output ("user            : {0}" -f $env:USERNAME)
Write-Output ("os              : {0}" -f (Get-CimInstance Win32_OperatingSystem).Caption)
Write-Output ("date            : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'))
Write-Output ""

Write-Output "--- 1. Host filesystem must be out of reach"
if (Test-Path 'C:\Users\kapranov') {
  Bad "C:\Users\kapranov is reachable from here - this is NOT an isolated environment"
} else { Ok "C:\Users\kapranov does not exist here" }

$drives = (Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name) -join ','
Write-Output "        filesystem drives: $drives"
if (Test-Path '\\tsclient\') { Bad "\\tsclient\ is present - drive passthrough is on" }
else { Ok "no \\tsclient\ redirection" }

$net = Get-SmbMapping -ErrorAction SilentlyContinue
if ($net) { Warn ("mapped network drives present: " + (($net | ForEach-Object { $_.LocalPath }) -join ',')) }
else { Ok "no mapped network drives" }

Write-Output ""
Write-Output "--- 2. Shared clipboard"
Write-Output "        on the HOST copy the marker CLC_HOST_CLIPBOARD_PROBE_20261026 first"
$marker = 'CLC_HOST_CLIPBOARD_PROBE_20261026'
$clipAvailable = $true
$clip = $null
try { $clip = (Get-Clipboard -ErrorAction Stop) -join "`n" } catch { $clipAvailable = $false }
# only the verdict is printed; clipboard contents never leave this variable
if (-not $clipAvailable) { Warn "clipboard unavailable" }
elseif ($clip -and $clip.Contains($marker)) { Bad "marker visible - the clipboard is shared with the host" }
else { Ok "marker not visible" }
Remove-Variable clip -ErrorAction SilentlyContinue

Write-Output ""
Write-Output "--- 3. Toolchain"
foreach ($t in @('git', 'python', 'bash')) {
  $v = & $t --version 2>$null | Select-Object -First 1
  if ($LASTEXITCODE -eq 0 -and $v) { Ok "$t : $v" } else { Bad "$t is missing or does not run" }
}
$codexBin = $null
$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($codex) {
  $codexBin = $codex.Source
  $cv = & codex --version 2>$null | Select-Object -First 1
  Ok "codex : $cv"
} else {
  $guess = Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe" -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($guess) {
    $codexBin = $guess.FullName
    Ok ("codex : " + (& $codexBin --version 2>$null | Select-Object -First 1))
  } else { Bad "codex binary not found" }
}

Write-Output ""
Write-Output "--- 4. Codex identity in this environment"
# The credential file is never opened or parsed: existence only.
$auth = "$env:USERPROFILE\.codex\auth.json"
if (Test-Path $auth) {
  Ok "a credential file exists in this profile (not opened, not parsed)"
} else {
  Bad "no credential file here - run codex login inside this environment"
}
# Account ownership cannot be established from here: `codex login status`
# returns nothing when its output is redirected, and parsing credentials is
# out of bounds for this script. It stays a manual statement.
Write-Output "        ACTION (manual): run  codex login status  yourself in this"
Write-Output "        environment and state the verdict in the report - logged in or"
Write-Output "        not, and whether the account is SEPARATE from the host or the"
Write-Output "        SAME one. Do not paste the raw output. The same account means"
Write-Output "        file isolation without credential or account isolation."

Write-Output ""
Write-Output "--- 5. Published version installed and self-checked"
$scripts = "$env:USERPROFILE\.claude\scripts"
if (Test-Path "$scripts\codex-task.sh") {
  $lines = @(Get-Content "$scripts\codex-task.sh").Count
  Ok "codex-task.sh installed ($lines lines)"
  $m1 = Select-String -Path "$scripts\codex-task.sh" -Pattern 'moved past the verified commit' -Quiet
  $m2 = Select-String -Path "$scripts\codex-task.sh" -Pattern 'checked-out branch changed' -Quiet
  if ($m1 -and $m2) { Ok "post-review merge gates present (branch-moved, HEAD-switched)" }
  else { Bad "this is an OLDER copy: the post-review merge gates are missing" }
} else { Bad "the integration is not installed in this profile - run install.sh" }

Write-Output ""
Write-Output "--- 6. Test suites (the numbers that gate the canary)"
$repo = $null
foreach ($c in @("$env:USERPROFILE\claude-love-codex", "$PWD\..\..", "$PWD")) {
  if (Test-Path "$c\tests\run-tests.sh") { $repo = (Resolve-Path $c).Path; break }
}
if (-not $repo) {
  Bad "repository clone with tests/ not found - clone it and re-run"
} else {
  Write-Output "        repo: $repo"
  foreach ($s in @(@('run-tests.sh', '96'), @('run-lifecycle.sh', '25'), @('run-merge-atomic.sh', '47'))) {
    $out = & bash -c "cd '$repo' && env -u PYTHONDONTWRITEBYTECODE bash tests/$($s[0]) 2>&1 | grep RESULT | tail -1"
    if ($out -match "PASS=$($s[1]) FAIL=0") { Ok "$($s[0]) -> $out" } else { Bad "$($s[0]) -> $out" }
  }
}

Write-Output ""
Write-Output "--- 7. Bench repository has no remote"
$bench = "C:\Windows\Temp\clc-canary\loans"
if (Test-Path "$bench\.git") {
  $r = & git -C $bench remote -v
  if ([string]::IsNullOrWhiteSpace($r)) { Ok "bench repository has no remote" }
  else { Bad "bench repository HAS a remote: $r" }
} else { Write-Output "        no bench here yet - nothing created; checked again at canary start" }

Write-Output ""
Write-Output "--- 8. Network (expected: reachable; the model API needs it)"
try { $null = [System.Net.Dns]::GetHostEntry('api.openai.com'); Ok "DNS resolves" } catch { Bad "DNS does not resolve" }
$tcp = $false
try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('api.openai.com', 443); $tcp = $true; $c.Close() } catch {}
if ($tcp) { Ok "outbound 443 works" } else { Bad "no outbound 443 - Codex will not run" }
Write-Output "        NOTE: network access is intentional. This environment bounds"
Write-Output "        file access, not exfiltration."

Write-Output ""
Write-Output "=== RESULT: PASS=$pass FAIL=$fail WARN=$warn ==="
if ($fail -gt 0) { Write-Output "Do not start the canary: fix the failures above first." }
else { Write-Output "Preflight clean. Paste this output back before starting the canary." }
