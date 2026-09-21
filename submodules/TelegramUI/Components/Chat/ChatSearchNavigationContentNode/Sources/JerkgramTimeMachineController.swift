import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import AccountContext
import AlertUI
import JerkgramCore

private struct JerkgramTimeMachineUIState: Equatable {
    var kinds: Set<JerkgramEventKind>
    var senderPeerId: Int64?
    var showsDiff: Bool
}

private struct JerkgramTimeMachinePageState: Equatable {
    var events: [JerkgramCanonicalEvent]
    var hasMore: Bool
}

private final class JerkgramTimeMachineUIArguments {
    let toggleKind: (JerkgramEventKind) -> Void
    let selectSender: () -> Void
    let toggleDiff: () -> Void
    let selectEvent: (JerkgramCanonicalEvent) -> Void
    let loadMore: () -> Void
    init(
        toggleKind: @escaping (JerkgramEventKind) -> Void,
        selectSender: @escaping () -> Void,
        toggleDiff: @escaping () -> Void,
        selectEvent: @escaping (JerkgramCanonicalEvent) -> Void,
        loadMore: @escaping () -> Void
    ) {
        self.toggleKind = toggleKind
        self.selectSender = selectSender
        self.toggleDiff = toggleDiff
        self.selectEvent = selectEvent
        self.loadMore = loadMore
    }
}

private enum JerkgramTimeMachineUIEntry: ItemListNodeEntry {
    case header(Int32, String)
    case summary(Int32, Int32, String, String)
    case filter(Int32, Int32, String, String, JerkgramEventKind?)
    case diffToggle(Int32, Int32, String, String, Bool)
    case result(Int32, Int32, String, String, String?, JerkgramCanonicalEvent)
    case info(Int32, String)
    case loadMore(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .summary(section, _, _, _), let .filter(section, _, _, _, _), let .diffToggle(section, _, _, _, _), let .result(section, _, _, _, _, _), let .info(section, _), let .loadMore(section, _): return section
        }
    }
    var stableId: Int32 {
        switch self {
        case let .header(section, _): return section * 1000
        case let .summary(section, index, _, _): return section * 1000 + index
        case let .filter(section, index, _, _, _), let .diffToggle(section, index, _, _, _), let .result(section, index, _, _, _, _): return section * 1000 + index
        case .info: return Int32.max - 1
        case .loadMore: return Int32.max
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { return lhs.stableId == rhs.stableId && String(describing: lhs) == String(describing: rhs) }
    static func < (lhs: Self, rhs: Self) -> Bool { return lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! JerkgramTimeMachineUIArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .summary(_, _, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData, systemStyle: .glass,
                title: title, label: value, labelStyle: .text,
                sectionId: self.section, style: .blocks,
                disclosureStyle: .none, action: nil
            )
case let .filter(_, _, title, value, kind):
    if let kind {
        return ItemListSwitchItem(
            presentationData: presentationData, systemStyle: .glass,
            title: title, value: value == "✓",
            sectionId: self.section, style: .blocks,
            updated: { _ in arguments.toggleKind(kind) }
        )
    } else {
        return ItemListDisclosureItem(
            presentationData: presentationData, systemStyle: .glass,
            title: title, label: value, labelStyle: .text,
            sectionId: self.section, style: .blocks,
            disclosureStyle: .none,
            action: { arguments.selectSender() }
        )
    }
        case let .diffToggle(_, _, title, hint, value):
            return ItemListSwitchItem(
                presentationData: presentationData, systemStyle: .glass,
                title: title, text: hint, value: value,
                maximumNumberOfLines: 0,
                sectionId: self.section, style: .blocks,
                updated: { _ in arguments.toggleDiff() }
            )
        case let .result(_, _, title, value, diff, event):
            // An attributed title is the only label in this item that wraps, so
            // the change summary rides along as a second, dimmer line.
            let attributedTitle: NSAttributedString?
            if let diff {
                let composed = NSMutableAttributedString(
                    string: title,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 15.0),
                        .foregroundColor: presentationData.theme.list.itemPrimaryTextColor
                    ]
                )
                composed.append(NSAttributedString(
                    string: "\n" + diff,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 13.0),
                        .foregroundColor: presentationData.theme.list.itemSecondaryTextColor
                    ]
                ))
                attributedTitle = composed
            } else {
                attributedTitle = nil
            }
            return ItemListDisclosureItem(
                presentationData: presentationData, systemStyle: .glass,
                title: title, attributedTitle: attributedTitle,
                label: value, labelStyle: .text,
                sectionId: self.section, style: .blocks,
                disclosureStyle: .arrow, action: { arguments.selectEvent(event) }
            )
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .loadMore(_, title):
            return ItemListActionItem(
                presentationData: presentationData, title: title,
                kind: .generic, alignment: .center,
                sectionId: self.section, style: .blocks,
                action: { arguments.loadMore() }
            )
        }
    }
}

private func jerkgramTimeMachineDateText(_ timestampMs: Int64, dateTimeFormat: PresentationDateTimeFormat) -> String {
    let _ = dateTimeFormat
    let timestamp = TimeInterval(timestampMs) / 1000.0
    guard timestamp > 0.0 else { return "" }
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: timestamp))
}

private func jerkgramTimeMachineRootURL() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Jerkgram", isDirectory: true)
}

private func jerkgramEventKindTitle(_ kind: JerkgramEventKind, strings: JerkgramStrings) -> String {
    switch kind {
    case .deletedMessage, .deletedReply: return strings.timeMachineDeleted
    case .editedMessage: return strings.timeMachineEdited
    case .recoveredMedia: return strings.timeMachineMedia
    default: return kind.rawValue
    }
}

/// Compact inline summary of an edit: only the changed fragments survive, since a
/// list row has no room for the untouched text. Both sides are capped first so a
/// pathological message can never slow the list layout down.
private func jerkgramTimeMachineInlineDiff(_ event: JerkgramCanonicalEvent) -> String? {
    guard event.kind == .editedMessage,
          let old = event.payload.previousText,
          let new = event.payload.text else {
        return nil
    }

    var fragments: [String] = []
    for operation in JerkgramTextDiff.diff(
        old: String(old.prefix(300)),
        new: String(new.prefix(300))
    ) {
        switch operation {
        case .equal:
            break
        case let .insert(value):
            fragments.append("[+\(value)]")
        case let .delete(value):
            fragments.append("[-\(value)]")
        case let .replace(old, new):
            fragments.append("[-\(old)] [+\(new)]")
        }
    }

    guard !fragments.isEmpty else {
        return nil
    }

    let joined = fragments.joined()
    return joined.count > 200 ? String(joined.prefix(200)) + "…" : joined
}

private func jerkgramDiffText(_ event: JerkgramCanonicalEvent) -> String {
    guard event.kind == .editedMessage,
          let old = event.payload.previousText,
          let new = event.payload.text else {
        return event.payload.text ?? event.payload.previousText ?? event.eventId.rawValue
    }
    return JerkgramTextDiff.diff(old: old, new: new).map { operation in
        switch operation {
        case let .equal(value): return value
        case let .insert(value): return "[+\(value)]"
        case let .delete(value): return "[-\(value)]"
        case let .replace(old, new): return "[-\(old)] [+\(new)]"
        }
    }.joined()
}

public func jerkgramTimeMachineController(
    context: AccountContext,
    chatPeerId: Int64,
    initialQuery: String,
    eventIds: Set<JerkgramEventId>? = nil,
    navigateToMessage: @escaping (EngineMessage.Id) -> Void
) -> ViewController {
    let accountPeerId = context.account.peerId.toInt64()
    let eventsValue = Atomic<[JerkgramCanonicalEvent]>(value: [])
    let eventsPromise = ValuePromise(
        JerkgramTimeMachinePageState(events: [], hasMore: true),
        ignoreRepeated: true
    )
    let pageLock = NSLock()
    var beforeSequence: Int64?
    var beforeEventId: JerkgramEventId?
    var hasMore = true
    var isLoading = false
    let loadNextPage: () -> Void = {
        pageLock.lock()
        guard hasMore && !isLoading else {
            pageLock.unlock()
            return
        }
        isLoading = true
        let cursorSequence = beforeSequence
        let cursorEventId = beforeEventId
        pageLock.unlock()
        Queue.concurrentDefaultQueue().async {
            let store = JerkgramJSONLEventStore(rootURL: jerkgramTimeMachineRootURL())
            let page = (try? store.eventPage(
                accountPeerId: accountPeerId,
                chatPeerId: chatPeerId,
                beforeSequence: cursorSequence,
                beforeEventId: cursorEventId,
                limit: 250
            )) ?? []
            let events = eventsValue.modify { $0 + page }
            pageLock.lock()
            if let last = page.last {
                beforeSequence = last.sequence
                beforeEventId = last.eventId
            }
            hasMore = page.count == 250
            isLoading = false
            let pageHasMore = hasMore
            pageLock.unlock()
            eventsPromise.set(JerkgramTimeMachinePageState(events: events, hasMore: pageHasMore))
        }
    }
    loadNextPage()
    let initial = JerkgramTimeMachineUIState(
        kinds: [.deletedMessage, .deletedReply, .editedMessage, .recoveredMedia],
        senderPeerId: nil,
        showsDiff: true
    )
    let stateValue = Atomic(value: initial)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    var controller: ItemListController?

    let arguments = JerkgramTimeMachineUIArguments(toggleKind: { kind in
        let value = stateValue.modify { current in
            var current = current
            if current.kinds.contains(kind) { current.kinds.remove(kind) } else { current.kinds.insert(kind) }
            return current
        }
        statePromise.set(value)
    }, selectSender: {
        let senders = Array(Set(eventsValue.with { $0.compactMap(\.senderPeerId) })).sorted()
        let value = stateValue.modify { current in
            var current = current
            if let sender = current.senderPeerId, let index = senders.firstIndex(of: sender), index + 1 < senders.count {
                current.senderPeerId = senders[index + 1]
            } else if current.senderPeerId == nil {
                current.senderPeerId = senders.first
            } else {
                current.senderPeerId = nil
            }
            return current
        }
        statePromise.set(value)
    }, toggleDiff: {
        let value = stateValue.modify { current in
            var current = current
            current.showsDiff.toggle()
            return current
        }
        statePromise.set(value)
    }, selectEvent: { event in
        if let namespace = event.messageNamespace, let id = event.messageId {
            navigateToMessage(EngineMessage.Id(
                peerId: EnginePeer.Id(event.chatPeerId),
                namespace: namespace,
                id: id
            ))
            controller?.dismiss()
        } else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let localDetail = jerkgramDiffText(event)
            controller?.present(textAlertController(
                context: context,
                title: presentationData.strings.jerkgram.timeMachine,
                text: localDetail,
                actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
            ), in: .window(.root), with: nil)
        }
    }, loadMore: loadNextPage)

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get(), eventsPromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state, page -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings.jerkgram
        let needle = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let results = page.events.filter { event in
            if let eventIds, !eventIds.contains(event.eventId) { return false }
            guard state.kinds.contains(event.kind) else { return false }
            if let senderPeerId = state.senderPeerId, event.senderPeerId != senderPeerId { return false }
            if !needle.isEmpty {
                let search = [event.payload.text, event.payload.previousText]
                    .compactMap { $0 }.joined(separator: " ").lowercased()
                if !search.contains(needle) { return false }
            }
            return true
        }.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence > rhs.sequence }
            return lhs.eventId > rhs.eventId
        }
        var entries: [JerkgramTimeMachineUIEntry] = [
            
            .header(1, strings.timeMachineFilters),
            .filter(1, 1, strings.timeMachineDeleted, state.kinds.contains(.deletedMessage) ? "✓" : "", .deletedMessage),
            .filter(1, 2, strings.timeMachineEdited, state.kinds.contains(.editedMessage) ? "✓" : "", .editedMessage),
            .filter(1, 3, strings.timeMachineMedia, state.kinds.contains(.recoveredMedia) ? "✓" : "", .recoveredMedia),
            .filter(1, 4, strings.timeMachineAuthor, state.senderPeerId.map(String.init) ?? strings.timeMachineAllAuthors, nil),
            .diffToggle(1, 5, strings.timeMachineShowDiff, strings.timeMachineShowDiffHint, state.showsDiff),
            .header(2, strings.timeMachineResults),
        ]
        for (index, event) in results.enumerated() {
            let text = event.payload.text ?? event.payload.previousText ?? event.eventId.rawValue
            let date = jerkgramTimeMachineDateText(event.observedAtMs, dateTimeFormat: presentationData.dateTimeFormat)
            let kind = jerkgramEventKindTitle(event.kind, strings: strings)
            let detail = date.isEmpty ? kind : "\(kind) · \(date)"
            let diff = state.showsDiff ? jerkgramTimeMachineInlineDiff(event) : nil
            entries.append(.result(2, Int32(index + 1), String(text.prefix(120)), detail, diff, event))
        }
        if results.isEmpty { entries.append(.info(2, strings.timeMachineEmpty)) }
        if page.hasMore { entries.append(.loadMore(2, strings.timeMachineLoadMore)) }
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text(strings.timeMachine),
                leftNavigationButton: ItemListNavigationButton(
                    content: .text("‹ " + presentationData.strings.Common_Back),
                    style: .regular,
                    enabled: true,
                    action: { controller?.dismiss() }
                ),
                rightNavigationButton: nil,
                backNavigationButton: nil
            ),
            (ItemListNodeState(
                presentationData: ItemListPresentationData(presentationData),
                entries: entries, style: .blocks, animateChanges: false
            ), arguments as Any)
        )
    }
    controller = ItemListController(context: context, state: signal)
    return controller!
}
