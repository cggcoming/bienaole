import Foundation

/// App 主进程与 Widget / App Intent 之间交换少量状态的地方。
///
/// 刻意做成**双通道**：
/// - 开了 App Group entitlement（付费开发者账号）时，走真正的共享容器；
/// - 没开（例如用免费个人 Apple ID 真机调试——App Groups 这类 capability 对个人团队不可用）时，
///   自动降级到进程内 `UserDefaults.standard`。
///
/// 于是同一份代码在两种签名环境下都能跑通，真机调试时不必改代码、也不必为签名卡住。
/// 代价是：降级后 Widget 进程读不到主进程新写的值；但实时活动的数据本来是通过
/// `AlarmAttributes` 随闹钟一起下发的，不依赖这条通道，所以功能上无损。
enum SharedStore {

    static let appGroupID = "group.com.dawnus.shared"

    /// 共享容器。未配置 App Group 时为 nil，此时全部走降级通道。
    /// `UserDefaults` 本身线程安全，这里只是为了让 Swift 6 的全局变量检查放行。
    nonisolated(unsafe) private static let group = UserDefaults(suiteName: appGroupID)

    /// 当前是否真的在用共享容器（用于「引擎」页提示，也便于排查签名问题）
    static var isUsingAppGroup: Bool { group != nil }

    static func set(_ value: Any?, forKey key: String) {
        group?.set(value, forKey: key)
        UserDefaults.standard.set(value, forKey: key)
    }

    static func string(forKey key: String) -> String? {
        if let v = group?.string(forKey: key) { return v }
        return UserDefaults.standard.string(forKey: key)
    }

    static func double(forKey key: String) -> Double {
        if let v = group?.object(forKey: key) as? Double { return v }
        return UserDefaults.standard.double(forKey: key)
    }

    static func remove(forKey key: String) {
        group?.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }
}
