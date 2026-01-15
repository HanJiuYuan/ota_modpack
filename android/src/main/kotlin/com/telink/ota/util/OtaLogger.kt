package com.telink.ota.util

import android.util.Log

/**
 * Kotlin 等价实现，保持与 Java `OtaLogger` 相同的字段与静态方法。
 */
object OtaLogger {
    @JvmField
    var TAG: String = "Telink-OTA"

    @JvmField
    var ENABLE: Boolean = true

    @JvmStatic
    fun isLoggable(level: Int): Boolean {
        return ENABLE && Log.isLoggable(TAG, level)
    }

    @JvmStatic
    fun getStackTraceString(th: Throwable): String {
        return if (ENABLE) Log.getStackTraceString(th) else th.message ?: ""
    }

    @JvmStatic
    fun println(level: Int, msg: String): Int {
        return if (ENABLE) Log.println(level, TAG, msg) else 0
    }

    @JvmStatic
    fun v(msg: String): Int {
        return if (ENABLE) Log.v(TAG, msg) else 0
    }

    @JvmStatic
    fun v(msg: String, th: Throwable): Int {
        return if (ENABLE) Log.v(TAG, msg, th) else 0
    }

    @JvmStatic
    fun d(msg: String): Int {
        return if (ENABLE) Log.d(TAG, msg) else 0
    }

    @JvmStatic
    fun d(msg: String, th: Throwable): Int {
        return if (ENABLE) Log.d(TAG, msg, th) else 0
    }

    @JvmStatic
    fun i(msg: String): Int {
        return if (ENABLE) Log.i(TAG, msg) else 0
    }

    @JvmStatic
    fun i(msg: String, th: Throwable): Int {
        return if (ENABLE) Log.i(TAG, msg, th) else 0
    }

    @JvmStatic
    fun w(msg: String): Int {
        return if (ENABLE) Log.w(TAG, msg) else 0
    }

    @JvmStatic
    fun w(msg: String, th: Throwable): Int {
        return if (ENABLE) Log.w(TAG, msg, th) else 0
    }

    @JvmStatic
    fun w(th: Throwable): Int {
        return if (ENABLE) Log.w(TAG, th) else 0
    }

    @JvmStatic
    fun e(msg: String): Int {
        // 注意：Java 版本中 e(msg) 实现误用了 Log.w，这里保持一致还是用 Log.w?
        // 为避免行为差异，这里仍然使用 Log.w 以保持兼容。
        return if (ENABLE) Log.w(TAG, msg) else 0
    }

    @JvmStatic
    fun e(msg: String, th: Throwable): Int {
        return if (ENABLE) Log.e(TAG, msg, th) else 0
    }
}

