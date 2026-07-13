// IMU parsing and HID constants for Apple Silicon SPU accelerometer.
// Adapted from section9-lab/AppleSPUAccelerometer (MIT).

import Foundation

public let kPageVendor: Int = 0xFF00
public let kUsageAccel: Int = 3
public let kIMUReportLen: Int = 22
public let kIMUDecimation: Int = 8
public let kIMUDataOffset: Int = 6
public let kReportBufSize: Int = 4096
public let kReportIntervalUS: Int32 = 1000
public let kAccelScale: Double = 65536.0

public struct IMUSample: Sendable {
    public let x: Int32
    public let y: Int32
    public let z: Int32

    public var gX: Double { Double(x) / kAccelScale }
    public var gY: Double { Double(y) / kAccelScale }
    public var gZ: Double { Double(z) / kAccelScale }

    public var magnitude: Double {
        (gX * gX + gY * gY + gZ * gZ).squareRoot()
    }
}

public func parseIMUReport(_ report: UnsafePointer<UInt8>, length: Int) -> IMUSample? {
    guard length >= kIMUDataOffset + 12 else { return nil }
    let off = kIMUDataOffset
    let x = readInt32LE(report, offset: off)
    let y = readInt32LE(report, offset: off + 4)
    let z = readInt32LE(report, offset: off + 8)
    return IMUSample(x: x, y: y, z: z)
}

@inline(__always)
func readInt32LE(_ ptr: UnsafePointer<UInt8>, offset: Int) -> Int32 {
    let p = ptr.advanced(by: offset)
    let raw = UInt32(p[0])
        | (UInt32(p[1]) << 8)
        | (UInt32(p[2]) << 16)
        | (UInt32(p[3]) << 24)
    return Int32(bitPattern: raw)
}

public enum SPUError: Error, CustomStringConvertible, Sendable {
    case needsRoot
    case matchingFailed(String)
    case serviceEnumeration(String, kern_return_t)
    case noAccelerometerFound
    case deviceOpenFailed(kern_return_t)

    public var description: String {
        switch self {
        case .needsRoot:
            return "Root privileges required for IOKit HID access. Run with: sudo"
        case .matchingFailed(let name):
            return "IOServiceMatching failed for \(name)"
        case .serviceEnumeration(let name, let kr):
            return "IOServiceGetMatchingServices failed for \(name): kern_return \(kr)"
        case .noAccelerometerFound:
            return "No accelerometer found (requires Apple Silicon MacBook with SPU)"
        case .deviceOpenFailed(let kr):
            return "IOHIDDeviceOpen failed: kern_return \(kr)"
        }
    }
}
