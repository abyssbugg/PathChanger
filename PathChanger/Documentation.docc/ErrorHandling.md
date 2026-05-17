# ``ErrorHandling``

A comprehensive guide to error handling patterns in PathChanger.

@Metadata {
    @PageImage(purpose: icon, source: "errorhandling-icon", alt: "Error handling icon")
    @PageKind(article)
}

## Overview

PathChanger uses a consistent, type-safe error handling approach with:

- **Custom Error Types**: Domain-specific errors conforming to `LocalizedError`
- **Async Throws**: Standard pattern for async operations
- **Result Types**: Used only for batch operations returning multiple outcomes
- **Optionals**: Used only when absence is a valid, non-error state

## Error Type Categories

### Device & Connection Errors

| Error Type | Module | Purpose |
|-----------|--------|---------|
| ``DeviceError`` | DeviceManager | Device discovery and connection failures |
| ``LocationInjectionError`` | DevLocationBridge | Location injection failures |
| ``PersistentBridgeError`` | PersistentLocationBridge | Persistent bridge process errors |
| ``PrivilegedCommandError`` | TunneldManager | Privileged command validation |

### Validation Errors

| Error Type | Module | Purpose |
|-----------|--------|---------|
| ``ValidationError`` | ArgumentSanitizer | Input validation failures |
| ``CommandValidationError`` | DevLocationBridge | Command structure validation |
| ``SubprocessSecurityError`` | DevLocationBridge | Subprocess security violations |

### Service Errors

| Error Type | Module | Purpose |
|-----------|--------|---------|
| ``QueueError`` | RateLimiter | Rate limiting queue errors |
| ``PythonResolverError`` | PythonPathResolver | Python dependency errors |

### Data Errors

| Error Type | Module | Purpose |
|-----------|--------|---------|
| ``GPXParserError`` | GPXParser | GPX file parsing failures |
| ``RouteLibraryError`` | RouteLibrary | Route storage operations |

## Usage Patterns

### Pattern 1: Async Throws (Default)

Use for all async operations that can fail:

```swift
func setLocation(_ coordinate: LocationCoordinate, for device: Device) async throws {
    guard coordinate.isValid else {
        throw ValidationError.invalidCoordinates(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }
    
    try await performLocationInjection(coordinate, device: device)
}
```

### Pattern 2: Optionals (Non-Error Absence)

Use when absence is a valid state, not an error:

```swift
// Cache lookup - nil means "not cached", not an error
func getCachedDevice(udid: String) -> Device? {
    guard let entry = cache[udid] else { return nil }
    return entry.device
}
```

### Pattern 3: Result Type (Batch Operations)

Use only when returning multiple outcomes from a single operation:

```swift
func injectToAll(devices: [Device]) async -> [String: Result<Void, Error>] {
    var results: [String: Result<Void, Error>] = [:]
    
    for device in devices {
        do {
            try await setLocation(coordinate, for: device)
            results[device.id] = .success(())
        } catch {
            results[device.id] = .failure(error)
        }
    }
    
    return results
}
```

## Error Handling Best Practices

### 1. Always Use Typed Errors

```swift
// GOOD: Specific error type
throw LocationInjectionError.deviceNotFound

// AVOID: Generic error
throw NSError(domain: "...", code: 1)
```

### 2. Implement LocalizedError

```swift
enum MyError: Error, LocalizedError {
    case operationFailed(reason: String)
    
    var errorDescription: String? {
        switch self {
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        return "Please try again or contact support."
    }
}
```

### 3. Use Error Classification for Recovery

```swift
func handleError(_ error: Error) -> ErrorAction {
    switch error {
    case let deviceError as DeviceError:
        return actionForDeviceError(deviceError)
    case let injectionError as LocationInjectionError:
        return actionForInjectionError(injectionError)
    default:
        return .logAndContinue
    }
}
```

### 4. Log Errors with Context

```swift
do {
    try await riskyOperation()
} catch {
    Logger.error(
        "Operation failed: \(error.localizedDescription)",
        category: .device,
        metadata: ["deviceId": device.id]
    )
    throw error
}
```

## Error Recovery Strategies

The ``ReliabilityManager`` implements automatic error recovery with:

- **Exponential Backoff**: Delays between retry attempts
- **Circuit Breaker**: Prevents cascading failures
- **Error Classification**: Different strategies per error type

```swift
let strategy = ReconnectionStrategy(
    maxAttempts: 5,
    initialDelaySeconds: 1.0,
    maxDelaySeconds: 30.0,
    backoffMultiplier: 2.0,
    jitterFactor: 0.1
)
```

## Testing Error Paths

Always test error conditions:

```swift
func testInvalidCoordinatesThrows() async throws {
    let bridge = DevLocationBridge()
    let invalidCoord = LocationCoordinate(latitude: 999, longitude: 999)
    
    do {
        try await bridge.setLocation(invalidCoord, for: mockDevice)
        XCTFail("Should throw ValidationError")
    } catch let error as ValidationError {
        XCTAssertEqual(error, .invalidCoordinates(latitude: 999, longitude: 999))
    }
}
```

## See Also

- ``ReliabilityManager``
- ``ErrorHandler``
- ``Logger``
