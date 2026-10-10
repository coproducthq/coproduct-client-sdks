import 'package:flutter/services.dart';

import 'native_paywall_bridge.dart';

/// The Dart side of the CoproductPaywallPlugin (iOS-only StoreKit2 bridge).
/// Request and response only, with no state of its own -- mirrors
/// coproduct's HostContextChannel in shape.
class MethodChannelPaywallBridge implements NativePaywallBridge {
  const MethodChannelPaywallBridge();

  static const _channel = MethodChannel('app.coproduct.flutter/paywall');

  @override
  Future<String> priceFor(String productId) async {
    try {
      final price = await _channel.invokeMethod<String>('priceFor', {'productId': productId});
      if (price == null) throw const PaywallBridgeUnavailable();
      return price;
    } on MissingPluginException {
      throw const PaywallBridgeUnavailable();
    }
  }

  @override
  Future<PurchaseResult> purchase(String productId) async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMethod<Map<Object?, Object?>>('purchase', {'productId': productId});
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
        .map((entry) => _restoredTransactionFromChannel(entry! as Map<Object?, Object?>))
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

RestoredTransaction _restoredTransactionFromChannel(Map<Object?, Object?> raw) {
  return RestoredTransaction(
    transactionId: raw['transactionId'] as String,
    productId: raw['productId'] as String,
    purchaseDate: _parseChannelDate(raw['purchaseDate'])!,
    expirationDate: _parseChannelDate(raw['expirationDate']),
  );
}

// Swift sends milliseconds-since-epoch (Int) for every date, matching
// StandardMethodCodec's native number representation -- no string date
// parsing crosses the bridge
DateTime? _parseChannelDate(Object? raw) {
  if (raw == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(raw as int, isUtc: true);
}
