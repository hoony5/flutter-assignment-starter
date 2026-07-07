import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../theme/app_assets.dart';
import '../../../../theme/app_theme.dart';
import '../layout/search_layout_spec.dart';

class SearchToast extends StatelessWidget {
  const SearchToast({
    required this.layout,
    required this.leadingText,
    required this.trailingText,
    super.key,
  });

  final SearchLayoutSpec layout;
  final String leadingText;
  final String trailingText;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: SearchLayoutSpec.toastHeight,
          padding: EdgeInsets.symmetric(
            horizontal: 16 * layout.horizontalScale,
          ),
          decoration: BoxDecoration(
            color: AppDerivedColors.searchToastBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppDerivedColors.searchToastBorder),
          ),
          child: Row(
            children: [
              const _ToastFavoriteIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: AppTypography.searchToast,
                    children: [
                      TextSpan(
                        text: leadingText,
                        style: AppTypography.searchToast.copyWith(
                          color: AppColors.text.text_fafafa,
                        ),
                      ),
                      TextSpan(
                        text: trailingText,
                        style: AppTypography.searchToast.copyWith(
                          color: AppColors.text.text_3_9e9e9e,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToastFavoriteIcon extends StatelessWidget {
  const _ToastFavoriteIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('search-toast-favorite-icon'),
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AppAssetSlotIcon(
            assetPath: AppAssets.favoriteHeart,
            slotWidth: 20,
            slotHeight: 20,
            assetWidth: AppAssetSizes.favoriteHeart.width,
            assetHeight: AppAssetSizes.favoriteHeart.height,
            color: AppColors.mainAndAccent.up_f93f62,
          ),
          Positioned(
            top: 7,
            left: 8,
            child: AppAssetSlotIcon(
              key: const Key('search-toast-check-icon'),
              assetPath: AppAssets.toastCheck,
              slotWidth: AppAssetSizes.toastCheck.width,
              slotHeight: AppAssetSizes.toastCheck.height,
              assetWidth: AppAssetSizes.toastCheck.width,
              assetHeight: AppAssetSizes.toastCheck.height,
              color: AppColors.text.text_fafafa,
            ),
          ),
        ],
      ),
    );
  }
}
