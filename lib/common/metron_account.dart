import 'dart:math' as math;

/// Panel account data; membership expiry is separate from login token expiry.
class MetronAccount {
  const MetronAccount({
    this.name,
    this.level,
    this.levelName,
    this.membershipExpiresAt,
    this.membershipUnlimited = false,
    this.accountExpiresAt,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.speedLimitMbps,
    this.deviceLimit,
  });

  final String? name;
  final int? level;
  final String? levelName;
  final DateTime? membershipExpiresAt;
  final bool membershipUnlimited;
  final DateTime? accountExpiresAt;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final num? speedLimitMbps;
  final int? deviceLimit;

  List<String> alertsAt(DateTime now) {
    final alerts = <String>[];
    if (level != null && level! <= 0) {
      alerts.add(level! < 0 ? '尚未开通会员，可前往面板选择套餐' : '会员已到期，请及时续费');
    } else if (!membershipUnlimited && membershipExpiresAt != null) {
      final remaining = membershipExpiresAt!.difference(now);
      if (remaining <= Duration.zero) {
        alerts.add('会员已到期，请及时续费');
      } else if (remaining <= const Duration(days: 3)) {
        alerts.add('会员即将到期，请及时续费');
      }
    }
    if (remainingBytes != null && totalBytes != null) {
      if (remainingBytes == 0) {
        alerts.add('可用流量已耗尽，请查看套餐或流量包');
      } else if (totalBytes! > 0 && remainingBytes! / totalBytes! <= .1) {
        alerts.add('剩余流量不足 10%，请注意用量');
      }
    }
    return alerts;
  }

  int? get usedBytes => uploadBytes == null || downloadBytes == null
      ? null
      : uploadBytes! + downloadBytes!;
  int? get remainingBytes => totalBytes == null || usedBytes == null
      ? null
      : math.max(0, totalBytes! - usedBytes!);
  double? get usedFraction => totalBytes == null || usedBytes == null
      ? null
      : totalBytes == 0
      ? (usedBytes! > 0 ? 1 : 0)
      : (usedBytes! / totalBytes!).clamp(0, 1).toDouble();

  static MetronAccount? parse(Object? value) {
    if (value is! Map) return null;
    String? text(Object? raw) =>
        raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
    num? number(Object? raw) {
      final parsed = num.tryParse('$raw');
      return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
    }

    DateTime? date(Object? raw) {
      final seconds = number(raw);
      if (seconds == null || seconds <= 0 || seconds > 8640000000000) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(
        (seconds * 1000).toInt(),
        isUtc: true,
      ).toLocal();
    }

    return MetronAccount(
      name: text(value['name']),
      level: int.tryParse('${value['level']}'),
      levelName: text(value['level_name']),
      membershipExpiresAt: date(value['membership_expire_at']),
      membershipUnlimited: value['membership_unlimited'] == true,
      accountExpiresAt: date(value['account_expire_at']),
      uploadBytes: number(value['upload_bytes'])?.toInt(),
      downloadBytes: number(value['download_bytes'])?.toInt(),
      totalBytes: number(value['total_bytes'])?.toInt(),
      speedLimitMbps: number(value['speed_limit_mbps']),
      deviceLimit: number(value['device_limit'])?.toInt(),
    );
  }
}
