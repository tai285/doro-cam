import AVFoundation
import CoreMedia
import DoroCameraCore
import Foundation

// The only place that talks to AVCaptureDevice. It turns the real device into plain facts for the
// Flutter-free core, applies already-clamped settings, and reads back what the device reports.

extension DeviceFacts {
    init(device: AVCaptureDevice, photoOutput: AVCapturePhotoOutput?) {
        let format = device.activeFormat
        let position: CameraFacing
        switch device.position {
        case .front: position = .front
        case .back: position = .back
        default: position = .external
        }
        var sizes: [PixelSize] = []
        for dimension in format.supportedMaxPhotoDimensions {
            sizes.append(PixelSize(width: Int(dimension.width), height: Int(dimension.height)))
        }
        sizes.sort { $0.width * $0.height > $1.width * $1.height }

        self.init(
            uniqueId: device.uniqueID,
            position: position,
            deviceTypeName: device.deviceType.rawValue,
            isLogical: device.isVirtualDevice,
            constituentIds: device.constituentDevices.map { $0.uniqueID },
            minISO: format.minISO,
            maxISO: format.maxISO,
            minExposureSeconds: format.minExposureDuration.seconds,
            maxExposureSeconds: format.maxExposureDuration.seconds,
            supportsCustomExposure: device.isExposureModeSupported(.custom),
            minExposureTargetBias: device.minExposureTargetBias,
            maxExposureTargetBias: device.maxExposureTargetBias,
            lensAperture: device.lensAperture,
            horizontalFieldOfViewDegrees: format.videoFieldOfView,
            supportsAutoFocus: device.isFocusModeSupported(.autoFocus),
            supportsContinuousFocus: device.isFocusModeSupported(.continuousAutoFocus),
            supportsFocusPointOfInterest: device.isFocusPointOfInterestSupported,
            supportsLockedLensPosition: device.isLockingFocusWithCustomLensPositionSupported,
            minimumFocusDistanceMillimeters: device.minimumFocusDistance > 0 ? device.minimumFocusDistance : nil,
            supportsLockedWhiteBalance: device.isLockingWhiteBalanceWithCustomDeviceGainsSupported,
            maxWhiteBalanceGain: device.maxWhiteBalanceGain,
            minZoom: Double(device.minAvailableVideoZoomFactor),
            maxZoom: Double(device.maxAvailableVideoZoomFactor),
            switchOverZoomFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue },
            hasFlash: device.hasFlash,
            hasTorch: device.hasTorch,
            supportsHDR: format.isVideoHDRSupported,
            supportsHEIF: photoOutput?.availablePhotoCodecTypes.contains(.hevc) ?? true,
            supportsRAW: !(photoOutput?.availableRawPhotoPixelFormatTypes.isEmpty ?? true),
            photoSizes: sizes,
            livePhotoCaptureSupported: photoOutput?.isLivePhotoCaptureSupported ?? false,
            hasMicrophone: AVCaptureDevice.default(for: .audio) != nil
        )
    }
}

enum DeviceDiscovery {
    /// Every camera third-party apps can use, in a stable order (back cameras first).
    static func devices() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
            .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
        ]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
        return discovery.devices.sorted { lhs, rhs in
            if lhs.position != rhs.position { return lhs.position == .back }
            return lhs.uniqueID < rhs.uniqueID
        }
    }

    static func device(id: String) -> AVCaptureDevice? {
        AVCaptureDevice(uniqueID: id)
    }

    static func label(for facts: DeviceFacts) -> String {
        let side = facts.position == .front ? "Front camera" : "Back camera"
        switch CapabilityProbe.lensKind(for: facts) {
        case .ultraWide: return "\(side) (ultra-wide)"
        case .tele: return "\(side) (telephoto)"
        case .wide where facts.isLogical: return side
        case .wide: return "\(side) (wide)"
        default: return side
        }
    }
}

/// Applies settings to one device and reads back what it reports (CAM-050).
final class DeviceController {
    let device: AVCaptureDevice
    let capabilities: CameraCapabilities

    init(device: AVCaptureDevice, capabilities: CameraCapabilities) {
        self.device = device
        self.capabilities = capabilities
    }

    func apply(_ settings: EffectiveSettings) async throws {
        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraError(.cameraInUse, "The camera is being used by another app.")
        }
        defer { device.unlockForConfiguration() }

        // Zoom first: it changes which lens is active and therefore the other ranges.
        let zoom = min(max(settings.zoomFactor, Double(device.minAvailableVideoZoomFactor)), Double(device.maxAvailableVideoZoomFactor))
        device.videoZoomFactor = CGFloat(zoom)

        // Exposure
        if settings.exposureMode == .manual, let iso = settings.iso, let duration = settings.exposureTimeNs {
            let format = device.activeFormat
            let clampedISO = min(max(Float(iso), format.minISO), format.maxISO)
            let clampedDuration = CMTimeClampToRange(
                CMTime(value: duration, timescale: 1_000_000_000),
                range: CMTimeRange(start: format.minExposureDuration, end: format.maxExposureDuration)
            )
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO) { _ in continuation.resume() }
            }
        } else if settings.exposureMode == .manual {
            // Only one of ISO and shutter given: keep the other at its current metered value (docs/specs/camera.md rule 3).
            let format = device.activeFormat
            let iso = settings.iso.map { min(max(Float($0), format.minISO), format.maxISO) } ?? device.iso
            let duration = settings.exposureTimeNs.map {
                CMTimeClampToRange(CMTime(value: $0, timescale: 1_000_000_000), range: CMTimeRange(start: format.minExposureDuration, end: format.maxExposureDuration))
            } ?? device.exposureDuration
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                device.setExposureModeCustom(duration: duration, iso: iso) { _ in continuation.resume() }
            }
        } else {
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if let bias = settings.exposureBiasEV {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    device.setExposureTargetBias(Float(bias)) { _ in continuation.resume() }
                }
            } else {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    device.setExposureTargetBias(0) { _ in continuation.resume() }
                }
            }
            if settings.exposureLocked, device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
        }

        // Focus
        switch settings.focusMode {
        case .continuous:
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        case .auto:
            if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
        case .manual:
            if let diopters = settings.focusDiopters, let manual = capabilities.focus.manual {
                let position = FocusMath.lensPosition(forDiopters: diopters, minFocusDiopters: manual.minFocusDistanceDiopters)
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    device.setFocusModeLocked(lensPosition: Float(position)) { _ in continuation.resume() }
                }
            }
        }
        if settings.focusLocked, settings.focusMode != .manual, device.isFocusModeSupported(.locked) {
            device.focusMode = .locked
        }

        // White balance
        switch settings.whiteBalance {
        case .auto:
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        case .preset(let preset):
            if let kelvin = WhiteBalanceMath.kelvin(for: preset) { await lockWhiteBalance(kelvin: kelvin) }
        case .kelvin(let kelvin):
            await lockWhiteBalance(kelvin: kelvin)
        }

        // Torch
        if device.hasTorch {
            if settings.torch {
                try? device.setTorchModeOn(level: 1.0)
            } else if device.torchMode != .off {
                device.torchMode = .off
            }
        }
    }

    private func lockWhiteBalance(kelvin: Int) async {
        guard device.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }
        let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(kelvin), tint: 0)
        var gains = device.deviceWhiteBalanceGains(for: values)
        let limits = WhiteBalanceMath.clampGains(red: gains.redGain, green: gains.greenGain, blue: gains.blueGain, maxGain: device.maxWhiteBalanceGain)
        gains = AVCaptureDevice.WhiteBalanceGains(redGain: limits.red, greenGain: limits.green, blueGain: limits.blue)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            device.setWhiteBalanceModeLocked(with: gains) { _ in continuation.resume() }
        }
    }

    func focus(at point: CGPoint) throws {
        do { try device.lockForConfiguration() } catch { throw CameraError(.cameraInUse, "The camera is being used by another app.") }
        defer { device.unlockForConfiguration() }
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
        }
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
            device.exposurePointOfInterest = point
            device.exposureMode = .autoExpose
        }
    }

    /// What the device reports right now (the values behind CAM-050).
    func report(zoom: Double, dimensions: (width: Int, height: Int)) -> AppliedReport {
        let gains = device.deviceWhiteBalanceGains
        var kelvin: Int?
        let valid = gains.redGain >= 1 && gains.greenGain >= 1 && gains.blueGain >= 1 && gains.redGain <= device.maxWhiteBalanceGain
            && gains.greenGain <= device.maxWhiteBalanceGain && gains.blueGain <= device.maxWhiteBalanceGain
        if valid {
            kelvin = Int(device.temperatureAndTintValues(for: gains).temperature.rounded())
        }
        var diopters: Double?
        if let manual = capabilities.focus.manual {
            diopters = FocusMath.diopters(forLensPosition: Double(device.lensPosition), minFocusDiopters: manual.minFocusDistanceDiopters)
        }
        return AppliedReport(
            iso: Int(device.iso.rounded()),
            exposureTimeNs: ExposureMath.nanoseconds(fromSeconds: device.exposureDuration.seconds),
            exposureBiasEV: Double(device.exposureTargetBias),
            aperture: Double(device.lensAperture),
            focalLength35mmEq: CapabilityProbe.equivalentFocalLength35mm(horizontalFieldOfViewDegrees: device.activeFormat.videoFieldOfView),
            focusDiopters: diopters,
            whiteBalanceKelvin: kelvin,
            zoomFactor: zoom,
            widthPx: dimensions.width,
            heightPx: dimensions.height
        )
    }

    var isAdjustingExposure: Bool { device.isAdjustingExposure }
    var focusModeIsLocked: Bool { device.focusMode == .locked }
    var exposureModeIsLocked: Bool { device.exposureMode == .locked }
}
