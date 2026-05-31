//
//  ModuleRuntime.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import Foundation
import JavaScriptCore

final class ModuleRuntime {
    private let module: ModuleDefinition
    private let context: JSContext
    private let contextQueue: DispatchQueue
    private var lastException: JSValue?

    init(module: ModuleDefinition) throws {
        self.module = module
        self.contextQueue = DispatchQueue(label: "celestia.module.context.\(module.id)")

        guard let context = JSContext() else {
            throw RuntimeError.contextCreationFailed
        }
        self.context = context

        var initError: Error?
        contextQueue.sync {
            do {
                configureContext()
                try evaluateScript(module.script)
                try validateExports()
            } catch {
                initError = error
            }
        }
        if let initError { throw initError }
    }

    // MARK: - Public API

    func searchResults(keyword: String) async throws -> Any {
        try await call(function: .searchResults, argument: keyword)
    }

    func extractDetails(url: String) async throws -> Any {
        try await call(function: .extractDetails, argument: url)
    }

    func extractEpisodes(url: String) async throws -> Any {
        try await call(function: .extractEpisodes, argument: url)
    }

    func extractStreamUrl(url: String) async throws -> Any {
        try await call(function: .extractStreamUrl, argument: url)
    }
}

// MARK: - Errors & Enums

private extension ModuleRuntime {
    enum ModuleFunction: String, CaseIterable {
        case searchResults
        case extractDetails
        case extractEpisodes
        case extractStreamUrl
    }

    enum RuntimeError: LocalizedError {
        case contextCreationFailed
        case missingExport(String)
        case javaScriptException(String)
        case invalidURL(String)
        case invalidFunctionResult(String)

        var errorDescription: String? {
            switch self {
            case .contextCreationFailed:          return "Unable to create JavaScript context."
            case .missingExport(let name):        return "Module script did not export required function: \(name)."
            case .javaScriptException(let msg):   return "JavaScript exception: \(msg)"
            case .invalidURL(let url):            return "Invalid URL provided to fetch: \(url)"
            case .invalidFunctionResult(let fn):  return "Module function returned invalid result: \(fn)"
            }
        }
    }
}

// MARK: - Context Setup

private extension ModuleRuntime {
    func configureContext() {
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastException = exception
            let name = self?.module.name ?? "Unknown"
            print("[Module \(name)] JS exception: \(exception?.toString() ?? "Unknown")")
        }

        setupConsole()
        setupBase64()
        setupFetch()
        setupFetchV2Native()
        setupFetchV2Shim()
        setupScrapingUtilities()
    }

    func validateExports() throws {
        for fn in ModuleFunction.allCases {
            let value = context.objectForKeyedSubscript(fn.rawValue as NSString)
            guard value?.isUndefined == false else {
                throw RuntimeError.missingExport(fn.rawValue)
            }
        }
    }

    func evaluateScript(_ script: String) throws {
        context.evaluateScript(script)
        if let exception = lastException {
            lastException = nil
            throw RuntimeError.javaScriptException(exception.toString() ?? "Unknown")
        }
    }
}

// MARK: - JS Globals: Console & Base64

private extension ModuleRuntime {
    func setupConsole() {
        let name = module.name
        let log: @convention(block) (JSValue) -> Void = { value in
            print("[Module \(name)] \(value.isUndefined ? "undefined" : value.toString() ?? "")")
        }
        let console = JSValue(newObjectIn: context)
        console?.setValue(log, forProperty: "log")
        console?.setValue(log, forProperty: "error")
        context.setObject(console, forKeyedSubscript: "console" as NSString)
        context.setObject(log, forKeyedSubscript: "log" as NSString)
    }

    func setupBase64() {
        let btoa: @convention(block) (String) -> String? = { str in
            str.data(using: .utf8)?.base64EncodedString()
        }
        let atob: @convention(block) (String) -> String? = { base64 in
            Data(base64Encoded: base64).flatMap { String(data: $0, encoding: .utf8) }
        }
        context.setObject(btoa, forKeyedSubscript: "btoa" as NSString)
        context.setObject(atob, forKeyedSubscript: "atob" as NSString)
    }
}

// MARK: - JS Globals: fetch (v1)

private extension ModuleRuntime {
    func setupFetch() {
        let ctx = context
        let queue = contextQueue

        let fetchBlock: @convention(block) (String, JSValue?) -> JSValue = { urlString, options in
            JSValue(newPromiseIn: ctx) { resolve, reject in
                Task {
                    do {
                        var request = try Self.buildRequest(urlString: urlString, options: options)
                        let (data, response) = try await URLSession.shared.data(for: request)
                        let responseValue = Self.buildFetchResponse(data: data, response: response, context: ctx)
                        queue.async { resolve?.call(withArguments: [responseValue as Any]) }
                    } catch {
                        queue.async { reject?.call(withArguments: [error.localizedDescription]) }
                    }
                }
            } ?? JSValue(undefinedIn: ctx)
        }

        context.setObject(fetchBlock, forKeyedSubscript: "fetch" as NSString)
    }

    static func buildRequest(urlString: String, options: JSValue?) throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            throw RuntimeError.invalidURL(urlString)
        }
        var request = URLRequest(url: url)
        guard let options, !options.isUndefined, !options.isNull else { return request }

        if let method = options.forProperty("method")?.toString() {
            request.httpMethod = method
        }
        if let headers = options.forProperty("headers")?.toDictionary() as? [String: Any] {
            headers.forEach { request.setValue("\($1)", forHTTPHeaderField: $0) }
        }
        if let body = options.forProperty("body")?.toString() {
            request.httpBody = body.data(using: .utf8)
        }
        return request
    }

    static func buildFetchResponse(data: Data, response: URLResponse, context: JSContext) -> JSValue? {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let bodyString = String(data: data, encoding: .utf8) ?? ""
        let jsonObject = try? JSONSerialization.jsonObject(with: data)

        let obj = JSValue(newObjectIn: context)
        obj?.setValue(status, forProperty: "status")
        obj?.setValue((200..<300).contains(status), forProperty: "ok")

        let text: @convention(block) () -> JSValue = {
            JSValue(newPromiseIn: context) { resolve, _ in
                resolve?.call(withArguments: [bodyString])
            } ?? JSValue(undefinedIn: context)
        }
        let json: @convention(block) () -> JSValue = {
            JSValue(newPromiseIn: context) { resolve, reject in
                if let jsonObject { resolve?.call(withArguments: [jsonObject]) }
                else { reject?.call(withArguments: ["Invalid JSON"]) }
            } ?? JSValue(undefinedIn: context)
        }

        obj?.setValue(text, forProperty: "text")
        obj?.setValue(json, forProperty: "json")
        return obj
    }
}

// MARK: - JS Globals: fetchV2

private extension ModuleRuntime {
    func setupFetchV2Shim() {
        context.evaluateScript("""
        function fetchv2(url, headers = {}, method = "GET", body = null, redirect = true, encoding) {
            var processedBody = (method !== "GET" && body)
                ? ((typeof body === 'object') ? JSON.stringify(body) : body)
                : null;
            var processedHeaders = (headers && typeof headers === 'object' && !Array.isArray(headers))
                ? headers : {};
            return new Promise(function(resolve, reject) {
                fetchV2Native(url, processedHeaders, method, processedBody, redirect, encoding || "utf-8",
                    function(rawText) {
                        resolve({
                            headers: rawText.headers,
                            status: rawText.status,
                            _data: rawText.body,
                            text: function() { return Promise.resolve(this._data); },
                            json: function() {
                                try { return Promise.resolve(JSON.parse(this._data)); }
                                catch (e) { return Promise.reject("JSON parse error: " + e.message); }
                            }
                        });
                    }, reject);
            });
        }
        """)
    }

    func setupFetchV2Native() {
        let queue = contextQueue

        let block: @convention(block) (String, Any?, String?, String?, ObjCBool, String?, JSValue, JSValue) -> Void = {
            [weak self] urlString, headersAny, method, body, redirect, encoding, resolve, reject in
            guard let self else { return }

            guard let url = URL(string: urlString) else {
                queue.async { resolve.call(withArguments: [["error": "Invalid URL"]]) }
                return
            }

            let httpMethod = method ?? "GET"
            let bodyIsEmpty = body == nil || body?.isEmpty == true || body == "null" || body == "undefined"

            if httpMethod == "GET" && !bodyIsEmpty {
                queue.async { resolve.call(withArguments: [["error": "GET request must not have a body"]]) }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = httpMethod

            if let headers = Self.parseHeaders(headersAny) {
                headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            }
            if httpMethod != "GET", let body, !bodyIsEmpty {
                request.httpBody = body.data(using: .utf8)
            }

            let encoding = self.encodingFromString(encoding)
            let handler = FetchV2RedirectHandler(allowRedirects: redirect.boolValue)
            let session = URLSession(configuration: .ephemeral, delegate: handler, delegateQueue: nil)

            session.downloadTask(with: request) { tempURL, response, error in
                defer { session.finishTasksAndInvalidate() }

                let callResolve: ([String: Any]) -> Void = { dict in
                    queue.async { if !resolve.isUndefined { resolve.call(withArguments: [dict]) } }
                }

                if let error { callResolve(["error": error.localizedDescription]); return }
                guard let tempURL else { callResolve(["error": "No data"]); return }

                let headers = (response as? HTTPURLResponse)
                    .map { Self.stringifiedHeaders($0.allHeaderFields) } ?? [:]
                var result: [String: Any] = [
                    "status": (response as? HTTPURLResponse)?.statusCode ?? 0,
                    "headers": headers,
                    "body": ""
                ]

                do {
                    let data = try Data(contentsOf: tempURL)
                    guard data.count <= 10_000_000 else {
                        callResolve(["error": "Response exceeds maximum size"]); return
                    }
                    result["body"] = String(data: data, encoding: encoding)
                        ?? String(data: data, encoding: .utf8)
                        ?? ""
                    callResolve(result)
                } catch {
                    callResolve(["error": "Error reading downloaded file"])
                }
            }.resume()
        }

        context.setObject(block, forKeyedSubscript: "fetchV2Native" as NSString)
    }

    static func parseHeaders(_ raw: Any?) -> [String: String]? {
        let dict: [AnyHashable: Any]?
        if let d = raw as? [String: Any]       { dict = d }
        else if let d = raw as? [AnyHashable: Any] { dict = d }
        else { return nil }

        guard let dict else { return nil }
        var result: [String: String] = [:]
        for (key, value) in dict {
            guard !(value is NSNull) else { continue }
            let k = String(describing: key)
            let v = (value as? String) ?? (value as? NSNumber)?.stringValue ?? String(describing: value)
            result[k] = v
        }
        return result.isEmpty ? nil : result
    }

    static func stringifiedHeaders(_ fields: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in fields {
            guard let k = key as? String else { continue }
            result[k] = (value as? String) ?? String(describing: value)
        }
        return result
    }

    func encodingFromString(_ string: String?) -> String.Encoding {
        switch string?.lowercased() {
        case "windows-1251", "cp1251":  return .windowsCP1251
        case "windows-1252", "cp1252":  return .windowsCP1252
        case "iso-8859-1", "latin1":    return .isoLatin1
        case "ascii":                   return .ascii
        case "utf-16", "utf16":         return .utf16
        default:                        return .utf8
        }
    }
}

// MARK: - JS Globals: Scraping Utilities

private extension ModuleRuntime {
    func setupScrapingUtilities() {
        context.evaluateScript("""
        function getElementsByTag(html, tag) {
            const regex = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'gi');
            let result = [], match;
            while ((match = regex.exec(html)) !== null) result.push(match[1]);
            return result;
        }
        function getAttribute(html, tag, attr) {
            const regex = new RegExp(`<${tag}[^>]*${attr}=["']?([^"' >]+)["']?[^>]*>`, 'i');
            const match = regex.exec(html);
            return match ? match[1] : null;
        }
        function getInnerText(html) {
            return html.replace(/<[^>]+>/g, '').replace(/\\s+/g, ' ').trim();
        }
        function extractBetween(str, start, end) {
            const s = str.indexOf(start);
            if (s === -1) return '';
            const e = str.indexOf(end, s + start.length);
            if (e === -1) return '';
            return str.substring(s + start.length, e);
        }
        function stripHtml(html) { return html.replace(/<[^>]+>/g, ''); }
        function normalizeWhitespace(str) { return str.replace(/\\s+/g, ' ').trim(); }
        function urlEncode(str) { return encodeURIComponent(str); }
        function urlDecode(str) { try { return decodeURIComponent(str); } catch (e) { return str; } }
        function htmlEntityDecode(str) {
            return str.replace(/&([a-zA-Z]+);/g, function(_, entity) {
                const map = { quot: '"', apos: "'", amp: '&', lt: '<', gt: '>' };
                return map[entity] || _;
            });
        }
        function transformResponse(response, fn) { try { return fn(response); } catch (e) { return response; } }
        """)
    }
}

// MARK: - Call & Promise Resolution

private extension ModuleRuntime {
    func call(function fn: ModuleFunction, argument: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            contextQueue.async {
                do {
                    let jsFunction = self.context.objectForKeyedSubscript(fn.rawValue as NSString)
                    let result = jsFunction?.call(withArguments: [argument])

                    if let exception = self.lastException {
                        self.lastException = nil
                        throw RuntimeError.javaScriptException(exception.toString() ?? "Unknown")
                    }
                    guard let result else { throw RuntimeError.invalidFunctionResult(fn.rawValue) }

                    if self.isPromise(result) {
                        self.resolvePromise(result, functionName: fn.rawValue, continuation: continuation)
                    } else {
                        continuation.resume(returning: try self.normalizeOutput(result))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func resolvePromise(_ promise: JSValue, functionName: String, continuation: CheckedContinuation<Any, Error>) {
        let onFulfilled: @convention(block) (JSValue) -> Void = { [weak self] value in
            do {
                continuation.resume(returning: try self?.normalizeOutput(value) ?? NSNull())
            } catch {
                continuation.resume(throwing: error)
            }
        }
        let onRejected: @convention(block) (JSValue) -> Void = { value in
            continuation.resume(throwing: RuntimeError.javaScriptException(value.toString() ?? "Unknown"))
        }
        promise.invokeMethod("then", withArguments: [onFulfilled])
        promise.invokeMethod("catch", withArguments: [onRejected])
    }

    func isPromise(_ value: JSValue) -> Bool {
        value.isObject && value.forProperty("then")?.isObject == true
    }

    func normalizeOutput(_ value: JSValue) throws -> Any {
        if value.isUndefined || value.isNull { return NSNull() }
        return value.toObject() ?? value.toString() ?? NSNull()
    }
}

// MARK: - Redirect Handler

private final class FetchV2RedirectHandler: NSObject, URLSessionTaskDelegate {
    private let allowRedirects: Bool

    init(allowRedirects: Bool) {
        self.allowRedirects = allowRedirects
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(allowRedirects ? request : nil)
    }
}
