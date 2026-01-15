import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ota_upgrade_platform_interface.dart';

/// An implementation of [OtaUpgradePlatform] that uses method channels.
class MethodChannelOtaUpgrade extends OtaUpgradePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('ota_upgrade');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
