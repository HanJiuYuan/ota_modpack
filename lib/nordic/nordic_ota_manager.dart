import 'dart:async';
import 'package:nordic_dfu/nordic_dfu.dart';
import '../core/ota_result.dart';

/// Nordic DFU OTA升级管理器
///
/// 该类负责管理Nordic DFU固件升级流程，包括启动升级、监控进度、处理错误和取消升级等功能。
/// 采用单例模式确保应用程序中只有一个升级任务在进行。
class NordicOtaManager {
  /// 升级状态流控制器
  ///
  /// 用于向监听者广播OTA升级状态变化
  final _otaStatusController = StreamController<OtaResult>.broadcast();

  /// 升级状态流
  ///
  /// 应用程序可以监听该流来获取实时的OTA升级状态
  Stream<OtaResult> get otaStatus => _otaStatusController.stream;

  /// 当前正在升级的设备地址
  String? _currentDeviceAddress;

  /// 是否正在进行升级任务
  ///
  /// 用于防止多个升级任务同时进行
  bool _isUpdating = false;

  /// 获取是否正在升级状态
  ///
  /// 返回当前是否有正在进行的升级任务
  bool get isUpdating => _isUpdating;

  /// 单例实例
  ///
  /// 全局唯一的NordicOtaManager实例
  static final NordicOtaManager _instance = NordicOtaManager._internal();

  /// 工厂构造函数
  ///
  /// 返回全局唯一的NordicOtaManager实例
  factory NordicOtaManager() {
    return _instance;
  }

  /// 内部构造函数
  ///
  /// 私有构造函数，防止外部直接创建实例
  NordicOtaManager._internal();

  /// 开始DFU升级
  ///
  /// 启动设备固件升级流程，并通过状态流通知升级进度和结果
  ///
  /// 参数:
  /// * [deviceAddress] - 设备MAC地址或UUID，必需
  /// * [filePath] - 固件文件路径，必需
  /// * [fileInAsset] - 固件文件是否位于应用资源中，默认为false
  /// * [enablePRNs] - 是否启用包接收通知，默认为false
  /// * [numberOfPackets] - 数据包数量，默认为12
  /// * [forceDfu] - 是否强制DFU模式，默认为false
  /// * [disableResume] - 是否禁用恢复功能，默认为true
  /// * [name] - 设备名称，可选
  ///
  /// 返回:
  /// * 布尔值表示升级任务是否成功启动
  Future<bool> startDfu({
    required String deviceAddress,
    required String filePath,
    bool fileInAsset = false,
    bool enablePRNs = false,
    int? numberOfPackets = 12,
    bool forceDfu = false,
    bool disableResume = true,
    String? name,
  }) async {
    // 检查是否已有升级任务在进行
    if (_isUpdating) {
      _otaStatusController.add(
        OtaResult.failure(
          errorMessage: '已有一个升级任务正在进行中',
          deviceAddress: deviceAddress,
        ),
      );
      return false;
    }

    try {
      // 标记升级开始，保存设备地址
      _isUpdating = true;
      _currentDeviceAddress = deviceAddress;

      // 发布初始进度状态
      _otaStatusController.add(
        OtaResult.progress(
          progress: 0,
          deviceAddress: deviceAddress,
          description: '开始连接设备...',
        ),
      );

      // 创建DFU事件处理器，负责处理各种DFU事件
      final dfuHandler = DfuEventHandler(
        // 设备已连接回调
        onDeviceConnected: (deviceAddress) => _onDeviceConnected(deviceAddress),
        // 设备连接中回调
        onDeviceConnecting: (deviceAddress) =>
            _onDeviceConnecting(deviceAddress),
        // 设备已断开回调
        onDeviceDisconnected: (deviceAddress) =>
            _onDeviceDisconnected(deviceAddress),
        // DFU中止回调
        onDfuAborted: (deviceAddress) => _onDfuAborted(deviceAddress),
        // DFU完成回调
        onDfuCompleted: (deviceAddress) => _onDfuCompleted(deviceAddress),
        // DFU过程开始回调
        onDfuProcessStarted: (deviceAddress) =>
            _onDfuProcessStarted(deviceAddress),
        // DFU过程准备开始回调
        onDfuProcessStarting: (deviceAddress) => {},
        // 正在启用DFU模式回调
        onEnablingDfuMode: (deviceAddress) => {},
        // 固件验证回调
        onFirmwareValidating: (deviceAddress) => {},
        // 错误回调
        onError: (deviceAddress, error, errorCode, message) => _onError(
            deviceAddress, message ?? error.toString(), errorCode ?? -1),
        // 进度变化回调
        onProgressChanged: (deviceAddress, percent, speed, avgSpeed,
                currentPart, totalParts) =>
            _onProgressChanged(deviceAddress, percent, speed, avgSpeed,
                currentPart, totalParts),
      );

      // 调用Nordic DFU库启动升级流程
      final result = await NordicDfu().startDfu(
        deviceAddress,
        filePath,
        fileInAsset: fileInAsset,
        name: name,
        numberOfPackets: numberOfPackets,
        forceDfu: forceDfu,
        dfuEventHandler: dfuHandler,
      );

      // 标记升级已结束
      _isUpdating = false;

      // 处理升级结果
      if (result != null) {
        // 升级成功
        _otaStatusController.add(
          OtaResult.success(deviceAddress: deviceAddress),
        );
        return true;
      } else {
        // 升级失败
        _otaStatusController.add(
          OtaResult.failure(
            errorMessage: '升级过程返回失败',
            deviceAddress: deviceAddress,
          ),
        );
        return false;
      }
    } catch (e) {
      // 发生异常，升级失败
      _isUpdating = false;
      _otaStatusController.add(OtaResult.fromException(e, deviceAddress));
      return false;
    }
  }

  /// 取消当前升级任务
  ///
  /// 中止正在进行的DFU升级流程
  ///
  /// 返回:
  /// * 布尔值表示是否成功取消升级任务
  Future<bool> cancelDfu() async {
    // 检查是否有正在进行的升级任务
    if (!_isUpdating) return false;

    try {
      // 调用Nordic DFU库中止DFU过程
      await NordicDfu().abortDfu();
      _isUpdating = false;

      // 发布取消状态
      _otaStatusController.add(
        OtaResult.cancelled(deviceAddress: _currentDeviceAddress),
      );
      return true;
    } catch (e) {
      // 取消过程中发生异常
      _otaStatusController.add(
        OtaResult.fromException(e, _currentDeviceAddress),
      );
      return false;
    }
  }

  /// 处理进度变化回调
  ///
  /// 当DFU升级进度发生变化时调用，更新进度信息并通知监听者
  ///
  /// 参数:
  /// * [deviceAddress] - 设备地址
  /// * [percent] - 进度百分比(0-100)
  /// * [speed] - 当前速度(KB/s)
  /// * [avgSpeed] - 平均速度(KB/s)
  /// * [currentPart] - 当前部分
  /// * [totalParts] - 总部分数
  void _onProgressChanged(String deviceAddress, int percent, double speed,
      double avgSpeed, int currentPart, int totalParts) {
    _otaStatusController.add(
      OtaResult.fromDfuProgress(
        deviceAddress,
        percent,
        speed,
        avgSpeed,
        currentPart,
        totalParts,
      ),
    );
  }

  /// 设备已连接回调
  ///
  /// 当设备连接成功时调用，通知监听者设备已连接
  ///
  /// 参数:
  /// * [deviceAddress] - 已连接的设备地址
  void _onDeviceConnected(String deviceAddress) {
    _otaStatusController.add(
      OtaResult.progress(
        progress: 0,
        deviceAddress: deviceAddress,
        description: '设备已连接',
      ),
    );
  }

  /// 设备连接中回调
  ///
  /// 当设备正在建立连接时调用，通知监听者设备连接正在进行
  ///
  /// 参数:
  /// * [deviceAddress] - 正在连接的设备地址
  void _onDeviceConnecting(String deviceAddress) {
    _otaStatusController.add(
      OtaResult.progress(
        progress: 0,
        deviceAddress: deviceAddress,
        description: '正在连接设备...',
      ),
    );
  }

  /// 设备已断开回调
  ///
  /// 当设备断开连接时调用，通知监听者设备已断开
  ///
  /// 参数:
  /// * [deviceAddress] - 已断开的设备地址
  void _onDeviceDisconnected(String deviceAddress) {
    _otaStatusController.add(
      OtaResult.progress(
        progress: 0,
        deviceAddress: deviceAddress,
        description: '设备已断开连接',
      ),
    );
  }

  /// DFU中止回调
  ///
  /// 当DFU过程被中止时调用，更新状态并通知监听者
  ///
  /// 参数:
  /// * [deviceAddress] - 设备地址
  void _onDfuAborted(String deviceAddress) {
    _isUpdating = false;
    _otaStatusController.add(
      OtaResult.cancelled(
        deviceAddress: deviceAddress,
      ),
    );
  }

  /// DFU完成回调
  ///
  /// 当DFU过程成功完成时调用，更新状态并通知监听者
  ///
  /// 参数:
  /// * [deviceAddress] - 设备地址
  void _onDfuCompleted(String deviceAddress) {
    _isUpdating = false;
    _otaStatusController.add(
      OtaResult.success(
        deviceAddress: deviceAddress,
      ),
    );
  }

  /// DFU过程开始回调
  ///
  /// 当DFU升级过程正式开始时调用，通知监听者
  ///
  /// 参数:
  /// * [deviceAddress] - 设备地址
  void _onDfuProcessStarted(String deviceAddress) {
    _otaStatusController.add(
      OtaResult.progress(
        progress: 0,
        deviceAddress: deviceAddress,
        description: '升级过程已启动',
      ),
    );
  }

  /// 错误回调
  ///
  /// 当DFU过程中发生错误时调用，更新状态并通知监听者
  ///
  /// 参数:
  /// * [deviceAddress] - 设备地址
  /// * [error] - 错误信息
  /// * [errorCode] - 错误代码
  void _onError(String deviceAddress, String error, int errorCode) {
    _isUpdating = false;
    _otaStatusController.add(
      OtaResult.failure(
        errorMessage: '错误[$errorCode]: $error',
        deviceAddress: deviceAddress,
      ),
    );
  }

  /// 资源释放
  ///
  /// 释放资源并关闭流，应在对象不再使用时调用
  /// 如有正在进行的升级任务，会尝试取消
  void dispose() {
    if (_isUpdating) {
      NordicDfu().abortDfu().catchError((_) {});
      _isUpdating = false;
    }
    _otaStatusController.close();
  }
}
