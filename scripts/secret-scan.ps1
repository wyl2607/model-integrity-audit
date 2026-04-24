$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ShellScript = Join-Path $ScriptDir "secret-scan.sh"

function Test-Command($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command "bash")) {
    Write-Error "Missing required command: bash. Install Git for Windows, then reopen Windows Terminal."
    exit 1
}

$EscapedScript = $ShellScript.Replace("'", "'\''")
$BashScript = & bash -lc "wslpath -u '$EscapedScript' 2>/dev/null || cygpath -u '$EscapedScript' 2>/dev/null || printf '%s' '$EscapedScript'"
& bash $BashScript @args
exit $LASTEXITCODE
