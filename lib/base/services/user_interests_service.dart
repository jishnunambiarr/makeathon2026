import 'package:campus_flutter/base/enums/user_preference.dart';
import 'package:campus_flutter/base/services/user_preferences_service.dart';
import 'package:campus_flutter/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Persistent list of user interests (keywords / topics) that personalize
/// parts of the app such as the News "For You" tab. Written either via the
/// voice agent (see `agent_client_tools.dart`) or manually from a settings UI.
///
/// Storage: `UserPreference.userInterests` in `SharedPreferences`, same pattern
/// as `homeWidgets`. State is exposed as a Riverpod [StateProvider] so any
/// widget that `ref.watch`es it reacts to writes immediately.
const int _maxInterests = 20;
const int _maxInterestLength = 40;

/// Reactive user interests (lowercased, deduped). Initialized synchronously
/// from `SharedPreferences` so the first frame already has the saved list.
final userInterestsProvider = StateProvider<List<String>>((ref) {
  final stored =
      getIt<UserPreferencesService>().load(UserPreference.userInterests)
          as List<String>? ??
      const <String>[];
  return stored
      .map(normalizeInterest)
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
});

/// Write-side helpers for [userInterestsProvider]. Not a state holder —
/// every mutator reads the current list off the provider, computes the next
/// list, writes it back, and persists to SharedPreferences.
class UserInterests {
  UserInterests._();

  /// Add a single interest. Normalizes (trim + lowercase), dedups case-insensitively,
  /// caps total list at [_maxInterests]. Returns the resulting list.
  static Future<List<String>> add(Ref ref, String interest) {
    return _mutate(ref, (current) {
      final cleaned = normalizeInterest(interest);
      if (cleaned.isEmpty) return current;
      if (current.any((e) => e == cleaned)) return current;
      final next = <String>[...current, cleaned];
      if (next.length > _maxInterests) {
        next.removeRange(0, next.length - _maxInterests);
      }
      return next;
    });
  }

  /// Same as [add] but takes a [WidgetRef] (for use inside widgets / ClientTools).
  static Future<List<String>> addWith(WidgetRef ref, String interest) {
    return _mutateWith(ref, (current) {
      final cleaned = normalizeInterest(interest);
      if (cleaned.isEmpty) return current;
      if (current.any((e) => e == cleaned)) return current;
      final next = <String>[...current, cleaned];
      if (next.length > _maxInterests) {
        next.removeRange(0, next.length - _maxInterests);
      }
      return next;
    });
  }

  /// Remove a single interest (case-insensitive). Returns the resulting list.
  static Future<List<String>> removeWith(WidgetRef ref, String interest) {
    return _mutateWith(ref, (current) {
      final cleaned = normalizeInterest(interest);
      if (cleaned.isEmpty) return current;
      final next = current.where((e) => e != cleaned).toList(growable: false);
      return next.length == current.length ? current : next;
    });
  }

  /// Drop all interests.
  static Future<void> clearWith(WidgetRef ref) async {
    await _mutateWith(ref, (_) => const <String>[]);
  }

  static Future<List<String>> _mutate(
    Ref ref,
    List<String> Function(List<String> current) compute,
  ) async {
    final current = ref.read(userInterestsProvider);
    final next = compute(current);
    if (identical(next, current)) return current;
    ref.read(userInterestsProvider.notifier).state = next;
    _persist(next);
    return next;
  }

  static Future<List<String>> _mutateWith(
    WidgetRef ref,
    List<String> Function(List<String> current) compute,
  ) async {
    final current = ref.read(userInterestsProvider);
    final next = compute(current);
    if (identical(next, current)) return current;
    ref.read(userInterestsProvider.notifier).state = next;
    _persist(next);
    return next;
  }

  static void _persist(List<String> value) {
    getIt<UserPreferencesService>().save(
      UserPreference.userInterests,
      value.toList(growable: false),
    );
  }
}

/// Trim + lowercase + truncate to [_maxInterestLength]. Public so the agent
/// tools can echo the canonical form back to the model.
String normalizeInterest(String raw) {
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  return trimmed.length > _maxInterestLength
      ? trimmed.substring(0, _maxInterestLength)
      : trimmed;
}
