import 'dart:convert';

/// The native-capability actions the platform script can trigger by
/// navigating to a coproduct-action: URL, intercepted by the WebView's
/// navigation delegate and never actually navigated.
sealed class CoproductAction {
  const CoproductAction();

  static CoproductAction? parse(String url) {
    if (!url.startsWith('coproduct-action:')) return null;

    final withoutScheme = url.substring('coproduct-action:'.length);
    final parts = withoutScheme.split('?');
    final action = parts[0];
    final params = parts.length > 1 ? Uri.splitQueryString(parts[1]) : <String, String>{};

    switch (action) {
      case 'requestPermission':
        return RequestPermissionAction(params['permission'] ?? '');
      case 'openUrl':
        return OpenUrlAction(params['url'] ?? '');
      case 'dismiss':
        return const DismissAction();
      case 'complete':
        return const CompleteAction();
      case 'showPaywall':
        return ShowPaywallAction(params['paywallId'] ?? '');
      case 'track':
        return TrackAction(
          event: params['event'] ?? '',
          screenId: params['screenId'] ?? '',
          answers: params['answers'] == null
              ? const {}
              : (jsonDecode(params['answers']!) as Map).map(
                  (k, v) => MapEntry(k as String, (v as List).cast<String>()),
                ),
        );
      default:
        return null;
    }
  }
}

final class RequestPermissionAction extends CoproductAction {
  final String permission;
  const RequestPermissionAction(this.permission);
}

final class OpenUrlAction extends CoproductAction {
  final String url;
  const OpenUrlAction(this.url);
}

final class DismissAction extends CoproductAction {
  const DismissAction();
}

final class CompleteAction extends CoproductAction {
  const CompleteAction();
}

final class ShowPaywallAction extends CoproductAction {
  final String paywallId;
  const ShowPaywallAction(this.paywallId);
}

final class TrackAction extends CoproductAction {
  final String event;
  final String screenId;
  final Map<String, List<String>> answers;
  const TrackAction({required this.event, required this.screenId, required this.answers});
}
