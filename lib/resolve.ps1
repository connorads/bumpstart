# resolve.ps1: PURE CORE, the pwsh mirror of resolve.sh. Given a repo root + an id
# list, return a Plan object or a domain error - no network, no installs, no
# filesystem writes. Depends on meta.ps1 (Get-BlockDir, Get-Meta) + os.ps1
# (Get-VibeOsKey). Dot-sourced. 5.1-safe.
#
# The OS-neutral outputs (StepIds/StepKinds/DefaultHarness/Error) are locked to
# resolve.sh by the shared TSV contract. Targets are OS-specific (MAC reads
# TARGET, WIN reads TARGET_WIN) and so are asserted per-spine, not in the contract.

# Kind ordering: lower runs first; launch happens after all steps.
function Get-KindRank {
  param([string]$Kind)
  switch ($Kind) {
    'harness'      { 10 }
    'app'          { 15 }
    'auth'         { 20 }
    'tool'         { 30 }
    'mcp'          { 40 }
    'skill'        { 50 }
    'instructions' { 60 }
    'preset'       { 99 }
    default        { 90 }
  }
}

# _Expand: append the fully-expanded ids (INCLUDEs first, self last) to the
# [ref]$Expanded list. Deps land before dependents. Sets [ref]$Err + returns
# $false on unknown id or cycle. $Stack accumulates "$Stack $Id" exactly as bash,
# so the cycle error string is byte-identical.
function _Expand {
  param([string]$Root, [string]$Id, [string]$Stack, [ref]$Expanded, [ref]$Err)
  if ((" $Stack ").Contains(" $Id ")) {
    $Err.Value = "include cycle:$Stack -> $Id"
    return $false
  }
  $dir = Get-BlockDir $Root $Id
  if (-not $dir) {
    $Err.Value = "unknown block: $Id"
    return $false
  }
  $includes = (Get-Meta $dir 'INCLUDE') -split '\s+' | Where-Object { $_ -ne '' }
  foreach ($inc in $includes) {
    if (-not (_Expand $Root $inc "$Stack $Id" $Expanded $Err)) { return $false }
  }
  [void]$Expanded.Value.Add($Id)
  return $true
}

# Resolve-Plan <root> <ids...> - a [pscustomobject] Plan (StepIds, StepKinds,
# StepDescs, DefaultHarness, Targets, Error). On failure every list is empty and
# Error carries the identical domain-error string bash produces.
function Resolve-Plan {
  param([string]$Root, [string[]]$Ids)

  $fail = {
    param($msg)
    [pscustomobject]@{
      StepIds        = @()
      StepKinds      = @()
      StepDescs      = @()
      DefaultHarness = ''
      Targets        = @()
      Error          = $msg
    }
  }

  if (-not $Ids -or $Ids.Count -eq 0) { return (& $fail 'no blocks requested') }

  $expanded = New-Object System.Collections.Generic.List[string]
  $err = [ref]''
  foreach ($id in $Ids) {
    if (-not (_Expand $Root $id '' ([ref]$expanded) $err)) { return (& $fail $err.Value) }
  }

  # default-harness = the AGENT declared by the last id in the expanded
  # (input-order) list that declares one - computed before kind-reordering, so it
  # is genuinely last-in-list-wins. The value is the agent's own name, never the
  # block id: the binary/trust/launch all want <agent>.
  $harness = ''
  foreach ($id in $expanded) {
    $dir = Get-BlockDir $Root $id
    $agent = Get-Meta $dir 'AGENT'
    if ($agent) { $harness = $agent }
  }
  if (-not $harness) {
    return (& $fail "no harness in plan (add e.g. 'claude' or 'codex')")
  }

  # Dedupe (first occurrence), drop presets, decorate with (rank, index) so a
  # sort by rank then index orders by kind then input.
  $seen = New-Object System.Collections.Generic.HashSet[string]
  $rows = New-Object System.Collections.Generic.List[object]
  $i = 0
  foreach ($id in $expanded) {
    if (-not $seen.Add($id)) { continue }
    $dir = Get-BlockDir $Root $id
    $kind = Get-Meta $dir 'KIND'
    if ($kind -eq 'preset') { continue }
    $rows.Add([pscustomobject]@{
      Rank  = Get-KindRank $kind
      Index = $i
      Id    = $id
      Kind  = $kind
      Desc  = Get-Meta $dir 'DESC'
    })
    $i++
  }

  $sorted = $rows | Sort-Object Rank, Index
  $stepIds   = @($sorted | ForEach-Object { $_.Id })
  $stepKinds = @($sorted | ForEach-Object { $_.Kind })
  $stepDescs = @($sorted | ForEach-Object { $_.Desc })

  # Instruction targets = the OS-native TARGET of each harness present, deduped in
  # order - only meaningful when some step ships content (content.md or a per-OS
  # content.<os>.md), since that is what the canonical file is assembled from.
  $osTok = (Get-VibeOs)
  $targetField = @{ MAC = 'TARGET'; WIN = 'TARGET_WIN'; LINUX = 'TARGET_LINUX' }[(Get-VibeOsKey)]
  $targets = @()
  $writes = $false
  foreach ($id in $stepIds) {
    $dir = Get-BlockDir $Root $id
    if ((Test-Path -LiteralPath (Join-Path $dir 'content.md')) -or
        (Test-Path -LiteralPath (Join-Path $dir "content.$osTok.md"))) {
      $writes = $true
      break
    }
  }
  if ($writes) {
    $seenT = New-Object System.Collections.Generic.HashSet[string]
    for ($j = 0; $j -lt $stepIds.Count; $j++) {
      if ($stepKinds[$j] -eq 'harness') {
        $dir = Get-BlockDir $Root $stepIds[$j]
        $t = Get-Meta $dir $targetField
        if ($t -and $seenT.Add($t)) { $targets += $t }
      }
    }
  }

  [pscustomobject]@{
    StepIds        = $stepIds
    StepKinds      = $stepKinds
    StepDescs      = $stepDescs
    DefaultHarness = $harness
    Targets        = $targets
    Error          = ''
  }
}
