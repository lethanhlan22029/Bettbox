import 'package:bett_box/models/models.dart';
import 'identity.dart';

/// Keep local selection and layout while accepting only subscription metadata.
Profile mergeMetronSubscription(Profile current, Profile downloaded) =>
    current.copyWith(
      label: AppIdentity.brandName,
      url: downloaded.url,
      lastUpdateDate: downloaded.lastUpdateDate,
      subscriptionInfo: downloaded.subscriptionInfo,
      isUpdating: false,
    );
