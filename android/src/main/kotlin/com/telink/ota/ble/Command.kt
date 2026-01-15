package com.telink.ota.ble

import com.telink.ota.util.Arrays
import java.util.UUID

/**
 * Kotlin 等价实现，保持与 Java 版本 `Command` 的字段与构造签名一致，
 * 确保 Java 代码可以互操作（包括无参/多参构造）。
 */
class Command {

    var serviceUUID: UUID? = null
    var characteristicUUID: UUID? = null
    var descriptorUUID: UUID? = null
    var type: CommandType = CommandType.WRITE
    var data: ByteArray? = null
    var tag: Any? = null
    var delay: Int = 0

    constructor() : this(null, null, CommandType.WRITE)

    constructor(serviceUUID: UUID?, characteristicUUID: UUID?, type: CommandType) : this(serviceUUID, characteristicUUID, type, null)

    constructor(serviceUUID: UUID?, characteristicUUID: UUID?, type: CommandType, data: ByteArray?) : this(serviceUUID, characteristicUUID, type, data, null)

    constructor(serviceUUID: UUID?, characteristicUUID: UUID?, type: CommandType, data: ByteArray?, tag: Any?) {
        this.serviceUUID = serviceUUID
        this.characteristicUUID = characteristicUUID
        this.type = type
        this.data = data
        this.tag = tag
    }

    fun clear() {
        this.serviceUUID = null
        this.characteristicUUID = null
        this.descriptorUUID = null
        this.data = null
    }

    override fun toString(): String {
        var d = ""
        val bytes = data
        if (bytes != null) {
            d = Arrays.bytesToHexString(bytes, ",")
        }
        return "{ tag : ${this.tag}, type : ${this.type} CHARACTERISTIC_UUID :" +
            (characteristicUUID?.toString() ?: "null") + " data: " + d + " delay :" + delay + "}"
    }

    enum class CommandType {
        READ, READ_DESCRIPTOR, WRITE, WRITE_NO_RESPONSE, ENABLE_NOTIFY, DISABLE_NOTIFY
    }

    interface Callback {
        fun success(peripheral: Peripheral, command: Command, obj: Any?)
        fun error(peripheral: Peripheral, command: Command, errorMsg: String)
        fun timeout(peripheral: Peripheral, command: Command): Boolean
    }

    companion object {
        @JvmStatic
        fun newInstance(): Command {
            return Command()
        }
    }
}

