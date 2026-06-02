//
//  JSController.swift
//  Celestia
//
//  Created by Francesco on 02/06/26.
//

import JavaScriptCore

final class JSController {
    let moduleName: String
    var context: JSContext
    
    init(moduleName: String, script: String) {
        self.moduleName = moduleName
        guard let ctx = JSContext() else {
            fatalError("Unable to create JavaScript context")
        }
        self.context = ctx
        setupContext()
        loadScript(script)
    }
    
    func setupContext() {
        context.setupJavaScriptEnvironment()
        context.exceptionHandler = { [weak self] _, exception in
            let name = self?.moduleName ?? "Unknown"
            Logger.shared.log("[Module \(name)] JS exception: \(exception?.toString() ?? "unknown")", type: "Error")
        }
    }
    
    func loadScript(_ script: String) {
        context = JSContext()!
        setupContext()
        context.evaluateScript(script)
        if let exception = context.exception {
            Logger.shared.log("Error loading script for \(moduleName): \(exception)", type: "Error")
        }
    }
}

final class Logger {
    static let shared = Logger()
    private init() {}
    
    func log(_ message: String, type: String = "Info") {
        print("[\(type)] \(message)")
    }
}
