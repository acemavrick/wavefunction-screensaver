//
//  WaveView.swift
//  Wavefunction Screensaver
//
//  Created by acemavrick on 6/28/25.
//

import Foundation
import ScreenSaver

class WaveView: ScreenSaverView {
    var x: Int = 0;
    var size, y : Int;
    
    override init?(frame: NSRect, isPreview: Bool) {
        size = Int.random(in: 50...300)
        y = Int.random(in: 0...(Int(frame.height) - size))
        super.init(frame: frame, isPreview: isPreview)
    }
    
    @available(*, unavailable)
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: NSRect) {
        // draw a single frame
        NSColor.orange.set()
        rect.fill()
        
        // draw another rectangle
        NSColor.yellow.set()
        NSRect(x: x, y: y, width: size, height: size).fill()
    }
    
    override func animateOneFrame() {
        x += 50
        if x > Int(bounds.width) {
            x = -100
        }
        setNeedsDisplay(bounds)
    }
    
    override func startAnimation() {
        super.startAnimation()
    }
    
    override func stopAnimation() {
        super.stopAnimation()
    }
}
