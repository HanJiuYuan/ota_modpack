
import 'ota_upgrade_platform_interface.dart';

class OtaUpgrade {
  Future<String?> getPlatformVersion() {
    return OtaUpgradePlatform.instance.getPlatformVersion();
  }
}
