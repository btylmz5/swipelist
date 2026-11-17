# Swipelist app icon — liquid glass set

Variant **3b** geometry (three fanned cards + four-bar waveform on the leading card),
rendered in three appearances. Geometry is identical across all three; only the
material changes.

Installed in this project as:

- `Swipelist/Assets.xcassets/AppIcon.appiconset` — the three 1024² PNGs, wired to
  the light / dark / tinted appearance slots
- `Swipelist/SwipelistAppIconGlass.swift` — the live copy of the SwiftUI view,
  used on the sign-in screen at `size: 84`

`AppIcon-glass-light.svg` shipped with the previous neutral `#FFFFFF → #D6D6DE`
backdrop; its `#bg` gradient was repointed at the pale-lime field below to match
the view. Regenerate the SVGs from the source and this note can go.

## Files

| File | Use |
|---|---|
| `SwipelistAppIconGlass.swift` | Drop-in SwiftUI view, all three appearances (live copy in `Swipelist/`) |
| `AppIcon-glass-dark.svg` | 1024² dark artwork |
| `AppIcon-glass-light.svg` | 1024² light artwork |
| `AppIcon-glass-tinted.svg` | 1024² tinted artwork (lime ramp) |
| `SwipelistAppIcon.swift` | Earlier flat (non-glass) 3b, kept for reference |
| `AppIcon-3b.svg` | Earlier flat 3b artwork |

## SwiftUI

```swift
SwipelistAppIcon(size: 180)                                   // dark, masked
SwipelistAppIcon(size: 180, appearance: .light)
SwipelistAppIcon(size: 180, appearance: .tinted(.lime))       // .indigo .slate .violet
SwipelistAppIcon(size: 1024, appearance: .dark, masked: false) // submission artwork
```

`masked: false` for anything you ship to App Store Connect — the system applies the
superellipse mask and its own shadow. `masked: true` is for in-app and preview use.

## Geometry (fractions of `size`, so 40pt and 1024pt are the same drawing)

- card side `0.47`, corner radius `0.088`, hairline `0.009`
- back card `rotate(-16°)`, offset `(-0.123, 0.033)`
- mid card `rotate(-7°)`, offset `(-0.053, 0.009)`
- leading card `rotate(9°)`, offset `(0.088, -0.026)`
- bars: width `0.047`, radius `0.024`, gap `0.031`, heights `[0.153, 0.27, 0.20, 0.317]`
- icon mask radius `0.2237` (iOS superellipse approximation)

## Palette

- lime `#D4FF3F`; leading-card glass ramp dark `#EAFF95 → #D9FF52 → #C4F02E → #A6D024`,
  light `#F2FFB4 → #DEFF6B → #CDF93C → #B4E024`
- light-mode field `#F4FFD1 → #E9FFAE → #DBF988 → #CBEE63` (pale lime — a tint of the brand color, kept far enough from the leading card to hold separation)
- ink `#0B0B0D`; bar cut dark `#090E02` @82%, light `#101604` @86%
- tint ramps (highlight / mid / shadow): lime `#4E6410 #2C3A08 #161D04`,
  indigo `#3A3F86 #232752 #12142E`, slate `#3A4048 #242A31 #12161B`,
  violet `#4B2C7A #301A52 #180D2A`

## Icon Composer

Prefer building this as layers and letting Apple's renderer apply specular and shadow,
rather than shipping the baked highlights here. Layer order, back to front:

1. backdrop (radial gradient, center `40% 24%`)
2. back card
3. mid card
4. leading card
5. waveform bars

The SVGs are structured in this order and can be split apart directly.
