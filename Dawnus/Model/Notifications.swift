import Foundation

extension Notification.Name {
    /// 用户答对全部题目、或点了「起床」之后发出——RootView 收到就切到晨间仪式链。
    static let dawnusDidUnlock = Notification.Name("dawnusDidUnlock")
}
