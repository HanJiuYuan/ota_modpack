import 'dart:convert';

import 'package:ble_integrated/blue/blue_connection.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:ota_upgrade/ota_upgrade.dart';
import 'package:ota_upgrade/telink/telink_ota.dart'; // 导入 Telink OTA 库
import 'package:ble_integrated/blue/blue_scan.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:ble_integrated/blue/blue_connection.dart';

void main() {
  runApp(const MaterialApp(home: MyApp())); // 将 MaterialApp 放在这里
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _otaUpgradePlugin = OtaUpgrade();
  List dfuDevices = [];
  // Telink OTA 相关状态
  final TextEditingController _macController = TextEditingController();
  String _otaStatus = "就绪";
  int _otaProgress = 0;
  bool _otaInProgress = false;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _progressSubscription;

  // 添加时间记录相关变量
  DateTime? _otaStartTime;
  DateTime? _otaEndTime;
  Duration? _otaElapsedTime;
  Timer? _timeUpdateTimer;
  String _otaTimeInfo = "";

  // 🔥 新增：传输统计相关变量
  String _transferStats = "";
  int _lastProgress = 0;
  DateTime? _lastProgressTime;

  // 添加升级历史记录
  List<Map<String, dynamic>> _otaHistory = [];
  // 添加readInterval输入控制器
  final TextEditingController _readIntervalController =
      TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    initPlatformState();

    // 初始化 OTA 监听
    _statusSubscription = TelinkOta.statusStream.listen((status) {
      print('===== OTA状态更新 =====');
      print('状态: ${status['state']}');
      if (status['errorMessage'] != null) {
        print('错误信息: ${status['errorMessage']}');
      }
      if (status['macAddress'] != null) {
        print('设备地址: ${status['macAddress']}');
      }
      print(
          '当前计时状态: 开始时间=${_otaStartTime}, 进行中=${_otaStartTime != null && _otaEndTime == null}');

      setState(() {
        _otaStatus = "${status['state']}";
        if (status['errorMessage'] != null) {
          String errorMessage = status['errorMessage'];
          _otaStatus += " - $errorMessage";

          // 设备断开连接的特殊处理
          if (errorMessage.contains('设备断开') || errorMessage.contains('正在重连')) {
            _otaStatus += "\n💡 建议: 确保设备距离很近且电量充足";
          }
        }

        // 根据README.md的状态说明更新运行状态
        if (['completed', 'failed', 'aborted'].contains(status['state'])) {
          _otaInProgress = false;

          // 停止计时
          print('OTA结束，停止计时. 状态: ${status['state']}');
          _stopOtaTimer();

          // 如果是completed状态，添加成功提示
          if (status['state'] == 'completed') {
            _otaStatus += "\n✅ 设备重启应用新固件中，连接断开为正常现象";
            // 记录成功的升级时间
            if (_otaElapsedTime != null) {
              _otaStatus += "\n⏱️ ${_otaTimeInfo}";
            }
            // 保存成功的升级记录
            _saveOtaRecord(
                '成功',
                _getSpeedDescription(
                    int.tryParse(_readIntervalController.text) ?? 0));
          } else if (status['state'] == 'failed') {
            // 🔥 添加特殊错误处理
            if (status['errorMessage'] != null) {
              String errorMessage = status['errorMessage'];

              // 版本冲突或设备状态异常的特殊处理
              if (errorMessage.contains('版本冲突') ||
                  errorMessage.contains('设备状态异常') ||
                  errorMessage.contains('0x06') ||
                  errorMessage.contains('拒绝升级')) {
                _otaStatus += "\n🔄 建议: 设备可能需要完全重启后再尝试升级";
                _otaStatus += "\n💡 请断电重启设备，等待30秒后重试";
              } else if (errorMessage.contains('连接超时')) {
                _otaStatus += "\n💡 建议: 确保设备距离很近(<1米)且电量充足(>50%)";
              } else if (errorMessage.contains('设备断开')) {
                _otaStatus += "\n💡 建议: 设备可能进入休眠模式，请重启设备后重试";
              } else if (errorMessage.contains('进度:') &&
                  errorMessage.contains('/')) {
                _otaStatus += "\n💡 建议: OTA传输过程中断开，请检查信号强度和电量";
              }
            }
            // 记录失败的升级时间
            if (_otaElapsedTime != null) {
              _otaStatus += "\n⏱️ ${_otaTimeInfo}";
            }
            // 保存失败的升级记录
            _saveOtaRecord(
                '失败',
                _getSpeedDescription(
                    int.tryParse(_readIntervalController.text) ?? 0));
          } else if (status['state'] == 'aborted') {
            // 保存取消的升级记录
            _saveOtaRecord(
                '取消',
                _getSpeedDescription(
                    int.tryParse(_readIntervalController.text) ?? 0));
          }
        } else if ([
          'connecting',
          'scanning',
          'deviceFound',
          'connected',
          'starting',
          'progress',
          'reconnecting' // 🔥 新增重连状态
        ].contains(status['state'])) {
          _otaInProgress = true;

          // 从扫描开始就计时，这是OTA流程的真正开始
          if (['scanning', 'connecting', 'connected', 'starting', 'progress']
              .contains(status['state'])) {
            if (_otaStartTime == null) {
              print('开始OTA计时. 状态: ${status['state']}');
              _startOtaTimer();
            }
          }

          // 添加连接状态的详细信息
          if (status['state'] == 'connecting') {
            _otaStatus += "\n🔄 正在建立蓝牙连接...";
          } else if (status['state'] == 'deviceFound') {
            _otaStatus += "\n📱 找到目标设备，开始连接";
          } else if (status['state'] == 'connected') {
            _otaStatus += "\n✅ 设备连接成功，准备OTA";
          } else if (status['state'] == 'reconnecting') {
            // 🔥 新增重连状态的处理
            _otaStatus += "\n🔄 设备连接中断，正在智能重连...";
          }
        }
      });
    });

    _progressSubscription = TelinkOta.progressStream.listen((progress) {
      // iOS: 0~1(double)，Android: 0~100(int)
      final dynamic raw = progress['progress'];
      int percentage;
      if (raw is double) {
        // 仅当是 double 且在 0..1 内时按 iOS 处理
        if (raw >= 0.0 && raw <= 1.0) {
          percentage = (raw * 100).round();
        } else {
          // 异常 double，按 0..100 处理
          percentage = raw.round();
        }
      } else if (raw is int) {
        // Android 正常上报 0..100
        percentage = raw;
      } else if (raw is num) {
        // 兜底：其它 num 类型
        percentage = raw.round();
      } else {
        percentage = 0;
      }
      // 合法化边界
      if (percentage < 0) percentage = 0;
      if (percentage > 100) percentage = 100;
      print('OTA进度: $percentage%');

      // 🔥 计算传输统计
      _calculateTransferStats(percentage);

      setState(() {
        _otaProgress = percentage;
      });
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _progressSubscription?.cancel();
    _timeUpdateTimer?.cancel();
    _macController.dispose();
    _readIntervalController.dispose();
    super.dispose();
  }

  Future<void> initPlatformState() async {
    String platformVersion;
    try {
      platformVersion = await _otaUpgradePlugin.getPlatformVersion() ??
          'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  // 取消 OTA 升级
  Future<void> _cancelOtaUpgrade() async {
    try {
      print("===== 开始取消OTA升级 =====");

      // 立即更新UI状态，让用户知道取消操作正在进行
      setState(() {
        _otaStatus = "正在取消...";
        _otaInProgress = false; // 立即设置为false，禁用取消按钮避免重复点击
      });

      String result = await TelinkOta.cancelOta();
      print("OTA 取消结果: $result");

      // 重置计时器状态
      _timeUpdateTimer?.cancel();
      setState(() {
        _otaStartTime = null;
        _otaEndTime = null;
        _otaElapsedTime = null;
        _otaTimeInfo = "";
        _otaProgress = 0; // 重置进度
        // 🔥 重置传输统计
        _transferStats = "";
        _lastProgress = 0;
        _lastProgressTime = null;
      });

      print("===== OTA升级取消完成 =====");
    } catch (e) {
      print("取消 OTA 错误: $e");
      setState(() {
        _otaStatus = "取消失败: $e";
        _otaInProgress = false;
      });
    }
  }

  // 打印所有可用资产以进行调试
  Future<void> printAvailableAssets() async {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);
    print("可用资产列表:");
    for (var asset in manifestMap.keys) {
      print(" - $asset");
    }
  }

  Future<void> loadAndStartOta() async {
    await _loadAndStartOtaWithRetry(maxRetries: 3);
  }

  Future<void> _loadAndStartOtaWithRetry(
      {int maxRetries = 3, int currentAttempt = 1}) async {
    try {
      print("===== loadAndStartOta 开始 (尝试 $currentAttempt/$maxRetries) =====");

      // 🔥 重置OTA状态，清理可能的残留
      try {
        print("重置OTA状态...");
        await TelinkOta.resetOtaState();
        print("OTA状态重置完成");
      } catch (e) {
        print("重置OTA状态时出现警告: $e");
      }

      // 重置时间记录状态
      _timeUpdateTimer?.cancel();
      setState(() {
        _otaStartTime = null;
        _otaEndTime = null;
        _otaElapsedTime = null;
        _otaTimeInfo = "";
        // 🔥 重置传输统计
        _transferStats = "";
        _lastProgress = 0;
        _lastProgressTime = null;
      });
      print("已重置时间记录状态和传输统计");

      print("等待蓝牙适配器就绪...");
      bool adapterIsOn = await FlutterBluePlus.adapterState
          .map((s) => s == BluetoothAdapterState.on)
          .firstWhere((isOn) => isOn, orElse: () => false);

      if (!adapterIsOn) {
        print("蓝牙未开启或状态未知。");
        setState(() {
          _otaStatus = "错误: 蓝牙未开启";
          _otaInProgress = false;
        });
        return;
      }

      print("蓝牙适配器已就绪，直接启动OTA流程...");
      setState(() {
        _otaStatus = currentAttempt > 1
            ? "重试中 ($currentAttempt/$maxRetries)..."
            : "启动中...";
        _otaInProgress = true;
      });

      // 按照README.md的标准方法，直接调用TelinkOta.startOta
      // 不需要预先扫描，让原生层自己处理扫描和连接
      print("准备调用 TelinkOta.startOta...");
      final readInterval = int.tryParse(_readIntervalController.text) ?? 0;
      print(
          "使用速度设置: ${_getSpeedDescription(readInterval)} (readInterval: $readInterval)");

      // 备用计时启动 - 确保计时一定会开始
      if (_otaStartTime == null) {
        print('备用计时启动 - 在调用startOta前启动计时');
        _startOtaTimer();
      }

      // 🔥 添加延迟以确保设备完全准备好，特别是在连续OTA的情况下
      print('等待2秒以确保设备完全准备好接受新的OTA请求...');
      setState(() {
        _otaStatus = "等待设备准备完成...";
      });
      await Future.delayed(const Duration(seconds: 2));

      String result;
      if (Platform.isAndroid) {
        // Android 需要真实的 MAC 地址
        final mac = 'D8:5F:77:84:60:86';
        if (mac.isEmpty) {
          throw '请填写Android设备 MAC 地址后重试 (形如 11:22:33:44:55:66)';
        }
        result = await _startOtaAndroid(
          mac: mac,
          assetPath: 'assets/OTAV2.bin',
          readInterval: 8,
          timeout: 30,
        );
      } else {
        // iOS 走原有参数：deviceName + (可选)标识符
        result = await TelinkOta.startOta(
          macAddress: 'A728D090-7138-8AFE-308E-131CAEF85C93',
          deviceName: 'Leriphr_demo',
          filePath: 'assets/OTAV2.bin',
          fileInAsset: true,
          readInterval: readInterval,
          connectionTimeout: 10.0,
        );
      }
      print('TelinkOta.startOta 调用完成，结果: $result');

      print("===== loadAndStartOta 完成 =====");
    } catch (e) {
      print('loadAndStartOta 发生错误: $e');
      print('错误堆栈: ${StackTrace.current}');

      // 检查是否是连接超时错误且还有重试次数
      if (e.toString().contains('CONNECTION_TIMEOUT') &&
          currentAttempt < maxRetries) {
        print('连接超时，准备重试... (${currentAttempt + 1}/$maxRetries)');
        setState(() {
          _otaStatus = "连接超时，准备重试 (${currentAttempt + 1}/$maxRetries)...";
        });

        // 等待3秒后重试，给设备时间恢复
        await Future.delayed(const Duration(seconds: 3));

        // 检查用户是否在等待期间取消了操作
        if (_otaInProgress) {
          await _loadAndStartOtaWithRetry(
              maxRetries: maxRetries, currentAttempt: currentAttempt + 1);
        }
      } else {
        setState(() {
          _otaStatus = "错误: $e";
          _otaInProgress = false;
        });
      }
    }
  }

  // Android 专用：通过 MAC 地址发起 Telink OTA 升级
  Future<String> _startOtaAndroid({
    required String mac,
    required String assetPath,
    int readInterval = 8,
    double timeout = 15.0,
    String? serviceUUID,
    String? characteristicUUID,
  }) async {
    print(
        'Android OTA 启动: mac=$mac, asset=$assetPath, readInterval=$readInterval, timeout=$timeout');
    final result = await TelinkOta.startOta(
      macAddress: mac,
      filePath: assetPath,
      fileInAsset: true,
      readInterval: readInterval,
      connectionTimeout: timeout,
      serviceUUID: serviceUUID,
      characteristicUUID: characteristicUUID,
    );
    return result;
  }

  // 开始OTA计时
  void _startOtaTimer() {
    _otaStartTime = DateTime.now();
    _otaEndTime = null;
    _otaElapsedTime = null;
    _updateOtaTimeInfo();

    // 启动定时器，每秒更新一次显示的时间
    _timeUpdateTimer?.cancel();
    _timeUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_otaStartTime != null && _otaEndTime == null) {
        _updateOtaTimeInfo();
      }
    });
  }

  // 停止OTA计时
  void _stopOtaTimer() {
    _otaEndTime = DateTime.now();
    _timeUpdateTimer?.cancel();
    if (_otaStartTime != null && _otaEndTime != null) {
      _otaElapsedTime = _otaEndTime!.difference(_otaStartTime!);
    }
    _updateOtaTimeInfo();
  }

  // 保存升级记录到历史
  void _saveOtaRecord(String result, String speedMode) {
    print('准备保存OTA记录: $result, 速度模式: $speedMode');
    print('开始时间: $_otaStartTime, 结束时间: $_otaEndTime, 耗时: $_otaElapsedTime');

    final record = {
      'timestamp': (_otaStartTime ?? DateTime.now()).toIso8601String(),
      'startTime': _otaStartTime != null
          ? '${_otaStartTime!.hour.toString().padLeft(2, '0')}:${_otaStartTime!.minute.toString().padLeft(2, '0')}:${_otaStartTime!.second.toString().padLeft(2, '0')}'
          : '未知',
      'duration':
          _otaElapsedTime != null ? _formatDuration(_otaElapsedTime!) : '未记录',
      'result': result,
      'speedMode': speedMode,
      'progress': _otaProgress,
    };

    setState(() {
      _otaHistory.insert(0, record); // 最新的记录放在前面
      // 只保留最近20条记录
      if (_otaHistory.length > 20) {
        _otaHistory = _otaHistory.take(20).toList();
      }
    });

    print("OTA记录已保存: $record");
  }

  // 更新时间显示信息
  void _updateOtaTimeInfo() {
    if (!mounted) return;

    setState(() {
      if (_otaStartTime == null) {
        _otaTimeInfo = "";
      } else if (_otaEndTime == null) {
        // OTA进行中，显示已用时间
        final elapsed = DateTime.now().difference(_otaStartTime!);
        _otaTimeInfo = "已用时间: ${_formatDuration(elapsed)}";
      } else {
        // OTA已完成，显示总耗时
        _otaTimeInfo = "总耗时: ${_formatDuration(_otaElapsedTime!)}";
      }
    });
  }

  // 格式化时长显示
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final milliseconds = duration.inMilliseconds % 1000;

    if (minutes > 0) {
      return "${minutes}分${seconds}秒";
    } else if (seconds > 0) {
      return "${seconds}.${(milliseconds / 100).floor()}秒";
    } else {
      return "${milliseconds}毫秒";
    }
  }

  // 🔥 新增：计算传输统计
  void _calculateTransferStats(int currentProgress) {
    if (!mounted) return;

    final now = DateTime.now();

    if (_lastProgressTime != null && _lastProgress != currentProgress) {
      // 计算进度变化率
      final timeDiff = now.difference(_lastProgressTime!).inMilliseconds;
      final progressDiff = currentProgress - _lastProgress;

      if (timeDiff > 0 && progressDiff > 0) {
        // 计算传输速度 (百分比/秒)
        final speed = (progressDiff / timeDiff * 1000).toStringAsFixed(1);

        // 估算剩余时间
        final remainingProgress = 100 - currentProgress;
        final avgSpeed = progressDiff / (timeDiff / 1000);
        final estimatedRemaining =
            avgSpeed > 0 ? remainingProgress / avgSpeed : 0;

        // 计算包/秒
        final packetsPerSecond = (progressDiff / timeDiff * 1000).floor();

        setState(() {
          _transferStats = "速度: ${speed}%/秒 | ${packetsPerSecond}包/秒";
          if (estimatedRemaining > 0 && estimatedRemaining < 300) {
            // 只显示合理的估算
            _transferStats += "\n预计剩余: ${estimatedRemaining.toInt()}秒";
          }

          // 添加当前速度模式提示
          final readInterval = int.tryParse(_readIntervalController.text) ?? 0;
          _transferStats +=
              "\n当前: ${_getSpeedDescription(readInterval)} (间隔:$readInterval)";
        });
      }
    }

    _lastProgress = currentProgress;
    _lastProgressTime = now;
  }

  // 显示升级历史对话框
  void _showOtaHistory() {
    // 计算统计信息
    final successCount =
        _otaHistory.where((record) => record['result'] == '成功').length;
    final failureCount =
        _otaHistory.where((record) => record['result'] == '失败').length;
    final cancelCount =
        _otaHistory.where((record) => record['result'] == '取消').length;
    final successRate = _otaHistory.isNotEmpty
        ? (successCount / _otaHistory.length * 100).toStringAsFixed(1)
        : '0.0';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('OTA升级历史'),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                // 统计信息卡片
                if (_otaHistory.isNotEmpty)
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          const Text(
                            '统计信息',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatItem(
                                  '总计', '${_otaHistory.length}', Colors.blue),
                              _buildStatItem(
                                  '成功', '$successCount', Colors.green),
                              _buildStatItem('失败', '$failureCount', Colors.red),
                              _buildStatItem(
                                  '取消', '$cancelCount', Colors.orange),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('成功率: $successRate%',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                // 历史记录列表
                Expanded(
                  child: _otaHistory.isEmpty
                      ? const Center(child: Text('暂无升级记录'))
                      : ListView.builder(
                          itemCount: _otaHistory.length,
                          itemBuilder: (context, index) {
                            final record = _otaHistory[index];
                            final resultColor = record['result'] == '成功'
                                ? Colors.green
                                : record['result'] == '失败'
                                    ? Colors.red
                                    : Colors.orange;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                title: Row(
                                  children: [
                                    Icon(
                                      record['result'] == '成功'
                                          ? Icons.check_circle
                                          : record['result'] == '失败'
                                              ? Icons.error
                                              : Icons.cancel,
                                      color: resultColor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${record['result']} - ${record['duration']}',
                                      style: TextStyle(
                                        color: resultColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('开始时间: ${record['startTime']}'),
                                    Text('速度模式: ${record['speedMode']}'),
                                    Text('进度: ${record['progress']}%'),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _otaHistory.clear();
                });
                Navigator.of(context).pop();
              },
              child: const Text('清空历史'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  // 构建统计项widget
  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  // 根据readInterval值获取速度描述
  String _getSpeedDescription(int readInterval) {
    if (readInterval == 0) {
      return '🚀 极速模式';
    } else if (readInterval <= 12) {
      return '⚡ 快速模式';
    } else if (readInterval <= 32) {
      return '🛡️ 稳定模式';
    } else {
      return '🐌 超稳定模式';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 注意这里直接返回 Scaffold 而不是 MaterialApp
      appBar: AppBar(
        title: const Text('Telink OTA 示例'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text('系统平台: $_platformVersion\n'),

            // MAC 地址输入
            TextField(
              controller: _macController,
              decoration: const InputDecoration(
                labelText: '设备 MAC 地址',
                hintText: '输入设备 MAC 地址 (例如: 11:22:33:44:55:66)',
              ),
              enabled: !_otaInProgress,
            ),
            const SizedBox(height: 24),

            // 状态和进度
            Text(
              'OTA 状态: $_otaStatus',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // 添加时间显示
            if (_otaTimeInfo.isNotEmpty)
              Text(
                _otaTimeInfo,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (_otaTimeInfo.isNotEmpty) const SizedBox(height: 8),

            // 🔥 新增：传输统计显示
            if (_transferStats.isNotEmpty && _otaInProgress)
              Text(
                _transferStats,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (_transferStats.isNotEmpty && _otaInProgress)
              const SizedBox(height: 8),

            LinearProgressIndicator(
              value: _otaProgress / 100,
              minHeight: 10,
            ),
            Text('进度: $_otaProgress%'),
            const SizedBox(height: 24),

            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: loadAndStartOta,
                  child: const Text('开始升级'),
                ),
                ElevatedButton(
                  onPressed: _otaInProgress ? _cancelOtaUpgrade : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('取消升级'),
                ),
              ],
            ),
            ElevatedButton(
              onPressed: printAvailableAssets,
              child: const Text('打印可用资产'),
            ),
            ElevatedButton(
              onPressed: _showOtaHistory,
              child: Text('查看升级历史 (${_otaHistory.length})'),
            ),

            if (_otaHistory.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '最近升级: ${_otaHistory.first['result']} (${_otaHistory.first['duration']})',
                  style: TextStyle(
                    fontSize: 12,
                    color: _otaHistory.first['result'] == '成功'
                        ? Colors.green
                        : _otaHistory.first['result'] == '失败'
                            ? Colors.red
                            : Colors.orange,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
