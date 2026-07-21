# ADR 001: Python Bridge Architecture

## Status
Superseded (2026-07). `PersistentLocationBridge` was removed (commit `c1d550b`);
the app now uses the subprocess bridge (`DevLocationBridge`) only. This ADR is
retained for historical decision provenance. Do not reintroduce a persistent
bridge without a new ADR. See ADR 004 for the current security posture.

## Context
PathChanger needs to communicate with iOS devices to simulate GPS locations. The pymobiledevice3 library provides this capability but is Python-based. We needed to decide between:

1. **Native Swift implementation** - Rewrite pymobiledevice3 functionality in Swift
2. **Python subprocess** - Call Python scripts for each operation
3. **Persistent Python bridge** - Maintain a long-running Python process for communication

## Decision
We chose a **hybrid approach** with both subprocess and persistent bridge options:

- `DevLocationBridge` - Traditional subprocess execution for compatibility
- `PersistentLocationBridge` - Long-running Python process for high-performance scenarios

## Rationale

### Why not native Swift?
- pymobiledevice3 is complex (~50k lines) and actively maintained
- Would require significant reverse engineering effort
- Security updates would need to be manually ported
- Time-to-market would be significantly longer

### Why persistent bridge for performance mode?
- Subprocess creation overhead is ~50-100ms per call
- For joystick mode (10 updates/second), this adds unacceptable latency
- Persistent bridge reduces overhead to ~5-10ms per operation

### Why keep subprocess as option?
- More reliable for one-off operations
- Easier to debug and monitor
- Better isolation for security-sensitive operations
- Fallback if persistent bridge fails

## Consequences

### Positive
- Fast location updates for real-time simulation
- Leverages well-tested pymobiledevice3 library
- Flexibility to choose appropriate method per use case

### Negative
- Requires Python installation on user's machine
- Two code paths to maintain
- Potential version compatibility issues with pymobiledevice3

## Alternatives Considered
- libimobiledevice (C library) - Less feature-complete than pymobiledevice3
- Running Python in-process via embedded interpreter - Too complex
- WebSocket-based communication - Overkill for local IPC
