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

// A struct to match the layout of our uniforms in the Metal shader.
struct WaveUniforms {
    var dx: Float = 1.0
    var dt: Float = 0.5
    var c: Float = 1.0
    var time: Float = 0.0
    var damper: Float = 0.99
    var padding0: Float = 0.0 // for alignment
    var resolution: SIMD2<Float> = .zero
    // for colormap, not used in grey fragment shader
    var c0, c1, c2, c3, c4, c5, c6: SIMD4<Float>
}

class WaveView: ScreenSaverView, MTKViewDelegate {
    private var mtkView: MTKView?
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    
    // Pipelines
    private var renderPipelineState: MTLRenderPipelineState!
    private var computePipelineState: MTLComputePipelineState!
    private var copyPipelineState: MTLComputePipelineState!
    
    // Buffers
    private var waveBufferP: MTLBuffer! // previous state
    private var waveBufferC: MTLBuffer! // current state
    private var waveBufferN: MTLBuffer! // next state
    
    private var uniforms = WaveUniforms(c0: .zero, c1: .zero, c2: .zero, c3: .zero, c4: .zero, c5: .zero, c6: .zero)

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        
        self.wantsLayer = true
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            self.layer?.backgroundColor = NSColor.blue.cgColor
            print("Metal is not supported on this device")
            return nil
        }
        self.device = device

        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.delegate = self
        mtkView.autoresizingMask = [.width, .height]
        self.addSubview(mtkView)
        self.mtkView = mtkView
        
        if !setupPipelines() {
            mtkView.isPaused = true
            mtkView.isHidden = true
            self.layer?.backgroundColor = NSColor.yellow.cgColor
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
            
            // Create an initial state on the CPU with a disturbance in the center.
            var initialData = [SIMD2<Float>](repeating: SIMD2<Float>(0.0, 1.0), count: width * height)
            let centerX = width / 2
            let centerY = height / 2
            let disturbanceRadius: Float = 20.0

            for y in 0..<height {
                for x in 0..<width {
                    let index = y * width + x
                    let distance = sqrt(pow(Float(x - centerX), 2) + pow(Float(y - centerY), 2))
                    if distance < disturbanceRadius {
                        // Use a cosine bell for a smooth initial pulse.
                        let pulse = 5.0 * (0.5 * (cos(distance / disturbanceRadius * .pi) + 1.0))
                        initialData[index] = SIMD2<Float>(pulse, 1.0)
                    }
                }
            }
            
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
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        uniforms.time += 1.0 / Float(self.animationTimeInterval == 0 ? 60 : (1/self.animationTimeInterval))

        // Compute passes
        if let computePass = commandBuffer.makeComputeCommandEncoder() {
            let w = computePipelineState.threadExecutionWidth
            let h = computePipelineState.maxTotalThreadsPerThreadgroup / w
            let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
            let threadsPerGrid = MTLSize(width: Int(view.drawableSize.width), height: Int(view.drawableSize.height), depth: 1)

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
    
    override func startAnimation() {
        super.startAnimation()
        mtkView?.isPaused = false
    }
    
    override func stopAnimation() {
        super.stopAnimation()
        mtkView?.isPaused = true
    }
}
