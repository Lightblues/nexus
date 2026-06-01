import Foundation
import IOKit

/// System-wide HID idle time. Equivalent to Electron's
/// `powerMonitor.getSystemIdleTime()`. Reads from the IOHIDSystem registry entry.
enum IdleDetector {
    /// Seconds since last keyboard/mouse/trackpad event.
    /// Returns 0 on read failure (treats failure as "user is active").
    static func systemIdleSeconds() -> TimeInterval {
        var iter: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iter
        )
        guard kr == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iter) }

        let entry = IOIteratorNext(iter)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        let propsErr = IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
        guard propsErr == KERN_SUCCESS, let props = properties?.takeRetainedValue() else { return 0 }

        let dict = props as NSDictionary
        guard let idleNs = dict["HIDIdleTime"] as? NSNumber else { return 0 }
        // HIDIdleTime is nanoseconds.
        return idleNs.doubleValue / 1_000_000_000
    }
}
