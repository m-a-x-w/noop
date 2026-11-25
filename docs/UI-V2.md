# NOOP v2 UI rework — conventions for implementation agents

Master spec: this rework is version **10.0.0**, a full iPhone UI redesign. Sleek premium dark-minimal:
near-black surfaces, big mono numerals, hairline dividers, restrained per-domain accents. **Dark-only.**
Data layer is **untouched** — you read the existing stores/engines; you never modify them.

## Where code goes (the anti-collision rule)

- **New v2 tokens/components** → `Packages/StrandDesign/Sources/StrandDesign/V2/` (a new namespaced folder
  in the existing package target — additive, no `Package.swift` product churn).
- **New v2 screens/shell** → `StrandiOS/UI/` (compiled into the `NOOPiOS` target ONLY, because the whole
  `StrandiOS/` tree is iOS-only). This means **zero `#if os(...)` branches** are needed in v2 screens.
- **Your packet owns a disjoint directory.** Create your files there. Do **NOT** edit files outside your
  packet's scope. In particular do NOT touch these shared files unless your packet explicitly says so:
  `Strand/Screens/*`, `StrandiOS/App/StrandiOSApp.swift`, `StrandiOS/App/RootTabView.swift`, `project.yml`,
  any generated `Info.plist`. Version keys live only in `project.yml` (never hand-edit generated plists).

## Hard constraints

- **v1 tokens are frozen.** Never modify `StrandPalette`, `StrandCard`, `NoopMotion`, `Typography.swift`,
  etc. — macOS, the watch app, and the widget extension all consume them. v2 is purely additive until the
  cleanup phase (E2/E3) deletes orphans.
- **Package code is multi-platform.** `StrandDesign` builds for macOS 13 / iOS 16 / watchOS 10. Anything in
  `StrandDesign/V2/` must compile on all three — gate iOS-17-only API (`chartXSelection`, `.contentTransition`
  variants, etc.) behind `@available(iOS 17, *)` with a graceful fallback, or keep it iOS-16-safe.
- **Font:** 0xProto Nerd Font Mono is the house face (mono for data/labels/titles). SF Pro (`Font.system`)
  is used only for long prose (coach chat, help/terms, insight paragraphs). Never use Nerd Font PUA glyphs
  for UI icons — SF Symbols only.

## Shell selection during migration

`StrandiOS/App/StrandiOSApp.swift` picks the shell: `useV2Shell ? V2RootView() : RootTabView()`.
`useV2Shell` reads `@AppStorage("noop.uiV2Enabled")` (default **false**), overridden in DEBUG by the
`--ui-v2` / `--ui-v1` launch arguments. So every commit ships v1 by default; you verify v2 with `--ui-v2`.

## Per-packet verification (Definition of Done)

Run from the worktree root (`/Users/max/Documents/Projects/noop-ui-v2`):

```sh
# only if you changed project.yml (integration packets only):
xcodegen generate
# build the iPhone app:
xcodebuild -project Strand.xcodeproj -scheme NOOPiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

A packet is done when: the `NOOPiOS` scheme **builds clean**, the v1 shell is unchanged with the flag off,
and (for a visible surface) a simulator screenshot of the new surface is captured:

```sh
xcrun simctl launch booted com.noopapp.noop --ui-v2 --demo-seed
xcrun simctl io booted screenshot <packet-id>.png   # into the scratchpad
```

At **wave boundaries** additionally build `-scheme Strand` (macOS) and `-scheme NOOPWatch`, and run
`-scheme Strand test`, to prove shared code and the other targets still compile.

## Adding new source files

xcodegen globs the target source directories, so a new file under `StrandiOS/UI/` or
`StrandDesign/V2/` is picked up automatically — but you must run `xcodegen generate` once so
`Strand.xcodeproj` references it before `xcodebuild`. (This regenerates the tracked `project.pbxproj`; it's
expected churn on this branch.)
