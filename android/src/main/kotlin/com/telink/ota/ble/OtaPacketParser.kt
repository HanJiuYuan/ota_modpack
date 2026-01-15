package com.telink.ota.ble

import com.telink.ota.util.Arrays
import com.telink.ota.util.OtaLogger
import kotlin.math.floor

class OtaPacketParser {

    private var total: Int = 0
    private var index: Int = -1
    private var data: ByteArray? = null
    private var progress: Int = 0

    fun set(data: ByteArray) {
        clear()
        this.data = data
        val length = data.size
        val size = 16
        total = if (length % size == 0) {
            length / size
        } else {
            floor(length / size.toDouble() + 1).toInt()
        }
    }

    fun clear() {
        this.progress = 0
        this.total = 0
        this.index = -1
        this.data = null
    }

    fun getTotal(): Int {
        return this.total
    }

    fun setStartIndex(startIndex: Int) {
        val d = data ?: return
        if (startIndex < 0) return
        if (total <= 0) return
        val clamped = if (startIndex >= total) total - 1 else startIndex
        // 设置为上一个索引，这样下一包就是 startIndex
        this.index = clamped - 1
        // 预估进度
        val a = this.getNextPacketIndex().toFloat()
        val b = this.total.toFloat()
        this.progress = kotlin.math.floor(a / b * 100f).toInt()
    }

    fun getFirmwareVersion(): ByteArray? {
        val d = data ?: return null
        if (d.size < 6) return null
        val version = ByteArray(4)
        System.arraycopy(d, 2, version, 0, 4)
        return version
    }

    fun hasNextPacket(): Boolean {
        return this.total > 0 && (this.index + 1) < this.total
    }

    fun isLast(): Boolean {
        return (this.index + 1) == this.total
    }

    fun getNextPacketIndex(): Int {
        return this.index + 1
    }

    fun getNextPacket(): ByteArray {
        val nextIndex = this.getNextPacketIndex()
        val packet = this.getPacket(nextIndex)
        this.index = nextIndex
        return packet
    }

    fun getPacket(index: Int): ByteArray {
        val d = this.data ?: throw IllegalStateException("No data set for OtaPacketParser")
        val length = d.size
        val size = 16
        val packetSize = if (length > size) {
            if ((index + 1) == this.total) {
                length - index * size
            } else {
                size
            }
        } else {
            length
        } + 4

        val packet = ByteArray(20) { 0xFF.toByte() }
        System.arraycopy(d, index * size, packet, 2, packetSize - 4)
        this.fillIndex(packet, index)
        val crc = this.crc16(packet)
        this.fillCrc(packet, crc)
        OtaLogger.d("ota packet ---> index : $index total : ${this.total} crc : $crc content : ${Arrays.bytesToHexString(packet, ":")}")
        return packet
    }

    fun getCheckPacket(): ByteArray {
        val packet = ByteArray(16) { 0xFF.toByte() }
        val index = this.getNextPacketIndex()
        this.fillIndex(packet, index)
        val crc = this.crc16(packet)
        this.fillCrc(packet, crc)
        OtaLogger.d("ota check packet ---> index : $index crc : $crc content : ${Arrays.bytesToHexString(packet, ":")}")
        return packet
    }

    fun fillIndex(packet: ByteArray, index: Int) {
        var offset = 0
        packet[offset++] = (index and 0xFF).toByte()
        packet[offset] = (index shr 8 and 0xFF).toByte()
    }

    fun fillCrc(packet: ByteArray, crc: Int) {
        var offset = packet.size - 2
        packet[offset++] = (crc and 0xFF).toByte()
        packet[offset] = (crc shr 8 and 0xFF).toByte()
    }

    fun crc16(packet: ByteArray): Int {
        val length = packet.size - 2
        val poly = shortArrayOf(0, 0xA001.toShort())
        var crc = 0xFFFF
        var ds: Int
        for (j in 0 until length) {
            ds = packet[j].toInt()
            for (i in 0 until 8) {
                crc = (crc shr 1) xor (poly[(crc xor ds) and 1].toInt()) and 0xFFFF
                ds = ds shr 1
            }
        }
        return crc
    }

    fun invalidateProgress(): Boolean {
        val a = this.getNextPacketIndex().toFloat()
        val b = this.total.toFloat()
        OtaLogger.d("invalidate progress: $a -- $b")
        val progress = floor(a / b * 100).toInt()
        if (progress == this.progress) return false
        this.progress = progress
        return true
    }

    fun getProgress(): Int {
        return this.progress
    }

    fun getIndex(): Int {
        return this.index
    }
}

