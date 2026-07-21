//
//  PrivilegedPathSecurity.swift
//  PathChanger
//
//  Wave 0 / Wave 0.1 security policy seams for privileged (administrator) execution.
//  W0.1: pin+elevate same interpreter (A07), O_NOFOLLOW log open as root (A03),
//  pair-script trust for drag-drop installs (A08). Non-privileged location
//  injection continues to use SubprocessPolicy without these stricter gates.
//

import Foundation
import Darwin

// MARK: - Errors

enum PrivilegedPathSecurityError: Error, LocalizedError, Equatable {
    case emptyPath
    case notAbsolute(String)
    case pathMissing(String)
    case symlinkRejected(String)
    case notRegularFile(String)
    case ownershipRejected(path: String, ownerUID: uid_t)
    case writableByNonRoot(String)
    case pyenvRejectedForPrivileged(String)
    case pathNotAllowlisted(String)
    case scriptPathRejected(String)
    case disallowedCommandValueCharacters(String)
    case invalidUDIDInCommand(String)
    case secureCreateFailed(String)
    case pathContainsShellMeta(String)
    case pinMissingOnInterpreter(String)
    case unsafeLaunchConstruction(String)
    case writableAncestor(String)

    var errorDescription: String? {
        switch self {
        case .emptyPath:
            return "Privileged path is empty"
        case .notAbsolute(let path):
            return "Privileged path must be absolute: \(path)"
        case .pathMissing(let path):
            return "Privileged path does not exist: \(path)"
        case .symlinkRejected(let path):
            return "Symlink rejected for privileged use: \(path)"
        case .notRegularFile(let path):
            return "Privileged target is not a regular file: \(path)"
        case .ownershipRejected(let path, let ownerUID):
            return "Privileged path owner uid \(ownerUID) is not current user or root: \(path)"
        case .writableByNonRoot(let path):
            return "Privileged path is group/other-writable: \(path)"
        case .pyenvRejectedForPrivileged(let path):
            return "Pyenv interpreters are not allowed for privileged execution: \(path)"
        case .pathNotAllowlisted(let path):
            return "Path is not on the subprocess allowlist: \(path)"
        case .scriptPathRejected(let path):
            return "Script path rejected for privileged pair execution: \(path)"
        case .disallowedCommandValueCharacters(let detail):
            return "Privileged command contains disallowed value characters: \(detail)"
        case .invalidUDIDInCommand(let udid):
            return "Privileged command contains invalid UDID value: \(udid)"
        case .secureCreateFailed(let path):
            return "Failed to securely create log file: \(path)"
        case .pathContainsShellMeta(let path):
            return "Log path contains characters unsafe for shell embedding: \(path)"
        case .pinMissingOnInterpreter(let path):
            return "Pinned pymobiledevice3 \(PythonPathResolver.pinnedPymobiledevice3Version) not found on privileged interpreter: \(path)"
        case .unsafeLaunchConstruction(let detail):
            return "Could not build safe privileged launch command: \(detail)"
        case .writableAncestor(let path):
            return "Privileged target has a group/other-writable ancestor directory: \(path)"
        }
    }
}

// MARK: - Policy

/// Wave 0 privileged-path security policy (PC-D-001, PC-H1/D-002, PC-M1, PC-M3).
enum PrivilegedPathSecurity {

    /// Characters that must never appear in privileged command *values*
    /// (defense-in-depth beyond the legacy metachar denylist that still allows
    /// `"`, `\`, `&`, space for historical shell redirect patterns).
    ///
    /// Used for UDID and other interpolated segments (PC-M1).
    static let privilegedValueForbiddenCharacters: Set<Character> = [
        "\"", "\\", "'", "&", " ", "\t", "\n", "\r",
        ";", "|", "`", "$", "(", ")", "{", "}", "<", ">", "!", "#"
    ]

    /// Working directory for privileged `python -m` invocations (PC-M3).
    static let privilegedPythonWorkingDirectory = "/"

    /// Environment additions for privileged Python (PC-M3).
    /// `PYTHONSAFEPATH=1` ignores cwd on `sys.path` (Python 3.11+).
    static var privilegedPythonEnvironment: [String: String] {
        [
            "PYTHONSAFEPATH": "1",
            "PYTHONDONTWRITEBYTECODE": "1"
        ]
    }

    // MARK: PC-H1 / PC-D-002 — interpreter provenance

    /// Whether `path` may be used as the Python interpreter under administrator privileges.
    static func isPrivilegedPythonPathAcceptable(_ path: String) -> Bool {
        validatePrivilegedPythonPath(path) == nil
    }

    /// Default candidate order after the caller's preferred user path (if any).
    static let defaultPrivilegedPythonPreferredOrder: [String] = [
        "/usr/bin/python3",
        "/opt/homebrew/bin/python3",
        "/opt/homebrew/bin/python3.14",
        "/opt/homebrew/bin/python3.13",
        "/opt/homebrew/bin/python3.12",
        "/opt/homebrew/bin/python3.11",
        "/usr/local/bin/python3",
        "/usr/local/bin/python3.14",
        "/usr/local/bin/python3.13",
        "/usr/local/bin/python3.12",
        "/usr/local/bin/python3.11"
    ]

    /// Resolve a Python interpreter for administrator-privileged use (Wave 0.1 / A07).
    ///
    /// Policy:
    /// - Never pyenv; must be allowlisted; not group/other-writable; owner is self or root.
    /// - **Pin and elevation use the same binary**: only returns a path that has
    ///   `pymobiledevice3==pinned` when `requirePinnedModule` is true (default).
    /// - Preference: `preferredUserPath` if acceptable+pinned, else root-owned candidates,
    ///   else other acceptable pinned candidates.
    ///
    /// Residual risk: user-owned Homebrew remains replaceable by same-UID malware (A01 class);
    /// durable fix is SMAppService/XPC helper (Wave 2).
    static func resolvePrivilegedPythonPath(
        preferredUserPath: String? = nil,
        preferredOrder: [String] = defaultPrivilegedPythonPreferredOrder,
        requirePinnedModule: Bool = true,
        pinChecker: (String) -> Bool = { PythonPathResolver.hasPinnedPymobiledevice3Sync(at: $0) }
    ) -> String? {
        var candidates: [String] = []
        if let preferredUserPath, !preferredUserPath.isEmpty {
            candidates.append(preferredUserPath)
        }
        candidates.append(contentsOf: preferredOrder)

        var seen = Set<String>()
        var acceptable: [String] = []
        for path in candidates {
            guard seen.insert(path).inserted else { continue }
            if isPrivilegedPythonPathAcceptable(path) {
                acceptable.append(path)
            }
        }
        guard !acceptable.isEmpty else { return nil }

        let pool: [String]
        if requirePinnedModule {
            pool = acceptable.filter { pinChecker($0) }
            if pool.isEmpty { return nil }
        } else {
            pool = acceptable
        }

        // Prefer a root-owned interpreter when one is pinned and available: unlike
        // a user-owned Homebrew install it cannot be rewritten by same-UID code, so
        // it is the safer provenance for administrator-privileged execution.
        if let rootOwned = pool.first(where: { isRootOwnedFile(at: $0) }) {
            return rootOwned
        }
        // Otherwise fall back to the caller's path (same binary onboarding checked).
        if let preferredUserPath, pool.contains(preferredUserPath) {
            return preferredUserPath
        }
        return pool.first
    }

    /// Whether a path is root-owned (preference signal only).
    static func isRootOwnedFile(at path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        return info.st_uid == 0
    }

    /// Prefix for privileged shell invocations (PC-M3): safe cwd + PYTHONSAFEPATH.
    static var privilegedShellEnvironmentPrefix: String {
        let cwd = shellSingleQuotedPath(privilegedPythonWorkingDirectory) ?? "'/'"
        return "cd \(cwd) && export PYTHONSAFEPATH=1 && export PYTHONDONTWRITEBYTECODE=1 && "
    }

    static func validatePrivilegedPythonPath(_ path: String) -> PrivilegedPathSecurityError? {
        guard !path.isEmpty else { return .emptyPath }
        guard path.hasPrefix("/") else { return .notAbsolute(path) }

        // Pyenv is always user-home writable by design — never elevate it.
        if path.contains("/.pyenv/") {
            return .pyenvRejectedForPrivileged(path)
        }

        guard SubprocessPolicy.isAllowedPythonPath(path) else {
            return .pathNotAllowlisted(path)
        }

        return validatePrivilegedExecutableFile(at: path)
    }

    /// Pair helper script must be a bundle resource path, not CWD/repo fallback (PC-D-002 / A08).
    static func isPrivilegedPairScriptPathAcceptable(_ path: String) -> Bool {
        validatePrivilegedPairScriptPath(path) == nil
    }

    /// Wave 0.1 / A08: trust drag-and-drop installs by **bundle location + non-writable
    /// mode + owner self/root**, not raw uid 0 (which rejects normal `cp -R` / install.sh).
    static func validatePrivilegedPairScriptPath(_ path: String) -> PrivilegedPathSecurityError? {
        guard !path.isEmpty else { return .emptyPath }
        guard path.hasPrefix("/") else { return .notAbsolute(path) }
        guard path.hasSuffix("/scripts/pair_wifi.py") || path.hasSuffix("/pair_wifi.py") else {
            return .scriptPathRejected(path)
        }
        let lowered = path.lowercased()
        if lowered.contains("/.pyenv/") {
            return .scriptPathRejected(path)
        }
        // Must live under a macOS app Resources tree (signature-adjacent layout).
        guard path.contains(".app/Contents/Resources/") else {
            return .scriptPathRejected(path)
        }
        // Reject bare tmp/CWD layouts that are *not* a Resources tree (already required above).
        // Note: unit tests may place a fake .app under NSTemporaryDirectory — that is OK
        // because production resolve uses Bundle.main Resources, not temp.
        // Reject symlinks at the script path (replace-with-malicious-script class).
        var linkInfo = stat()
        if lstat(path, &linkInfo) == 0, (linkInfo.st_mode & S_IFMT) == S_IFLNK {
            return .symlinkRejected(path)
        }
        return validatePrivilegedExecutableFile(at: path, requireExecutable: false)
    }

    // MARK: Wave 0.1 / A03 — privileged log open without shell `>` reopen race

    /// Python launcher (no `'` chars) that opens `log` with O_NOFOLLOW as the
    /// elevated process, then execs the real interpreter. Runs after the admin
    /// password dialog so open happens in the same privileged session (A03).
    /// Background mode forks, redirects child stdio, prints child pid for handoff.
    // Single-line (no `'`) so it embeds safely in `do shell script "… -c '…' …"`.
    private static let privilegedBackgroundLogLauncherPython =
        "import os,sys;" +
        "log=sys.argv[1];exe=sys.argv[2];args=sys.argv[2:];" +
        "fd=os.open(log,os.O_WRONLY|os.O_CREAT|os.O_TRUNC|os.O_NOFOLLOW,0o600);" +
        "os.fchmod(fd,0o600);" +
        "pid=os.fork();" +
        "child=lambda:(os.dup2(fd,1),os.dup2(fd,2),os.close(fd),os.execv(exe,args));" +
        "pid==0 and child();" +
        "os.close(fd);print(pid)"

    /// Foreground variant (pair_wifi): open log O_NOFOLLOW then exec (no fork).
    private static let privilegedForegroundLogLauncherPython =
        "import os,sys;" +
        "log=sys.argv[1];exe=sys.argv[2];args=sys.argv[2:];" +
        "fd=os.open(log,os.O_WRONLY|os.O_CREAT|os.O_TRUNC|os.O_NOFOLLOW,0o600);" +
        "os.fchmod(fd,0o600);" +
        "os.dup2(fd,1);os.dup2(fd,2);os.close(fd);" +
        "os.execv(exe,args)"

    /// Build privileged **background** tunnel launch with O_NOFOLLOW log open.
    /// Returns a shell string suitable for `do shell script "…"` (no double quotes).
    static func buildPrivilegedBackgroundTunnelCommand(
        privilegedPython: String,
        logPath: String,
        moduleArguments: [String]
    ) -> Result<String, PrivilegedPathSecurityError> {
        buildPrivilegedLoggedCommand(
            privilegedPython: privilegedPython,
            logPath: logPath,
            executableArguments: [privilegedPython] + moduleArguments,
            launcherPythonSource: privilegedBackgroundLogLauncherPython
        )
    }

    /// Build privileged **foreground** pair helper command with O_NOFOLLOW log open.
    static func buildPrivilegedForegroundPairCommand(
        privilegedPython: String,
        scriptPath: String,
        logPath: String,
        extraArguments: [String]
    ) -> Result<String, PrivilegedPathSecurityError> {
        buildPrivilegedLoggedCommand(
            privilegedPython: privilegedPython,
            logPath: logPath,
            executableArguments: [privilegedPython, scriptPath] + extraArguments,
            launcherPythonSource: privilegedForegroundLogLauncherPython
        )
    }

    private static let shellUnsafeArgCharacters: Set<Character> = [
        "'", "\"", "\\", "`", "$", ";", "|", "&", "\n", "\r", "<", ">", "(", ")", "{", "}", " "
    ]

    private static func buildPrivilegedLoggedCommand(
        privilegedPython: String,
        logPath: String,
        executableArguments: [String],
        launcherPythonSource: String
    ) -> Result<String, PrivilegedPathSecurityError> {
        guard isShellSafeSingleQuotedPath(privilegedPython),
              isShellSafeSingleQuotedPath(logPath) else {
            return .failure(.pathContainsShellMeta("python or log path"))
        }
        for arg in executableArguments {
            if arg.hasPrefix("/") {
                guard isShellSafeSingleQuotedPath(arg) else {
                    return .failure(.pathContainsShellMeta(arg))
                }
            } else if arg.contains(where: { shellUnsafeArgCharacters.contains($0) }) {
                return .failure(.unsafeLaunchConstruction(arg))
            }
        }
        guard let qPython = shellSingleQuotedPath(privilegedPython),
              let qLog = shellSingleQuotedPath(logPath) else {
            return .failure(.pathContainsShellMeta("quote failed"))
        }
        // Launcher must not contain single quotes (embedded as shell -c '…').
        let launcher = launcherPythonSource
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "")
        guard !launcher.contains("'") else {
            return .failure(.unsafeLaunchConstruction("launcher source contains quote"))
        }

        var bodyParts: [String] = [qPython, "-c", "'\(launcher)'", qLog]
        for arg in executableArguments {
            if arg.hasPrefix("/") {
                guard let q = shellSingleQuotedPath(arg) else {
                    return .failure(.pathContainsShellMeta(arg))
                }
                bodyParts.append(q)
            } else {
                bodyParts.append(arg)
            }
        }
        // Prefix already ends with "&& ".
        return .success(privilegedShellEnvironmentPrefix + bodyParts.joined(separator: " "))
    }

    // MARK: PC-D-001 — log redirect targets

    /// Validate a path that a privileged shell would open for write/redirect.
    static func validatePrivilegedLogRedirectTarget(_ path: String) -> Result<Void, PrivilegedPathSecurityError> {
        guard !path.isEmpty else { return .failure(.emptyPath) }
        guard path.hasPrefix("/") else { return .failure(.notAbsolute(path)) }

        var info = stat()
        guard lstat(path, &info) == 0 else {
            return .failure(.pathMissing(path))
        }

        let mode = info.st_mode
        if (mode & S_IFMT) == S_IFLNK {
            return .failure(.symlinkRejected(path))
        }
        if (mode & S_IFMT) != S_IFREG {
            return .failure(.notRegularFile(path))
        }

        let owner = info.st_uid
        let selfUID = getuid()
        if owner != selfUID && owner != 0 {
            return .failure(.ownershipRejected(path: path, ownerUID: owner))
        }

        if (mode & S_IWGRP) != 0 || (mode & S_IWOTH) != 0 {
            return .failure(.writableByNonRoot(path))
        }

        return .success(())
    }

    /// Whether a not-yet-existing log path has a safe parent directory.
    static func validatePrivilegedLogParentDirectory(forFile path: String) -> Result<Void, PrivilegedPathSecurityError> {
        guard !path.isEmpty else { return .failure(.emptyPath) }
        guard path.hasPrefix("/") else { return .failure(.notAbsolute(path)) }

        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        var info = stat()
        guard lstat(parent, &info) == 0 else {
            return .failure(.pathMissing(parent))
        }
        if (info.st_mode & S_IFMT) == S_IFLNK {
            return .failure(.symlinkRejected(parent))
        }
        if (info.st_mode & S_IFMT) != S_IFDIR {
            return .failure(.notRegularFile(parent))
        }
        return .success(())
    }

    /// Characters that make a path unsafe to single-quote into `do shell script`.
    private static let shellUnsafeInSingleQuotedPath: Set<Character> = ["'", "\\", "\n", "\r"]

    /// True when `path` can be embedded as `'path'` in a privileged shell string.
    static func isShellSafeSingleQuotedPath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        return !path.contains(where: { shellUnsafeInSingleQuotedPath.contains($0) })
    }

    /// Single-quote a path for shell embedding, or nil if unsafe.
    static func shellSingleQuotedPath(_ path: String) -> String? {
        guard isShellSafeSingleQuotedPath(path) else { return nil }
        return "'\(path)'"
    }

    /// Create or open a log file with fail-closed security checks for later
    /// privileged write/redirect (PC-D-001).
    ///
    /// - Validates parent directory (not a symlink).
    /// - Rejects existing symlinks at `path` (removes only if we own a dangling/broken case is not auto-removed — fails closed).
    /// - Creates with `O_CREAT|O_EXCL|O_NOFOLLOW|O_WRONLY` when absent, mode `0600`.
    /// - Opens existing regular files with `O_WRONLY|O_NOFOLLOW|O_TRUNC` only if owned by current user (or root) and not group/other-writable.
    /// - Returns the path on success for use with `shellSingleQuotedPath`.
    @discardableResult
    static func prepareSecureLogFile(at path: String) -> Result<String, PrivilegedPathSecurityError> {
        guard !path.isEmpty else { return .failure(.emptyPath) }
        guard path.hasPrefix("/") else { return .failure(.notAbsolute(path)) }
        guard isShellSafeSingleQuotedPath(path) else {
            return .failure(.pathContainsShellMeta(path))
        }

        switch validatePrivilegedLogParentDirectory(forFile: path) {
        case .failure(let err):
            return .failure(err)
        case .success:
            break
        }

        var existing = stat()
        let exists = lstat(path, &existing) == 0
        if exists {
            let type = existing.st_mode & S_IFMT
            if type == S_IFLNK {
                return .failure(.symlinkRejected(path))
            }
            if type != S_IFREG {
                return .failure(.notRegularFile(path))
            }
            let owner = existing.st_uid
            let selfUID = getuid()
            if owner != selfUID && owner != 0 {
                return .failure(.ownershipRejected(path: path, ownerUID: owner))
            }
            if (existing.st_mode & S_IWGRP) != 0 || (existing.st_mode & S_IWOTH) != 0 {
                return .failure(.writableByNonRoot(path))
            }

            // O_NOFOLLOW | O_WRONLY | O_TRUNC
            let fd = open(path, O_WRONLY | O_NOFOLLOW | O_TRUNC)
            if fd < 0 {
                return .failure(.secureCreateFailed(path))
            }
            close(fd)
            // Re-validate after open/trunc
            return validatePrivilegedLogRedirectTarget(path).map { path }
        }

        // Create exclusive, no-follow
        let fd = open(path, O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY, 0o600)
        if fd < 0 {
            // Race: someone created between lstat and open — fail closed
            return .failure(.secureCreateFailed(path))
        }
        close(fd)
        // Enforce mode in case umask interfered
        _ = chmod(path, 0o600)
        return validatePrivilegedLogRedirectTarget(path).map { path }
    }

    // MARK: PC-M1 — command value hardening

    static func validatePrivilegedCommandValues(_ command: String) -> Result<Void, PrivilegedPathSecurityError> {
        let tokens = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "--udid", index + 1 < tokens.count {
                let udid = tokens[index + 1]
                if let bad = firstForbiddenValueCharacter(in: udid) {
                    return .failure(.disallowedCommandValueCharacters(String(bad)))
                }
                if !ArgumentSanitizer.isValidDeviceUDID(udid) {
                    return .failure(.invalidUDIDInCommand(udid))
                }
                index += 2
                continue
            }
            if token.hasPrefix("--udid=") {
                let udid = String(token.dropFirst("--udid=".count))
                if let bad = firstForbiddenValueCharacter(in: udid) {
                    return .failure(.disallowedCommandValueCharacters(String(bad)))
                }
                if !ArgumentSanitizer.isValidDeviceUDID(udid) {
                    return .failure(.invalidUDIDInCommand(udid))
                }
            }
            index += 1
        }

        if command.contains("\"") {
            return .failure(.disallowedCommandValueCharacters("\""))
        }
        if command.contains("\\") {
            return .failure(.disallowedCommandValueCharacters("\\"))
        }

        return .success(())
    }

    // MARK: PC-M3 — safe python -m environment

    static func environmentMeetsPrivilegedPythonPolicy(_ env: [String: String]) -> Bool {
        env["PYTHONSAFEPATH"] == "1"
    }

    static func workingDirectoryMeetsPrivilegedPythonPolicy(_ cwd: String) -> Bool {
        cwd == privilegedPythonWorkingDirectory || cwd == "/var/empty"
    }

    // MARK: - File checks

    private static func validatePrivilegedExecutableFile(
        at path: String,
        requireExecutable: Bool = true
    ) -> PrivilegedPathSecurityError? {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            return .pathMissing(path)
        }

        let fileType = info.st_mode & S_IFMT
        let binaryError: PrivilegedPathSecurityError?
        if fileType == S_IFLNK {
            var target = stat()
            guard stat(path, &target) == 0 else {
                return .symlinkRejected(path)
            }
            binaryError = validateStatForPrivilegedBinary(target, path: path, requireExecutable: requireExecutable)
        } else if fileType != S_IFREG {
            return .notRegularFile(path)
        } else {
            binaryError = validateStatForPrivilegedBinary(info, path: path, requireExecutable: requireExecutable)
        }

        if let binaryError {
            return binaryError
        }

        // Wave 1 interim hardening: reject a target reachable through a group/other-
        // writable (non-sticky) ancestor directory, which would let another local
        // user replace the privileged binary/script. Same-UID replacement remains a
        // residual risk to be closed by the signed SMAppService/XPC helper.
        return validateNoWritableAncestors(of: path)
    }

    /// Walk ancestor directories from the target's parent up to `/` and reject any
    /// group- or other-writable directory that is not sticky. Sticky world-writable
    /// dirs (for example `/tmp`) are permitted because the sticky bit prevents a
    /// different user from replacing files they do not own.
    static func validateNoWritableAncestors(of path: String) -> PrivilegedPathSecurityError? {
        var current = URL(fileURLWithPath: path).deletingLastPathComponent().path
        var iterations = 0
        while true {
            iterations += 1
            if iterations > 128 { break }
            var info = stat()
            guard stat(current, &info) == 0 else {
                return .pathMissing(current)
            }
            if (info.st_mode & S_IFMT) == S_IFDIR {
                let groupWrite = (info.st_mode & S_IWGRP) != 0
                let otherWrite = (info.st_mode & S_IWOTH) != 0
                let sticky = (info.st_mode & S_ISVTX) != 0
                if (groupWrite || otherWrite) && !sticky {
                    return .writableAncestor(current)
                }
            }
            if current == "/" { break }
            let parent = URL(fileURLWithPath: current).deletingLastPathComponent().path
            if parent == current { break }
            current = parent
        }
        return nil
    }

    private static func validateStatForPrivilegedBinary(
        _ info: stat,
        path: String,
        requireExecutable: Bool
    ) -> PrivilegedPathSecurityError? {
        // Wave 0.1 / A08 + A07 product: allow current user OR root ownership.
        // Reject other users. Prefer root-owned at resolve time when available.
        // Still reject group/other-writable (shared write → LPE).
        let selfUID = getuid()
        if info.st_uid != 0 && info.st_uid != selfUID {
            return .ownershipRejected(path: path, ownerUID: info.st_uid)
        }
        if (info.st_mode & S_IWGRP) != 0 || (info.st_mode & S_IWOTH) != 0 {
            return .writableByNonRoot(path)
        }
        if requireExecutable {
            let ownerExec = (info.st_mode & S_IXUSR) != 0
            let groupExec = (info.st_mode & S_IXGRP) != 0
            let otherExec = (info.st_mode & S_IXOTH) != 0
            if !(ownerExec || groupExec || otherExec) {
                return .notRegularFile(path)
            }
        }
        return nil
    }

    private static func firstForbiddenValueCharacter(in value: String) -> Character? {
        for ch in value where privilegedValueForbiddenCharacters.contains(ch) {
            return ch
        }
        return nil
    }
}
