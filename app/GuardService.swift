import Foundation
import Security

@objc(FlClashGuardControl)
protocol GuardServiceProtocol {
    func perform(_ action: String, reply: @escaping (Int32, String) -> Void)
}

enum GuardService {
    static let name = "local.flclash-egress-guard.control"
    static let directory = URL(fileURLWithPath: "/Library/PrivilegedHelperTools").appendingPathComponent(name)

    static var owner: uid_t? {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("owner"), encoding: .utf8)
        else { return nil }
        return uid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // macOS derives the identity from the administrator-approved copy of the signed app.
    static func approvedRequirement() -> SecRequirement? {
        var code: SecStaticCode?, requirement: SecRequirement?
        let url = directory.appendingPathComponent("Approved.app") as CFURL
        guard SecStaticCodeCreateWithPath(url, [], &code) == errSecSuccess, let code = code,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    static var approved: Bool {
        var ownCode: SecCode?
        guard owner == getuid(), let requirement = approvedRequirement(),
              SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode = ownCode else { return false }
        return SecCodeCheckValidity(ownCode, [], requirement) == errSecSuccess
    }
}
