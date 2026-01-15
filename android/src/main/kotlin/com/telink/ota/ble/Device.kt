package com.telink.ota.ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattService
import android.content.Context
import com.telink.ota.fundation.OtaSetting
import com.telink.ota.fundation.StatusCode
import com.telink.ota.util.Arrays
import com.telink.ota.util.OtaLogger
import java.util.UUID

class Device(context: Context) : Peripheral(context) {

    companion object {
        @JvmField
        val TAG: String = Device::class.java.simpleName

        @JvmField
        val OTA_PREPARE: Int = 0xFF00
        @JvmField
        val OTA_START: Int = 0xFF01
        @JvmField
        val OTA_END: Int = 0xFF02

        private const val TAG_OTA_WRITE: Int = 1
        private const val TAG_OTA_READ: Int = 2
        private const val TAG_OTA_LAST: Int = 3

        private const val TAG_OTA_PRE_READ: Int = 4
        private const val TAG_OTA_PREPARE: Int = 5

        private const val TAG_OTA_START: Int = 7
        private const val TAG_OTA_END: Int = 8
        private const val TAG_OTA_ENABLE_NOTIFICATION: Int = 9

        private const val TAG_GENERAL_READ: Int = 11
        private const val TAG_GENERAL_WRITE: Int = 12
        private const val TAG_GENERAL_READ_DESCRIPTOR: Int = 13
        private const val TAG_GENERAL_ENABLE_NOTIFICATION: Int = 14
    }

    private val mOtaParser = OtaPacketParser()
    private val mOtaCallback = OtaCommandCallback()
    private val mOtaTimeoutTask = OtaTimeoutTask()

    private var mDeviceStateCallback: DeviceStateCallback? = null

    private var otaRunning: Boolean = false

    private var skipVersionCompare: Boolean = true
    private var otaBatteryLimit: Int = 30
    @JvmField
    var PACKET_DELAY_MS: Int = 10 // 每包固定延迟，降低写入失败概率，可被外部调节

    private val REBOOT_STEP_PREPARE = 1
    private val REBOOT_STEP_DISCONNECTED = 2
    private val REBOOT_STEP_CONNECTED = 3
    private val RECONNECT_RETRY = 3

    fun setDeviceStateCallback(callback: DeviceStateCallback?) {
        this.mDeviceStateCallback = callback
    }

    override fun connect(bluetoothDevice: BluetoothDevice) {
        mDeviceStateCallback?.onConnectionStateChange(this, BluetoothGatt.STATE_CONNECTING)
        super.connect(bluetoothDevice)
    }

    fun clearAll(disconnect: Boolean) {
        this.mDeviceStateCallback = null
        this.resetOta()
        this.clear()
        if (disconnect) {
            this.forceDisconnect()
        }
    }

    override fun onConnect() {
        super.onConnect()
        // 保持与 Java 行为一致：连接时不主动通知上层，等待 services discovered
    }

    override fun onDisconnect() {
        super.onDisconnect()
        if (isConnectWaiting.get()) {
            this.connect()
        } else {
            if (otaRunning) {
                onOtaFailure(StatusCode.FAIL_CONNECTION_INTERRUPT)
            }
            resetOta()
            mDeviceStateCallback?.onConnectionStateChange(this, BluetoothGatt.STATE_DISCONNECTED)
        }
    }

    fun setSkipVersionCompare(skipVersionCompare: Boolean) {
        this.skipVersionCompare = skipVersionCompare
    }

    fun setOtaBatteryLimit(otaBatteryLimit: Int) {
        this.otaBatteryLimit = otaBatteryLimit
    }

    override fun onServicesDiscovered(services: List<BluetoothGattService>?) {
        super.onServicesDiscovered(services)
        if (services != null) {
            mDeviceStateCallback?.onConnectionStateChange(this, BluetoothGatt.STATE_CONNECTED)
        }
    }

    override fun onNotify(data: ByteArray, serviceUUID: UUID, characteristicUUID: UUID, tag: Any) {
        super.onNotify(data, serviceUUID, characteristicUUID, tag)
    }

    override fun onEnableNotify() {}
    override fun onDisableNotify() {}

    protected fun onOtaStart() {
        mDeviceStateCallback?.onOtaStateChanged(this, StatusCode.STARTED)
    }

    protected fun onOtaComplete() {
        otaRunning = false
        mDeviceStateCallback?.onOtaStateChanged(this, StatusCode.SUCCESS)
    }

    protected fun onOtaFailure(statusCode: StatusCode) {
        mDeviceStateCallback?.onOtaStateChanged(this, statusCode)
    }

    protected fun onOtaProgress() {
        mDeviceStateCallback?.onOtaProgressUpdate(otaProgress)
    }

    // ---------------------------------------------------------------------------------------------
    // OTA API
    // ---------------------------------------------------------------------------------------------

    private var otaSetting: OtaSetting? = null

    fun startOta(otaSetting: OtaSetting) {
        if (otaRunning) {
            onOtaFailure(StatusCode.BUSY)
            return
        }
        if (!isConnected()) {
            onOtaFailure(StatusCode.FAIL_UNCONNECTED)
            return
        }

        this.otaSetting = otaSetting
        if (!validateOtaSettings()) {
            return
        }

        resetOta()
        otaRunning = true
        val fw = otaSetting.getFirmwareData()
        // validateOtaSettings 已经保证非空
        mOtaParser.set(fw!!)
        // 断点续传：若上层指定了 resumeFromPacketIndex，则从该分片继续
        val startIndex = otaSetting.getResumeFromPacketIndex()
        if (startIndex != null && startIndex > 0) {
            mOtaParser.setStartIndex(startIndex)
        }
        mDelayHandler.postDelayed(mOtaTimeoutTask, otaSetting.getOtaTimeout().toLong())
        sendOTAPrepareCommand()
    }

    private fun getService(serviceUUID: UUID): BluetoothGattService? {
        if (mServices != null) {
            for (service in mServices!!) {
                if (service.uuid == serviceUUID) return service
            }
        }
        return null
    }

    fun stopOta(disconnect: Boolean) {
        resetOta()
        if (disconnect) {
            disconnect()
        }
    }

    fun validateOtaSettings(): Boolean {
        val setting = otaSetting
        if (setting == null || setting.getFirmwareData() == null) {
            onOtaFailure(StatusCode.FAIL_PARAMS_ERR)
            return false
        }

        val serviceUUID = otaService
        val service = getService(serviceUUID)
        if (service == null) {
            onOtaFailure(StatusCode.FAIL_SERVICE_NOT_FOUND)
            return false
        }
        if (service.getCharacteristic(otaCharacteristic) == null) {
            onOtaFailure(StatusCode.FAIL_CHARACTERISTIC_NOT_FOUND)
            return false
        }
        return true
    }

    val otaProgress: Int
        get() = mOtaParser.getProgress()

    private fun resetOta() {
        otaRunning = false
        this.mDelayHandler.removeCallbacksAndMessages(null)
        this.mOtaParser.clear()
    }

    private fun setOtaProgressChanged() {
        if (this.mOtaParser.invalidateProgress()) {
            onOtaProgress()
        }
    }

    private fun sendOTAPrepareCommand() {
        onOtaStart()
        val prepareCmd = Command.newInstance()
        prepareCmd.serviceUUID = otaService
        prepareCmd.characteristicUUID = otaCharacteristic
        prepareCmd.type = Command.CommandType.WRITE_NO_RESPONSE
        prepareCmd.tag = TAG_OTA_PREPARE
        prepareCmd.data = byteArrayOf((OTA_PREPARE and 0xFF).toByte(), (OTA_PREPARE shr 8 and 0xFF).toByte())
        sendCommand(mOtaCallback, prepareCmd)
    }

    private fun sendOtaStartCommand() {
        val startCmd = Command.newInstance()
        startCmd.serviceUUID = otaService
        startCmd.characteristicUUID = otaCharacteristic
        startCmd.type = Command.CommandType.WRITE_NO_RESPONSE
        startCmd.tag = TAG_OTA_START
        startCmd.data = byteArrayOf((OTA_START and 0xFF).toByte(), (OTA_START shr 8 and 0xFF).toByte())
        sendCommand(mOtaCallback, startCmd)
    }

    private fun sendOtaEndCommand() {
        val endCmd = Command.newInstance()
        endCmd.serviceUUID = otaService
        endCmd.characteristicUUID = otaCharacteristic
        endCmd.type = Command.CommandType.WRITE_NO_RESPONSE
        endCmd.tag = TAG_OTA_END
        val index = mOtaParser.getIndex()
        val data = ByteArray(8)
        data[0] = (OTA_END and 0xFF).toByte()
        data[1] = (OTA_END shr 8 and 0xFF).toByte()
        data[2] = (index and 0xFF).toByte()
        data[3] = (index shr 8 and 0xFF).toByte()
        data[4] = (index.inv() and 0xFF).toByte()
        data[5] = (index.inv() shr 8 and 0xFF).toByte()
        val crc = mOtaParser.crc16(data)
        mOtaParser.fillCrc(data, crc)
        endCmd.data = data
        sendCommand(mOtaCallback, endCmd)
    }

    private fun sendNextOtaPacketCommand(delay: Int): Boolean {
        var result = false
        if (this.mOtaParser.hasNextPacket()) {
            val cmd = Command.newInstance()
            cmd.serviceUUID = otaService
            cmd.characteristicUUID = otaCharacteristic
            cmd.type = Command.CommandType.WRITE_NO_RESPONSE
            cmd.data = this.mOtaParser.getNextPacket()
            if (this.mOtaParser.isLast()) {
                cmd.tag = TAG_OTA_LAST
                result = true
            } else {
                cmd.tag = TAG_OTA_WRITE
            }
            cmd.delay = if (delay > 0) delay else PACKET_DELAY_MS
            this.sendCommand(this.mOtaCallback, cmd)
            setOtaProgressChanged()
        }
        return result
    }

    private fun validateOta(): Boolean {
        val setting = otaSetting ?: return false
        val readInterval = setting.getReadInterval()
        if (readInterval <= 0) return false
        val sectionSize = 16 * readInterval
        val sendTotal = this.mOtaParser.getNextPacketIndex() * 16
        OtaLogger.i("ota onCommandSampled byte length : $sendTotal")
        if (sendTotal > 0 && sendTotal % sectionSize == 0) {
            OtaLogger.i("onCommandSampled ota read packet ${mOtaParser.getNextPacketIndex()}")
            val cmd = Command.newInstance()
            cmd.serviceUUID = otaService
            cmd.characteristicUUID = otaCharacteristic
            cmd.type = Command.CommandType.READ
            cmd.tag = TAG_OTA_READ
            this.sendCommand(mOtaCallback, cmd)
            return true
        }
        return false
    }

    private val otaService: UUID
        get() {
            val setting = this.otaSetting
            val uuid = setting?.getServiceUUID()
            if (uuid != null) return uuid
            return UuidInfo.OTA_SERVICE_UUID
        }

    private val otaCharacteristic: UUID
        get() {
            val setting = this.otaSetting
            val uuid = setting?.getCharacteristicUUID()
            if (uuid != null) return uuid
            return UuidInfo.OTA_CHARACTERISTIC_UUID
        }

    fun isNotificationEnable(characteristic: BluetoothGattCharacteristic): Boolean {
        val key = generateHashKey(characteristic.service.uuid, characteristic)
        return mNotificationCallbacks.containsKey(key)
    }

    fun enableNotification(serviceUUID: UUID, characteristicUUID: UUID) {
        val cmd = Command.newInstance()
        cmd.serviceUUID = serviceUUID
        cmd.characteristicUUID = characteristicUUID
        cmd.type = Command.CommandType.ENABLE_NOTIFY
        cmd.tag = TAG_GENERAL_ENABLE_NOTIFICATION
        sendCommand(null, cmd)
    }

    // 暴露当前分包索引与总包数，供上层进度事件使用
    fun getCurrentPacketIndex(): Int {
        return mOtaParser.getNextPacketIndex()
    }

    fun getTotalPackets(): Int {
        return mOtaParser.getTotal()
    }

    interface DeviceStateCallback {
        fun onConnectionStateChange(device: Device, state: Int)
        fun onOtaStateChanged(device: Device, statusCode: StatusCode)
        fun onOtaProgressUpdate(progress: Int)
    }

    private inner class OtaCommandCallback : Command.Callback {
        override fun success(peripheral: Peripheral, command: Command, obj: Any?) {
            if (!otaRunning) return
            when (command.tag) {
                TAG_OTA_PRE_READ -> {
                    OtaLogger.d("read response: " + Arrays.bytesToHexString(obj as ByteArray?, "-"))
                }
                TAG_OTA_PREPARE -> {
                    sendOtaStartCommand()
                }
                TAG_OTA_START -> {
                    // 启动后按节流发送第一包
                    sendNextOtaPacketCommand(PACKET_DELAY_MS)
                }
                TAG_OTA_END -> {
                    resetOta()
                    setOtaProgressChanged()
                    onOtaComplete()
                }
                TAG_OTA_LAST -> {
                    sendOtaEndCommand()
                }
                TAG_OTA_WRITE -> {
                    if (!validateOta()) {
                        sendNextOtaPacketCommand(PACKET_DELAY_MS)
                    }
                }
                TAG_OTA_READ -> {
                    sendNextOtaPacketCommand(PACKET_DELAY_MS)
                }
            }
        }

        override fun error(peripheral: Peripheral, command: Command, errorMsg: String) {
            if (!otaRunning) return
            OtaLogger.d("error packet : ${command.tag} errorMsg : $errorMsg")
            if (command.tag == TAG_OTA_END) {
                resetOta()
                setOtaProgressChanged()
                onOtaComplete()
            } else {
                resetOta()
                onOtaFailure(StatusCode.FAIL_PACKET_SENT_ERR)
            }
        }

        override fun timeout(peripheral: Peripheral, command: Command): Boolean {
            if (!otaRunning) return false
            OtaLogger.d("timeout : " + Arrays.bytesToHexString(command.data, ":"))
            if (command.tag == TAG_OTA_END) {
                resetOta()
                setOtaProgressChanged()
                onOtaComplete()
            } else {
                resetOta()
                onOtaFailure(StatusCode.FAIL_PACKET_SENT_TIMEOUT)
            }
            return false
        }
    }

    private inner class OtaTimeoutTask : Runnable {
        override fun run() {
            resetOta()
            onOtaFailure(StatusCode.FAIL_FLOW_TIMEOUT)
        }
    }
}

