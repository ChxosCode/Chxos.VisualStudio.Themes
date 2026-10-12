Set-StrictMode -Version Latest

function Test-RuntimeAcceptance {
    param([object[]]$Manifest, [string[]]$Themes, [object[]]$Evidence, [string]$VsixSha256)
    $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $Evidence) {
        if (-not $keys.Add("$($record.Theme)/$($record.Scenario)")) { throw 'Duplicate runtime evidence identity.' }
        if ($record.Theme -cnotin $Themes -or $record.Scenario -cnotin @($Manifest | ForEach-Object Id)) { throw 'Unknown theme/scenario in runtime evidence.' }
    }
    foreach ($theme in $Themes) {
        foreach ($scenario in $Manifest) {
            $records = @($Evidence | Where-Object { $_.Theme -ceq $theme -and $_.Scenario -ceq $scenario.Id })
            $status = 'skipped'; $reason = 'No evidence supplied.'
            if ($records.Count -eq 1) {
                $record = $records[0]
                $status = 'invalid'; $reason = 'Evidence requires exact artifact, reviewer, state confirmation and hashed capture.'
                $fields = @($record.PSObject.Properties.Name)
                $missing = @(@('VsixSha256','Reviewer','StateVerified','Path','Sha256','Status','Notes') | Where-Object { $_ -cnotin $fields })
                if ($missing.Count -eq 0 -and $record.VsixSha256 -ceq $VsixSha256 -and $record.Reviewer -and $record.StateVerified -is [bool] -and $record.StateVerified -eq $true -and $record.Path -and (Test-Path -LiteralPath $record.Path -PathType Leaf)) {
                    if ((Get-FileHash -LiteralPath $record.Path -Algorithm SHA256).Hash -ceq $record.Sha256 -and $record.Status -cin @('pass','fail')) {
                        $status = $record.Status; $reason = [string]$record.Notes
                    }
                }
            }
            [pscustomobject]@{ Theme=$theme; Scenario=$scenario.Id; Required=$scenario.Required; Status=$status; Reason=$reason }
        }
    }
}

function Get-CaptureCompleteness {
    param([string[]]$RequiredScenarios, [Collections.IDictionary]$Reference, [Collections.IDictionary]$Candidate)
    foreach ($scenario in $RequiredScenarios) {
        $missing = @()
        if (-not $Reference.Contains($scenario)) { $missing += 'reference' }
        if (-not $Candidate.Contains($scenario)) { $missing += 'candidate' }
        [pscustomobject]@{ Scenario=$scenario; Status=$(if ($missing.Count) {'invalid'} else {'captured'}); Missing=($missing -join ', ') }
    }
}

Export-ModuleMember -Function Test-RuntimeAcceptance, Get-CaptureCompleteness
