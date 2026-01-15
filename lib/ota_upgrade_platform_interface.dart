import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'ota_upgrade_method_channel.dart';

abstract class OtaUpgradePlatform extends PlatformInterface {
  /// Constructs a OtaUpgradePlatform.
  OtaUpgradePlatform() : super(token: _token);

  static final Object _token = Object();

  static OtaUpgradePlatform _instance = MethodChannelOtaUpgrade();

  /// The default instance of [OtaUpgradePlatform] to use.
  ///
  /// Defaults to [MethodChannelOtaUpgrade].
  static OtaUpgradePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [OtaUpgradePlatform] when
  /// they register themselves.
  static set instance(OtaUpgradePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
