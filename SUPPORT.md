# Support

See the [installation steps and supported versions](README.md) first.

## Troubleshooting

**The theme is missing.** Restart Visual Studio, then check **Extensions > Manage
Extensions**. Make sure the product is installed and enabled in the Visual
Studio 2026 instance you are using. Select it under **Tools > Options > All
Settings > Environment > Visual Experience > Color theme**. If installation
failed, include the installer's message when reporting the problem. Microsoft's
[extension guide](https://learn.microsoft.com/en-us/visualstudio/ide/finding-and-using-visual-studio-extensions?view=visualstudio)
has more help.

**Editor colors do not match the rest of the IDE.** Set **Editor Appearance** to
**Match Theme** in Visual Experience settings. Fonts and Colors customizations,
per-theme overrides, and other extensions can also change colors. Save any
custom settings before resetting them. See Microsoft's
[theme settings guide](https://learn.microsoft.com/en-us/visualstudio/ide/visual-studio-color-themes?view=visualstudio).

## Report a problem

Use the **Theme rendering problem** issue form. Include:

- Theme and product version.
- Full Visual Studio version and edition.
- Affected window or editor language, steps to reproduce, and what you expected.
- A cropped screenshot with demonstration code. Remove private code, paths,
  account details, and secrets.

For scaling or extension-related problems, include display and text scaling,
architecture, Windows version, Editor Appearance, and relevant extensions.
For source builds, include the package key and commit.

Testing is still incomplete for some semantic colors and overlapping editor
highlights. ARM64, other display configurations, and Windows High Contrast also
need verification. User overrides and third-party classifications can affect
colors.

For build errors or testing in an isolated IDE profile, see
[development](docs/DEVELOPMENT.md).
