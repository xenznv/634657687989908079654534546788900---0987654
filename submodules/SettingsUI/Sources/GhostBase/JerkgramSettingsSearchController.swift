import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SearchBarNode
import SearchUI
import MergeLists

// One searchable option of the Jerkgram settings.
private struct JerkgramSearchOption {
    let title: String
    let description: String
    let keywords: String
    let page: GhostBaseSettingsPage

    func matches(query: String) -> Bool {
        let loweredQuery = query.lowercased()
        return self.title.lowercased().contains(loweredQuery)
            || self.keywords.lowercased().contains(loweredQuery)
    }
}

private func jerkgramSearchRegistry(strings: JerkgramStrings) -> [JerkgramSearchOption] {
    var options: [JerkgramSearchOption] = []

    let russian = strings.languageCode == "ru"
    func add(_ title: String, _ descriptionEn: String, _ descriptionRu: String, _ keywords: String, _ page: GhostBaseSettingsPage) {
        options.append(JerkgramSearchOption(title: title, description: russian ? descriptionRu : descriptionEn, keywords: keywords, page: page))
    }

    // Root destinations
    add(strings.infoDisplay, strings.infoDisplayHint, strings.infoDisplayHint, "info display profile id dc registration seconds phone", .home)
    add(strings.ghostMode, strings.ghostModeHint, strings.ghostModeHint, "ghost online read typing recording upload presence", .ghostMode)
    add(strings.messages, strings.messagesHint, strings.messagesHint, "messages deleted edited history", .messages)
    add(strings.protectedContent, strings.protectedContentHint, strings.protectedContentHint, "protected screenshot save copy forward", .protectedContent)
    add(strings.mediaAndStories, strings.mediaAndStoriesHint, strings.mediaAndStoriesHint, "media stories one time", .mediaStories)
    add(strings.dataAndBackup, strings.dataAndBackupHint, strings.dataAndBackupHint, "data backup retention archive", .dataAndBackup)
    add(strings.historyStorageTitle, strings.historyStorageHint, strings.historyStorageHint, "history storage retention media limit occupied space time machine", .dataAndBackup)
    add(strings.debugConsole, strings.debugConsoleHint, strings.debugConsoleHint, "debug console log crash diagnostics errors events", .debugConsole)

    // Basic Functions
    add(strings.profileCard, "Show ID, DC and registration date in profiles", "Показывать ID, DC и дату регистрации в профилях", "profile information id dc", .home)
    add(strings.telegramId, "Show the Telegram ID row in profiles", "Показывать строку Telegram ID в профилях", "id identifier", .home)
    add(strings.showDcs, "Show the data center of an account", "Показывать дата-центр аккаунта", "dc data center", .home)
    add(strings.registrationDate, "Show the account registration date", "Показывать дату регистрации аккаунта", "registration date", .home)
    add(strings.messageSeconds, "Show seconds in message timestamps", "Показывать секунды во времени сообщений", "seconds time timestamp clock", .home)
    add(strings.messageCharacterCount, "Show the character count of messages", "Показывать счётчик символов сообщений", "character count symbols counter", .home)
    add(strings.hideMyPhone, "Hide your phone number", "Скрыть ваш номер телефона", "phone number hide", .home)
    add(strings.starsBalance, "Override the displayed stars balance", "Изменить отображаемый баланс звёзд", "stars balance", .stars)

    // Ghost Mode
    add(strings.messageReadReceipts, strings.messageReadReceiptsHint, strings.messageReadReceiptsHint, "read receipts double check messages", .ghostMode)
    add(strings.storyReadReceipts, strings.storyReadReceiptsHint, strings.storyReadReceiptsHint, "read receipts stories seen view", .ghostMode)
    add(strings.typing, strings.typingHint, strings.typingHint, "typing status", .ghostMode)
    add(strings.recording, strings.recordingVoiceHint, strings.recordingVoiceHint, "recording voice message", .ghostMode)
    add(strings.uploading, strings.uploadingVideoHint, strings.uploadingVideoHint, "uploading video", .ghostMode)
    add(strings.recording, strings.recordingVideoHint, strings.recordingVideoHint, "recording video round", .ghostMode)
    add(strings.uploading, strings.uploadingVoiceHint, strings.uploadingVoiceHint, "uploading voice message", .ghostMode)
    add(strings.uploading, strings.uploadingPhotoHint, strings.uploadingPhotoHint, "uploading photo", .ghostMode)
    add(strings.uploading, strings.uploadingFileHint, strings.uploadingFileHint, "uploading file document", .ghostMode)
    add(strings.uploading, strings.uploadingRoundHint, strings.uploadingRoundHint, "uploading round video", .ghostMode)
    add(strings.choosingSticker, strings.choosingStickerHint, strings.choosingStickerHint, "sticker activity picking", .ghostMode)
    add(strings.gameActivity, strings.gameActivityHint, strings.gameActivityHint, "game activity playing", .ghostMode)
    add(strings.choosingEmoji, strings.emojiInteractionHint, strings.emojiInteractionHint, "emoji activity interaction", .ghostMode)
    add(strings.choosingEmoji, strings.emojiAckHint, strings.emojiAckHint, "emoji acknowledgement reaction", .ghostMode)
    add(strings.scheduledSend, strings.scheduledSendHint, strings.scheduledSendHint, "scheduled send delay", .ghostMode)
    add(strings.hideOnline, strings.hideOnlineHint, strings.hideOnlineHint, "online status last seen presence", .ghostMode)
    add(strings.choosingLocationTitle, strings.choosingLocationHint, strings.choosingLocationHint, "choosing location geo live", .ghostMode)
    add(strings.choosingContactTitle, strings.choosingContactHint, strings.choosingContactHint, "choosing contact share", .ghostMode)
    add(strings.speakingGroupCallTitle, strings.speakingGroupCallHint, strings.speakingGroupCallHint, "speaking group call voice chat", .ghostMode)

    // Messages
    add(strings.saveDeletedMessages, "Keep deleted messages locally", "Сохранять удалённые сообщения локально", "save deleted messages", .messages)
    add(strings.deletedMessages, "Show deleted messages in the chat", "Показывать удалённые сообщения в чате", "show deleted messages", .messages)
    add(strings.saveEditHistory, "Keep previous versions of edited messages", "Сохранять прошлые версии изменённых сообщений", "save edit history", .messages)
    add(strings.editHistory, "Show the edit history of messages", "Показывать историю редактирования сообщений", "show edit history", .messages)
    add(strings.portableReply, "Reply to deleted messages", "Отвечать на удалённые сообщения", "deleted replies portable reply", .messages)
    add(strings.saveDeletedMedia, "Keep media of deleted messages", "Сохранять медиа удалённых сообщений", "deleted media keep", .messages)
    add(strings.sendStyle, "Choose how your text is sent", "Выбрать формат отправки текста", "send style text formatting", .messages)
    add(strings.hideBlockedMessages, "Hide blocked messages locally", "Скрывать заблокированные сообщения локально", "blocked messages hide", .messages)
    add(strings.hideBlockedReactions, "Hide reactions locally", "Скрывать реакции локально", "blocked reactions hide", .messages)

    // Protected Content
    add(strings.bypassAll, strings.bypassAllHint, strings.bypassAllHint, "bypass all restrictions protection save copy forward screenshot screen recording view once", .protectedContent)
    add(strings.removeAds, strings.removeAdsHint, strings.removeAdsHint, "remove ads sponsored posts channels no advertising premium", .protectedContent)
    add(strings.showHiddenChats, strings.showHiddenChatsHint, strings.showHiddenChatsHint, "open hidden chats restricted channels sensitive censored", .protectedContent)
    add(strings.shareFromGallery, "Share protected media from the gallery", "Делиться защищёнными медиа из галереи", "gallery share bypass", .protectedContent)
    add(strings.saveFromGallery, "Save protected media to the gallery", "Сохранять защищённые медиа в галерею", "gallery save bypass", .protectedContent)
    add(strings.copyFromGallery, "Copy protected media", "Копировать защищённые медиа", "gallery copy bypass", .protectedContent)
    add(strings.saveFromChat, "Save protected media from chats", "Сохранять защищённые медиа из чатов", "chat save bypass", .protectedContent)
    add(strings.copyFromChat, "Copy protected media from chats", "Копировать защищённые медиа из чатов", "chat copy bypass", .protectedContent)
    add(strings.forwardFromChat, "Forward protected messages", "Пересылать защищённые сообщения", "chat forward bypass", .protectedContent)
    add(strings.allowScreenshots, "Allow screenshots in protected chats", "Разрешить скриншоты в защищённых чатах", "screenshots allow", .protectedContent)
    add(strings.allowScreenRecording, "Allow screen recording in protected chats", "Разрешить запись экрана в защищённых чатах", "screen recording allow", .protectedContent)

    // History & Storage
    add(strings.historyDuration, "How long the local history is kept", "Сколько хранится локальная история", "history duration retention keep days forever", .dataAndBackup)
    add(strings.recoveredMediaLimit, "Size limit for saved media", "Лимит размера сохранённых медиа", "media limit size storage mb gb", .dataAndBackup)
    add(strings.cleanupExpired, "Delete expired history entries now", "Удалить истёкшие записи истории сейчас", "cleanup clear expired purge history storage", .dataAndBackup)

    // Media & Stories
    add(strings.oneTimeScreenshots, "Screenshot view-once media", "Скриншотить медиа с одиночным просмотром", "one time screenshots view once", .mediaStories)
    add(strings.oneTimeScreenRecording, "Screen-record view-once media", "Записывать экран поверх медиа с одиночным просмотром", "one time screen recording", .mediaStories)
    add(strings.oneTimeMedia, "Save view-once media", "Сохранять медиа с одиночным просмотром", "one time media save", .mediaStories)
    add(strings.storySave, "Save stories of any account", "Сохранять истории любого аккаунта", "stories save bypass", .mediaStories)

    return options.sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
}

private func jerkgramSearchLocalizedPageTitle(page: GhostBaseSettingsPage, strings: JerkgramStrings) -> String {
    switch page {
    case .home:
        return strings.infoDisplay
    case .ghostMode:
        return strings.ghostMode
    case .messages:
        return strings.messages
    case .protectedContent:
        return strings.protectedContent
    case .mediaStories:
        return strings.mediaAndStories
    case .dataAndBackup:
        return strings.dataAndBackup
    case .debugConsole:
        return strings.debugConsole
    default:
        return strings.settingsTitle
    }
}

private final class JerkgramSettingsSearchArguments {
    let openPage: (GhostBaseSettingsPage) -> Void

    init(openPage: @escaping (GhostBaseSettingsPage) -> Void) {
        self.openPage = openPage
    }
}

private enum JerkgramSettingsSearchEntry: ItemListNodeEntry {
    case header(Int32, String)
    case option(Int32, Int32, String, String, GhostBaseSettingsPage)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _):
            return section
        case let .option(section, _, _, _, _):
            return section
        case let .info(section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(section, _):
            return section * 1000
        case let .option(section, index, _, _, _):
            return section * 1000 + index
        case let .info(section, _):
            return section * 1000 + 999
        }
    }

    static func ==(lhs: JerkgramSettingsSearchEntry, rhs: JerkgramSettingsSearchEntry) -> Bool {
        switch lhs {
        case let .header(ls, lt):
            if case let .header(rs, rt) = rhs {
                return ls == rs && lt == rt
            }
            return false
        case let .option(ls, li, lt, lp, lPage):
            if case let .option(rs, ri, rt, rp, rPage) = rhs {
                return ls == rs && li == ri && lt == rt && lp == rp && lPage.title == rPage.title
            }
            return false
        case let .info(ls, lt):
            if case let .info(rs, rt) = rhs {
                return ls == rs && lt == rt
            }
            return false
        }
    }

    static func <(lhs: JerkgramSettingsSearchEntry, rhs: JerkgramSettingsSearchEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! JerkgramSettingsSearchArguments

        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(
                presentationData: presentationData,
                text: text.uppercased(),
                sectionId: self.section
            )
        case let .option(_, _, title, subtitle, page):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: title,
                label: subtitle,
                labelStyle: .detailText,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openPage(page)
                }
            )
        case let .info(_, text):
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain(text),
                sectionId: self.section
            )
        }
    }
}

private func jerkgramSettingsSearchEntries(
    query: String?,
    strings: JerkgramStrings
) -> [JerkgramSettingsSearchEntry] {
    let registry = jerkgramSearchRegistry(strings: strings)

    let loweredQuery = query?.lowercased() ?? ""
    // With an empty query the full option list is shown, sorted A to Z.
    let filtered = loweredQuery.isEmpty
        ? registry
        : registry.filter { $0.matches(query: loweredQuery) }

    if loweredQuery.isEmpty {
        guard !filtered.isEmpty else {
            return [
                .info(0, strings.searchSettingsHint)
            ]
        }
    } else if filtered.isEmpty {
        return [
            .info(0, strings.searchNothingFound)
        ]
    }

    var entries: [JerkgramSettingsSearchEntry] = []
    var index: Int32 = 1
    for option in filtered {
        let pageSubtitle = jerkgramSearchLocalizedPageTitle(page: option.page, strings: strings)
        entries.append(.option(0, index, option.title, "\(pageSubtitle) · \(option.description)", option.page))
        index += 1
    }
    return entries
}

private struct JerkgramSettingsSearchContainerTransition {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
}

private func jerkgramPreparedSearchContainerTransition(
    presentationData: ItemListPresentationData,
    from fromEntries: [JerkgramSettingsSearchEntry],
    to toEntries: [JerkgramSettingsSearchEntry],
    arguments: JerkgramSettingsSearchArguments,
    forceUpdate: Bool
) -> JerkgramSettingsSearchContainerTransition {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries, allUpdated: forceUpdate)

    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(presentationData: presentationData, arguments: arguments), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(presentationData: presentationData, arguments: arguments), directionHint: nil) }

    return JerkgramSettingsSearchContainerTransition(
        deletions: deletions,
        insertions: insertions,
        updates: updates
    )
}

// Navigation-bar search field content (mirrors InviteRequestsSearchItem).
private final class JerkgramSettingsSearchNavigationContentNode: NavigationBarContentNode, ItemListControllerSearchNavigationContentNode {
    private var theme: PresentationTheme
    private let strings: PresentationStrings
    private let searchBar: SearchBarNode
    private var queryUpdated: ((String) -> Void)?

    init(theme: PresentationTheme, strings: PresentationStrings, placeholder: String, cancel: @escaping () -> Void) {
        self.theme = theme
        self.strings = strings

        self.searchBar = SearchBarNode(
            theme: SearchBarNodeTheme(theme: theme, hasSeparator: false),
            presentationTheme: theme,
            strings: strings,
            fieldStyle: .modern,
            displayBackground: false
        )

        super.init()

        self.addSubnode(self.searchBar)

        self.searchBar.cancel = { [weak self] in
            self?.searchBar.deactivate(clear: false)
            cancel()
        }

        self.searchBar.textUpdated = { [weak self] query, _ in
            self?.queryUpdated?(query)
        }

        self.updatePlaceholder(placeholder: placeholder)
    }

    func setQueryUpdated(_ f: @escaping (String) -> Void) {
        self.queryUpdated = f
    }

    func updateTheme(_ theme: PresentationTheme) {
        self.theme = theme
        self.searchBar.updateThemeAndStrings(theme: SearchBarNodeTheme(theme: self.theme, hasSeparator: false), presentationTheme: self.theme, strings: self.strings)
    }

    func updatePlaceholder(placeholder: String) {
        self.searchBar.placeholderString = NSAttributedString(
            string: placeholder,
            font: Font.regular(17.0),
            textColor: self.theme.rootController.navigationSearchBar.inputPlaceholderTextColor
        )
    }

    override var nominalHeight: CGFloat {
        return 56.0
    }

    override func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGSize {
        let searchBarFrame = CGRect(origin: CGPoint(x: 0.0, y: size.height - self.nominalHeight), size: CGSize(width: size.width, height: 56.0))
        self.searchBar.frame = searchBarFrame
        self.searchBar.updateLayout(boundingSize: searchBarFrame.size, leftInset: leftInset, rightInset: rightInset, transition: transition)

        return size
    }

    func activate() {
        self.searchBar.activate()
    }

    func deactivate() {
        self.searchBar.deactivate(clear: false)
    }
}

// List content shown while search is active.
private final class JerkgramSettingsSearchContainerNode: SearchDisplayControllerContentNode {
    private var presentationData: PresentationData
    private let openPage: (GhostBaseSettingsPage) -> Void

    private let listNode: ListView

    private var enqueuedTransitions: [JerkgramSettingsSearchContainerTransition] = []
    private var hasValidLayout = false

    private let arguments: JerkgramSettingsSearchArguments

    init(presentationData: PresentationData, openPage: @escaping (GhostBaseSettingsPage) -> Void) {
        self.presentationData = presentationData
        self.openPage = openPage
        self.arguments = JerkgramSettingsSearchArguments(openPage: openPage)

        self.listNode = ListViewImpl()
        self.listNode.backgroundColor = presentationData.theme.chatList.backgroundColor

        super.init()

        self.addSubnode(self.listNode)

        self.replaceEntries(entries: jerkgramSettingsSearchEntries(query: nil, strings: presentationData.strings.jerkgram), forceUpdate: true)
    }

    override func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        self.listNode.backgroundColor = presentationData.theme.chatList.backgroundColor
    }

    override func searchTextUpdated(text: String) {
        let entries = jerkgramSettingsSearchEntries(query: text.isEmpty ? nil : text, strings: self.presentationData.strings.jerkgram)
        self.replaceEntries(entries: entries, forceUpdate: false)
    }

    private var currentEntries: [JerkgramSettingsSearchEntry] = []

    private func replaceEntries(entries: [JerkgramSettingsSearchEntry], forceUpdate: Bool) {
        let previous = self.currentEntries
        self.currentEntries = entries
        let transition = jerkgramPreparedSearchContainerTransition(
            presentationData: ItemListPresentationData(self.presentationData),
            from: previous,
            to: entries,
            arguments: self.arguments,
            forceUpdate: forceUpdate
        )
        self.enqueueTransition(transition)
    }

    private func enqueueTransition(_ transition: JerkgramSettingsSearchContainerTransition) {
        self.enqueuedTransitions.append(transition)

        if self.hasValidLayout {
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }

    private func dequeueTransition() {
        if let transition = self.enqueuedTransitions.first {
            self.enqueuedTransitions.remove(at: 0)

            var options = ListViewDeleteAndInsertOptions()
            options.insert(.PreferSynchronousDrawing)
            options.insert(.PreferSynchronousResourceLoading)

            self.listNode.transaction(
                deleteIndices: transition.deletions,
                insertIndicesAndItems: transition.insertions,
                updateIndicesAndItems: transition.updates,
                options: options,
                updateSizeAndInsets: nil,
                updateOpaqueState: nil,
                completion: { _ in }
            )
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: transition)

        let (duration, curve) = listViewAnimationDurationAndCurve(transition: transition)

        self.listNode.frame = CGRect(origin: CGPoint(), size: layout.size)
        self.listNode.transaction(
            deleteIndices: [],
            insertIndicesAndItems: [],
            updateIndicesAndItems: [],
            options: [.Synchronous],
            scrollToItem: nil,
            updateSizeAndInsets: ListViewUpdateSizeAndInsets(
                size: layout.size,
                insets: UIEdgeInsets(
                    top: navigationBarHeight,
                    left: layout.safeInsets.left,
                    bottom: layout.insets(options: [.input]).bottom,
                    right: layout.safeInsets.right
                ),
                duration: duration,
                curve: curve
            ),
            stationaryItemRange: nil,
            updateOpaqueState: nil,
            completion: { _ in }
        )

        if !self.hasValidLayout {
            self.hasValidLayout = true
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }
}

// The ItemListControllerSearchNode hosting the container.
private final class JerkgramSettingsSearchItemNode: ItemListControllerSearchNode {
    private let containerNode: JerkgramSettingsSearchContainerNode

    init(context: AccountContext, openPage: @escaping (GhostBaseSettingsPage) -> Void) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.containerNode = JerkgramSettingsSearchContainerNode(
            presentationData: presentationData,
            openPage: openPage
        )

        super.init()

        self.addSubnode(self.containerNode)
    }

    override func queryUpdated(_ query: String) {
        self.containerNode.searchTextUpdated(text: query)
    }

    override func updateLayout(layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(node: self.containerNode, frame: CGRect(origin: CGPoint(), size: layout.size))
        self.containerNode.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: transition)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let result = self.containerNode.hitTest(self.view.convert(point, to: self.containerNode.view), with: event) {
            return result
        }
        return super.hitTest(point, with: event)
    }
}

// The ItemListControllerSearch implementation handed to the ItemListController.
private final class JerkgramSettingsSearchItem: ItemListControllerSearch {
    private let context: AccountContext
    private let openPage: (GhostBaseSettingsPage) -> Void
    private let cancel: () -> Void

    init(context: AccountContext, openPage: @escaping (GhostBaseSettingsPage) -> Void, cancel: @escaping () -> Void) {
        self.context = context
        self.openPage = openPage
        self.cancel = cancel
    }

    func isEqual(to: ItemListControllerSearch) -> Bool {
        return to is JerkgramSettingsSearchItem
    }

    func titleContentNode(current: (NavigationBarContentNode & ItemListControllerSearchNavigationContentNode)?) -> (NavigationBarContentNode & ItemListControllerSearchNavigationContentNode)? {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        if let current = current as? JerkgramSettingsSearchNavigationContentNode {
            current.updateTheme(presentationData.theme)
            return current
        } else {
            return JerkgramSettingsSearchNavigationContentNode(
                theme: presentationData.theme,
                strings: presentationData.strings,
                placeholder: presentationData.strings.jerkgram.searchSettings,
                cancel: self.cancel
            )
        }
    }

    func node(current: ItemListControllerSearchNode?, titleContentNode: (NavigationBarContentNode & ItemListControllerSearchNavigationContentNode)?) -> ItemListControllerSearchNode {
        return JerkgramSettingsSearchItemNode(
            context: self.context,
            openPage: self.openPage
        )
    }
}

private struct JerkgramSettingsSearchControllerState: Equatable {
    let searching: Bool
}

public func jerkgramSettingsSearchController(
    context: AccountContext
) -> ViewController {
    let statePromise = ValuePromise(JerkgramSettingsSearchControllerState(searching: false), ignoreRepeated: true)
    let stateValue = Atomic(value: JerkgramSettingsSearchControllerState(searching: false))
    let updateState: ((JerkgramSettingsSearchControllerState) -> JerkgramSettingsSearchControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = JerkgramSettingsSearchArguments(openPage: { page in
        let target: ViewController
        switch page {
        case .dataAndBackup:
            target = jerkgramDataAndBackupController(context: context)
        case .stars:
            target = jerkgramStarsEditorController(context: context)
        default:
            target = ghostBaseSettingsPageController(context: context, page: page)
        }
        pushControllerImpl?(target)
    })

    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let rightNavigationButton: ItemListNavigationButton?
        if !state.searching {
            rightNavigationButton = ItemListNavigationButton(
                content: .icon(.search),
                style: .regular,
                enabled: true,
                action: {
                    updateState { current in
                        return JerkgramSettingsSearchControllerState(searching: true)
                    }
                }
            )
        } else {
            rightNavigationButton = nil
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(presentationData.strings.jerkgram.searchSettings),
            leftNavigationButton: nil,
            rightNavigationButton: rightNavigationButton,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )

        var searchItem: ItemListControllerSearch?
        if state.searching {
            searchItem = JerkgramSettingsSearchItem(
                context: context,
                openPage: arguments.openPage,
                cancel: {
                    updateState { current in
                        return JerkgramSettingsSearchControllerState(searching: false)
                    }
                }
            )
        }

        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: jerkgramSettingsSearchEntries(
                query: nil,
                strings: presentationData.strings.jerkgram
            ),
            style: .blocks,
            searchItem: searchItem,
            animateChanges: false
        )

        return (controllerState, (listState, arguments as Any))
    }

    let controller = ItemListController(
        context: context,
        state: signal
    )

    pushControllerImpl = { [weak controller] target in
        controller?.push(target)
    }

    return controller
}
