# Marketplace listing drafts

These are local drafts for three separate Visual Studio Marketplace listings.
All three packages are prepared as `1.0.1` previews; runtime acceptance is still
pending. No repository workflow publishes them.

| Listing | Suggested internal name | VSIX ID | Overview |
| --- | --- | --- | --- |
| Foundation Theme | `foundation` | `Chxos.Foundation.VisualStudio.Theme` | [Foundation](foundation.md) |
| Pinknoise Theme | `pinknoise` | `Chxos.Pinknoise.VisualStudio.Theme` | [Pinknoise](pinknoise.md) |
| Cosmora Theme Pack | `cosmora` | `Chxos.Cosmora.VisualStudio.ThemePack` | [Cosmora](cosmora.md) |

The internal names above are suggestions for the listing URLs, separate from
the existing VSIX IDs. Confirm the Marketplace publisher ID in the dashboard;
the VSIX author is `ChxosCode`, matching the publisher display name. The
publisher ID is a separate account identifier.

## Listing fields

Use the name, description, version, tags, icon, and preview image from each VSIX.
The catalog is their source of truth. Set:

- Pricing: **Free**.
- Type: **Tools**; choose the closest theme or IDE category available in the dashboard.
- Compatibility: **Visual Studio 2026**, Community, Professional, and Enterprise.
- The stable API target is **17.14 and later**. Visual Studio 2022 17.14 is also
  eligible for installation but has not been tested; retain that note in the overview.
- Repository: <https://github.com/ChxosCode/Chxos.VisualStudio.Themes>.
- Support: <https://github.com/ChxosCode/Chxos.VisualStudio.Themes/issues>.
- Release notes: <https://github.com/ChxosCode/Chxos.VisualStudio.Themes/blob/main/CHANGELOG.md>.

Paste the corresponding overview into each listing. The PNGs at
`Chxos.VisualStudio.Themes/assets/packages/<key>/icon.png` and `preview.png` are
the packaged assets. Overviews use actual IDE captures from `1.0.1` in Visual
Studio Community 2026 (`18.10.12201.205`). The six images are in
[`docs/screenshots`](../docs/screenshots/); the Cosmora overview shows all four
variants. Push these files before using their raw GitHub URLs in Marketplace.

## Prepare and review

1. Build Release packages and confirm `build.json` reports `Succeeded: true`.
2. Stage the three public candidates using `Stage-PublicArtifacts.ps1`, then run
   its `-Check` mode. Upload only each product's `.vsix`, not the artifact ZIP,
   checksum file, or `candidate.json`. Never upload `all-dev`.
3. Complete install, theme selection, update from `1.0.0`, and uninstall checks
   against the exact archives. Review remaining runtime coverage described in
   [development](../docs/DEVELOPMENT.md#release-qualification).
4. Review the overview, screenshots, publisher profile, compatibility, version,
   Preview badge, and checksum for each product.

When publication is authorized, use **New extension > Visual Studio** under the
chosen publisher in the [Marketplace dashboard](https://marketplace.visualstudio.com/manage).
**Save & Upload** saves a draft; **Make Public** publishes it. No repository
workflow performs either action. See Microsoft's
[publishing walkthrough](https://learn.microsoft.com/en-us/visualstudio/extensibility/walkthrough-publishing-a-visual-studio-extension?view=visualstudio).

The [Preview badge](https://devblogs.microsoft.com/visualstudio/new-preview-label-for-visual-studio-extensions-2/)
does not create a separate update channel. Future previews and stable versions
use the same listings and VSIX IDs, with increasing numeric versions.
