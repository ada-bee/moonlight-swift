import AppKit
import Carbon.HIToolbox
import MoonlightCore

struct WindowsVirtualKeyMap {
    struct Mapping {
        let keyCode: UInt16
        let virtualKey: UInt16
        let flags: SessionController.KeyboardFlags
        let isModifier: Bool
    }

    private static func mapping(
        keyCode: UInt16,
        virtualKey: UInt16,
        flags: SessionController.KeyboardFlags = [],
        isModifier: Bool = false
    ) -> Mapping {
        Mapping(keyCode: keyCode, virtualKey: virtualKey, flags: flags, isModifier: isModifier)
    }

    static func map(keyCode: UInt16) -> Mapping? {
        let keyCodeValue = Int(keyCode)

        switch keyCodeValue {
        case Int(kVK_ANSI_A):
            return mapping(keyCode: keyCode, virtualKey: 0x41)
        case Int(kVK_ANSI_B):
            return mapping(keyCode: keyCode, virtualKey: 0x42)
        case Int(kVK_ANSI_C):
            return mapping(keyCode: keyCode, virtualKey: 0x43)
        case Int(kVK_ANSI_D):
            return mapping(keyCode: keyCode, virtualKey: 0x44)
        case Int(kVK_ANSI_E):
            return mapping(keyCode: keyCode, virtualKey: 0x45)
        case Int(kVK_ANSI_F):
            return mapping(keyCode: keyCode, virtualKey: 0x46)
        case Int(kVK_ANSI_G):
            return mapping(keyCode: keyCode, virtualKey: 0x47)
        case Int(kVK_ANSI_H):
            return mapping(keyCode: keyCode, virtualKey: 0x48)
        case Int(kVK_ANSI_I):
            return mapping(keyCode: keyCode, virtualKey: 0x49)
        case Int(kVK_ANSI_J):
            return mapping(keyCode: keyCode, virtualKey: 0x4A)
        case Int(kVK_ANSI_K):
            return mapping(keyCode: keyCode, virtualKey: 0x4B)
        case Int(kVK_ANSI_L):
            return mapping(keyCode: keyCode, virtualKey: 0x4C)
        case Int(kVK_ANSI_M):
            return mapping(keyCode: keyCode, virtualKey: 0x4D)
        case Int(kVK_ANSI_N):
            return mapping(keyCode: keyCode, virtualKey: 0x4E)
        case Int(kVK_ANSI_O):
            return mapping(keyCode: keyCode, virtualKey: 0x4F)
        case Int(kVK_ANSI_P):
            return mapping(keyCode: keyCode, virtualKey: 0x50)
        case Int(kVK_ANSI_Q):
            return mapping(keyCode: keyCode, virtualKey: 0x51)
        case Int(kVK_ANSI_R):
            return mapping(keyCode: keyCode, virtualKey: 0x52)
        case Int(kVK_ANSI_S):
            return mapping(keyCode: keyCode, virtualKey: 0x53)
        case Int(kVK_ANSI_T):
            return mapping(keyCode: keyCode, virtualKey: 0x54)
        case Int(kVK_ANSI_U):
            return mapping(keyCode: keyCode, virtualKey: 0x55)
        case Int(kVK_ANSI_V):
            return mapping(keyCode: keyCode, virtualKey: 0x56)
        case Int(kVK_ANSI_W):
            return mapping(keyCode: keyCode, virtualKey: 0x57)
        case Int(kVK_ANSI_X):
            return mapping(keyCode: keyCode, virtualKey: 0x58)
        case Int(kVK_ANSI_Y):
            return mapping(keyCode: keyCode, virtualKey: 0x59)
        case Int(kVK_ANSI_Z):
            return mapping(keyCode: keyCode, virtualKey: 0x5A)

        case Int(kVK_ANSI_0):
            return mapping(keyCode: keyCode, virtualKey: 0x30)
        case Int(kVK_ANSI_1):
            return mapping(keyCode: keyCode, virtualKey: 0x31)
        case Int(kVK_ANSI_2):
            return mapping(keyCode: keyCode, virtualKey: 0x32)
        case Int(kVK_ANSI_3):
            return mapping(keyCode: keyCode, virtualKey: 0x33)
        case Int(kVK_ANSI_4):
            return mapping(keyCode: keyCode, virtualKey: 0x34)
        case Int(kVK_ANSI_5):
            return mapping(keyCode: keyCode, virtualKey: 0x35)
        case Int(kVK_ANSI_6):
            return mapping(keyCode: keyCode, virtualKey: 0x36)
        case Int(kVK_ANSI_7):
            return mapping(keyCode: keyCode, virtualKey: 0x37)
        case Int(kVK_ANSI_8):
            return mapping(keyCode: keyCode, virtualKey: 0x38)
        case Int(kVK_ANSI_9):
            return mapping(keyCode: keyCode, virtualKey: 0x39)

        case Int(kVK_ANSI_Keypad0):
            return mapping(keyCode: keyCode, virtualKey: 0x60)
        case Int(kVK_ANSI_Keypad1):
            return mapping(keyCode: keyCode, virtualKey: 0x61)
        case Int(kVK_ANSI_Keypad2):
            return mapping(keyCode: keyCode, virtualKey: 0x62)
        case Int(kVK_ANSI_Keypad3):
            return mapping(keyCode: keyCode, virtualKey: 0x63)
        case Int(kVK_ANSI_Keypad4):
            return mapping(keyCode: keyCode, virtualKey: 0x64)
        case Int(kVK_ANSI_Keypad5):
            return mapping(keyCode: keyCode, virtualKey: 0x65)
        case Int(kVK_ANSI_Keypad6):
            return mapping(keyCode: keyCode, virtualKey: 0x66)
        case Int(kVK_ANSI_Keypad7):
            return mapping(keyCode: keyCode, virtualKey: 0x67)
        case Int(kVK_ANSI_Keypad8):
            return mapping(keyCode: keyCode, virtualKey: 0x68)
        case Int(kVK_ANSI_Keypad9):
            return mapping(keyCode: keyCode, virtualKey: 0x69)

        case Int(kVK_F1):
            return mapping(keyCode: keyCode, virtualKey: 0x70)
        case Int(kVK_F2):
            return mapping(keyCode: keyCode, virtualKey: 0x71)
        case Int(kVK_F3):
            return mapping(keyCode: keyCode, virtualKey: 0x72)
        case Int(kVK_F4):
            return mapping(keyCode: keyCode, virtualKey: 0x73)
        case Int(kVK_F5):
            return mapping(keyCode: keyCode, virtualKey: 0x74)
        case Int(kVK_F6):
            return mapping(keyCode: keyCode, virtualKey: 0x75)
        case Int(kVK_F7):
            return mapping(keyCode: keyCode, virtualKey: 0x76)
        case Int(kVK_F8):
            return mapping(keyCode: keyCode, virtualKey: 0x77)
        case Int(kVK_F9):
            return mapping(keyCode: keyCode, virtualKey: 0x78)
        case Int(kVK_F10):
            return mapping(keyCode: keyCode, virtualKey: 0x79)
        case Int(kVK_F11):
            return mapping(keyCode: keyCode, virtualKey: 0x7A)
        case Int(kVK_F12):
            return mapping(keyCode: keyCode, virtualKey: 0x7B)
        case Int(kVK_F13):
            return mapping(keyCode: keyCode, virtualKey: 0x7C)
        case Int(kVK_F14):
            return mapping(keyCode: keyCode, virtualKey: 0x7D)
        case Int(kVK_F15):
            return mapping(keyCode: keyCode, virtualKey: 0x7E)
        case Int(kVK_F16):
            return mapping(keyCode: keyCode, virtualKey: 0x7F)
        case Int(kVK_F17):
            return mapping(keyCode: keyCode, virtualKey: 0x80)
        case Int(kVK_F18):
            return mapping(keyCode: keyCode, virtualKey: 0x81)
        case Int(kVK_F19):
            return mapping(keyCode: keyCode, virtualKey: 0x82)
        case Int(kVK_F20):
            return mapping(keyCode: keyCode, virtualKey: 0x83)

        case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
            return mapping(keyCode: keyCode, virtualKey: 0x0D)
        case Int(kVK_Tab):
            return mapping(keyCode: keyCode, virtualKey: 0x09)
        case Int(kVK_Space):
            return mapping(keyCode: keyCode, virtualKey: 0x20)
        case Int(kVK_Delete):
            return mapping(keyCode: keyCode, virtualKey: 0x08)
        case Int(kVK_Escape):
            return mapping(keyCode: keyCode, virtualKey: 0x1B)
        case Int(kVK_CapsLock):
            return mapping(keyCode: keyCode, virtualKey: 0x14, isModifier: true)
        case Int(kVK_Help):
            return mapping(keyCode: keyCode, virtualKey: 0x2D)
        case Int(kVK_Home):
            return mapping(keyCode: keyCode, virtualKey: 0x24)
        case Int(kVK_PageUp):
            return mapping(keyCode: keyCode, virtualKey: 0x21)
        case Int(kVK_ForwardDelete):
            return mapping(keyCode: keyCode, virtualKey: 0x2E)
        case Int(kVK_End):
            return mapping(keyCode: keyCode, virtualKey: 0x23)
        case Int(kVK_PageDown):
            return mapping(keyCode: keyCode, virtualKey: 0x22)
        case Int(kVK_LeftArrow):
            return mapping(keyCode: keyCode, virtualKey: 0x25)
        case Int(kVK_RightArrow):
            return mapping(keyCode: keyCode, virtualKey: 0x27)
        case Int(kVK_DownArrow):
            return mapping(keyCode: keyCode, virtualKey: 0x28)
        case Int(kVK_UpArrow):
            return mapping(keyCode: keyCode, virtualKey: 0x26)
        case Int(kVK_ANSI_Minus):
            return mapping(keyCode: keyCode, virtualKey: 0xBD)
        case Int(kVK_ANSI_Equal):
            return mapping(keyCode: keyCode, virtualKey: 0xBB)
        case Int(kVK_ANSI_LeftBracket):
            return mapping(keyCode: keyCode, virtualKey: 0xDB)
        case Int(kVK_ANSI_RightBracket):
            return mapping(keyCode: keyCode, virtualKey: 0xDD)
        case Int(kVK_ANSI_Backslash):
            return mapping(keyCode: keyCode, virtualKey: 0xDC)
        case Int(kVK_ANSI_Semicolon):
            return mapping(keyCode: keyCode, virtualKey: 0xBA)
        case Int(kVK_ANSI_Quote):
            return mapping(keyCode: keyCode, virtualKey: 0xDE)
        case Int(kVK_ANSI_Grave):
            return mapping(keyCode: keyCode, virtualKey: 0xC0)
        case Int(kVK_ANSI_Comma):
            return mapping(keyCode: keyCode, virtualKey: 0xBC)
        case Int(kVK_ANSI_Period):
            return mapping(keyCode: keyCode, virtualKey: 0xBE)
        case Int(kVK_ANSI_Slash):
            return mapping(keyCode: keyCode, virtualKey: 0xBF)
        case Int(kVK_ANSI_KeypadDecimal):
            return mapping(keyCode: keyCode, virtualKey: 0x6E)
        case Int(kVK_ANSI_KeypadMultiply):
            return mapping(keyCode: keyCode, virtualKey: 0x6A)
        case Int(kVK_ANSI_KeypadPlus):
            return mapping(keyCode: keyCode, virtualKey: 0x6B)
        case Int(kVK_ANSI_KeypadClear):
            return mapping(keyCode: keyCode, virtualKey: 0x90)
        case Int(kVK_ANSI_KeypadDivide):
            return mapping(keyCode: keyCode, virtualKey: 0x6F)
        case Int(kVK_ANSI_KeypadMinus):
            return mapping(keyCode: keyCode, virtualKey: 0x6D)
        case Int(kVK_ANSI_KeypadEquals):
            return mapping(keyCode: keyCode, virtualKey: 0xBB)
        case Int(kVK_Shift):
            return mapping(keyCode: keyCode, virtualKey: 0xA0, isModifier: true)
        case Int(kVK_RightShift):
            return mapping(keyCode: keyCode, virtualKey: 0xA1, isModifier: true)
        case Int(kVK_Control):
            return mapping(keyCode: keyCode, virtualKey: 0xA2, isModifier: true)
        case Int(kVK_RightControl):
            return mapping(keyCode: keyCode, virtualKey: 0xA3, isModifier: true)
        case Int(kVK_Option):
            return mapping(keyCode: keyCode, virtualKey: 0xA4, isModifier: true)
        case Int(kVK_RightOption):
            return mapping(keyCode: keyCode, virtualKey: 0xA5, isModifier: true)
        case Int(kVK_Command):
            return mapping(keyCode: keyCode, virtualKey: 0x5B, isModifier: true)
        case Int(kVK_RightCommand):
            return mapping(keyCode: keyCode, virtualKey: 0x5C, isModifier: true)
        case Int(kVK_Function):
            return mapping(keyCode: keyCode, virtualKey: 0xFF)
        case Int(kVK_ISO_Section):
            return mapping(keyCode: keyCode, virtualKey: 0xE2, flags: [.nonNormalized])
        default:
            return nil
        }
    }
}
