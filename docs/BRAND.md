# Headroom brand assets

The selected direction is **A — Balanced** from the user's hammock refinement sheet, with the **Light** macOS app-icon treatment. The artwork is a clean vector recreation of that visual reference, not a crop or a pixel-exact extraction. It retains the layered green fabric, two suspension dots and floating central circle. Flat color regions replace the reference's subtle raster shading for reproducible rendering.

## Files

- `Assets/Brand/headroom.svg`: editable color mark, transparent background.
- `Assets/Brand/headroom-monochrome.svg`: simplified silhouette using `currentColor`; internal fabric layers are omitted at small sizes.
- `Assets/Brand/headroom.png`: transparent color mark for contexts without SVG support.
- `Assets/Brand/headroom-app-icon.png`: 1024-pixel Light app-icon preview.
- `scripts/generate-brand.swift`: shared path geometry and native renderer for SVG, PNG and all ten macOS iconset representations (16 through 1024 pixels).

The app build generates `Headroom.icns`, copies it into `Contents/Resources` and declares `CFBundleIconFile` before signing. Finder, system app lists and notifications can use the app identity. The menu-bar status text and Codex terminal symbol retain their existing meanings; the branding does not add a competing status icon. macOS may cache previously displayed icons.

## Regeneration

From the repository root:

```sh
swift scripts/generate-brand.swift /private/tmp/headroom-brand-preview
```

Review the exports before copying the four top-level SVG/PNG files back into `Assets/Brand`. The temporary iconset belongs in build output, not source control. `bash scripts/check.sh` rebuilds and packages the icon automatically with the app. No registry package, image service, fonts or third-party renderer is required.

The asset files and generator are covered by the repository's MIT license. A dark or tinted app-icon variant and a custom wordmark have not been produced; the approved Light version is the shipped icon.
