//
//  Store.swift
//  Wavefunction Screensaver
//
//  Created by acemavrick on 6/29/25.
//  Based on JellyfishSaver.Store by Eskil Gjerde Sviggum
//  Refactored to use ScreenSaverDefaults for modern, safe settings storage.
//

import ScreenSaver

@MainActor
class Store: NSObject {
    
    private enum Keys {
        static let c = "wavefunction.c"
        static let dx = "wavefunction.dx"
        static let dt = "wavefunction.dt"
        static let damper = "wavefunction.damper"
        static let disturbanceCooldownMin = "wavefunction.disturbanceCooldownMin"
        static let disturbanceCooldownMax = "wavefunction.disturbanceCooldownMax"
        static let disturbanceDensityMin = "wavefunction.disturbanceDensityMin"
        static let disturbanceDensityMax = "wavefunction.disturbanceDensityMax"
        static let disturbanceRadiusMin = "wavefunction.disturbanceRadiusMin"
        static let disturbanceRadiusMax = "wavefunction.disturbanceRadiusMax"
        static let disturbanceStrengthMin = "wavefunction.disturbanceStrengthMin"
        static let disturbanceStrengthMax = "wavefunction.disturbanceStrengthMax"
        static let batterySaverMode = "wavefunction.batterySaverMode"
    }
    
    public static let defaultC: Float = 3.0
    public static let defaultDx: Float = 0.0005
    public static let defaultDt: Float = 0.00005
    public static let defaultDamper: Float = 0.9998
    public static let defaultDisturbanceCooldownMin: Int = 45
    public static let defaultDisturbanceCooldownMax: Int = 1000
    public static let defaultDisturbanceDensityMin: Int = 1
    public static let defaultDisturbanceDensityMax: Int = 3
    public static let defaultDisturbanceRadiusMin: Float = 1
    public static let defaultDisturbanceRadiusMax: Float = 3
    public static let defaultDisturbanceStrengthMin: Float = 1
    public static let defaultDisturbanceStrengthMax: Float = 3
    public static let defaultBatterySaverMode: Bool = false

    static let shared = Store()
    
    private let defaults: ScreenSaverDefaults
    
    private override init() {
        // You may want to replace "com.acemavrick.Wavefunction-Screensaver" with your actual bundle identifier from your project settings
        let bundleIdentifier = Bundle(for: type(of: self)).bundleIdentifier ?? "com.acemavrick.Wavefunction-Screensaver"
        self.defaults = ScreenSaverDefaults(forModuleWithName: bundleIdentifier)!
        super.init()
    }

    var c: Float {
        get {
            // Check if the value exists before returning, otherwise provide the default.
            if defaults.object(forKey: Keys.c) != nil {
                return defaults.float(forKey: Keys.c)
            } else {
                return Self.defaultC
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.c)
            defaults.synchronize()
        }
    }

    var dx: Float {
        get {
            if defaults.object(forKey: Keys.dx) != nil {
                return defaults.float(forKey: Keys.dx)
            } else {
                return Self.defaultDx
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.dx)
            defaults.synchronize()
        }
    }

    var dt: Float {
        get {
            if defaults.object(forKey: Keys.dt) != nil {
                return defaults.float(forKey: Keys.dt)
            } else {
                return Self.defaultDt
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.dt)
            defaults.synchronize()
        }
    }

    var damper: Float {
        get {
            if defaults.object(forKey: Keys.damper) != nil {
                return defaults.float(forKey: Keys.damper)
            } else {
                return Self.defaultDamper
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.damper)
            defaults.synchronize()
        }
    }

    var disturbanceCooldownMin: Int {
        get {
            if defaults.object(forKey: Keys.disturbanceCooldownMin) != nil {
                return defaults.integer(forKey: Keys.disturbanceCooldownMin)
            } else {
                return Self.defaultDisturbanceCooldownMin
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.disturbanceCooldownMin)
            defaults.synchronize()
        }
    }
    
    var disturbanceCooldownMax: Int {
        get {
            if defaults.object(forKey: Keys.disturbanceCooldownMax) != nil {
                return defaults.integer(forKey: Keys.disturbanceCooldownMax)
            } else {
                return Self.defaultDisturbanceCooldownMax
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.disturbanceCooldownMax)
            defaults.synchronize()
        }
    }
    
    var disturbanceDensityMin: Int {
        get {
            if defaults.object(forKey: Keys.disturbanceDensityMin) != nil {
                return defaults.integer(forKey: Keys.disturbanceDensityMin)
            } else {
                return Self.defaultDisturbanceDensityMin
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.disturbanceDensityMin)
            defaults.synchronize()
        }
    }
    
    var disturbanceDensityMax: Int {
        get {
            if defaults.object(forKey: Keys.disturbanceDensityMax) != nil {
                return defaults.integer(forKey: Keys.disturbanceDensityMax)
            } else {
                return Self.defaultDisturbanceDensityMax
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.disturbanceDensityMax)
            defaults.synchronize()
        }
    }
    
    var disturbanceRadiusMin: Float {
        get {
            if defaults.object(forKey: Keys.disturbanceRadiusMin) != nil {
                return defaults.float(forKey: Keys.disturbanceRadiusMin)
            } else {
                return Self.defaultDisturbanceRadiusMin
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.disturbanceRadiusMin)
            defaults.synchronize()
        }
    }
    
    var disturbanceRadiusMax: Float {
        get {
            if defaults.object(forKey: Keys.disturbanceRadiusMax) != nil {
                return defaults.float(forKey: Keys.disturbanceRadiusMax)
            } else {
                return Self.defaultDisturbanceRadiusMax
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.disturbanceRadiusMax)
            defaults.synchronize()
        }
    }
    
    var disturbanceStrengthMin: Float {
        get {
            if defaults.object(forKey: Keys.disturbanceStrengthMin) != nil {
                return defaults.float(forKey: Keys.disturbanceStrengthMin)
            } else {
                return Self.defaultDisturbanceStrengthMin
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.disturbanceStrengthMin)
            defaults.synchronize()
        }
    }
    
    var disturbanceStrengthMax: Float {
        get {
            if defaults.object(forKey: Keys.disturbanceStrengthMax) != nil {
                return defaults.float(forKey: Keys.disturbanceStrengthMax)
            } else {
                return Self.defaultDisturbanceStrengthMax
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.disturbanceStrengthMax)
            defaults.synchronize()
        }
    }
    
    var batterySaverMode: Bool {
        get {
            if defaults.object(forKey: Keys.batterySaverMode) != nil {
                return defaults.bool(forKey: Keys.batterySaverMode)
            } else {
                return Self.defaultBatterySaverMode
            }
        }
        set {
            defaults.set(newValue, forKey: Keys.batterySaverMode)
            defaults.synchronize()
        }
    }
}
