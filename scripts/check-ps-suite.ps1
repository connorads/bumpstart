#!/usr/bin/env pwsh
# check-ps-suite.ps1: run the Pester suite and fail on a failure OR on any skip.
#
# Zero is the right number of skips here, and it is a claim about this suite rather
# than a general rule. It depends on nothing external - bootstrap.ps1 pins Pester and
# PSScriptAnalyzer, and the one effect the spine has reaches the outside world through
# a single seam the tests fake (Get-BumpUserEnvKey, tests/helpers/FakeEnvKey.ps1). So
# a skip can only mean one thing: a case gated on the host it happened to land on -
# which is exactly the shape that let `check` sit green on macOS while `check-windows`
# was red on the same file. Caught at the commit now, not by the Windows job.
#
# No flag and no allow-list, deliberately. A skip that genuinely belongs is a
# conversation worth having, and the way to have it is to delete this gate with the
# reason in that commit - not to grow an exceptions list nobody re-reads.
#
# Written in pwsh rather than shell for the same reason as its sibling
# lint-automatic-os-vars.ps1: it runs identically on macOS and on windows-latest.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# -CI keeps what the task did before: NUnit testResults.xml (gitignored) and a
# non-zero exit on failures. -PassThru is what lets the skip count be read as well.
$result = Invoke-Pester -Path (Join-Path $root 'tests') -CI -PassThru

if ($result.FailedCount -gt 0) { exit 1 }

if ($result.SkippedCount -gt 0) {
  Write-Host ("{0} test(s) were skipped, and this suite has nothing legitimate to skip:" -f $result.SkippedCount)
  foreach ($t in $result.Tests | Where-Object { $_.Skipped }) {
    Write-Host ("  {0}" -f $t.ExpandedPath)
  }
  Write-Host 'A host difference belongs behind a seam the test fakes, not behind -Skip:.'
  exit 1
}

exit 0
