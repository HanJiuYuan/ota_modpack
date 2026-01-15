import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TelinkOtaStatus {
  static const String connecting = 'connecting';
  static const String discoveringServices = 'discoveringServices';
  static const String starting = 'starting';
  static const String progress = 'progress';
  static const String completed = 'completed';
  static const String aborted = 'aborted';
  static const String failed = 'failed';
  static const String cancelling = 'cancelling';

  // iOS平台特有状态
  static const String scanning = 'scanning';
  static const String deviceFound = 'deviceFound';
}

class TelinkOta {
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.ota_upgrade/telink_ota_method');

  static const EventChannel _statusEventChannel =
      EventChannel('com.example.ota_upgrade/telink_ota_status_event');

  static const EventChannel _progressEventChannel =
      EventChannel('com.example.ota_upgrade/telink_ota_progress_event');

  static Stream<Map<String, dynamic>>? _statusStream;
  static Stream<Map<String, dynamic>>? _progressStream;

  /// 获取 OTA 状态流
  static Stream<Map<String, dynamic>> get statusStream {
    _statusStream ??= _statusEventChannel
        .receiveBroadcastStream()
        .map<Map<String, dynamic>>((event) => Map<String, dynamic>.from(event));
    return _statusStream!;
  }

  /// 获取 OTA 进度流
  static Stream<Map<String, dynamic>> get progressStream {
    _progressStream ??= _progressEventChannel
        .receiveBroadcastStream()
        .map<Map<String, dynamic>>((event) => Map<String, dynamic>.from(event));
    return _progressStream!;
  }

  /// 开始 OTA 升级
  ///
  /// [macAddress] 设备 MAC 地址（Android必须，iOS可选）
  /// [deviceName] 设备名称（iOS扫描用，可选）
  /// [filePath] 固件文件路径
  /// [fileInAsset] 是否是资产文件，默认为 false
  /// [readInterval] 读取间隔，默认为 8
  /// [connectionTimeout] 连接超时时间（秒），默认为 15 秒
  static Future<String> startOta({
    required String macAddress,
    String? deviceName,
    required String filePath,
    bool fileInAsset = false,
    int readInterval = 8,
    double connectionTimeout = 15.0,
    String? serviceUUID,
    String? characteristicUUID,
    int? resumeFromPacketIndex,
    int? packetDelayMs,
  }) async {
    debugPrint('TelinkOta: 开始OTA升级流程');
    debugPrint('TelinkOta: macAddress = $macAddress');
    debugPrint('TelinkOta: deviceName = $deviceName');
    debugPrint('TelinkOta: filePath = $filePath');
    debugPrint('TelinkOta: fileInAsset = $fileInAsset');
    debugPrint('TelinkOta: readInterval = $readInterval');
    debugPrint('TelinkOta: connectionTimeout = $connectionTimeout');
    debugPrint('TelinkOta: Platform.isIOS = ${Platform.isIOS}');

    final Map<String, dynamic> params = {
      'macAddress': macAddress,
      'filePath': filePath,
      'fileInAsset': fileInAsset,
      'readInterval': readInterval,
      'connectionTimeout': connectionTimeout,
    };

    if (deviceName != null) {
      params['deviceName'] = deviceName;
    }

    if (serviceUUID != null) {
      params['serviceUUID'] = serviceUUID;
    }

    if (characteristicUUID != null) {
      params['characteristicUUID'] = characteristicUUID;
    }

    if (resumeFromPacketIndex != null) {
      params['resumeFromPacketIndex'] = resumeFromPacketIndex;
    }

    if (packetDelayMs != null) {
      params['packetDelayMs'] = packetDelayMs;
    }

    debugPrint('TelinkOta: 准备调用原生方法，参数 = $params');

    // 根据平台调用不同方法
    if (Platform.isIOS) {
      debugPrint('TelinkOta: 调用 iOS 原生方法 startTelinkOtaIOS');
      final result =
          await _methodChannel.invokeMethod('startTelinkOtaIOS', params);
      debugPrint('TelinkOta: iOS 原生方法返回结果 = $result');
      return result;
    } else {
      debugPrint('TelinkOta: 调用 Android 原生方法 startTelinkOta');
      final result =
          await _methodChannel.invokeMethod('startTelinkOta', params);
      debugPrint('TelinkOta: Android 原生方法返回结果 = $result');
      return result;
    }
  }

  /// 取消正在进行的OTA
  static Future<String> cancelOta() async {
    try {
      final String result = await _methodChannel.invokeMethod('cancelOta');
      return result;
    } on PlatformException catch (e) {
      throw '取消OTA失败: ${e.message}';
    }
  }

  /// 重置OTA状态（用于清理可能的残留状态）
  static Future<String> resetOtaState() async {
    try {
      // 先尝试取消任何可能的OTA
      await _methodChannel.invokeMethod('cancelOta');
      return 'OTA状态已重置';
    } on PlatformException catch (e) {
      // 即使取消失败也没关系，可能本来就没有OTA在进行
      print('重置OTA状态: ${e.message}');
      return 'OTA状态重置完成';
    }
  }

  /// 重置蓝牙扫描状态 - 解决设备广播但搜索不到的问题
  ///
  /// 当设备在广播但程序搜索不到时，调用此方法重置扫描状态
  static Future<String> resetScanState() async {
    debugPrint('TelinkOta: 重置蓝牙扫描状态');
    final result = await _methodChannel.invokeMethod('resetScanState');
    debugPrint('TelinkOta: 扫描状态重置结果 = $result');
    return result;
  }
}
