import 'package:package_info_plus/package_info_plus.dart';

const subscriptionUserAgent = 'FlClash/ClashMetaForAndroid/maomaoyun';

extension PackageInfoExtension on PackageInfo {
  String get ua => subscriptionUserAgent;
}
