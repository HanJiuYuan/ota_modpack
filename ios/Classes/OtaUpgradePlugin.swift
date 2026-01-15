import Flutter
import UIKit
import ota_upgrade 
import CoreBluetooth

@objc public class OtaUpgradePlugin: NSObject, FlutterPlugin {
  // Telink OTA related channels
  private var telinkMethodChannel: FlutterMethodChannel!
  private var telinkStatusEventChannel: FlutterEventChannel!
  private var telinkProgressEventChannel: FlutterEventChannel!
  
  // Main plugin channel
  private var mainPluginMethodChannel: FlutterMethodChannel!

  private var statusStreamHandler = StatusStreamHandler()
  private var progressStreamHandler = ProgressStreamHandler()
  private var registrar: FlutterPluginRegistrar!
  
  // 简化：只跟踪当前OTA任务
  private var currentOtaTask: String? = nil
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = OtaUpgradePlugin()
    instance.registrar = registrar
    
    // 初始化 Telink OTA Channels
    instance.telinkMethodChannel = FlutterMethodChannel(
      name: "com.example.ota_upgrade/telink_ota_method", 
      binaryMessenger: registrar.messenger()
    )
    instance.telinkStatusEventChannel = FlutterEventChannel(
      name: "com.example.ota_upgrade/telink_ota_status_event", 
      binaryMessenger: registrar.messenger()
    )
    instance.telinkProgressEventChannel = FlutterEventChannel(
      name: "com.example.ota_upgrade/telink_ota_progress_event", 
      binaryMessenger: registrar.messenger()
    )
    
    registrar.addMethodCallDelegate(instance, channel: instance.telinkMethodChannel)
    instance.telinkStatusEventChannel.setStreamHandler(instance.statusStreamHandler)
    instance.telinkProgressEventChannel.setStreamHandler(instance.progressStreamHandler)

    // 初始化主插件 Channel
    instance.mainPluginMethodChannel = FlutterMethodChannel(
      name: "ota_upgrade", 
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: instance.mainPluginMethodChannel)

    print("OtaUpgradePlugin: All channels registered.")
    
    // 确保状态干净
    instance.currentOtaTask = nil
    
    // 重置底层的OTA状态
    let wrapper = TelinkOtaWrapper.sharedInstance()
    wrapper.cancelOta()
    
    print("OtaUpgradePlugin: 初始化完成，状态已重置")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    print("OtaUpgradePlugin: 收到方法调用: \(call.method)")
    
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    
    case "startTelinkOta", "startTelinkOtaIOS":
      handleStartOta(call: call, result: result)
    
    case "cancelOta":
      handleCancelOta(result: result)
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func handleStartOta(call: FlutterMethodCall, result: @escaping FlutterResult) {
    print("OtaUpgradePlugin: 处理 startOta")
    
    // 检查是否已有OTA在进行
    if currentOtaTask != nil {
      result(FlutterError(code: "BUSY", message: "另一个 OTA 进程正在进行中: \(currentOtaTask!)", details: nil))
      return
    }
    
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGS", message: "参数格式错误", details: nil))
      return
    }
    
    let macAddress = args["macAddress"] as? String
    let deviceName = args["deviceName"] as? String  
    let filePath = args["filePath"] as? String
    let isAsset = args["fileInAsset"] as? Bool ?? false
    let readInterval = args["readInterval"] as? Int ?? 8
    
    // 参数验证
    if filePath == nil {
      result(FlutterError(code: "INVALID_ARGS", message: "固件文件路径缺失", details: nil))
      return
    }
    
    let deviceId = macAddress ?? deviceName
    if deviceId == nil {
      result(FlutterError(code: "INVALID_ARGS", message: "必须提供macAddress或deviceName参数", details: nil))
      return
    }
    
    // 处理文件路径
    if isAsset, let assetPath = filePath {
      loadAssetFile(assetPath) { [weak self] localPath in
        guard let self = self, let localPath = localPath else {
          result(FlutterError(code: "FILE_ERROR", message: "无法加载固件文件", details: nil))
          self?.statusStreamHandler.send(state: "failed", errorMessage: "无法加载固件文件")
          return
        }
        
        self.performOta(deviceId: deviceId!, filePath: localPath, readInterval: readInterval, result: result)
      }
    } else if let path = filePath {
      performOta(deviceId: deviceId!, filePath: path, readInterval: readInterval, result: result)
    }
  }
  
  private func performOta(deviceId: String, filePath: String, readInterval: Int, result: @escaping FlutterResult) {
    print("OtaUpgradePlugin: 执行OTA - 设备: \(deviceId), 文件: \(filePath)")
    
    currentOtaTask = deviceId
    
    // 发送初始状态
    statusStreamHandler.send(state: "connecting", macAddress: deviceId)
    
    let wrapper = TelinkOtaWrapper.sharedInstance()
    
    // 设置目标设备
    wrapper.setConnectedDevice(deviceId)
    
    // 直接调用wrapper的OTA方法，让它处理所有连接和OTA逻辑
    wrapper.startOta(withFilePath: filePath, readInterval: readInterval, 
      progressCallback: { [weak self] progress in
        guard let self = self else { return }
        
        // 发送进度更新
        self.progressStreamHandler.send(progress: progress)
        
        // 第一次进度更新时发送connected和starting状态
        if progress == 0 {
          self.statusStreamHandler.send(state: "connected", macAddress: deviceId)
          self.statusStreamHandler.send(state: "starting", macAddress: deviceId)
        }
        
        // 有进度就发送progress状态
        if progress > 0 {
          self.statusStreamHandler.send(state: "progress", macAddress: deviceId)
        }
      },
      completionCallback: { [weak self] success, errorMessage in
        guard let self = self else { return }
        
        if success {
          self.statusStreamHandler.send(state: "completed", macAddress: deviceId)
        } else {
          let error = errorMessage ?? "OTA失败"
          
          // 分析错误类型，提供更详细的状态
          if error.contains("蓝牙未开启") {
            self.statusStreamHandler.send(state: "failed", macAddress: deviceId, errorMessage: "蓝牙未开启")
          } else if error.contains("连接失败") || error.contains("连接超时") {
            self.statusStreamHandler.send(state: "failed", macAddress: deviceId, errorMessage: "设备连接失败")
          } else if error.contains("无法找到指定设备") {
            self.statusStreamHandler.send(state: "failed", macAddress: deviceId, errorMessage: "未找到设备")
          } else {
            self.statusStreamHandler.send(state: "failed", macAddress: deviceId, errorMessage: error)
          }
        }
        
        // 清理当前任务
        self.currentOtaTask = nil
      }
    )
    
    // 立即返回，实际结果通过EventChannel回调
    result("OTA进程已启动")
  }
  
  private func handleCancelOta(result: @escaping FlutterResult) {
    print("OtaUpgradePlugin: 取消OTA")
    
    let wrapper = TelinkOtaWrapper.sharedInstance()
    wrapper.cancelOta()
    
    statusStreamHandler.send(state: "aborted", macAddress: currentOtaTask)
    currentOtaTask = nil
    
    result("OTA已取消")
  }
  
  private func loadAssetFile(_ assetPath: String, completion: @escaping (String?) -> Void) {
    print("OtaUpgradePlugin: 加载资源文件: \(assetPath)")
    
    let key = registrar.lookupKey(forAsset: assetPath)
    if let path = Bundle.main.path(forResource: key, ofType: nil) {
      completion(path)
      return
    }
    
    let packageKey = registrar.lookupKey(forAsset: assetPath, fromPackage: "ota_upgrade")
    if let path = Bundle.main.path(forResource: packageKey, ofType: nil) {
      completion(path)
      return
    }
    
    // 检查 App.framework
    if let frameworkPath = Bundle.main.path(forResource: "App", ofType: "framework"),
       let appBundle = Bundle(path: frameworkPath) {
      
      if let path = appBundle.path(forResource: key, ofType: nil) {
        completion(path)
        return
      }
      
      if let path = appBundle.path(forResource: packageKey, ofType: nil) {
        completion(path)
        return
      }
    }
    
    print("OtaUpgradePlugin: 无法找到资源文件")
    completion(nil)
  }
}

// MARK: - Stream Handlers
class StatusStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }
  
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
  
  func send(state: String, macAddress: String? = nil, errorMessage: String? = nil) {
    guard let eventSink = eventSink else { return }
    
    var event: [String: Any] = ["state": state]
    if let macAddress = macAddress {
      event["macAddress"] = macAddress
    }
    if let errorMessage = errorMessage {
      event["errorMessage"] = errorMessage
    }
    
    DispatchQueue.main.async {
      eventSink(event)
    }
  }
}

class ProgressStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }
  
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
  
  func send(progress: Float) {
    guard let eventSink = eventSink else { return }
    
    DispatchQueue.main.async {
      eventSink(["progress": progress])
    }
  }
}
