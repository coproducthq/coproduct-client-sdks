// The native-capability actions the platform script can trigger by
// navigating to a coproduct-action: URL, intercepted by the WebView's
// onShouldStartLoadWithRequest and never actually navigated. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/coproduct_action.dart.
export type CoproductAction =
  | { type: 'requestPermission'; permission: string }
  | { type: 'openUrl'; url: string }
  | { type: 'dismiss' }
  | { type: 'complete' }
  | { type: 'showPaywall'; paywallId: string }
  | {
      type: 'request';
      operation: string;
      requestId: string;
      params: Record<string, string>;
    }
  | {
      type: 'track';
      event: string;
      screenId: string;
      answers: Record<string, string[]>;
    };

export function parseCoproductAction(url: string): CoproductAction | undefined {
  if (!url.startsWith('coproduct-action:')) return undefined;

  const withoutScheme = url.slice('coproduct-action:'.length);
  const [action = '', query] = withoutScheme.split('?');
  const params = new URLSearchParams(query ?? '');

  switch (action) {
    case 'requestPermission':
      return {
        type: 'requestPermission',
        permission: params.get('permission') ?? '',
      };
    case 'openUrl':
      return { type: 'openUrl', url: params.get('url') ?? '' };
    case 'dismiss':
      return { type: 'dismiss' };
    case 'complete':
      return { type: 'complete' };
    case 'showPaywall':
      return { type: 'showPaywall', paywallId: params.get('paywallId') ?? '' };
    case 'request': {
      const requestParams: Record<string, string> = {};
      for (const [key, value] of params.entries()) {
        if (key.startsWith('param_'))
          requestParams[key.slice('param_'.length)] = value;
      }
      return {
        type: 'request',
        operation: params.get('operation') ?? '',
        requestId: params.get('requestId') ?? '',
        params: requestParams,
      };
    }
    case 'track': {
      const rawAnswers = params.get('answers');
      const answers: Record<string, string[]> =
        rawAnswers == null ? {} : JSON.parse(rawAnswers);
      return {
        type: 'track',
        event: params.get('event') ?? '',
        screenId: params.get('screenId') ?? '',
        answers,
      };
    }
    default:
      return undefined;
  }
}
