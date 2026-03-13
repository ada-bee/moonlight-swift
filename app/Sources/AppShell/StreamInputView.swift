import AppKit
import Carbon.HIToolbox
import MoonlightCore

@MainActor
final class StreamInputView: NSView {
    private let sessionController: SessionController
    private let streamResolution: CGSize

    private var trackingArea: NSTrackingArea?
    private var commandKeyActive = false
    private var suppressRemoteInputForLocalCommand = false
    private var mouseInsideVideoRegion = false
    private var continueAbsoluteDragOutsideVideoRegion = false
    private var localCursorHiddenByView = false
    private var pressedMouseButtons: Set<SessionController.MouseButton> = []
    private var pressedKeys: [UInt16: SessionController.KeyboardFlags] = [:]
    private var pressedModifierKeys: Set<UInt16> = []

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

    var isFullscreenPointerCaptureEnabled = false {
        didSet {
            guard oldValue != isFullscreenPointerCaptureEnabled else {
                return
            }

            releaseAllRemoteInputs()
            if isFullscreenPointerCaptureEnabled {
                setLocalCursorHidden(false)
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
        for button in pressedMouseButtons {
            sessionController.sendMouseButton(button, action: .release)
        }
        pressedMouseButtons.removeAll()

        for (virtualKey, flags) in pressedKeys {
            sessionController.sendKeyboard(virtualKey: virtualKey, action: .up, flags: flags)
        }
        pressedKeys.removeAll()

        for virtualKey in pressedModifierKeys {
            sessionController.sendKeyboard(virtualKey: virtualKey, action: .up)
        }
        pressedModifierKeys.removeAll()

        continueAbsoluteDragOutsideVideoRegion = false
        updateLocalCursorVisibility()
    }

    func handleWindowDidResignKey() {
        commandKeyActive = false
        suppressRemoteInputForLocalCommand = false
        releaseAllRemoteInputs()
        mouseInsideVideoRegion = false
        setLocalCursorHidden(false)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        window?.makeFirstResponder(self)
        mouseInsideVideoRegion = videoRect().contains(convert(event.locationInWindow, from: nil))
        if !isFullscreenPointerCaptureEnabled {
            forwardAbsoluteMouseIfNeeded(locationInView: convert(event.locationInWindow, from: nil), force: true)
        }
        updateLocalCursorVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        _ = event
        mouseInsideVideoRegion = false
        if pressedMouseButtons.isEmpty {
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

        if !isFullscreenPointerCaptureEnabled {
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
        guard shouldForwardKeyboard(event) else {
            super.keyDown(with: event)
            return
        }

        guard !event.isARepeat else {
            return
        }

        guard let mapping = WindowsVirtualKeyMap.map(keyCode: event.keyCode) else {
            return
        }

        sessionController.sendKeyboard(
            virtualKey: mapping.virtualKey,
            action: .down,
            modifiers: keyboardModifiers(from: event.modifierFlags),
            flags: mapping.flags
        )
        pressedKeys[mapping.virtualKey] = mapping.flags
    }

    override func keyUp(with event: NSEvent) {
        guard shouldForwardKeyboard(event) else {
            super.keyUp(with: event)
            return
        }

        guard let mapping = WindowsVirtualKeyMap.map(keyCode: event.keyCode) else {
            return
        }

        sessionController.sendKeyboard(
            virtualKey: mapping.virtualKey,
            action: .up,
            modifiers: keyboardModifiers(from: event.modifierFlags),
            flags: mapping.flags
        )
        pressedKeys.removeValue(forKey: mapping.virtualKey)
    }

    override func flagsChanged(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == UInt16(kVK_Command) || event.keyCode == UInt16(kVK_RightCommand) {
            let commandDown = modifiers.contains(.command)
            if commandDown && !commandKeyActive {
                commandKeyActive = true
                suppressRemoteInputForLocalCommand = true
                releaseAllRemoteInputs()
                setLocalCursorHidden(false)
            } else if !commandDown && commandKeyActive {
                commandKeyActive = false
                suppressRemoteInputForLocalCommand = false
                synchronizeModifierState(with: modifiers)
                updateLocalCursorVisibility()
            }
            return
        }

        guard !suppressRemoteInputForLocalCommand else {
            return
        }

        guard let mapping = WindowsVirtualKeyMap.map(keyCode: event.keyCode) else {
            return
        }

        let isDown = modifierKeyIsDown(for: event.keyCode, modifiers: modifiers)
        if isDown {
            if !pressedModifierKeys.contains(mapping.virtualKey) {
                sessionController.sendKeyboard(
                    virtualKey: mapping.virtualKey,
                    action: .down,
                    modifiers: keyboardModifiers(from: modifiers)
                )
                pressedModifierKeys.insert(mapping.virtualKey)
            }
        } else if pressedModifierKeys.contains(mapping.virtualKey) {
            sessionController.sendKeyboard(
                virtualKey: mapping.virtualKey,
                action: .up,
                modifiers: keyboardModifiers(from: modifiers)
            )
            pressedModifierKeys.remove(mapping.virtualKey)
        }
    }
}

private extension StreamInputView {
    func handleMouseMotion(_ event: NSEvent) {
        guard shouldForwardInput(for: event) else {
            return
        }

        if isFullscreenPointerCaptureEnabled {
            let deltaX = Int32(event.deltaX.rounded())
            let deltaY = Int32(event.deltaY.rounded())
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
            if suppressRemoteInputForLocalCommand, action == .press, button == .left, !isFullscreenPointerCaptureEnabled {
                window?.performDrag(with: event)
            }
            return
        }

        let locationInView = convert(event.locationInWindow, from: nil)
        let insideVideo = videoRect().contains(locationInView)

        if !isFullscreenPointerCaptureEnabled && action == .press && !insideVideo {
            return
        }

        sessionController.sendMouseButton(button, action: action)

        switch action {
        case .press:
            pressedMouseButtons.insert(button)
            if !isFullscreenPointerCaptureEnabled {
                forwardAbsoluteMouseIfNeeded(locationInView: locationInView, force: true)
            }
        case .release:
            pressedMouseButtons.remove(button)
            if !isFullscreenPointerCaptureEnabled && pressedMouseButtons.isEmpty {
                continueAbsoluteDragOutsideVideoRegion = false
            }
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
        guard NSApp.isActive, let window, window.isVisible else {
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

        if !isInside && !pressedMouseButtons.isEmpty {
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
        let desiredMappings: [(NSEvent.ModifierFlags, UInt16)] = [
            (.shift, 0xA0),
            (.control, 0xA2),
            (.option, 0xA4),
            (.capsLock, 0x14)
        ]

        for (flag, virtualKey) in desiredMappings {
            let shouldBeDown = modifiers.contains(flag)
            let isDown = pressedModifierKeys.contains(virtualKey)

            if shouldBeDown && !isDown {
                sessionController.sendKeyboard(
                    virtualKey: virtualKey,
                    action: .down,
                    modifiers: keyboardModifiers(from: modifiers)
                )
                pressedModifierKeys.insert(virtualKey)
            } else if !shouldBeDown && isDown {
                sessionController.sendKeyboard(
                    virtualKey: virtualKey,
                    action: .up,
                    modifiers: keyboardModifiers(from: modifiers)
                )
                pressedModifierKeys.remove(virtualKey)
            }
        }
    }

    func scrollAmount(for delta: CGFloat, precise: Bool) -> Int32 {
        if precise {
            return Int32((max(min(delta, 1), -1) * 120).rounded())
        }

        return Int32((delta * 120).rounded())
    }

    func updateLocalCursorVisibility() {
        guard !isFullscreenPointerCaptureEnabled else {
            setLocalCursorHidden(false)
            return
        }

        let shouldHideCursor = mouseInsideVideoRegion && !suppressRemoteInputForLocalCommand
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
