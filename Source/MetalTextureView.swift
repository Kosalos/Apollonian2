import UIKit
import Metal
import MetalKit

class MetalTextureView: MTKView,MTKViewDelegate {
    var pipelineR: MTLRenderPipelineState!
    var sampler: MTLSamplerState?
    var vertices: MTLBuffer?
    var outTexture: MTLTexture! = nil
    let queue = DispatchQueue(label:"Q")
    var commandQueue: MTLCommandQueue! = nil
    
    func initialize(_ texture:MTLTexture) {
        delegate = self
        outTexture = texture
        
        if commandQueue == nil {
            let device:MTLDevice! = MTLCreateSystemDefaultDevice()
            self.device = device
            commandQueue = device.makeCommandQueue()
            
            do {
                let library: MTLLibrary = try device.makeDefaultLibrary(bundle: .main)
                let descriptor: MTLRenderPipelineDescriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction   = library.makeFunction(name: "metalTextureView_Vertex")
                descriptor.fragmentFunction = library.makeFunction(name: "metalTextureView_Fragment")
                descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
                pipelineR = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                fatalError(String(describing: error))
            }
            
            let p1 = float2(0,0)
            let p2 = float2(1,0)
            let p3 = float2(0,1)
            let p4 = float2(1,1)
            vertices = device.makeBuffer(bytes: [p1,p2,p3,p4], length: 4 * MemoryLayout<float2>.stride,  options: [])
            
            let descriptor: MTLSamplerDescriptor = MTLSamplerDescriptor()
            descriptor.magFilter = .nearest
            descriptor.minFilter = .nearest
            descriptor.sAddressMode = .repeat
            descriptor.tAddressMode = .repeat
            sampler = device.makeSamplerState(descriptor: descriptor)
        }
    }
    
    //MARK: -
    
    var pt = CGPoint()
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            pt = touch.location(in: self)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            var npt = touch.location(in: self)
            npt.x = (npt.x - pt.x) * 20
            npt.y = (npt.y - pt.y) * 20
            vc.focusMovement(npt)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {  vc.focusMovement(CGPoint()) } // 0,0 = stop movement
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with: event) }

    //MARK: -
    
    func draw(in view: MTKView) {
        if outTexture == nil { Swift.print("Must call MetalTextureView.initialize() first!"); exit(0) }
        
        let descriptor:MTLRenderPassDescriptor = currentRenderPassDescriptor!
        let commandBuffer = commandQueue.makeCommandBuffer()!
        guard let encoder: MTLRenderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipelineR)
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setFragmentTexture(outTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        if let drawable = currentDrawable { commandBuffer.present(drawable) }
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
