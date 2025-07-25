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

// A struct to match the layout of our uniforms in the Metal shader.
struct WaveUniforms {
    var dx: Float = 0.0 // not customizeable from here
    var dt: Float = 0.0 // not customizeable from here
    var c: Float = 0.0 // not customizeable from here
    var time: Float = 0.0 
    var damper: Float = 0.0 // not customizeable from here
    var padding0: Float = 0.0 // for alignment
    var resolution: SIMD2<Float> = .zero
    var c0, c1, c2, c3, c4, c5, c6: SIMD4<Float>
}

// A struct for passing disturbance data to the shader.
struct DisturbanceUniforms {
    var position: SIMD2<Float> = .zero
    var radius: Float = 20.0
    var strength: Float = 5.0
}

@MainActor
class WaveView: ScreenSaverView, MTKViewDelegate {
    private var mtkView: MTKView?
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    
    // Pipelines
    private var renderPipelineState: MTLRenderPipelineState!
    private var computePipelineState: MTLComputePipelineState!
    private var copyPipelineState: MTLComputePipelineState!
    private var addDisturbancePipelineState: MTLComputePipelineState!
    
    // Buffers
    private var waveBufferP: MTLBuffer! // previous state
    private var waveBufferC: MTLBuffer! // current state
    private var waveBufferN: MTLBuffer! // next state
    
    private var uniforms = WaveUniforms(c0: .zero, c1: .zero, c2: .zero, c3: .zero, c4: .zero, c5: .zero, c6: .zero)
    
    // Disturbance properties
    // exposed
    private var disturbanceCooldownRange: ClosedRange<Int> = 0...0
    private var disturbanceDensityRange: ClosedRange<Int> = 0...0
    private var disturbanceRadiusRange: ClosedRange<Float> = 0...0
    private var disturbanceStrengthRange: ClosedRange<Float> = 0...0

    // internal
    private var frameCounter: Int = 0
    private var disturbanceCooldown: Int = 0
    private var disturbanceDensity: Int = 1

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

        // explicitly release all metal objects.
        renderPipelineState = nil
        computePipelineState = nil
        copyPipelineState = nil
        addDisturbancePipelineState = nil
        
        waveBufferP = nil
        waveBufferC = nil
        waveBufferN = nil
        
        commandQueue = nil
        
        exit(0)
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
        self.device = device

        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.delegate = self
        mtkView.autoresizingMask = [.width, .height]
        self.addSubview(mtkView)
        self.mtkView = mtkView
        
        if !setupPipelines() {
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
    
    private func setupPipelines() -> Bool {
        guard let mtkView = mtkView else { return false }
        commandQueue = device.makeCommandQueue()

        let library: MTLLibrary
        do {
            let bundle = Bundle(for: WaveView.self)
            guard let defaultMetalLibraryUrl = bundle.url(forResource: "default", withExtension: "metallib") else {
                print("Could not find default.metallib in the bundle. Make sure Shaders.metal is added to the target.")
                return false
            }
            library = try device.makeLibrary(URL: defaultMetalLibraryUrl)
        } catch {
            print("Could not load Metal library: \(error)")
            return false
        }

        // Create render pipeline
        do {
            guard let vertexFunction = library.makeFunction(name: "waveVertex") else {
                print("Could not find vertex function.")
                return false
            }
            guard let fragmentFunction = library.makeFunction(name: "waveFragment") else {
                print("Could not find fragment function.")
                return false
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Could not create render pipeline state: \(error)")
            return false
        }
        
        // Create compute pipelines
        do {
            guard let computeFunction = library.makeFunction(name: "waveCompute") else {
                print("Could not find 'waveCompute' function.")
                return false
            }
            computePipelineState = try device.makeComputePipelineState(function: computeFunction)
        } catch {
            print("Could not create 'waveCompute' pipeline state: \(error)")
            return false
        }
        
        do {
            guard let copyFunction = library.makeFunction(name: "waveCopy") else {
                print("Could not find 'waveCopy' function.")
                return false
            }
            copyPipelineState = try device.makeComputePipelineState(function: copyFunction)
        } catch {
            print("Could not create 'waveCopy' pipeline state: \(error)")
            return false
        }
        
        do {
            guard let disturbanceFunction = library.makeFunction(name: "addDisturbance") else {
                print("Could not find 'addDisturbance' function.")
                return false
            }
            addDisturbancePipelineState = try device.makeComputePipelineState(function: disturbanceFunction)
        } catch {
            print("Could not create 'addDisturbance' pipeline state: \(error)")
            return false
        }
        
        return true
    }
    
    override func draw(_ rect: NSRect) {}
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let width = Int(size.width)
        let height = Int(size.height)
        let bufferSize = width * height * MemoryLayout<SIMD2<Float>>.stride
        
        if bufferSize > 0 {
            let options: MTLResourceOptions = .storageModePrivate
            waveBufferP = device.makeBuffer(length: bufferSize, options: options)
            waveBufferC = device.makeBuffer(length: bufferSize, options: options)
            waveBufferN = device.makeBuffer(length: bufferSize, options: options)
            
            // Create an initial state on the CPU
            let initialData = [SIMD2<Float>](repeating: SIMD2<Float>(0.0, 1.0), count: width * height)
            
            // Create a temporary shared buffer to copy the initial data to the GPU.
            let initialDataSize = initialData.count * MemoryLayout<SIMD2<Float>>.stride
            let initialBuffer = device.makeBuffer(bytes: initialData, length: initialDataSize, options: .storageModeShared)

            // Copy the initial state to all three GPU buffers.
            guard let commandBuffer = commandQueue.makeCommandBuffer(), let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
            blitEncoder.copy(from: initialBuffer!, sourceOffset: 0, to: waveBufferP, destinationOffset: 0, size: initialDataSize)
            blitEncoder.copy(from: initialBuffer!, sourceOffset: 0, to: waveBufferC, destinationOffset: 0, size: initialDataSize)
            blitEncoder.copy(from: initialBuffer!, sourceOffset: 0, to: waveBufferN, destinationOffset: 0, size: initialDataSize)
            blitEncoder.endEncoding()
            commandBuffer.commit()
            
            uniforms.resolution = SIMD2<Float>(Float(width), Float(height))
        }
    }
    
    func draw(in view: MTKView) {
        autoreleasepool {
            guard shouldBeAnimating else { return }

            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                    cleanUp()
                return
            }
            
            uniforms.time += 1.0 / Float(self.animationTimeInterval == 0 ? 60 : (1/self.animationTimeInterval))

            // Compute passes
            if let computePass = commandBuffer.makeComputeCommandEncoder() {
                let w = computePipelineState.threadExecutionWidth
                let h = computePipelineState.maxTotalThreadsPerThreadgroup / w
                let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
                let threadsPerGrid = MTLSize(width: Int(view.drawableSize.width), height: Int(view.drawableSize.height), depth: 1)
                
                // Add disturbances
                frameCounter += 1
                if frameCounter >= disturbanceCooldown {
                    frameCounter = 0
                    
                    computePass.setComputePipelineState(addDisturbancePipelineState)
                    computePass.setBuffer(waveBufferC, offset: 0, index: 0)
                    computePass.setBytes(&uniforms, length: MemoryLayout<WaveUniforms>.stride, index: 2)

                    for _ in 0..<disturbanceDensity {
                        var disturbance = DisturbanceUniforms(
                            position: SIMD2<Float>(
                                Float.random(in: 0..<Float(view.drawableSize.width)),
                                Float.random(in: 0..<Float(view.drawableSize.height))
                            ),
                            radius: Float.random(in: disturbanceRadiusRange),
                            strength: Float.random(in: disturbanceStrengthRange)
                        )
                        computePass.setBytes(&disturbance, length: MemoryLayout<DisturbanceUniforms>.stride, index: 1)
                        computePass.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                    }

                    // decide next cooldown & density
                    disturbanceCooldown = Int.random(in: disturbanceCooldownRange)
                    disturbanceDensity = Int.random(in: disturbanceDensityRange)
                }

                // Wave simulation
                computePass.setComputePipelineState(computePipelineState)
                computePass.setBuffer(waveBufferP, offset: 0, index: 0)
                computePass.setBuffer(waveBufferC, offset: 0, index: 1)
                computePass.setBuffer(waveBufferN, offset: 0, index: 2)
                computePass.setBytes(&uniforms, length: MemoryLayout<WaveUniforms>.stride, index: 3)
                computePass.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                
                // Copy wave buffers for next frame
                computePass.setComputePipelineState(copyPipelineState)
                // Buffers are already set from previous kernel
                computePass.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                
                computePass.endEncoding()
            }

            // Render pass
            if let renderPass = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderPass.setRenderPipelineState(renderPipelineState)
                renderPass.setFragmentBytes(&uniforms, length: MemoryLayout<WaveUniforms>.stride, index: 0)
                renderPass.setFragmentBuffer(waveBufferC, offset: 0, index: 1) // Render the current wave state
                renderPass.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                renderPass.endEncoding()
            }

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
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
        uniforms.c = store.c
        uniforms.dx = store.dx
        uniforms.dt = store.dt
        uniforms.damper = store.damper

        disturbanceCooldownRange = store.disturbanceCooldownMin...store.disturbanceCooldownMax
        disturbanceDensityRange = store.disturbanceDensityMin...store.disturbanceDensityMax
        disturbanceRadiusRange = store.disturbanceRadiusMin...store.disturbanceRadiusMax
        disturbanceStrengthRange = store.disturbanceStrengthMin...store.disturbanceStrengthMax
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
