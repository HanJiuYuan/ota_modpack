import 'package:nordic_dfu/nordic_dfu.dart';

// 结果处理
/// OTA升级结果状态枚举
enum OtaStatus {
  /// 成功
  success,

  /// 失败
  failure,

  /// 取消
  cancelled,

  /// 进行中
  inProgress,

  /// 未开始
  notStarted,
}

/// OTA升级结果封装类
class OtaResult {
  /// 升级状态
  final OtaStatus status;

  /// 错误信息（如果有）
  final String? errorMessage;

  /// 详细描述
  final String? description;

  /// 进度百分比 (0-100)
  final int? progress;

  /// 升级速度 (KB/s)
  final double? speed;

  /// 平均速度 (KB/s)
  final double? averageSpeed;

  /// 当前部分
  final int? currentPart;

  /// 总部分数
  final int? totalParts;

  /// 设备地址
  final String? deviceAddress;

  /// 创建成功结果
  const OtaResult.success({
    this.deviceAddress,
    this.description = '固件升级成功',
    this.progress = 100,
    this.speed,
    this.averageSpeed,
    this.currentPart,
    this.totalParts,
  })  : status = OtaStatus.success,
        errorMessage = null;

  /// 创建失败结果
  const OtaResult.failure({
    required this.errorMessage,
    this.deviceAddress,
    this.description,
    this.progress,
    this.speed,
    this.averageSpeed,
    this.currentPart,
    this.totalParts,
  }) : status = OtaStatus.failure;

  /// 创建取消结果
  const OtaResult.cancelled({
    this.deviceAddress,
    this.description = '固件升级已取消',
    this.progress,
    this.errorMessage,
    this.speed,
    this.averageSpeed,
    this.currentPart,
    this.totalParts,
  }) : status = OtaStatus.cancelled;

  /// 创建进度结果
  const OtaResult.progress({
    required this.progress,
    this.deviceAddress,
    this.speed,
    this.averageSpeed,
    this.currentPart,
    this.totalParts,
    this.description,
  })  : status = OtaStatus.inProgress,
        errorMessage = null;

  /// 从Nordic DFU进度回调创建进度结果
  factory OtaResult.fromDfuProgress(String deviceAddress, int percent,
      double speed, double avgSpeed, int currentPart, int totalParts) {
    return OtaResult.progress(
      deviceAddress: deviceAddress,
      progress: percent,
      speed: speed,
      averageSpeed: avgSpeed,
      currentPart: currentPart,
      totalParts: totalParts,
      description: '升级进度: $percent%',
    );
  }

  /// 从异常创建失败结果
  factory OtaResult.fromException(dynamic exception, [String? deviceAddress]) {
    String errorMessage = '未知错误';

    if (exception is String) {
      errorMessage = exception;
    } else if (exception is Map && exception.containsKey('message')) {
      errorMessage = '固件升级错误: ${exception['message']}';
    } else {
      errorMessage = exception.toString();
    }

    return OtaResult.failure(
      errorMessage: errorMessage,
      deviceAddress: deviceAddress,
      description: '固件升级失败',
    );
  }

  /// 检查是否成功
  bool get isSuccess => status == OtaStatus.success;

  /// 检查是否失败
  bool get isFailure => status == OtaStatus.failure;

  /// 检查是否取消
  bool get isCancelled => status == OtaStatus.cancelled;

  /// 检查是否进行中
  bool get isInProgress => status == OtaStatus.inProgress;

  @override
  String toString() {
    switch (status) {
      case OtaStatus.success:
        return 'OTA升级成功${description != null ? ': $description' : ''}';
      case OtaStatus.failure:
        return 'OTA升级失败: $errorMessage';
      case OtaStatus.cancelled:
        return 'OTA升级已取消${description != null ? ': $description' : ''}';
      case OtaStatus.inProgress:
        return 'OTA升级进行中: $progress%';
      case OtaStatus.notStarted:
        return 'OTA升级未开始';
    }
  }
}
