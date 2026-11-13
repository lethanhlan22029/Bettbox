import 'client_config.g.dart';

const _useDevIdentity = bool.fromEnvironment('APP_DEV');
const _useLiteBuild = bool.fromEnvironment('APP_LITE');

class AppIdentity {
  static const isDev = _useDevIdentity;
  static const isLite = _useLiteBuild;

  static const productName = 'Bettbox';
  static const devSuffix = 'Dev';
  static const packageId = 'com.appshub.bettbox';

  static const compactName = isDev ? '$productName$devSuffix' : productName;
  static const brandName = String.fromEnvironment(
    'APP_DISPLAY_NAME',
    defaultValue: ClientDefaults.displayName,
  );
  // Preserve existing scheduled tasks/registry entries across the rebrand.
  static const launchRegistrationName = isDev
      ? '$productName $devSuffix'
      : productName;
  static const displayName = isDev ? '$brandName 测试版' : brandName;
  static const mainExecutableName = productName;
  static const coreExecutableName = '${compactName}Core';
  static const dataDirName = compactName;
  static const tunDeviceName = compactName;
}

class WindowsHelperIdentity {
  static const serviceName = '${AppIdentity.compactName}HelperService';
  static const pipeName = '\\\\.\\pipe\\${AppIdentity.compactName}.Helper';
}
