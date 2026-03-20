import AppKit
import Carbon.HIToolbox
import GameController
import MoonlightCore

@MainActor
final class StreamInputView: NSView {
    private static let rawMouseQueue = DispatchQueue(label: "GameStream.RawMouse", qos: .userInteractive)

    private final class RawMouseDispatchState {
        private let lock = NSLock()
        private var remainderX = 0.0
        private var remainderY = 0.0
        private var mouseMode: StreamMouseMode = .absolute
        private var mouseCaptureActive = false
        private var rawMouseScale = 1.0

        func update(mouseMode: StreamMouseMode? = nil, mouseCaptureActive: Bool? = nil, rawMouseScale: Double? = nil) {
            lock.lock()
            defer { lock.unlock() }

            if let mouseMode {
                self.mouseMode = mouseMode
            }
            if let mouseCaptureActive {
                self.mouseCaptureActive = mouseCaptureActive
            }
            if let rawMouseScale {
                self.rawMouseScale = rawMouseScale
            }
        }

        func reset() {
            lock.lock()
            remainderX = 0
            remainderY = 0
            lock.unlock()
        }

        func translate(deltaX: Double, deltaY: Double) -> (Int32, Int32)? {
            lock.lock()
            defer { lock.unlock() }

            guard mouseMode == .raw, mouseCaptureActive else {
                return nil
            }

            let translatedDeltaX = Self.translate(value: deltaX * rawMouseScale, remainder: &remainderX)
            let translatedDeltaY = Self.translate(value: -deltaY * rawMouseScale, remainder: &remainderY)

            guard translatedDeltaX != 0 || translatedDeltaY != 0 else {
                return nil
            }

            return (translatedDeltaX, translatedDeltaY)
        }

        private static func translate(value: Double, remainder: inout Double) -> Int32 {
            guard value.isFinite else {
                return 0
            }

            let totalDelta = remainder + value
            let integralDelta = totalDelta.rounded(.towardZero)
            remainder = totalDelta - integralDelta
            return Int32(clamping: Int64(integralDelta))
        }
    }

    private struct PressedKeyState {
        let mapping: WindowsVirtualKeyMap.Mapping

        init(mapping: WindowsVirtualKeyMap.Mapping) {
            self.mapping = mapping
        }

        var keyCode: UInt16 { mapping.keyCode }
        var virtualKey: UInt16 { mapping.virtualKey }
        var flags: SessionController.KeyboardFlags { mapping.flags }
        var isModifier: Bool { mapping.isModifier }
    }

    private let sessionController: SessionController
    private let streamResolution: CGSize
    private let rawMouseDispatchState = RawMouseDispatchState()
    private var rawMouseScale: Double

    private var trackingArea: NSTrackingArea?
    private var rawMouseObservers: [NSObjectProtocol] = []
    private var rawMouseDevices: [ObjectIdentifier: GCMouse] = [:]
    private var commandKeyActive = false
    private var suppressRemoteInputForLocalCommand = false
    private var mouseInsideVideoRegion = false
    private var continueAbsoluteDragOutsideVideoRegion = false
    private var mouseCaptureActive = false
    private var localCursorHiddenByView = false
    private var physicallyPressedMouseButtons: Set<SessionController.MouseButton> = []
    private var remotelyPressedMouseButtons: Set<SessionController.MouseButton> = []
    private var physicallyPressedKeyboardInputs: [UInt16: PressedKeyState] = [:]
    private var remotelyPressedKeyboardInputs: [UInt16: PressedKeyState] = [:]

    var onLocalCommandSuppressionChanged: ((Bool) -> Void)?
    var onHideStreamRequested: (() -> Void)?
    var onStopSessionRequested: (() -> Void)?
    var onQuitApplicationRequested: (() -> Void)?

    var rendererView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()

            guard let rendererView else {
                return
            }

            rendererView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(rendererView, positioned: .below, relativeTo: nil)

            NSLayoutConstraint.activate([
                rendererView.leadingAnchor.constraint(equalTo: leadingAnchor),
                rendererView.trailingAnchor.constraint(equalTo: trailingAnchor),
                rendererView.topAnchor.constraint(equalTo: topAnchor),
                rendererView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    var mouseMode: StreamMouseMode = .absolute {
        didSet {
            guard oldValue != mouseMode else {
                return
            }

            rawMouseDispatchState.update(mouseMode: mouseMode)
            resetInputState(releaseRemote: true, clearLocal: true, resetPointerTracking: false)
        }
    }

    init(sessionController: SessionController) {
        self.sessionController = sessionController
        let resolution = sessionController.configuration.video.resolution
        self.streamResolution = CGSize(width: resolution.width, height: resolution.height)
        self.rawMouseScale = sessionController.configuration.input.effectiveRawMouseScale
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        rawMouseDispatchState.update(mouseMode: mouseMode, mouseCaptureActive: mouseCaptureActive, rawMouseScale: rawMouseScale)
        configureRawMouseObservation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }

        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        _ = event
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        if newWindow == nil {
            tearDownRawMouseObservation()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    func setFullscreenPresentation(_ isFullscreen: Bool) {
        layer?.cornerRadius = isFullscreen ? 0 : 14
    }

    func setMouseCaptureState(_ isActive: Bool) {
        guard mouseCaptureActive != isActive else {
            return
        }

        mouseCaptureActive = isActive
        rawMouseDispatchState.update(mouseCaptureActive: isActive)
        if isActive {
            updateCursorVisibility()
        } else {
            resetInputState(releaseRemote: true, clearLocal: true, resetPointerTracking: false)
        }
    }

    func updateInputConfiguration(_ input: MVPConfiguration.Input) {
        rawMouseScale = input.effectiveRawMouseScale
        rawMouseDispatchState.update(rawMouseScale: rawMouseScale)
        rawMouseDispatchState.reset()
    }

    func releaseAllRemoteInputs() {
        resetInputState(releaseRemote: true, clearLocal: true, resetPointerTracking: false)
    }

    func resetLocalInputState() {
        resetInputState(releaseRemote: false, clearLocal: true, resetPointerTracking: true)
    }

    func handleWindowDidResignKey() {
        resetInputState(releaseRemote: true, clearLocal: true, resetPointerTracking: true)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        window?.makeFirstResponder(self)
        mouseInsideVideoRegion = videoRect().contains(convert(event.locationInWindow, from: nil))
        if mouseMode == .absolute {
            forwardAbsoluteMouseIfNeeded(locationInView: convert(event.locationInWindow, from: nil), force: true)
        }
        updateCursorVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        _ = event
        mouseInsideVideoRegion = false
        if physicallyPressedMouseButtons.isEmpty {
            continueAbsoluteDragOutsideVideoRegion = false
        }
        updateCursorVisibility()
    }

    override func mouseMoved(with event: NSEvent) {
        handleMouseMotion(event)
    }

    override func mouseDragged(with event: NSEvent) {
        handleMouseMotion(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        handleMouseMotion(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        handleMouseMotion(event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        handleMouseButton(event, button: .left, action: .press)
    }

    override func mouseUp(with event: NSEvent) {
        handleMouseButton(event, button: .left, action: .release)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        handleMouseButton(event, button: .right, action: .press)
    }

    override func rightMouseUp(with event: NSEvent) {
        handleMouseButton(event, button: .right, action: .release)
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let button = mouseButton(for: event.buttonNumber) else {
            super.otherMouseDown(with: event)
            return
        }

        handleMouseButton(event, button: button, action: .press)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let button = mouseButton(for: event.buttonNumber) else {
            super.otherMouseUp(with: event)
            return
        }

        handleMouseButton(event, button: button, action: .release)
    }

    override func scrollWheel(with event: NSEvent) {
        guard shouldForwardInput(for: event) else {
            super.scrollWheel(with: event)
            return
        }

        if mouseMode == .absolute {
            let location = convert(event.locationInWindow, from: nil)
            guard videoRect().contains(location) else {
                return
            }
        }

        let verticalAmount = scrollAmount(for: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
        if verticalAmount != 0 {
            sessionController.sendScroll(delta: verticalAmount)
        }

        let horizontalAmount = scrollAmount(for: event.scrollingDeltaX, precise: event.hasPreciseScrollingDeltas)
        if horizontalAmount != 0 {
            sessionController.sendHorizontalScroll(delta: horizontalAmount)
        }
    }

    override func keyDown(with event: NSEvent) {
        if handleLocalShortcut(event) {
            return
        }

        let shouldForward = shouldForwardKeyboard(event)

        guard let state = keyboardState(for: event.keyCode), !state.isModifier else {
            if !shouldForward {
                super.keyDown(with: event)
            }
            return
        }

        if !event.isARepeat {
            physicallyPressedKeyboardInputs[state.keyCode] = state
        }

        guard shouldForward else {
            super.keyDown(with: event)
            return
        }

        guard !event.isARepeat else {
            return
        }

        pressRemoteKeyIfNeeded(state, modifiers: keyboardModifiers(from: event.modifierFlags))
    }

    override func keyUp(with event: NSEvent) {
        let shouldForward = shouldForwardKeyboard(event)
        let state = physicallyPressedKeyboardInputs.removeValue(forKey: event.keyCode) ?? keyboardState(for: event.keyCode)

        guard shouldForward else {
            super.keyUp(with: event)
            return
        }

        guard let state, !state.isModifier else {
            return
        }

        releaseRemoteKeyIfNeeded(forKeyCode: state.keyCode, modifiers: keyboardModifiers(from: event.modifierFlags))
    }

    override func flagsChanged(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == UInt16(kVK_Command) || event.keyCode == UInt16(kVK_RightCommand) {
            let commandDown = modifiers.contains(.command)
            if commandDown && !commandKeyActive {
                beginLocalCommandSuppression()
            } else if !commandDown && commandKeyActive {
                endLocalCommandSuppression(with: modifiers)
            }
            return
        }

        guard let state = keyboardState(for: event.keyCode), state.isModifier else {
            return
        }

        let isDown = modifierKeyIsDown(for: state.keyCode, modifiers: modifiers)
        if isDown {
            physicallyPressedKeyboardInputs[state.keyCode] = state
        } else {
            physicallyPressedKeyboardInputs.removeValue(forKey: state.keyCode)
        }

        guard !suppressRemoteInputForLocalCommand else {
            return
        }

        let currentModifiers = keyboardModifiers(from: modifiers)
        if isDown {
            pressRemoteKeyIfNeeded(state, modifiers: currentModifiers)
        } else {
            releaseRemoteKeyIfNeeded(forKeyCode: state.keyCode, modifiers: currentModifiers)
        }
    }
}

private extension StreamInputView {
    func handleLocalShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch Int(event.keyCode) {
        case kVK_ANSI_W:
            if modifiers == [.command] {
                onHideStreamRequested?()
                return true
            }

            if modifiers == [.control, .shift] {
                onStopSessionRequested?()
                return true
            }
        case kVK_ANSI_Q:
            if modifiers == [.command] {
                onQuitApplicationRequested?()
                return true
            }
        default:
            break
        }

        return false
    }

    private func keyboardState(for keyCode: UInt16) -> PressedKeyState? {
        WindowsVirtualKeyMap.map(keyCode: keyCode).map(PressedKeyState.init)
    }

    func setLocalShortcutSuppression(_ isSuppressed: Bool) {
        guard suppressRemoteInputForLocalCommand != isSuppressed else {
            return
        }

        suppressRemoteInputForLocalCommand = isSuppressed
        onLocalCommandSuppressionChanged?(isSuppressed)
    }

    func beginLocalCommandSuppression() {
        commandKeyActive = true
        setLocalShortcutSuppression(true)
        releaseRemoteInputsOnly()
        updateCursorVisibility()
    }

    func endLocalCommandSuppression(with modifiers: NSEvent.ModifierFlags) {
        commandKeyActive = false
        setLocalShortcutSuppression(false)
        synchronizeRemoteModifierState(with: modifiers)
        resynchronizeCurrentlyHeldInputs(with: modifiers)
        updateCursorVisibility()
    }

    func resetInputState(releaseRemote: Bool, clearLocal: Bool, resetPointerTracking: Bool) {
        if releaseRemote {
            releaseRemoteInputsOnly()
        }

        if clearLocal {
            clearInputBookkeepingOnly()
        }

        if resetPointerTracking {
            mouseInsideVideoRegion = false
            continueAbsoluteDragOutsideVideoRegion = false
        }

        updateCursorVisibility()
    }

    func releaseRemoteInputsOnly() {
        for button in remotelyPressedMouseButtons {
            sessionController.sendMouseButton(button, action: .release)
        }
        remotelyPressedMouseButtons.removeAll()

        let remoteKeyCodes = remotelyPressedKeyboardInputs.keys.sorted()
        for keyCode in remoteKeyCodes where remotelyPressedKeyboardInputs[keyCode]?.isModifier == false {
            releaseRemoteKeyIfNeeded(forKeyCode: keyCode)
        }
        for keyCode in remoteKeyCodes where remotelyPressedKeyboardInputs[keyCode]?.isModifier == true {
            releaseRemoteKeyIfNeeded(forKeyCode: keyCode)
        }

        updateCursorVisibility()
    }

    func clearInputBookkeepingOnly() {
        commandKeyActive = false
        setLocalShortcutSuppression(false)
        rawMouseDispatchState.reset()
        physicallyPressedMouseButtons.removeAll()
        remotelyPressedMouseButtons.removeAll()
        physicallyPressedKeyboardInputs.removeAll()
        remotelyPressedKeyboardInputs.removeAll()
        continueAbsoluteDragOutsideVideoRegion = false
        updateCursorVisibility()
    }

    func resynchronizeCurrentlyHeldInputs(with modifiers: NSEvent.ModifierFlags) {
        let currentModifiers = keyboardModifiers(from: modifiers)

        for keyCode in physicallyPressedKeyboardInputs.keys.sorted() {
            guard let state = physicallyPressedKeyboardInputs[keyCode], !state.isModifier else {
                continue
            }

            pressRemoteKeyIfNeeded(state, modifiers: currentModifiers)
        }

        guard !physicallyPressedMouseButtons.isEmpty else {
            return
        }

        if mouseMode == .absolute {
            forwardCurrentAbsoluteMousePosition(force: true)
        }

        for button in physicallyPressedMouseButtons.subtracting(remotelyPressedMouseButtons) {
            sessionController.sendMouseButton(button, action: .press)
            remotelyPressedMouseButtons.insert(button)
        }
    }

    func handleMouseMotion(_ event: NSEvent) {
        guard shouldForwardInput(for: event) else {
            return
        }

        if mouseMode == .raw {
            guard mouseCaptureActive else {
                return
            }

            if hasRawMouseDeviceInput == false {
                refreshRawMouseDevices()
            }
            return
        }

        let locationInView = convert(event.locationInWindow, from: nil)
        forwardAbsoluteMouseIfNeeded(locationInView: locationInView, force: false)
    }

    func handleMouseButton(_ event: NSEvent, button: SessionController.MouseButton, action: SessionController.MouseButtonAction) {
        guard shouldForwardInput(for: event) else {
            if action == .release {
                physicallyPressedMouseButtons.remove(button)
                if mouseMode == .absolute && physicallyPressedMouseButtons.isEmpty {
                    continueAbsoluteDragOutsideVideoRegion = false
                }
            }

            if suppressRemoteInputForLocalCommand, action == .press, button == .left {
                window?.performDrag(with: event)
            }
            return
        }

        let locationInView = convert(event.locationInWindow, from: nil)
        let insideVideo = videoRect().contains(locationInView)

        if mouseMode == .absolute && action == .press && !insideVideo {
            return
        }

        if mouseMode == .raw && !mouseCaptureActive {
            return
        }

        switch action {
        case .press:
            if mouseMode == .absolute {
                forwardAbsoluteMouseIfNeeded(locationInView: locationInView, force: true)
            }

            physicallyPressedMouseButtons.insert(button)
            guard !remotelyPressedMouseButtons.contains(button) else {
                return
            }

            sessionController.sendMouseButton(button, action: .press)
            remotelyPressedMouseButtons.insert(button)
        case .release:
            physicallyPressedMouseButtons.remove(button)
            if mouseMode == .absolute && physicallyPressedMouseButtons.isEmpty {
                continueAbsoluteDragOutsideVideoRegion = false
            }

            guard remotelyPressedMouseButtons.contains(button) else {
                return
            }

            sessionController.sendMouseButton(button, action: .release)
            remotelyPressedMouseButtons.remove(button)
        }
    }

    func shouldForwardKeyboard(_ event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true else {
            return false
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            return false
        }

        return !suppressRemoteInputForLocalCommand
    }

    func shouldForwardInput(for event: NSEvent) -> Bool {
        _ = event
        guard NSApp.isActive, let window, window.isVisible, window.isKeyWindow else {
            return false
        }

        return !suppressRemoteInputForLocalCommand
    }

    func videoRect() -> CGRect {
        guard bounds.width > 0, bounds.height > 0, streamResolution.width > 0, streamResolution.height > 0 else {
            return bounds
        }

        let streamAspectRatio = streamResolution.width / streamResolution.height
        let boundsAspectRatio = bounds.width / bounds.height

        if boundsAspectRatio > streamAspectRatio {
            let width = bounds.height * streamAspectRatio
            return CGRect(x: (bounds.width - width) * 0.5, y: 0, width: width, height: bounds.height)
        } else {
            let height = bounds.width / streamAspectRatio
            return CGRect(x: 0, y: (bounds.height - height) * 0.5, width: bounds.width, height: height)
        }
    }

    func forwardAbsoluteMouseIfNeeded(locationInView: CGPoint, force: Bool) {
        let videoRect = videoRect()
        let isInside = videoRect.contains(locationInView)

        if !isInside && !mouseInsideVideoRegion && !continueAbsoluteDragOutsideVideoRegion {
            return
        }

        if !isInside && !physicallyPressedMouseButtons.isEmpty {
            continueAbsoluteDragOutsideVideoRegion = true
        }

        let clampedX = min(max(locationInView.x, videoRect.minX), videoRect.maxX)
        let clampedY = min(max(locationInView.y, videoRect.minY), videoRect.maxY)

        let normalizedX = videoRect.width > 0 ? (clampedX - videoRect.minX) / videoRect.width : 0
        let normalizedY = videoRect.height > 0 ? (clampedY - videoRect.minY) / videoRect.height : 0

        let streamX = Int32((normalizedX * (streamResolution.width - 1)).rounded())
        let streamY = Int32(((1 - normalizedY) * (streamResolution.height - 1)).rounded())

        if force || isInside || mouseInsideVideoRegion || continueAbsoluteDragOutsideVideoRegion {
            sessionController.sendAbsoluteMouse(
                x: streamX,
                y: streamY,
                referenceWidth: Int32(streamResolution.width),
                referenceHeight: Int32(streamResolution.height)
            )
        }

        mouseInsideVideoRegion = isInside
        updateCursorVisibility()
    }

    func forwardCurrentAbsoluteMousePosition(force: Bool) {
        guard let window else {
            return
        }

        let locationInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        forwardAbsoluteMouseIfNeeded(locationInView: locationInView, force: force)
    }

    func mouseButton(for buttonNumber: Int) -> SessionController.MouseButton? {
        switch buttonNumber {
        case 2:
            return .middle
        case 3:
            return .x1
        case 4:
            return .x2
        default:
            return nil
        }
    }

    func keyboardModifiers(from flags: NSEvent.ModifierFlags) -> SessionController.KeyboardModifiers {
        let deviceFlags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: SessionController.KeyboardModifiers = []

        if deviceFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if deviceFlags.contains(.control) {
            modifiers.insert(.control)
        }
        if deviceFlags.contains(.option) {
            modifiers.insert(.alternate)
        }

        return modifiers
    }

    func modifierKeyIsDown(for keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch Int(keyCode) {
        case kVK_Shift, kVK_RightShift:
            return modifiers.contains(.shift)
        case kVK_Control, kVK_RightControl:
            return modifiers.contains(.control)
        case kVK_Option, kVK_RightOption:
            return modifiers.contains(.option)
        case kVK_CapsLock:
            return modifiers.contains(.capsLock)
        default:
            return false
        }
    }

    func synchronizeRemoteModifierState(with modifiers: NSEvent.ModifierFlags) {
        let currentModifiers = keyboardModifiers(from: modifiers)
        let desiredKeyCodes = physicallyPressedKeyboardInputs.keys.sorted().filter { keyCode in
            physicallyPressedKeyboardInputs[keyCode]?.isModifier == true
        }

        for keyCode in desiredKeyCodes {
            guard let state = physicallyPressedKeyboardInputs[keyCode] else {
                continue
            }

            pressRemoteKeyIfNeeded(state, modifiers: currentModifiers)
        }

        let remoteModifierKeyCodes = remotelyPressedKeyboardInputs.keys.sorted().filter { keyCode in
            remotelyPressedKeyboardInputs[keyCode]?.isModifier == true
        }

        for keyCode in remoteModifierKeyCodes where physicallyPressedKeyboardInputs[keyCode] == nil {
            releaseRemoteKeyIfNeeded(forKeyCode: keyCode, modifiers: currentModifiers)
        }
    }

    private func pressRemoteKeyIfNeeded(
        _ state: PressedKeyState,
        modifiers: SessionController.KeyboardModifiers = []
    ) {
        guard remotelyPressedKeyboardInputs[state.keyCode] == nil else {
            return
        }

        sessionController.sendKeyboard(
            virtualKey: state.virtualKey,
            action: .down,
            modifiers: modifiers,
            flags: state.flags
        )
        remotelyPressedKeyboardInputs[state.keyCode] = state
    }

    func releaseRemoteKeyIfNeeded(
        forKeyCode keyCode: UInt16,
        modifiers: SessionController.KeyboardModifiers = []
    ) {
        guard let state = remotelyPressedKeyboardInputs.removeValue(forKey: keyCode) else {
            return
        }

        sessionController.sendKeyboard(
            virtualKey: state.virtualKey,
            action: .up,
            modifiers: modifiers,
            flags: state.flags
        )
    }

    func scrollAmount(for delta: CGFloat, precise: Bool) -> Int32 {
        _ = precise
        let scaledDelta = delta * 120
        return Int32(scaledDelta.rounded())
    }

    func configureRawMouseObservation() {
        let notificationCenter = NotificationCenter.default
        rawMouseObservers = [
            notificationCenter.addObserver(
                forName: NSNotification.Name.GCMouseDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshRawMouseDevices()
                }
            },
            notificationCenter.addObserver(
                forName: NSNotification.Name.GCMouseDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshRawMouseDevices()
                }
            }
        ]
        refreshRawMouseDevices()
    }

    func tearDownRawMouseObservation() {
        let notificationCenter = NotificationCenter.default
        for observer in rawMouseObservers {
            notificationCenter.removeObserver(observer)
        }
        rawMouseObservers.removeAll()

        for mouse in rawMouseDevices.values {
            mouse.mouseInput?.mouseMovedHandler = nil
        }
        rawMouseDevices.removeAll()
    }

    func refreshRawMouseDevices() {
        let connectedMice = GCMouse.mice()
        let connectedIdentifiers = Set(connectedMice.map { ObjectIdentifier($0) })

        for (identifier, mouse) in rawMouseDevices where connectedIdentifiers.contains(identifier) == false {
            mouse.mouseInput?.mouseMovedHandler = nil
            rawMouseDevices.removeValue(forKey: identifier)
        }

        for mouse in connectedMice {
            let identifier = ObjectIdentifier(mouse)
            guard rawMouseDevices[identifier] == nil else {
                continue
            }

            mouse.handlerQueue = Self.rawMouseQueue
            mouse.mouseInput?.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
                guard let self else {
                    return
                }

                if let (translatedDeltaX, translatedDeltaY) = self.rawMouseDispatchState.translate(
                    deltaX: Double(deltaX),
                    deltaY: Double(deltaY)
                ) {
                    self.sessionController.sendRelativeMouse(deltaX: translatedDeltaX, deltaY: translatedDeltaY)
                }
            }
            rawMouseDevices[identifier] = mouse
        }
    }

    var hasRawMouseDeviceInput: Bool {
        rawMouseDevices.isEmpty == false
    }

    func updateCursorVisibility() {
        guard mouseMode != .raw else {
            if localCursorHiddenByView {
                setLocalCursorHidden(false)
            }
            return
        }

        let shouldHideCursor = window?.isKeyWindow == true && mouseInsideVideoRegion && !suppressRemoteInputForLocalCommand
        setLocalCursorHidden(shouldHideCursor)
    }

    func setLocalCursorHidden(_ hidden: Bool) {
        guard localCursorHiddenByView != hidden else {
            return
        }

        if hidden {
            NSCursor.hide()
        } else {
            NSCursor.unhide()
        }

        localCursorHiddenByView = hidden
    }
}
