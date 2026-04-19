import 'package:campus_flutter/base/networking/apis/tumdev/campus_backend.pbgrpc.dart';
import 'package:campus_flutter/campusComponent/service/news_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

final newsViewModel = Provider((ref) => NewsViewModel());

class NewsViewModel {
  BehaviorSubject<Map<String, List<News>>?> newsBySource =
      BehaviorSubject.seeded(null);
  BehaviorSubject<List<News>?> news = BehaviorSubject.seeded(null);

  final BehaviorSubject<DateTime?> lastFetched = BehaviorSubject.seeded(null);

  Future fetch(bool forcedRefresh) async {
    return NewsService.fetchRecentNews(forcedRefresh).then((value) {
      lastFetched.add(value.$1);
      value.$2.sort((news1, news2) {
        final date1 = news1.date.toDateTime();
        final date2 = news2.date.toDateTime();
        return date2.compareTo(date1);
      });
      newsBySource.add(mapNewsBySource(value.$2));
      news.add(value.$2);
    }, onError: (error) => news.addError(error));
  }

  Map<String, List<News>> mapNewsBySource(List<News> news) {
    Map<String, List<News>> mappedNews = {};

    for (var news in news) {
      if (!mappedNews.containsKey(news.sourceTitle)) {
        mappedNews[news.sourceTitle] = [];
      }
      mappedNews[news.sourceTitle]!.add(news);
    }

    return mappedNews;
  }

  /// Returns news items whose title + body contain at least one of the
  /// given [interests] (case-insensitive), sorted by (match count desc,
  /// date desc). Returns an empty list if no interests are set or no news
  /// has been loaded yet.
  List<News> forYouNews(List<String> interests) {
    final source = news.value;
    if (source == null || source.isEmpty || interests.isEmpty) {
      return const [];
    }
    final normalized = interests
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    if (normalized.isEmpty) return const [];

    final scored = <(int, News)>[];
    for (final n in source) {
      final score = _scoreNews(n, normalized);
      if (score > 0) scored.add((score, n));
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      if (byScore != 0) return byScore;
      return b.$2.date.toDateTime().compareTo(a.$2.date.toDateTime());
    });
    return scored.map((e) => e.$2).toList();
  }

  int _scoreNews(News n, List<String> normalizedInterests) {
    final hay = '${n.title} ${n.text}'.toLowerCase();
    var score = 0;
    for (final interest in normalizedInterests) {
      if (hay.contains(interest)) score += 1;
    }
    return score;
  }

  List<News> latestFiveNews() {
    if (news.value != null) {
      final news = this.news.value!;
      Set<String> seenTitles = {};
      news.retainWhere((element) {
        if (seenTitles.contains(element.title)) {
          return false;
        } else {
          seenTitles.add(element.title);
          return true;
        }
      });
      news.sort(
        (news1, news2) =>
            news2.date.toDateTime().compareTo(news1.date.toDateTime()),
      );
      if (news.length > 5) {
        return news.sublist(0, 5).toList();
      } else {
        return news;
      }
    } else {
      return [];
    }
  }
}
