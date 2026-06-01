import Foundation
import AppKit
import Carbon.HIToolbox

/// Global hotkey registration via Carbon's `RegisterEventHotKey` — the only
/// macOS API that filters at the kernel level for a specific accelerator,
/// without us monitoring every key event (which would trigger Input Monitoring
/// permission prompts).
///
/// Single shared instance; `set(combo:)` is reentrant — calling again with a new
/// combo unregisters the old one.
///
/// Combo string parsing uses Electron's "Accelerator" syntax for compatibility
/// with the existing `config.hotkey.palette` value:
///   "CommandOrControl+Shift+Space" → ⌘⇧Space (or ⌃⇧Space; we treat
///     CommandOrControl as Command on macOS, matching Electron's behavior).
@MainActor
final class HotKey {
    static let shared = HotKey()

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onFire: (() -> Void)?
    /// Sentinel signature: 4-char OSType 'NEXU'. Used to identify our hotkey
    /// in the global Carbon dispatch.
    private static let signature: OSType = 0x4E455855

    private init() {}

    /// Install or replace the global accelerator. `nil` to clear.
    func set(combo: String?, onFire: @escaping () -> Void) {
        clear()
        guard let combo = combo,
              let parsed = KeyCombo.parse(combo) else {
            if let combo {
                Log.palette.warn("Could not parse hotkey '\(combo)'")
            }
            return
        }
        self.onFire = onFire
        installEventHandler()

        var hkRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(parsed.keyCode),
            UInt32(parsed.carbonModifiers),
            id,
            GetApplicationEventTarget(),
            0,
            &hkRef
        )
        guard status == noErr, let hkRef else {
            Log.palette.warn("Hotkey registration failed (status=\(status)). Another app may hold \(combo).")
            return
        }
        self.ref = hkRef
        Log.palette.info("Hotkey registered: \(combo)")
    }

    func clear() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        // Note: we leave the event handler installed; it's harmless without
        // a registered hotkey, and it lets `set()` reuse it on next call.
    }

    private func installEventHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard err == noErr, hkID.signature == HotKey.signature else { return noErr }
                let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in me.onFire?() }
                return noErr
            },
            1,
            &spec,
            userData,
            &handler
        )
    }
}

// MARK: - Combo parsing

struct KeyCombo {
    let keyCode: Int            // Carbon kVK_... value
    let carbonModifiers: Int    // OR-ed Carbon modifier mask

    /// Parse Electron-style accelerator string. Tokens split by `+`, case-insensitive.
    /// Recognizes: Cmd / Command / CommandOrControl, Ctrl / Control, Alt / Option,
    /// Shift; plus a single key (letter, digit, named like Space, Tab, F1, Return,
    /// Escape, Up, Down, Left, Right).
    static func parse(_ raw: String) -> KeyCombo? {
        let parts = raw
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, !last.isEmpty else { return nil }

        var mods = 0
        for token in parts.dropLast() {
            switch token.lowercased() {
            case "cmd", "command", "commandorcontrol", "cmdorctrl":
                mods |= cmdKey
            case "ctrl", "control":
                mods |= controlKey
            case "alt", "opt", "option":
                mods |= optionKey
            case "shift":
                mods |= shiftKey
            default:
                return nil
            }
        }

        guard let kc = keyCode(for: last) else { return nil }
        return KeyCombo(keyCode: kc, carbonModifiers: mods)
    }

    private static func keyCode(for name: String) -> Int? {
        let n = name.lowercased()
        // Single-char letters/digits — map via NSString conversion.
        if n.count == 1, let scalar = n.unicodeScalars.first {
            let lookup: [Character: Int] = [
                "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
                "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
                "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
                "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
                "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
                "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
                "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
                "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
                "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
                "8": kVK_ANSI_8, "9": kVK_ANSI_9
            ]
            if let kc = lookup[Character(String(scalar))] {
                return kc
            }
        }
        switch n {
        case "space": return kVK_Space
        case "tab": return kVK_Tab
        case "return", "enter": return kVK_Return
        case "escape", "esc": return kVK_Escape
        case "up": return kVK_UpArrow
        case "down": return kVK_DownArrow
        case "left": return kVK_LeftArrow
        case "right": return kVK_RightArrow
        case "f1": return kVK_F1
        case "f2": return kVK_F2
        case "f3": return kVK_F3
        case "f4": return kVK_F4
        case "f5": return kVK_F5
        case "f6": return kVK_F6
        case "f7": return kVK_F7
        case "f8": return kVK_F8
        case "f9": return kVK_F9
        case "f10": return kVK_F10
        case "f11": return kVK_F11
        case "f12": return kVK_F12
        default: return nil
        }
    }
}
