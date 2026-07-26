# Shared resolver contract — the pwsh side. Reads the SAME TSV as contract.bats
# via Import-Csv and drives resolve.ps1, asserting identical ids/kinds/harness/
# error. Both spines green off one file ⇒ the two resolvers cannot diverge on the
# OS-neutral core.

# Discovery-time: -ForEach expands its data when Pester discovers tests, before
# any BeforeAll runs — so the cases must be read here at script scope, not inside
# BeforeAll (which runs later).
$ContractCases = Import-Csv -LiteralPath "$PSScriptRoot/fixtures/contract/resolve-cases.tsv" -Delimiter "`t"

BeforeAll {
  . "$PSScriptRoot/../lib/os.ps1"
  . "$PSScriptRoot/../lib/meta.ps1"
  . "$PSScriptRoot/../lib/resolve.ps1"
  $script:fix = "$PSScriptRoot/fixtures"
}

Describe 'shared resolve contract' {
  It 'resolves [<input>] identically to the bash spine' -ForEach $ContractCases {
    $ids = if ($_.input) { @($_.input -split '\s+') } else { @() }
    $plan = Resolve-Plan $script:fix $ids

    if ($_.expect_error) {
      $plan.Error | Should -Be $_.expect_error
    } else {
      $plan.Error | Should -Be ''
      ($plan.StepIds -join ' ')   | Should -Be $_.expect_ids
      ($plan.StepKinds -join ' ') | Should -Be $_.expect_kinds
      $plan.DefaultHarness        | Should -Be $_.expect_harness
    }
  }
}
