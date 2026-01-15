这个Flutter插件提供了通过蓝牙进行固件空中升级(OTA)的功能，特别针对Telink/nordic系列蓝牙芯片设计。
功能特点:
支持Telink BLE设备固件更新
提供进度和状态监控
支持从应用资产或本地文件系统加载固件文件
支持取消进行中的OTA操作
高度可配置的连接参数
平台设置
Android
添加以下权限到 android/app/src/main/AndroidManifest.xml:
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" 
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" 
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" 
    android:maxSdkVersion="30" />

iOS
在 ios/Runner/Info.plist 中添加蓝牙权限：
<key>NSBluetoothAlwaysUsageDescription</key>
<string>此应用需要蓝牙权限以进行固件升级</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>此应用需要蓝牙权限以进行固件升级</string>
Telink系列蓝牙芯片使用方法
初始化
import 'package:ota_upgrade/telink/telink_ota.dart';
启动OTA升级
try {
  final result = await TelinkOta.startOta(
    macAddress: '20:20:20:20:20:20',  // 设备MAC地址
    filePath: 'assets/firmware.bin',   // 固件文件路径
    fileInAsset: true,                 // 从应用资产加载
    readInterval: 16,                  // 读取间隔
    connectionTimeout: 10.0,           // 连接超时时间（秒），默认15秒
  );
  print('OTA请求结果: $result');
} catch (e) {
  print('OTA错误: $e');
}

iOS特有的使用方法：
// iOS平台支持设备名称匹配和连接超时设置
try {
  final result = await TelinkOta.startOta(
    macAddress: 'A728D090-7138-8AFE-308E-131CAEF85C93',  // 设备UUID (iOS使用UUID而非MAC地址)
    deviceName: 'Leriphr_demo',        // 设备广播名称 (iOS扫描用，可选)
    filePath: 'assets/firmware.bin',   // 固件文件路径
    fileInAsset: true,                 // 从应用资产加载
    readInterval: 16,                  // 读取间隔，0表示最快速度
    connectionTimeout: 10.0,           // 连接超时时间（秒），默认15秒
  );
  print('OTA请求结果: $result');
} catch (e) {
  print('OTA错误: $e');
}
监听OTA状态
TelinkOta.statusStream.listen((status) {
  print('OTA状态: ${status['state']}');
  if (status['errorMessage'] != null) {
    print('错误信息: ${status['errorMessage']}');
  }
});
监听OTA进度
TelinkOta.progressStream.listen((progress) {
  setState(() {
    // 处理iOS平台的0-1范围进度值
    num progressValue = progress['progress'] ?? 0;
    _progress = (progressValue * 100).round();
  });
});
取消正在进行的OTA
try {
  final result = await TelinkOta.cancelOta();
  print('取消OTA结果: $result');
} catch (e) {
  print('取消失败: $e');
}

故障排除功能
当OTA升级失败后设备无法被扫描到时，可以使用以下功能：

强制扫描设备
// 强制扫描30秒，寻找指定设备
try {
  final result = await TelinkOta.forceScanDevices(
    scanDuration: 30.0,              // 扫描时长（秒）
    deviceName: 'Leriphr_demo',      // 目标设备名称（可选）
    macAddress: 'A728D090-7138-8AFE-308E-131CAEF85C93', // 目标设备MAC（可选）
  );
  print('强制扫描结果: $result');
} catch (e) {
  print('强制扫描错误: $e');
}

重置蓝牙缓存
// 清理iOS蓝牙缓存，解决连接问题
try {
  final result = await TelinkOta.resetBluetoothCache();
  print('蓝牙重置结果: $result');
} catch (e) {
  print('蓝牙重置错误: $e');
}

重置蓝牙扫描状态
// 解决设备广播但程序搜索不到的问题
try {
  final result = await TelinkOta.resetScanState();
  print('扫描状态重置结果: $result');
} catch (e) {
  print('重置扫描状态错误: $e');
}

推荐的故障排除流程：
1. **立即尝试**: 如果OTA失败，首先重启设备（物理重启）
2. **重置蓝牙**: 调用 `resetBluetoothCache()` 清理iOS蓝牙缓存
3. **强制扫描**: 使用 `forceScanDevices()` 进行长时间扫描（30秒）
4. **检查设备状态**: 确认设备是否改变了广播名称或进入特殊模式
5. **重新尝试**: 找到设备后重新进行OTA升级

**🔧 常见问题解决方案**

**问题：设备在广播但程序搜索不到（最常见）**
- **症状**: 设备确实在广播，但iOS应用无法发现设备，必须重启应用才能找到
- **原因**: iOS蓝牙扫描缓存没有正确重置，设备数组状态混乱
- **解决方案**: 
  - **自动解决**: 每次调用 `TelinkOta.startOta()` 时会自动重置扫描状态
  - **手动解决**: 调用 `TelinkOta.resetScanState()` 方法
- **原理**: 该方法会完全重置iOS蓝牙扫描状态，清理设备缓存数组，重新开始扫描

**✨ 自动扫描重置功能**
从v2.0开始，插件在每次开始OTA时会自动执行以下操作：
1. 重置蓝牙扫描状态
2. 清理设备缓存数组
3. 重新开始扫描
4. 确保能够发现目标设备

这意味着用户通常不需要手动处理"设备找不到"的问题。

API参数说明
TelinkOta.startOta
| 参数名 | 类型 | 必需 | 描述 |
| --- | --- | --- | --- |
| macAddress | String | 是 | 设备的MAC地址，格式为"XX:XX:XX:XX:XX:XX"（Android）或设备UUID（iOS） |
| deviceName | String | 否 | 设备广播名称，iOS平台用于扫描匹配，Android平台忽略 |
| filePath | String | 是 | 固件文件路径。如果fileInAsset为true，则是应用资产中的路径 |
| fileInAsset | bool | 否 | 指定文件是否位于应用资产中，默认为false |
| readInterval | int | 否 | OTA过程中的读取间隔，默认为8，较大的值可能提高稳定性，0表示最快速度 |
| connectionTimeout | double | 否 | 连接超时时间（秒），默认为15秒，仅iOS平台支持 |
| serviceUUID | String | 否 | 自定义服务UUID，不提供则使用默认值 |
| characteristicUUID | String | 否 | 自定义特性UUID，不提供则使用默认值 |
OTA状态说明
| 状态 | 描述 |
| --- | --- |
| scanning | 正在扫描设备（仅iOS） |
| deviceFound | 发现目标设备（仅iOS） |
| connecting | 正在连接到设备 |
| connected | 设备连接成功（仅iOS） |
| discoveringServices | 连接成功，正在发现服务 |
| starting | OTA过程开始 |
| progress | OTA数据传输中 |
| completed | OTA成功完成，设备会重启应用新固件，连接断开是正常现象 |
| failed | OTA失败，查看errorMessage获取详细错误 |
| aborted | OTA被手动取消 |
| cancelling | 正在取消OTA |
完整示例


class OtaPage extends StatefulWidget {
  @override
  State<OtaPage> createState() => _OtaPageState();
}

class _OtaPageState extends State<OtaPage> {
  String _status = '准备';
  int _progress = 0;
  bool _otaRunning = false;
  
  @override
  void initState() {
    super.initState();
    _setupOtaListeners();
  }
  
  void _setupOtaListeners() {
    TelinkOta.statusStream.listen((status) {
      setState(() {
        _status = '${status['state']}';
        if (status['errorMessage'] != null) {
          _status += ': ${status['errorMessage']}';
        }
        
        _otaRunning = !['completed', 'failed', 'aborted'].contains(status['state']);
      });
    });
    
    TelinkOta.progressStream.listen((progress) {
      setState(() {
        // 处理iOS平台的0-1范围进度值
        num progressValue = progress['progress'] ?? 0;
        _progress = (progressValue * 100).round();
      });
    });
  }
  
  Future<void> _startOta() async {
    try {
      final result = await TelinkOta.startOta(
        macAddress: '20:20:20:20:20:20',
        filePath: 'assets/firmware.bin',
        fileInAsset: true,
        readInterval: 16,
      );
      print('OTA请求结果: $result');
    } catch (e) {
      print('OTA错误: $e');
    }
  }
  
  Future<void> _cancelOta() async {
    try {
      final result = await TelinkOta.cancelOta();
      print('取消结果: $result');
    } catch (e) {
      print('取消错误: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OTA升级示例')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('状态: $_status', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _progress / 100),
            Text('$_progress%'),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _otaRunning ? null : _startOta,
              child: const Text('开始OTA'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _otaRunning ? _cancelOta : null,
              child: const Text('取消OTA'),
            ),
          ],
        ),
      ),
    );
  }
}
故障排除
如果遇到连接中断或OTA失败，请尝试：
1.增加读取间隔 (readInterval 参数)
2.确保设备电量充足
3.减少设备与手机之间的距离
4.避免在其他蓝牙设备活跃的环境中进行OTA
5.确认固件文件是否与设备匹配

速度优化建议：
• **iOS和Android平台都支持动态速度控制**：readInterval参数现在在iOS中也真正有效！
• 速度模式说明：
  - `readInterval = 0`: 最快速度模式（写入间隔1ms，读取间隔16包）
  - `readInterval = 1-8`: 平衡模式（写入间隔10ms，读取间隔为设定值）
  - `readInterval > 8`: 稳定模式（写入间隔20ms，读取间隔为设定值）
• 推荐设置：从 readInterval = 4 开始尝试，如果传输失败可增加到8或16
• 对于2分钟的传输，使用 readInterval = 0 可能减少到30-60秒

iOS平台特有问题：
6.如果连接超时，尝试增加 connectionTimeout 参数（默认15秒）
7.确保设备处于广播状态且信号强度足够
8.使用设备名称(deviceName)参数可提高扫描成功率
9.OTA完成后设备断开连接是正常现象，表示设备正在重启应用新固件
10.如果反复连接失败，尝试关闭并重新打开设备蓝牙

**🚨 OTA失败后设备找不到的解决方案：**

这是最常见的问题！当OTA过程中断后，设备可能会：
- 进入特殊的恢复模式或DFU模式
- 改变广播名称（如从"Leriphr_demo"变为"DFU_Leriphr"或"Recovery_xxx"）
- 改变广播UUID或服务特征
- 暂时停止广播，需要手动重启

**解决步骤：**
1. **物理重启设备** - 断电重启让设备回到正常状态（最重要！）
2. **使用重置蓝牙功能** - 调用 `TelinkOta.resetBluetoothCache()` 清理iOS蓝牙缓存
3. **使用强制扫描功能** - 调用 `TelinkOta.forceScanDevices()` 进行30秒深度扫描
4. **检查扫描结果** - 设备可能以不同名称出现，查看控制台日志中的所有发现设备
5. **更新设备信息** - 如果发现设备名称或UUID改变，更新代码中的参数
6. **等待设备恢复** - 有些设备需要几分钟才能完全恢复到正常状态

**预防措施：**
- 确保设备电量充足（推荐>50%）
- 保持设备距离很近（<1米）
- 避免在蓝牙干扰环境中进行OTA
- 使用较慢的传输速度（readInterval >= 8）提高稳定性
- OTA前确保设备处于稳定的连接状态