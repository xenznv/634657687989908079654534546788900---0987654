import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import AccountContext
import JerkgramCore
import CoreLocation

public func jerkgramSpoofController(context: AccountContext) -> ViewController {
    let initialState = JerkgramSpoofController.shared.currentState
    let stateValue = Atomic(value: initialState)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)

    let modes: [JerkgramSpoofMode] = [.session, .persistent]

    final class Arguments {
        let toggle: (String, Bool) -> Void
        let action: (String) -> Void
        init(toggle: @escaping (String, Bool) -> Void, action: @escaping (String) -> Void) {
            self.toggle = toggle
            self.action = action
        }
    }

    enum Entry: ItemListNodeEntry {
        case header(Int32, String)
        case toggle(Int32, Int32, String, Bool)
        case input(Int32, Int32, String, String, String)
        case action(Int32, Int32, String, String, String)
        case info(Int32, String)

        var section: ItemListSectionId {
            switch self {
            case let .header(section, _), let .toggle(section, _, _, _), let .input(section, _, _, _, _), let .action(section, _, _, _, _), let .info(section, _):
                return section
            }
        }
        var stableId: Int32 {
            switch self {
            case let .header(section, _): return section * 1000
            case let .toggle(section, index, _, _), let .input(section, index, _, _, _), let .action(section, index, _, _, _): return section * 1000 + index
            case let .info(section, _): return section * 1000 + 999
            }
        }
        static func == (lhs: Entry, rhs: Entry) -> Bool {
            return lhs.stableId == rhs.stableId && String(describing: lhs) == String(describing: rhs)
        }
        static func < (lhs: Entry, rhs: Entry) -> Bool {
            return lhs.stableId < rhs.stableId
        }
        func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
            let arguments = arguments as! Arguments
            switch self {
            case let .header(_, title):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
            case let .toggle(_, _, title, value):
                return ItemListSwitchItem(
                    presentationData: presentationData, systemStyle: .glass,
                    title: title, value: value, sectionId: self.section,
                    style: .blocks, updated: { arguments.toggle("enabled", $0) }
                )
            case let .input(_, _, title, text, action):
                return ItemListSingleLineInputItem(
                    presentationData: presentationData,
                    title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor),
                    text: text,
                    placeholder: "0.0",
                    type: .regular(capitalization: false, autocorrection: false),
                    returnKeyType: .done,
                    alignment: .right,
                    spacing: 16.0,
                    clearType: .never,
                    maxLength: 12,
                    sectionId: self.section,
                    style: .blocks,
                    textUpdated: { updatedText in
                        arguments.action(action + ":" + updatedText)
                    },
                    shouldUpdateText: { _ in true }
                )
            case let .action(_, _, title, value, action):
                return ItemListDisclosureItem(
                    presentationData: presentationData, systemStyle: .glass,
                    title: title, label: value, labelStyle: .text,
                    sectionId: self.section, style: .blocks,
                    disclosureStyle: action == "cycleMode" ? .arrow : .none,
                    action: action.isEmpty ? nil : { arguments.action(action) }
                )
            case let .info(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            }
        }
    }

    func formatMode(_ mode: JerkgramSpoofMode, strings: JerkgramStrings) -> String {
        switch mode {
        case .session: return strings.spoofModeSession
        case .persistent: return strings.spoofModePersistent
        }
    }

    func entries(state: JerkgramSpoofState, strings: JerkgramStrings) -> [Entry] {
        var entries: [Entry] = [
            .header(0, strings.spoofSection),
            .toggle(0, 1, strings.spoofEnabled, state.enabled),
            .input(0, 2, strings.spoofLatitude, String(format: "%.6f", state.latitude), "lat"),
            .input(0, 3, strings.spoofLongitude, String(format: "%.6f", state.longitude), "lon"),
            .action(0, 4, strings.spoofMode, formatMode(state.mode, strings: strings), "cycleMode"),
            .info(0, state.enabled ? strings.spoofActiveHint : strings.spoofHint)
        ]
        if state.enabled {
            entries.append(.action(1, 1, strings.spoofStop, "", "disable"))
        }
        return entries
    }

    var controller: ItemListController?

    let arguments = Arguments(toggle: { _, value in
        JerkgramSpoofController.shared.setEnabled(value)
        statePromise.set(JerkgramSpoofController.shared.currentState)
    }, action: { rawAction in
        let parts = rawAction.split(separator: ":", maxSplits: 1).map(String.init)
        let action = parts.first ?? rawAction
        let value = parts.count > 1 ? parts[1] : nil

        switch action {
        case "lat":
            if let text = value, let parsed = Double(text) {
                JerkgramSpoofController.shared.setCoordinate(latitude: parsed, longitude: JerkgramSpoofController.shared.currentState.longitude)
            } else if let text = value, text.isEmpty {
                break
            } else {
                statePromise.set(JerkgramSpoofController.shared.currentState)
                return
            }
            statePromise.set(JerkgramSpoofController.shared.currentState)
        case "lon":
            if let text = value, let parsed = Double(text) {
                JerkgramSpoofController.shared.setCoordinate(latitude: JerkgramSpoofController.shared.currentState.latitude, longitude: parsed)
            } else if let text = value, text.isEmpty {
                break
            } else {
                statePromise.set(JerkgramSpoofController.shared.currentState)
                return
            }
            statePromise.set(JerkgramSpoofController.shared.currentState)
        case "cycleMode":
            JerkgramSpoofController.shared.update { state in
                let currentIndex = modes.firstIndex(of: state.mode) ?? 0
                state.mode = modes[(currentIndex + 1) % modes.count]
            }
            statePromise.set(JerkgramSpoofController.shared.currentState)
        case "disable":
            JerkgramSpoofController.shared.setEnabled(false)
            statePromise.set(JerkgramSpoofController.shared.currentState)
        default:
            break
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings.jerkgram
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text(strings.spoof),
                leftNavigationButton: nil, rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            ),
            (ItemListNodeState(
                presentationData: ItemListPresentationData(presentationData),
                entries: entries(state: state, strings: strings),
                style: .blocks, animateChanges: false
            ), arguments as Any)
        )
    }
    controller = ItemListController(context: context, state: signal)
    return controller!
}
