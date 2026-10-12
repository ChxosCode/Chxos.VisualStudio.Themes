# Contributing

Start with an issue describing the theme, affected part of the IDE, and proposed change.

1. Follow the [development setup](docs/DEVELOPMENT.md).
2. Edit the [authoring inputs](docs/AUTHORING.md), regenerate, and review the diff.
3. Run generation checks and the relevant regression suites. For theme or
   packaging changes, also validate all themes, build the affected packages in
   Release, and inspect their VSIX files.
4. Explain the change and how you checked it, including relevant measurements
   and IDE configurations. Mark unfinished visual checks as pending. Add a
   regression test when it catches a meaningful defect.
5. Update the changelog and instructions for user-visible changes.

Follow the authoring guide's identity, typed-value, and palette rules. Do not add
exemptions just to make validation pass. Review rendering changes in the running IDE.

Commit the required generated sources, dependency locks, fixtures, and validation
records. Leave build outputs, private captures, local notes, and deferred generated
themes out of Git. Use demonstration code in public screenshots.
