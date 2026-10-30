//
//  OnboardingState.swift
//  BreezeSpeak
//
//  首次启动的一次性状态：引导是否走完、免责协议是否已同意。
//  两个标记分开存，协议同意单独可查——后续要改条款时，可以只让协议这一步重来。
//

import Foundation

enum OnboardingState {
    private static let completedKey = "breezespeak.onboarding.completed"
    private static let disclaimerKey = "breezespeak.disclaimer.accepted"
    private static let disclaimerVersionKey = "breezespeak.disclaimer.version"

    /// 当前条款版本。条款有实质修改时 +1，老用户会重新过一遍协议页。
    static let disclaimerVersion = 1

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static var hasAcceptedDisclaimer: Bool {
        UserDefaults.standard.bool(forKey: disclaimerKey)
            && UserDefaults.standard.integer(forKey: disclaimerVersionKey) == disclaimerVersion
    }

    static func acceptDisclaimer() {
        UserDefaults.standard.set(true, forKey: disclaimerKey)
        UserDefaults.standard.set(disclaimerVersion, forKey: disclaimerVersionKey)
    }

    static func complete() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// 调试用：清掉标记，下次启动重新走引导
    static func reset() {
        UserDefaults.standard.removeObject(forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: disclaimerKey)
        UserDefaults.standard.removeObject(forKey: disclaimerVersionKey)
    }
}
