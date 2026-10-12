[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'EditorSelectionContrast.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'PriorityThemeRefinements.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ContextualContrast.psm1')
Import-Module (Join-Path $PSScriptRoot 'DebuggerHighlightContrast.psm1')
$selection=Read-EditorSelectionPolicy
$policy=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')
$project=Split-Path -Parent $PSScriptRoot
$catalog=Get-Content (Join-Path $project 'authoring/ThemeCatalog.json') -Raw | ConvertFrom-Json
$count=0
function Assert-Selection([bool]$Value,[string]$Name) { if (-not $Value) { throw "FAILED selection: $Name" };$script:count++ }
function Reject-Selection([scriptblock]$Action,[string]$Name) { $rejected=$false;try { & $Action | Out-Null } catch {$rejected=$true};Assert-Selection $rejected $Name }
Assert-Selection ((Get-NormalSelectionBackground 'FF223249' 'FF0E0E11') -ceq 'FF161C27') 'Foundation baseline composition'
Assert-Selection ((Get-NormalSelectionBackground 'FF1C293B' 'FF0E0E11') -ceq 'FF141922') 'Foundation inactive composition'
Assert-Selection ((Get-NormalSelectionBackground 'FF010204' 'FF000000') -ceq 'FF000102') 'Single encoded-channel rounding'
Assert-Selection ((Get-NormalSelectionBackground 'FFFFFFFF' 'FF000000') -ceq 'FF666666') 'Opacity applied once in encoded sRGB'
Assert-Selection ((Get-NormalSelectionBackground 'FFFFFFFF' 'FF202020') -ceq 'FF797979') 'Underlay affects composition'
foreach ($type in @('CT_INVALID','CT_AUTOMATIC','CT_SYSCOLOR','CT_COLORINDEX')) {
    Reject-Selection { Get-NormalSelectionBackground 'FF223249' 'FF0E0E11' -Type $type } "Unsupported fill type $type"
    Reject-Selection { Get-NormalSelectionBackground 'FF223249' 'FF0E0E11' -UnderlayType $type } "Unsupported underlay type $type"
}
Reject-Selection { Get-NormalSelectionBackground '40223249' 'FF0E0E11' } 'Authored alpha cannot substitute for element opacity'
Reject-Selection { Get-NormalSelectionBackground 'FF223249' '400E0E11' } 'Incomplete underlay'
$changes=Get-Content (Join-Path $PSScriptRoot 'evidence/editor-selection/changes.json') -Raw | ConvertFrom-Json
$surfacePolicy=Get-Content (Join-Path $PSScriptRoot 'EditorSurfacePolicy.json') -Raw | ConvertFrom-Json
Assert-Selection ($changes.Count -eq 112 -and @($changes | Where-Object { $_.Key[2] -eq 'Background' }).Count -eq 26) '112 exact changes, 26 dedicated fills'
Assert-Selection (@($changes.Id | Select-Object -Unique).Count -eq 112) 'Unique change IDs'
$pairs=0;$unresolved=0
foreach ($theme in $catalog) {
    [xml]$xml=Get-Content (Join-Path $project $theme.File) -Raw
    $rows=@(Test-PriorityThemeRefinements $xml $policy)
    $matrix=@($rows | Where-Object Check -CEQ 'selection-text');$pairs+=$matrix.Count
    Assert-Selection ($matrix.Count -eq 170 -and @($matrix | Where-Object { $_.Status -ne 'passed' -or -not $_.Enforced -or $_.Ratio -lt 4.5 }).Count -eq 0) "$($theme.Name) 85 roles both states"
    Assert-Selection (@($matrix | Where-Object { $_.Resolution -like 'inherited-*' -and $_.InheritanceTarget }).Count -eq 10) 'Inherited targets remain explicit'
    Assert-Selection (@($matrix | Where-Object { $_.RuntimeAcceptance -ne 'pending' }).Count -eq 0) 'Source pass is not runtime acceptance'
    $unknown=@($rows | Where-Object Check -CEQ 'selection-unresolved-classification');$unresolved+=$unknown.Count
    Assert-Selection ($unknown.Count -eq 14 -and @($unknown | Where-Object { $_.Enforced -or $_.Status -ne 'unresolved' -or -not $_.Detail }).Count -eq 0) 'Unknown consumers remain investigated, not passing'
    if ($theme.Name -eq 'Amberroot') { Assert-Selection (@($rows | Where-Object { $_.Check -eq 'selection-current-line-hierarchy' -and -not $_.Enforced -and $_.Status -eq 'unresolved' }).Count -eq 1) 'Amberroot hierarchy exception visible' }
    foreach ($change in $changes | Where-Object File -CEQ $theme.File) {
        $node=$xml.SelectSingleNode('//Category[@Name="'+$change.Key[0]+'"]/Color[@Name="'+$change.Key[1]+'"]/'+$change.Key[2])
        Assert-Selection ($node.Type -ceq $change.Type -and $node.Source -ceq $change.After) 'Exact reviewed component'
        if ($change.Key[2] -ceq 'Foreground') {
            # These are separate source contexts, not an overlap precedence model.
            $contexts=@(@('Text Editor Text Manager Items','Plain Text','Background'),@('Text Editor MEF Items','CurrentLineActiveFormat','Background'),@('Text Editor MEF Items','MarkerFormatDefinition/HighlightedReference','Background'),@('Text Editor MEF Items','MarkerFormatDefinition/HighlightedDefinition','Background'),@('Text Editor MEF Items','brace matching','Background'))
            $contexts+=@($surfacePolicy.Surfaces | Where-Object { $_.Syntax -and $_.Kind -eq 'fill' -and $_.Role -ne 'Inactive Selected Text' } | ForEach-Object { ,@($_.Category,$_.Role,$_.Component) })
            $contexts+=@(Get-DebuggerHighlightRoles | ForEach-Object { ,@('Text Editor MEF Items',$_,'Background') })
            foreach ($key in $contexts) {
                $background=$xml.SelectSingleNode('//Category[@Name="'+$key[0]+'"]/Color[@Name="'+$key[1]+'"]/'+$key[2])
                if ($null -eq $background -or $background.Type -cne 'CT_RAW' -or $background.Source -cnotmatch '^FF[0-9A-F]{6}$') { throw "Unresolved foreground companion context: $($key -join '/')." }
                $prior=Get-ContextualContrast -Foreground $change.Before -Layers @($background.Source)
                $after=Get-ContextualContrast -Foreground $change.After -Layers @($background.Source)
                Assert-Selection ($after+0.000001 -ge 4.5 -and $after+0.000001 -ge $prior) "$($theme.Name) foreground companion readability: $($change.Key[1]) on $($key[1])"
            }
        }
    }
}
Assert-Selection ($pairs -eq 2210 -and $unresolved -eq 182) 'Complete counts'
[xml]$foundation=Get-Content (Join-Path $project 'Foundation.vstheme') -Raw
$invalidModel=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ThemeRolePolicy.psd1')
$invalidModel.EditorSelectionModel='unverified-model'
[xml]$badModelTheme=$foundation.OuterXml
$badModelTheme.SelectSingleNode('//Category[@Name="Shell"]/Color[@Name="ControlSolidFillDefault"]/Background').Source='FF777777'
$badModelRows=@(Test-PriorityThemeRefinements $badModelTheme $invalidModel)
Assert-Selection (@($badModelRows | Where-Object { $_.Check -eq 'selection-model' -and $_.Status -eq 'failed' }).Count -eq 1) 'Invalid model metadata fails'
Assert-Selection (@($badModelRows | Where-Object { $_.Check -eq 'selection-text' -and $_.Status -eq 'unresolved' }).Count -eq 170) 'Invalid model cannot fall back to passing calculations'
Assert-Selection (@($badModelRows | Where-Object { $_.Check -eq 'image-context' -and $_.Status -eq 'failed' }).Count -eq 1) 'Invalid selection metadata does not hide existing color diagnostics'
foreach ($case in @('faint','strong','reversed','underlay','inherited-base')) {
    [xml]$copy=$foundation.OuterXml
    $a=$copy.SelectSingleNode('//Category[@Name="Text Editor Text Manager Items"]/Color[@Name="Selected Text"]/Background');$i=$copy.SelectSingleNode('//Category[@Name="Text Editor Text Manager Items"]/Color[@Name="Inactive Selected Text"]/Background')
    switch ($case) {
        'faint' {$a.Source='FF0E0E11'}
        'strong' {$a.Source='FFFFFFFF'}
        'reversed' {$swap=$a.Source;$a.Source=$i.Source;$i.Source=$swap}
        'underlay' {$copy.SelectSingleNode('//Category[@Name="Text Editor Text Manager Items"]/Color[@Name="Plain Text"]/Background').Type='CT_AUTOMATIC'}
        'inherited-base' {$copy.SelectSingleNode('//Color[@Name="class name"]/Foreground').Type='CT_AUTOMATIC'}
    }
    Assert-Selection (@(Test-PriorityThemeRefinements $copy $policy | Where-Object { $_.Enforced -and $_.Status -ne 'passed' -and $_.Check -ne 'anchor' }).Count -gt 0) "Measured failure, not only exact anchor: $case"
}
$tempParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture=Join-Path $tempParent ('chxos-selection-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
try {
    foreach ($case in @('opacity','layer','rounding','underlay','missing-guard','invalid-guard','duplicate-role','missing-role','missing-investigation')) {
        $metadataCopy=$selection | ConvertTo-Json -Depth 15 | ConvertFrom-Json
        switch ($case) {
            'opacity' {$metadataCopy.ElementOpacity=0.16}
            'layer' {$metadataCopy.LayerOpacity=0.4}
            'rounding' {$metadataCopy.Rounding='truncate'}
            'underlay' {$metadataCopy.Underlay=@('Shell','SolidBackgroundFillBase','Background')}
            'missing-guard' {$metadataCopy.Guards.PSObject.Properties.Remove('Foundation')}
            'invalid-guard' {$metadataCopy.Guards.Foundation.MinimumStateDistance=-1}
            'duplicate-role' {$metadataCopy.ExtraRoles[0]=$metadataCopy.ExtraRoles[1]}
            'missing-role' {$metadataCopy.ExtraRoles=@($metadataCopy.ExtraRoles | Select-Object -Skip 1)}
            'missing-investigation' {$metadataCopy.Unresolved[0].Next=''}
        }
        $path=Join-Path $fixture ($case+'.json');$metadataCopy | ConvertTo-Json -Depth 15 | Set-Content $path -Encoding UTF8
        Reject-Selection { Read-EditorSelectionPolicy $path } "Malformed metadata: $case"
    }
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($tempParent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'chxos-selection-*') {throw 'Unsafe selection fixture cleanup.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "Editor selection regression suite: $count cases passed; runtime acceptance pending."
