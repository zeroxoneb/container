//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc. and the container project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import ContainerizationError
import Foundation

/// A host raw disk image attached to a container machine as virtio-blk.
///
/// `format` is the filesystem type vminitd uses to mount the device (for example
/// `btrfs` or `ext4`). The image must already contain that filesystem; this does
/// not format the disk.
public struct MachineDisk: Codable, Sendable, Equatable {
    /// Absolute path to a raw disk image on the Mac host.
    public var source: String
    /// Absolute path inside the guest where the filesystem is mounted.
    public var destination: String
    /// Guest filesystem type passed to mount(2), for example `btrfs`.
    public var format: String
    /// When true, the guest mount is read-only.
    public var readonly: Bool
    /// Extra guest mount(2) options, for example `subvolid=5`.
    public var mountOptions: [String]

    public init(
        source: String, destination: String, format: String, readonly: Bool = false, mountOptions: [String] = []
    ) {
        self.source = source
        self.destination = destination
        self.format = format
        self.readonly = readonly
        self.mountOptions = mountOptions
    }

    /// Canonical CLI/config form: `source=PATH,dest=PATH,format=FS[,ro][,k=v...]`.
    public var specString: String {
        var parts = [
            "source=\(source)",
            "dest=\(destination)",
            "format=\(format)",
        ]
        if readonly {
            parts.append("ro")
        }
        parts.append(contentsOf: mountOptions)
        return parts.joined(separator: ",")
    }

    /// Parse `source=PATH,dest=PATH,format=FS[,ro][,k=v...]`.
    public static func parse(_ spec: String) throws -> MachineDisk {
        var source: String?
        var destination: String?
        var format: String?
        var readonly = false
        var mountOptions: [String] = []
        var seenKeys: Set<String> = []

        func claim(_ key: String) throws {
            guard seenKeys.insert(key).inserted else {
                throw ContainerizationError(.invalidArgument, message: "disk spec repeats '\(key)='")
            }
        }
        func addMountOption(_ option: String) throws {
            guard !option.isEmpty, !option.contains(where: \.isWhitespace) else {
                throw ContainerizationError(.invalidArgument, message: "disk spec has a bad mount option '\(option)'")
            }
            guard !mountOptions.contains(option) else {
                throw ContainerizationError(.invalidArgument, message: "disk spec repeats mount option '\(option)'")
            }
            mountOptions.append(option)
        }

        guard !spec.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ContainerizationError(.invalidArgument, message: "disk spec is empty")
        }
        for part in spec.split(separator: ",", omittingEmptySubsequences: false) {
            let piece = part.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else {
                throw ContainerizationError(.invalidArgument, message: "disk spec has an empty field")
            }
            if piece == "ro" {
                try claim("ro")
                readonly = true
                continue
            }
            let kv = piece.split(separator: "=", maxSplits: 1)
            if kv.count != 2 {
                // Flag-style mount option, e.g. user_subvol_rm_allowed.
                try addMountOption(piece)
                continue
            }
            let key = String(kv[0]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(kv[1]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else {
                throw ContainerizationError(.invalidArgument, message: "disk spec field '\(piece)' needs a name and a value")
            }
            switch key {
            case "source":
                try claim("source")
                source = value
            case "dest", "destination":
                try claim("dest")
                destination = value
            case "format":
                try claim("format")
                format = value
            case "ro":
                try claim("ro")
                readonly = Self.parseBool(value)
            default:
                // Pass through as a mount option (e.g. subvolid=5).
                try addMountOption("\(key)=\(value)")
            }
        }

        guard let source, !source.isEmpty else {
            throw ContainerizationError(.invalidArgument, message: "disk spec missing source=PATH")
        }
        guard let destination, destination.hasPrefix("/"), destination != "/" else {
            throw ContainerizationError(
                .invalidArgument,
                message: "disk spec dest must be an absolute guest path below / (got '\(destination ?? "")')"
            )
        }
        guard let format, Self.isValidFormat(format) else {
            throw ContainerizationError(.invalidArgument, message: "disk spec format must be one filesystem name (e.g. format=btrfs)")
        }

        let disk = MachineDisk(
            source: URL(fileURLWithPath: source).path,
            destination: destination,
            format: format,
            readonly: readonly,
            mountOptions: mountOptions
        )
        try Self.validate(disk)
        return disk
    }

    /// Check one disk field set. This does not read the host file.
    public static func validate(_ disk: MachineDisk) throws {
        guard !disk.source.isEmpty else {
            throw ContainerizationError(.invalidArgument, message: "disk spec missing source=PATH")
        }
        guard disk.destination.hasPrefix("/"), disk.destination != "/" else {
            throw ContainerizationError(
                .invalidArgument,
                message: "disk spec dest must be an absolute guest path below / (got '\(disk.destination)')"
            )
        }
        guard Self.isValidFormat(disk.format) else {
            throw ContainerizationError(.invalidArgument, message: "disk spec format must be one filesystem name (e.g. format=btrfs)")
        }
        var seenOptions: Set<String> = []
        for option in disk.mountOptions {
            guard !option.isEmpty, !option.contains(where: \.isWhitespace) else {
                throw ContainerizationError(.invalidArgument, message: "disk spec has a bad mount option '\(option)'")
            }
            guard seenOptions.insert(option).inserted else {
                throw ContainerizationError(.invalidArgument, message: "disk spec repeats mount option '\(option)'")
            }
        }
    }

    /// Check a disk list for repeat host files and repeat guest paths.
    public static func validateList(_ disks: [MachineDisk]) throws {
        var sources: Set<String> = []
        var destinations: Set<String> = []
        for disk in disks {
            try Self.validate(disk)
            let source = URL(fileURLWithPath: disk.source).path
            guard sources.insert(source).inserted else {
                throw ContainerizationError(.invalidArgument, message: "two disks use the same source '\(source)'")
            }
            guard destinations.insert(disk.destination).inserted else {
                throw ContainerizationError(.invalidArgument, message: "two disks use the same dest '\(disk.destination)'")
            }
        }
    }

    private static func isValidFormat(_ format: String) -> Bool {
        !format.isEmpty && format.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
    }

    /// Confirm the host image exists and is a non-empty raw file whose size is a multiple of 512.
    public static func validateSource(_ path: String) throws {
        let absolute = URL(fileURLWithPath: path).path
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: absolute, isDirectory: &isDirectory) else {
            throw ContainerizationError(.invalidArgument, message: "disk image not found at '\(absolute)'")
        }
        guard !isDirectory.boolValue else {
            throw ContainerizationError(.invalidArgument, message: "disk path '\(absolute)' is a directory, expected a raw image file")
        }
        guard fm.isReadableFile(atPath: absolute) else {
            throw ContainerizationError(.invalidArgument, message: "disk image at '\(absolute)' is not readable")
        }
        let attrs = try fm.attributesOfItem(atPath: absolute)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        guard size > 0 else {
            throw ContainerizationError(.invalidArgument, message: "disk image at '\(absolute)' is empty")
        }
        guard size.isMultiple(of: 512) else {
            throw ContainerizationError(
                .invalidArgument,
                message: "disk image at '\(absolute)' size \(size) is not a multiple of 512 bytes"
            )
        }
    }

    private static func parseBool(_ value: String) -> Bool {
        ["1", "true", "yes"].contains(value.lowercased())
    }
}
