# Theme authoring

See [development](DEVELOPMENT.md) for build and test commands. Paths below are
relative to `Chxos.VisualStudio.Themes/`.

## Authoring inputs

| File | Controls |
| --- | --- |
| `authoring/ThemeCatalog.json` | Theme names, GUIDs, filenames, and payload names |
| `authoring/Components.json` | Ordered categories, typed components, and theme bindings |
| `authoring/Palettes.json` | Semantic color anchors |
| `authoring/PackageCatalog.json` | Product identities, versions, included themes, and assets |
| `tools/ThemeRolePolicy.psd1` | Semantic bindings, state rules, thresholds, and exceptions |
| `tools/ContextualRelationships.json` | Contextual source checks |
| `tools/EditorSurfacePolicy.json` | Editor surface and texture checks |
| `tools/EditorSelectionPolicy.json` | Selection model and visibility checks |
| `tools/RenderingContracts.json` | Rendering consumers and evidence requirements |
| `tools/ComponentInventory.json` | Retained component classifications |

Policies and tests define the checks. Generated `.vstheme` files, properties,
and manifests must match their inputs.

## Make a change

Identify the theme, category, component, rendering consumer, and state you want
to change. Edit the relevant input, regenerate, and review the diff. Avoid global
RGB replacements: the same color can serve unrelated roles.

Preserve names, GUIDs, component parity, array order, and typed assignments.
`CT_RAW`, `CT_INVALID`, `CT_AUTOMATIC`, `CT_SYSCOLOR`, and `CT_COLORINDEX` have
different meanings; preserve their sentinel and index values too. Raw colors in
the Cosmora variants must map one-to-one in both directions, without splits or
collisions.

Run generation checks, all-theme validation, relevant regression tests, and
package inspection. For rendering changes, test the inspected VSIX in an
isolated IDE profile.

## Rendering rules

- Preserve inherited field, property, and event foregrounds. Resolve inherited
  members and record classifications before calculating contrast.
- Keep editor selection anchors separate from shell selections. The selection
  policy's fixed opacity model applies only to its documented consumer and IDE
  version. Check High Contrast and overlapping highlights separately.
- Keep registered editor RGB fills opaque where required. Preserve debugger
  outlines, automatic disabled resources, gutter indicators, and distinct Find,
  reference, current-line, and diff states.
- Do not infer rendered transparency from authored ARGB. Check the consumer's
  validity branch, underlay, and composition order. A marker foreground may draw
  an outline; a fill or texture is not text.
- Keep neutral control surfaces distinct from action and focus colors. Preserve
  hover, pressed, checked, disabled, and inactive cues in each palette.

`RefinementEnforcement` controls expanded checks separately from public package
membership. Passing source checks or assigning inventory labels does not prove
that a consumer renders correctly. Keep unresolved findings open.

The [validation records](../Chxos.VisualStudio.Themes/tools/evidence/README.md)
are required test inputs. Preserve their IDs, hashes, and original review scope.
Add new evidence with the version and conditions actually tested. Do not rewrite
old assessments or make tests depend on private extracts or captures.

## Add a theme or product

Add a new theme to the ordered authoring data and catalog with a new canonical
GUID. Update the independent inventory assertions, role bindings, tests, and
assets. Preserve Dark inheritance unless the new design changes it.

To promote a deferred theme, follow [adding a product](DEVELOPMENT.md#adding-a-product).
A separately published fork needs distinct theme and package identities,
publisher details, links, and artwork. Keep license notices and complete
generation, validation, package inspection, and runtime testing before release.
