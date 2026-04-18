import 'dart:math' as math;

import 'package:campus_flutter/base/enums/search_type.dart';
import 'package:campus_flutter/base/networking/protocols/api.dart';
import 'package:campus_flutter/base/routing/router.dart';
import 'package:campus_flutter/base/routing/routes.dart' as routes;
import 'package:campus_flutter/campusComponent/service/news_service.dart';
import 'package:campus_flutter/calendarComponent/viewModels/calendar_viewmodel.dart';
import 'package:campus_flutter/homeComponent/service/departures_service.dart';
import 'package:campus_flutter/navigaTumComponent/services/navigatum_service.dart';
import 'package:campus_flutter/placesComponent/model/cafeterias/cafeteria.dart';
import 'package:campus_flutter/placesComponent/services/cafeterias_service.dart';
import 'package:campus_flutter/placesComponent/services/mealplan_service.dart';
import 'package:campus_flutter/placesComponent/services/study_rooms_service.dart';
import 'package:campus_flutter/searchComponent/viewModels/search_viewmodel.dart';
import 'package:campus_flutter/settingsComponent/views/settings_view.dart';
import 'package:campus_flutter/studiesComponent/service/grade_service.dart';
import 'package:campus_flutter/studiesComponent/service/lecture_service.dart';
import 'package:elevenlabs_agents/elevenlabs_agents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Minimal, whitelisted tool surface for the in-app ElevenLabs agent.
///
/// These tools are executed on-device via `elevenlabs_agents` client tool calls.
class AgentClientTools {
  static const String toolGetNews = 'get_news';
  static const String toolGetCafeteriaMenu = 'get_cafeteria_menu';
  static const String toolGetDepartures = 'get_departures';
  static const String toolGetStudyRooms = 'get_study_rooms';
  static const String toolSearchRooms = 'search_rooms';

  static const String toolGetNextEvents = 'get_next_events';
  static const String toolGetMyCourses = 'get_my_courses';
  static const String toolGetGrades = 'get_grades';

  static const String toolNavigate = 'navigate';
  static const String toolOpenSearch = 'open_search';
  static const String toolTriggerShortcut = 'trigger_shortcut';
  static const String toolOpenPersonDetails = 'open_person_details';
  static const String toolOpenNavigaTumRoom = 'open_navigatum_room';

  /// Strictly allowed destinations for `navigate`.
  static const Set<String> allowedRoutes = {
    routes.home,
    routes.studies,
    routes.calendar,
    routes.campus,
    routes.places,
    routes.agent,
    routes.departures,
    routes.cafeterias,
    routes.studyRooms,
    routes.news,
    routes.movies,
    routes.studentClubs,
    routes.search,
    routes.roomSearch,
    routes.personSearch,
    routes.menuSettings,
    routes.feedback,
  };

  static Map<String, ClientTool> build({
    required WidgetRef ref,
  }) {
    return <String, ClientTool>{
      toolGetNews: _GetNewsTool(),
      toolGetCafeteriaMenu: _GetCafeteriaMenuTool(),
      toolGetDepartures: _GetDeparturesTool(),
      toolGetStudyRooms: _GetStudyRoomsTool(),
      toolSearchRooms: _SearchRoomsTool(),

      toolGetNextEvents: _RequireLoginTool(
        delegate: _GetNextEventsTool(ref: ref),
      ),
      toolGetMyCourses: _RequireLoginTool(delegate: _GetMyCoursesTool()),
      toolGetGrades: _RequireLoginTool(delegate: _GetGradesTool()),

      toolNavigate: _NavigateTool(ref: ref),
      toolOpenSearch: _OpenSearchTool(ref: ref),
      toolTriggerShortcut: _TriggerShortcutTool(ref: ref),
      toolOpenPersonDetails: _OpenPersonDetailsTool(ref: ref),
      toolOpenNavigaTumRoom: _OpenNavigaTumRoomTool(ref: ref),
    };
  }
}

class _RequireLoginTool implements ClientTool {
  final ClientTool delegate;
  _RequireLoginTool({required this.delegate});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    if (Api.tumToken.trim().isEmpty) {
      return ClientToolResult.failure('Please log in in the app first.');
    }
    return await delegate.execute(parameters);
  }
}

class _GetNewsTool implements ClientTool {
  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final limit = _asInt(parameters['limit'], defaultValue: 5, min: 1, max: 20);
    final recent = _asBool(parameters['recent'], defaultValue: true);
    final (_, list) = recent
        ? await NewsService.fetchRecentNews(false)
        : await NewsService.fetchNews(false);

    final items = list.take(limit).map((n) {
      return {
        'title': n.title,
        'source': n.sourceTitle,
        'date': n.date.toDateTime().toIso8601String(),
        'link': n.link,
      };
    }).toList();

    return ClientToolResult.success({
      'count': items.length,
      'items': items,
    });
  }
}

class _GetCafeteriaMenuTool implements ClientTool {
  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final cafeteriaId = _asString(parameters['cafeteriaId']);
    final dayOffset = _asInt(parameters['dayOffset'], defaultValue: 0, min: 0, max: 14);
    final dishLimit = _asInt(parameters['dishLimit'], defaultValue: 10, min: 1, max: 30);

    final (_, cafeterias) = await CafeteriasService.fetchCafeterias(false);
    if (cafeterias.isEmpty) {
      return ClientToolResult.failure('No cafeterias available right now.');
    }

    Cafeteria cafeteria = cafeterias.first;
    if (cafeteriaId != null) {
      final match = cafeterias.where((c) => c.id == cafeteriaId).toList();
      if (match.isEmpty) {
        return ClientToolResult.failure(
          'Unknown cafeteriaId. Try one of: ${cafeterias.take(8).map((c) => c.id).join(", ")}',
        );
      }
      cafeteria = match.first;
    }

    final (_, menuDays) = await MealPlanService.getCafeteriaMenu(false, cafeteria);
    if (menuDays.isEmpty) {
      return ClientToolResult.success({
        'cafeteria': {'id': cafeteria.id, 'name': cafeteria.name},
        'days': [],
      });
    }

    // Pick a day: either explicit offset from today, or just the first available day.
    final targetDate = DateTime.now().add(Duration(days: dayOffset));
    final targetDay = menuDays.firstWhere(
      (d) => _sameDate(d.date, targetDate),
      orElse: () => menuDays.first,
    );

    final flattened = <Map<String, dynamic>>[];
    for (final cat in targetDay.categories) {
      for (final dish in cat.dishes.take(math.max(0, dishLimit - flattened.length))) {
        flattened.add({
          'category': cat.name,
          'name': dish.name,
          'priceStudents': dish.prices['students']?.basePrice,
          'priceEmployees': dish.prices['employees']?.basePrice,
          'labels': dish.labels,
        });
        if (flattened.length >= dishLimit) break;
      }
      if (flattened.length >= dishLimit) break;
    }

    return ClientToolResult.success({
      'cafeteria': {'id': cafeteria.id, 'name': cafeteria.name},
      'date': targetDay.date.toIso8601String(),
      'items': flattened,
    });
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _GetDeparturesTool implements ClientTool {
  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final station = _asString(parameters['station']);
    final limit = _asInt(parameters['limit'], defaultValue: 6, min: 1, max: 20);
    final walkingTime = _asInt(parameters['walkingTime'], min: 0, max: 60);

    if (station == null || station.trim().isEmpty) {
      return ClientToolResult.failure(
        'Missing parameter "station". Example: { "station": "Garching-Forschungszentrum" }',
      );
    }

    final res = await DeparturesService.fetchDepartures(false, station, walkingTime);
    final deps = res.data.departures.take(limit).map((d) {
      return {
        'line': d.servingLine.number,
        'direction': d.servingLine.direction,
        'countdownMinutes': d.countdown,
        'delayMinutes': d.servingLine.delay,
      };
    }).toList();

    return ClientToolResult.success({
      'station': station,
      'count': deps.length,
      'departures': deps,
    });
  }
}

class _GetStudyRoomsTool implements ClientTool {
  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final limit = _asInt(parameters['limit'], defaultValue: 8, min: 1, max: 30);
    final (_, data) = await StudyRoomsService.fetchStudyRooms(false);

    final rooms = (data.rooms ?? []).toList();
    rooms.sort((a, b) {
      final av = a.isAvailable ? 0 : 1;
      final bv = b.isAvailable ? 0 : 1;
      if (av != bv) return av - bv;
      return (a.name ?? '').compareTo(b.name ?? '');
    });

    final items = rooms.take(limit).map((r) {
      return {
        'id': r.id,
        'name': r.name,
        'building': r.buildingName,
        'status': r.status,
        'available': r.isAvailable,
        'percent': r.percent,
        'occupiedUntil': r.occupiedUntil?.toIso8601String(),
      };
    }).toList();

    return ClientToolResult.success({
      'count': items.length,
      'rooms': items,
    });
  }
}

class _SearchRoomsTool implements ClientTool {
  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final query = _asString(parameters['query']);
    final limit = _asInt(parameters['limit'], defaultValue: 8, min: 1, max: 20);
    if (query == null || query.trim().isEmpty) {
      return ClientToolResult.failure('Missing parameter "query".');
    }

    final res = await NavigaTumService.search(false, query.trim());
    final entities = <Map<String, dynamic>>[];
    for (final section in res.sections) {
      for (final e in section.entries) {
        entities.add({
          'id': e.id,
          'name': e.name,
          'type': e.type,
          'subtext': e.subtext,
          'section': section.type,
        });
        if (entities.length >= limit) break;
      }
      if (entities.length >= limit) break;
    }

    return ClientToolResult.success({
      'query': query,
      'count': entities.length,
      'results': entities,
    });
  }
}

class _GetNextEventsTool implements ClientTool {
  final WidgetRef ref;
  _GetNextEventsTool({required this.ref});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final limit = _asInt(parameters['limit'], defaultValue: 5, min: 1, max: 20);

    // Use the same in-app event list & visibility filtering as the Calendar UI.
    // This avoids reporting events the user has hidden or that were canceled.
    final vm = ref.read(calendarViewModel);
    await vm.fetch(false);
    final events = vm.events.value ?? const [];

    final now = DateTime.now();
    final showHidden = ref.read(showHiddenCalendarEntries);
    final upcoming = events
        .where(
          (e) =>
              e.startDate.isAfter(now) &&
              (showHidden ? true : (e.isVisible ?? true)) &&
              !e.isCanceled,
        )
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    final items = upcoming.take(limit).map((e) {
      return {
        'id': e.id,
        'title': e.title,
        'from': e.startDate.toIso8601String(),
        'to': e.endDate.toIso8601String(),
        'locations': e.locations,
      };
    }).toList();

    return ClientToolResult.success({'count': items.length, 'events': items});
  }
}

class _GetMyCoursesTool implements ClientTool {
  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final limit = _asInt(parameters['limit'], defaultValue: 8, min: 1, max: 30);
    final (_, lectures) = await LectureService.fetchLecture(false);
    final items = lectures.take(limit).map((l) {
      return {
        'title': l.title,
        'id': l.id,
        'semester': l.semester,
        'lectureId': l.lvNumber,
      };
    }).toList();
    return ClientToolResult.success({'count': items.length, 'courses': items});
  }
}

class _GetGradesTool implements ClientTool {
  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final limit = _asInt(parameters['limit'], defaultValue: 10, min: 1, max: 30);
    final gradesRes = await GradeService.fetchGrades(false);
    final avgRes = await GradeService.fetchAverageGrades(false);

    final items = gradesRes.data.take(limit).map((g) {
      return {
        'title': g.title,
        'grade': g.grade,
        'semester': g.semester,
        'date': g.date?.toIso8601String(),
      };
    }).toList();

    final averages = avgRes.data.map((a) {
      return {
        'study': a.studyDesignation,
        'averageGrade': a.averageGrade,
      };
    }).toList();

    return ClientToolResult.success({
      'count': items.length,
      'grades': items,
      'averages': averages,
    });
  }
}

class _NavigateTool implements ClientTool {
  final WidgetRef ref;
  _NavigateTool({required this.ref});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final route = _asString(parameters['route']);
    if (route == null || route.trim().isEmpty) {
      return ClientToolResult.failure('Missing parameter "route".');
    }
    if (!AgentClientTools.allowedRoutes.contains(route)) {
      return ClientToolResult.failure('Route not allowed.');
    }

    ref.read(routerProvider).go(route);
    return ClientToolResult.success({'navigatedTo': route});
  }
}

class _OpenSearchTool implements ClientTool {
  final WidgetRef ref;
  _OpenSearchTool({required this.ref});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final typeStr = _asString(parameters['type']) ?? 'general';
    final query = _asString(parameters['query']);
    final categoryTab = _asString(parameters['categoryTab']);

    final SearchType type = switch (typeStr) {
      'room' => SearchType.room,
      'person' => SearchType.person,
      _ => SearchType.general,
    };

    final router = ref.read(routerProvider);
    final vm = ref.read(searchViewModel(type));

    final idx = _tabIndex(categoryTab);
    if (idx != null) vm.setSearchCategories(idx);

    if (query != null && query.trim().isNotEmpty) {
      vm.search(searchString: query.trim());
      router.push(routes.search, extra: query.trim());
    } else {
      router.push(routes.search);
    }

    return ClientToolResult.success({'opened': routes.search, 'type': type.name});
  }

  int? _tabIndex(String? tab) {
    switch (tab) {
      case 'home':
        return 0;
      case 'studies':
        return 1;
      case 'calendar':
        return 2;
      case 'campus':
        return 3;
      case 'places':
        return 4;
      case 'agent':
        return 5;
      default:
        return null;
    }
  }
}

class _TriggerShortcutTool implements ClientTool {
  final WidgetRef ref;
  _TriggerShortcutTool({required this.ref});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final shortcut = _asString(parameters['shortcutType']);
    if (shortcut == null || shortcut.trim().isEmpty) {
      return ClientToolResult.failure('Missing parameter "shortcutType".');
    }

    final route = switch (shortcut) {
      'home' => routes.home,
      'cafeterias' => routes.cafeterias,
      'studyRooms' => routes.studyRooms,
      'calendar' => routes.calendar,
      'studies' => routes.studies,
      'roomSearch' => routes.roomSearch,
      _ => null,
    };

    if (route == null) return ClientToolResult.failure('Unknown shortcutType.');
    ref.read(routerProvider).go(route);
    return ClientToolResult.success({'navigatedTo': route});
  }
}

class _OpenPersonDetailsTool implements ClientTool {
  final WidgetRef ref;
  _OpenPersonDetailsTool({required this.ref});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final id = _asString(parameters['obfuscatedId']);
    if (id == null || id.trim().isEmpty) {
      return ClientToolResult.failure('Missing parameter "obfuscatedId".');
    }
    ref.read(routerProvider).push(routes.personDetails, extra: id.trim());
    return ClientToolResult.success({'opened': routes.personDetails, 'id': id.trim()});
  }
}

class _OpenNavigaTumRoomTool implements ClientTool {
  final WidgetRef ref;
  _OpenNavigaTumRoomTool({required this.ref});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    final id = _asString(parameters['id']);
    if (id == null || id.trim().isEmpty) {
      return ClientToolResult.failure('Missing parameter "id".');
    }
    ref.read(routerProvider).push(routes.navigaTum, extra: id.trim());
    return ClientToolResult.success({'opened': routes.navigaTum, 'id': id.trim()});
  }
}

String? _asString(dynamic v) => v is String ? v : null;

bool _asBool(dynamic v, {required bool defaultValue}) {
  if (v is bool) return v;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
  }
  return defaultValue;
}

int _asInt(
  dynamic v, {
  int? defaultValue,
  int? min,
  int? max,
}) {
  int? parsed;
  if (v is int) parsed = v;
  if (v is double) parsed = v.round();
  if (v is String) parsed = int.tryParse(v.trim());
  parsed ??= defaultValue;
  if (parsed == null) return 0;
  if (min != null) parsed = math.max(min, parsed);
  if (max != null) parsed = math.min(max, parsed);
  return parsed;
}

