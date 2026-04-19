import 'package:campus_flutter/base/enums/device.dart';
import 'package:campus_flutter/base/enums/error_handling_view_type.dart';
import 'package:campus_flutter/base/errorHandling/error_handling_router.dart';
import 'package:campus_flutter/base/extensions/context.dart';
import 'package:campus_flutter/base/networking/apis/tumdev/campus_backend.pbgrpc.dart';
import 'package:campus_flutter/base/services/device_type_service.dart';
import 'package:campus_flutter/base/services/user_interests_service.dart';
import 'package:campus_flutter/base/util/delayed_loading_indicator.dart';
import 'package:campus_flutter/campusComponent/view/news/news_card_view.dart';
import 'package:campus_flutter/campusComponent/viewmodel/news_viewmodel.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  static const String _forYouTabLabel = 'For You';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interests = ref.watch(userInterestsProvider);
    final vm = ref.watch(newsViewModel);
    return StreamBuilder(
      stream: vm.newsBySource,
      builder: (context, snapshot) {
        final bySource = snapshot.data;
        final forYou = interests.isEmpty
            ? const <News>[]
            : vm.forYouNews(interests);
        final hasForYou = interests.isNotEmpty;
        final sourceEntries =
            bySource?.entries.toList() ?? const <MapEntry<String, List<News>>>[];
        final tabCount = sourceEntries.length + (hasForYou ? 1 : 0);

        return DefaultTabController(
          length: tabCount,
          child: Scaffold(
            appBar: AppBar(
              title: Text(context.tr("news")),
              bottom: tabCount > 0
                  ? TabBar(
                      isScrollable: true,
                      tabs: [
                        if (hasForYou)
                          const Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome, size: 16),
                                SizedBox(width: 6),
                                Text(_forYouTabLabel),
                              ],
                            ),
                          ),
                        for (final entry in sourceEntries)
                          Tab(text: entry.key),
                      ],
                    )
                  : null,
            ),
            body: Column(
              children: [
                if (!hasForYou && snapshot.hasData)
                  _InterestsNudgeBanner(),
                Expanded(
                  child: _buildBody(
                    context: context,
                    snapshot: snapshot,
                    sourceEntries: sourceEntries,
                    forYou: forYou,
                    hasForYou: hasForYou,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required AsyncSnapshot snapshot,
    required List<MapEntry<String, List<News>>> sourceEntries,
    required List<News> forYou,
    required bool hasForYou,
  }) {
    if (snapshot.hasError) {
      return Center(
        child: ErrorHandlingRouter(
          error: snapshot.error,
          errorHandlingViewType: ErrorHandlingViewType.fullScreen,
        ),
      );
    }
    if (!snapshot.hasData) {
      return Center(
        child: DelayedLoadingIndicator(name: context.tr("news")),
      );
    }
    return TabBarView(
      children: [
        if (hasForYou) _buildForYouTab(context, forYou),
        for (final entry in sourceEntries)
          _buildNewsGrid(context, entry.value),
      ],
    );
  }

  Widget _buildForYouTab(BuildContext context, List<News> items) {
    if (items.isEmpty) {
      return const _ForYouEmptyState();
    }
    return _buildNewsGrid(context, items);
  }

  Widget _buildNewsGrid(BuildContext context, List<News> items) {
    return Scrollbar(
      child: GridView.count(
        crossAxisCount: crossAxisCount(context),
        mainAxisSpacing: context.padding,
        crossAxisSpacing: context.padding,
        padding: EdgeInsets.all(context.padding),
        childAspectRatio: 1.1,
        children: [
          for (final news in items)
            LayoutBuilder(
              builder: (context, constraints) => NewsCardView(
                news: news,
                width: constraints.maxWidth,
              ),
            ),
        ],
      ),
    );
  }

  int crossAxisCount(BuildContext context) {
    switch (DeviceService.getType(context)) {
      case Device.landscapeTablet:
        return 3;
      case Device.portraitTablet:
        return 2;
      case Device.phone:
        return 1;
    }
  }
}

class _InterestsNudgeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: context.padding,
        vertical: context.padding * 0.75,
      ),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          SizedBox(width: context.padding * 0.75),
          Expanded(
            child: Text(
              "Tell Coco what you're into to get a personalized news feed.",
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ForYouEmptyState extends StatelessWidget {
  const _ForYouEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.padding * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 36,
              color: theme.colorScheme.primary,
            ),
            SizedBox(height: context.padding),
            Text(
              'Nothing matches your interests right now.',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: context.padding * 0.5),
            Text(
              "Come back later, or tell Coco what else you're into.",
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
