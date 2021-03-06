import UIKit

class CTranslate: UIView {
    let viewSize:Float = 4  // -2 ... +2
    var scale:Float = 0
    var xc:CGFloat = 0
    var fastEdit = true
    var hasFocus = false

    func mapPoint(_ pt:CGPoint) -> float3 {
        var v = float3()
        v.x = Float(pt.x) * scale - viewSize/2 // centered on origin
        v.y = Float(pt.y) * scale - viewSize/2
        v.z = 0
        return v
    }
    
    func unMapPoint(_ p:float3) -> CGPoint {
        var v = CGPoint()
        v.x = xc + CGFloat(p.x / scale)
        v.y = xc + CGFloat(p.y / scale)
        return v
    }
    
    override func draw(_ rect: CGRect) {
        if scale == 0 {
            scale = viewSize / Float(bounds.width)
            xc = bounds.width / 2
            
            let tap1 = UITapGestureRecognizer(target: self, action: #selector(self.handleTap1(_:)))
            tap1.numberOfTapsRequired = 1
            addGestureRecognizer(tap1)
            
            let tap2 = UITapGestureRecognizer(target: self, action: #selector(self.handleTap2(_:)))
            tap2.numberOfTapsRequired = 2
            addGestureRecognizer(tap2)
            
            isUserInteractionEnabled = true
            self.backgroundColor = .clear
        }
        
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(fastEdit ? nrmColorFast.cgColor : nrmColorSlow.cgColor)
        context?.addRect(bounds)
        context?.fillPath()
        
        UIColor.black.set()
        context?.setLineWidth(2)
        drawVLine(context!,bounds.midX,0,bounds.height)
        drawHLine(context!,0,bounds.width,bounds.midY)
        drawText(10,8,textColor,16,"Move")
        
        drawBorder(context!,bounds)
        
        if hasFocus {
            context?.setLineWidth(1)
            context!.setStrokeColor(UIColor.red.cgColor)
            drawRect(context!,bounds)
        }
    }
    
    //MARK:-
    
    func tapCommon() {
        dx = 0
        dy = 0
        setNeedsDisplay()
    }

    @objc func handleTap1(_ sender: UITapGestureRecognizer) {
        vc.removeAllFocus()
        hasFocus = true
        tapCommon()
    }
    
    @objc func handleTap2(_ sender: UITapGestureRecognizer) {
        fastEdit = !fastEdit
        tapCommon()
    }

    //MARK:-
    
    func removeFocus() {
        if hasFocus {
            hasFocus = false
            setNeedsDisplay()
        }
    }
    
    func focusMovement(_ pt:CGPoint) {
        if pt.x == 0 { touched = false; return }
        
        dx = Float(pt.x)
        dy = Float(pt.y)

        if !fastEdit {
            dx /= 10
            dy /= 10
        }
        
        touched = true
        setNeedsDisplay()
    }
    
    // MARK: Touch --------------------------
    
    var touched:Bool = false
    var dx:Float = 0
    var dy:Float = 0

    func update() -> Bool {
        if touched { vc.alterPosition(dx,dy,0) }
        return touched
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            dx = Float(pt.x - bounds.size.width/2) * 0.05
            dy = Float(pt.y - bounds.size.height/2) * 0.05
            touched = true
            
            if !fastEdit {
                dx /= 100
                dy /= 100
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { touchesBegan(touches, with:event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touched = false }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with:event) }
}

