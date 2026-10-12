# Chxos Visual Studio Themes

Three dark theme products for Visual Studio 2026:

| Product | Themes | Colors |
| --- | --- | --- |
| Foundation Theme | Foundation | Charcoal with blue accents |
| Pinknoise Theme | Pinknoise | Plum with pink actions and cyan focus cues |
| Cosmora Theme Pack | Cosmora, Cosmora Blueshift, Cosmora Redshift, Cosmora Ultraviolet | Purple, blue, ember, and ultraviolet palettes |

The current `1.0.0` builds are for testing. There are no public downloads yet,
and runtime testing is still in progress.

## Compatibility

The packages target Visual Studio 2026 (18.x), Community, Professional, and
Enterprise. Testing has focused on AMD64. The manifests allow ARM64, but it has
not been verified in use. Visual Studio 2022, earlier versions, and Visual Studio
Code are not supported.

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
- [Editing themes](docs/AUTHORING.md)

Licensed under the [MIT License](LICENSE.txt).
