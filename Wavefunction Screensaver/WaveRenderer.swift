import Foundation
import MetalKit

// A struct to match the layout of our uniforms in the Metal shader.
struct WaveUniforms {
    var dx: Float = 0.0
    var dt: Float = 0.0
    var c: Float = 0.0
    var time: Float = 0.0
    var damper: Float = 0.0
    var padding0: Float = 0.0
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
class WaveRenderer {
    private var device: MTLDevice
    private var commandQueue: MTLCommandQueue!
    private var waveHeap: MTLHeap!

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
    private var disturbanceCooldownRange: ClosedRange<Int> = 0...0
    private var disturbanceDensityRange: ClosedRange<Int> = 0...0
    private var disturbanceRadiusRange: ClosedRange<Float> = 0...0
    private var disturbanceStrengthRange: ClosedRange<Float> = 0...0

    private var frameCounter: Int = 0
    private var disturbanceCooldown: Int = 0
    private var disturbanceDensity: Int = 1

    var animationTimeInterval: TimeInterval = 1.0 / 60.0

    init(device: MTLDevice) {
        self.device = device
    }

    func setup(pixelFormat: MTLPixelFormat) -> Bool {
        commandQueue = device.makeCommandQueue()
        return setupPipelines(pixelFormat: pixelFormat)
    }

    private func setupPipelines(pixelFormat: MTLPixelFormat) -> Bool {
        let library: MTLLibrary
        do {
            let bundle = Bundle(for: WaveRenderer.self)
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
            pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
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

    func cleanUp() {
        // explicitly release all metal objects.
        renderPipelineState = nil
        computePipelineState = nil
        copyPipelineState = nil
        addDisturbancePipelineState = nil
        
        waveBufferP = nil
        waveBufferC = nil
        waveBufferN = nil
        
        waveHeap = nil
        commandQueue = nil
    }

    func drawableSizeWillChange(size: CGSize) {
        let width = Int(size.width)
        let height = Int(size.height)
        let bufferSize = width * height * MemoryLayout<Float>.stride
        
        if bufferSize > 0 {
            let options: MTLResourceOptions = .storageModePrivate
            
            let sizeAndAlign = device.heapBufferSizeAndAlign(length: bufferSize, options: options)
            let alignedBufferSize = sizeAndAlign.size
            
            let heapDescriptor = MTLHeapDescriptor()
            heapDescriptor.size = alignedBufferSize * 3
            heapDescriptor.storageMode = .private
            
            guard let heap = device.makeHeap(descriptor: heapDescriptor) else {
                fatalError("Could not create heap")
            }
            self.waveHeap = heap
            
            waveBufferP = heap.makeBuffer(length: bufferSize, options: options)
            waveBufferC = heap.makeBuffer(length: bufferSize, options: options)
            waveBufferN = heap.makeBuffer(length: bufferSize, options: options)
            
            // Create an initial state on the CPU
            let initialData = [Float](repeating: 0.0, count: width * height)
            
            // Create a temporary shared buffer to copy the initial data to the GPU.
            let initialDataSize = initialData.count * MemoryLayout<Float>.stride
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
    
    func updateSettings(c: Float, dx: Float, dt: Float, damper: Float, disturbanceCooldownRange: ClosedRange<Int>, disturbanceDensityRange: ClosedRange<Int>, disturbanceRadiusRange: ClosedRange<Float>, disturbanceStrengthRange: ClosedRange<Float>) {
        self.uniforms.c = c
        self.uniforms.dx = dx
        self.uniforms.dt = dt
        self.uniforms.damper = damper
        
        self.disturbanceCooldownRange = disturbanceCooldownRange
        self.disturbanceDensityRange = disturbanceDensityRange
        self.disturbanceRadiusRange = disturbanceRadiusRange
        self.disturbanceStrengthRange = disturbanceStrengthRange
    }
}
