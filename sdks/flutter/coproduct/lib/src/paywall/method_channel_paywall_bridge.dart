import 'package:flutter/services.dart';

import 'native_paywall_bridge.dart';

/// The Dart side of the CoproductPaywallPlugin: StoreKit 2 on iOS and
/// Google Play Billing on Android, over one method channel. Request and
/// response only, with no state of its own -- mirrors coproduct's
/// HostContextChannel in shape.
class MethodChannelPaywallBridge
    implements NativePaywallBridge, PackageResolvingBridge {
  const MethodChannelPaywallBridge();

  static const _channel = MethodChannel('app.coproduct.flutter/paywall');

  @override
  Future<String> priceFor(String productId, PackageKind kind) async {
    try {
      final price = await _channel.invokeMethod<String>('priceFor', {
        'productId': productId,
        'kind': kind.name.toUpperCase(),
      });
      if (price == null) throw const PaywallBridgeUnavailable();
      return price;
    } on MissingPluginException {
      throw const PaywallBridgeUnavailable();
    }
  }

  @override
  Future<PaywallPackageRuntime> packageFor(
    String productId,
    PackageKind kind,
  ) async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMethod<Map<Object?, Object?>>('packageFor', {
        'productId': productId,
        'kind': kind.name.toUpperCase(),
      });
    } on MissingPluginException {
      throw const PaywallBridgeUnavailable();
    }
    if (raw == null) throw const PaywallBridgeUnavailable();
    return _packageRuntimeFromChannel(raw);
  }

  @override
  Future<PurchaseResult> purchase(String productId, PackageKind kind) async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMethod<Map<Object?, Object?>>('purchase', {
        'productId': productId,
        'kind': kind.name.toUpperCase(),
      });
    } on MissingPluginException {
      throw const PaywallBridgeUnavailable();
    }
    if (raw == null) throw const PaywallBridgeUnavailable();
    return _purchaseResultFromChannel(raw);
  }

  @override
  Future<List<RestoredTransaction>> restore() async {
    final List<Object?>? raw;
    try {
      raw = await _channel.invokeMethod<List<Object?>>('restore');
    } on MissingPluginException {
      throw const PaywallBridgeUnavailable();
    }
    if (raw == null) return const [];
    return raw
        .map(
          (entry) =>
              _restoredTransactionFromChannel(entry! as Map<Object?, Object?>),
        )
        .toList();
  }
}

PurchaseResult _purchaseResultFromChannel(Map<Object?, Object?> raw) {
  final outcome = switch (raw['outcome'] as String?) {
    'success' => PurchaseOutcome.success,
    'cancelled' => PurchaseOutcome.cancelled,
    'pending' => PurchaseOutcome.pending,
    final other => throw StateError('Unknown purchase outcome: $other'),
  };
  return PurchaseResult(
    outcome: outcome,
    transactionId: raw['transactionId'] as String?,
    productId: raw['productId'] as String?,
    purchaseDate: _parseChannelDate(raw['purchaseDate']),
    expirationDate: _parseChannelDate(raw['expirationDate']),
  );
}

PaywallPackageRuntime _packageRuntimeFromChannel(Map<Object?, Object?> raw) {
  final introRaw = raw['intro'] as Map<Object?, Object?>?;
  return PaywallPackageRuntime(
    price: raw['price'] as String,
    intro: introRaw == null
        ? null
        : PaywallIntroOffer(
            eligible: introRaw['eligible'] as bool,
            label: introRaw['label'] as String,
          ),
  );
}

RestoredTransaction _restoredTransactionFromChannel(Map<Object?, Object?> raw) {
  return RestoredTransaction(
    transactionId: raw['transactionId'] as String,
    productId: raw['productId'] as String,
    purchaseDate: _parseChannelDate(raw['purchaseDate'])!,
    expirationDate: _parseChannelDate(raw['expirationDate']),
  );
}

// The native side (Swift or Kotlin) sends milliseconds-since-epoch (Int)
// for every date, matching StandardMethodCodec's native number
// representation -- no string date parsing crosses the bridge
DateTime? _parseChannelDate(Object? raw) {
  if (raw == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(raw as int, isUtc: true);
}
