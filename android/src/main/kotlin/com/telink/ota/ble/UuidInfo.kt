package com.telink.ota.ble

import java.util.UUID

/**
 * Kotlin 等价实现，提供与 Java 相同的静态 UUID 常量。
 */
object UuidInfo {
    @JvmField
    val OTA_SERVICE_UUID: UUID = UUID.fromString("00010203-0405-0607-0809-0a0b0c0d1912")

    @JvmField
    val OTA_CHARACTERISTIC_UUID: UUID = UUID.fromString("00010203-0405-0607-0809-0a0b0c0d2b12")

    @JvmField
    val VERSION_SERVICE_UUID: UUID = UUID.fromString("0000d0ff-3c17-d293-8e48-14fe2e4da212")

    @JvmField
    val VERSION_CHARACTERISTIC_UUID: UUID = UUID.fromString("0000ffd4-0000-1000-8000-00805f9b34fb")

    @JvmField
    val BATTERY_SERVICE_UUID: UUID = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb")

    @JvmField
    val BATTERY_LEVEL_CHARACTERISTIC_UUID: UUID = UUID.fromString("00002A19-0000-1000-8000-00805f9b34fb")
}

