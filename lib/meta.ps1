# meta.ps1: read block metadata by parsing the `meta` file LINE BY LINE. The pwsh
# mirror of meta.sh. Dot-sourced itself.
#
# NEVER dot-source a `meta` file: it may hold a single-quoted command cell with a
# $(...)/backtick that must stay inert. This is a PARSER, not an evaluator - it
# matches KEY=VALUE, strips one layer of matching outer quotes, and returns the
# inner literal. Nothing in a value is ever executed here. 5.1-safe.

function Get-BlockDir {
  param([string]$Root, [string]$Id)
  $b = Join-Path (Join-Path $Root 'blocks') $Id
  if (Test-Path -LiteralPath (Join-Path $b 'meta')) { return $b }
  $p = Join-Path (Join-Path $Root 'presets') $Id
  if (Test-Path -LiteralPath (Join-Path $p 'meta')) { return $p }
  return $null
}

# Get-Meta <dir> <field> - the field's inner literal, or '' when absent (mirrors
# meta_get's pre-declared-empty behaviour). One layer of matching outer single OR
# double quotes is stripped, the same one layer the shell strips at source time.
# INCLUDE is returned whole; callers whitespace-split it, as in bash.
function Get-Meta {
  param([string]$Dir, [string]$Field)
  $file = Join-Path $Dir 'meta'
  if (-not (Test-Path -LiteralPath $file)) { return '' }
  foreach ($line in (Get-Content -LiteralPath $file)) {
    if ($line -match '^([A-Z_]+)=(.*)$') {
      if ($Matches[1] -eq $Field) {
        $val = $Matches[2]
        if ($val.Length -ge 2) {
          $first = $val[0]
          $last = $val[$val.Length - 1]
          if (($first -eq "'" -and $last -eq "'") -or ($first -eq '"' -and $last -eq '"')) {
            $val = $val.Substring(1, $val.Length - 2)
          }
        }
        return $val
      }
    }
  }
  return ''
}
