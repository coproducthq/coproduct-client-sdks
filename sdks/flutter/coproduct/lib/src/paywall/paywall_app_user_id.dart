import '../coproduct_client.dart';

/// Picks the id a paywall records purchases and reads entitlements under.
///
/// An [appUserId] the app passed wins. Otherwise it is the SDK's anonymous id,
/// from the client of the nearest `CoproductScope` when there is one, else
/// from the running SDK. Null when none of them has an id, which means the SDK
/// is not initialized
String? resolvePaywallAppUserId({
  String? appUserId,
  CoproductClient? scopedClient,
  CoproductClient? currentClient,
}) => appUserId ?? scopedClient?.anonymousId ?? currentClient?.anonymousId;
