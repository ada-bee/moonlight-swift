import AppKit
import Carbon.HIToolbox
import MoonlightCore

struct WindowsVirtualKeyMap {
    struct Mapping {
        let virtualKey: UInt16
        let flags: SessionController.KeyboardFlags
    }

    static func map(keyCode: UInt16) -> Mapping? {
        let keyCodeValue = Int(keyCode)

        switch keyCodeValue {
        case Int(kVK_ANSI_A):
            return Mapping(virtualKey: 0x41, flags: [])
        case Int(kVK_ANSI_B):
            return Mapping(virtualKey: 0x42, flags: [])
        case Int(kVK_ANSI_C):
            return Mapping(virtualKey: 0x43, flags: [])
        case Int(kVK_ANSI_D):
            return Mapping(virtualKey: 0x44, flags: [])
        case Int(kVK_ANSI_E):
            return Mapping(virtualKey: 0x45, flags: [])
        case Int(kVK_ANSI_F):
            return Mapping(virtualKey: 0x46, flags: [])
        case Int(kVK_ANSI_G):
            return Mapping(virtualKey: 0x47, flags: [])
        case Int(kVK_ANSI_H):
            return Mapping(virtualKey: 0x48, flags: [])
        case Int(kVK_ANSI_I):
            return Mapping(virtualKey: 0x49, flags: [])
        case Int(kVK_ANSI_J):
            return Mapping(virtualKey: 0x4A, flags: [])
        case Int(kVK_ANSI_K):
            return Mapping(virtualKey: 0x4B, flags: [])
        case Int(kVK_ANSI_L):
            return Mapping(virtualKey: 0x4C, flags: [])
        case Int(kVK_ANSI_M):
            return Mapping(virtualKey: 0x4D, flags: [])
        case Int(kVK_ANSI_N):
            return Mapping(virtualKey: 0x4E, flags: [])
        case Int(kVK_ANSI_O):
            return Mapping(virtualKey: 0x4F, flags: [])
        case Int(kVK_ANSI_P):
            return Mapping(virtualKey: 0x50, flags: [])
        case Int(kVK_ANSI_Q):
            return Mapping(virtualKey: 0x51, flags: [])
        case Int(kVK_ANSI_R):
            return Mapping(virtualKey: 0x52, flags: [])
        case Int(kVK_ANSI_S):
            return Mapping(virtualKey: 0x53, flags: [])
        case Int(kVK_ANSI_T):
            return Mapping(virtualKey: 0x54, flags: [])
        case Int(kVK_ANSI_U):
            return Mapping(virtualKey: 0x55, flags: [])
        case Int(kVK_ANSI_V):
            return Mapping(virtualKey: 0x56, flags: [])
        case Int(kVK_ANSI_W):
            return Mapping(virtualKey: 0x57, flags: [])
        case Int(kVK_ANSI_X):
            return Mapping(virtualKey: 0x58, flags: [])
        case Int(kVK_ANSI_Y):
            return Mapping(virtualKey: 0x59, flags: [])
        case Int(kVK_ANSI_Z):
            return Mapping(virtualKey: 0x5A, flags: [])

        case Int(kVK_ANSI_0):
            return Mapping(virtualKey: 0x30, flags: [])
        case Int(kVK_ANSI_1):
            return Mapping(virtualKey: 0x31, flags: [])
        case Int(kVK_ANSI_2):
            return Mapping(virtualKey: 0x32, flags: [])
        case Int(kVK_ANSI_3):
            return Mapping(virtualKey: 0x33, flags: [])
        case Int(kVK_ANSI_4):
            return Mapping(virtualKey: 0x34, flags: [])
        case Int(kVK_ANSI_5):
            return Mapping(virtualKey: 0x35, flags: [])
        case Int(kVK_ANSI_6):
            return Mapping(virtualKey: 0x36, flags: [])
        case Int(kVK_ANSI_7):
            return Mapping(virtualKey: 0x37, flags: [])
        case Int(kVK_ANSI_8):
            return Mapping(virtualKey: 0x38, flags: [])
        case Int(kVK_ANSI_9):
            return Mapping(virtualKey: 0x39, flags: [])

        case Int(kVK_ANSI_Keypad0):
            return Mapping(virtualKey: 0x60, flags: [])
        case Int(kVK_ANSI_Keypad1):
            return Mapping(virtualKey: 0x61, flags: [])
        case Int(kVK_ANSI_Keypad2):
            return Mapping(virtualKey: 0x62, flags: [])
        case Int(kVK_ANSI_Keypad3):
            return Mapping(virtualKey: 0x63, flags: [])
        case Int(kVK_ANSI_Keypad4):
            return Mapping(virtualKey: 0x64, flags: [])
        case Int(kVK_ANSI_Keypad5):
            return Mapping(virtualKey: 0x65, flags: [])
        case Int(kVK_ANSI_Keypad6):
            return Mapping(virtualKey: 0x66, flags: [])
        case Int(kVK_ANSI_Keypad7):
            return Mapping(virtualKey: 0x67, flags: [])
        case Int(kVK_ANSI_Keypad8):
            return Mapping(virtualKey: 0x68, flags: [])
        case Int(kVK_ANSI_Keypad9):
            return Mapping(virtualKey: 0x69, flags: [])

        case Int(kVK_F1):
            return Mapping(virtualKey: 0x70, flags: [])
        case Int(kVK_F2):
            return Mapping(virtualKey: 0x71, flags: [])
        case Int(kVK_F3):
            return Mapping(virtualKey: 0x72, flags: [])
        case Int(kVK_F4):
            return Mapping(virtualKey: 0x73, flags: [])
        case Int(kVK_F5):
            return Mapping(virtualKey: 0x74, flags: [])
        case Int(kVK_F6):
            return Mapping(virtualKey: 0x75, flags: [])
        case Int(kVK_F7):
            return Mapping(virtualKey: 0x76, flags: [])
        case Int(kVK_F8):
            return Mapping(virtualKey: 0x77, flags: [])
        case Int(kVK_F9):
            return Mapping(virtualKey: 0x78, flags: [])
        case Int(kVK_F10):
            return Mapping(virtualKey: 0x79, flags: [])
        case Int(kVK_F11):
            return Mapping(virtualKey: 0x7A, flags: [])
        case Int(kVK_F12):
            return Mapping(virtualKey: 0x7B, flags: [])
        case Int(kVK_F13):
            return Mapping(virtualKey: 0x7C, flags: [])
        case Int(kVK_F14):
            return Mapping(virtualKey: 0x7D, flags: [])
        case Int(kVK_F15):
            return Mapping(virtualKey: 0x7E, flags: [])
        case Int(kVK_F16):
            return Mapping(virtualKey: 0x7F, flags: [])
        case Int(kVK_F17):
            return Mapping(virtualKey: 0x80, flags: [])
        case Int(kVK_F18):
            return Mapping(virtualKey: 0x81, flags: [])
        case Int(kVK_F19):
            return Mapping(virtualKey: 0x82, flags: [])
        case Int(kVK_F20):
            return Mapping(virtualKey: 0x83, flags: [])

        case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
            return Mapping(virtualKey: 0x0D, flags: [])
        case Int(kVK_Tab):
            return Mapping(virtualKey: 0x09, flags: [])
        case Int(kVK_Space):
            return Mapping(virtualKey: 0x20, flags: [])
        case Int(kVK_Delete):
            return Mapping(virtualKey: 0x08, flags: [])
        case Int(kVK_Escape):
            return Mapping(virtualKey: 0x1B, flags: [])
        case Int(kVK_CapsLock):
            return Mapping(virtualKey: 0x14, flags: [])
        case Int(kVK_Help):
            return Mapping(virtualKey: 0x2D, flags: [])
        case Int(kVK_Home):
            return Mapping(virtualKey: 0x24, flags: [])
        case Int(kVK_PageUp):
            return Mapping(virtualKey: 0x21, flags: [])
        case Int(kVK_ForwardDelete):
            return Mapping(virtualKey: 0x2E, flags: [])
        case Int(kVK_End):
            return Mapping(virtualKey: 0x23, flags: [])
        case Int(kVK_PageDown):
            return Mapping(virtualKey: 0x22, flags: [])
        case Int(kVK_LeftArrow):
            return Mapping(virtualKey: 0x25, flags: [])
        case Int(kVK_RightArrow):
            return Mapping(virtualKey: 0x27, flags: [])
        case Int(kVK_DownArrow):
            return Mapping(virtualKey: 0x28, flags: [])
        case Int(kVK_UpArrow):
            return Mapping(virtualKey: 0x26, flags: [])
        case Int(kVK_ANSI_Minus):
            return Mapping(virtualKey: 0xBD, flags: [])
        case Int(kVK_ANSI_Equal):
            return Mapping(virtualKey: 0xBB, flags: [])
        case Int(kVK_ANSI_LeftBracket):
            return Mapping(virtualKey: 0xDB, flags: [])
        case Int(kVK_ANSI_RightBracket):
            return Mapping(virtualKey: 0xDD, flags: [])
        case Int(kVK_ANSI_Backslash):
            return Mapping(virtualKey: 0xDC, flags: [])
        case Int(kVK_ANSI_Semicolon):
            return Mapping(virtualKey: 0xBA, flags: [])
        case Int(kVK_ANSI_Quote):
            return Mapping(virtualKey: 0xDE, flags: [])
        case Int(kVK_ANSI_Grave):
            return Mapping(virtualKey: 0xC0, flags: [])
        case Int(kVK_ANSI_Comma):
            return Mapping(virtualKey: 0xBC, flags: [])
        case Int(kVK_ANSI_Period):
            return Mapping(virtualKey: 0xBE, flags: [])
        case Int(kVK_ANSI_Slash):
            return Mapping(virtualKey: 0xBF, flags: [])
        case Int(kVK_ANSI_KeypadDecimal):
            return Mapping(virtualKey: 0x6E, flags: [])
        case Int(kVK_ANSI_KeypadMultiply):
            return Mapping(virtualKey: 0x6A, flags: [])
        case Int(kVK_ANSI_KeypadPlus):
            return Mapping(virtualKey: 0x6B, flags: [])
        case Int(kVK_ANSI_KeypadClear):
            return Mapping(virtualKey: 0x90, flags: [])
        case Int(kVK_ANSI_KeypadDivide):
            return Mapping(virtualKey: 0x6F, flags: [])
        case Int(kVK_ANSI_KeypadMinus):
            return Mapping(virtualKey: 0x6D, flags: [])
        case Int(kVK_ANSI_KeypadEquals):
            return Mapping(virtualKey: 0xBB, flags: [])
        case Int(kVK_Shift):
            return Mapping(virtualKey: 0xA0, flags: [])
        case Int(kVK_RightShift):
            return Mapping(virtualKey: 0xA1, flags: [])
        case Int(kVK_Control):
            return Mapping(virtualKey: 0xA2, flags: [])
        case Int(kVK_RightControl):
            return Mapping(virtualKey: 0xA3, flags: [])
        case Int(kVK_Option):
            return Mapping(virtualKey: 0xA4, flags: [])
        case Int(kVK_RightOption):
            return Mapping(virtualKey: 0xA5, flags: [])
        case Int(kVK_Command):
            return Mapping(virtualKey: 0x5B, flags: [])
        case Int(kVK_RightCommand):
            return Mapping(virtualKey: 0x5C, flags: [])
        case Int(kVK_Function):
            return Mapping(virtualKey: 0xFF, flags: [])
        case Int(kVK_ISO_Section):
            return Mapping(virtualKey: 0xE2, flags: [.nonNormalized])
        default:
            return nil
        }
    }
}
