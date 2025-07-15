//
//  WaveView.swift
//  Wavefunction Screensaver
//
//  Created by acemavrick on 6/28/25.
//

import Foundation
import ScreenSaver
import QuartzCore
import MetalKit
import SwiftUI
import IOKit.ps

@MainActor
class WaveView: ScreenSaverView, MTKViewDelegate {
    private var mtkView: MTKView?
    private var waveRenderer: WaveRenderer?

    private var shouldBeAnimating = false
    private var isOnBatteryPower = false
    
    private var settingsWindow: NSWindow?

    let store = Store.shared

    private func cleanUp() {
        // a paused view will not send any more drawing callbacks.
        mtkView?.isPaused = true

        // break the delegate cycle and remove from view hierarchy.
        mtkView?.delegate = nil
        mtkView?.removeFromSuperview()
        mtkView = nil

        waveRenderer?.cleanUp()
        waveRenderer = nil
    }

    override var hasConfigureSheet: Bool {
        return true
    }

    override var configureSheet: NSWindow? {
        if settingsWindow == nil {
            let settingsView = SettingsView(
                initialC: store.c,
                initialDx: store.dx,
                initialDt: store.dt,
                initialDamper: store.damper,
                initialDisturbanceCooldownMin: store.disturbanceCooldownMin,
                initialDisturbanceCooldownMax: store.disturbanceCooldownMax,
                initialDisturbanceDensityMin: store.disturbanceDensityMin,
                initialDisturbanceDensityMax: store.disturbanceDensityMax,
                initialDisturbanceRadiusMin: store.disturbanceRadiusMin,
                initialDisturbanceRadiusMax: store.disturbanceRadiusMax,
                initialDisturbanceStrengthMin: store.disturbanceStrengthMin,
                initialDisturbanceStrengthMax: store.disturbanceStrengthMax,
                onSave: { newC, newDx, newDt, newDamper, newCooldownMin, newCooldownMax, newDensityMin, newDensityMax, newRadiusMin, newRadiusMax, newStrengthMin, newStrengthMax in
                    self.store.c = newC
                    self.store.dx = newDx
                    self.store.dt = newDt
                    self.store.damper = newDamper
                    self.store.disturbanceCooldownMin = newCooldownMin
                    self.store.disturbanceCooldownMax = newCooldownMax
                    self.store.disturbanceDensityMin = newDensityMin
                    self.store.disturbanceDensityMax = newDensityMax
                    self.store.disturbanceRadiusMin = newRadiusMin
                    self.store.disturbanceRadiusMax = newRadiusMax
                    self.store.disturbanceStrengthMin = newStrengthMin
                    self.store.disturbanceStrengthMax = newStrengthMax

                    self.updateSettingsFromStore()
                },
                onDismiss: {
                    if let window = self.settingsWindow {
                        window.endSheet(window)
                    }
                }
            )
            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.setContentSize(hostingController.view.intrinsicContentSize)
            settingsWindow = window
        }
        return settingsWindow
    }

    override init?( frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        
        self.wantsLayer = true
        
        // check battery status
        isOnBatteryPower = checkBatteryPower()
        
        if isPreview {
            self.layer?.backgroundColor = NSColor.systemPink.cgColor
            return
        }
        
        if isOnBatteryPower {
            // use low-power mode with simple background
            self.layer?.backgroundColor = NSColor.systemBlue.cgColor
            return
        }
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            // metal not supported
            self.layer?.backgroundColor = NSColor.systemRed.cgColor
            return nil
        }

        self.waveRenderer = WaveRenderer(device: device)

        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.delegate = self
        mtkView.autoresizingMask = [.width, .height]
        self.addSubview(mtkView)
        self.mtkView = mtkView
        
        if !setupMetal() {
            // cannot setup pipelines
            mtkView.isPaused = true
            mtkView.isHidden = true
            self.layer?.backgroundColor = NSColor.systemYellow.cgColor
        }
    }
    
    @available(*, unavailable)
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        mtkView?.frame = self.bounds
    }
    
    private func setupMetal() -> Bool {
        guard let mtkView = mtkView, let waveRenderer = waveRenderer else { return false }
        return waveRenderer.setup(pixelFormat: mtkView.colorPixelFormat)
    }
    
    override func draw(_ rect: NSRect) {}
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        waveRenderer?.drawableSizeWillChange(size: size)
    }
    
    func draw(in view: MTKView) {
        guard shouldBeAnimating else { return }
        waveRenderer?.draw(in: view)
    }
    
    override func startAnimation() {
        super.startAnimation()
        
        updateSettingsFromStore()
        
        // recheck battery status when starting animation
        let currentBatteryStatus = checkBatteryPower()
        if currentBatteryStatus != isOnBatteryPower {
            isOnBatteryPower = currentBatteryStatus
            
            if isOnBatteryPower {
                // switch to battery mode
                mtkView?.isPaused = true
                mtkView?.isHidden = true
                self.layer?.backgroundColor = NSColor.systemBlue.cgColor
                shouldBeAnimating = false
                return
            } else {
                // switch back to gpu mode if metal was previously initialized
                if mtkView != nil {
                    self.layer?.backgroundColor = nil
                    mtkView?.isHidden = false
                }
            }
        }
        
        guard !isOnBatteryPower else { return }
        
        if mtkView == nil {
            if let device = MTLCreateSystemDefaultDevice() {
                self.waveRenderer = WaveRenderer(device: device)
                let newMtkView = MTKView(frame: self.bounds, device: device)
                newMtkView.delegate = self
                self.addSubview(newMtkView)
                self.mtkView = newMtkView
                if !setupMetal() {
                    newMtkView.isPaused = true
                    newMtkView.isHidden = true
                    self.layer?.backgroundColor = NSColor.systemYellow.cgColor
                    shouldBeAnimating = false
                    return
                }
            }
        }
        
        shouldBeAnimating = true
        mtkView?.isPaused = false
    }
    
    override func stopAnimation() {
        super.stopAnimation()
        shouldBeAnimating = false
        mtkView?.isPaused = true
        mtkView?.isHidden = true
        cleanUp()
    }
    
    private func updateSettingsFromStore() {
        waveRenderer?.updateSettings(
            c: store.c,
            dx: store.dx,
            dt: store.dt,
            damper: store.damper,
            disturbanceCooldownRange: store.disturbanceCooldownMin...store.disturbanceCooldownMax,
            disturbanceDensityRange: store.disturbanceDensityMin...store.disturbanceDensityMax,
            disturbanceRadiusRange: store.disturbanceRadiusMin...store.disturbanceRadiusMax,
            disturbanceStrengthRange: store.disturbanceStrengthMin...store.disturbanceStrengthMax
        )
        if let waveRenderer = waveRenderer {
            waveRenderer.animationTimeInterval = self.animationTimeInterval
        }
    }
    
    // battery power checking function
    private func checkBatteryPower() -> Bool {
        let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let powerSourcesList = IOPSCopyPowerSourcesList(powerSourceInfo)?.takeRetainedValue() as? [CFTypeRef]
        
        guard let sources = powerSourcesList else { return false }
        
        for source in sources {
            let sourceInfo = IOPSGetPowerSourceDescription(powerSourceInfo, source)?.takeUnretainedValue()
            guard let info = sourceInfo as? [String: Any] else { continue }
            
            // check if this is the internal battery
            if let type = info[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                // check power source state
                if let powerSource = info[kIOPSPowerSourceStateKey] as? String {
                    return powerSource == kIOPSBatteryPowerValue
                }
            }
        }
        
        return false
    }
}
