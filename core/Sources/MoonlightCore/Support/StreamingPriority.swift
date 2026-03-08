import Darwin
import Foundation

enum StreamingPriority {
    static func promoteCurrentThreadForRenderWork() {
        _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
    }

    static func promoteCurrentThreadForConnectionCallbacks() {
        _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0)
    }

    static func promoteCurrentThreadForVideoCallbacks() {
        _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
    }
}
