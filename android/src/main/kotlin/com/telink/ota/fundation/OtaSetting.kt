package com.telink.ota.fundation

import java.util.UUID

/**
 * Kotlin 等价实现，保持与原 Java `OtaSetting` 的字段与方法签名一致，
 * 以确保现有 Java 代码（如 `Device`、`Peripheral`）可直接互操作。
 */
class OtaSetting {

    private var firmwareData: ByteArray? = null

    private var serviceUUID: UUID? = null

    private var characteristicUUID: UUID? = null

    /**
     * 读取间隔：每写入 [x] 个分组后进行一次读取校验
     * 若值 <= 0，则不发送读取校验
     */
    private var readInterval: Int = 8

    /**
     * 默认 5 分钟
     */
    private var otaTimeout: Int = 5 * 60 * 1000

    // 断点续传：从指定分包索引继续（可选）
    private var resumeFromPacketIndex: Int? = null

    fun getFirmwareData(): ByteArray? {
        return firmwareData
    }

    fun setFirmwareData(firmwareData: ByteArray?) {
        this.firmwareData = firmwareData
    }

    fun getServiceUUID(): UUID? {
        return serviceUUID
    }

    fun setServiceUUID(serviceUUID: UUID?) {
        this.serviceUUID = serviceUUID
    }

    fun getCharacteristicUUID(): UUID? {
        return characteristicUUID
    }

    fun setCharacteristicUUID(characteristicUUID: UUID?) {
        this.characteristicUUID = characteristicUUID
    }

    fun getReadInterval(): Int {
        return readInterval
    }

    fun setReadInterval(readInterval: Int) {
        this.readInterval = readInterval
    }

    fun getOtaTimeout(): Int {
        return otaTimeout
    }

    fun setOtaTimeout(otaTimeout: Int) {
        this.otaTimeout = otaTimeout
    }

    fun getResumeFromPacketIndex(): Int? {
        return resumeFromPacketIndex
    }

    fun setResumeFromPacketIndex(index: Int?) {
        this.resumeFromPacketIndex = index
    }
}

