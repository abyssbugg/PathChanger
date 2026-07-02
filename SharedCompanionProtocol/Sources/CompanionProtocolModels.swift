import Foundation

/// Messages exchanged between the macOS host app and the iOS companion app.
public enum CompanionMessage: Codable, Sendable {
    case status(SpoofingStatus)
    case emergencyStop
    case ping
    case pong
    case locationUpdate(latitude: Double, longitude: Double)
    case connectionState(isConnected: Bool)
}

/// Current spoofing status payload shared by host and companion.
public struct SpoofingStatus: Codable, Sendable {
    public var isActive: Bool
    public var isPaused: Bool
    public var currentLatitude: Double?
    public var currentLongitude: Double?
    public var targetLatitude: Double?
    public var targetLongitude: Double?
    public var deviceName: String?
    public var mode: String
    public var speed: String
    public var routeProgress: Double?

    public init(
        isActive: Bool,
        isPaused: Bool,
        currentLatitude: Double?,
        currentLongitude: Double?,
        targetLatitude: Double?,
        targetLongitude: Double?,
        deviceName: String?,
        mode: String,
        speed: String,
        routeProgress: Double?
    ) {
        self.isActive = isActive
        self.isPaused = isPaused
        self.currentLatitude = currentLatitude
        self.currentLongitude = currentLongitude
        self.targetLatitude = targetLatitude
        self.targetLongitude = targetLongitude
        self.deviceName = deviceName
        self.mode = mode
        self.speed = speed
        self.routeProgress = routeProgress
    }
}
