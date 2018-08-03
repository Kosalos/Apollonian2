import UIKit
import Metal

let limColor = UIColor(red:0.25, green:0.25, blue:0.2, alpha: 1)
let nrmColorFast = UIColor(red:0.2, green:0.2, blue:0.2, alpha: 1)
let nrmColorSlow = UIColor(red:0.2, green:0.25, blue:0.2, alpha: 1)
let textColor = UIColor.lightGray

var vc:ViewController! = nil

class ViewController: UIViewController, WGDelegate  {
    var control = Control()
    var cBuffer:MTLBuffer! = nil
    var outTextureL: MTLTexture!
    var outTextureR: MTLTexture!
    var pipeline1: MTLComputePipelineState!
    let queue = DispatchQueue(label: "Queue")
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()

    var circleMove:Bool = false
    var isStereo:Bool = false
    var autoChg:Bool = false
    var dist1000:Float = 0.0
    
    let SIZE:Int = 1024
    let threadGroupCount = MTLSizeMake(20,20, 1)
    lazy var threadGroups: MTLSize = { MTLSizeMake(SIZE / threadGroupCount.width, SIZE / threadGroupCount.height, 1) }()
    
    @IBOutlet var metalTextureViewL: MetalTextureView!
    @IBOutlet var metalTextureViewR: MetalTextureView!
    @IBOutlet var wg:WidgetGroup!
    @IBOutlet var cRotate: CRotate!
    @IBOutlet var cTranslate: CTranslate!
    @IBOutlet var cTranslateZ: CTranslateZ!

    //MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        wg.delegate = self
        wg.initialize()
        initializeWidgetGroup()

        do {
            let defaultLibrary:MTLLibrary! = self.device.makeDefaultLibrary()
            guard let kf1 = defaultLibrary.makeFunction(name: "rayMarchShader")  else { fatalError() }
            pipeline1 = try device.makeComputePipelineState(function: kf1)
        }
        catch { fatalError("error creating pipelines") }
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: SIZE,
            height: SIZE,
            mipmapped: false)
        outTextureL = self.device.makeTexture(descriptor: textureDescriptor)!
        outTextureR = self.device.makeTexture(descriptor: textureDescriptor)!

        metalTextureViewL.initialize(outTextureL)
        metalTextureViewR.initialize(outTextureR)

        cBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)        
        layoutViews()

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(self.handleGesture(gesture:)))
        swipeUp.direction = .up
        self.view.addGestureRecognizer(swipeUp)
        
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.handleGesture(gesture:)))
        swipeDown.direction = .down
        self.view.addGestureRecognizer(swipeDown)

        reset()
        Timer.scheduledTimer(withTimeInterval:0.05, repeats:true) { timer in self.timerHandler() }
        updateImage()
    }
    
    @objc func handleGesture(gesture: UISwipeGestureRecognizer) -> Void {
        switch gesture.direction {
        case .up : wg.moveFocus(-1)
        case .down : wg.moveFocus(+1)
        default : break
        }
    }
    
    //MARK: -
    
    let cameraMin:Float = -5
    let cameraMax:Float = 5
    let focusMin:Float = -10
    let focusMax:Float = 10
    let cameraDelta:Float = 1.5
    
    let zoomMin:Float = 0.001
    let zoomMax:Float = 1
    let distMin:Float = 0.00001 * 1000
    let distMax:Float = 0.03 * 1000
    let sPmin:Float = 0.01
    let sPmax:Float = 1
    let sPchg:Float = 0.25
    
    func initializeWidgetGroup() {
        wg.reset()
        wg.addSingleFloat(&control.zoom,zoomMin, zoomMax, 2, "Zoom",.refresh)
        wg.addSingleFloat(&dist1000,distMin, distMax, 50, "minDist",.refresh)
        wg.addSingleFloat(&control.multiplier,sPmin,sPmax,sPchg, "multiplier",.refresh)
        wg.addSingleFloat(&control.dali,0.1,1,0.1, "Dali",.refresh)
        wg.addLine()
        wg.addFloat3Dual(&control.light,cameraMin, cameraMax, cameraDelta,"Light XY",.refresh)
        wg.addFloat3Single(&control.light,cameraMin,cameraMax,cameraDelta, "Light Z",.refresh)
        wg.addLine()
        wg.addFloat3Dual(&control.color,0,5,1,"Color RG",.refresh)
        wg.addFloat3Single(&control.color,0,5,1,"Color B",.refresh)
        wg.addLine()
        wg.addColor(1,Float(RowHT * 11))
        wg.addSingleFloat(&control.lighting.ambient,sPmin,sPmax,sPchg, "ambient",.refresh)
        wg.addSingleFloat(&control.lighting.diffuse,sPmin,sPmax,sPchg, "diffuse",.refresh)
        wg.addSingleFloat(&control.lighting.specular,sPmin,sPmax,sPchg, "specular",.refresh)
        wg.addSingleFloat(&control.lighting.harshness,sPmin,sPmax,sPchg, "harsh",.refresh)
        wg.addSingleFloat(&control.lighting.saturation,sPmin,sPmax,sPchg, "saturate",.refresh)
        wg.addSingleFloat(&control.lighting.gamma,sPmin,sPmax,sPchg, "gamma",.refresh)
        wg.addSingleFloat(&control.lighting.shadowMin,sPmin,sPmax,sPchg, "sMin",.refresh)
        wg.addSingleFloat(&control.lighting.shadowMax,sPmin,sPmax,sPchg, "sMax",.refresh)
        wg.addSingleFloat(&control.lighting.shadowMult,sPmin,sPmax,sPchg, "sMult",.refresh)
        wg.addSingleFloat(&control.lighting.shadowAmt,sPmin,sPmax,sPchg, "sAmt",.refresh)
        wg.addCommand("auto Chg",.autoChg)
        wg.addLine()
        wg.addSingleFloat(&control.foam, 0.5,2,0.1, "Foam",.refresh)
        wg.addSingleFloat(&control.foam2, 0.5,2,0.4, "Foam2",.refresh)
        wg.addSingleFloat(&control.bend, 0.01,0.03,0.01, "Bend",.refresh)
        wg.addLine()
        wg.addSingleFloat(&control.fog, 10,100,30, "Fog",.refresh)
        wg.addLine()
        wg.addCommand("Save/Load",.saveLoad)
        wg.addCommand("Help",.help)
        wg.addCommand("Reset",.reset)
        wg.addLine()
        wg.addCommand("Stereo",.stereo)
        
        if isStereo {
            wg.addSingleFloat(&control.parallax,-0.01,0.01,0.0002, "Parallax",.refresh)
        }
        
        wg.addLine()
    }

    //MARK: -
    
    func wgCommand(_ cmd: CmdIdent) {
        switch(cmd) {
        case .reset :
            reset()
            updateImage()
        case .saveLoad : performSegue(withIdentifier: "saveLoadSegue", sender: self)
        case .help : performSegue(withIdentifier: "helpSegue", sender: self)
        case .stereo :
            isStereo = !isStereo
            initializeWidgetGroup()
            layoutViews()
            updateImage()
        case .autoChg:
            autoChg = !autoChg
        case .loadedData :
            Timer.scheduledTimer(withTimeInterval:0.05, repeats:false) { timer in self.delayedLoad() }
        case .refresh :
            updateImage()
        default :
            break
        }
    }
    
    @objc func delayedLoad() {
        wg.setNeedsDisplay()
        updateImage()
    }
        
    func wgGetString(_ index: Int) -> String {
        return ""
    }
    
    func wgGetColor(_ index: Int) -> UIColor {
        switch(index) {
        case 1 : return autoChg ? UIColor(red:0.2, green:0.2, blue:0, alpha:1) : .black
        default : return .black
        }
    }
    
    func wgOptionSelected(_ ident: Int, _ index: Int) {
    }
    
    func wgGetOptionString(_ ident: Int) -> String {
        return ""
    }

    //MARK: -
    
    func removeAllFocus() {
        wg.removeAllFocus()
        cTranslate.removeFocus()
        cTranslateZ.removeFocus()
        cRotate.removeFocus()
    }
    
    func focusMovement(_ pt:CGPoint) {
        if cTranslate.hasFocus { cTranslate.focusMovement(pt); return }
        if cTranslateZ.hasFocus { cTranslateZ.focusMovement(pt); return }
        if cRotate.hasFocus { cRotate.focusMovement(pt); return }
        wg.focusMovement(pt)
    }
    
    //MARK: -
    
    func alterAngle(_ dx:Float, _ dy:Float) {
        let center:CGFloat = cRotate.bounds.width/2
        arcBall.mouseDown(CGPoint(x: center, y: center))
        arcBall.mouseMove(CGPoint(x: center + CGFloat(dx/50), y: center + CGFloat(dy/50)))
        
        let direction = simd_make_float4(0,0.1,0,0)
        let rotatedDirection = simd_mul(arcBall.transformMatrix, direction)
        
        control.focus.x = rotatedDirection.x + control.camera.x
        control.focus.y = rotatedDirection.y + control.camera.y
        control.focus.z = rotatedDirection.z + control.camera.z
    }
    
    func alterPosition(_ dx:Float, _ dy:Float, _ dz:Float) {
        func axisAlter(_ dir:float4, _ amt:Float) {
            let diff = simd_mul(arcBall.transformMatrix, dir) * amt / 300.0
            
            control.camera.x -= diff.x
            control.camera.y -= diff.y
            control.camera.z -= diff.z
            control.focus.x -= diff.x
            control.focus.y -= diff.y
            control.focus.z -= diff.z
        }
        
        let q:Float = 0.1
        axisAlter(simd_make_float4(q,0,0,0),dx)
        axisAlter(simd_make_float4(0,0,q,0),dy)
        axisAlter(simd_make_float4(0,q,0,0),dz)
    }

    //MARK: -
    
    var wgWidth:CGFloat = 0
    
    @objc func layoutViews() {
        let xs:CGFloat = view.bounds.width
        let ys:CGFloat = view.bounds.height
        
        wgWidth = wg.isHidden ? 0 : 120
        let vxs:CGFloat = xs - wgWidth

        if !wg.isHidden { wg.frame = CGRect(x:0, y:0, width:wgWidth, height:ys) }

        if isStereo {
            metalTextureViewR.isHidden = false
            let vxs2:CGFloat = vxs/2
            metalTextureViewL.frame = CGRect(x:wgWidth, y:0, width:vxs2, height:ys)
            metalTextureViewR.frame = CGRect(x:wgWidth+vxs2, y:0, width:vxs2, height:ys)
        }
        else {
            metalTextureViewR.isHidden = true
            metalTextureViewL.frame = CGRect(x:wgWidth, y:0, width:vxs, height:ys)
        }

        var x:CGFloat = wgWidth + 20
        var y:CGFloat = ys - 100
        
        func frame(_ xs:CGFloat, _ ys:CGFloat, _ dx:CGFloat, _ dy:CGFloat) -> CGRect {
            let r = CGRect(x:x, y:y, width:xs, height:ys)
            x += dx; y += dy
            return r
        }
        
        cTranslate.frame = frame(80,80,90,0)
        cTranslateZ.frame = frame(30,80,0,0)
        x = xs - 90
        cRotate.frame = frame(80,80,0,0)
        resetArcBall()
        
        for w in [ cTranslate,cTranslateZ,cRotate ] as [Any] { view.bringSubview(toFront:w as! UIView) }
    }
    
    func reset() {
        control.camera.x = 0.509296
        control.camera.y = 11.3861
        control.camera.z = 0.460886
        control.focus.x = 0.509277
        control.focus.y = 11.3799
        control.focus.z = 0.550133
        control.light = float3(1,1,1)
        control.color = float3(1,1,1)
        control.zoom = 0.956
        control.minDist = 0.006
        dist1000 = control.minDist * 1000.0
        control.lighting.ambient = 0.5
        control.lighting.diffuse = 0.5
        control.lighting.specular = 0.5
        control.lighting.harshness = 0.5
        control.lighting.saturation = 0.5
        control.lighting.gamma = 0.5
        control.multiplier = 0.5
        control.lighting.shadowMin = 0.5
        control.lighting.shadowMax = 0.5
        control.lighting.shadowMult = 0.5
        control.lighting.shadowAmt = 0.1
        control.dali = 1
        control.foam = 1
        control.foam2 = 1
        control.fog = 100
        control.bend = 0.02
        
        autoChg = false
        resetArcBall()
    }
    
    func resetArcBall() { arcBall.initialize(Float(cRotate.frame.width),Float(cRotate.frame.height)) }
    
    //MARK: -
    
    var circleAngle:Float = 0

    @objc func timerHandler() {
        var refresh:Bool = false
        if wg.update() { refresh = true }
        if cTranslate.update() { refresh = true }
        if cTranslateZ.update() { refresh = true }
        if cRotate.update() { refresh = true }
        
        if autoChg {
            func alter(_ v: inout Float) {
                if (arc4random() & 1023) < 800 { return }
                var r = v + cosf(circleAngle) / 40
                if r < 0 { r = 0 } else if r > 1 { r = 1 }
                v = r
            }
            
            alter(&control.lighting.ambient)
            alter(&control.lighting.diffuse)
            alter(&control.lighting.specular)
            alter(&control.lighting.harshness)
            alter(&control.lighting.saturation)
            alter(&control.lighting.gamma)
            alter(&control.lighting.shadowMin)
            alter(&control.lighting.shadowMax)
            alter(&control.lighting.shadowMult)
            alter(&control.lighting.shadowAmt)

            circleAngle += 0.02
            wg.setNeedsDisplay()
            refresh = true
        }
        
        if refresh { updateImage() }
    }
    
    var isBusy:Bool = false
    //var ui:Int = 0
    
    func updateImage() {
        //print("UpdateImage",ui); ui += 1
        if isBusy { return }
        isBusy = true
        
        control.light = normalize(control.light)
        control.minDist = dist1000 / 1000.0

        calcRayMarch(0)
        metalTextureViewL.display(metalTextureViewL.layer)
        
        if isStereo {
            calcRayMarch(1)
            metalTextureViewR.display(metalTextureViewR.layer)
        }

        isBusy = false
    }
    
    //MARK: -
    
    func calcRayMarch(_ who:Int) {
        var c = control
        if isStereo {
            if who == 0 { c.camera.x -= control.parallax; }
            if who == 1 { c.camera.x += control.parallax; }
        }
        
        let xs:CGFloat = metalTextureViewL.bounds.width
        let ys:CGFloat = metalTextureViewL.bounds.height
        c.ySize = Int32(ys)
        c.xSize = Int32(ys * ys / xs) // maintain aspect ratio during stereo mode

        cBuffer.contents().copyMemory(from:&c, byteCount:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline1)
        commandEncoder.setTexture(who == 0 ? outTextureL : outTextureR, index: 0)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    //MARK: -

    @IBAction func tapGesture(_ sender: UITapGestureRecognizer) {
        wg.isHidden = !wg.isHidden
        layoutViews()
        updateImage()
    }

    var oldPt = CGPoint()
    
    @IBAction func panGesture(_ sender: UIPanGestureRecognizer) {
        var pt = sender.translation(in: self.view)
        
        switch sender.state {
        case .began :
            oldPt = pt
        case .changed :
            pt.x -= oldPt.x
            pt.y -= oldPt.y
            focusMovement(pt)
        case .ended :
            focusMovement(CGPoint()) // 0,0 == stop auto change
        default : break
        }
    }

    override var prefersStatusBarHidden: Bool { return true }
}

