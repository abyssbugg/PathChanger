# ADR 002: Actor-Based Device Caching

## Status
Accepted

## Context
Device discovery involves multiple async operations (USB enumeration, WiFi scanning) that can be slow. We needed a caching strategy that:

1. Reduces redundant device queries
2. Handles concurrent access safely
3. Provides fresh data when needed
4. Integrates well with SwiftUI's reactive model

## Decision
Implement device caching using **Swift Actors** with time-to-live (TTL) based invalidation.

```swift
actor DeviceCache {
    private var cache: [String: CacheEntry<Device>] = [:]
    private let ttl: TimeInterval = 60.0
    
    func get(_ udid: String) async -> Device? { ... }
    func set(_ device: Device) async { ... }
    func invalidateAll() async { ... }
}
```

## Rationale

### Why Actors?
- Built-in thread safety without manual locking
- Clear isolation boundaries for cache state
- Native Swift concurrency integration
- Compiler-enforced data race prevention

### Why TTL-based invalidation?
- Simple and predictable behavior
- Balances freshness vs performance
- Easy to tune per use case
- No complex dependency tracking needed

### Cache Invalidation Strategy
- TTL expiration (60s default for device info)
- Manual invalidation on tunnel state changes
- Bulk invalidation on disconnect events

## Consequences

### Positive
- Thread-safe by construction
- Clean integration with async/await
- Predictable memory usage
- Easy to reason about cache behavior

### Negative
- Requires careful TTL tuning
- Potential for stale data in edge cases
- Actor isolation can complicate some access patterns

## Metrics
- Cache hit rate: ~80% in typical use
- Memory overhead: <1MB for 50 devices
- Latency reduction: 90% for cached queries
