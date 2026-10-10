import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FlowProgress {
  final int version;
  final String screenId;
  final Map<String, List<String>> answers;

  const FlowProgress({required this.version, required this.screenId, required this.answers});
}

/// Persists onboarding progress to local device storage, keyed by flowId
/// and version, so an app crash or restart resumes on the last known
/// screen of the same version the device started on, rather than
/// restarting from startScreenId.
class LocalProgressStore {
  static String _key(String flowId) => 'coproduct_onboarding_progress_$flowId';

  Future<void> save({
    required String flowId,
    required int version,
    required String screenId,
    required Map<String, List<String>> answers,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(flowId), jsonEncode({
      'version': version,
      'screenId': screenId,
      'answers': answers,
    }));
  }

  Future<FlowProgress?> load({required String flowId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(flowId));
    if (raw == null) return null;

    final json = jsonDecode(raw) as Map<String, dynamic>;
    return FlowProgress(
      version: json['version'] as int,
      screenId: json['screenId'] as String,
      answers: (json['answers'] as Map).map(
        (k, v) => MapEntry(k as String, (v as List).cast<String>()),
      ),
    );
  }

  Future<void> clear({required String flowId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(flowId));
  }
}
