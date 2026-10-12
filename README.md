# Chxos Visual Studio Themes

Three dark theme products for Visual Studio 2026:

| Product | Themes | Colors |
| --- | --- | --- |
| Foundation Theme | [Foundation](docs/screenshots/foundation.jpg) | Charcoal with blue accents |
| Pinknoise Theme | [Pinknoise](docs/screenshots/pinknoise.jpg) | Plum with pink actions and cyan focus cues |
| Cosmora Theme Pack | [Cosmora](docs/screenshots/cosmora.jpg), [Blueshift](docs/screenshots/cosmora-blueshift.jpg), [Redshift](docs/screenshots/cosmora-redshift.jpg), [Ultraviolet](docs/screenshots/cosmora-ultraviolet.jpg) | Purple, blue, ember, and ultraviolet palettes |

The current `1.0.1` builds are previews for testing. There are no public releases yet,
and runtime testing is still in progress.

Theme links above open IDE screenshots captured from these builds in Visual
Studio Community 2026, with C# and Razor editors set to **Match Theme**.

## Compatibility

The packages target stable API version 17.14 and later, which Visual Studio 2026
supports, across Community, Professional, and Enterprise. Runtime testing has
focused on Visual Studio 2026 on AMD64. Visual Studio 2022 17.14 and ARM64 are
eligible for installation but have not been tested. Earlier Visual Studio
versions and Visual Studio Code are not supported.

## Install and configure

Use the `.vsix` supplied for your chosen product, or
[build it from source](docs/DEVELOPMENT.md#build-and-test).

1. Open the `.vsix` and select your Visual Studio 2026 installation. Close and
   reopen Visual Studio when prompted.
2. Open **Tools > Options > All Settings > Environment > Visual Experience**
   and select the installed theme under **Color theme**.
3. Set **Editor Appearance** to **Match Theme** to use the theme's editor colors.

Microsoft's guides cover [VSIX installation](https://learn.microsoft.com/en-us/visualstudio/ide/finding-and-using-visual-studio-extensions?view=visualstudio#install-extensions-without-using-extension-manager)
and [Visual Experience settings](https://learn.microsoft.com/en-us/visualstudio/ide/configure-visual-experience-options?view=visualstudio).

You can install the products independently. To remove one, select a built-in
theme, uninstall the product through **Extensions > Manage Extensions**, and
restart when prompted.

## Help

- [Troubleshooting and reporting problems](SUPPORT.md)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Building and preparing packages](docs/DEVELOPMENT.md)
- [Marketplace listing drafts](marketplace/README.md)
- [Editing themes](docs/AUTHORING.md)

Licensed under the [MIT License](LICENSE.txt).
