import SwiftUI
import CoreText

// MARK: - NOOP v2 Typography (0xProto Nerd Font Mono)
//
// The v2 house face is **0xProto Nerd Font Mono** — a mono grotesque used for every
// data/label/title role. Long-form prose (coach chat, help/terms, insight paragraphs)
// stays on SF Pro via `prose` / `proseSmall`; never render paragraphs in the mono face.
//
// Two families of API:
//  • Fixed-geometry numerals (`display`, `numeral`) live inside rings/tiles of a known
//    size, so they use `.custom(_:fixedSize:)` — a FROZEN point size that never grows with
//    Dynamic Type and therefore can't overflow its container.
//  • Dynamic-Type roles (`title`…`overline`) use `.custom(_:size:relativeTo:)` so they scale
//    with the user's Larger-Text setting, anchored to a matching system text style.
//
// This lives in `StrandDesign/V2/` (additive) and compiles on macOS 13 / iOS 16 / watchOS 10.
// The fonts ship in `Bundle.module` via the target's `.process("Resources")` rule; call
// `registerFonts()` once per process before any view renders (app + widget entry points).
public enum V2Font {

    // MARK: Family / PostScript constants (single source of truth)

    /// The registered family name (name-table ID 1) — used only for diagnostics; the roles
    /// below select faces by PostScript name for exactness.
    static let family = "0xProto Nerd Font Mono"
    /// PostScript names (name-table ID 6). `Font.custom` accepts either the family or a
    /// PostScript name; we pass PostScript names so the exact face is selected.
    static let psRegular = "0xProtoNFM-Regular"
    static let psBold    = "0xProtoNFM-Bold"
    static let psItalic  = "0xProtoNFM-Italic"

    /// Only Regular + Bold faces exist, so any bold-ish weight maps to the Bold face and any
    /// lighter weight to Regular; the requested `Font.Weight` is then re-applied on top so the
    /// caller's intent is honoured (SwiftUI synthesises intermediate weights when needed).
    private static func face(for weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold, .heavy, .black: return psBold
        default:                               return psRegular
        }
    }

    /// A Dynamic-Type-scaled mono font: fixed base `size`, scaling anchored to `style`.
    private static func scaled(_ size: CGFloat, _ weight: Font.Weight,
                               relativeTo style: Font.TextStyle) -> Font {
        Font.custom(face(for: weight), size: size, relativeTo: style).weight(weight)
    }

    // MARK: Fixed-size numerals (hero / gauge — live in fixed geometry)

    /// The big hero/gauge number. Bold, FROZEN point size (never scales with Dynamic Type),
    /// tabular by construction (mono face) so a changing value never reflows.
    public static func display(_ size: CGFloat = 64) -> Font {
        Font.custom(psBold, fixedSize: size).weight(.bold)
    }

    /// A fixed-size numeral at an arbitrary weight — for tile/gauge numbers inside fixed geometry.
    public static func numeral(_ size: CGFloat, _ w: Font.Weight = .bold) -> Font {
        Font.custom(face(for: w), fixedSize: size).weight(w)
    }

    // MARK: Dynamic-Type-scaled roles

    /// 20 / Bold — screen + section titles. Scales relative to `.title3`.
    public static let title: Font   = scaled(20, .bold,    relativeTo: .title3)
    /// 16 / Bold — card + group headings. Scales relative to `.headline`.
    public static let heading: Font = scaled(16, .bold,    relativeTo: .headline)
    /// 14 / Regular — default body/data text. Scales relative to `.body`.
    public static let body: Font    = scaled(14, .regular, relativeTo: .body)
    /// 12 / Regular — field labels + secondary data. Scales relative to `.subheadline`.
    public static let label: Font   = scaled(12, .regular, relativeTo: .subheadline)
    /// 11 / Regular — captions + footnotes. Scales relative to `.caption`.
    public static let caption: Font = scaled(11, .regular, relativeTo: .caption)
    /// 10 / Bold — overline eyebrows. Callers add `.tracking(overlineTracking)` + `.textCase(.uppercase)`.
    public static let overline: Font = scaled(10, .bold,   relativeTo: .caption2)
    /// Letter-spacing (points) callers apply to `overline` text.
    public static let overlineTracking: CGFloat = 1.5

    // MARK: Long-form prose (SF Pro — NOT the mono face)

    /// Long-form paragraph text (coach chat, help/terms, insight prose). SF Pro, Dynamic-Type.
    public static let prose: Font      = .system(.body)
    /// Smaller long-form prose (secondary paragraphs, disclaimers). SF Pro, Dynamic-Type.
    public static let proseSmall: Font = .system(.subheadline)

    // MARK: Runtime font registration

    /// Register the bundled 0xProto faces with the process's font manager so `Font.custom`
    /// can resolve them. Idempotent: a second call (e.g. the widget process, or a re-entry)
    /// treats the "already registered" error as success rather than failing.
    ///
    /// - Returns: `true` only if every face is present and registered (or already was).
    @discardableResult
    public static func registerFonts() -> Bool {
        // File basenames (differ from the PostScript names above).
        let files = ["0xProtoNerdFontMono-Regular",
                     "0xProtoNerdFontMono-Bold",
                     "0xProtoNerdFontMono-Italic"]
        var allSucceeded = true
        for name in files {
            // The fonts sit under Resources/Fonts; `.process("Resources")` preserves that
            // subdirectory in the bundle. Fall back to a flat lookup for robustness.
            let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf")
            guard let fontURL = url else {
                allSucceeded = false
                continue
            }
            var errorRef: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &errorRef)
            if !ok {
                // Ignore "already registered" so re-entry / a second process is a no-op success.
                if let error = errorRef?.takeRetainedValue(),
                   CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue {
                    continue
                }
                allSucceeded = false
            }
        }
        return allSucceeded
    }

    #if DEBUG
    /// DEBUG-only sanity check: asks CoreText to resolve each expected PostScript face and prints
    /// whether it resolved to the real 0xProto face or silently fell back to a system font.
    /// Call once after `registerFonts()` to confirm the faces landed in the process.
    /// (Uses `CTFontCreateWithName`/`CTFontCopyPostScriptName`, available on the iOS 16 / macOS 13 /
    /// watchOS 10 floor — unlike `CTFontManagerCopyAvailableFontFamilyNames`, which is iOS 18+.)
    public static func _debugDumpFamilies() {
        print("[V2Font] expected family=\(family)")
        for ps in [psRegular, psBold, psItalic] {
            let font = CTFontCreateWithName(ps as CFString, 12, nil)
            let resolved = CTFontCopyPostScriptName(font) as String
            print("[V2Font]   requested \(ps) -> resolved \(resolved) " +
                  (resolved == ps ? "OK" : "MISSING (fell back to system)"))
        }
    }
    #endif
}
