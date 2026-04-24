$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ShellScript = Join-Path $ScriptDir "compare-app-vs-cli-gpt55.sh"

function Test-Command($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-BashCommand($Name) {
    & bash -lc "command -v $Name >/dev/null 2>&1"
    return $LASTEXITCODE -eq 0
}

$missing = @()
if (-not (Test-Command "bash")) {
    $missing += "bash"
}
foreach ($cmd in @("codex", "jq", "rg", "awk", "sed", "perl")) {
    if ((Test-Command "bash") -and -not (Test-BashCommand $cmd)) {
        $missing += $cmd
    }
}

if ($missing.Count -gt 0) {
    Write-Error "Missing required command(s): $($missing -join ', '). Install Git for Windows, jq, ripgrep, and Codex CLI, then reopen Windows Terminal."
    exit 1
}

$EscapedScript = $ShellScript.Replace("'", "'\''")
$BashScript = & bash -lc "wslpath -u '$EscapedScript' 2>/dev/null || cygpath -u '$EscapedScript' 2>/dev/null || printf '%s' '$EscapedScript'"
& bash $BashScript @args
exit $LASTEXITCODE
