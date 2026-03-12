//
//  Notification+Extension.swift
//  Qiri
//
//  Created by 김은찬 on 10/21/25.
//

import Foundation

extension Notification.Name {
    static let sttCompleted = Notification.Name("sttCompleted")
    static let sttResponseUpdated = Notification.Name("sttResponseUpdated")
    static let sttCleanResponseUpdated = Notification.Name("sttCleanResponseUpdated")
    static let sttError = Notification.Name("sttError")
    static let sttResponseCompleted = Notification.Name("sttResponseCompleted")
    static let WCSessionMessageReceived = Notification.Name("WCSessionMessageReceived")
    static let moveToAnswerMore = Notification.Name("moveToAnswerMore")
    static let sttResponseStarted = Notification.Name("sttResponseStarted")
    static let returnToMain = Notification.Name("returnToMain")
    static let processSpeechInput = Notification.Name("processSpeechInput")
}
