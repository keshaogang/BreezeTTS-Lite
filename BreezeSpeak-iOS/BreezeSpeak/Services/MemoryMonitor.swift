//
//  MemoryMonitor.swift
//  BreezeSpeak
//
//  内存 / 显存监视。MLX 使用统一内存，进程 footprint 即近似显存占用。
//

import Foundation
import SwiftUI

enum DeviceMemory {
    /// 当前进程已用内存（phys_footprint）
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    /// 还能给本进程使用的内存（iOS 15+）
    static func available() -> UInt64 {
        let value = os_proc_available_memory()
        return value > 0 ? UInt64(value) : 0
    }

    static var total: UInt64 { ProcessInfo.processInfo.physicalMemory }
}

@MainActor
final class MemoryMonitor: ObservableObject {
    @Published private(set) var footprint: UInt64 = 0
    @Published private(set) var available: UInt64 = 0
    @Published private(set) var peak: UInt64 = 0
    /// 推理期间由引擎上报的 MLX 活跃显存估算
    @Published var mlxActive: UInt64 = 0
    @Published private(set) var isRunning = false
    /// true 表示 os_proc_available_memory 不可用（模拟器恒为 0），当前值是总量减 footprint 的估算
    @Published private(set) var availableIsEstimate = false

    private var timer: Timer?

    var total: UInt64 { DeviceMemory.total }
    var deviceBudget: UInt64 { ProcessInfo.processInfo.physicalMemory }

    var usageFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(footprint) / Double(total))
    }

    var availableFraction: Double {
        guard available > 0, total > 0 else { return 0 }
        return min(1, Double(available) / Double(total))
    }

    /// 余量语义说明：
    /// `os_proc_available_memory()` 返回的是「离被系统（jetsam）杀掉还有多远」，
    /// 而不是「还能不能再跑一次推理」。mmap 进来的权重本身就算在这份配额里，
    /// 所以权重常驻之后这个值只剩几百 MB 是完全正常的。
    var isHeadroomCritical: Bool {
        available > 0 && available < 150_000_000
    }

    var pressureLabel: String {
        if isHeadroomCritical { return "危险" }
        if usageFraction > 0.86 { return "偏高" }
        return "正常"
    }

    var pressureColor: Color {
        if isHeadroomCritical { return Palette.danger }
        if usageFraction > 0.86 { return Palette.peach }
        return Palette.mint
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        mlxActive = 0
    }

    func sample() {
        footprint = DeviceMemory.footprint()
        let reported = DeviceMemory.available()
        availableIsEstimate = reported == 0
        available = reported > 0 ? reported : max(0, DeviceMemory.total - footprint)
        peak = max(peak, footprint)
    }

    func resetPeak() {
        peak = footprint
    }
}
