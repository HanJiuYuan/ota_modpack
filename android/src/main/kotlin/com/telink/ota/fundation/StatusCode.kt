package com.telink.ota.fundation

/**
 * Kotlin 枚举，保持与 Java `StatusCode` 相同的名称与语义，
 * 以确保 Java 引用（例如 `statusCode.isFailed` 与 `isComplete`）仍然可用。
 */
enum class StatusCode(val code: Int, val desc: String) {
    /** ota success */
    SUCCESS(0x00, "OTA success"),

    /** ota started */
    STARTED(0x01, "OTA started"),

    /** ota stopped when call Device#stopOta(boolean) */
    STOPPED(0x02, "OTA stopped"),

    /** previous ota running when start again */
    BUSY(0x04, "OTA busy"),

    /** previous ota running */
    REBOOTING(0x05, "OTA rebooting"),

    /** ota params err */
    FAIL_PARAMS_ERR(0x10, "OTA fail: params err"),

    /** connection interrupt when ota running */
    FAIL_CONNECTION_INTERRUPT(0x11, "OTA fail: connection interrupt"),

    /** battery check err */
    FAIL_BATTERY_CHECK_ERR(0x12, "OTA fail: battery check err"),

    /** version compare err */
    FAIL_VERSION_COMPARE_ERR(0x13, "OTA fail: version compare err"),

    /** send command err */
    FAIL_PACKET_SENT_ERR(0x14, "OTA fail: packet sent err"),

    /** send command timeout */
    FAIL_PACKET_SENT_TIMEOUT(0x15, "OTA fail: packet sent timeout"),

    /** flow timeout */
    FAIL_FLOW_TIMEOUT(0x16, "OTA fail: flow timeout"),

    /** reconnect err */
    FAIL_RECONNECT_ERR(0x17, "OTA fail: reconnect err"),

    /** not connected */
    FAIL_UNCONNECTED(0x18, "OTA fail: device not connected"),

    /** service not found */
    FAIL_SERVICE_NOT_FOUND(0x19, "OTA fail: service not found"),

    /** characteristic not found */
    FAIL_CHARACTERISTIC_NOT_FOUND(0x1A, "OTA fail: characteristic not found");

    fun isFailed(): Boolean {
        return code >= 0x10
    }

    fun isComplete(): Boolean {
        return isFailed() || this == SUCCESS || this == STOPPED
    }
}

