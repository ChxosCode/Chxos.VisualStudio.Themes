# Development

One VSIX project builds Foundation, Pinknoise, the four-theme Cosmora pack, and
the internal `all-dev` collection. Product identities and independent versions
are in [PackageCatalog.json](../Chxos.VisualStudio.Themes/authoring/PackageCatalog.json).

## Prerequisites

Use Windows, Git, the .NET SDK specified in [global.json](../global.json), and
Windows PowerShell 5.1. The first restore needs NuGet access. The VSIX compiler
and VSSDK tools are pinned in `Chxos.VisualStudio.Themes/packages.lock.json`, so
command-line packaging does not require Visual Studio. Interactive tests need
Visual Studio 2026 with its extension-development workload and a desktop session.

## Build and test

Run these commands from the repository root in PowerShell:

```powershell
./Chxos.VisualStudio.Themes/tools/Build-ThemePackages.ps1 -AllPublic
# Include all-dev to build the internal thirteen-theme collection too:
./Chxos.VisualStudio.Themes/tools/Build-ThemePackages.ps1 -Package foundation,pinknoise,cosmora,all-dev
```

Use either `-AllPublic` or `-Package`. For multiple keys, call the script directly;
`powershell.exe -File` does not parse comma-separated arguments as an array.

The builder defaults to Release, generates missing deferred themes, checks
generation drift, validates all thirteen themes, restores locked dependencies,
and builds and inspects the selected packages. It does not install or publish.

Outputs go to `artifacts/packages/<run>/<configuration>/<key>/<version>/`.
`-OutputDirectory` changes the parent of the run directory. Check that the overall
`Succeeded` value in `build.json` is true before using an archive; a failed run
may leave a VSIX behind.

For a direct solution build, use the same package and configuration for restore
and build:

```powershell
dotnet restore ./Chxos.VisualStudio.Themes.slnx --locked-mode -p:Configuration=Release -p:ThemePackage=foundation
dotnet build ./Chxos.VisualStudio.Themes.slnx -c Release --no-restore -p:ThemePackage=foundation
```

Direct builds default to `all-dev`. Each package and configuration has separate
`bin/` and `obj/` outputs. IDE builds may deploy to an experimental instance;
command-line builds do not.

The [CI workflow](../.github/workflows/ci.yml) lists regression, four-package build,
clean-build, isolation, and eligibility checks. Run an individual suite by
substituting its filename below, or build the visual-test fixture:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./Chxos.VisualStudio.Themes/tools/Test-PublicRepository.Tests.ps1
dotnet build ./Chxos.VisualStudio.Themes/tools/VisualAuditFixture/VisualAuditFixture.csproj -c Release
```

## Generation and assets

Edit the shared [authoring inputs](AUTHORING.md). The six public `.vstheme` files
are checked in. The seven deferred themes are generated, validated alongside
them, and included in `all-dev`.

```powershell
./Chxos.VisualStudio.Themes/tools/Generate-Themes.ps1 -MissingDeferred
./Chxos.VisualStudio.Themes/tools/Generate-Themes.ps1 -Check
./Chxos.VisualStudio.Themes/tools/Generate-ThemePackages.ps1 -Check
./Chxos.VisualStudio.Themes/tools/Test-ThemeContrast.ps1
```

`-MissingDeferred` creates only missing deferred files. After authoring changes,
run the relevant generator without `-Check` and commit updated public themes,
properties, and manifests with their inputs.

VSIX builds use checked-in PNGs from
`Chxos.VisualStudio.Themes/assets/packages/<key>/`. To regenerate them from the
SVGs, use Windows with Segoe UI, Node.js >=20.9.0, npm >=10, and locked sharp:

```powershell
npm --prefix ./Chxos.VisualStudio.Themes ci --include=dev --include=optional
npm --prefix ./Chxos.VisualStudio.Themes run assets:check
# After editing SVGs, render and visually review the PNGs:
npm --prefix ./Chxos.VisualStudio.Themes run assets:render
```

## Runtime testing

Use a fresh, dedicated experimental profile and compare installed payload hashes
with the inspected archive. Keep `all-dev` separate from public products because
their theme registrations overlap. Never reset a normal IDE profile.

These tools are in `Chxos.VisualStudio.Themes/tools/`. Specify `-Package` for a
public product; inspection and readiness tools default to `all-dev`.

| Tool | Arguments and purpose |
| --- | --- |
| `Test-VsixPackage.ps1` | `-Package <key> -VsixPath <archive>` checks metadata, included themes, assets, eligibility, and payload |
| `Test-VsixEligibility.Tests.ps1` | `-Package <key> -VsixPath <archive>` tests compatibility boundaries |
| `Invoke-ThemeVisualAudit.ps1` | `-Package <key> -VsixPath <archive> -RootSuffix <fresh-suffix>` opens the demonstration fixture; add `-ThemeName All` for every theme in the package |
| `Invoke-PackageLifecycle.ps1` | `-Action <action> -StatePath <new-state.json>` tracks Initialize, Install, Inspect, Refresh, Upgrade, and Uninstall in an isolated profile |
| `New-PackageUpgradeFixture.ps1` | `-Package <key> -OutputDirectory <new-directory>` creates a next-patch fixture for upgrade tests; do not distribute it |
| `Test-ReleaseReadiness.ps1` | `-Package <key> -VsixPath <archive> -EnvironmentPath <environment.json> -EvidencePath <scenarios.json> -OutputPath <report.json>` checks runtime evidence for that archive |

For lifecycle tests, run `Initialize` with a new state file, then reuse that file
for later actions. Install needs `-Package` and `-VsixPath`; upgrade needs
`-Package` and `-UpgradeFixturePath`. Uninstall needs `-Package`.

[RuntimeScenarios.json](../Chxos.VisualStudio.Themes/tools/RuntimeScenarios.json)
defines the required coverage. Record archive and payload hashes, environment,
theme and state, reviewer and date, and hashed captures. Leave incomplete checks
pending. Older captures or passing source checks cannot verify a different archive.

## Release qualification

No product is ready for a public release yet. Before publishing:

- Pass shared validation and hosted CI, build Release with locked dependencies,
  and inspect the archive to be released.
- Complete the applicable lifecycle, runtime, and rendering-consumer checks.
- Review metadata, compatibility, publisher details, URLs, version, screenshots,
  checksums, and release notes.

Readiness checks cover runtime and consumer evidence; the other release checks
are still required.

CI checks all four packages and uploads only the three public products as
unqualified candidates. Each contains `<key>.vsix`, `candidate.json`, and
`SHA256SUMS.txt`; failed validation or staging prevents uploads. Actions artifacts
follow repository access, so a public repository's artifacts are not private
tester distribution. Downloads exclude `all-dev`, upgrade fixtures, and private
evidence.

## Prepare an individual product release

Three manual Actions workflows use [release-product.yml](../.github/workflows/release-product.yml)
at the same revision:

| Workflow | Package key | Matching tag |
| --- | --- | --- |
| Prepare Foundation release | `foundation` | `foundation/v<version>` |
| Prepare Pinknoise release | `pinknoise` | `pinknoise/v<version>` |
| Prepare Cosmora pack release | `cosmora` | `cosmora/v<version>` |

After pushing the workflows to the default branch, select the product in
**Actions > Run workflow**, choose the branch or ref, and enter its exact catalog
version. The input confirms the version without changing it. For a new version,
update that product's catalog entry and regenerate package metadata first.
Existing tags must match the product and version; workflows do not create tags.

Each workflow validates the product, version, ref, and public dependencies,
builds and inspects that product, and checks eligibility and artifact contents.
The three-file artifact is named `<package>-<version>-unqualified-candidate`, kept
for 14 days, and summarized with its commit and archive hash.

Full CI and release qualification are separate. These workflows have read-only
permissions, no publishing credentials, and do not publish to Marketplace or
GitHub Releases. They have not yet been tested on GitHub.

To stage locally, use a successful build report and a new output directory:

```powershell
$candidate = Join-Path $PWD 'artifacts/foundation-candidate'
./Chxos.VisualStudio.Themes/tools/Stage-PublicArtifacts.ps1 -Package foundation -BuildReportPath '<run>/build.json' -OutputDirectory $candidate
./Chxos.VisualStudio.Themes/tools/Stage-PublicArtifacts.ps1 -Package foundation -Check -OutputDirectory $candidate
```

The parent directory must exist. With `-Package`, the report must contain exactly
the selected public products. Omit it to stage all three, as CI does. Staging
copies the archives unchanged; release qualification is still required.

## Adding a product

To promote a deferred theme, give it a unique public identity and assets, remove
it from `DeferredPublicThemes` and the generated-source ignore list, and
regenerate. Update the public-artifact allowlist, CI package selections and
uploads, regression fixtures, issue options, and documentation. Each theme must
belong to one public product or remain deferred; internal collections may overlap.
Run source, package, clean-build, isolation, eligibility, and lifecycle checks.

## Troubleshooting

If `Microsoft.VsSDK.targets` is missing, restore locked dependencies for the
package and configuration you are building. For validation failures, inspect the
reported policy and component before changing values or exemptions. If Windows
PowerShell child processes cannot load standard modules, check whether they
inherited PowerShell Core's `PSModulePath`.
