Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'PriorityThemeRefinements.psm1')
Import-Module (Join-Path $PSScriptRoot 'EditorSelectionContrast.psm1')

# Metadata only. This module never calculates contrast or decides whether a
# legacy source measurement passes. It is usable without Visual Studio/network.
function Read-RenderingContracts {
    param([string]$RegistryPath = (Join-Path $PSScriptRoot 'RenderingContracts.json'), [Collections.IDictionary]$Policy)
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($registry.SchemaVersion -notin @(1,2)) { throw 'Unsupported rendering registry schema.' }
    $snapshotRoot = Join-Path $root $registry.AuditSnapshot.Path
    $snapshots = @{}
    foreach ($file in $registry.AuditSnapshot.Files) {
        $path = Join-Path $snapshotRoot $file.Name
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $file.Sha256) { throw "Audit snapshot hash mismatch: $($file.Name)." }
        if ($snapshots.ContainsKey($file.Name)) { throw "Duplicate audit snapshot: $($file.Name)." }
        $snapshots[$file.Name] = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $evidence = @{}
    foreach ($spec in @(
        @{ Kind='documentation'; Rows=$snapshots['sources.json'] },
        @{ Kind='implementation'; Rows=$snapshots['consumers.json'].consumers },
        @{ Kind='audit'; Rows=$snapshots['rules.json'].groups },
        @{ Kind='audit'; Rows=$snapshots['rules.json'].rules },
        @{ Kind='finding'; Rows=$snapshots['findings.json'].findings }
    )) {
        foreach ($row in $spec.Rows) {
            if ($evidence.ContainsKey($row.id)) { throw "Duplicate evidence identity: $($row.id)." }
            $evidence[$row.id] = @{ Kind=$spec.Kind; Record=$row }
        }
    }
    if ($registry.SchemaVersion -eq 2) {
        $seenPaths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($source in $registry.EvidenceSources) {
            if ([IO.Path]::IsPathRooted($source.Path) -or $source.Path -match '(^|[\\/])\.\.([\\/]|$)' -or $source.Path -notmatch '^(docs/audits/evidence|Chxos\.VisualStudio\.Themes/tools/evidence)/.+\.json$' -or -not $seenPaths.Add($source.Path)) { throw 'Invalid supplemental evidence path.' }
            $path=Join-Path $root $source.Path
            if ($source.Sha256 -cnotmatch '^[0-9A-F]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $source.Sha256) { throw "Supplemental evidence hash mismatch: $($source.Path)." }
            foreach ($entry in (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)) {
                if ($entry.Kind -cnotin @('documentation','implementation','project-decision') -or -not $entry.Record.id -or $evidence.ContainsKey($entry.Record.id)) { throw 'Invalid or duplicate supplemental evidence identity.' }
                $evidence[$entry.Record.id]=@{Kind=$entry.Kind;Record=$entry.Record}
            }
        }
    }
    $project = Split-Path -Parent $PSScriptRoot
    $model = Get-Content (Join-Path $project 'authoring/Components.json') -Raw | ConvertFrom-Json
    $palettes = Get-Content (Join-Path $project 'authoring/Palettes.json') -Raw | ConvertFrom-Json
    $parts = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($category in $model.Categories) {
        foreach ($color in $category.Colors) {
            foreach ($part in $color.Components) { $parts.Add((@($category.Name,$color.Name,$part.Component) -join [char]31),$part) }
        }
    }
    if ($null -eq $Policy) { $Policy = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1') }
    [pscustomobject]@{
        Registry=$registry; Evidence=$evidence; Snapshots=$snapshots; Parts=$parts; Policy=$Policy; Palettes=$palettes; ThemeOrder=$model.ThemeOrder
        Themes=@((Get-Content (Join-Path $project 'authoring/ThemeCatalog.json') -Raw | ConvertFrom-Json) | ForEach-Object Name)
        Relationships=(Get-Content (Join-Path $PSScriptRoot 'ContextualRelationships.json') -Raw | ConvertFrom-Json)
        Surfaces=(Get-Content (Join-Path $PSScriptRoot 'EditorSurfacePolicy.json') -Raw | ConvertFrom-Json).Surfaces
    }
}

function Resolve-RenderingPolicyMember {
    param([Collections.IDictionary]$Policy, [object]$Selector)
    if (-not $Policy.Contains($Selector.Family)) { throw "Missing policy family: $($Selector.Family)." }
    $value = $Policy[$Selector.Family]
    $fields = @($Selector.PSObject.Properties.Name | Where-Object { $_ -ne 'Family' })
    if ($fields.Count -gt 1 -or @($fields | Where-Object { $_ -notin @('Key','Match','Value') }).Count) { throw 'Malformed policy selector.' }
    if ($fields.Count -eq 0) {
        if ($value -is [Collections.IDictionary] -or $value -is [array]) { throw 'A collection requires a member selector.' }
        return ,$value
    }
    if ($fields[0] -eq 'Key') {
        if ($value -isnot [Collections.IDictionary] -or -not $value.Contains($Selector.Key)) { throw "Missing named policy member: $($Selector.Key)." }
        return ,$value[$Selector.Key]
    }
    if ($value -isnot [array]) { throw 'Array member selector requires an array policy.' }
    $matches = @($value | Where-Object {
        $candidate = $_
        if ($fields[0] -eq 'Value') { $candidate -isnot [Collections.IDictionary] -and $candidate -ceq $Selector.Value }
        else {
            $match = $candidate -is [Collections.IDictionary] -and @($Selector.Match.PSObject.Properties).Count -gt 0
            foreach ($property in $Selector.Match.PSObject.Properties) {
                if (-not $match -or -not $candidate.Contains($property.Name) -or $candidate[$property.Name] -cne $property.Value) { $match=$false; break }
            }
            $match
        }
    })
    if ($matches.Count -ne 1) { throw "Policy selector must match exactly one member, found $($matches.Count): $($Selector.Family)." }
    return ,$matches[0]
}

function Test-RenderingContracts {
    param([Parameter(Mandatory)][object]$Context)
    $r=$Context.Registry
    $errors=[Collections.Generic.List[string]]::new()
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $profiles=@{}; $contracts=@{}; $relationContracts=@{}; $surfaceContracts=@{}; $memberGroups=@{}
    function Assert-Evidence($references) {
        foreach ($id in $references) { if (-not $Context.Evidence.ContainsKey($id)) { throw "Unknown evidence citation: $id." } }
    }
    function Assert-Component($key) {
        if (@($key).Count -ne 3 -or $key[2] -cnotin @('Foreground','Background') -or -not $Context.Parts.ContainsKey(($key -join [char]31))) { throw "Missing or invalid component: $($key -join '/')." }
    }
    if ($r.SchemaVersion -notin @(1,2)) { $errors.Add('Unsupported rendering registry schema.') }
    if ($Context.Policy.Contains('EditorSelectionModel')) {
        try {
            $selection=Read-EditorSelectionPolicy
            $profile=@($r.Profiles | Where-Object Id -CEQ 'selection-normal')
            if ($profile.Count -ne 1 -or $profile[0].SelectionModel.Id -cne $selection.Id -or
                $profile[0].SelectionModel.Policy -cne 'EditorSelectionPolicy.json' -or
                $Context.Policy.EditorSelectionModel -cne $selection.Id -or $profile[0].SelectionModel.Version -cne $selection.Version -or
                $profile[0].SelectionModel.ElementOpacity -ne $selection.ElementOpacity -or
                $profile[0].SelectionModel.LayerOpacity -ne 1 -or $profile[0].SelectionModel.BrushOpacity -ne 1) { throw 'Selection policy/registry rendering model disagreement.' }
            Assert-Evidence $profile[0].SelectionModel.Evidence
            if (@($profile[0].SelectionModel.Evidence | Where-Object { $_ -cin @('SEL-PAINTER-1810','SEL-FONTS-1810','SEL-CALCULATION') }).Count -ne 3) { throw 'Selection model requires the reviewed implementation and calculation evidence.' }
            foreach ($entry in $selection.ExtraRoles) { Assert-Component @($entry.Category,$entry.Role,'Foreground') }
            foreach ($entry in $selection.Unresolved) { Assert-Component $entry.Key }
            $contract=$r.Contracts | Where-Object Id -CEQ 'RC-ACTIVE-SELECTION'
            $modelRequirement=@($contract.Requirements | Where-Object Source -CEQ 'EditorSelectionContrast.psm1#Get-NormalSelectionBackground')
            if ($modelRequirement.Count -ne 1 -or $modelRequirement[0].Enforcement -cne 'implemented' -or
                (($modelRequirement[0].Themes | Sort-Object) -join '|') -cne (($Context.Themes | Sort-Object) -join '|')) { throw 'Selection model requirement scope disagrees with the reviewed catalog.' }
        } catch { $errors.Add("Selection metadata: $($_.Exception.Message)") }
    }
    $hasScopeContracts=@($r.PolicyMembers | Where-Object { $_.Selector.Family -ceq 'RefinementEnforcement' }).Count -gt 0
    foreach ($problem in Test-RefinementEnforcementPolicy -Policy $Context.Policy -ThemeNames $Context.Themes -RequireExplicit $hasScopeContracts) { $errors.Add($problem) }
    if ($Context.Policy.Contains('RefinementEnforcement') -and $Context.Policy.RefinementEnforcement -is [Collections.IDictionary]) {
        $enforcedThemes=@($Context.Themes | Where-Object { $Context.Policy.RefinementEnforcement.Contains($_) -and $Context.Policy.RefinementEnforcement[$_] -ceq 'enforced' })
        $pendingThemes=@($Context.Themes | Where-Object { $Context.Policy.RefinementEnforcement.Contains($_) -and $Context.Policy.RefinementEnforcement[$_] -ceq 'pending' })
        foreach ($spec in @(
            @('RC-ACTIVE-SELECTION','PriorityThemeRefinements.psm1#Test-PriorityThemeRefinements'),
            @('RC-PRIORITY-REFINEMENTS','ThemeRolePolicy.psd1#PriorityRefinementAnchors'),
            @('RC-PRIORITY-REFINEMENTS','ThemeRolePolicy.psd1#PrioritySelectionMinimum'),
            @('RC-PRIORITY-REFINEMENTS','ThemeRolePolicy.psd1#PrioritySelectionDistanceMinimum'),
            @('RC-TOOLBAR-IMAGE-CONTEXT','PriorityThemeRefinements.psm1#Get-PriorityIconRenderingDecision')
        )) {
            $contract=@($r.Contracts | Where-Object Id -CEQ $spec[0])
            foreach ($state in @('implemented','pending')) {
                $expected=if ($state -eq 'implemented') { $enforcedThemes } else { $pendingThemes }
                $actual=@($contract | ForEach-Object Requirements | Where-Object { $_.Source -ceq $spec[1] -and $_.Enforcement -ceq $state } | ForEach-Object Themes)
                if ((($actual | Sort-Object) -join '|') -cne (($expected | Sort-Object) -join '|')) { $errors.Add("Refinement scope/registry disagreement: $($spec[0]) $($spec[1]) $state.") }
            }
        }
    }
    foreach ($e in $Context.Evidence.Values) {
        try {
            if ($e.Kind -eq 'documentation') {
                $s=$e.Record
                if ($s.url -notmatch '^https://' -or -not $s.sections -or -not $s.applicability -or $s.retrievedDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "Incomplete documentation provenance: $($s.id)." }
            }
            if ($e.Kind -eq 'implementation') {
                $s=$e.Record
                if ($s.assembly.Sha256 -cnotmatch '^[0-9A-F]{64}$' -or -not $s.assembly.FileVersion -or -not $s.result) { throw "Incomplete implementation provenance: $($s.id)." }
            }
            if ($e.Kind -eq 'project-decision' -and (-not $e.Record.result -or $e.Record.date -notmatch '^\d{4}-\d{2}-\d{2}$')) { throw 'Incomplete project-decision provenance.' }
        } catch { $errors.Add($_.Exception.Message) }
    }
    foreach ($profile in $r.Profiles) {
        try {
            if ($profiles.ContainsKey($profile.Id)) { throw "Duplicate rendering profile: $($profile.Id)." }
            $profiles[$profile.Id]=$profile
            Assert-Evidence $profile.Evidence
            if (-not $profile.Claim -or -not $profile.Validity) { throw 'Missing rendering claim or validity semantics.' }
            if ($profile.Representation -cnotin @('unresolved','colorref-rgb','argb-brush','conditional','inherited','automatic','system-index','image-background-color')) { throw 'Unknown consumer representation.' }
            if ($profile.Representation -eq 'image-background-color' -and ($r.SchemaVersion -ne 2 -or $profile.Alpha -cne 'not-applicable' -or $profile.Validity -cne 'opaque-context-only')) { throw 'Image background context requires schema 2 and opaque context semantics, not brush composition.' }
            if ($profile.Alpha -cnotin @('unresolved','discarded-for-valid-raw','brush-alpha','not-applicable')) { throw 'Unknown alpha behavior.' }
            if ($profile.Representation -eq 'colorref-rgb' -and $profile.Alpha -cne 'discarded-for-valid-raw') { throw 'RGB conversion cannot claim brush-alpha composition.' }
            if ($profile.Representation -eq 'argb-brush' -and $profile.Alpha -cne 'brush-alpha') { throw 'Brush representation requires explicit brush alpha semantics.' }
            if ($profile.Representation -notin @('unresolved','conditional') -and @($profile.Evidence | Where-Object { $Context.Evidence[$_].Kind -eq 'implementation' }).Count -eq 0) { throw 'A resolved consumer profile requires version-pinned implementation evidence.' }
        } catch { $errors.Add("Profile $($profile.Id): $($_.Exception.Message)") }
    }
    foreach ($c in $r.Contracts) {
        try {
            if ($c.Id -cnotmatch '^RC-[A-Z0-9-]+$' -or -not $ids.Add($c.Id)) { throw "Invalid or duplicate contract ID: $($c.Id)." }
            $contracts[$c.Id]=$c
            if ($c.PSObject.Properties.Name -contains 'RelationshipId') {
                if (-not $relationContracts.ContainsKey($c.RelationshipId)) { $relationContracts[$c.RelationshipId]=[Collections.Generic.List[object]]::new() }
                $relationContracts[$c.RelationshipId].Add($c)
            }
            if ($c.PSObject.Properties.Name -contains 'SurfaceKey') {
                $surfaceKey=$c.SurfaceKey -join [char]31
                if (-not $surfaceContracts.ContainsKey($surfaceKey)) { $surfaceContracts[$surfaceKey]=0 }
                $surfaceContracts[$surfaceKey]++
            }
            if ($c.Assessment -cnotin @('supported','intentional project policy','mismatch','unresolved')) { throw 'Invalid audit assessment.' }
            if ($c.RenderingStatus -cnotin @('supported','conditional','unresolved','policy-only')) { throw 'Invalid rendering status.' }
            if (-not $profiles.ContainsKey($c.Profile)) { throw 'Missing rendering profile.' }
            $profile=$profiles[$c.Profile]
            if ($profile.Representation -eq 'image-background-color') {
                Assert-Component $c.ImageBackgroundComponent
                $contextPart=$Context.Parts[($c.ImageBackgroundComponent -join [char]31)]
                if ($contextPart.Type -cne 'CT_RAW' -or -not $c.ImageConditions) { throw 'Image context requires a raw component and explicit image eligibility conditions.' }
                foreach ($theme in $c.Themes) {
                    $index=[Array]::IndexOf($Context.Themes,$theme)
                    $value=if ($contextPart.PSObject.Properties.Name -contains 'Anchors') { $Context.Palettes.($Context.ThemeOrder[$index]).($contextPart.Anchors[$index]) } elseif ($contextPart.PSObject.Properties.Name -contains 'Sources') { $contextPart.Sources[$index] } else { $contextPart.Source }
                    if ($value -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Image context evidence establishes opaque values only.' }
                }
            }
            if ($c.Purpose -cnotin @('text','glyph','fill','border','texture','unresolved')) { throw 'Invalid semantic purpose.' }
            if (@($c.Themes).Count -eq 0 -or @($c.Themes | Select-Object -Unique).Count -ne @($c.Themes).Count -or @($c.Themes | Where-Object { $_ -cnotin $Context.Themes }).Count) { throw 'Invalid theme scope.' }
            if (-not $c.Consumer -or -not $c.State -or -not $c.VersionScope -or -not $c.Overlap -or -not $c.NextInvestigation) { throw 'Missing consumer, state, version, overlap or next investigation.' }
            Assert-Evidence $c.Evidence
            Assert-Evidence $c.AuditRuleIds
            $componentIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($part in $c.Components) {
                Assert-Component $part.Key
                if (-not $componentIds.Add(($part.Key -join [char]31))) { throw 'Duplicate component within contract.' }
                if ($part.AuthoredType -cnotin @('CT_RAW','CT_INVALID','CT_AUTOMATIC','CT_SYSCOLOR','CT_COLORINDEX') -or $Context.Parts[($part.Key -join [char]31)].Type -cne $part.AuthoredType) { throw 'Authored type does not match the typed component inventory.' }
            }
            if ($c.Underlay.Order -cne 'nearest-to-outermost') { throw 'Unknown underlay composition order.' }
            foreach ($key in $c.Underlay.Layers) { Assert-Component $key }
            if ($c.PSObject.Properties.Name -contains 'AdjacentSurfaces') { foreach ($key in $c.AdjacentSurfaces) { Assert-Component $key } }
            if ($c.Underlay.Complete) {
                if (@($c.Underlay.Layers).Count -eq 0) { throw 'A complete underlay requires a terminal surface.' }
                $base=$Context.Parts[($c.Underlay.Layers[-1] -join [char]31)]
                if ($base.Type -cne 'CT_RAW') { throw 'A complete raw chain cannot terminate in an unresolved typed surface.' }
                # This checks authoring metadata, never the mutable theme fixture.
                if ($base.PSObject.Properties.Name -contains 'Sources' -and @($base.Sources | Where-Object { $_ -cnotmatch '^FF[0-9A-F]{6}$' }).Count) { throw 'Complete underlay must terminate in an opaque base.' }
                if ($base.PSObject.Properties.Name -contains 'Source' -and $base.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Complete underlay must terminate in an opaque base.' }
                if ($base.PSObject.Properties.Name -contains 'Anchors') {
                    for ($i=0;$i -lt $Context.ThemeOrder.Count;$i++) {
                        $palette=$Context.Palettes.($Context.ThemeOrder[$i]); $anchor=$base.Anchors[$i]
                        if ($palette.$anchor -cnotmatch '^FF[0-9A-F]{6}$') { throw 'Complete underlay anchor must resolve to an opaque base.' }
                    }
                }
            }
            if ($c.RenderingStatus -eq 'supported') {
                if ($profile.Representation -in @('unresolved','conditional') -or $c.Purpose -eq 'unresolved' -or -not $c.Underlay.Complete) { throw 'Unsupported confirmation: representation, meaning and complete underlay must be established.' }
                if (@($c.Components).Count -eq 0) { throw 'A supported consumer requires components.' }
                if ($c.Id -cnotin $profile.SupportedContractIds) { throw 'Unsupported confirmation outside the evidence profile reviewed scope.' }
            }
            if ($c.RenderingStatus -in @('unresolved','conditional') -and -not $c.MissingEvidence) { throw 'Unresolved consumers require missing evidence and a concrete next investigation.' }
            if ($profile.Validity -eq 'unresolved-post-merge' -and ($c.RenderingStatus -ne 'conditional' -or @($c.ConditionalBranches).Count -ne 2)) { throw 'Unresolved validity must retain both conditional branches.' }
            if ($c.RenderingStatus -eq 'conditional') {
                if ($profile.Representation -ne 'conditional') { throw 'Conditional rendering requires a conditional profile.' }
                foreach ($branch in $c.ConditionalBranches) {
                    if (-not $branch.Condition -or $branch.Representation -cnotin @('inherited','colorref-rgb') -or ($branch.Representation -eq 'colorref-rgb' -and $branch.Alpha -ne 'discarded-for-valid-raw')) { throw 'Invalid conditional rendering branch.' }
                    foreach ($key in $branch.Underlay) { Assert-Component $key }
                }
            }
            foreach ($q in $c.Requirements) {
                $enforcement=@('existing-unchanged','pending')
                if ($r.SchemaVersion -eq 2) { $enforcement+=@('implemented') }
                if ($q.Kind -cnotin @('contrast','comfort','perceptual-distance','binding','representation','rendering-model') -or $q.Enforcement -cnotin $enforcement -or -not $q.Source -or -not $q.Description -or -not $q.Basis) { throw 'Malformed validation requirement.' }
                if ($q.PSObject.Properties.Name -contains 'Themes') {
                    if ($r.SchemaVersion -ne 2 -or @($q.Themes).Count -eq 0 -or @($q.Themes | Select-Object -Unique).Count -ne @($q.Themes).Count -or @($q.Themes | Where-Object { $_ -cnotin $c.Themes }).Count) { throw 'Invalid requirement theme scope.' }
                }
                if ($q.Enforcement -eq 'implemented' -and ($q.PSObject.Properties.Name -notcontains 'Themes' -or $q.Source -notmatch '(ThemeRolePolicy.psd1|PriorityThemeRefinements.psm1|EditorSelectionContrast.psm1)#')) { throw 'Implemented requirement needs theme scope and executable policy location.' }
                Assert-Evidence $q.Evidence
            }
            if ($r.SchemaVersion -eq 2) {
                $scoped=@($c.Requirements | Where-Object { $_.PSObject.Properties.Name -contains 'Id' } | Group-Object Id)
                foreach ($group in $scoped) {
                    $scopes=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                    foreach ($q in $group.Group) {
                        $scope=if ($q.PSObject.Properties.Name -contains 'Themes') { $q.Themes } else { $c.Themes }
                        foreach ($theme in $scope) { if (-not $scopes.Add($theme)) { throw 'Overlapping requirement enforcement scopes.' } }
                    }
                }
            }
            if ($c.PSObject.Properties.Name -contains 'PolicySelector') { $null=Resolve-RenderingPolicyMember $Context.Policy $c.PolicySelector }
        } catch { $errors.Add("Contract $($c.Id): $($_.Exception.Message)") }
    }
    # Ensure the sidecar describes every existing registration exactly once.
    foreach ($entry in $Context.Relationships) {
        $matches=@(if ($relationContracts.ContainsKey($entry.id)) { $relationContracts[$entry.id].ToArray() })
        if ($matches.Count -ne 1) { $errors.Add("Relationship coverage must be one-to-one: $($entry.id).") }
        else {
            if ($matches[0].Assessment -cne $Context.Evidence['DR-REL-'+$entry.id].Record.assessment) { $errors.Add("Relationship assessment differs from the retained audit: $($entry.id).") }
            $registeredKeys=@($matches[0].Components | ForEach-Object { $_.Key -join [char]31 })
            foreach ($key in @(@{Key=$entry.foreground},@{Key=$entry.background})+@($entry.bases | ForEach-Object { @{Key=$_} })) {
                if (($key.Key -join [char]31) -cnotin $registeredKeys) { $errors.Add("Relationship component coverage missing: $($entry.id).") }
            }
        }
    }
    foreach ($id in $relationContracts.Keys) { if ($id -cnotin @($Context.Relationships | ForEach-Object id)) { $errors.Add("Unknown relationship selector: $id.") } }
    foreach ($key in $surfaceContracts.Keys) { if ($key -cnotin @($Context.Surfaces | ForEach-Object { @($_.Category,$_.Role,$_.Component) -join [char]31 })) { $errors.Add("Unknown editor surface selector: $key.") } }
    foreach ($entry in $Context.Surfaces) {
        $key=@($entry.Category,$entry.Role,$entry.Component) -join [char]31
        if (-not $surfaceContracts.ContainsKey($key) -or $surfaceContracts[$key] -ne 1) { $errors.Add("Editor surface coverage must be one-to-one: $key.") }
    }
    foreach ($member in $r.PolicyMembers) {
        if (-not $Context.Policy.Contains($member.Selector.Family)) { $errors.Add("Unknown policy family: $($member.Selector.Family).") }
        if (-not $memberGroups.ContainsKey($member.Selector.Family)) { $memberGroups[$member.Selector.Family]=[Collections.Generic.List[object]]::new() }
        $memberGroups[$member.Selector.Family].Add($member)
    }
    foreach ($family in $Context.Policy.Keys) {
        $members=@(if ($memberGroups.ContainsKey($family)) { $memberGroups[$family].ToArray() })
        $value=$Context.Policy[$family]
        $expected=if ($value -is [Collections.IDictionary] -or $value -is [array]) { $value.Count } else { 1 }
        if ($members.Count -ne $expected) { $errors.Add("Policy member coverage mismatch: $family.") }
        $selectors=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($member in $members) {
            try {
                $resolved=Resolve-RenderingPolicyMember $Context.Policy $member.Selector
                # Resolved values catch overlapping selectors, regardless of property order.
                $signature=if ($resolved -is [Collections.IDictionary]) { ($resolved.Keys | Sort-Object | ForEach-Object { $_+'='+($resolved[$_] | ConvertTo-Json -Depth 15 -Compress) }) -join '|' } else { $member.Selector | ConvertTo-Json -Depth 10 -Compress }
                if (-not $selectors.Add($signature)) { throw 'Duplicate or overlapping policy member selectors.' }
                if (-not $contracts.ContainsKey($member.Id)) { throw 'Policy member has no contract.' }
                if (($contracts[$member.Id].PolicySelector | ConvertTo-Json -Compress) -cne ($member.Selector | ConvertTo-Json -Compress)) { throw 'Policy member and contract selectors disagree.' }
            } catch { $errors.Add("Policy $family`: $($_.Exception.Message)") }
        }
    }
    $auditIds=@($Context.Snapshots['rules.json'].rules | ForEach-Object id)
    $coverageIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $requirementIds=@($r.Requirements | ForEach-Object Id)
    if (@($requirementIds | Select-Object -Unique).Count -ne $requirementIds.Count) { $errors.Add('Duplicate project requirement IDs.') }
    if (@($r.CalculationProfiles.Id | Select-Object -Unique).Count -ne @($r.CalculationProfiles).Count) { $errors.Add('Duplicate calculation profile IDs.') }
    foreach ($entry in $r.RuleCoverage) {
        try {
            if (-not $coverageIds.Add($entry.AuditRuleId) -or $entry.AuditRuleId -cnotin $auditIds) { throw 'Duplicate or unknown audit rule mapping.' }
            if ($entry.Classification -cnotin @('rendering-contract','project-requirement','structural','screening') -or -not $entry.Rationale -or $entry.RequirementId -cnotin $requirementIds) { throw 'Invalid rule reconciliation.' }
            foreach ($id in $entry.ContractIds) { if (-not $contracts.ContainsKey($id)) { throw "Unknown contract reference: $id." } }
            if ($entry.Classification -eq 'rendering-contract' -and @($entry.ContractIds).Count -eq 0) { throw 'Rendering rule has no contract.' }
        } catch { $errors.Add("Rule $($entry.AuditRuleId): $($_.Exception.Message)") }
    }
    if ($coverageIds.Count -ne $auditIds.Count) { $errors.Add('Not every audit rule has a reconciliation.') }
    foreach ($item in @($r.Requirements)+@($r.CalculationProfiles)) {
        try { Assert-Evidence $item.Evidence } catch { $errors.Add($_.Exception.Message) }
    }
    foreach ($profile in $r.Profiles) {
        foreach ($id in $profile.SupportedContractIds) {
            if (-not $contracts.ContainsKey($id) -or $contracts[$id].Profile -cne $profile.Id -or $contracts[$id].RenderingStatus -cne 'supported') { $errors.Add("Stale profile support reference: $id.") }
        }
    }
    return $errors.ToArray()
}

function Get-RenderingEvidenceReport {
    param([Parameter(Mandatory)][object]$Context, [object[]]$Inventory)
    $r=$Context.Registry
    $byComponent=@{}
    foreach ($c in $r.Contracts) {
        foreach ($part in $c.Components) {
            $key=$part.Key -join [char]31
            if (-not $byComponent.ContainsKey($key)) { $byComponent[$key]=[Collections.Generic.List[string]]::new() }
            $byComponent[$key].Add($c.Id)
        }
    }
    $components=@(foreach ($part in $Inventory) {
        $key=$part.key -join [char]31
        [pscustomobject]@{ Key=$part.key; HistoricalClassification=$part.classification; ContractIds=@(if ($byComponent.ContainsKey($key)) { $byComponent[$key].ToArray() }) }
    })
    $relationshipEvidence=@(foreach ($c in $r.Contracts | Where-Object { $_.PSObject.Properties.Name -contains 'RelationshipId' }) {
        [pscustomobject]@{ Id=$c.RelationshipId; ContractId=$c.Id; Assessment=$c.Assessment; RenderingStatus=$c.RenderingStatus; Runtime='pending' }
    })
    [pscustomobject]@{
        SchemaVersion=1
        Scope='Evidence confidence is independent of legacy source-check status. Registry coverage is not runtime or release acceptance.'
        ContractCount=@($r.Contracts).Count; AuditRuleCount=@($r.RuleCoverage).Count; PolicyMemberCount=@($r.PolicyMembers).Count
        RelationshipAssessments=@($relationshipEvidence | Group-Object Assessment | ForEach-Object { [pscustomobject]@{ Assessment=$_.Name; Count=$_.Count } })
        Relationships=$relationshipEvidence
        Contracts=@($r.Contracts | Select-Object Id,Assessment,RenderingStatus,Profile,Purpose,Themes,Requirements,MissingEvidence,NextInvestigation)
        Components=$components
        PendingRequirements=@(foreach ($c in $r.Contracts) { foreach ($q in $c.Requirements | Where-Object Enforcement -eq 'pending') { [pscustomobject]@{ ContractId=$c.Id; Requirement=$q } } })
        RuntimeAcceptance='pending'; ReleaseAcceptance='not evaluated'
    }
}

Export-ModuleMember -Function Read-RenderingContracts, Test-RenderingContracts, Resolve-RenderingPolicyMember, Get-RenderingEvidenceReport
