import SwiftUI
import AppKit
import AVFoundation
import UserNotifications

@main
struct NewsWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
    
    init() {
        // Hide app from dock - delay to ensure NSApp is ready
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var eventMonitor: Any?
    var speechRate: Double = 0.5
    var refreshSoundName = "Pop"
    var newsSoundName = "Submarine"
    var keywordSoundName = "Glass"
    var monitoredKeywords: [String] = []
    var refreshInterval: Double = 30.0
    var startupMenuItem: NSMenuItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permissions
        requestNotificationPermissions()
        
        // Load saved speech rate from UserDefaults
        let savedSpeechRate = UserDefaults.standard.double(forKey: "SpeechRate")
        if savedSpeechRate > 0 {
            speechRate = savedSpeechRate
        }
        
        // Load saved sound preferences from UserDefaults
        if let savedRefreshSound = UserDefaults.standard.string(forKey: "RefreshSound") {
            refreshSoundName = savedRefreshSound
        }
        if let savedNewsSound = UserDefaults.standard.string(forKey: "NewsSound") {
            newsSoundName = savedNewsSound
        }
        if let savedKeywordSound = UserDefaults.standard.string(forKey: "KeywordSound") {
            keywordSoundName = savedKeywordSound
        }
        
        // Load saved keywords from UserDefaults
        if let savedKeywords = UserDefaults.standard.array(forKey: "MonitoredKeywords") as? [String] {
            monitoredKeywords = savedKeywords
        }
        
        // Load saved refresh interval from UserDefaults
        let savedRefreshInterval = UserDefaults.standard.double(forKey: "RefreshInterval")
        if savedRefreshInterval > 0 {
            refreshInterval = savedRefreshInterval
        }
        
        // Set default broadcast settings if not already configured
        if UserDefaults.standard.object(forKey: "ImportantNewsBroadcastEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "ImportantNewsBroadcastEnabled")
        }
        if UserDefaults.standard.object(forKey: "ImportantNewsBroadcastTitle") == nil {
            UserDefaults.standard.set(true, forKey: "ImportantNewsBroadcastTitle")
        }
        if UserDefaults.standard.object(forKey: "KeywordNewsBroadcastEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "KeywordNewsBroadcastEnabled")
        }
        if UserDefaults.standard.object(forKey: "KeywordNewsBroadcastTitle") == nil {
            UserDefaults.standard.set(false, forKey: "KeywordNewsBroadcastTitle")
        }
        
        setupMenuBar()
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Use simple programmatic icon for menu bar
            button.image = createDirectAPINewsIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "SinaNews24 - Direct API (Click for latest news)"
            
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            
            // Ensure no menu is set by default (manual handling only)
            button.menu = nil
        }
        
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 350, height: 400)
        popover?.behavior = .applicationDefined
        popover?.animates = true
        popover?.delegate = self
        popover?.contentViewController = NSHostingController(rootView: ContentView(speechRate: speechRate))
        
        setupStatusMenu()
    }
    
    func setupStatusMenu() {
        // Menu will be created dynamically on right-click
    }
    
    @objc func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else {
            return
        }
        
        if event.type == .rightMouseUp {
            // Right click - show menu
            showContextMenu()
        } else {
            // Left click - refresh news and open popover
            refreshNewsAndOpenPopover()
        }
    }
    
    func showContextMenu() {
        // Close popover when showing context menu
        if popover?.isShown == true {
            closePopover()
        }
        
        let menu = NSMenu()
        
        let refreshItem = NSMenuItem(title: "Refresh News", action: #selector(refreshNews), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Direct API indicator
        let apiInfoItem = NSMenuItem(title: "🚀 API Settings...", action: #selector(showAPISettings), keyEquivalent: "")
        apiInfoItem.target = self
        menu.addItem(apiInfoItem)
        
        let voiceSpeedItem = NSMenuItem(title: "Voice Speed...", action: #selector(showVoiceSpeedSettings), keyEquivalent: "")
        voiceSpeedItem.target = self
        menu.addItem(voiceSpeedItem)
        
        let keywordSettingsItem = NSMenuItem(title: "Keyword Monitoring", action: #selector(showKeywordSettings), keyEquivalent: "")
        keywordSettingsItem.target = self
        menu.addItem(keywordSettingsItem)
        
        let broadcastSettingsItem = NSMenuItem(title: "Broadcast Settings...", action: #selector(showBroadcastSettings), keyEquivalent: "")
        broadcastSettingsItem.target = self
        menu.addItem(broadcastSettingsItem)
        
        let refreshIntervalItem = NSMenuItem(title: "Refresh Interval...", action: #selector(showRefreshIntervalSettings), keyEquivalent: "")
        refreshIntervalItem.target = self
        menu.addItem(refreshIntervalItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Create start at login menu item
        let enabled = isStartAtLoginEnabled()
        let startupItem = NSMenuItem(title: "Start at Login: \(enabled ? "On" : "Off")", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        startupItem.target = self
        menu.addItem(startupItem)
        
        let quitItem = NSMenuItem(title: "Quit SinaNews24", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Show menu manually for right-click only
        if let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
        }
    }
    
    @objc func togglePopover() {
        if statusItem?.button != nil {
            if popover?.isShown == true {
                closePopover()
            } else {
                openPopover()
            }
        }
    }
    
    func refreshNewsAndOpenPopover() {
        if popover?.isShown == true {
            // If popover is already open, refresh the news and play sound
            triggerManualRefresh()
        } else {
            // If popover is closed, open it with fresh content and play sound
            triggerManualRefresh()
            openPopover()
        }
    }
    
    func triggerManualRefresh() {
        // Play refresh sound
        let soundName = UserDefaults.standard.string(forKey: "RefreshSound") ?? "Pop"
        if soundName != "None", let sound = NSSound(named: soundName) {
            sound.play()
            print("🔊 Playing refresh sound: \(soundName)")
        }
        
        // Force refresh by recreating the ContentView
        let contentView = ContentView(speechRate: speechRate)
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }
    
    func openPopover() {
        guard let button = statusItem?.button else { return }
        
        // Create ContentView with the current speech rate
        let contentView = ContentView(speechRate: speechRate)
        
        // Refresh news when opening popover
        popover?.contentViewController = NSHostingController(rootView: contentView)
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // Bring app to front and focus the window
        NSApp.activate(ignoringOtherApps: true)
        
        // Ensure the popover window gets focus
        DispatchQueue.main.async {
            if let popoverWindow = self.popover?.contentViewController?.view.window {
                popoverWindow.makeKeyAndOrderFront(nil)
                popoverWindow.orderFrontRegardless()
            }
        }
        
        // Add global monitor for clicks outside
        addGlobalMonitor()
    }
    
    func closePopover() {
        popover?.performClose(nil)
        removeGlobalMonitor()
    }
    
    @objc func refreshNews() {
        // Force refresh news
        if popover?.isShown == true {
            let contentView = ContentView(speechRate: speechRate)
            popover?.contentViewController = NSHostingController(rootView: contentView)
        }
    }
    
    class VoiceSpeedDialogController: NSObject {
        let speedLabel: NSTextField
        let speedSlider: NSSlider
        let testSynthesizer: AVSpeechSynthesizer
        var speechDemoTimer: Timer?
        
        init(initialRate: Double) {
            speedLabel = NSTextField(labelWithString: "Speed: \(String(format: "%.1fx", initialRate * 2))")
            speedSlider = NSSlider()
            testSynthesizer = AVSpeechSynthesizer()
            
            super.init()
            
            setupSlider(initialRate: initialRate)
        }
        
        private func setupSlider(initialRate: Double) {
            speedSlider.frame = NSRect(x: 10, y: 45, width: 300, height: 20)
            speedSlider.minValue = 0.1
            speedSlider.maxValue = 1.2
            speedSlider.doubleValue = initialRate
            speedSlider.numberOfTickMarks = 12
            speedSlider.allowsTickMarkValuesOnly = false
            speedSlider.tickMarkPosition = .below
            speedSlider.isContinuous = true
            speedSlider.target = self
            speedSlider.action = #selector(sliderChanged(_:))
        }
        
        @objc func sliderChanged(_ slider: NSSlider) {
            let displaySpeed = slider.doubleValue * 2.0
            speedLabel.stringValue = "Speed: \(String(format: "%.1fx", displaySpeed))"
            
            // Debounce speech demo
            speechDemoTimer?.invalidate()
            speechDemoTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                self.playSpeechDemo(rate: slider.doubleValue)
            }
        }
        
        private func playSpeechDemo(rate: Double) {
            // Stop any current speech
            testSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
            
            // Create utterance
            let utterance = AVSpeechUtterance(string: "播报速度预览")
            utterance.rate = Float(rate)
            utterance.volume = 0.95
            utterance.pitchMultiplier = 1.05
            
            // Get Chinese voice
            let availableVoices = AVSpeechSynthesisVoice.speechVoices()
            let chineseVoices = availableVoices.filter { $0.language.hasPrefix("zh") }
            
            if let voice = chineseVoices.first(where: { $0.quality == .enhanced }) ?? chineseVoices.first {
                utterance.voice = voice
            }
            
            testSynthesizer.speak(utterance)
        }
        
        func stopSpeech() {
            speechDemoTimer?.invalidate()
            testSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        }
    }

    @objc func showVoiceSpeedSettings() {
        let alert = NSAlert()
        alert.messageText = "Voice Speed Settings"
        alert.informativeText = "Adjust the voice speed for news announcements:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        if let iconPath = Bundle.main.path(forResource: "SinaNews24", ofType: "icns"),
           let appIcon = NSImage(contentsOfFile: iconPath) {
            alert.icon = appIcon
        } else if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        
        // Create dialog controller
        let dialogController = VoiceSpeedDialogController(initialRate: speechRate)
        
        // Create container view
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        
        // Setup speed label
        dialogController.speedLabel.frame = NSRect(x: 0, y: 70, width: 320, height: 20)
        dialogController.speedLabel.alignment = .center
        dialogController.speedLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        containerView.addSubview(dialogController.speedLabel)
        
        // Add slider
        containerView.addSubview(dialogController.speedSlider)
        
        // Speed range labels
        let slowLabel = NSTextField(labelWithString: "Slow")
        slowLabel.frame = NSRect(x: 10, y: 25, width: 50, height: 15)
        slowLabel.font = NSFont.systemFont(ofSize: 10)
        slowLabel.textColor = .secondaryLabelColor
        slowLabel.alignment = .left
        containerView.addSubview(slowLabel)
        
        let fastLabel = NSTextField(labelWithString: "Fast")
        fastLabel.frame = NSRect(x: 260, y: 25, width: 50, height: 15)
        fastLabel.font = NSFont.systemFont(ofSize: 10)
        fastLabel.textColor = .secondaryLabelColor
        fastLabel.alignment = .right
        containerView.addSubview(fastLabel)
        
        // Instructions
        let instructionLabel = NSTextField(labelWithString: "Drag the slider to test different speeds in real-time")
        instructionLabel.frame = NSRect(x: 0, y: 5, width: 320, height: 15)
        instructionLabel.alignment = .center
        instructionLabel.font = NSFont.systemFont(ofSize: 11)
        instructionLabel.textColor = .secondaryLabelColor
        containerView.addSubview(instructionLabel)
        
        alert.accessoryView = containerView
        
        // Keep strong reference
        objc_setAssociatedObject(containerView, "dialogController", dialogController, .OBJC_ASSOCIATION_RETAIN)
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            speechRate = dialogController.speedSlider.doubleValue
            UserDefaults.standard.set(speechRate, forKey: "SpeechRate")
            print("✅ Speech rate saved: \(speechRate)")
        }
        
        dialogController.stopSpeech()
    }

    @objc func showRefreshIntervalSettings() {
        let alert = NSAlert()
        alert.messageText = "Refresh Interval Settings"
        alert.informativeText = "Adjust how often news is refreshed in the background:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        if let iconPath = Bundle.main.path(forResource: "SinaNews24", ofType: "icns"),
           let appIcon = NSImage(contentsOfFile: iconPath) {
            alert.icon = appIcon
        } else if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        
        // Create dialog controller for proper real-time updates
        let dialogController = RefreshIntervalDialogController(initialInterval: refreshInterval)
        
        // Create container view
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        
        // Setup interval label
        dialogController.intervalLabel.frame = NSRect(x: 0, y: 70, width: 320, height: 20)
        dialogController.intervalLabel.alignment = .center
        dialogController.intervalLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        containerView.addSubview(dialogController.intervalLabel)
        
        // Add slider
        containerView.addSubview(dialogController.intervalSlider)
        
        // Range labels with key intervals
        let fastLabel = NSTextField(labelWithString: "5s")
        fastLabel.frame = NSRect(x: 10, y: 25, width: 30, height: 15)
        fastLabel.font = NSFont.systemFont(ofSize: 9)
        fastLabel.textColor = .secondaryLabelColor
        fastLabel.alignment = .left
        containerView.addSubview(fastLabel)
        
        let mediumLabel = NSTextField(labelWithString: "30s")
        mediumLabel.frame = NSRect(x: 145, y: 25, width: 30, height: 15)
        mediumLabel.font = NSFont.systemFont(ofSize: 9)
        mediumLabel.textColor = .secondaryLabelColor
        mediumLabel.alignment = .center
        containerView.addSubview(mediumLabel)
        
        let slowLabel = NSTextField(labelWithString: "60s")
        slowLabel.frame = NSRect(x: 280, y: 25, width: 30, height: 15)
        slowLabel.font = NSFont.systemFont(ofSize: 9)
        slowLabel.textColor = .secondaryLabelColor
        slowLabel.alignment = .right
        containerView.addSubview(slowLabel)
        
        // Instructions
        let instructionLabel = NSTextField(labelWithString: "Faster intervals use more CPU but provide more timely updates")
        instructionLabel.frame = NSRect(x: 0, y: 5, width: 320, height: 15)
        instructionLabel.alignment = .center
        instructionLabel.font = NSFont.systemFont(ofSize: 11)
        instructionLabel.textColor = .secondaryLabelColor
        containerView.addSubview(instructionLabel)
        
        alert.accessoryView = containerView
        
        // Keep strong reference
        objc_setAssociatedObject(containerView, "dialogController", dialogController, .OBJC_ASSOCIATION_RETAIN)
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            refreshInterval = dialogController.intervalSlider.doubleValue
            UserDefaults.standard.set(refreshInterval, forKey: "RefreshInterval")
            NotificationCenter.default.post(name: NSNotification.Name("RefreshIntervalChanged"), object: refreshInterval)
            print("✅ Refresh interval saved permanently: \(refreshInterval)s")
        } else {
            // User cancelled - revert to previous setting
            let savedInterval = UserDefaults.standard.double(forKey: "RefreshInterval")
            refreshInterval = savedInterval > 0 ? savedInterval : 30.0
            NotificationCenter.default.post(name: NSNotification.Name("RefreshIntervalChanged"), object: refreshInterval)
            print("❌ Refresh interval cancelled - reverted to: \(refreshInterval)s")
        }
    }
    
    class RefreshIntervalDialogController: NSObject {
        let intervalLabel: NSTextField
        let intervalSlider: NSSlider
        
        init(initialInterval: Double) {
            intervalLabel = NSTextField(labelWithString: "Interval: \(Int(initialInterval))s")
            intervalSlider = NSSlider()
            
            super.init()
            
            setupSlider(initialInterval: initialInterval)
        }
        
        private func setupSlider(initialInterval: Double) {
            intervalSlider.frame = NSRect(x: 10, y: 45, width: 300, height: 20)
            intervalSlider.minValue = 5.0
            intervalSlider.maxValue = 60.0
            intervalSlider.doubleValue = initialInterval
            intervalSlider.numberOfTickMarks = 12
            intervalSlider.allowsTickMarkValuesOnly = false
            intervalSlider.tickMarkPosition = .below
            intervalSlider.isContinuous = true
            intervalSlider.target = self
            intervalSlider.action = #selector(sliderChanged(_:))
        }
        
        @objc func sliderChanged(_ slider: NSSlider) {
            let currentValue = Int(slider.doubleValue)
            intervalLabel.stringValue = "Interval: \(currentValue)s"
        }
    }

    class TextFieldDelegate: NSObject, NSTextFieldDelegate {
        var onEnterPressed: (() -> Void)?
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onEnterPressed?()
                return true
            }
            return false
        }
    }

    class BroadcastSettingsController: NSObject {
        var importantTitleRadio: NSButton!
        var importantContentRadio: NSButton!
        var keywordTitleRadio: NSButton!
        var keywordContentRadio: NSButton!
        
        @objc func importantTitleSelected(_ sender: NSButton) {
            importantTitleRadio.state = .on
            importantContentRadio.state = .off
        }
        
        @objc func importantContentSelected(_ sender: NSButton) {
            importantTitleRadio.state = .off
            importantContentRadio.state = .on
        }
        
        @objc func keywordTitleSelected(_ sender: NSButton) {
            keywordTitleRadio.state = .on
            keywordContentRadio.state = .off
        }
        
        @objc func keywordContentSelected(_ sender: NSButton) {
            keywordTitleRadio.state = .off
            keywordContentRadio.state = .on
        }
    }

    class KeywordDialogController: NSObject {
        var keywords: [String]
        let tagContainer: NSView
        let inputField: NSTextField
        let parentDelegate: AppDelegate
        
        init(initialKeywords: [String], tagContainer: NSView, inputField: NSTextField, parentDelegate: AppDelegate) {
            self.keywords = initialKeywords
            self.tagContainer = tagContainer
            self.inputField = inputField
            self.parentDelegate = parentDelegate
            super.init()
        }
        
        func addKeyword(_ keyword: String) -> Bool {
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty && !keywords.contains(trimmed) else { return false }
            keywords.append(trimmed)
            refreshDisplay()
            return true
        }
        
        func removeKeyword(at index: Int) {
            guard index >= 0 && index < keywords.count else { return }
            keywords.remove(at: index)
            refreshDisplay()
        }
        
        func refreshDisplay() {
            // Clear existing tags
            tagContainer.subviews.forEach { $0.removeFromSuperview() }
            
            if keywords.isEmpty {
                let emptyLabel = NSTextField(labelWithString: "No keywords added yet")
                emptyLabel.frame = NSRect(x: 10, y: 40, width: 300, height: 20)
                emptyLabel.font = NSFont.systemFont(ofSize: 12)
                emptyLabel.textColor = .secondaryLabelColor
                tagContainer.addSubview(emptyLabel)
                return
            }
            
            var yPosition: CGFloat = 70
            var xPosition: CGFloat = 10
            let tagSpacing: CGFloat = 8
            let containerMaxWidth: CGFloat = 380 // Match the tag container width
            
            for (index, keyword) in keywords.enumerated() {
                // Create container view for each tag
                let containerView = NSView()
                
                // Create liquid glass keyword container
                let keywordLabel = NSTextField(labelWithString: keyword)
                keywordLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
                keywordLabel.textColor = .labelColor
                keywordLabel.backgroundColor = .clear
                keywordLabel.isBordered = false
                keywordLabel.isEditable = false
                keywordLabel.alignment = .center
                keywordLabel.sizeToFit()
                let labelSize = keywordLabel.frame.size
                keywordLabel.frame = NSRect(x: 6, y: 4, width: labelSize.width + 8, height: 18)
                
                // Container setup (calculate width first)
                let containerWidth = labelSize.width + 52
                
                // Check if this tag would exceed the right border, wrap to new line if needed
                if xPosition + containerWidth > containerMaxWidth && xPosition > 10 {
                    xPosition = 10
                    yPosition -= 35
                }
                
                // Create liquid glass background for keyword (more compact)
                let keywordBackdrop = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: labelSize.width + 20, height: 26))
                keywordBackdrop.material = .hudWindow
                keywordBackdrop.blendingMode = .behindWindow
                keywordBackdrop.state = .active
                keywordBackdrop.wantsLayer = true
                keywordBackdrop.layer?.cornerRadius = 13
                keywordBackdrop.layer?.borderWidth = 0.5
                keywordBackdrop.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
                
                // Create liquid glass delete button (more transparent)
                let deleteButton = NSButton()
                deleteButton.title = "×"
                deleteButton.bezelStyle = .circular
                deleteButton.isBordered = false
                deleteButton.font = NSFont.systemFont(ofSize: 12, weight: .bold)
                deleteButton.frame = NSRect(x: labelSize.width + 24, y: 1, width: 24, height: 24)
                deleteButton.toolTip = "Remove '\(keyword)'"
                deleteButton.wantsLayer = true
                deleteButton.layer?.cornerRadius = 12
                deleteButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.4).cgColor
                deleteButton.layer?.borderWidth = 0.5
                deleteButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
                deleteButton.contentTintColor = .white
                
                // Set up delete action using index
                deleteButton.target = self
                deleteButton.action = #selector(deleteKeywordAtIndex(_:))
                deleteButton.tag = index
                
                // Position the container
                containerView.frame = NSRect(x: xPosition, y: yPosition, width: containerWidth, height: 26)
                
                containerView.addSubview(keywordBackdrop)
                containerView.addSubview(keywordLabel)
                containerView.addSubview(deleteButton)
                tagContainer.addSubview(containerView)
                
                // Move to next position
                xPosition += containerWidth + tagSpacing
            }
            
            // Update container height based on the lowest yPosition to accommodate all lines
            let minYPosition = yPosition
            let neededHeight = max(100, 70 - minYPosition + 35) // Start height - lowest position + margin
            
            // Update the tag container frame to fit all content
            if let scrollView = tagContainer.superview as? NSScrollView {
                tagContainer.frame = NSRect(x: 0, y: 0, width: 380, height: neededHeight)
                scrollView.documentView = tagContainer
            }
            
            tagContainer.needsDisplay = true
        }
        
        @objc func deleteKeywordAtIndex(_ sender: NSButton) {
            let index = sender.tag
            removeKeyword(at: index)
        }
        
        @objc func addKeywordFromButton(_ sender: NSButton) {
            addKeywordFromInput()
        }
        
        func addKeywordFromInput() {
            let keyword = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if addKeyword(keyword) {
                inputField.stringValue = ""
            }
        }
    }

    @objc func showBroadcastSettings() {
        let alert = NSAlert()
        alert.messageText = "Broadcast Settings"
        alert.informativeText = "Control when and how news is broadcast via text-to-speech."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        if let iconPath = Bundle.main.path(forResource: "SinaNews24", ofType: "icns"),
           let appIcon = NSImage(contentsOfFile: iconPath) {
            alert.icon = appIcon
        } else if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
        
        // Create broadcast settings controller
        let broadcastController = BroadcastSettingsController()
        
        // Important News Section
        let importantLabel = NSTextField(labelWithString: "Important News (Red) Broadcast:")
        importantLabel.frame = NSRect(x: 0, y: 240, width: 420, height: 20)
        importantLabel.alignment = .left
        importantLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        importantLabel.textColor = .systemRed
        containerView.addSubview(importantLabel)
        
        // Important news enable checkbox
        let importantEnabledCheckbox = NSButton(checkboxWithTitle: "Enable important news broadcast", target: nil, action: nil)
        importantEnabledCheckbox.frame = NSRect(x: 20, y: 210, width: 300, height: 20)
        importantEnabledCheckbox.font = NSFont.systemFont(ofSize: 12)
        let importantEnabled = UserDefaults.standard.object(forKey: "ImportantNewsBroadcastEnabled") as? Bool ?? true
        importantEnabledCheckbox.state = importantEnabled ? .on : .off
        containerView.addSubview(importantEnabledCheckbox)
        
        // Important news content type radio buttons
        let importantContentLabel = NSTextField(labelWithString: "Broadcast content:")
        importantContentLabel.frame = NSRect(x: 40, y: 185, width: 120, height: 15)
        importantContentLabel.font = NSFont.systemFont(ofSize: 11)
        importantContentLabel.textColor = .secondaryLabelColor
        containerView.addSubview(importantContentLabel)
        
        let importantTitleRadio = NSButton(radioButtonWithTitle: "Title only", target: broadcastController, action: #selector(BroadcastSettingsController.importantTitleSelected(_:)))
        importantTitleRadio.frame = NSRect(x: 60, y: 160, width: 100, height: 20)
        importantTitleRadio.font = NSFont.systemFont(ofSize: 11)
        broadcastController.importantTitleRadio = importantTitleRadio
        containerView.addSubview(importantTitleRadio)
        
        let importantContentRadio = NSButton(radioButtonWithTitle: "Full content", target: broadcastController, action: #selector(BroadcastSettingsController.importantContentSelected(_:)))
        importantContentRadio.frame = NSRect(x: 180, y: 160, width: 120, height: 20)
        importantContentRadio.font = NSFont.systemFont(ofSize: 11)
        broadcastController.importantContentRadio = importantContentRadio
        containerView.addSubview(importantContentRadio)
        
        // Set default/saved state for important news
        let importantBroadcastTitle = UserDefaults.standard.object(forKey: "ImportantNewsBroadcastTitle") as? Bool ?? true
        if importantBroadcastTitle {
            importantTitleRadio.state = .on
            importantContentRadio.state = .off
        } else {
            importantTitleRadio.state = .off
            importantContentRadio.state = .on
        }
        
        // Separator line
        let separatorView = NSView(frame: NSRect(x: 0, y: 130, width: 420, height: 1))
        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = NSColor.separatorColor.cgColor
        containerView.addSubview(separatorView)
        
        // Keyword News Section
        let keywordLabel = NSTextField(labelWithString: "Keyword Matching News Broadcast:")
        keywordLabel.frame = NSRect(x: 0, y: 100, width: 420, height: 20)
        keywordLabel.alignment = .left
        keywordLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        keywordLabel.textColor = .systemBlue
        containerView.addSubview(keywordLabel)
        
        // Keyword news enable checkbox
        let keywordEnabledCheckbox = NSButton(checkboxWithTitle: "Enable keyword news broadcast", target: nil, action: nil)
        keywordEnabledCheckbox.frame = NSRect(x: 20, y: 70, width: 300, height: 20)
        keywordEnabledCheckbox.font = NSFont.systemFont(ofSize: 12)
        let keywordEnabled = UserDefaults.standard.object(forKey: "KeywordNewsBroadcastEnabled") as? Bool ?? true
        keywordEnabledCheckbox.state = keywordEnabled ? .on : .off
        containerView.addSubview(keywordEnabledCheckbox)
        
        // Keyword news content type radio buttons
        let keywordContentLabel = NSTextField(labelWithString: "Broadcast content:")
        keywordContentLabel.frame = NSRect(x: 40, y: 45, width: 120, height: 15)
        keywordContentLabel.font = NSFont.systemFont(ofSize: 11)
        keywordContentLabel.textColor = .secondaryLabelColor
        containerView.addSubview(keywordContentLabel)
        
        let keywordTitleRadio = NSButton(radioButtonWithTitle: "Title only", target: broadcastController, action: #selector(BroadcastSettingsController.keywordTitleSelected(_:)))
        keywordTitleRadio.frame = NSRect(x: 60, y: 20, width: 100, height: 20)
        keywordTitleRadio.font = NSFont.systemFont(ofSize: 11)
        broadcastController.keywordTitleRadio = keywordTitleRadio
        containerView.addSubview(keywordTitleRadio)
        
        let keywordContentRadio = NSButton(radioButtonWithTitle: "Full content", target: broadcastController, action: #selector(BroadcastSettingsController.keywordContentSelected(_:)))
        keywordContentRadio.frame = NSRect(x: 180, y: 20, width: 120, height: 20)
        keywordContentRadio.font = NSFont.systemFont(ofSize: 11)
        broadcastController.keywordContentRadio = keywordContentRadio
        containerView.addSubview(keywordContentRadio)
        
        // Set default/saved state for keyword news
        let keywordBroadcastTitle = UserDefaults.standard.object(forKey: "KeywordNewsBroadcastTitle") as? Bool ?? false
        if keywordBroadcastTitle {
            keywordTitleRadio.state = .on
            keywordContentRadio.state = .off
        } else {
            keywordTitleRadio.state = .off
            keywordContentRadio.state = .on
        }
        
        alert.accessoryView = containerView
        
        // Keep strong reference to controller
        objc_setAssociatedObject(containerView, "broadcastController", broadcastController, .OBJC_ASSOCIATION_RETAIN)
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Save important news settings
            UserDefaults.standard.set(importantEnabledCheckbox.state == .on, forKey: "ImportantNewsBroadcastEnabled")
            UserDefaults.standard.set(broadcastController.importantTitleRadio.state == .on, forKey: "ImportantNewsBroadcastTitle")
            
            // Save keyword news settings
            UserDefaults.standard.set(keywordEnabledCheckbox.state == .on, forKey: "KeywordNewsBroadcastEnabled")
            UserDefaults.standard.set(broadcastController.keywordTitleRadio.state == .on, forKey: "KeywordNewsBroadcastTitle")
            
        }
    }

    @objc func showAPISettings() {
        let alert = NSAlert()
        alert.messageText = "API Settings"
        alert.informativeText = "Configure the news API endpoint and parameters."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        if let iconPath = Bundle.main.path(forResource: "SinaNews24", ofType: "icns"),
           let appIcon = NSImage(contentsOfFile: iconPath) {
            alert.icon = appIcon
        } else if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        
        let apiLabel = NSTextField(labelWithString: "API Endpoint:")
        apiLabel.frame = NSRect(x: 0, y: 90, width: 100, height: 20)
        apiLabel.alignment = .left
        apiLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        containerView.addSubview(apiLabel)
        
        let apiField = NSTextField(frame: NSRect(x: 0, y: 60, width: 400, height: 24))
        apiField.stringValue = "https://zhibo.sina.com.cn/api/zhibo/feed"
        apiField.bezelStyle = .roundedBezel
        containerView.addSubview(apiField)
        
        let statusLabel = NSTextField(labelWithString: "Status: Connected to Sina News API")
        statusLabel.frame = NSRect(x: 0, y: 30, width: 400, height: 20)
        statusLabel.alignment = .left
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .systemGreen
        containerView.addSubview(statusLabel)
        
        let instructionLabel = NSTextField(labelWithString: "Note: Currently using the default Sina News API endpoint.")
        instructionLabel.frame = NSRect(x: 0, y: 5, width: 400, height: 20)
        instructionLabel.alignment = .left
        instructionLabel.font = NSFont.systemFont(ofSize: 10)
        instructionLabel.textColor = .secondaryLabelColor
        containerView.addSubview(instructionLabel)
        
        alert.accessoryView = containerView
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            UserDefaults.standard.set(apiField.stringValue, forKey: "APIEndpoint")
        }
    }

    @objc func showKeywordSettings() {
        let alert = NSAlert()
        alert.messageText = "Keyword Monitoring"
        alert.informativeText = "Add Chinese keywords to monitor. When these words appear in news, the full content will be read aloud."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        if let iconPath = Bundle.main.path(forResource: "SinaNews24", ofType: "icns"),
           let appIcon = NSImage(contentsOfFile: iconPath) {
            alert.icon = appIcon
        } else if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        
        // Create container for keyword settings (more compact)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 280))
        
        // Keywords management - hide the label and make area more compact
        let keywordsLabel = NSTextField(labelWithString: "Keywords:")
        keywordsLabel.frame = NSRect(x: 0, y: 240, width: 80, height: 20)
        keywordsLabel.alignment = .left
        keywordsLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        keywordsLabel.isHidden = true  // Hide the label
        containerView.addSubview(keywordsLabel)
        
        // Create liquid glass input field (more compact, no placeholder)
        let inputField = NSTextField(frame: NSRect(x: 0, y: 230, width: 300, height: 28))
        inputField.placeholderString = ""
        inputField.bezelStyle = .roundedBezel
        inputField.isBordered = false
        inputField.backgroundColor = .clear
        inputField.textColor = .labelColor
        inputField.font = NSFont.systemFont(ofSize: 12)
        inputField.alignment = .left
        inputField.usesSingleLineMode = true
        inputField.cell?.sendsActionOnEndEditing = false
        
        // Liquid glass styling for input field
        inputField.wantsLayer = true
        inputField.layer?.cornerRadius = 16
        inputField.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.1).cgColor
        
        // Add material effect background (better positioned)
        let inputBackdrop = NSVisualEffectView(frame: NSRect(x: 0, y: 230, width: 300, height: 28))
        inputBackdrop.material = .hudWindow
        inputBackdrop.blendingMode = .behindWindow
        inputBackdrop.state = .active
        inputBackdrop.wantsLayer = true
        inputBackdrop.layer?.cornerRadius = 14
        inputBackdrop.layer?.borderWidth = 0.5
        inputBackdrop.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        
        containerView.addSubview(inputBackdrop)
        containerView.addSubview(inputField)
        
        // Liquid glass add button (positioned correctly)
        let addButton = NSButton(frame: NSRect(x: 310, y: 230, width: 60, height: 28))
        addButton.title = "Add"
        addButton.bezelStyle = .rounded
        addButton.isBordered = false
        addButton.wantsLayer = true
        addButton.layer?.cornerRadius = 14
        addButton.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        addButton.layer?.borderWidth = 0.5
        addButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        addButton.contentTintColor = .white
        addButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        containerView.addSubview(addButton)
        
        // Tag display area (more compact)
        let tagScrollView = NSScrollView(frame: NSRect(x: 0, y: 120, width: 400, height: 100))
        tagScrollView.hasVerticalScroller = true
        tagScrollView.autohidesScrollers = true
        tagScrollView.borderType = .noBorder
        tagScrollView.backgroundColor = NSColor.clear
        tagScrollView.drawsBackground = false
        
        let tagContainerView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 100))
        tagContainerView.wantsLayer = true
        tagContainerView.layer?.backgroundColor = NSColor.clear.cgColor
        
        tagScrollView.documentView = tagContainerView
        containerView.addSubview(tagScrollView)
        
        // Instructions (more compact and better organized)
        let instructionLabel = NSTextField(labelWithString: "Type keywords and press Enter or click Add. Click × to remove.\nExample: 股市, 地震, 疫情, 政策")
        instructionLabel.frame = NSRect(x: 0, y: 20, width: 400, height: 50)
        instructionLabel.alignment = .left
        instructionLabel.font = NSFont.systemFont(ofSize: 11)
        instructionLabel.textColor = .secondaryLabelColor
        instructionLabel.isEditable = false
        instructionLabel.isBordered = false
        instructionLabel.backgroundColor = .clear
        instructionLabel.maximumNumberOfLines = 3
        containerView.addSubview(instructionLabel)
        
        alert.accessoryView = containerView
        
        // Create dialog controller
        let dialogController = KeywordDialogController(
            initialKeywords: monitoredKeywords,
            tagContainer: tagContainerView,
            inputField: inputField,
            parentDelegate: self
        )
        
        // Store controller reference
        objc_setAssociatedObject(containerView, "dialogController", dialogController, .OBJC_ASSOCIATION_RETAIN)
        
        // Initial display
        dialogController.refreshDisplay()
        
        // Add button action
        addButton.target = dialogController
        addButton.action = #selector(KeywordDialogController.addKeywordFromButton(_:))
        
        // Enter key action for input field
        let fieldDelegate = TextFieldDelegate()
        fieldDelegate.onEnterPressed = {
            dialogController.addKeywordFromInput()
        }
        inputField.delegate = fieldDelegate
        objc_setAssociatedObject(inputField, "fieldDelegate", fieldDelegate, .OBJC_ASSOCIATION_RETAIN)
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Save the keywords
            monitoredKeywords = dialogController.keywords
            UserDefaults.standard.set(monitoredKeywords, forKey: "MonitoredKeywords")
        }
    }
    

    @objc func toggleStartAtLogin() {
        // Use simple UserDefaults tracking instead of AppleScript
        let currentState = UserDefaults.standard.bool(forKey: "StartAtLogin")
        let newState = !currentState
        
        let appName = "SinaNews24"
        
        if newState {
            // Enable start at login
            let script = """
            tell application "System Events"
                make login item at end with properties {path:"\(Bundle.main.bundlePath)", hidden:false, name:"\(appName)"}
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(nil)
            }
        } else {
            // Disable start at login
            let script = """
            tell application "System Events"
                delete login item "\(appName)"
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(nil)
            }
        }
        
        // Save the new state
        UserDefaults.standard.set(newState, forKey: "StartAtLogin")
    }
    
    func isStartAtLoginEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "StartAtLogin")
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            // Notification permission handling
        }
    }
    
    func sendImportantNewsNotification(title: String, content: String) {
        let center = UNUserNotificationCenter.current()
        
        // Create notification content
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "🚨 重要新闻"
        notificationContent.subtitle = title
        notificationContent.body = content
        notificationContent.sound = UNNotificationSound.default
        notificationContent.badge = 1
        
        // Make notification persistent - don't auto-dismiss
        notificationContent.categoryIdentifier = "IMPORTANT_NEWS"
        
        // Create unique identifier based on content hash
        let identifier = "important_news_\(abs(content.hashValue))"
        
        // Create trigger (immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: notificationContent, trigger: trigger)
        
        // Schedule notification
        center.add(request) { error in
            // Notification scheduling handled
        }
    }
    
    func sendKeywordNewsNotification(keyword: String, title: String, content: String) {
        let center = UNUserNotificationCenter.current()
        
        // Create notification content
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "🔍 关键词匹配: \(keyword)"
        notificationContent.subtitle = title
        notificationContent.body = content
        notificationContent.sound = UNNotificationSound.default
        notificationContent.badge = 1
        
        // Make notification persistent
        notificationContent.categoryIdentifier = "KEYWORD_NEWS"
        
        // Create unique identifier
        let identifier = "keyword_news_\(keyword)_\(abs(content.hashValue))"
        
        // Create trigger (immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: notificationContent, trigger: trigger)
        
        // Schedule notification
        center.add(request) { error in
            // Keyword notification scheduling handled
        }
    }
    
    private func createDirectAPINewsIcon() -> NSImage {
        // Create a radar-style icon for news monitoring
        let size = NSSize(width: 22, height: 20)  // Larger overall size
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        
        // Use system color for proper dark/light mode adaptation
        let strokeColor = NSColor.labelColor
        let center = NSPoint(x: 11, y: 10)  // Adjusted for new size
        let maxRadius: CGFloat = 8.5  // Larger radius
        
        // Draw radar circles (3 concentric circles) with gradient transparency
        for i in 1...3 {
            let radius = CGFloat(i) * (maxRadius / 3)
            let circlePath = NSBezierPath()
            circlePath.appendOval(in: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            
            // Gradient transparency: inner more opaque, outer more transparent
            let alpha = 0.9 - CGFloat(i - 1) * 0.25  // 0.9, 0.65, 0.4
            strokeColor.withAlphaComponent(alpha).setStroke()
            
            // Gradient line width: inner thicker, outer thinner
            let lineWidth = 1.2 - CGFloat(i - 1) * 0.2  // 1.2, 1.0, 0.8
            circlePath.lineWidth = lineWidth
            circlePath.stroke()
        }
        
        // Draw radar sweep line (rotating line from center)
        let sweepPath = NSBezierPath()
        sweepPath.move(to: center)
        let sweepEndX = center.x + maxRadius * cos(45 * .pi / 180) // 45 degree angle
        let sweepEndY = center.y + maxRadius * sin(45 * .pi / 180)
        sweepPath.line(to: NSPoint(x: sweepEndX, y: sweepEndY))
        
        strokeColor.withAlphaComponent(0.95).setStroke()  // Keep sweep line prominent
        sweepPath.lineWidth = 1.5  // Slightly thicker sweep line
        sweepPath.stroke()
        
        // Draw center dot
        let centerDot = NSBezierPath()
        centerDot.appendOval(in: NSRect(
            x: center.x - 1.3,
            y: center.y - 1.3,
            width: 2.6,
            height: 2.6
        ))
        strokeColor.withAlphaComponent(0.98).setFill()  // Most opaque element
        centerDot.fill()
        
        // Draw small activity dots to represent news signals
        let activityDots = [
            NSPoint(x: center.x + 5, y: center.y + 2.5),
            NSPoint(x: center.x - 4, y: center.y + 4.5),
            NSPoint(x: center.x + 3, y: center.y - 5.5)
        ]
        
        for dot in activityDots {
            let dotPath = NSBezierPath()
            dotPath.appendOval(in: NSRect(
                x: dot.x - 0.8,
                y: dot.y - 0.8,
                width: 1.6,
                height: 1.6
            ))
            strokeColor.withAlphaComponent(0.8).setFill()  // Medium opacity for dots
            dotPath.fill()
        }
        
        context?.restoreGState()
        image.unlockFocus()
        image.isTemplate = true
        
        return image
    }
}

extension AppDelegate {
    func addGlobalMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }
    
    func removeGlobalMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

extension AppDelegate {
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        return true
    }
    
    func popoverDidClose(_ notification: Notification) {
        removeGlobalMonitor()
    }
    
    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        return false // Keep as popover, don't detach
    }
}