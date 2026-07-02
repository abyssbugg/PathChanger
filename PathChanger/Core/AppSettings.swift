//
//  AppSettings.swift
//  PathChanger
//
//  Centralized configuration management with security-conscious defaults
//

import Foundation

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings(defaults: .standard)

    private let defaults: UserDefaults

    // MARK: - Timeout Settings (SEC-02 Fix)

    @Published var commandTimeout: Double {
        didSet {
            let clamped = Self.clampCommandTimeout(commandTimeout)
            if commandTimeout != clamped {
                commandTimeout = clamped
                return
            }
            defaults.set(commandTimeout, forKey: "commandTimeout")
        }
    }

    private static func clampCommandTimeout(_ value: Double) -> Double {
        min(max(value, AppConstants.Timeout.commandTimeoutMin), AppConstants.Timeout.commandTimeoutMax)
    }

    private static func clampTunnelTimeout(_ value: Double) -> Double {
        min(max(value, AppConstants.Timeout.tunnelTimeoutMin), AppConstants.Timeout.tunnelTimeoutMax)
    }

    private static func clampRateLimitCapacity(_ value: Int) -> Int {
        min(max(value, AppConstants.RateLimiting.minCapacity), AppConstants.RateLimiting.maxCapacity)
    }

    private static func clampRateLimitRefillRate(_ value: Double) -> Double {
        min(max(value, AppConstants.RateLimiting.minRefillRate), AppConstants.RateLimiting.maxRefillRate)
    }

    @Published var tunnelTimeout: Double {
        didSet {
            let clamped = Self.clampTunnelTimeout(tunnelTimeout)
            if tunnelTimeout != clamped {
                tunnelTimeout = clamped
                return
            }
            defaults.set(tunnelTimeout, forKey: "tunnelTimeout")
        }
    }

    // MARK: - Rate Limiting Settings

    @Published var rateLimitCapacity: Int {
        didSet {
            let clamped = Self.clampRateLimitCapacity(rateLimitCapacity)
            if rateLimitCapacity != clamped {
                rateLimitCapacity = clamped
                return
            }
            defaults.set(rateLimitCapacity, forKey: "rateLimitCapacity")
        }
    }

    @Published var rateLimitRefillRate: Double {
        didSet {
            let clamped = Self.clampRateLimitRefillRate(rateLimitRefillRate)
            if rateLimitRefillRate != clamped {
                rateLimitRefillRate = clamped
                return
            }
            defaults.set(rateLimitRefillRate, forKey: "rateLimitRefillRate")
        }
    }

    // MARK: - Initialization

    init(defaults: UserDefaults) {
        self.defaults = defaults

        if defaults.object(forKey: "commandTimeout") != nil {
            self.commandTimeout = Self.clampCommandTimeout(defaults.double(forKey: "commandTimeout"))
        } else {
            self.commandTimeout = AppConstants.Timeout.defaultCommandTimeout
        }

        if defaults.object(forKey: "tunnelTimeout") != nil {
            self.tunnelTimeout = Self.clampTunnelTimeout(defaults.double(forKey: "tunnelTimeout"))
        } else {
            self.tunnelTimeout = AppConstants.Timeout.defaultTunnelTimeout
        }

        if defaults.object(forKey: "rateLimitCapacity") != nil {
            self.rateLimitCapacity = Self.clampRateLimitCapacity(defaults.integer(forKey: "rateLimitCapacity"))
        } else {
            self.rateLimitCapacity = AppConstants.RateLimiting.tokenBucketCapacity
        }

        if defaults.object(forKey: "rateLimitRefillRate") != nil {
            self.rateLimitRefillRate = Self.clampRateLimitRefillRate(defaults.double(forKey: "rateLimitRefillRate"))
        } else {
            self.rateLimitRefillRate = AppConstants.RateLimiting.tokenRefillRate
        }
    }

    // MARK: - Reset to Defaults

    func resetToDefaults() {
        commandTimeout = AppConstants.Timeout.defaultCommandTimeout
        tunnelTimeout = AppConstants.Timeout.defaultTunnelTimeout
        rateLimitCapacity = AppConstants.RateLimiting.tokenBucketCapacity
        rateLimitRefillRate = AppConstants.RateLimiting.tokenRefillRate
    }
}
