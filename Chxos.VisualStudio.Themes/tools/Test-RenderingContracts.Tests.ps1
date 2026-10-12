[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'RenderingContracts.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ContextualContrast.psm1') -Force
$context=Read-RenderingContracts
$baseline=$context.Registry | ConvertTo-Json -Depth 35 -Compress
$count=0
function Assert-Case([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:count++
    Write-Host "PASS: $Name"
}
function Reject-Case([string]$Name,[scriptblock]$Mutate,[string]$Expected) {
    $context.Registry=$baseline | ConvertFrom-Json
    & $Mutate $context.Registry
    $problems=@(Test-RenderingContracts $context)
    Assert-Case (@($problems | Where-Object { $_ -like "*$Expected*" }).Count -gt 0) $Name
}
Assert-Case (@(Test-RenderingContracts $context).Count -eq 0) 'complete offline registry'
Assert-Case ($context.Registry.RuleCoverage.Count -eq 448 -and $context.Registry.PolicyMembers.Count -eq (369 + @($context.Registry.PolicyMembers | Where-Object Id -like 'RC-DEFERRED-*').Count)) '448 historical audit rules and all current policy members reconciled'
Reject-Case 'selection opacity disagreement rejected' { param($r) ($r.Profiles | Where-Object Id -CEQ 'selection-normal').SelectionModel.ElementOpacity=0.16 } 'rendering model disagreement'
Reject-Case 'selection evidence cannot be removed' { param($r) ($r.Profiles | Where-Object Id -CEQ 'selection-normal').SelectionModel.Evidence=@('SEL-CALCULATION') } 'requires the reviewed implementation'
Reject-Case 'selection model scope cannot shrink' { param($r) (($r.Contracts | Where-Object Id -CEQ 'RC-ACTIVE-SELECTION').Requirements | Where-Object Id -CEQ 'normal-selection-model').Themes=@('Foundation') } 'requirement scope disagrees'
Reject-Case 'duplicate contract ID' { param($r) $r.Contracts[1].Id=$r.Contracts[0].Id } 'duplicate contract ID'
Reject-Case 'missing component' { param($r) $r.Contracts[0].Components[0].Key[1]='Missing' } 'Missing or invalid component'
Reject-Case 'invalid authored type' { param($r) $r.Contracts[0].Components[0].AuthoredType='CT_INVALID' } 'Authored type'
Reject-Case 'broken evidence citation' { param($r) $r.Contracts[0].Evidence=@('UNKNOWN-SOURCE') } 'Unknown evidence'
Reject-Case 'RGB cannot compose source alpha' { param($r) ($r.Profiles | Where-Object Id -eq 'editor-rgb').Alpha='brush-alpha' } 'RGB conversion cannot'
Reject-Case 'unsupported named-pair confirmation' { param($r) $r.Contracts[0].RenderingStatus='supported' } 'Unsupported confirmation'
Reject-Case 'profile cannot confirm an unreviewed consumer' { param($r) $c=$r.Contracts[0]; $c.Profile='editor-rgb'; $c.RenderingStatus='supported'; $c.Underlay.Complete=$true } 'outside the evidence profile'
Reject-Case 'incomplete composition chain' { param($r) ($r.Contracts | Where-Object Id -eq 'RC-ACTIVE-SELECTION').Underlay.Layers=@() } 'complete underlay requires'
Reject-Case 'unknown composition order' { param($r) $r.Contracts[0].Underlay.Order='outer-to-inner' } 'composition order'
Reject-Case 'unresolved validity is not a selected branch' { param($r) ($r.Contracts | Where-Object Id -eq 'RC-F04-043').RenderingStatus='supported' } 'Unsupported confirmation'
Reject-Case 'conditional branch cannot disappear' { param($r) ($r.Contracts | Where-Object Id -eq 'RC-F04-043').ConditionalBranches=@() } 'both conditional branches'
Reject-Case 'conditional branch references resolve' { param($r) ($r.Contracts | Where-Object Id -eq 'RC-F04-043').ConditionalBranches[0].Underlay[0][1]='Missing' } 'Missing or invalid component'
Reject-Case 'missing investigation' { param($r) $r.Contracts[0].NextInvestigation='' } 'next investigation'
Reject-Case 'missing unresolved evidence gap' { param($r) $r.Contracts[0].MissingEvidence='' } 'Unresolved consumers require'
Reject-Case 'unknown theme scope' { param($r) $r.Contracts[0].Themes=@('Unknown') } 'theme scope'
Reject-Case 'duplicate theme scope' { param($r) $r.Contracts[0].Themes=@('Foundation','Foundation') } 'theme scope'
Reject-Case 'missing rule reconciliation' { param($r) $r.RuleCoverage=@($r.RuleCoverage | Select-Object -Skip 1) } 'Not every audit rule'
Reject-Case 'duplicate audit mapping' { param($r) $r.RuleCoverage[1].AuditRuleId=$r.RuleCoverage[0].AuditRuleId } 'Duplicate or unknown audit'
Reject-Case 'dangling contract mapping' { param($r) $r.RuleCoverage[0].ContractIds=@('RC-MISSING') } 'Unknown contract reference'
Reject-Case 'missing policy member' { param($r) $r.PolicyMembers=@($r.PolicyMembers | Select-Object -Skip 1) } 'Policy member coverage mismatch'
Reject-Case 'ambiguous policy selector' { param($r) $c=$r.Contracts | Where-Object { $_.PSObject.Properties.Name -contains 'PolicySelector' -and $_.PolicySelector.Family -eq 'OpaqueContent' } | Select-Object -First 1; $c.PolicySelector.Match=[pscustomobject]@{ Anchor='TextFillPrimary' } } 'exactly one member'
Reject-Case 'unknown relationship ID' { param($r) $r.Contracts[0].RelationshipId='F99-999' } 'Unknown relationship selector'
Reject-Case 'confidence cannot exceed retained contextual audit' { param($r) $r.Contracts[0].Assessment='supported' } 'assessment differs'
Reject-Case 'invalid requirement enforcement' { param($r) $r.Contracts[0].Requirements[0].Enforcement='new-color-failure' } 'Malformed validation requirement'
Reject-Case 'image context is not a brush' { param($r) ($r.Profiles | Where-Object Id -eq 'toolbar-image-background').Alpha='brush-alpha' } 'opaque context semantics'
Reject-Case 'implemented requirement scope cannot escape contract' { param($r) $c=$r.Contracts | Where-Object Id -eq 'RC-PRIORITY-REFINEMENTS'; $c.Themes=@('Foundation'); $c.Requirements[0].Themes=@('Amberroot') } 'Invalid requirement theme scope'
Reject-Case 'registry scope cannot omit enforced themes' { param($r) ($r.Contracts | Where-Object Id -eq 'RC-PRIORITY-REFINEMENTS').Requirements[0].Themes=@('Amberroot') } 'scope/registry disagreement'
foreach ($scopeCase in @('missing-map','missing-theme','unknown-theme','invalid-state','missing-anchor','policy-registry-disagreement')) {
    $scopePolicy=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')
    switch ($scopeCase) {
        'missing-map' { $scopePolicy.Remove('RefinementEnforcement') }
        'missing-theme' { $scopePolicy.RefinementEnforcement.Remove('Amberroot') }
        'unknown-theme' { $scopePolicy.RefinementEnforcement.Unknown='pending' }
        'invalid-state' { $scopePolicy.RefinementEnforcement.Amberroot='invalid' }
        'missing-anchor' { $scopePolicy.PriorityRefinementAnchors.Foundation.Remove('ControlSolidFillDefault') }
        'policy-registry-disagreement' { $scopePolicy.RefinementEnforcement.Hardline=$(if ($scopePolicy.RefinementEnforcement.Hardline -ceq 'enforced') { 'pending' } else { 'enforced' }); $scopePolicy.PriorityRefinementAnchors.Hardline=@{ControlSolidFillDefault='FF34393C';EditorActiveSelectionFill='FF20384A'} }
    }
    $scopeContext=Read-RenderingContracts -Policy $scopePolicy
    Assert-Case (@(Test-RenderingContracts $scopeContext).Count -gt 0) "scope integrity: $scopeCase"
}
Reject-Case 'duplicate requirement themes rejected' { param($r) ($r.Contracts | Where-Object Id -eq 'RC-PRIORITY-REFINEMENTS').Requirements[0].Themes=@('Foundation','Foundation') } 'Invalid requirement theme scope'
Reject-Case 'pending and implemented scopes cannot overlap' { param($r) $c=$r.Contracts | Where-Object Id -eq 'RC-ACTIVE-SELECTION'; $q=$c.Requirements[0] | ConvertTo-Json -Depth 15 | ConvertFrom-Json; $q.Enforcement='pending'; $q.Themes=@('Foundation'); $c.Requirements+=@($q) } 'Overlapping requirement enforcement scopes'
Reject-Case 'image eligibility cannot disappear' { param($r) ($r.Contracts | Where-Object Id -eq 'RC-TOOLBAR-IMAGE-CONTEXT').ImageConditions='' } 'explicit image eligibility'
$context.Registry=$baseline | ConvertFrom-Json
$foundation=$context.Registry.Contracts | Where-Object Id -eq 'RC-FOUNDATION-SURFACES'
Assert-Case ($foundation.Themes.Count -eq 1 -and $foundation.Themes[0] -ceq 'Foundation') 'theme-specific policy scope retained'
$inventory=Get-Content (Join-Path $PSScriptRoot 'ComponentInventory.json') -Raw | ConvertFrom-Json
$report=Get-RenderingEvidenceReport $context $inventory
Assert-Case ($report.Components.Count -eq 3959 -and @($report.Components | Where-Object { $_.ContractIds.Count -gt 1 }).Count -gt 0) 'complete inventory and multiple consumers supported'
foreach ($type in @('CT_RAW','CT_INVALID','CT_AUTOMATIC','CT_SYSCOLOR','CT_COLORINDEX')) {
    Assert-Case (@($context.Parts.Values | Where-Object Type -ceq $type).Count -gt 0) "typed values preserved: $type"
}
foreach ($pair in @(@('supported',4),@('mismatch',9),@('unresolved',56))) {
    Assert-Case (@($report.Relationships | Where-Object Assessment -ceq $pair[0]).Count -eq $pair[1]) "contextual assessment count: $($pair[0])"
}
[xml]$theme=Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'Amberroot.vstheme') -Raw
$legacy=@(Test-ContextualRelationships $theme $context.Relationships)
foreach ($id in @('F01-001','F04-043')) {
    Assert-Case (($legacy | Where-Object Id -ceq $id).Status -ceq 'validated' -and ($report.Relationships | Where-Object Id -ceq $id).Assessment -cne 'supported') "source pass is independent of evidence: $id"
}
$before=$legacy | ConvertTo-Json -Depth 10 -Compress
$pending=$context.Registry.Contracts | Where-Object Id -eq 'RC-ACTIVE-SELECTION'
$q=$pending.Requirements[0] | ConvertTo-Json -Depth 15 | ConvertFrom-Json; $q.Id='test-pending'; $q.Enforcement='pending'; $q.Themes=@('Amberroot'); $q.Description='Pending source matrix remains non-enforcing.'; $pending.Requirements+=@($q)
$after=@(Test-ContextualRelationships $theme $context.Relationships) | ConvertTo-Json -Depth 10 -Compress
Assert-Case ($before -ceq $after -and @((Get-RenderingEvidenceReport $context $inventory).PendingRequirements).Count -gt 0 -and $report.RuntimeAcceptance -ceq 'pending') 'pending metadata leaves evaluator output unchanged'
# An invalid registry must be collected without hiding the existing inventory
# diagnostic. Everything mutable lives in an owned, disposable directory.
$fixtureParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureRoot=Join-Path $fixtureParent ('cosmora-rendering-registry-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
try {
    $project=Split-Path -Parent $PSScriptRoot
    Get-ChildItem $project -Filter '*.vstheme' | Where-Object Name -ne 'Amberroot.vstheme' | Copy-Item -Destination $fixtureRoot
    $bad=$baseline | ConvertFrom-Json
    $supplemental=$baseline | ConvertFrom-Json
    $supplemental.EvidenceSources[0].Sha256='0'*64
    $supplementalPath=Join-Path $fixtureRoot 'bad-supplemental.json'
    $supplemental | ConvertTo-Json -Depth 35 | Set-Content $supplementalPath -Encoding UTF8
    $errorText=''
    try { Read-RenderingContracts -RegistryPath $supplementalPath | Out-Null } catch { $errorText=$_.Exception.Message }
    Assert-Case ($errorText -like '*Supplemental evidence hash mismatch*') 'supplemental citation bytes are verified offline'
    $selectionEvidence=$baseline | ConvertFrom-Json
    ($selectionEvidence.EvidenceSources | Where-Object Path -like '*/editor-selection/supplemental-evidence.json').Sha256='0'*64
    $selectionEvidence | ConvertTo-Json -Depth 35 | Set-Content $supplementalPath -Encoding UTF8
    $errorText='';try { Read-RenderingContracts -RegistryPath $supplementalPath | Out-Null } catch { $errorText=$_.Exception.Message }
    Assert-Case ($errorText -like '*Supplemental evidence hash mismatch*') 'selection supplemental bytes verified offline'
    # Recreate the original schema-1 scope without changing its frozen audit snapshot.
    $legacy=$baseline | ConvertFrom-Json
    $legacy.SchemaVersion=1; $legacy.PSObject.Properties.Remove('EvidenceSources')
    $legacy.Contracts=@($legacy.Contracts | Where-Object { $_.Id -ne 'RC-SELECTION-MODEL-POLICY' -and $_.Id -notlike 'RC-PRIORITY*' -and $_.Id -notlike 'RC-SEMANTIC*' -and $_.Id -notlike 'RC-REFINEMENT-SCOPE-*' -and $_.Id -notlike 'RC-DEFERRED-*' -and $_.Id -notin @('RC-TOOLBAR-IMAGE-CONTEXT','RC-SOLID-CONTROL-VISIBLE-FILL') })
    $legacy.Profiles=@($legacy.Profiles | Where-Object Id -ne 'toolbar-image-background')
    $legacy.PolicyMembers=@($legacy.PolicyMembers | Where-Object { $_.Id -ne 'RC-SELECTION-MODEL-POLICY' -and $_.Id -notlike 'RC-PRIORITY*' -and $_.Id -notlike 'RC-SEMANTIC*' -and $_.Id -notlike 'RC-REFINEMENT-SCOPE-*' -and $_.Id -notlike 'RC-DEFERRED-*' })
    foreach ($contract in $legacy.Contracts) { $contract.Evidence=@($contract.Evidence | Where-Object { $_ -notlike 'SEMANTIC-*' }) }
    foreach ($profile in $legacy.Profiles) {
        $profile.Evidence=@($profile.Evidence | Where-Object { $_ -notlike 'SEL-*' })
        $profile.PSObject.Properties.Remove('SelectionModel')
    }
    foreach ($contract in $legacy.Contracts) {
        $contract.Evidence=@($contract.Evidence | Where-Object { $_ -notlike 'SEL-*' })
        $contract.Requirements=@($contract.Requirements | Where-Object { $_.Source -notlike 'EditorSelectionContrast.psm1#*' -and $_.Source -ne 'PriorityThemeRefinements.psm1#selection-current-line-hierarchy' })
    }
    # Restore the historical inactive surface profile instead of attributing the
    # newly observed selection opacity to the old schema-1 snapshot.
    ($legacy.Contracts | Where-Object Id -CEQ 'RC-SURFACE-B1873A82CABA').Profile='editor-rgb'
    ($legacy.Profiles | Where-Object Id -CEQ 'editor-rgb').SupportedContractIds+=@('RC-SURFACE-B1873A82CABA')
    ($legacy.Profiles | Where-Object Id -CEQ 'selection-normal').SupportedContractIds=@('RC-ACTIVE-SELECTION')
    $selection=$legacy.Contracts | Where-Object Id -eq 'RC-ACTIVE-SELECTION'
    $selection.Requirements=@($selection.Requirements | Select-Object -First 1); $selection.Requirements[0].Enforcement='pending'; $selection.Requirements[0].Evidence=@('DA-F02','W3C-TEXT'); $selection.Requirements[0].Basis='project policy'; $selection.Requirements[0].Description='Historical active syntax matrix requires investigation.'
    $selection.Requirements[0].PSObject.Properties.Remove('Themes');$selection.Requirements[0].PSObject.Properties.Remove('Id')
    $legacyPath=Join-Path $fixtureRoot 'legacy-v1.json'
    $legacy | ConvertTo-Json -Depth 35 | Set-Content $legacyPath -Encoding UTF8
    $legacyPolicy=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')
    foreach ($priorityName in @($legacyPolicy.ActiveSelectionAnchors.Keys | Where-Object { $_ -cne 'Nullsector' })) { $legacyPolicy.ActiveSelectionAnchors.Remove($priorityName) }
    foreach ($family in @('PriorityRefinementAnchors','PrioritySelectionMinimum','PrioritySelectionDistanceMinimum','RefinementEnforcement','EditorSelectionModel')) { $legacyPolicy.Remove($family) }
    foreach ($family in @('Struct','Interface','Control','Directive')) { $legacyPolicy.CoreSyntaxFamilyRoles.Remove($family) }
    $legacyContext=Read-RenderingContracts -RegistryPath $legacyPath -Policy $legacyPolicy
    $legacyErrors=@(Test-RenderingContracts $legacyContext)
    if ($legacyErrors.Count) { Write-Host ($legacyErrors -join "`n") }
    Assert-Case ($legacyErrors.Count -eq 0 -and $legacyContext.Registry.PolicyMembers.Count -eq 337) 'schema 1 remains readable and valid in its historical policy scope'
    $bad.AuditSnapshot.Files[0].Sha256='0'*64
    $registryPath=Join-Path $fixtureRoot 'RenderingContracts.json'
    $bad | ConvertTo-Json -Depth 35 | Set-Content -LiteralPath $registryPath -Encoding UTF8
    $validatorOutput= & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-ThemeContrast.ps1') -ThemeDirectory $fixtureRoot -FocusThemeFile Cosmora.vstheme -RenderingRegistryPath $registryPath 2>&1 | Out-String
    $validatorExit=$LASTEXITCODE
    Assert-Case ($validatorExit -eq 1 -and $validatorOutput -match 'Audit snapshot hash mismatch' -and $validatorOutput -match "Missing expected theme file.*Amberroot") 'metadata errors do not mask legacy diagnostics'
}
finally {
    $resolved=[IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolved.StartsWith($fixtureParent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'cosmora-rendering-registry-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "Rendering registry regression suite: $count cases passed."
