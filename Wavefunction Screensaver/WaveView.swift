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

class WaveView: ScreenSaverView, MTKViewDelegate {
    private var mtkView: MTKView?
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    
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
        
        if !setupPipeline() {
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
    
    private func setupPipeline() -> Bool {
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
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            return true
        } catch {
            print("Could not create render pipeline state: \(error)")
            return false
        }
    }
    
    // this is no longer used for drawing, MTKView handles it
    override func draw(_ rect: NSRect) {}
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // called when the view size changes
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // pass the viewport size to the fragment shader
        var viewportSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        renderEncoder.setFragmentBytes(&viewportSize, length: MemoryLayout.size(ofValue: viewportSize), index: 0)

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.endEncoding()
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
