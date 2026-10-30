//
//  InferenceBackend.swift
//  BreezeSpeak
//
//  推理后端固定策略：默认就是最快的，不给用户选项。
//
//  依据（同一台 8 GB iPad Air M3，同进程、同热状态、同一句 15 字、同一份 Q8_0 权重）：
//      GPU 请求  · 音频 2.88 秒 / 耗时 29.08 秒 · 0.099× 实时
//      CPU       · 音频 2.80 秒 / 耗时 12.69 秒 · 0.221× 实时
//  CPU 快 2.2 倍。原因是权重体积接近设备内存上限时，Metal 要额外准备一份常驻缓冲，
//  搬数据的代价超过了并行计算的收益；CPU 路径是纯带宽受限，反而稳。
//
//  所以这里不再「有 GPU 就用 GPU」，而是直接选 CPU。想验证 GPU 是否已经调优好，
//  用启动参数 `-gpuEngine` 打开即可（只在 DEBUG 里用于对照测速）。
//

import Foundation

enum InferenceBackend {
    /// 真正传给引擎的 `useGPU`。
    static var usesGPU: Bool {
        #if targetEnvironment(simulator)
        // 模拟器的 Metal 设备用 XPC 共享内存搬运权重，GB 级缓冲会直接 trap
        return false
        #else
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-gpuEngine") { return true }
        #endif
        return false
        #endif
    }

    /// 界面上展示的后端名。注意这是「请求值」——引擎是闭源静态库，
    /// Metal 初始化失败会静默回退 CPU，App 侧查不到真相。
    static var label: String { usesGPU ? "GPU" : "CPU" }
}
