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
struct Uniforms {
    var time: Float
    var resolution: SIMD2<Float>
}

class WaveView: ScreenSaverView, MTKViewDelegate {
    private var mtkView: MTKView?
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var renderPipelineState: MTLRenderPipelineState!
    private var computePipelineState: MTLComputePipelineState!
    
    private var screenBuffer: MTLBuffer!
    private var time: Float = 0

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        
        // ensure this view is layer-backed
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
        
        if !setupRenderPipeline() || !setupComputePipeline() {
            // indicate failure to set up the pipeline
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
    
    private func setupRenderPipeline() -> Bool {
        guard let mtkView = mtkView else { return false }
        commandQueue = device.makeCommandQueue()

        // explicitly load the compiled metal library from the bundle
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

        // create the vertex and fragment functions
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")

        // create a pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        // create the pipeline state
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            return true
        } catch {
            print("Could not create render pipeline state: \(error)")
            return false
        }
    }
    
    private func setupComputePipeline() -> Bool {
        let library: MTLLibrary
        do {
            let bundle = Bundle(for: WaveView.self)
            guard let defaultMetalLibraryUrl = bundle.url(forResource: "default", withExtension: "metallib") else {
                print("Could not find default.metallib in the bundle.")
                return false
            }
            library = try device.makeLibrary(URL: defaultMetalLibraryUrl)
        } catch {
            print("Could not load Metal library: \(error)")
            return false
        }
        
        guard let computeFunction = library.makeFunction(name: "computeKernel") else {
            print("Could not create compute function.")
            return false
        }
        
        do {
            computePipelineState = try device.makeComputePipelineState(function: computeFunction)
            return true
        } catch {
            print("Could not create compute pipeline state: \(error)")
            return false
        }
    }
    
    // this is no longer used for drawing, MTKView handles it
    override func draw(_ rect: NSRect) {}
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // called when the view size changes
        let bufferSize = Int(size.width) * Int(size.height) * MemoryLayout<SIMD2<Float>>.stride
        if bufferSize > 0 {
            screenBuffer = device.makeBuffer(length: bufferSize, options: .storageModePrivate)
        }
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        time += 1.0 / Float(self.animationTimeInterval == 0 ? 60 : (1/self.animationTimeInterval))

        // Compute pass
        if let computePass = commandBuffer.makeComputeCommandEncoder() {
            computePass.setComputePipelineState(computePipelineState)
            
            var uniforms = Uniforms(time: time, resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)))
            computePass.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            computePass.setBuffer(screenBuffer, offset: 0, index: 0)
            
            let w = computePipelineState.threadExecutionWidth
            let h = computePipelineState.maxTotalThreadsPerThreadgroup / w
            let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
            
            let threadsPerGrid = MTLSize(width: Int(view.drawableSize.width), height: Int(view.drawableSize.height), depth: 1)
            
            computePass.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            computePass.endEncoding()
        }

        // Render pass
        if let renderPass = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            renderPass.setRenderPipelineState(renderPipelineState)
            
            var uniforms = Uniforms(time: time, resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)))
            renderPass.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            renderPass.setFragmentBuffer(screenBuffer, offset: 0, index: 1)
            
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
