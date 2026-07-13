// SPU HID driver. Adapted from section9-lab/AppleSPUAccelerometer (MIT).

import Foundation
import IOKit
import IOKit.hid

public typealias RawSampleCallback = (IMUSample) -> Void

public final class SPUDriver: @unchecked Sendable {
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var onSample: RawSampleCallback?
    private var decimationCounter: Int = 0
    private var hidDevice: IOHIDDevice?
    private var unmanagedSelf: Unmanaged<SPUDriver>?
    private var runLoop: CFRunLoop?

    public init() {}

    deinit {
        reportBuffer?.deallocate()
    }

    /// Start the sensor. Blocks the calling thread on a CFRunLoop.
    public func start(callback: @escaping RawSampleCallback) throws {
        self.onSample = callback
        try wakeSPUDrivers()
        try registerAccelerometer()
        runLoop = CFRunLoopGetCurrent()
        CFRunLoopRun()
    }

    public func stop() {
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        unmanagedSelf?.release()
        unmanagedSelf = nil
    }

    private func wakeSPUDrivers() throws {
        try withMatchingServices("AppleSPUHIDDriver") { service in
            ioRegistrySetInt32(service, key: "SensorPropertyReportingState", value: 1)
            ioRegistrySetInt32(service, key: "SensorPropertyPowerState", value: 1)
            ioRegistrySetInt32(service, key: "ReportInterval", value: kReportIntervalUS)
        }
    }

    private func registerAccelerometer() throws {
        var found = false

        try withMatchingServices("AppleSPUHIDDevice") { service in
            guard !found else { return }

            let usagePage = ioRegistryPropInt(service, key: "PrimaryUsagePage") ?? 0
            let usage = ioRegistryPropInt(service, key: "PrimaryUsage") ?? 0
            guard usagePage == kPageVendor && usage == kUsageAccel else { return }

            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { return }

            let kr = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard kr == kIOReturnSuccess else {
                throw SPUError.deviceOpenFailed(kr)
            }

            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: kReportBufSize)
            buf.initialize(repeating: 0, count: kReportBufSize)
            self.reportBuffer = buf
            self.hidDevice = device

            self.unmanagedSelf = Unmanaged.passRetained(self)
            let ctx = self.unmanagedSelf!.toOpaque()

            IOHIDDeviceRegisterInputReportCallback(
                device,
                buf,
                kReportBufSize,
                SPUDriver.hidReportCallback,
                ctx
            )

            IOHIDDeviceScheduleWithRunLoop(
                device,
                CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue
            )

            found = true
        }

        if !found {
            throw SPUError.noAccelerometerFound
        }
    }

    private static let hidReportCallback: IOHIDReportCallback = {
        context, _, _, _, _, report, reportLength in

        guard let context else { return }
        let driver = Unmanaged<SPUDriver>.fromOpaque(context).takeUnretainedValue()
        guard reportLength == kIMUReportLen else { return }

        driver.decimationCounter += 1
        if driver.decimationCounter < kIMUDecimation { return }
        driver.decimationCounter = 0

        guard let sample = parseIMUReport(report, length: Int(reportLength)) else { return }
        driver.onSample?(sample)
    }
}
