import UIKit

protocol WGDelegate {
    func wgCommand(_ cmd:CmdIdent)
    func wgGetString(_ index:Int) -> String
    func wgGetColor(_ index:Int) -> UIColor
    func wgOptionSelected(_ ident:Int, _ index:Int)
    func wgGetOptionString(_ ident:Int) -> String
}

enum WgEntryKind { case singleFloat,dualFloat,dropDown,option,command,legend,line,string,color,move,gap,float3Dual,float3Single }
enum CmdIdent { case none,refresh,reset,saveLoad,help,stereo,autoChg,loadedData }

let NONE:Int = -1
let FontSZ:CGFloat = 20
let RowHT:CGFloat = 25
let GrphSZ:CGFloat = 21
let TxtYoff:CGFloat = 0
let Tab1:CGFloat = 5     // graph x1
let Tab2:CGFloat = 24    // text after graph
var py = CGFloat()

struct wgEntryData {
    var kind:WgEntryKind = .legend
    var index:Int = 0
    var cmd:CmdIdent = .help
    var str:[String] = []
    var valuePointerX:UnsafeMutableRawPointer! = nil
    var valuePointerY:UnsafeMutableRawPointer! = nil
    var deltaValue:Float = 0
    var mRange = float2()
    var fastEdit:Bool = true
    var visible:Bool = true
    var yCoord = CGFloat()
    
    func isValueWidget() ->Bool { return kind == .singleFloat || kind == .dualFloat }
    
    func getFloatValue(_ who:Int) -> Float {
        switch who {
        case 0 :
            if valuePointerX == nil { return 0 }
            return valuePointerX.load(as: Float.self)
        default:
            if valuePointerY == nil { return 0 }
            return valuePointerY.load(as: Float.self)
        }
    }
    
    func getInt32Value() -> Int {
        if valuePointerX == nil { return 0 }
        let v =  Int(valuePointerX.load(as: Int32.self))
        //Swift.print("getInt32Value = ",v.description)
        return v;
    }
    
    func ratioClamped(_ v:CGFloat) -> CGFloat {
        if v < 0.05 { return CGFloat(0.05) }          // so graph line is always visible
        if v > 0.95 { return CGFloat(0.95) }
        return v
    }
    
    func valueRatio(_ who:Int) -> CGFloat {
        let den = mRange.y - mRange.x
        if den == 0 { return CGFloat(0) }
        return ratioClamped(CGFloat((getFloatValue(who) - mRange.x) / den ))
    }
    
    func float3ValueRatio(_ who:Int) -> CGFloat {
        func getFloat3Value(_ who:Int) -> Float {
            if valuePointerX == nil { return 0 }
            let v:float3 = valuePointerX.load(as: float3.self)
            switch who {
            case 0 : return v.x
            case 1 : return v.y
            case 2 : return v.z
            default: return 0
            }
        }
        
        let den = mRange.y - mRange.x
        if den == 0 { return CGFloat(0) }
        return ratioClamped(CGFloat((getFloat3Value(who) - mRange.x) / den ))
    }
}

class WidgetGroup: UIView {
    var delegate:WGDelegate?
    var context : CGContext?
    var data:[wgEntryData] = []
    var focus:Int = NONE
    var previousFocus:Int = NONE
    var deltaX:Float = 0
    var deltaY:Float = 0
    
    func initialize() {
        self.backgroundColor = UIColor.black
        
        let tap2 = UITapGestureRecognizer(target: self, action: #selector(self.handleTap2(_:)))
        tap2.numberOfTapsRequired = 2
        addGestureRecognizer(tap2)
    }
    
    @objc func handleTap2(_ sender: UITapGestureRecognizer) {
        if focus != NONE {
            data[focus].fastEdit = !data[focus].fastEdit
            setNeedsDisplay()
        }
    }
    
    func reset() { data.removeAll() }
    
    func removeAllFocus() { focus = NONE; setNeedsDisplay() }
    
    func wgOptionSelected(_ ident:Int, _ index:Int) {
        delegate?.wgOptionSelected(ident,index)
        setNeedsDisplay()
    }
    
    //MARK:-
    
    var dIndex:Int = 0
    
    func newEntry() {
        data.append(wgEntryData())
        dIndex = data.count-1
    }
    
    func addCommon(_ ddIndex:Int, _ min:Float, _ max:Float, _ delta:Float, _ iname:String,_ nCmd:CmdIdent) {
        data[ddIndex].mRange.x = min
        data[ddIndex].mRange.y = max
        data[ddIndex].deltaValue = delta
        data[dIndex].cmd = nCmd
        data[ddIndex].str.append(iname)
    }
    
    func addSingleFloat(_ vx:UnsafeMutableRawPointer, _ min:Float, _ max:Float,  _ delta:Float, _ iname:String, _ nCmd:CmdIdent = .none) {
        newEntry()
        data[dIndex].kind = .singleFloat
        data[dIndex].valuePointerX = vx
        addCommon(dIndex,min,max,delta,iname,nCmd)
    }
    
    func addDualFloat(_ vx:UnsafeMutableRawPointer, _ vy:UnsafeMutableRawPointer, _ min:Float, _ max:Float,  _ delta:Float, _ iname:String, _ nCmd:CmdIdent = .none) {
        newEntry()
        data[dIndex].kind = .dualFloat
        data[dIndex].valuePointerX = vx
        data[dIndex].valuePointerY = vy
        addCommon(dIndex,min,max,delta,iname,nCmd)
    }

    func addFloat3Dual(_ vx:UnsafeMutableRawPointer, _ min:Float, _ max:Float,  _ delta:Float, _ iname:String, _ nCmd:CmdIdent = .none) {
        newEntry()
        data[dIndex].kind = .float3Dual
        data[dIndex].valuePointerX = vx
        addCommon(dIndex,min,max,delta,iname,nCmd)
    }

    func addFloat3Single(_ vx:UnsafeMutableRawPointer, _ min:Float, _ max:Float,  _ delta:Float, _ iname:String, _ nCmd:CmdIdent = .none) {
        newEntry()
        data[dIndex].kind = .float3Single
        data[dIndex].valuePointerX = vx
        addCommon(dIndex,min,max,delta,iname,nCmd)
    }

    func addDropDown(_ vx:UnsafeMutableRawPointer, _ items:[String]) {
        newEntry()
        data[dIndex].kind = .dropDown
        data[dIndex].valuePointerX = vx
        for i in items { data[dIndex].str.append(i) }
    }
    
    func addLegend(_ iname:String) {
        newEntry()
        data[dIndex].kind = .legend
        data[dIndex].str.append(iname)
    }
    
    func addLine() {
        newEntry()
        data[dIndex].kind = .line
    }
    
    func addMove() {
        newEntry()
        data[dIndex].kind = .move
        data[dIndex].str.append("Move")
    }
    
    func addCommand(_ iname:String, _ ncmd:CmdIdent) {
        newEntry()
        data[dIndex].kind = .command
        data[dIndex].str.append(iname)
        data[dIndex].cmd = ncmd
    }
    
    func addString(_ iname:String, _ cNumber:Int) {
        newEntry()
        data[dIndex].kind = .string
        data[dIndex].str.append(iname)
        data[dIndex].index = cNumber
    }
    
    func addColor(_ index:Int, _ height:Float) {
        newEntry()
        data[dIndex].kind = .color
        data[dIndex].index = index
        data[dIndex].deltaValue = height
    }
    
    func addOptionSelect(_ ident:Int, _ title:String, _ message:String, _ options:[String]) {
        newEntry()
        data[dIndex].kind = .option
        data[dIndex].index = ident
        data[dIndex].str.append(title)
        data[dIndex].str.append(message)
        for i in 0 ..< options.count { data[dIndex].str.append(options[i]) }
    }
    
    func addGap(_ height:Float) {
        newEntry()
        data[dIndex].kind = .gap
        data[dIndex].deltaValue = height
    }
    
    //MARK:-
    
    func drawGraph(_ index:Int) {
        let d = data[index]
        let x:CGFloat = 5
        let rect = CGRect(x:x, y:py, width:GrphSZ, height:GrphSZ)
        
        if d.fastEdit { UIColor.black.set() } else { UIColor.red.set() }
        UIBezierPath(rect:rect).fill()
        
        if d.kind != .move {       // x,y cursor lines
            context!.setLineWidth(2)
            UIColor.white.set()
            
            switch d.kind {
            case .float3Dual :
                let cx = rect.origin.x + d.float3ValueRatio(0) * rect.width
                drawVLine(context!,cx,rect.origin.y,rect.origin.y + GrphSZ)
                
                let y = rect.origin.y + (1.0 - d.float3ValueRatio(1)) * rect.height
                drawHLine(context!,rect.origin.x,rect.origin.x + GrphSZ,y)
            case .float3Single :
                let cx = rect.origin.x + d.float3ValueRatio(2) * rect.width
                drawVLine(context!,cx,rect.origin.y,rect.origin.y + GrphSZ)
            default :
                let cx = rect.origin.x + d.valueRatio(0) * rect.width
                drawVLine(context!,cx,rect.origin.y,rect.origin.y + GrphSZ)
                
                if d.kind == .dualFloat || d.kind == .float3Dual {
                    let y = rect.origin.y + (1.0 - d.valueRatio(1)) * rect.height
                    drawHLine(context!,rect.origin.x,rect.origin.x + GrphSZ,y)
                }
            }
        }
        
        UIColor.white.set()
        UIBezierPath(rect:rect).stroke()
    }
    
    func drawEntry(_ index:Int) {
        let tColor:UIColor = index == focus ? .green : .white
        data[index].yCoord = py
        
        switch(data[index].kind) {
        case .singleFloat, .dualFloat, .move, .float3Dual, .float3Single :
            drawText(Tab2+10,py+TxtYoff,tColor,FontSZ,data[index].str[0])
            drawGraph(index)
            
        case .dropDown : drawText(Tab1,py+TxtYoff,tColor,FontSZ,data[index].str[data[index].getInt32Value()])
        case .command  : drawText(Tab1,py+TxtYoff,tColor,FontSZ,data[index].str[0])
        case .string   : drawText(Tab1,py+TxtYoff,tColor,FontSZ, (delegate?.wgGetString(data[index].index))!)
        case .legend   : drawText(Tab1,py+TxtYoff,.yellow,FontSZ,data[index].str[0])
        case .option   : drawText(Tab1,py+TxtYoff,tColor,FontSZ, (delegate?.wgGetOptionString(data[index].index))!)

        case .line :
            UIColor.white.set()
            context?.setLineWidth(1)
            drawHLine(context!,0,bounds.width,py)
            py -= RowHT - 5
            
        case .color :
            let c = (delegate?.wgGetColor(data[index].index))!
            c.setFill()
            let r = CGRect(x:1, y:py-3, width:bounds.width-2, height:CGFloat(data[index].deltaValue)+2)
            UIBezierPath(rect:r).fill()
            py -= RowHT
            
        case .gap :
            py += CGFloat(data[index].deltaValue)
        }
        
        py += RowHT
    }
    
    func baseYCoord() -> CGFloat { return 5 } //  zorro (vc.view.bounds.height - 800) / 2 }
    
    override func draw(_ rect: CGRect) {
        if vc == nil { return }
        context = UIGraphicsGetCurrentContext()
        
        py = baseYCoord()
        for i in 0 ..< data.count { drawEntry(i) }
        
        UIColor.white.setStroke()
        UIBezierPath(rect:bounds).stroke()
    }
    
    func nextYCoord() -> CGFloat {
        py = baseYCoord()
        for i in 0 ..< data.count {
            switch(data[i].kind) {
            case .line  : py -= RowHT - 5
            case .color : py -= RowHT
            case .gap   : py += CGFloat(data[i].deltaValue)
            default : break
            }
            
            py += RowHT
        }
        
        return py
    }
    
    //MARK:-
    
    func float3Value() -> float3 {
        if focus == NONE { return float3() }
        return data[focus].valuePointerX.load(as: float3.self)
    }
    
    func update() -> Bool {
        if focus == NONE { return false }
        if deltaX == 0 && deltaY == 0 { return false } // marks end of session

        switch data[focus].kind {
        case .float3Single :  // hardwired to .z field of float3
            var v:float3 = float3Value()
            v.z = fClamp2(v.z + deltaX * data[focus].deltaValue, data[focus].mRange)
            data[focus].valuePointerX.storeBytes(of:v, as:float3.self)
        case .float3Dual :   // hardwired to .xy fields of float3
            var v:float3 = float3Value()
            v.x = fClamp2(v.x + deltaX * data[focus].deltaValue, data[focus].mRange)
            v.y = fClamp2(v.y + deltaY * data[focus].deltaValue, data[focus].mRange)
            data[focus].valuePointerX.storeBytes(of:v, as:float3.self)
        default :
            if data[focus].isValueWidget() {
                let valueX = fClamp2(data[focus].getFloatValue(0) + deltaX * data[focus].deltaValue, data[focus].mRange)
                data[focus].valuePointerX.storeBytes(of:valueX, as:Float.self)
                
                if data[focus].kind == .dualFloat {
                    let valueY = fClamp2(data[focus].getFloatValue(1) + deltaY * data[focus].deltaValue, data[focus].mRange)
                    data[focus].valuePointerY.storeBytes(of:valueY, as:Float.self)
                }
            }
            else { return false }
        }
        
        delegate?.wgCommand(data[focus].cmd)
        setNeedsDisplay()
        return true
    }
    
    func moveFocus(_ dir:Int) {
        if focus == NONE || data.count < 2 { return }
        
        while true {
            focus += dir
            if focus >= data.count { focus = 0 } else if focus < 0 { focus = data.count-1 }
            if [ .singleFloat, .dualFloat, .float3Dual, .float3Single ].contains(data[focus].kind) { break }
        }
        
        setNeedsDisplay()
    }
    
    //MARK:-
    
    func stopChanges() { deltaX = 0; deltaY = 0 }
    
    func focusMovement(_ pt:CGPoint) {
        if focus == NONE { return }
        
        if pt.x == 0 && pt.y == 0 { // panning just ended
            stopChanges()
            return
        }
        
        let denom:Float = 1000
        deltaX =  Float(pt.x) / denom
        deltaY = -Float(pt.y) / denom
        
        if data[focus].kind == .singleFloat {  // largest delta runs the show
            if fabs(deltaY) > fabs(deltaX) { deltaX = deltaY }
        }
        
        if !data[focus].fastEdit {
            let den = Float((data[focus].kind == .move) ? 10 : 100)
            deltaX /= den
            deltaY /= den
        }
        
        setNeedsDisplay()
    }
    
    // MARK:
    
    func optionSelectPopup(_ ident:Int, _ title:String, _ message:String, _ options:[String]) {
        let alert = UIAlertController(title:title, message:message, preferredStyle: .actionSheet)
        
        func attrString(_ text:String, _ key:String) {
            let a1 = NSMutableAttributedString(string: text,
                                               attributes: [kCTFontAttributeName as NSAttributedStringKey:UIFont(name: "Helvetica", size: 24.0)!])
            alert.setValue(a1, forKey: key)
        }
        
        attrString(title,"attributedTitle")
        attrString(message,"attributedMessage")
        
        for i in 0 ..< options.count {
            let sa = UIAlertAction(title: options[i], style: .default) { action -> Void in self.wgOptionSelected(ident,i) }
            alert.addAction(sa)
        }
        
        alert.view.subviews[0].subviews[0].backgroundColor = UIColor.darkGray
        alert.view.tintColor = UIColor.white
        alert.popoverPresentationController?.sourceView = self
        vc.present(alert, animated: true, completion: nil)
    }
    
    //MARK:-
        
    func shouldMemorizeFocus() -> Bool {
        if focus == NONE { return false }
        return [ .singleFloat, .dualFloat, .option, .move ].contains(data[focus].kind)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        var pt = CGPoint()
        for touch in touches { pt = touch.location(in: self) }
        stopChanges()
        
        if focus == NONE { vc.removeAllFocus() }
        
        if shouldMemorizeFocus() { previousFocus = focus }
        
        for i in 0 ..< data.count { // move Focus to this entry?
            if [ .singleFloat, .dualFloat, .command, .option, .dropDown, .move, .float3Dual, .float3Single ].contains(data[i].kind) &&
                pt.y >= data[i].yCoord && pt.y < data[i].yCoord + RowHT {
                focus = i
                setNeedsDisplay()
                return
            }
        }
    }
    
    override func touchesMoved(     _ touches: Set<UITouch>, with event: UIEvent?) { touchesBegan(touches, with:event) }
    override func touchesCancelled( _ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with:event) }
    
    override func touchesEnded( _ touches: Set<UITouch>, with event: UIEvent?) {
        if focus == NONE { return }
        
        if data[focus].kind == .command {
            delegate?.wgCommand(data[focus].cmd)
            
            focus = NONE
            if previousFocus != NONE { focus = previousFocus }
            
            setNeedsDisplay()
            return
        }
        
        if data[focus].kind == .option {
            let p = data[focus]
            optionSelectPopup(p.index, p.str[0], p.str[1], Array(p.str[2 ..< p.str.count]))
            setNeedsDisplay()
        }
        
        stopChanges()
    }
    
    func functionNameChanged() {}
    
    func fClamp2(_ v:Float, _ range:float2) -> Float {
        if v < range.x { return range.x }
        if v > range.y { return range.y }
        return v
    }
    
}

// MARK:

func drawLine(_ context:CGContext, _ p1:CGPoint, _ p2:CGPoint) {
    context.beginPath()
    context.move(to:p1)
    context.addLine(to:p2)
    context.strokePath()
}

func drawVLine(_ context:CGContext, _ x:CGFloat, _ y1:CGFloat, _ y2:CGFloat) { drawLine(context,CGPoint(x:x,y:y1),CGPoint(x:x,y:y2)) }
func drawHLine(_ context:CGContext, _ x1:CGFloat, _ x2:CGFloat, _ y:CGFloat) { drawLine(context,CGPoint(x:x1, y:y),CGPoint(x: x2, y:y)) }

func drawRect(_ context:CGContext, _ r:CGRect) {
    context.beginPath()
    context.addRect(r)
    context.strokePath()
}

func drawFilledCircle(_ context:CGContext, _ center:CGPoint, _ diameter:CGFloat, _ color:CGColor) {
    context.beginPath()
    context.addEllipse(in: CGRect(x:CGFloat(center.x - diameter/2), y:CGFloat(center.y - diameter/2), width:CGFloat(diameter), height:CGFloat(diameter)))
    context.setFillColor(color)
    context.fillPath()
}

//MARK:-

var fntSize:CGFloat = 0
var txtColor:UIColor = .clear
var textFontAttributes:NSDictionary! = nil

func drawText(_ x:CGFloat, _ y:CGFloat, _ color:UIColor, _ sz:CGFloat, _ str:String) {
    if sz != fntSize || color != txtColor {
        fntSize = sz
        txtColor = color
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = NSTextAlignment.left
        let font = UIFont.init(name: "Helvetica", size:sz)!
        
        textFontAttributes = [
            NSAttributedStringKey.font: font,
            NSAttributedStringKey.foregroundColor: color,
            NSAttributedStringKey.paragraphStyle: paraStyle,
        ]
    }
    
    str.draw(in: CGRect(x:x, y:y, width:800, height:100), withAttributes: textFontAttributes as? [NSAttributedStringKey : Any])
}


