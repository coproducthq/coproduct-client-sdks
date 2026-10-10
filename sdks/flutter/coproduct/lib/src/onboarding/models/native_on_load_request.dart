/// A screen's on-load native request: fires the instant the screen becomes
/// current, suspending the screen's own reveal until native resolves it.
/// Mirrors ZNativeRequest in packages/snapshot-spec/src/onboarding-flow.ts
class NativeOnLoadRequest {
  final String operation;
  final Map<String, String> params;
  final String resultKey;
  final int timeoutMs;

  const NativeOnLoadRequest({
    required this.operation,
    required this.params,
    required this.resultKey,
    required this.timeoutMs,
  });

  factory NativeOnLoadRequest.fromJson(Map<String, dynamic> json) => NativeOnLoadRequest(
        operation: json['operation'] as String,
        params: (json['params'] as Map).map((k, v) => MapEntry(k as String, v as String)),
        resultKey: json['resultKey'] as String,
        timeoutMs: json['timeoutMs'] as int,
      );

  Map<String, dynamic> toJson() => {
        'operation': operation,
        'params': params,
        'resultKey': resultKey,
        'timeoutMs': timeoutMs,
      };
}
