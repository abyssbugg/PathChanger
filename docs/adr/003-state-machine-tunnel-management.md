# ADR 003: State Machine for Tunnel Management

## Status
Superseded in part (2026-07). The finite-state-machine decision stands, but the
code below has drifted: the current `TunnelState` (`PathChanger/Device/TunnelState.swift`)
has no `externallyManaged` case and the `starting`/`running` shapes differ from
this document. Treat the concrete enum/event snippets here as historical; consult
the source for the authoritative state model.

## Context
Tunnel lifecycle management is complex with multiple states, transitions, and error conditions:

- Idle → Starting → Running → Stopping → Idle
- Error states and recovery
- External tunnel detection
- Multiple tunnel modes (USB, WiFi, Daemon)

Ad-hoc state management led to bugs and race conditions.

## Decision
Implement tunnel state management using a **finite state machine** pattern with:

1. Explicit state enumeration
2. Event-driven transitions
3. Side effects separated from state logic
4. State machine observation via Combine

```swift
enum TunnelState: Equatable {
    case idle
    case starting(mode: TunnelMode)
    case running(mode: TunnelMode)
    case stopping
    case error(String)
    case externallyManaged(mode: TunnelMode)
}

enum TunnelEvent {
    case startRequested(mode: TunnelMode)
    case processLaunched(pid: Int32)
    case healthCheckPassed
    case healthCheckFailed
    case stopRequested
    // ...
}
```

## Rationale

### Why State Machine?
- Eliminates impossible states (e.g., "running while idle")
- Makes all valid transitions explicit
- Easier to reason about and test
- Clear separation of state logic and side effects

### Why Combine for Observation?
- Native integration with SwiftUI
- Debouncing for UI stability
- Easy subscription management
- Type-safe event handling

### State Transition Examples
```
idle --[startRequested]--> starting
starting --[processLaunched]--> running
running --[healthCheckFailed]--> error
error --[recoveryAttempted]--> starting
```

## Consequences

### Positive
- Eliminated race conditions in tunnel management
- Clear visualization of all states and transitions
- Comprehensive test coverage of state logic
- Predictable behavior under all conditions

### Negative
- More code than ad-hoc approach initially
- Learning curve for contributors
- Some transitions require careful event ordering

## Monitoring
- State transitions are logged for debugging
- Health monitor triggers events automatically
- Metrics track time spent in each state
