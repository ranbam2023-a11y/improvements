//
//  Multitouch.swift — access to Apple's private MultitouchSupport framework.
//
//  We dlopen the framework at runtime (no link-time dependency), register a
//  contact-frame callback on every trackpad, and hand frames to a single
//  handler. No permissions are required: raw trackpad contacts are not a
//  privacy-gated API.
//
//  start()/stop() are paired: stopping turns the devices off and drops the
//  handler, so a disabled augment leaves nothing running behind it.
//

import Foundation
import Darwin

typealias MTDeviceRef     = UnsafeMutableRawPointer
typealias MTFrameCallback = @convention(c) (MTDeviceRef?, UnsafeMutablePointer<MTTouch>?, Int, Double, Int) -> Void
typealias MTRegFn         = @convention(c) (MTDeviceRef, MTFrameCallback) -> Void
typealias MTCreateListFn  = @convention(c) () -> UnsafeMutableRawPointer?
typealias MTStartFn       = @convention(c) (MTDeviceRef, Int32) -> Int32
typealias MTStopFn        = @convention(c) (MTDeviceRef) -> Void

let mtFrameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

/// Single global sink for contact frames (the C callback can't capture context).
var mtHandler: ((UnsafeMutablePointer<MTTouch>?, Int, Double) -> Void)?

let mtFrameCallback: MTFrameCallback = { _, touches, count, timestamp, _ in
    mtHandler?(touches, count, timestamp)
}

/// Owns the dlopen'd framework and the registered devices.
final class Multitouch {
    static let shared = Multitouch()

    private(set) var deviceCount = 0
    private(set) var lastError: String?
    private(set) var isRunning = false

    private var devices: [MTDeviceRef] = []
    private var startFn: MTStartFn?
    private var stopFn: MTStopFn?

    private init() {}

    /// Registers `handler` and starts every trackpad.
    @discardableResult
    func start(handler: @escaping (UnsafeMutablePointer<MTTouch>?, Int, Double) -> Void) -> Bool {
        mtHandler = handler
        if isRunning { return true }

        if devices.isEmpty {
            guard let handle = dlopen(mtFrameworkPath, RTLD_NOW) else {
                lastError = "MultitouchSupport.framework could not be loaded"
                return false
            }
            guard let listSym  = dlsym(handle, "MTDeviceCreateList"),
                  let regSym   = dlsym(handle, "MTRegisterContactFrameCallback"),
                  let startSym = dlsym(handle, "MTDeviceStart") else {
                lastError = "MultitouchSupport symbols are missing"
                return false
            }

            let createList = unsafeBitCast(listSym,  to: MTCreateListFn.self)
            let register   = unsafeBitCast(regSym,   to: MTRegFn.self)
            startFn        = unsafeBitCast(startSym, to: MTStartFn.self)
            if let stopSym = dlsym(handle, "MTDeviceStop") {
                stopFn = unsafeBitCast(stopSym, to: MTStopFn.self)
            }

            guard let listPtr = createList() else {
                lastError = "No multitouch devices reported"
                return false
            }
            let list = Unmanaged<CFArray>.fromOpaque(listPtr).takeRetainedValue()
            let count = CFArrayGetCount(list)
            deviceCount = count

            for i in 0..<count {
                guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
                let device = UnsafeMutableRawPointer(mutating: raw)
                register(device, mtFrameCallback)
                devices.append(device)
            }
            if count == 0 { lastError = "No multitouch devices reported" }
        }

        for device in devices { _ = startFn?(device, 0) }
        isRunning = !devices.isEmpty
        return isRunning
    }

    /// Stops every device and drops the frame handler. Start again with start().
    func stop() {
        guard isRunning else { return }
        for device in devices { stopFn?(device) }
        isRunning = false
        mtHandler = nil
    }
}
