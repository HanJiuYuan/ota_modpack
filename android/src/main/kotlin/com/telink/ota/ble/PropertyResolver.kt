package com.telink.ota.ble

import android.bluetooth.BluetoothGattCharacteristic

class PropertyResolver(prop: Int) {
    private val properties: MutableMap<String, Boolean> = HashMap()
    private val mProp: Int = prop

    init {
        properties[READ] = (prop and BluetoothGattCharacteristic.PROPERTY_READ) != 0
        properties[WRITE] = (prop and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0
        properties[NOTIFY] = (prop and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0
        properties[INDICATE] = (prop and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
        properties[WRITE_NO_RESPONSE] = (prop and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
    }

    fun contains(key: String): Boolean {
        return properties.containsKey(key) && (properties[key] == true)
    }

    fun getGattCharacteristicPropDesc(): String {
        var desc = " "
        if ((mProp and BluetoothGattCharacteristic.PROPERTY_READ) != 0) desc += "read "
        if ((mProp and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0) desc += "write "
        if ((mProp and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0) desc += "notify "
        if ((mProp and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0) desc += "indicate "
        if ((mProp and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0) desc += "write_no_response "
        return desc
    }

    companion object {
        const val READ = "read"
        const val WRITE = "write"
        const val NOTIFY = "notify"
        const val INDICATE = "indicate"
        const val WRITE_NO_RESPONSE = "write_no_response"
    }
}

