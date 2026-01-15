
这个 Flutter 插件提供了通过蓝牙低功耗 (BLE) 进行固件空中升级 (OTA) 的功能，专为 **Telink (泰凌微)** 及 **Nordic** 系列蓝牙芯片设计。

## ✨ 主要功能

- 🚀 **固件更新**：支持 Telink/Nordic BLE 设备固件更新。
- 📊 **状态监控**：实时提供 OTA 进度和状态回调。
- 📂 **灵活加载**：支持从应用资源 (Assets) 或本地文件系统加载固件。
- ⚡ **高度可配置**：支持自定义连接参数、读取间隔和超时设置。
- 🛠 **故障恢复**：内置蓝牙缓存清理、强制扫描等故障恢复机制。
- 📱 **多平台支持**：完美适配 Android 和 iOS (解决了 iOS 蓝牙缓存和 UUID 扫描痛点)。

---

## 🔧 安装与配置

### 1. 添加依赖

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  ota_upgrade: ^latest_version
```

### 2. 平台配置

#### 🤖 Android 设置

在 `android/app/src/main/AndroidManifest.xml` 中添加以下权限：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="你的包名">
    <!-- 基础蓝牙权限 -->
    <uses-permission android:name="android.permission.BLUETOOTH"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
    
    <!-- Android 12+ 需要的新权限 -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    
    <!-- 位置权限 (用于扫描) -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="30" />
</manifest>
```

#### 🍎 iOS 设置

在 `ios/Runner/Info.plist` 中添加蓝牙权限描述：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>此应用需要蓝牙权限以进行固件升级</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>此应用需要蓝牙权限以进行固件升级</string>
```

---

## 🚀 使用指南

### 1. 初始化与引入

```dart
import 'package:ota_upgrade/telink/telink_ota.dart';
```

### 2. 启动 OTA 升级

**Android 示例：**

```dart
try {
  final result = await TelinkOta.startOta(
    macAddress: '20:20:20:20:20:20', // Android 使用 MAC 地址
    filePath: 'assets/firmware.bin',
    fileInAsset: true,
    readInterval: 16,
  );
  print('OTA请求结果: $result');
} catch (e) {
  print('OTA错误: $e');
}
```

**iOS 示例 (支持设备名称匹配)：**

```dart
try {
  final result = await TelinkOta.startOta(
    macAddress: 'A728D090-7138-8AFE-308E-131CAEF85C93', // iOS 使用 UUID
    deviceName: 'Leriphr_demo',        // 可选：用于辅助扫描匹配
    filePath: 'assets/firmware.bin',
    fileInAsset: true,
    readInterval: 16,                  // 0 表示最快速度
    connectionTimeout: 10.0,           // iOS 专属连接超时设置
  );
  print('OTA请求结果: $result');
} catch (e) {
  print('OTA错误: $e');
}
```

### 3. 监听状态与进度

```dart
// 监听 OTA 状态
TelinkOta.statusStream.listen((status) {
  print('当前状态: ${status['state']}');
  if (status['errorMessage'] != null) {
    print('错误信息: ${status['errorMessage']}');
  }
});

// 监听进度 (自动处理 iOS 0-1 的进度值)
TelinkOta.progressStream.listen((progress) {
  num progressValue = progress['progress'] ?? 0;
  int percentage = (progressValue * 100).round();
  print('进度: $percentage%');
});
```

### 4. 取消 OTA

```dart
try {
  await TelinkOta.cancelOta();
  print('OTA 已取消');
} catch (e) {
  print('取消失败: $e');
}
```

---

## 🛠 故障排除与高级功能

当 OTA 失败或设备无法被扫描到时，本插件提供了一系列高级修复功能。

### 自动扫描重置 (v2.0+)
✨ **特性**：每次调用 `startOta` 时，插件会自动重置蓝牙扫描状态并清理缓存，通常无需手动干预。

### 手动故障修复方法

如果不自动恢复，可按以下顺序尝试：

1.  **重置蓝牙缓存 (iOS)**
    ```dart
    await TelinkOta.resetBluetoothCache();
    ```
2.  **重置扫描状态**
    ```dart
    await TelinkOta.resetScanState();
    ```
3.  **强制深度扫描**
    ```dart
    // 强制扫描30秒，寻找指定设备
    await TelinkOta.forceScanDevices(
      scanDuration: 30.0,
      deviceName: 'Leriphr_demo', // 可选
      macAddress: '...',          // 可选
    );
    ```

### 🚨 常见问题解决方案 (FAQ)

**Q: 设备在广播，但 App 搜不到？**
> **A:** 这是 iOS 蓝牙缓存导致的常见问题。
> 1. 调用 `TelinkOta.resetBluetoothCache()`。
> 2. 如果失败，尝试**物理重启设备**（断电重连）。

**Q: OTA 失败后设备失联？**
> **A:** 设备可能进入了 DFU 模式或改名了（如变为 "DFU_xxxx"）。
> 1. 使用 `forceScanDevices()` 查看控制台打印的所有设备。
> 2. 更新代码中的 `deviceName` 或 `macAddress` 进行重连。

---

## ⚡ 速度与性能优化

可以通过调整 `readInterval` 参数来平衡速度与稳定性：

| readInterval 值 | 模式 | 描述 | 适用场景 |
| :--- | :--- | :--- | :--- |
| **0** | 极速模式 | 写入间隔 1ms | 信号极好，追求最快速度 |
| **1 - 8** | 平衡模式 | 写入间隔 10ms | 推荐默认设置 (建议从 4 开始) |
| **> 8** | 稳定模式 | 写入间隔 20ms | 干扰严重或连接不稳定时使用 |

> **建议**：默认从 `readInterval = 4` 开始尝试。如果传输失败，增加到 8 或 16。对于 2 分钟的文件，使用 `0` 可能缩短至 30-60 秒。

---

## 📚 API 参考

### `TelinkOta.startOta`

| 参数名 | 类型 | 必需 | 默认 | 描述 |
| :--- | :--- | :--- | :--- | :--- |
| `macAddress` | String | ✅ | - | Android 传 MAC 地址，iOS 传 UUID |
| `filePath` | String | ✅ | - | 固件文件路径 |
| `fileInAsset` | bool | ❌ | `false` | 是否从 Assets 加载 |
| `deviceName` | String | ❌ | `null` | 设备广播名 (iOS 辅助扫描用) |
| `readInterval` | int | ❌ | `8` | 读取间隔 (0 为最快) |
| `connectionTimeout`| double | ❌ | `15.0` | 连接超时秒数 (仅 iOS) |
| `serviceUUID` | String | ❌ | Default | 自定义服务 UUID |
| `characteristicUUID`| String | ❌ | Default | 自定义特征 UUID |

### OTA 状态枚举

| 状态 | 含义 |
| :--- | :--- |
| `scanning` | 正在扫描设备 (iOS) |
| `deviceFound` | 已发现目标设备 |
| `connecting` | 正在建立连接 |
| `connected` | 连接成功 |
| `starting` | OTA 开始 |
| `progress` | 正在传输数据 |
| `completed` | ✅ 升级成功 (设备将重启) |
| `failed` | ❌ 升级失败 |
| `aborted` | ⏹ 用户手动取消 |

---

## 📱 完整示例代码

<details>
<summary>点击展开完整 Widget 示例</summary>

```dart
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
        readInterval: 4, 
      );
      print('OTA Result: $result');
    } catch (e) {
      print('OTA Error: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OTA Demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Status: $_status'),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _progress / 100),
            Text('$_progress%'),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _otaRunning ? null : _startOta,
              child: const Text('Start OTA'),
            ),
          ],
        ),
      ),
    );
  }
}
```
</details>
```