[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RuntimeAcceptance.psm1') -Force
$count=0
function Assert-Case([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }; $script:count++
}
$required=@('present','missing')
$rows=@(Get-CaptureCompleteness $required ([ordered]@{present='a'}) ([ordered]@{present='b'}))
Assert-Case ($rows.Count -eq 2 -and $rows[1].Status -eq 'invalid') 'missing both captures remains visible'
$rows=@(Get-CaptureCompleteness @('present') ([ordered]@{}) ([ordered]@{present='b'}))
Assert-Case ($rows[0].Status -eq 'invalid') 'missing reference fails'
$rows=@(Get-CaptureCompleteness @('present') ([ordered]@{present='a'}) ([ordered]@{}))
Assert-Case ($rows[0].Status -eq 'invalid') 'missing candidate fails'
$manifest=@([pscustomobject]@{Id='example';Required=$true})
$hash='A'*64
$rows=@(Test-RuntimeAcceptance $manifest @('Amberroot') @() $hash)
Assert-Case ($rows[0].Status -eq 'skipped') 'no runtime evidence is not a pass'
$path=[IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($path,'synthetic test evidence, not a screenshot')
    $record=[pscustomobject]@{Theme='Amberroot';Scenario='example';VsixSha256=$hash;Reviewer='test';StateVerified=$true;Path=$path;Sha256=(Get-FileHash $path).Hash;Status='pass';Notes='synthetic'}
    Assert-Case ((Test-RuntimeAcceptance $manifest @('Amberroot') @($record) $hash).Status -eq 'pass') 'reviewed manual evidence accepted'
    $record.StateVerified=$false
    Assert-Case ((Test-RuntimeAcceptance $manifest @('Amberroot') @($record) $hash).Status -eq 'invalid') 'invalid UI state rejected'
    $record.StateVerified=$true;$record.VsixSha256='B'*64
    Assert-Case ((Test-RuntimeAcceptance $manifest @('Amberroot') @($record) $hash).Status -eq 'invalid') 'wrong artifact rejected'
    $record.VsixSha256=$hash;$record.Sha256='C'*64
    Assert-Case ((Test-RuntimeAcceptance $manifest @('Amberroot') @($record) $hash).Status -eq 'invalid') 'changed image rejected'
    $threw=$false
    try { Test-RuntimeAcceptance $manifest @('Amberroot') @($record,$record) $hash | Out-Null } catch {$threw=$true}
    Assert-Case $threw 'duplicate evidence rejected'
}
finally { Remove-Item -LiteralPath $path -Force }
Write-Host "All $count runtime acceptance cases pass."
