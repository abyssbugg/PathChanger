//
//  AppSettings.swift
//  PathChanger
//
//  Centralized configuration management with security-conscious defaults
//

import Foundation

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Timeout Settings (SEC-02 Fix)
    
    @Published var commandTimeout: Double {
        didSet {
            let clamped = min(max(commandTimeout, AppConstants.Timeout.commandTimeoutMin), AppConstants.Timeout.commandTimeoutMax)
            defaults.set(clamped, forKey: "commandTimeout")
        }
    }
    
    @Published var tunnelTimeout: Double {
        didSet {
            let clamped = min(max(tunnelTimeout, AppConstants.Timeout.tunnelTimeoutMin), AppConstants.Timeout.tunnelTimeoutMax)
            defaults.set(clamped, forKey: "tunnelTimeout")
        }
    }
    
    // MARK: - Rate Limiting Settings
    
    @Published var rateLimitCapacity: Int {
        didSet {
            let clamped = min(max(rateLimitCapacity, AppConstants.RateLimiting.minCapacity), AppConstants.RateLimiting.maxCapacity)
            defaults.set(clamped, forKey: "rateLimitCapacity")
        }
    }
    
    @Published var rateLimitRefillRate: Double {
        didSet {
            let clamped = min(max(rateLimitRefillRate, AppConstants.RateLimiting.minRefillRate), AppConstants.RateLimiting.maxRefillRate)
            defaults.set(clamped, forKey: "rateLimitRefillRate")
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        let savedCommandTimeout = defaults.double(forKey: "commandTimeout")
        self.commandTimeout = savedCommandTimeout > 0 ? savedCommandTimeout : AppConstants.Timeout.defaultCommandTimeout
        
        let savedTunnelTimeout = defaults.double(forKey: "tunnelTimeout")
        self.tunnelTimeout = savedTunnelTimeout > 0 ? savedTunnelTimeout : AppConstants.Timeout.defaultTunnelTimeout
        
        let savedRateLimitCapacity = defaults.integer(forKey: "rateLimitCapacity")
        self.rateLimitCapacity = savedRateLimitCapacity > 0 ? savedRateLimitCapacity : AppConstants.RateLimiting.tokenBucketCapacity
        
        let savedRateLimitRefillRate = defaults.double(forKey: "rateLimitRefillRate")
        self.rateLimitRefillRate = savedRateLimitRefillRate > 0 ? savedRateLimitRefillRate : AppConstants.RateLimiting.tokenRefillRate
    }
    
    // MARK: - Reset to Defaults
    
    func resetToDefaults() {
        commandTimeout = AppConstants.Timeout.defaultCommandTimeout
        tunnelTimeout = AppConstants.Timeout.defaultTunnelTimeout
        rateLimitCapacity = AppConstants.RateLimiting.tokenBucketCapacity
        rateLimitRefillRate = AppConstants.RateLimiting.tokenRefillRate
    }
}
