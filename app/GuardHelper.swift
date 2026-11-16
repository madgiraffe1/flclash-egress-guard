import Foundation
import Security

final class Helper: NSObject, NSXPCListenerDelegate, GuardServiceProtocol {
    private let work = DispatchQueue(label: GuardService.name)
    private let actions: Set<String> = ["status", "preview", "lock", "start", "enable",
                                         "boot-on", "boot-off", "disable", "rollback"]

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == GuardService.owner else { return false }
        connection.exportedInterface = NSXPCInterface(with: GuardServiceProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func perform(_ action: String, reply: @escaping (Int32, String) -> Void) {
        guard actions.contains(action), let uid = GuardService.owner else { reply(1, "此操作不可用。"); return }
        work.async {
            let resources = GuardService.directory.appendingPathComponent("Approved.app/Contents/Resources")
            let task = Process(), output = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = ["-I", "-B", resources.appendingPathComponent("egress-guard").path, action]
            if action == "start" { task.arguments?.append(String(uid)) }
            task.currentDirectoryURL = URL(fileURLWithPath: "/")
            task.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = output
            task.standardError = output
            do {
                try task.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                reply(task.terminationStatus, String(decoding: data, as: UTF8.self))
            } catch { reply(1, "系统助手未能启动防火墙控制器。") }
        }
    }
}

@main enum HelperMain {
    static func main() {
        guard let requirement = GuardService.approvedRequirement() else { exit(1) }
        var rule: CFString?
        guard SecRequirementCopyString(requirement, [], &rule) == errSecSuccess, let rule = rule else { exit(1) }
        let delegate = Helper(), listener = NSXPCListener(machServiceName: GuardService.name)
        listener.setConnectionCodeSigningRequirement(rule as String)
        listener.delegate = delegate
        listener.resume()
        withExtendedLifetime((delegate, listener)) { RunLoop.current.run() }
    }
}
