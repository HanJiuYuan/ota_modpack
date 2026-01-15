package com.telink.ota.util

import java.nio.charset.Charset

/**
 * Kotlin 等价实现，保留静态方法接口。
 */
object Strings {

    @JvmStatic
    fun stringToBytes(str: String, length: Int): ByteArray {
        if (length <= 0) {
            return str.toByteArray(Charset.defaultCharset())
        }
        val result = ByteArray(length)
        val srcBytes = str.toByteArray(Charset.defaultCharset())
        if (srcBytes.size <= length) {
            System.arraycopy(srcBytes, 0, result, 0, srcBytes.size)
        } else {
            System.arraycopy(srcBytes, 0, result, 0, length)
        }
        return result
    }

    @JvmStatic
    fun stringToBytes(str: String): ByteArray {
        return stringToBytes(str, 0)
    }

    @JvmStatic
    fun bytesToString(data: ByteArray?): String? {
        return if (data == null || data.isEmpty()) null else String(data, Charset.defaultCharset()).trim()
    }

    @JvmStatic
    fun isEmpty(str: String?): Boolean {
        return str == null || str.trim().isEmpty()
    }
}

