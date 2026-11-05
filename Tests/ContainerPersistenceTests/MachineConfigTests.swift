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

import ContainerPersistence
import ContainerizationError
import Foundation
import SystemPackage
import Testing

struct MachineConfigTests {
    @Test func virtualizationDefaultsToFalse() throws {
        let config = MachineConfig.default
        #expect(config.virtualization == false)
        #expect(config.kernelPath == nil)
    }

    @Test func withSetsVirtualizationTrue() throws {
        let updated = try MachineConfig.default.with(["virtualization": "true"])
        #expect(updated.virtualization == true)
    }

    @Test func withSetsVirtualizationFalse() throws {
        let enabled = try MachineConfig.default.with(["virtualization": "true"])
        let cleared = try enabled.with(["virtualization": "false"])
        #expect(cleared.virtualization == false)
    }

    @Test func withRejectsBogusBoolean() {
        #expect(throws: ContainerizationError.self) {
            try MachineConfig.default.with(["virtualization": "yes"])
        }
    }

    @Test func withSetsKernelPath() throws {
        let updated = try MachineConfig.default.with(["kernel": "/opt/kernels/vmlinux"])
        #expect(updated.kernelPath == FilePath("/opt/kernels/vmlinux"))
    }

    @Test func withEmptyKernelClearsKernelPath() throws {
        let withCustom = try MachineConfig.default.with(["kernel": "/opt/kernels/vmlinux"])
        #expect(withCustom.kernelPath == FilePath("/opt/kernels/vmlinux"))
        let cleared = try withCustom.with(["kernel": ""])
        #expect(cleared.kernelPath == nil)
    }

    @Test func withPreservesUnchangedFields() throws {
        let updated = try MachineConfig.default.with([
            "virtualization": "true",
            "kernel": "/opt/kernels/vmlinux",
        ])
        #expect(updated.cpus == MachineConfig.default.cpus)
        #expect(updated.memory.toUInt64(unit: .bytes) == MachineConfig.default.memory.toUInt64(unit: .bytes))
        #expect(updated.homeMount == MachineConfig.default.homeMount)
    }

    @Test func decodingMissingFieldsUsesDefaults() throws {
        // Older boot-config.json files predate virtualization/kernel — they must still load.
        let legacy = #"{"cpus":4,"memory":"1gb","homeMount":"rw"}"#
        let data = Data(legacy.utf8)
        let decoded = try JSONDecoder().decode(MachineConfig.self, from: data)
        #expect(decoded.cpus == 4)
        #expect(decoded.virtualization == false)
        #expect(decoded.kernelPath == nil)
        #expect(decoded.disks.isEmpty)
    }

    @Test func parseDiskSpec() throws {
        let disk = try MachineDisk.parse("source=/tmp/data.raw,dest=/mnt/btrfs,format=btrfs")
        #expect(disk.source == "/tmp/data.raw")
        #expect(disk.destination == "/mnt/btrfs")
        #expect(disk.format == "btrfs")
        #expect(disk.readonly == false)
        #expect(disk.mountOptions.isEmpty)
    }

    @Test func parseDiskSpecMountOptions() throws {
        let disk = try MachineDisk.parse(
            "source=/tmp/data.raw,dest=/run/fs/control,format=btrfs,subvolid=5,user_subvol_rm_allowed")
        #expect(disk.destination == "/run/fs/control")
        #expect(disk.mountOptions == ["subvolid=5", "user_subvol_rm_allowed"])
        #expect(disk.specString.contains("subvolid=5"))
        #expect(disk.specString.contains("user_subvol_rm_allowed"))
    }

    @Test func parseDiskSpecReadonly() throws {
        let disk = try MachineDisk.parse("source=/tmp/data.raw,destination=/mnt/data,format=ext4,ro")
        #expect(disk.destination == "/mnt/data")
        #expect(disk.format == "ext4")
        #expect(disk.readonly == true)
    }

    @Test func parseDiskSpecRejectsRelativeDest() {
        #expect(throws: ContainerizationError.self) {
            try MachineDisk.parse("source=/tmp/data.raw,dest=mnt/btrfs,format=btrfs")
        }
    }

    @Test func withReplacesDisks() throws {
        let disk = MachineDisk(source: "/tmp/data.raw", destination: "/mnt/btrfs", format: "btrfs")
        let updated = try MachineConfig.default.with([:], disks: [disk])
        #expect(updated.disks == [disk])
        let cleared = try updated.with([:], disks: [])
        #expect(cleared.disks.isEmpty)
    }

    @Test func parseDiskSpecRejectsTrailingComma() {
        #expect(throws: ContainerizationError.self) {
            try MachineDisk.parse("source=/tmp/data.raw,dest=/mnt/btrfs,format=btrfs,")
        }
    }

    @Test func parseDiskSpecRejectsRepeatKey() {
        #expect(throws: ContainerizationError.self) {
            try MachineDisk.parse("source=/tmp/a.raw,source=/tmp/b.raw,dest=/mnt/btrfs,format=btrfs")
        }
        #expect(throws: ContainerizationError.self) {
            try MachineDisk.parse("source=/tmp/a.raw,dest=/mnt/a,destination=/mnt/b,format=btrfs")
        }
    }

    @Test func parseDiskSpecRejectsBadFormat() {
        #expect(throws: ContainerizationError.self) {
            try MachineDisk.parse("source=/tmp/data.raw,dest=/mnt/btrfs,format=bt rfs")
        }
    }

    @Test func withRejectsRepeatGuestPath() throws {
        let first = MachineDisk(source: "/tmp/a.raw", destination: "/mnt/data", format: "ext4")
        let second = MachineDisk(source: "/tmp/b.raw", destination: "/mnt/data", format: "ext4")
        #expect(throws: ContainerizationError.self) {
            try MachineConfig.default.with([:], disks: [first, second])
        }
    }

    @Test func withRejectsRepeatSource() throws {
        let first = MachineDisk(source: "/tmp/a.raw", destination: "/mnt/a", format: "ext4")
        let second = MachineDisk(source: "/tmp/a.raw", destination: "/mnt/b", format: "ext4")
        #expect(throws: ContainerizationError.self) {
            try MachineConfig.default.with([:], disks: [first, second])
        }
    }

    @Test func roundTripJSONIncludesDisks() throws {
        let disk = MachineDisk(source: "/tmp/data.raw", destination: "/mnt/btrfs", format: "btrfs", readonly: true)
        let config = try MachineConfig.default.with([:], disks: [disk])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MachineConfig.self, from: data)
        #expect(decoded.disks == [disk])
    }

    @Test func roundTripJSON() throws {
        let config = try MachineConfig.default.with([
            "virtualization": "true",
            "kernel": "/some/vmlinux",
        ])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MachineConfig.self, from: data)
        #expect(decoded.virtualization == true)
        #expect(decoded.kernelPath == FilePath("/some/vmlinux"))
    }

    @Test func settableKeysIncludeNewFields() {
        let keys = MachineConfig.settableKeys.map(\.key)
        #expect(keys.contains("virtualization"))
        #expect(keys.contains("kernel"))
    }
}
