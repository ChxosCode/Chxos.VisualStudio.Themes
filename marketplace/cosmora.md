# Cosmora Theme Pack

Four dark themes for Visual Studio 2026, installed together:

| Theme | Palette |
| --- | --- |
| Cosmora | Purple |
| Cosmora Blueshift | Blue |
| Cosmora Redshift | Ember |
| Cosmora Ultraviolet | Ultraviolet |

Each theme colors the IDE and editor, including selections, diff backgrounds,
and C#/Razor semantic highlights.

![Cosmora in Visual Studio 2026](https://raw.githubusercontent.com/ChxosCode/Chxos.VisualStudio.Themes/main/docs/screenshots/cosmora.jpg)

![Cosmora Blueshift in Visual Studio 2026](https://raw.githubusercontent.com/ChxosCode/Chxos.VisualStudio.Themes/main/docs/screenshots/cosmora-blueshift.jpg)

![Cosmora Redshift in Visual Studio 2026](https://raw.githubusercontent.com/ChxosCode/Chxos.VisualStudio.Themes/main/docs/screenshots/cosmora-redshift.jpg)

![Cosmora Ultraviolet in Visual Studio 2026](https://raw.githubusercontent.com/ChxosCode/Chxos.VisualStudio.Themes/main/docs/screenshots/cosmora-ultraviolet.jpg)

Version `1.0.1` in Visual Studio Community 2026, with C# and Razor editors set to **Match Theme**.

## Install and select

1. Install the extension and restart Visual Studio when prompted. For a manual
   install, open `cosmora-1.0.1.vsix` and select your Visual Studio 2026 instance.
2. Open **Tools > Options > All Settings > Environment > Visual Experience**.
3. Choose any of the four themes under **Color theme** and set **Editor Appearance**
   to **Match Theme**.

## Compatibility and preview status

Version `1.0.1` is a preview for Visual Studio 2026, Community, Professional, and
Enterprise. The installer targets stable API version 17.14 and later, so Visual
Studio 2022 17.14 is also eligible but has not been tested. Earlier Visual Studio
versions and Visual Studio Code are not supported.

Testing has focused on AMD64. ARM64 is allowed by the installer but has not been
verified in use. Runtime review is still incomplete for some semantic colors,
overlapping editor highlights, display configurations, and Windows High
Contrast. Fonts and Colors overrides and other extensions can affect the result.

The extension ID is unchanged from the private `1.0.0` builds. Select a built-in
theme before uninstalling through **Extensions > Manage Extensions**; this removes
all four variants.

## Feedback

[Report a rendering problem](https://github.com/ChxosCode/Chxos.VisualStudio.Themes/issues/new?template=theme-problem.yml)
with the affected variant and extension version, full Visual Studio version,
steps to reproduce, and a screenshot with private code removed.

[Source and installation help](https://github.com/ChxosCode/Chxos.VisualStudio.Themes)
· [Release notes](https://github.com/ChxosCode/Chxos.VisualStudio.Themes/blob/main/CHANGELOG.md)
· Free, under the MIT License.
