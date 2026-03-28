# Framed

Framed is a macOS menu bar app for quickly resizing visible windows to common aspect ratios.

## v0.0.1

- Lives entirely in the menu bar.
- Lets you choose from `16:9`, `4:3`, and `1:1`.
- Shows a list of visible windows and applies the selected ratio to the chosen window.
- Uses macOS Accessibility APIs, so it needs Accessibility permission in System Settings.

## Development

```bash
xcodebuild -project Framed/Framed.xcodeproj -scheme Framed build
```

## Release

The repository includes a GitHub Actions workflow at `.github/workflows/macos-release.yaml` that archives, signs, notarizes, and uploads a DMG when you push a `v*` tag.
