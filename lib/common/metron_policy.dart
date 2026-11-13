import 'package:bett_box/enum/enum.dart';

const metronUsagePages = {
  PageLabel.dashboard,
  PageLabel.proxies,
  PageLabel.connections,
  PageLabel.account,
  PageLabel.support,
};

// These tiles open editors or advanced configuration sheets directly, without
// going through the sidebar. Filter saved layouts and the add-widget catalog.
const metronHiddenDashboardWidgets = {
  DashboardWidget.snifferOverride,
  DashboardWidget.ntpOverride,
  DashboardWidget.providersInfo,
  DashboardWidget.onlinePanel,
  DashboardWidget.ipv6Switch,
  DashboardWidget.wakelockSwitch,
  DashboardWidget.fcmStatus,
};
