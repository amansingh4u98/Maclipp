# Contributing To Maclipp

Thanks for helping improve Maclipp.

## Setup

Maclipp requires macOS 13 or newer and Swift 5.10 or newer. Clone the repository, then run:

```bash
./scripts/run-checks.sh
./scripts/build-app.sh
open dist/Maclipp.app
```

## Development Guidelines

- Keep clipboard data local by default.
- Preserve keyboard-only operation and multi-display behavior.
- Avoid adding dependencies when AppKit, SwiftUI, or the standard library provide a reasonable solution.
- Add or extend checks when changing storage, deduplication, retention, search, image decoding, or shortcut persistence.
- Do not commit `.build/`, `dist/`, local clipboard history, or signing credentials.

## Pull Requests

Before opening a pull request:

1. Run `./scripts/run-checks.sh`.
2. Run `./scripts/build-app.sh`.
3. Verify the generated app with `codesign --verify --deep --strict dist/Maclipp.app`.
4. Test menu-bar clicks, shortcut recording/conflict handling, text capture, image capture, and multi-display placement.
5. Describe user-visible behavior changes and any privacy implications.

Keep pull requests focused. Avoid unrelated refactors or generated-file churn.
