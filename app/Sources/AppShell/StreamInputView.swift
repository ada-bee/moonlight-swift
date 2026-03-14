import AppKit
import Carbon.HIToolbox
import MoonlightCore

@MainActor
final class StreamInputView: NSView {
    enum MouseMode {
        case absolute
        case raw
    }

    private struct PressedKeyState {
        let virtualKey: UInt16
        let flags: SessionController.KeyboardFlags

        init(mapping: WindowsVirtualKeyMap.Mapping) {
            self.virtualKey = mapping.virtualKey
            self.flags = mapping.flags
        }
    }

    private let sessionController: SessionController
    private let streamResolution: CGSize

    private var trackingArea: NSTrackingArea?
    private var commandKeyActive = false
    private var suppressRemoteInputForLocalCommand = false
    private var mouseInsideVideoRegion = false
    private var continueAbsoluteDragOutsideVideoRegion = false
    private var mouseCaptureActive = false
    private var localCursorHiddenByView = false
    private var physicallyPressedMouseButtons: Set<SessionController.MouseButton> = []
    private var remotelyPressedMouseButtons: Set<SessionController.MouseButton> = []
    private var physicallyPressedKeys: [UInt16: PressedKeyState] = [:]
    private var remotelyPressedKeys: [UInt16: PressedKeyState] = [:]
    private var physicallyPressedModifierKeys: [UInt16: UInt16] = [:]
    private var remotelyPressedModifierKeys: [UInt16: UInt16] = [:]

    var onLocalCommandSuppressionChanged: ((Bool) -> Void)?

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

    var mouseMode: MouseMode = .absolute {
        didSet {
            guard oldValue != mouseMode else {
                return
            }

            releaseAllRemoteInputs()
            if mouseMode == .raw {
                setLocalCursorHidden(false)
            } else {
                updateLocalCursorVisibility()
            }
        }
    }

    var isMouseCaptureActive = false {
        didSet {
            guard oldValue != isMouseCaptureActive else {
                return
            }

            mouseCaptureActive = isMouseCaptureActive
            if !isMouseCaptureActive {
                releaseAllRemoteInputs()
            } else {
                updateLocalCursorVisibility()
            }
        }
    }

    init(sessionController: SessionController) {
        self.sessionController = sessionController
        let resolution = sessionController.configuration.video.resolution
        self.streamResolution = CGSize(width: resolution.width, height: resolution.height)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
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

    func releaseAllRemoteInputs() {
        releaseRemoteInputsOnly()
        clearLocalBookkeepingOnly()
    }

    func resetLocalInputState() {
        clearLocalBookkeepingOnly()
        mouseInsideVideoRegion = false
        setLocalCursorHidden(false)
    }

    func handleWindowDidResignKey() {
        releaseAllRemoteInputs()
        mouseInsideVideoRegion = false
        setLocalCursorHidden(false)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        window?.makeFirstResponder(self)
        mouseInsideVideoRegion = videoRect().contains(convert(event.locationInWindow, from: nil))
        if mouseMode == .absolute {
            forwardAbsoluteMouseIfNeeded(locationInView: convert(event.locationInWindow, from: nil), force: true)
        }
        updateLocalCursorVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        _ = event
        mouseInsideVideoRegion = false
        if physicallyPressedMouseButtons.isEmpty {
            continueAbsoluteDragOutsideVideoRegion = false
        }
        updateLocalCursorVisibility()
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
        let shouldForward = shouldForwardKeyboard(event)

        guard let mapping = WindowsVirtualKeyMap.map(keyCode: event.keyCode) else {
            if !shouldForward {
                super.keyDown(with: event)
            }
            return
        }

        if !event.isARepeat {
            physicallyPressedKeys[event.keyCode] = PressedKeyState(mapping: mapping)
        }

        guard shouldForward else {
            super.keyDown(with: event)
            return
        }

        guard !event.isARepeat else {
            return
        }

        let state = PressedKeyState(mapping: mapping)
        guard remotelyPressedKeys[event.keyCode] == nil else {
            return
        }

        sessionController.sendKeyboard(
            virtualKey: state.virtualKey,
            action: .down,
            modifiers: keyboardModifiers(from: event.modifierFlags),
            flags: state.flags
        )
        remotelyPressedKeys[event.keyCode] = state
    }

    override func keyUp(with event: NSEvent) {
        let shouldForward = shouldForwardKeyboard(event)
        let state = physicallyPressedKeys.removeValue(forKey: event.keyCode) ?? WindowsVirtualKeyMap.map(keyCode: event.keyCode).map(PressedKeyState.init)

        guard shouldForward else {
            super.keyUp(with: event)
            return
        }

        guard let state else {
            return
        }

        guard remotelyPressedKeys.removeValue(forKey: event.keyCode) != nil else {
            return
        }

        sessionController.sendKeyboard(
            virtualKey: state.virtualKey,
            action: .up,
            modifiers: keyboardModifiers(from: event.modifierFlags),
            flags: state.flags
        )
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

        guard let mapping = WindowsVirtualKeyMap.map(keyCode: event.keyCode) else {
            return
        }

        let isDown = modifierKeyIsDown(for: event.keyCode, modifiers: modifiers)
        if isDown {
            physicallyPressedModifierKeys[event.keyCode] = mapping.virtualKey
        } else {
            physicallyPressedModifierKeys.removeValue(forKey: event.keyCode)
        }

        guard !suppressRemoteInputForLocalCommand else {
            return
        }

        if isDown {
            if remotelyPressedModifierKeys[event.keyCode] == nil {
                sessionController.sendKeyboard(
                    virtualKey: mapping.virtualKey,
                    action: .down,
                    modifiers: keyboardModifiers(from: modifiers)
                )
                remotelyPressedModifierKeys[event.keyCode] = mapping.virtualKey
            }
        } else if let virtualKey = remotelyPressedModifierKeys.removeValue(forKey: event.keyCode) {
            sessionController.sendKeyboard(
                virtualKey: virtualKey,
                action: .up,
                modifiers: keyboardModifiers(from: modifiers)
            )
        }
    }
}

private extension StreamInputView {
    func setSuppressRemoteInputForLocalCommand(_ isSuppressed: Bool) {
        guard suppressRemoteInputForLocalCommand != isSuppressed else {
            return
        }

        suppressRemoteInputForLocalCommand = isSuppressed
        onLocalCommandSuppressionChanged?(isSuppressed)
    }

    func beginLocalCommandSuppression() {
        commandKeyActive = true
        setSuppressRemoteInputForLocalCommand(true)
        releaseRemoteInputsOnly()
        setLocalCursorHidden(false)
    }

    func endLocalCommandSuppression(with modifiers: NSEvent.ModifierFlags) {
        commandKeyActive = false
        setSuppressRemoteInputForLocalCommand(false)
        synchronizeModifierState(with: modifiers)
        resynchronizeCurrentlyHeldInputs(with: modifiers)
        updateLocalCursorVisibility()
    }

    func releaseRemoteInputsOnly() {
        for button in remotelyPressedMouseButtons {
            sessionController.sendMouseButton(button, action: .release)
        }
        remotelyPressedMouseButtons.removeAll()

        for state in remotelyPressedKeys.values {
            sessionController.sendKeyboard(virtualKey: state.virtualKey, action: .up, flags: state.flags)
        }
        remotelyPressedKeys.removeAll()

        for virtualKey in remotelyPressedModifierKeys.values {
            sessionController.sendKeyboard(virtualKey: virtualKey, action: .up)
        }
        remotelyPressedModifierKeys.removeAll()

        updateLocalCursorVisibility()
    }

    func clearLocalBookkeepingOnly() {
        commandKeyActive = false
        setSuppressRemoteInputForLocalCommand(false)
        physicallyPressedMouseButtons.removeAll()
        remotelyPressedMouseButtons.removeAll()
        physicallyPressedKeys.removeAll()
        remotelyPressedKeys.removeAll()
        physicallyPressedModifierKeys.removeAll()
        remotelyPressedModifierKeys.removeAll()
        continueAbsoluteDragOutsideVideoRegion = false
        updateLocalCursorVisibility()
    }

    func resynchronizeCurrentlyHeldInputs(with modifiers: NSEvent.ModifierFlags) {
        let currentModifiers = keyboardModifiers(from: modifiers)

        for keyCode in physicallyPressedKeys.keys.sorted() {
            guard let state = physicallyPressedKeys[keyCode], remotelyPressedKeys[keyCode] == nil else {
                continue
            }

            sessionController.sendKeyboard(
                virtualKey: state.virtualKey,
                action: .down,
                modifiers: currentModifiers,
                flags: state.flags
            )
            remotelyPressedKeys[keyCode] = state
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

            let deltaX = Int32(rawRelativeMouseDeltaX(for: event))
            let deltaY = Int32(rawRelativeMouseDeltaY(for: event))
            if deltaX != 0 || deltaY != 0 {
                sessionController.sendRelativeMouse(deltaX: deltaX, deltaY: deltaY)
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
        updateLocalCursorVisibility()
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

    func synchronizeModifierState(with modifiers: NSEvent.ModifierFlags) {
        let currentModifiers = keyboardModifiers(from: modifiers)
        let desiredKeyCodes = physicallyPressedModifierKeys.keys.sorted()

        for keyCode in desiredKeyCodes {
            guard let virtualKey = physicallyPressedModifierKeys[keyCode], remotelyPressedModifierKeys[keyCode] == nil else {
                continue
            }

            sessionController.sendKeyboard(
                virtualKey: virtualKey,
                action: .down,
                modifiers: currentModifiers
            )
            remotelyPressedModifierKeys[keyCode] = virtualKey
        }

        for keyCode in remotelyPressedModifierKeys.keys.sorted() where physicallyPressedModifierKeys[keyCode] == nil {
            guard let virtualKey = remotelyPressedModifierKeys[keyCode] else {
                continue
            }

            sessionController.sendKeyboard(
                virtualKey: virtualKey,
                action: .up,
                modifiers: currentModifiers
            )
            remotelyPressedModifierKeys.removeValue(forKey: keyCode)
        }
    }

    func scrollAmount(for delta: CGFloat, precise: Bool) -> Int32 {
        _ = precise
        let scaledDelta = delta * 120
        return Int32(scaledDelta.rounded())
    }

    func rawRelativeMouseDeltaX(for event: NSEvent) -> Int64 {
        if let cgEvent = event.cgEvent {
            return cgEvent.getIntegerValueField(.mouseEventDeltaX)
        }

        return Int64(event.deltaX.rounded())
    }

    func rawRelativeMouseDeltaY(for event: NSEvent) -> Int64 {
        if let cgEvent = event.cgEvent {
            return cgEvent.getIntegerValueField(.mouseEventDeltaY)
        }

        return Int64(event.deltaY.rounded())
    }

    func updateLocalCursorVisibility() {
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
