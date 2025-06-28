//
//  WaveView.swift
//  Wavefunction Screensaver
//
//  Created by acemavrick on 6/28/25.
//

import Foundation
import ScreenSaver
import QuartzCore

class WaveView: ScreenSaverView {
    var x: CGFloat = 0
    var size, y: CGFloat
    var displayLink: CADisplayLink?
    var lastTimestamp: TimeInterval = 0
    let speed: CGFloat = 400.0 // points per second
    
    override init?(frame: NSRect, isPreview: Bool) {
        size = CGFloat.random(in: 50...300)
        y = CGFloat.random(in: 0...(frame.height - size))
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
        NSColor.green.set()
        NSRect(x: x, y: y, width: size, height: size).fill()
    }
    
    @objc func step(displayLink: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = displayLink.timestamp
            return
        }

        let oldRect = NSRect(x: x, y: y, width: size, height: size)

        var deltaTime = displayLink.timestamp - lastTimestamp
        lastTimestamp = displayLink.timestamp

        // cap delta time to prevent large jumps on lag
        if deltaTime > 0.1 {
            deltaTime = 1.0 / 60.0
        }

        x += speed * CGFloat(deltaTime)

        if x > bounds.width {
            size = CGFloat.random(in: 50...300)
            x = -size
            
            // ensure y-position is valid even with large sizes
            let yRange = 0...(max(0, bounds.height - size))
            y = CGFloat.random(in: yRange)
        }
        
        let newRect = NSRect(x: x, y: y, width: size, height: size)
        
        // redraw only the parts of the view that have changed
        setNeedsDisplay(oldRect.union(newRect))
    }
    
    override func startAnimation() {
        super.startAnimation()
        let screen = window?.screen ?? NSScreen.main
        displayLink = screen?.displayLink(target: self, selector: #selector(step(displayLink:)))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    override func stopAnimation() {
        super.stopAnimation()
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
    }
}
