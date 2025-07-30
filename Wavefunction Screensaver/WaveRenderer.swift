import Foundation
import MetalKit
import MetalPerformanceShaders

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

    // Pipelines
    private var renderPipelineState: MTLRenderPipelineState!
    private var updateWaveStatePipelineState: MTLComputePipelineState!
    private var addDisturbancePipelineState: MTLComputePipelineState!

    // MPS Kernels
    private var sobel: MPSImageSobel!
    private var convolution: MPSImageConvolution!
    private var gaussianBlur: MPSImageGaussianBlur!

    // Textures for wave simulation and effects
    private var waveTextureP: MTLTexture! // previous state
    private var waveTextureC: MTLTexture! // current state
    private var waveTextureN: MTLTexture! // next state
    private var laplacianTexture: MTLTexture!
    private var sobelTexture: MTLTexture!
    private var blurredSobelTexture: MTLTexture!

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
        setupMPSKernels()
        return setupPipelines(pixelFormat: pixelFormat)
    }

    private func setupMPSKernels() {
        let convWeights: [Float] = [
            0, 1, 0,
            1,-4, 1,
            0, 1, 0
        ]
        convolution = MPSImageConvolution(device: device,
                                          kernelWidth: 3,
                                          kernelHeight: 3,
                                          weights: convWeights)
        convolution.edgeMode = .zero

        sobel = MPSImageSobel(device: device)
        sobel.edgeMode = .clamp

        // Adjust the `sigma` value here to control the blur radius.
        // Larger sigma = more blurry/glowy. Smaller sigma = sharper.
        gaussianBlur = MPSImageGaussianBlur(device: device, sigma: 1.3)
        gaussianBlur.edgeMode = .clamp
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
            guard let updateFunction = library.makeFunction(name: "updateWaveState") else {
                print("Could not find 'updateWaveState' function.")
                return false
            }
            updateWaveStatePipelineState = try device.makeComputePipelineState(function: updateFunction)

            guard let disturbanceFunction = library.makeFunction(name: "addDisturbance") else {
                print("Could not find 'addDisturbance' function.")
                return false
            }
            addDisturbancePipelineState = try device.makeComputePipelineState(function: disturbanceFunction)
        } catch {
            print("Could not create compute pipeline state: \(error)")
            return false
        }

        return true
    }

    func cleanUp() {
        renderPipelineState = nil
        updateWaveStatePipelineState = nil
        addDisturbancePipelineState = nil
        sobel = nil
        convolution = nil
        gaussianBlur = nil
        waveTextureP = nil
        waveTextureC = nil
        waveTextureN = nil
        laplacianTexture = nil
        sobelTexture = nil
        blurredSobelTexture = nil
        commandQueue = nil
    }

    func drawableSizeWillChange(size: CGSize) {
        let width = Int(size.width)
        let height = Int(size.height)
        
        guard width > 0, height > 0 else { return }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        waveTextureP = device.makeTexture(descriptor: descriptor)
        waveTextureC = device.makeTexture(descriptor: descriptor)
        waveTextureN = device.makeTexture(descriptor: descriptor)
        laplacianTexture = device.makeTexture(descriptor: descriptor)

        // The Sobel filter will write the gradient magnitude to a single-channel texture.
        let sobelDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float,
                                                                       width: width,
                                                                       height: height,
                                                                       mipmapped: false)
        sobelDescriptor.usage = [.shaderRead, .shaderWrite]
        sobelDescriptor.storageMode = .private
        sobelTexture = device.makeTexture(descriptor: sobelDescriptor)
        blurredSobelTexture = device.makeTexture(descriptor: sobelDescriptor)

        // Clear textures to zero initially
        let zeroData = [Float](repeating: 0, count: width * height * 4) // Allocate enough for 4 channels to be safe
        let bytesPerRow = MemoryLayout<Float>.stride * width

        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = cmdBuffer.makeBlitCommandEncoder(),
              let tempBuffer = device.makeBuffer(bytes: zeroData, length: bytesPerRow * height, options: .storageModeShared)
        else { return }

        let sourceSize = MTLSize(width: width, height: height, depth: 1)

        blitEncoder.copy(from: tempBuffer, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: 0, sourceSize: sourceSize,
                         to: waveTextureP, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blitEncoder.copy(from: tempBuffer, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: 0, sourceSize: sourceSize,
                         to: waveTextureC, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blitEncoder.copy(from: tempBuffer, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: 0, sourceSize: sourceSize,
                         to: waveTextureN, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())

        blitEncoder.endEncoding()
        cmdBuffer.commit()
            
        uniforms.resolution = SIMD2<Float>(Float(width), Float(height))
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

            let w = 16
            let h = 16
            let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
            let threadsPerGrid = MTLSize(width: Int(view.drawableSize.width), height: Int(view.drawableSize.height), depth: 1)

            // Compute passes
            if let computePass = commandBuffer.makeComputeCommandEncoder() {
                // Add disturbances
                frameCounter += 1
                if frameCounter >= disturbanceCooldown {
                    frameCounter = 0
                    
                    computePass.setComputePipelineState(addDisturbancePipelineState)
                    computePass.setTexture(waveTextureC, index: 0)
                    computePass.setBytes(&uniforms, length: MemoryLayout<WaveUniforms>.stride, index: 1)
                    
                    for _ in 0..<disturbanceDensity {
                        var disturbance = DisturbanceUniforms(
                            position: SIMD2<Float>(Float.random(in: 0..<Float(view.drawableSize.width)),
                                                   Float.random(in: 0..<Float(view.drawableSize.height))),
                            radius: Float.random(in: disturbanceRadiusRange),
                            strength: Float.random(in: disturbanceStrengthRange)
                        )
                        computePass.setBytes(&disturbance, length: MemoryLayout<DisturbanceUniforms>.stride, index: 0)
                        computePass.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                    }
                    disturbanceCooldown = Int.random(in: disturbanceCooldownRange)
                    disturbanceDensity = Int.random(in: disturbanceDensityRange)
                }
                computePass.endEncoding()
            }
            
            // 1. Compute Laplacian using MPS
            convolution.encode(commandBuffer: commandBuffer, sourceTexture: waveTextureC, destinationTexture: laplacianTexture)
            
            // 2. Update wave state with custom kernel
            if let computePass = commandBuffer.makeComputeCommandEncoder() {
                computePass.setComputePipelineState(updateWaveStatePipelineState)
                computePass.setTexture(waveTextureP, index: 0)
                computePass.setTexture(waveTextureC, index: 1)
                computePass.setTexture(laplacianTexture, index: 2)
                computePass.setTexture(waveTextureN, index: 3)
                computePass.setBytes(&uniforms, length: MemoryLayout<WaveUniforms>.stride, index: 0)
                computePass.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                
                computePass.endEncoding()
            }
            
            // 3. Detect edges using Sobel
            sobel.encode(commandBuffer: commandBuffer, sourceTexture: waveTextureC, destinationTexture: sobelTexture)

            // 4. Blur the edges using MPS
            gaussianBlur.encode(commandBuffer: commandBuffer, sourceTexture: sobelTexture, destinationTexture: blurredSobelTexture)

            // 5. Render pass (compositing)
            if let renderPass = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderPass.setRenderPipelineState(renderPipelineState)
                renderPass.setFragmentTexture(waveTextureC, index: 0)
                renderPass.setFragmentTexture(blurredSobelTexture, index: 1)
                renderPass.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                renderPass.endEncoding()
            }

            commandBuffer.present(drawable)
            commandBuffer.commit()
            
            // swap textures for next frame
            let temp = waveTextureP
            waveTextureP = waveTextureC
            waveTextureC = waveTextureN
            waveTextureN = temp
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
