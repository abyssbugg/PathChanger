# PathChanger UI, Models, Simulation, GPX, and Map-Layer Audit
## 1. Executive summary
PathChanger is a local macOS application that controls a paired iOS device through a tunnel and imports user-selected GPX route files.
This audit covered all 39 assigned Swift files on `feat/ui-redesign` as they existed in the working tree, including the uncommitted UI changes.
Overall scoped risk posture: **Medium**.
No Critical or High finding was supported by the inspected evidence or the local, single-user deployment model.
The principal risk is unbounded, synchronous GPX parsing and route expansion, which can exhaust memory or stall the main actor after a user imports a crafted or accidentally extreme route.
Other confirmed issues affect GPX data integrity, privacy disclosure accuracy, legacy location-data retention, and redesign controls that persist state without changing behavior.
The parser explicitly disables external entity resolution at `PathChanger/GPX/GPXParser.swift:L268-L271`; no XXE finding is reported.
Imported strings are rendered through SwiftUI `Text`, not an HTML/template interpreter; no rendered-content injection sink was found in scope.
Finding totals: **Critical 0, High 0, Medium 1, Low 5, Info 1**.
Immediate actions (48h): cap GPX bytes/points/interpolation output and move parsing off the main actor.
Within 7 days: enforce coordinate validation at parse time and replace the parser's implicit “last object” association with explicit element context.
Within 30 days: correct privacy text and legacy-file retention, then remove or wire the redesign's inert controls and retired components.

## 2. Threat model
### System summary
The scoped code presents the macOS UI, stores favorite/history/route coordinates, parses and exports GPX, advances simulated movement, and surfaces tunnel/device state. Primary assets are the integrity of the coordinate applied to the selected paired device, availability of the desktop app, the user's precise location history/routes/favorites, device identity displayed in the UI, and truthful safety/privacy status.

Actors are the local authenticated macOS user, another same-user process with access to the app's files/defaults, a person who supplies a GPX file for the user to import, Apple platform map/search services, and the already-paired iOS device. There is no multi-tenant or anonymous server surface in this scope.

Data classes include precise coordinates, named places and route history (sensitive personal data), iOS device names/versions/identifiers (internal device metadata), GPX metadata supplied by a file author (untrusted), and ordinary UI preferences.

### Entry points
- User-selected `.gpx`/XML files enter through `SimulationView.fileImporter` and `RouteLibraryManager.importGPX` (`PathChanger/UI/SimulationView.swift:L77-L82`, `PathChanger/UI/SimulationView.swift:L872-L890`, `PathChanger/GPX/RouteLibrary.swift:L245-L267`).
- Manually entered/map-derived coordinates enter through `SimulationView` and `ModeControlPanel`; those paths check `LocationCoordinate.isValid` before setting a target (`PathChanger/UI/SimulationView.swift:L792-L839`, `PathChanger/UI/Components/ModeControlPanel.swift:L338-L357`).
- Place-search text enters through `LocationSearchService` from the sidebar (`PathChanger/UI/Components/CollapsibleSidebar.swift:L180-L193`).
- App-managed coordinate data is read from UserDefaults and JSON under Application Support, with one-shot copies from legacy Documents paths (`PathChanger/Models/LocationFavorites.swift:L109-L138`, `PathChanger/Models/LocationHistoryStore.swift:L45-L77`, `PathChanger/GPX/RouteLibrary.swift:L142-L173`).
- SwiftUI commands and redesigned controls mutate `AppState` and initiate simulation/tunnel operations (`PathChanger/PathChangerApp.swift:L90-L126`, `PathChanger/UI/Components/PrimaryActionPill.swift:L75-L113`).

### Trust boundaries
- Untrusted GPX bytes → `XMLParser` → in-memory GPX objects → persisted `SavedRoute` → route interpolation → device-location bridge.
- Local user input/search query → MapKit-backed search/map services → returned location metadata → target coordinate.
- Legacy `~/Documents/PathChanger` files → Application Support copy → retained duplicate in Documents.
- UI state/preferences → `AppState`/simulation engine → paired-device location side effect.

### Abuse cases
1. A supplied GPX contains enough points or near-100 km segments to stall or terminate PathChanger during import/start; user selection and route start are required, detection is immediate but cleanup may require deleting persisted route data.
2. A malformed GPX supplies out-of-range coordinates; the parser persists them and downstream layers silently drop, miscalculate, or display them.
3. Nested GPX metadata is deliberately ordered to overwrite the wrong object name/description, reducing route integrity.
4. A local process or synced Documents store retains old precise route/history data after the app migrates to Application Support.
5. A user relies on “all processing happens locally” while using service-backed map/search functionality.
6. A user relies on the “Safe Mode” switch or map preferences even though the values have no behavioral consumers.
7. A user invokes the documented Command-L “Set Location” action, but it only writes unread state and produces no presentation.
8. A maintainer re-mounts a superseded view or modifies one of two divergent control implementations, reintroducing inconsistent validation or execution semantics.

## 3. Methodology notes
All assigned files were opened: 24 under `PathChanger/UI`, 7 under `PathChanger/Models`, 3 under `PathChanger/Simulation`, 2 under `PathChanger/GPX`, `PathChanger/MapLayer/MapService.swift`, `PathChanger/PathChangerApp.swift`, and `PathChanger/AppDelegate.swift`.

Pass A mapped file import, map/search, persistence, UI-command, and paired-device side-effect boundaries. Pass B found no authentication/session implementation in scope; local-user and device-pairing controls are outside these files. Pass C reviewed XML parsing, coordinate parsing, XML writing, SwiftUI rendering, and subprocess diagnostics in the UI. Pass D found no cryptographic implementation or embedded secret in scope. Pass E traced coordinates, route/history persistence, pairing/diagnostic presentation, and privacy text. Pass F reviewed optionals, timer/session handling, main-actor work, persistence errors, and route mathematics. Pass G found no dependency declarations in scope. Pass H reviewed startup/onboarding/settings behavior but not entitlements or packaging, which were outside scope. Pass I used repository-wide exact-symbol reference searches to distinguish production reachability, test-only code, and preview-only code. Pass J evaluated the GPX-to-persistence-to-interpolation chain. Pass K provides regression invariants below.

No builds, tests, dependency installation, Git mutation, or source edits were performed. This is a static, read-only diagnostic audit. The only created file is this report.

Assumptions: the user intentionally chooses files through the macOS importer; the app runs under the local user's account; no untrusted remote party can invoke import without user interaction; MapKit/search service behavior and `LocationSearchService` internals beyond the assigned scope were not audited; logging implementation, device bridge cancellation, entitlements, and sandbox configuration were outside scope.

## 4. Critical & High findings
No Critical or High finding was supported.

## 5. Medium findings
### [MEDIUM] Unbounded GPX import and interpolation can exhaust memory or block the main actor
- **ID**: VULN-001
- **Category**: Vulnerability | Design flaw
- **CWE / OWASP / ASVS**: CWE-400 Uncontrolled Resource Consumption; CWE-770 Allocation of Resources Without Limits or Throttling
- **Location**: `PathChanger/GPX/GPXParser.swift:L252-L271`, `PathChanger/GPX/GPXParser.swift:L309-L313`, `PathChanger/GPX/RouteLibrary.swift:L126-L127`, `PathChanger/GPX/RouteLibrary.swift:L245-L267`, `PathChanger/Simulation/RouteInterpolator.swift:L18-L41`, `PathChanger/Simulation/RouteInterpolator.swift:L54-L72`
- **Evidence**:
  - Snippet: `let data = try Data(contentsOf: fileURL)` loads the complete selected file; delegate callbacks append every parsed point to arrays; no byte, point, segment, metadata-text, or aggregate-route limit is checked.
  - Snippet: `let steps = max(1, Int(duration / speed.updateInterval))` followed by `for stepIndex in 0..<steps` allocates a point for every update interval and appends every segment into one `allPoints` array.
  - Data flow: selected file URL → full `Data` → `XMLParser` arrays → `SavedRoute.coordinates` → `RouteInterpolator.interpolateRoute` → potentially much larger in-memory coordinate array.
  - Control flow: `RouteLibraryManager` is `@MainActor` (`PathChanger/GPX/RouteLibrary.swift:L126-L127`), and both `importGPX` methods perform synchronous file read/parse/distance calculation before returning; their `async` signatures do not move that work off the main actor.
  - Quantification: the per-segment guard permits any distance below 100,000 m. At walking speed (1.4 m/s, 1 s interval), one approximately 99 km segment expands to roughly 70,700 points; the number of segments is unbounded.
- **Description**: Streaming XML parsing avoids a DOM but does not bound retained data. Import also runs synchronously on the main actor. A route with many raw points can consume memory during parsing/persistence; a smaller route with many long-but-allowed segments can expand by orders of magnitude when playback is prepared.
- **Preconditions**: the local user selects a malicious or accidentally extreme GPX file. Interpolation amplification additionally requires loading/starting that route.
- **Impact**: availability loss of the PathChanger process, frozen UI, memory pressure affecting the Mac, and possible repeated startup degradation if a very large route was persisted before failure. No confidentiality or cross-user impact is established.
- **Exploitability analysis**: an attacker must persuade the user to import a file; no authentication bypass or remote invocation was found. Constructing an extreme but syntactically valid route is low complexity. The blast radius is one local app process and its current workflow, which limits severity to Medium.
- **Why scanners may miss this**: each allocation is individually ordinary; the risk emerges from the composition of unlimited XML point retention, main-actor execution, per-segment temporal interpolation, and aggregate appends.
- **Chaining**: BUG-001 allows malformed coordinate objects into the same persistence pipeline, but coordinate rejection alone does not mitigate resource exhaustion.
- **Recommended fix** (preferred + alternatives):
  - Enforce a maximum input byte size before `Data(contentsOf:)`, maximum metadata text length, maximum waypoint/track/route point count, maximum segment count, and maximum total interpolated points.
  - Parse from a bounded stream/background task and publish only the result back on `MainActor`; keep persistence mutation on `MainActor`.
  - Replace precomputed per-tick arrays with lazy distance/progress interpolation, or preflight the calculated aggregate point count with overflow-safe arithmetic and reject oversized routes.
  - Reject the import with a specific, user-visible error before persisting partial data.
  - Add tests at each limit and one multi-segment amplification test; assert peak output count is bounded independently of source geometry.
- **Incorrect fixes to avoid**: relying only on `XMLParser` streaming; raising the 100 km segment cap; checking only raw file bytes while retaining unlimited expanded points; dispatching the same unbounded work to a background queue without caps.
- **Residual risk after fix**: valid files near the chosen cap can still consume noticeable resources; telemetry and cancellation should cover long-running imports.
- **Priority / SLA suggestion**: Wave 1, this sprint.
- **Confidence**: CONFIRMED
- **Effort**: M

## 6. Low / Info
### [LOW] GPX coordinates bypass the model's available bounds validation
- **ID**: BUG-001
- **Category**: Bug | Design flaw
- **CWE / OWASP / ASVS**: CWE-20 Improper Input Validation
- **Location**: `PathChanger/GPX/GPXParser.swift:L339-L366`, `PathChanger/Models/LocationCoordinate.swift:L11-L24`, `PathChanger/Models/LocationCoordinate.swift:L47-L66`, `PathChanger/GPX/RouteLibrary.swift:L55-L77`, `PathChanger/UI/SimulationView.swift:L872-L886`
- **Evidence**:
  - Snippet: each GPX point uses `Double.init` and then the unchecked `LocationCoordinate(latitude:longitude:)`.
  - The type provides both `isValid` and a throwing validated initializer, but the parser calls neither.
  - Data flow: GPX `lat`/`lon` attributes → unchecked coordinate → unvalidated route distance calculation → saved route → `appState.loadRoute`.
- **Description**: finite but out-of-range latitude/longitude values are accepted and persisted. Downstream code is inconsistent: `SavedRoute` calculates trigonometric distance without validation, while `RouteInterpolator` silently filters invalid points (`PathChanger/Simulation/RouteInterpolator.swift:L18-L23`).
- **Preconditions**: user imports a GPX containing numeric but out-of-range coordinates.
- **Impact**: route names/counts can appear imported while geometry is silently altered or discarded; distance can become nonsensical; invalid coordinates can reach MapKit-facing presentation. Device injection is partially protected because interpolation filters invalid points.
- **Exploitability analysis**: user interaction is required and impact is local data integrity/availability, not privilege escalation.
- **Why scanners may miss this**: the model has validation APIs, but the parser uses a different initializer and downstream layers apply inconsistent policies.
- **Chaining**: amplifies VULN-001's malformed-input path but is not needed for its resource exhaustion.
- **Recommended fix** (preferred + alternatives):
  - Construct every GPX coordinate with `init(validatedLatitude:validatedLongitude:)`; fail the import with element/point context on the first invalid coordinate, or use a documented bounded skip policy with a rejected-point count.
  - Validate decoded persisted routes/favorites/history before use and before export.
  - Add boundary, non-finite, and mixed-validity route tests.
- **Incorrect fixes to avoid**: clamping coordinates silently; filtering only at simulation time; validating only the first and last route points.
- **Residual risk after fix**: geometrically valid coordinates can still represent implausible jumps; route-size and segment policies remain necessary.
- **Priority / SLA suggestion**: Wave 1, this sprint.
- **Confidence**: CONFIRMED
- **Effort**: S

### [LOW] Context-free XML state corrupts nested GPX metadata and route-point names
- **ID**: BUG-002
- **Category**: Bug
- **CWE / OWASP / ASVS**: CWE-20 Improper Input Validation; CWE-1164 Irrelevant Code (unused unsupported-version path is related hygiene)
- **Location**: `PathChanger/GPX/GPXParser.swift:L329-L333`, `PathChanger/GPX/GPXParser.swift:L374-L403`, `PathChanger/GPX/GPXParser.swift:L447-L447`, `PathChanger/GPX/GPXParser.swift:L526-L536`, `PathChanger/GPX/GPXParser.swift:L579-L580`
- **Evidence**:
  - Snippet: every start element resets one global `currentText`; every `<name>` is assigned according only to whether any route/track exists or whether the GPX already has a waypoint.
  - The writer emits `<author><name>…</name></author>`, but on reparse the child `<name>` is assigned to `GPXFile.name`, then `currentText` is cleared before `</author>`, leaving the author empty.
  - While a route is open, a route-point `<name>` is assigned to `currentRoute?.name`; `GPXRoutePoint.name` is never populated even though the writer emits it.
  - Control flow has no element stack or explicit current waypoint/track-point/route-point object.
- **Description**: the parser associates leaf content with whichever broad object happens to be non-nil, not with the XML parent path. Valid nested GPX emitted by the project's own writer does not round-trip.
- **Preconditions**: import or round-trip a GPX containing nested author data, route-point names, or noncanonical element ordering.
- **Impact**: metadata loss, route-name overwrite, incorrect labels, and inability to trust import/export fidelity. SwiftUI's text rendering prevents this from becoming markup injection in the inspected UI.
- **Exploitability analysis**: a file author can influence which labels are overwritten, but there is no code execution or authorization impact.
- **Why scanners may miss this**: each delegate callback is type-correct; the defect depends on XML nesting and ordering across callbacks.
- **Chaining**: mislabeled routes can make an operator select the wrong route, but device execution still requires local user action.
- **Recommended fix** (preferred + alternatives):
  - Maintain an element stack and explicit current objects for waypoint, track point, and route point; dispatch leaf text by full parent path.
  - Validate the GPX root namespace/version and use the currently unused `unsupportedVersion` error.
  - Add writer→parser round-trip tests covering metadata author, waypoint fields, route-point names, multiple segments, and reordered valid elements.
- **Incorrect fixes to avoid**: adding more “last element” conditionals; special-casing author without fixing the general stack model.
- **Residual risk after fix**: unsupported GPX extensions will still need a documented ignore policy.
- **Priority / SLA suggestion**: Wave 1, this sprint.
- **Confidence**: CONFIRMED
- **Effort**: M

### [LOW] Onboarding overstates local-only processing despite map/search service boundaries
- **ID**: DESIGN-001
- **Category**: Design flaw
- **CWE / OWASP / ASVS**: CWE-359 Exposure of Private Personal Information to an Unauthorized Actor (privacy-disclosure mismatch; no unauthorized disclosure is proven)
- **Location**: `PathChanger/UI/OnboardingView.swift:L313-L318`, `PathChanger/UI/SimulationView.swift:L88-L93`, `PathChanger/UI/Components/CollapsibleSidebar.swift:L19-L20`, `PathChanger/UI/Components/CollapsibleSidebar.swift:L180-L193`, `PathChanger/MapLayer/MapService.swift:L165-L172`
- **Evidence**:
  - The onboarding feature row states: `All processing happens locally on your Mac`.
  - The production shell renders a MapKit `Map` and exposes place search through `LocationSearchService`.
  - The in-scope map-service implementation constructs `MKLocalSearch.Request`, adds the query and current region, and awaits `search.start()`.
  - Data flow: user place query/current region → platform map/search service API → returned map items.
- **Description**: the absolute local-only statement does not disclose the platform map/search service boundary. The exact transport/privacy behavior of `LocationSearchService` was outside this assigned scope, so the finding does not claim a specific vendor retention policy.
- **Preconditions**: user views/uses the map or place search and relies on onboarding's privacy statement.
- **Impact**: informed-consent and privacy-expectation mismatch for potentially sensitive place queries and map regions.
- **Exploitability analysis**: this is not an attacker-controlled exfiltration path; the recipient is the configured platform service and use is user-initiated.
- **Why scanners may miss this**: the defect is the semantic mismatch between UX copy and platform-backed behavior.
- **Chaining**: none established.
- **Recommended fix** (preferred + alternatives):
  - Replace the absolute statement with precise language: device control and route persistence happen locally, while map tiles/search may use Apple platform services.
  - Add a privacy note near search and document which fields are sent by the actual `LocationSearchService`.
  - If offline-only behavior is a product requirement, disable online search/map services and provide a truly local alternative.
- **Incorrect fixes to avoid**: retaining “all processing” while adding an obscure exception; claiming anonymization without implementation evidence.
- **Residual risk after fix**: platform service behavior remains subject to vendor policy and network configuration.
- **Priority / SLA suggestion**: Wave 2, within 30 days.
- **Confidence**: LIKELY
- **Effort**: S

### [LOW] Migration intentionally retains duplicate precise location data in Documents
- **ID**: DESIGN-002
- **Category**: Design flaw
- **CWE / OWASP / ASVS**: CWE-459 Incomplete Cleanup
- **Location**: `PathChanger/Models/LocationHistoryStore.swift:L62-L75`, `PathChanger/GPX/RouteLibrary.swift:L158-L171`, `PathChanger/Models/LegacyDocumentsMigration.swift:L19-L33`
- **Evidence**:
  - Both stores explicitly state they “deliberately leave the legacy file in place as a non-destructive rollback fallback.”
  - `migrateFileIfNeeded` copies the file and creates a completion marker; it never deletes, expires, or encrypts the source.
  - Data flow: precise history/routes in `~/Documents/PathChanger/*.json` → copy to Application Support → original retained indefinitely.
- **Description**: after successful migration, the app maintains two copies of sensitive route/history data while only the new copy is actively managed. Clearing or updating the current store does not clean the legacy duplicate.
- **Preconditions**: the user ran a version that created legacy Documents files and then launches the migrated version; exposure requires access to the user's Documents, backups, or sync account.
- **Impact**: stale precise location history and complete saved routes can survive user cleanup expectations and may be synced/backed up under different policies. The history store limits active entries to 50; saved route point count is unbounded.
- **Exploitability analysis**: no cross-user read path is established by these files alone. Risk is data remanence under local/sync compromise, so severity is Low.
- **Why scanners may miss this**: the behavior is intentional and documented as rollback, not a failed API call.
- **Chaining**: the retained large route file can also preserve data associated with VULN-001.
- **Recommended fix** (preferred + alternatives):
  - After a verified copy and successful decode at the destination, offer explicit deletion of the legacy files or delete them after a short, documented rollback window.
  - Make “clear history/routes” remove both current and known legacy copies.
  - Record migration version/status without preserving sensitive payloads indefinitely.
- **Incorrect fixes to avoid**: deleting before destination validation; assuming the migration marker itself removes data; silently retaining duplicates without disclosure.
- **Residual risk after fix**: backups made before cleanup may retain copies according to backup-provider policy.
- **Priority / SLA suggestion**: Wave 2, within 30 days.
- **Confidence**: CONFIRMED
- **Effort**: S

### [LOW] Redesign exposes persisted controls and commands with no behavioral consumer
- **ID**: BUG-003
- **Category**: Bug | Dead code | Design flaw
- **CWE / OWASP / ASVS**: CWE-670 Always-Incorrect Control Flow Implementation; CWE-1164 Irrelevant Code
- **Location**: `PathChanger/PathChangerApp.swift:L90-L94`, `PathChanger/PathChangerApp.swift:L297-L301`, `PathChanger/Models/AppStateStores.swift:L131-L136`, `PathChanger/UI/SettingsView.swift:L10-L18`, `PathChanger/UI/SettingsView.swift:L487-L503`, `PathChanger/UI/SimulationView.swift:L23-L31`, `PathChanger/UI/Components/ModeControlPanel.swift:L22-L24`, `PathChanger/UI/Components/ModeControlPanel.swift:L177-L194`
- **Evidence**:
  - Command-L “Set Location…” only sets `showLocationInput = true`; repository-wide exact-symbol search found no read, sheet binding, or reset beyond the facade/store declaration.
  - `defaultMapStyle` and `showCoordinatesOnMap` occur only in Settings bindings; `SimulationView` initializes its independent map style to `.standard`.
  - `safeModeEnabled` occurs only in one `@AppStorage` declaration and its toggle. Its own comment calls it “Cosmetic-but-persisted,” while visible text claims “Mimics natural movement and respects cooldown to avoid detection.” The label remains “Safe Mode Enabled” even when the toggle is off.
  - Control flow: user action → UserDefaults/AppState mutation → no operational reader/sink.
- **Description**: the redesign left multiple zombie controls. They accept input and persist values but do not alter map behavior, coordinate presentation, movement policy, cooldown, or location-sheet presentation.
- **Preconditions**: local user invokes the menu command or changes one of the settings.
- **Impact**: incorrect UI behavior and false safety/privacy expectations. The “Safe Mode” claim is the most consequential because users may rely on a protection that is not enforced; no account/platform bypass capability is claimed.
- **Exploitability analysis**: no external attacker is required. This is a local integrity/trust defect and maintenance hazard.
- **Why scanners may miss this**: all bindings compile and persist correctly; only a repository-wide data-flow/reference check reveals that values are never consumed.
- **Chaining**: duplicated legacy controls in DEAD-010 increase the chance that a maintainer wires one path but not the production path.
- **Recommended fix** (preferred + alternatives):
  - Remove the controls and claims until behavior exists, or connect each to a single authoritative model consumed by the production shell.
  - For Command-L, present/focus the actual production coordinate editor or remove the command and shortcut description.
  - Initialize map style from one typed preference and conditionally render the promised coordinate overlay.
  - Do not ship “Safe Mode” or detection/cooldown claims without an enforceable policy, tests, and observable state; the label must reflect on/off state.
  - Add UI tests that change each preference and assert a visible/behavioral effect after relaunch.
- **Incorrect fixes to avoid**: renaming controls while leaving them inert; adding more independent `@State` mirrors; treating persistence as proof the behavior is implemented.
- **Residual risk after fix**: product claims still require review whenever behavior changes.
- **Priority / SLA suggestion**: Wave 1 for the Safe Mode claim and Command-L; Wave 2 for map preferences.
- **Confidence**: CONFIRMED
- **Effort**: M

### [INFO] Superseded and duplicate production code remains compiled after the redesign
- **ID**: DEAD-010
- **Category**: Dead code
- **CWE / OWASP / ASVS**: CWE-561 Dead Code
- **Location**: `PathChanger/UI/SimulationView.swift:L53-L63`, `PathChanger/UI/SimulationView.swift:L238-L240`, `PathChanger/UI/MainMapShell.swift:L53-L59`, `PathChanger/UI/Components/DeviceTunnelPill.swift:L7-L18`, `PathChanger/UI/Components/CollapsibleSidebar.swift:L237-L272`, `PathChanger/MapLayer/MapService.swift:L85-L220`, `PathChanger/Simulation/MovementPhysics.swift:L180-L699`, `PathChanger/UI/ErrorDialogView.swift:L12-L125`, `PathChanger/UI/ErrorDialogView.swift:L337-L559`
- **Evidence**:
  - Production `ContentView` mounts `MainMapShell`, and `MainMapShell` always mounts `SimulationView(..., embedded: true)`. The legacy mode controls only render under `if !embedded`; `topControls` has no call site at all.
  - `DeviceTunnelPill` marks itself superseded and is referenced only by its preview/tests/comments; production uses `ConnectionPill` and `DeviceDropdown`.
  - Exact-symbol searches found no production caller for `MapManager`/`MapKitService`; movement-physics types are referenced only by their own file and tests; several error/status/sheet views and `SidebarToggleButton` are preview-only or definition-only.
- **Description**: parallel implementations remain in the application target after the UI redesign. Some files contain useful shared types, but their retired views/helpers remain adjacent, obscuring the authority boundaries the comments attempt to enforce.
- **Preconditions**: maintenance change, accidental remount, or future refactor.
- **Impact**: larger review/test surface, divergent validation and UI semantics, and increased chance of modifying a nonproduction path. No currently reachable security exploit is established.
- **Exploitability analysis**: maintenance-only risk; no runtime attacker path.
- **Why scanners may miss this**: SwiftUI previews, tests, self-references, and shared types make file-level “used” checks insufficient.
- **Chaining**: reinforces BUG-003 by preserving multiple settings/control implementations.
- **Recommended fix** (preferred + alternatives):
  - Extract `ActiveTransportPresentation` into its own live file, then remove `DeviceTunnelPill`, its popover, and obsolete styles.
  - Delete or move preview/test-only helpers out of the production target after confirming product intent.
  - Remove `SimulationView.topControls`, unused `showCoordinateInput`, legacy standalone mode panels, sidebar recents helpers, and retired error/status sheets if no dynamic construction exists.
  - Either integrate `MapService`/movement physics through one authority or remove them and their orphaned tests in small, separately reviewed changes.
- **Incorrect fixes to avoid**: deleting shared resolvers with retired views; assuming Swift reflection cannot exist without checking target/runtime configuration; keeping duplicate paths solely because tests exercise them.
- **Residual risk after fix**: SwiftUI previews and compatibility code will still require periodic reachability review.
- **Priority / SLA suggestion**: Wave 2, within 30–60 days.
- **Confidence**: CONFIRMED for named exact-symbol results; runtime/dynamic construction was not found but should be rechecked before deletion.
- **Effort**: M

## 7. Vulnerability chains
### Crafted GPX → main-actor retention → amplified route allocation → local availability loss
The user-selected file is fully loaded and synchronously parsed on `RouteLibraryManager`'s main-actor context (`PathChanger/GPX/GPXParser.swift:L309-L313`, `PathChanger/GPX/RouteLibrary.swift:L126-L127`, `PathChanger/GPX/RouteLibrary.swift:L245-L267`). Each point is retained without a count cap, and a route that survives import is later expanded into per-update coordinates without an aggregate cap (`PathChanger/Simulation/RouteInterpolator.swift:L18-L41`, `PathChanger/Simulation/RouteInterpolator.swift:L54-L72`). This composition is more consequential than either operation alone: a compact geometric route can create a much larger playback array. User file selection and route start are compensating preconditions; blast radius remains the local app/workflow.

No chain to privilege escalation, code execution, pairing bypass, or cross-user data access was found in the assigned scope.

## 8. Dead code & unused surface report
### Dead / unused inventory
| ID | Symbol / path | Type | Evidence of non-use | Removal risk | Recommendation |
|---|---|---|---|---|---|
| DEAD-001 | `SimulationView.topControls`, `showCoordinateInput` | Unreachable/unused | Exact-symbol search finds declaration only; body never references `topControls` (`PathChanger/UI/SimulationView.swift:L31`, `PathChanger/UI/SimulationView.swift:L238-L240`) | Low | Delete after UI test confirms sidebar search and production coordinate editor coverage. |
| DEAD-002 | Legacy standalone `SimulationView` mode panels | Duplicate implementation | Production always passes `embedded: true`; panels are guarded by `if !embedded` (`PathChanger/UI/MainMapShell.swift:L53-L59`, `PathChanger/UI/SimulationView.swift:L53-L63`) | Medium because previews may use them | Consolidate on `ModeControlPanel`; update previews/tests first. |
| DEAD-003 | `DeviceTunnelPill`, popover, styles | Superseded view | File documents retirement; no production mount; tests assert it is not mounted (`PathChanger/UI/Components/DeviceTunnelPill.swift:L7-L18`) | Medium because `ActiveTransportPresentation` is live | Extract resolver, then delete retired view code. |
| DEAD-004 | `CollapsibleSidebar.emptyRecents`, `recentsList`, `recentRow` | Half-removed redesign path | Body now exposes Library flyout and session card; helpers have definition-only exact-symbol results (`PathChanger/UI/Components/CollapsibleSidebar.swift:L24-L76`, `PathChanger/UI/Components/CollapsibleSidebar.swift:L237-L300`) | Low | Delete helpers after flyout coverage is confirmed. |
| DEAD-005 | `SidebarToggleButton` | Preview-only component | Exact-symbol search finds definition and preview only (`PathChanger/UI/Components/SidebarToggleButton.swift:L11-L49`) | Low | Remove or mount as the sole toggle; do not retain two implementations. |
| DEAD-006 | `ErrorDialogView`, `ConnectionStatusBanner`, `TunneldStatusView`, `StartTunneldSheet`, `DeveloperModeGuideSheet` | Superseded/definition-only views | Production `ContentView` uses `EnhancedErrorDialogView`; exact-symbol search finds no production caller for listed views (`PathChanger/UI/ContentView.swift:L83-L102`, `PathChanger/UI/ErrorDialogView.swift:L12-L125`, `PathChanger/UI/ErrorDialogView.swift:L337-L559`) | Medium because product recovery flows may be planned | Confirm no dynamic presentation, then delete or move to prototypes. |
| DEAD-007 | `MapServiceProtocol`, `MapKitService`, `MapManager` | Duplicate map layer | Exact-symbol search finds only self-contained definitions; production uses SwiftUI `Map` directly (`PathChanger/MapLayer/MapService.swift:L85-L220`, `PathChanger/UI/SimulationView.swift:L88-L90`) | Medium if planned abstraction is pending | Integrate as the single map authority or remove. |
| DEAD-008 | `MovementPhysicsEngine`, `RouteRecorder`, `PhysicsRouteSimulation` | Test-only production code | References are confined to `MovementPhysics.swift` and `MovementPhysicsTests.swift`; active `SimulationEngine` uses `RouteInterpolator` (`PathChanger/Simulation/MovementPhysics.swift:L180-L699`, `PathChanger/Simulation/SimulationEngine.swift:L487-L497`) | Medium if future feature planned | Move behind an explicit target/feature or remove code and orphaned tests. |
| DEAD-009 | `GPXParserError.unsupportedVersion` | Unreachable error case | Declared at `PathChanger/GPX/GPXParser.swift:L186-L193`; parser ignores root version at `PathChanger/GPX/GPXParser.swift:L335-L337` | Low | Wire into root validation or remove the case. |

### Complexity / unneeded surface reduction
The highest-value reduction is to establish one production authority each for map controls, device/tunnel presentation, and simulation movement. Current comments identify those authorities, but retained implementations contradict that simplification. Removal should be split into small changes with exact-symbol/reference checks and UI regression tests.

## 9. Bugs / mistakes / error-handling defects
BUG-001, BUG-002, and BUG-003 are the confirmed correctness defects and are fully specified above.

Persistence uses non-atomic `Data.write(to:)` for routes and history (`PathChanger/GPX/RouteLibrary.swift:L340-L345`, `PathChanger/Models/LocationHistoryStore.swift:L125-L131`). A crash during write can corrupt the only active copy; route loading surfaces an error, while history loading silently replaces entries with an empty array (`PathChanger/Models/LocationHistoryStore.swift:L114-L122`). This was not counted as a separate finding because impact and failure frequency were not established, but remediation should use `.atomic`, preserve a last-known-good file, and surface history decode failure.

`SimulationEngine` uses session IDs, task cancellation, and waits for older tick tasks before starting a new normal session or clearing location (`PathChanger/Simulation/SimulationEngine.swift:L856-L868`, `PathChanger/Simulation/SimulationEngine.swift:L759-L774`). Recovery instead cancels without awaiting at `PathChanger/Simulation/SimulationEngine.swift:L700-L710`. Whether an already-entered bridge call can still affect the device after recovery depends on out-of-scope `LocationBridge` cancellation semantics; this remains a review question rather than a finding.

## 10. Dependency & supply-chain notes
No manifest, lockfile, package version, or third-party source was in the assigned scope, so dependency vulnerability and pinning conclusions are not made. The in-scope code relies on Foundation XMLParser, MapKit, SwiftUI, CoreLocation, and the out-of-scope pymobiledevice3 bridge. External-entity resolution is explicitly disabled in the parser (`PathChanger/GPX/GPXParser.swift:L268-L271`).

## 11. Remediation roadmap
### Wave 0: emergency
None required from this scope; no Critical/High issue was confirmed.

### Wave 1: high-risk design fixes
1. Add centralized GPX import limits and lazy/bounded route interpolation; move parse/geometry work off the main actor.
2. Enforce coordinate validation at the GPX boundary and persisted-data decode boundary.
3. Replace parser global/last-object association with an element stack and round-trip tests.
4. Remove the unwired Safe Mode claim and repair or remove Command-L.

### Wave 2: hardening and dead-code removal
1. Correct local-processing disclosure and document map/search data boundaries.
2. Delete legacy Documents copies after verified migration or a defined rollback window.
3. Wire or remove map preferences.
4. Extract live shared resolvers and remove retired/duplicate UI, map, and simulation implementations.
5. Make route/history writes atomic and surface decode failure.

### Wave 3: long-term architecture
Define one typed `GPXImportPolicy` containing byte, text, point, segment, distance, and output limits; make every file/data import use it. Keep a single production map/control authority and one simulation engine. Add an ADR for retention of precise location data, including migration cleanup and backup/sync expectations.

## 12. Verification plan
- GPX unit tests: empty input; unsupported root/version; XXE regression confirming no external fetch; exact coordinate boundaries; out-of-range/non-finite values; nested metadata; route-point names; reordered elements; writer→parser round trip.
- Resource tests: reject input just above each byte/point/text limit; reject an aggregate interpolation count above the cap; verify near-limit work completes without blocking a main-actor heartbeat.
- Property test: every successfully imported and every interpolated `LocationCoordinate` satisfies `isValid`.
- Persistence tests: atomic replacement, corrupt current file recovery, legacy copy validation, and deletion/retention policy.
- UI tests: Command-L presents/focuses the actual coordinate editor; default map style survives relaunch and changes the map; coordinate-overlay toggle changes rendering; no Safe Mode control exists unless it changes a tested engine policy.
- Reachability gate: exact-symbol/static analysis for preview-only and definition-only views before each redesign merge; prohibit duplicate T0/Phase-1 authorities.
- Privacy review: onboarding/search disclosure is checked whenever map/search providers change.
- Runtime metric: GPX input bytes, raw points, generated points, parse duration, and rejection reason, without logging route names or coordinates by default.

## 13. Residual risk & future-proofing
Even with limits, legitimate high-detail GPX files may be rejected; limits should be documented and adjustable only within a safe bounded range. Platform map/search services remain outside the app's full control and require accurate disclosure. Same-user processes can generally access user-scoped app data; encryption would only materially help with a separate key boundary, so retention minimization and OS file protection are the first controls. Device-side location integrity still depends on out-of-scope tunnel/bridge cancellation and authorization.

Architectural invariants to preserve:
- No untrusted file is fully retained or expanded without byte/object/aggregate caps.
- Every coordinate is validated once at ingress and remains valid by construction.
- GPX parsing decisions use explicit XML context, not “last object” state.
- Only one production UI surface initiates simulation; only one map/control implementation owns each state.
- Privacy and safety labels are backed by observable, tested behavior.
- Clearing sensitive history removes all app-known active and legacy copies.

## 14. Missing context / questions that would change severity
- App sandbox/entitlements and actual file-protection/backup/sync behavior for Documents and Application Support.
- `LocationSearchService` implementation and the platform/vendor privacy terms governing query/region data.
- `LocationBridge` cancellation behavior for an in-flight location write during pause/recovery.
- Maximum expected GPX size/route length and whether files arrive from untrusted third parties in normal use.
- Whether the Safe Mode feature has an external specification or is intentionally mockup-only.
- Whether MapService and MovementPhysics are planned features included in a different build configuration; no such production wiring was found in repository-wide exact-symbol searches.
- Whether product requirements promise deletion of all location history, including legacy and backup copies.
