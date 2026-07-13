// Thin IOKit helpers. Adapted from section9-lab/AppleSPUAccelerometer (MIT).

import Foundation
import IOKit
import IOKit.hid

func ioRegistryPropInt(_ service: io_service_t, key: String) -> Int? {
    guard let ref = IORegistryEntryCreateCFProperty(
        service, key as CFString, kCFAllocatorDefault, 0
    )?.takeRetainedValue() else {
        return nil
    }
    guard CFGetTypeID(ref) == CFNumberGetTypeID() else { return nil }
    var val: Int = 0
    guard CFNumberGetValue((ref as! CFNumber), .intType, &val) else {
        return nil
    }
    return val
}

@discardableResult
func ioRegistrySetInt32(_ service: io_service_t, key: String, value: Int32) -> Bool {
    var v = value
    guard let cfNum = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &v) else {
        return false
    }
    return IORegistryEntrySetCFProperty(service, key as CFString, cfNum) == KERN_SUCCESS
}

func withMatchingServices(_ className: String, body: (io_service_t) throws -> Void) throws {
    guard let matching = IOServiceMatching(className) else {
        throw SPUError.matchingFailed(className)
    }

    var iterator: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    guard kr == KERN_SUCCESS else {
        throw SPUError.serviceEnumeration(className, kr)
    }
    defer { IOObjectRelease(iterator) }

    var service = IOIteratorNext(iterator)
    while service != IO_OBJECT_NULL {
        defer {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        try body(service)
    }
}
