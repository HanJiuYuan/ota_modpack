package com.zyg.ota_upgrade

import androidx.annotation.NonNull
import android.util.Log
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.content.Context
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.io.InputStream

import com.telink.ota.ble.Device
import com.telink.ota.fundation.OtaSetting
import com.telink.ota.fundation.StatusCode
import com.telink.ota.util.OtaLogger

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import java.util.*
import android.bluetooth.BluetoothGattCharacteristic

/** OtaUpgradePlugin */
class OtaUpgradePlugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var mainChannel: MethodChannel
  private lateinit var telinkOtaChannel: MethodChannel
  private lateinit var telinkStatusChannel: EventChannel
  private lateinit var telinkProgressChannel: EventChannel
  
  private val TAG = "OtaUpgradePlugin"

  // Telink OTA 状态参数
  private var applicationContext: Context? = null
  private val mainThreadHandler = Handler(Looper.getMainLooper())
  private var mDevice: Device? = null
  private var telinkStatusEventSink: EventChannel.EventSink? = null
  private var telinkProgressEventSink: EventChannel.EventSink? = null
  private var currentOtaMacAddress: String? = null

  // 使用固定的写入延迟
  private val WRITE_DELAY = 20L // 毫秒，根据需要调整

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    Log.d(TAG, "onAttachedToEngine called")
    
    // 保存 Context
    applicationContext = flutterPluginBinding.applicationContext
    
    // 1. 设置主通道
    mainChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "ota_upgrade")
    mainChannel.setMethodCallHandler(this)
    
    // 2. 设置 Telink OTA 通道 - 与 telink_ota.dart 中的名称完全一致
    telinkOtaChannel = MethodChannel(flutterPluginBinding.binaryMessenger, 
                                   "com.example.ota_upgrade/telink_ota_method")
    telinkOtaChannel.setMethodCallHandler(this)
    
    // 3. 设置事件通道
    telinkStatusChannel = EventChannel(flutterPluginBinding.binaryMessenger,
                                     "com.example.ota_upgrade/telink_ota_status_event")
    telinkStatusChannel.setStreamHandler(telinkStatusStreamHandler)
    
    telinkProgressChannel = EventChannel(flutterPluginBinding.binaryMessenger,
                                       "com.example.ota_upgrade/telink_ota_progress_event")
    telinkProgressChannel.setStreamHandler(telinkProgressStreamHandler)
    
    // 启用 TelinkOtaLib 日志
    OtaLogger.ENABLE = true
    
    // 4. 打印确认日志
    Log.d(TAG, "所有通道已设置完成，包括 Telink OTA 通道")
  }

  // Telink OTA 状态流处理器
  private val telinkStatusStreamHandler = object : EventChannel.StreamHandler {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
      Log.d(TAG, "Telink Status EventChannel onListen")
      telinkStatusEventSink = events
    }

    override fun onCancel(arguments: Any?) {
      Log.d(TAG, "Telink Status EventChannel onCancel")
      telinkStatusEventSink = null
    }
  }

  // Telink OTA 进度流处理器
  private val telinkProgressStreamHandler = object : EventChannel.StreamHandler {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
      Log.d(TAG, "Telink Progress EventChannel onListen")
      telinkProgressEventSink = events
    }

    override fun onCancel(arguments: Any?) {
      Log.d(TAG, "Telink Progress EventChannel onCancel")
      telinkProgressEventSink = null
    }
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    Log.d(TAG, "收到方法调用: ${call.method}")
    
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      }
      "startTelinkOta" -> {
        Log.d(TAG, "收到 startTelinkOta 调用，参数: ${call.arguments}")
        
        val macAddress = call.argument<String>("macAddress")
        val filePath = call.argument<String>("filePath")
        val fileInAsset = call.argument<Boolean>("fileInAsset") ?: false
        val readInterval = call.argument<Int>("readInterval") ?: 8
        val serviceUUID = call.argument<String>("serviceUUID")
        val characteristicUUID = call.argument<String>("characteristicUUID")
        val resumeFromPacketIndex = call.argument<Int>("resumeFromPacketIndex")
        val packetDelayMs = call.argument<Int>("packetDelayMs")

        if (mDevice != null) {
          result.error("BUSY", "另一个 OTA 进程正在进行中: $currentOtaMacAddress", null)
          return
        }
        if (macAddress == null || !BluetoothAdapter.checkBluetoothAddress(macAddress)) {
          result.error("INVALID_ARGS", "无效的 MAC 地址: $macAddress", null)
          return
        }
        if (filePath == null) {
          result.error("INVALID_ARGS", "固件文件路径不能为空", null)
          return
        }

        try {
          // 读取固件文件
          val firmwareData = readFirmwareFile(filePath, fileInAsset)
          if (firmwareData == null || firmwareData.isEmpty()) {
            result.error("FILE_ERROR", "无法读取固件文件或文件为空", null)
            return
          }
          
          currentOtaMacAddress = macAddress
          startFullOtaProcess(macAddress, firmwareData, readInterval, serviceUUID, characteristicUUID, resumeFromPacketIndex, packetDelayMs)
          result.success("OTA 进程已为 $macAddress 启动")
        } catch (e: Exception) {
          Log.e(TAG, "读取固件文件失败", e)
          result.error("FILE_ERROR", "读取固件文件失败: ${e.message}", null)
        }
      }
      "cancelOta" -> {
        Log.d(TAG, "收到 cancelOta 调用")
        if (mDevice != null) {
          sendStatusUpdate("cancelling", currentOtaMacAddress, null)
          cleanupCurrentDevice(true) // 停止并断开连接
          sendStatusUpdate("aborted", currentOtaMacAddress, null)
          result.success("已请求取消 OTA: $currentOtaMacAddress")
        } else {
          result.error("IDLE", "当前没有活动的 OTA 进程可取消", null)
        }
      }
      else -> {
        Log.w(TAG, "未知方法: ${call.method}")
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    Log.d(TAG, "onDetachedFromEngine called")
    mainChannel.setMethodCallHandler(null)
    telinkOtaChannel.setMethodCallHandler(null)
    telinkStatusChannel.setStreamHandler(null)
    telinkProgressChannel.setStreamHandler(null)
    cleanupCurrentDevice(true)
    applicationContext = null
  }

  // --- Telink OTA 辅助方法 ---
  private fun sendStatusUpdate(state: String, macAddress: String?, errorMessage: String?) {
    telinkStatusEventSink?.let { sink ->
      val event = mutableMapOf<String, Any?>()
      event["state"] = state
      macAddress?.let { event["macAddress"] = it }
      errorMessage?.let { event["errorMessage"] = it }
      mainThreadHandler.post { sink.success(event) }
      Log.d(TAG, "发送状态更新: $state${errorMessage?.let { " 错误: $it" } ?: ""}")
    } ?: Log.w(TAG, "无法发送状态更新，telinkStatusEventSink 为 null")
  }

  private fun sendProgressUpdate(progress: Int, macAddress: String?) {
    telinkProgressEventSink?.let { sink ->
      val event = mutableMapOf<String, Any?>()
      event["progress"] = progress
      // 附带分包级别的断点信息
      mDevice?.let { dev ->
        try {
          event["packetIndex"] = dev.getCurrentPacketIndex()
          event["totalPackets"] = dev.getTotalPackets()
        } catch (_: Exception) {}
      }
      macAddress?.let { event["macAddress"] = it }
      mainThreadHandler.post { sink.success(event) }
    } ?: Log.w(TAG, "无法发送进度更新，telinkProgressEventSink 为 null")
  }

  // OTA 进程暂存数据 (因为连接是异步的)
  private var pendingFirmwareData: ByteArray? = null
  private var pendingReadInterval: Int = 8
  private var pendingServiceUUID: UUID? = null
  private var pendingCharacteristicUUID: UUID? = null
  private var pendingResumeFromPacketIndex: Int? = null
  private var pendingPacketDelayMs: Int? = null

  private fun startFullOtaProcess(
    macAddress: String,
    firmwareData: ByteArray,
    readInterval: Int,
    serviceUUIDStr: String?,
    characteristicUUIDStr: String?,
    resumeFromPacketIndex: Int?,
    packetDelayMs: Int?
  ) {
    Log.d(TAG, "开始 OTA 进程: $macAddress")
    val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
    if (bluetoothAdapter == null) {
      sendStatusUpdate("failed", macAddress, "蓝牙不可用")
      cleanupCurrentDevice(false)
      return
    }

    try {
      val bluetoothDevice = bluetoothAdapter.getRemoteDevice(macAddress)
      applicationContext?.let { ctx ->
        mDevice = Device(ctx)
        mDevice?.setDeviceStateCallback(otaDeviceCallback)
        sendStatusUpdate("connecting", macAddress, null)
        mDevice?.connect(bluetoothDevice)

        // 保存固件数据和参数，以便连接成功后使用
        this.pendingFirmwareData = firmwareData
        this.pendingReadInterval = readInterval
        this.pendingServiceUUID = serviceUUIDStr?.let { UUID.fromString(it) }
        this.pendingCharacteristicUUID = characteristicUUIDStr?.let { UUID.fromString(it) }
        // 把断点信息也暂存下来（通过 OtaSetting 传递）
        this.pendingResumeFromPacketIndex = resumeFromPacketIndex
        // 暂存自定义包间延迟
        this.pendingPacketDelayMs = packetDelayMs

      } ?: run {
        Log.e(TAG, "Context 为 null，无法启动 OTA")
        sendStatusUpdate("failed", macAddress, "内部错误: Context 为 null")
        cleanupCurrentDevice(false)
      }

    } catch (e: IllegalArgumentException) {
      Log.e(TAG, "startFullOtaProcess 中的 IllegalArgumentException: ${e.message}", e)
      sendStatusUpdate("failed", macAddress, "无效的 MAC 地址格式: ${e.message}")
      cleanupCurrentDevice(false)
    } catch (e: Exception) {
      Log.e(TAG, "startFullOtaProcess 中的异常: ${e.message}", e)
      sendStatusUpdate("failed", macAddress, "启动连接失败: ${e.message}")
      cleanupCurrentDevice(false)
    }
  }

  // 设备状态回调
  private val otaDeviceCallback = object : Device.DeviceStateCallback {
    override fun onConnectionStateChange(device: Device, state: Int) {
      val mac = device.macAddress
      Log.d(TAG, "回调 onConnectionStateChange: $state for $mac")

      if (mac == null || mac != currentOtaMacAddress) {
        if (mDevice == null) {
          Log.w(TAG, "忽略过期的 onConnectionStateChange，mDevice 为 null")
          return
        }
        Log.w(TAG, "收到意外设备的连接状态变化: $mac")
        return
      }

      when (state) {
        BluetoothGatt.STATE_CONNECTING -> {
          Log.d(TAG, "设备正在连接: $mac")
        }
        BluetoothGatt.STATE_CONNECTED -> {
          Log.d(TAG, "设备已连接: $mac，正在发现服务...")
          sendStatusUpdate("discoveringServices", mac, null)
          
          // 连接后启动 OTA
          pendingFirmwareData?.let { fwData ->
            val setting = OtaSetting().apply {
              setFirmwareData(fwData)
              setReadInterval(pendingReadInterval)
              pendingServiceUUID?.let { setServiceUUID(it) }
              pendingCharacteristicUUID?.let { setCharacteristicUUID(it) }
            }
            // 直接设置断点续传分片索引
            setting.setResumeFromPacketIndex(pendingResumeFromPacketIndex)
            // 如果设置了自定义包延迟，尝试注入到 Device（通过反射设置字段）
            try {
              pendingPacketDelayMs?.let { delay ->
                val field = Device::class.java.getDeclaredField("PACKET_DELAY_MS")
                field.isAccessible = true
                field.setInt(mDevice, delay)
              }
            } catch (_: Exception) {}
            Log.d(TAG, "尝试使用配置启动 OTA 进程")
            mDevice?.startOta(setting)
          } ?: run {
            Log.e(TAG, "已连接但无固件数据启动 OTA!")
            sendStatusUpdate("failed", mac, "内部错误: 连接后无固件数据")
            cleanupCurrentDevice(true)
          }
        }
        BluetoothGatt.STATE_DISCONNECTING -> {
          Log.d(TAG, "设备正在断开连接: $mac")
        }
        BluetoothGatt.STATE_DISCONNECTED -> {
          Log.d(TAG, "设备已断开连接: $mac")
          var connectionStatus = -1  // 定义在外部作用域的状态变量
          
          if (device != null && device.javaClass.methods.any { it.name == "getLastGattStatus" }) {
            try {
              // 尝试获取详细错误码（如果 Device 类提供）
              val statusMethod = device.javaClass.getMethod("getLastGattStatus")
              connectionStatus = (statusMethod.invoke(device) as? Int) ?: -1
              Log.d(TAG, "断开连接的详细错误码: $connectionStatus")
            } catch (e: Exception) {
              Log.e(TAG, "获取错误码失败: ${e.message}")
            }
          }
          
          if (mDevice != null) {
            if (connectionStatus == 133) {  // 使用外部作用域的变量
              Log.w(TAG, "设备连接错误 (错误码 133): 设备可能不存在或不在范围内")
              sendStatusUpdate("failed", mac, "设备连接错误: 设备不存在或不在范围内")
            } else {
              Log.w(TAG, "连接意外中断: $mac")
              sendStatusUpdate("failed", mac, "连接意外中断")
            }
            cleanupCurrentDevice(false)
          } else {
            Log.d(TAG, "$mac 的断开回调，但 mDevice 为 null (已清理)")
          }
        }
      }
    }

    override fun onOtaStateChanged(device: Device, statusCode: StatusCode) {
      val mac = device.macAddress
      Log.d(TAG, "回调 onOtaStateChanged: ${statusCode.desc} for $mac")

      if (mac == null || mac != currentOtaMacAddress) {
        if (mDevice == null && statusCode != StatusCode.SUCCESS && statusCode != StatusCode.STOPPED && !statusCode.isFailed()) {
          Log.w(TAG, "忽略过期的 onOtaStateChanged，mDevice 为 null")
          return
        }
        Log.w(TAG, "收到意外设备的 OTA 状态更新: $mac / $statusCode")
        return
      }

      when (statusCode) {
        StatusCode.STARTED -> {
          Log.i(TAG, "$mac 的 OTA 已开始")
          sendStatusUpdate("starting", mac, null)
          sendStatusUpdate("progress", mac, null)
        }
        StatusCode.SUCCESS -> {
          Log.i(TAG, "$mac 的 OTA 成功")
          sendStatusUpdate("completed", mac, null)
          cleanupCurrentDevice(true)
        }
        StatusCode.STOPPED -> {
          Log.i(TAG, "$mac 的 OTA 已停止")
          sendStatusUpdate("aborted", mac, null)
          if (mDevice != null) cleanupCurrentDevice(true)
        }
        else -> {
          if (statusCode.isFailed()) {
            Log.e(TAG, "$mac 的 OTA 失败，状态: ${statusCode.desc}")
            sendStatusUpdate("failed", mac, statusCode.desc)
            cleanupCurrentDevice(true)
          } else {
            Log.w(TAG, "$mac 的未处理 OTA 状态: ${statusCode.desc}")
          }
        }
      }
    }

    override fun onOtaProgressUpdate(progress: Int) {
      sendProgressUpdate(progress, currentOtaMacAddress)
    }
  }

  private fun cleanupCurrentDevice(disconnect: Boolean) {
    Log.d(TAG, "清理设备: $currentOtaMacAddress, 断开连接: $disconnect")
    mDevice?.let { dev ->
      Log.d(TAG, "清理 $currentOtaMacAddress 的设备实例")
      dev.setDeviceStateCallback(null)
      dev.clearAll(disconnect)
    }
    mDevice = null
    currentOtaMacAddress = null
    pendingFirmwareData = null
    pendingServiceUUID = null
    pendingCharacteristicUUID = null
    Log.d(TAG, "设备清理完成")
  }

  // 添加读取固件文件的方法
  private fun readFirmwareFile(filePath: String, isAsset: Boolean): ByteArray? {
    Log.d(TAG, "读取固件文件: $filePath, 是否为资产: $isAsset")
    var inputStream: InputStream? = null
    
    try {
      if (isAsset) {
        // 从 Flutter 资产中读取
        // 注意: Flutter资产路径通常以 "flutter_assets/" 开头
        val assetManager = applicationContext?.assets
        if (assetManager == null) {
          Log.e(TAG, "无法访问 AssetManager")
          return null
        }
        
        // 处理可能的包前缀
        var assetPath = filePath
        if (assetPath.startsWith("packages/")) {
          // 保留 packages/ 后面的路径部分
          assetPath = "flutter_assets/$assetPath"
        } else {
          assetPath = "flutter_assets/$assetPath"
        }
        
        Log.d(TAG, "尝试从资产加载: $assetPath")
        inputStream = assetManager.open(assetPath)
      } else {
        // 从文件系统读取
        val file = File(filePath)
        if (!file.exists() || !file.isFile) {
          Log.e(TAG, "文件不存在: $filePath")
          return null
        }
        inputStream = FileInputStream(file)
      }
      
      return inputStream?.readBytes()
    } catch (e: IOException) {
      Log.e(TAG, "读取文件失败: ${e.message}", e)
      return null
    } finally {
      inputStream?.close()
    }
  }

  // 在数据包发送后添加延迟
  private fun sendOtaPacket(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, data: ByteArray) {
    // 写入数据
    characteristic.setValue(data)
    gatt.writeCharacteristic(characteristic)
    
    // 固定延迟
    Thread.sleep(WRITE_DELAY)
  }
}
