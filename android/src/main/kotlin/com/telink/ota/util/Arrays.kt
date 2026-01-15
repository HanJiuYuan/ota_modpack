package com.telink.ota.util

import java.io.UnsupportedEncodingException
import java.nio.charset.Charset
import java.util.Formatter

/**
 * Kotlin 等价实现，保留与 Java 版本相同的 API，并通过 @JvmStatic 暴露静态方法。
 */
object Arrays {

    @JvmStatic
    fun reverse(a: ByteArray?): ByteArray? {
        if (a == null) return null
        var p1 = 0
        var p2 = a.size
        val result = ByteArray(p2)
        while (--p2 >= 0) {
            result[p2] = a[p1++]
        }
        return result
    }

    @JvmStatic
    fun reverse(arr: ByteArray, begin: Int, end: Int): ByteArray {
        var i = begin
        var j = end
        while (i < j) {
            val temp = arr[j]
            arr[j] = arr[i]
            arr[i] = temp
            i++
            j--
        }
        return arr
    }

    @JvmStatic
    fun equals(array1: ByteArray?, array2: ByteArray?): Boolean {
        if (array1 === array2) return true
        if (array1 == null || array2 == null || array1.size != array2.size) return false
        for (i in array1.indices) {
            if (array1[i] != array2[i]) return false
        }
        return true
    }

    @JvmStatic
    fun bytesToString(array: ByteArray?): String {
        if (array == null) return "null"
        if (array.isEmpty()) return "[]"
        val sb = StringBuilder(array.size * 6)
        sb.append('[')
        sb.append(array[0])
        for (i in 1 until array.size) {
            sb.append(", ")
            sb.append(array[i])
        }
        sb.append(']')
        return sb.toString()
    }

    @JvmStatic
    @Throws(UnsupportedEncodingException::class)
    fun bytesToString(data: ByteArray, charsetName: String): String {
        return String(data, Charset.forName(charsetName))
    }

    @JvmStatic
    fun bytesToHexString(array: ByteArray?, separator: String?): String {
        if (array == null || array.isEmpty()) return ""
        val sb = StringBuilder()
        val formatter = Formatter(sb)
        formatter.format("%02X", array[0])
        for (i in 1 until array.size) {
            if (!Strings.isEmpty(separator)) sb.append(separator)
            formatter.format("%02X", array[i])
        }
        formatter.flush()
        formatter.close()
        return sb.toString()
    }

    @JvmStatic
    fun hexToBytes(hex: String): ByteArray {
        var hexStr = hex
        if (hexStr.length == 1) {
            hexStr = "0$hexStr"
        }
        val length = hexStr.length / 2
        val result = ByteArray(length)
        for (i in 0 until length) {
            result[i] = Integer.parseInt(hexStr.substring(i * 2, i * 2 + 2), 16).toByte()
        }
        return result
    }

    @JvmStatic
    fun bytesToInt(src: ByteArray, offset: Int): Int {
        if (src.size != 4) return 0
        var value: Int
        value = (src[offset].toInt() and 0xFF
                or (src[offset + 1].toInt() and 0xFF shl 8)
                or (src[offset + 2].toInt() and 0xFF shl 16)
                or (src[offset + 3].toInt() and 0xFF shl 24))
        return value
    }
}

