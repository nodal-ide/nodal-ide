import Foundation

struct NginxPrefix {
    static let defaultRootName = "nginx"

    let root: URL

    static var `default`: NginxPrefix {
        NginxPrefix(
            root: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".codeedit", directoryHint: .isDirectory)
                .appending(path: "proxy", directoryHint: .isDirectory)
                .appending(path: defaultRootName, directoryHint: .isDirectory)
        )
    }

    var mimeTypesURL: URL {
        root.appending(path: "mime.types")
    }

    var generationsDirectory: URL {
        root.appending(path: "generations", directoryHint: .isDirectory)
    }

    var currentSymlink: URL {
        root.appending(path: "current")
    }

    var logsDirectory: URL {
        root.appending(path: "logs", directoryHint: .isDirectory)
    }

    var tempDirectory: URL {
        root.appending(path: "temp", directoryHint: .isDirectory)
    }

    var runDirectory: URL {
        root.appending(path: "run", directoryHint: .isDirectory)
    }

    var pidURL: URL {
        runDirectory.appending(path: "nginx.pid")
    }

    var errorLogURL: URL {
        logsDirectory.appending(path: "nginx.error.log")
    }

    func generationDirectory(named name: String) -> URL {
        generationsDirectory.appending(path: name, directoryHint: .isDirectory)
    }

    func createDirectories() throws {
        let fileManager = FileManager.default
        let directories = [
            root,
            generationsDirectory,
            logsDirectory,
            runDirectory
        ] + Self.tempSubdirectories.map { tempDirectory.appending(path: $0, directoryHint: .isDirectory) }

        for directory in directories {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    private static let tempSubdirectories = [
        "", "client_body", "proxy", "fastcgi", "uwsgi", "scgi"
    ]
}
