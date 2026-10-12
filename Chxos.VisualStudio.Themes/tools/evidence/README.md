# Validation records

These sanitized JSON records are required by the rendering registry and
source-preservation tests. They contain rule IDs, typed-component baselines,
consumer assessments, citations, inspected versions, and hashes. They document
those checks, but do not establish readiness for release.

Source locations and installation observations refer to the recorded review.
Current requirements are in [`RenderingContracts.json`](../RenderingContracts.json),
whose hashes verify these records without private extracts. Keep the original
assessments and unresolved findings when adding evidence from later reviews.

Raw logs, screenshots, implementation extracts, and local audit reports are kept
outside the public repository. Tests in a clean checkout do not need them.
