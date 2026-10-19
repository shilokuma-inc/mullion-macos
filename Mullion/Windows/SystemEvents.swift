//
//  SystemEvents.swift
//  Mullion
//

import AppKit

/// System Events に Apple Events を送り、ほかのアプリのウィンドウの位置と大きさを読み書きする。
///
/// 送れる相手は entitlements の temporary-exception.apple-events で System Events（com.apple.systemevents）だけに絞っている。
/// ウィンドウを操作するには、Mullion に「オートメーション」（System Events）と「アクセシビリティ」の許可が要る。
/// NSAppleScript はメインスレッドでしか使えず、許可の確認が出ている間は画面が止まるため、CompanionShortcut と同じく
/// NSAppleEventDescriptor を組み立ててメインスレッドの外で送る
nonisolated struct SystemEvents: Sendable {
    typealias Failure = SystemEventsWindowMover.Failure

    static let bundleIdentifier = "com.apple.systemevents"

    /// 1 回の送信を待つ上限（秒）。初めてのときは許可の確認に答えるまで返事が来ない
    var timeout: TimeInterval = 30
    /// System Events を起動したあとに送り直す回数（起動の直後は Apple Events を受け付けるまで少しかかることがある）
    var retriesAfterLaunch = 10
    /// 送り直す間隔
    var retryDelay: Duration = .milliseconds(200)

    /// SystemEventsWindowMover に渡す形
    var client: SystemEventsWindowMover.Client {
        SystemEventsWindowMover.Client(
            windowFrames: { try await windowFrames(pid: $0) },
            perform: { try await perform($0, pid: $1, expected: $2, target: $3) }
        )
    }

    /// プロセスのウィンドウ（しまってあるものを含む）の位置と大きさ。AppleScript の
    /// `{position, size} of every window of (first process whose unix id is pid)` にあたる
    @concurrent
    func windowFrames(pid: pid_t) async throws -> [CGRect] {
        let windows = Self.everyWindow(of: Self.process(pid: pid))
        let positions = try await send(Self.getEvent(Self.property("posn", of: windows)))
        let sizes = try await send(Self.getEvent(Self.property("ptsz", of: windows)))
        // 位置と大きさを別々に読むので、間にウィンドウが開閉されると組み合わせがずれることがある。数えるのと許可の確認にだけ使う
        return Self.frames(positions: Self.reply(positions), sizes: Self.reply(sizes))
    }

    /// AppleScript の `set size of (first window of process whose position is {x, y} and size is {w, h}) to {…}` にあたる。
    /// どのウィンドウを動かすかを System Events に選ばせるので、選んでから動かすまでの間に別のウィンドウに入れ替わらない
    @concurrent
    func perform(_ operation: SystemEventsWindowMover.Operation, pid: pid_t, expected: CGRect, target: CGRect) async throws {
        let window = Self.window(matching: expected, of: Self.process(pid: pid))
        let event = switch operation {
        case .resize: Self.setEvent(Self.property("ptsz", of: window), to: Self.pair(target.width, target.height))
        case .move: Self.setEvent(Self.property("posn", of: window), to: Self.pair(target.minX, target.minY))
        }
        _ = try await send(event)
    }

    // MARK: - 送信

    private func send(_ event: NSAppleEventDescriptor) async throws -> NSAppleEventDescriptor {
        try await Self.sendLaunchingIfNeeded(retries: retriesAfterLaunch, retryDelay: retryDelay) {
            try sendOnce(event)
        } launch: {
            try await Self.launchSystemEvents()
        }
    }

    /// send で送り、System Events が動いていなくて届かなかったら、launch で起動してから retries 回まで送り直す
    static func sendLaunchingIfNeeded<Reply>(
        retries: Int,
        retryDelay: Duration,
        send: () throws -> Reply,
        launch: () async throws -> Void
    ) async throws -> Reply {
        do {
            return try send()
        } catch Failure.systemEventsUnavailable {
            try await launch()
        }
        var attempt = 1
        while true {
            do {
                return try send()
            } catch Failure.systemEventsUnavailable where attempt < retries {
                attempt += 1
                try await Task.sleep(for: retryDelay)
            }
        }
    }

    /// System Events を手前に出さずに起動する
    private static func launchSystemEvents() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw Failure.systemEventsUnavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw Failure.systemEventsUnavailable
        }
    }

    private func sendOnce(_ event: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: timeout)
        } catch let error as NSError {
            throw Failure.from(code: error.code, message: error.localizedDescription)
        }
        // System Events の中で起きたエラー（許可が無い・ウィンドウが無いなど）は、返事の中のエラー番号として届く
        if let code = reply.paramDescriptor(forKeyword: Self.code("errn"))?.int32Value, code != 0 {
            let message = reply.paramDescriptor(forKeyword: Self.code("errs"))?.stringValue ?? ""
            throw Failure.from(code: Int(code), message: message)
        }
        return reply
    }

    // MARK: - Apple Event の組み立て

    /// `get <specifier>`
    static func getEvent(_ specifier: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let event = makeEvent(eventID: "getd")
        event.setParam(specifier, forKeyword: code("----"))
        return event
    }

    /// `set <specifier> to <value>`
    static func setEvent(_ specifier: NSAppleEventDescriptor, to value: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let event = makeEvent(eventID: "setd")
        event.setParam(specifier, forKeyword: code("----"))
        event.setParam(value, forKeyword: code("data"))
        return event
    }

    private static func makeEvent(eventID: String) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: code("core"),
            eventID: code(eventID),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

    /// `first process whose unix id is pid`
    static func process(pid: pid_t) -> NSAppleEventDescriptor {
        let test = comparison(property("idux", of: examined()), equals: NSAppleEventDescriptor(int32: pid))
        return first("prcs", of: specifier(want: "prcs", form: "test", selector: test, from: .null()))
    }

    /// `every window of process`
    static func everyWindow(of process: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        var all = code("all ")
        let selector = NSAppleEventDescriptor(descriptorType: code("abso"), bytes: &all, length: MemoryLayout<FourCharCode>.size)
        return specifier(want: "cwin", form: "indx", selector: selector ?? .null(), from: process)
    }

    /// `first window of process whose position is {x, y} and size is {width, height}`
    static func window(matching frame: CGRect, of process: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let terms = NSAppleEventDescriptor.list()
        terms.insert(comparison(property("posn", of: examined()), equals: pair(frame.minX, frame.minY)), at: 0)
        terms.insert(comparison(property("ptsz", of: examined()), equals: pair(frame.width, frame.height)), at: 0)
        let logical = NSAppleEventDescriptor.record()
        logical.setDescriptor(NSAppleEventDescriptor(enumCode: code("AND ")), forKeyword: code("logc"))
        logical.setDescriptor(terms, forKeyword: code("term"))
        let test = logical.coerce(toDescriptorType: code("logi")) ?? logical
        return first("cwin", of: specifier(want: "cwin", form: "test", selector: test, from: process))
    }

    /// `<property> of <container>`
    static func property(_ property: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(want: "prop", form: "prop", selector: NSAppleEventDescriptor(typeCode: code(property)), from: container)
    }

    /// 2 つの整数のリスト（`{x, y}` や `{width, height}`）
    static func pair(_ first: CGFloat, _ second: CGFloat) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(int32: int32(first)), at: 0)
        list.insert(NSAppleEventDescriptor(int32: int32(second)), at: 0)
        return list
    }

    /// 丸めて Int32 にする。範囲外や無限大でも落ちないように収める
    private static func int32(_ value: CGFloat) -> Int32 {
        let rounded = value.rounded()
        guard rounded.isFinite else { return 0 }
        return Int32(min(max(rounded, CGFloat(Int32.min)), CGFloat(Int32.max)))
    }

    /// 絞り込みの中の「調べている要素」（AppleScript の whose の中の its）
    private static func examined() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(descriptorType: code("exmn"), data: nil) ?? .null()
    }

    private static func comparison(_ lhs: NSAppleEventDescriptor, equals rhs: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code("=   ")), forKeyword: code("relo"))
        record.setDescriptor(lhs, forKeyword: code("obj1"))
        record.setDescriptor(rhs, forKeyword: code("obj2"))
        return record.coerce(toDescriptorType: code("cmpd")) ?? record
    }

    /// 絞り込んだ要素のうち最初のもの（AppleScript の `first … whose …`）
    private static func first(_ want: String, of elements: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(want: want, form: "indx", selector: NSAppleEventDescriptor(int32: 1), from: elements)
    }

    private static func specifier(
        want: String,
        form: String,
        selector: NSAppleEventDescriptor,
        from container: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(want)), forKeyword: code("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(selector, forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        return record.coerce(toDescriptorType: code("obj ")) ?? record
    }

    // MARK: - 返事の読み取り

    private static func reply(_ event: NSAppleEventDescriptor) -> NSAppleEventDescriptor? {
        event.paramDescriptor(forKeyword: code("----"))
    }

    /// `position of every window` と `size of every window` の返事（`{{x, y}, …}` と `{{w, h}, …}`）を、ウィンドウごとの位置と大きさにする
    static func frames(positions: NSAppleEventDescriptor?, sizes: NSAppleEventDescriptor?) -> [CGRect] {
        let origins = pairs(positions)
        let extents = pairs(sizes)
        return zip(origins, extents).map { CGRect(x: $0.0, y: $0.1, width: $1.0, height: $1.1) }
    }

    private static func pairs(_ descriptor: NSAppleEventDescriptor?) -> [(CGFloat, CGFloat)] {
        guard let descriptor, descriptor.descriptorType == code("list") else { return [] }
        return (0..<descriptor.numberOfItems).compactMap { offset in
            guard let item = descriptor.atIndex(offset + 1), item.numberOfItems == 2,
                  let first = item.atIndex(1)?.doubleValue,
                  let second = item.atIndex(2)?.doubleValue
            else {
                return nil
            }
            return (CGFloat(first), CGFloat(second))
        }
    }

    private static func code(_ string: String) -> FourCharCode {
        CompanionShortcut.code(string)
    }
}
