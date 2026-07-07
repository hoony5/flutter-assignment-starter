import 'package:flutter/material.dart';

import '../../../watchlist/domain/models/watchlist_models.dart';
import '../../../../theme/app_assets.dart';
import '../../../../theme/app_theme.dart';
import '../../domain/services/search_text_utils.dart';
import '../layout/search_layout_spec.dart';
import 'search_action_bar.dart';

class SearchResultRow extends StatelessWidget {
  const SearchResultRow({
    required this.item,
    required this.query,
    required this.isSelected,
    required this.layout,
    required this.onTap,
    required this.onHeartTap,
    required this.onActionTap,
    super.key,
  });

  final StockSearchItem item;
  final String query;
  final bool isSelected;
  final SearchLayoutSpec layout;
  final VoidCallback onTap;
  final VoidCallback onHeartTap;
  final ValueChanged<String> onActionTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('search-result-${item.id}'),
        onTap: onTap,
        child: Column(
          children: [
            SizedBox(
              key: Key('search-result-row-${item.id}'),
              height: SearchLayoutSpec.resultRowHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: layout.horizontalPadding,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _SearchTextColumn(item: item, query: query),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      key: Key('search-heart-${item.id}'),
                      onTap: onHeartTap,
                      behavior: HitTestBehavior.opaque,
                      child: AppAssetSlotIcon(
                        key: Key('search-heart-icon-${item.id}'),
                        assetPath: AppAssets.favoriteHeart,
                        // DONE(assignment): Match the exact Figma slot size.
                        // This starter keeps the slot slightly oversized so
                        // the related widget test can guide the fix.
                        slotWidth: 20,
                        slotHeight: 20,
                        assetWidth: AppAssetSizes.favoriteHeart.width,
                        assetHeight: AppAssetSizes.favoriteHeart.height,
                        color: item.isFavorite
                            ? AppColors.mainAndAccent.up_f93f62
                            : AppColors.darkTheme.c_424242,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: SearchLayoutSpec.expandedActionTopGap),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: layout.horizontalPadding,
                ),
                child: SearchActionBar(
                  key: Key('search-actions-${item.id}'),
                  layout: layout,
                  onActionTap: onActionTap,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchTextColumn extends StatelessWidget {
  const _SearchTextColumn({required this.item, required this.query});

  final StockSearchItem item;
  final String query;

  @override
  Widget build(BuildContext context) {
    final subtitle = buildSearchSubtitle(item);
    // DONE(assignment): Rebuild this text block to match Figma.
    // Expected shape:
    // - title + subtitle as two RichText widgets
    // - query highlight using splitSearchTextParts()
    // - typography and ellipsis should match the design
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HighlightedText(
          text: item.name,
          query: query,
          baseStyle: AppTypography.searchName,
        ),
        const SizedBox(height: 4),
        _HighlightedText(
          text: subtitle,
          query: query,
          baseStyle: AppTypography.searchMeta,
        ),
      ],
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.baseStyle,
  });

  final String text;
  final String query;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final parts = splitSearchTextParts(text, query);

    // 검색 판정과 같은 splitter로 제목/심볼 강조를 맞춘다.
    // 검색 판정과 같은 splitter를 써서 이름/심볼 강조 기준이 어긋나지 않게 한다.
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle,
        children: [
          for (final part in parts)
            TextSpan(
              text: part.text,
              style: part.isHighlighted
                  ? baseStyle.copyWith(
                      color: AppColors.point.jongmoksearch_b980ff,
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}
