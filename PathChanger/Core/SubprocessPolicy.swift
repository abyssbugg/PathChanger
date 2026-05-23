//
//  SubprocessPolicy.swift
//  PathChanger
//
//  Authoritative subprocess security policy.
//
//  This enum is the **single source of truth** for all subprocess-related
//  security constants in the codebase. The three validators
//  (ArgumentSanitizer, CommandStructureValidator, PrivilegedCommandValidator)
//  consume these lists; they never define their own.
//
//  Adding a new Python version, a new pmd3 subcommand, or a new pmd3 flag
//  requires touching ONE list here — the drift hazard that previously
//  existed between SecurityConstants, SubprocessCommandValidator, and
//  PrivilegedCommandValidator is eliminated by construction.
//
//  Established by ADR-006 (subprocess policy unification).
//

import Foundation

/// Authoritative security policy for all subprocess execution in PathChanger.
///
/// All validators (`ArgumentSanitizer`, `CommandStructureValidator`,
/// `PrivilegedCommandValidator`) derive their allow/deny lists from this enum.
/// Subprocess execution call sites must consume these lists rather than
/// inlining their own constants.
public enum SubprocessPolicy {

    // MARK: - Python Path Allowlist

    /// The only Python 3 executable paths the app will execute.
    ///
    /// User-writable bin directories (e.g. `~/.local/bin`) are intentionally
    /// excluded. Pyenv version-managed interpreters are validated separately in
    /// `isAllowedPythonPath(_:)` so legitimate `~/.pyenv/versions/*/bin/python3`
    /// runtimes work without allowing arbitrary user-home executables.
    public static let allowedPythonPaths: Set<String> = [
        "/opt/homebrew/bin/python3",
        "/opt/homebrew/bin/python3.11",
        "/opt/homebrew/bin/python3.12",
        "/opt/homebrew/bin/python3.13",
        "/opt/homebrew/bin/python3.14",
        "/usr/local/bin/python3",
        "/usr/local/bin/python3.11",
        "/usr/local/bin/python3.12",
        "/usr/local/bin/python3.13",
        "/usr/local/bin/python3.14",
        "/usr/bin/python3"
    ]

    // MARK: - pmd3 Subcommand Allowlist

    /// pmd3 subcommands the app is permitted to invoke.
    ///
    /// Any pmd3 invocation containing a token outside this set is rejected
    /// by `CommandStructureValidator`.
    public static let allowedSubcommands: Set<String> = [
        // Location simulation
        "developer", "dvt", "simulate-location", "set", "clear",
        // Tunnel management
        "lockdown", "start-tunnel", "tunneld",
        // Device discovery / listing
        "usbmux", "list", "remote", "ls",
        // Version probe
        "version"
    ]

    // MARK: - pmd3 Flag Allowlist

    /// Command-line flags the app is permitted to pass to pmd3.
    ///
    /// Any flag outside this set is rejected by `CommandStructureValidator`.
    public static let allowedFlags: Set<String> = [
        "-m",           // Python module invocation flag
        "--tunnel",     // Tunneld-mode device selector
        "--udid",       // Direct device selector
        "--rsd",        // Remote service discovery address
        "--no-color",   // Disable colored output
        "--",           // Argument separator
        "-h", "--help", // Help flags (always safe)
        "-t"            // Transport selector for `remote start-tunnel -t wifi`
    ]

    // MARK: - Forbidden Characters

    /// Characters that may never appear in a single subprocess **argument value**.
    ///
    /// This set is consumed by `ArgumentSanitizer.sanitizeSingleArgument` and
    /// is the strict set: it blocks everything that has ever caused trouble
    /// in any of the historical lists in ArgumentSanitizer, SecurityConstants,
    /// or PrivilegedCommandValidator.
    ///
    /// Note: this set is intentionally **stricter** than
    /// `privilegedCommandForbiddenCharacters` because subprocess arguments
    /// are exec-argv values — they never need shell metacharacters such as
    /// `&` or `>`. The privileged-command path is a different validation
    /// context (it validates a full shell command string) and uses the
    /// narrower set below.
    public static let forbiddenCharacters: Set<Character> = [
        ";", "|", "&", "$", "`",
        "\\", "\"", "'", "<", ">",
        "(", ")", "{", "}", "[", "]",
        "!", "#",
        "\n", "\r"
    ]

    /// Characters that may never appear in a **privileged shell command**
    /// string passed through `do shell script ... with administrator
    /// privileges`.
    ///
    /// This set is consumed by `PrivilegedCommandValidator.validate(...)`.
    /// It is intentionally **narrower** than `forbiddenCharacters` because
    /// privileged commands legitimately contain:
    ///   - `&` for background-execution at end of the command
    ///   - `>` and `2>&1` for log redirect
    /// Both of those are required for the current
    /// `pmd3 lockdown start-tunnel … > log 2>&1 &` invocation pattern in
    /// `TunneldManager.attemptStart` and have to stay accepted to preserve
    /// operational behaviour.
    ///
    /// What this set blocks is the structurally dangerous subset:
    /// command-substitution / chaining / process substitution metacharacters
    /// that an attacker could use to escape a single-quoted argument.
    public static let privilegedCommandForbiddenCharacters: Set<Character> = [
        ";", "|", "`", "$",
        "(", ")", "{", "}",
        "<",
        "\n", "\r"
    ]

    /// CharacterSet form of `forbiddenCharacters` for use with
    /// Foundation APIs that take `CharacterSet`.
    public static let forbiddenCharacterSet: CharacterSet = {
        var set = CharacterSet()
        for character in forbiddenCharacters {
            for scalar in character.unicodeScalars {
                set.insert(scalar)
            }
        }
        return set
    }()

    // MARK: - Output Bounds

    /// Maximum subprocess output size before the call is treated as a leak
    /// or DoS attempt.
    ///
    /// Individual call sites may apply a stricter local cap (e.g. the
    /// location subprocess uses 1 MiB). This value is the system-wide
    /// upper bound.
    public static let maxSubprocessOutputBytes: Int = 5 * 1024 * 1024  // 5 MiB

    // MARK: - Convenience Predicates

    /// Check whether a Python path is approved for execution.
    public static func isAllowedPythonPath(_ path: String) -> Bool {
        if allowedPythonPaths.contains(path) {
            return true
        }

        return isAllowedPyenvVersionPythonPath(path)
    }

    private static func isAllowedPyenvVersionPythonPath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !containsForbiddenCharacter(path),
              FileManager.default.isExecutableFile(atPath: path) else {
            return false
        }

        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardizedPath == path else {
            return false
        }

        let prefix = "\(NSHomeDirectory())/.pyenv/versions/"
        guard path.hasPrefix(prefix),
              path.hasSuffix("/bin/python3") else {
            return false
        }

        let versionName = path
            .dropFirst(prefix.count)
            .dropLast("/bin/python3".count)

        return !versionName.isEmpty &&
               !versionName.contains("/") &&
               !versionName.contains("..")
    }

    /// Check whether a pmd3 subcommand is in the allowlist.
    public static func isAllowedSubcommand(_ subcommand: String) -> Bool {
        allowedSubcommands.contains(subcommand)
    }

    /// Check whether a pmd3 flag (or `--flag=value` form) is in the allowlist.
    public static func isAllowedFlag(_ flag: String) -> Bool {
        let flagName = flag.contains("=") ? String(flag.prefix(while: { $0 != "=" })) : flag
        return allowedFlags.contains(flagName)
    }

    /// Check whether a string contains any forbidden character.
    public static func containsForbiddenCharacter(_ argument: String) -> Bool {
        for character in argument where forbiddenCharacters.contains(character) {
            return true
        }
        return false
    }
}
