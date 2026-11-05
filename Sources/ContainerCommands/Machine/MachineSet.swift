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

import ArgumentParser
import ContainerAPIClient
import ContainerPersistence
import ContainerizationError
import Foundation
import MachineAPIClient

extension Application {
    public struct MachineSet: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Set container machine configuration values"
        )

        @OptionGroup
        public var logOptions: Flags.Logging

        @Option(name: [.short, .long], help: "Container machine ID (uses default if not specified)")
        public var name: String?

        @Option(
            name: .long,
            help: "Replace extra disks (source=PATH,dest=PATH,format=FS[,ro][,k=v...]). Repeatable."
        )
        public var disk: [String] = []

        @Flag(name: .customLong("disk-clear"), help: "Remove all extra disks")
        public var diskClear: Bool = false

        @Argument(
            parsing: .remaining,
            help: ArgumentHelp(
                "Configuration values",
                discussion: MachineConfig.helpText(),
                valueName: "setting"
            )
        )
        public var rawArgs: [String] = []

        public func run() async throws {
            guard !rawArgs.isEmpty || !disk.isEmpty || diskClear else {
                throw ContainerizationError(.invalidArgument, message: "expected at least one configuration value (e.g., machine set cpus=4)")
            }

            let client = MachineClient()
            let resolvedName = try await resolveMachineId(name, client: client)
            let snapshot = try await client.inspect(id: resolvedName)

            let kwargs = Dictionary(
                try rawArgs.map { arg in
                    let parts = arg.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else {
                        throw ContainerizationError(.invalidArgument, message: "invalid argument format '\(arg)'. Expected 'key=value'")
                    }

                    return (String(parts[0]), String(parts[1]))
                },
                uniquingKeysWith: { _, last in last }
            )

            if kwargs["virtualization"] == "true" {
                try MachineCapabilities.requireNestedVirtualizationSupported()
            }
            var validatedKwargs = kwargs
            if let raw = kwargs["kernel"], !raw.isEmpty {
                validatedKwargs["kernel"] = try MachineConfig.validateKernelPath(raw).string
            }

            if diskClear && !disk.isEmpty {
                throw ContainerizationError(
                    .invalidArgument,
                    message: "cannot combine --disk-clear with --disk"
                )
            }
            let disks: [MachineDisk]?
            if diskClear {
                disks = []
            } else if !disk.isEmpty {
                disks = try disk.map { spec in
                    let parsed = try MachineDisk.parse(spec)
                    try MachineDisk.validateSource(parsed.source)
                    return parsed
                }
            } else {
                disks = nil
            }

            let newConfig = try snapshot.bootConfig.with(validatedKwargs, disks: disks)

            try await client.setConfig(id: resolvedName, bootConfig: newConfig)

            if snapshot.status == .running {
                FileHandle.standardError.write(
                    Data("Note: Changes will take effect after stopping and restarting '\(resolvedName)'.\n".utf8))
            }

            print(resolvedName)
        }
    }
}
