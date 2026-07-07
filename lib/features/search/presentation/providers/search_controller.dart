import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../watchlist/data/providers/watchlist_repository_provider.dart';
import '../../../watchlist/domain/models/watchlist_models.dart';
import '../../../watchlist/domain/repositories/watchlist_repository.dart';
import '../../../watchlist/presentation/providers/favorite_ids_controller.dart';

final searchControllerProvider =
    NotifierProvider<SearchController, SearchUiState>(SearchController.new);

class SearchController extends Notifier<SearchUiState> {
  WatchlistRepository get _repository => ref.read(watchlistRepositoryProvider);

  static const _searchDebounceDuration = Duration(milliseconds: 200);

  Timer? _toastTimer;
  int _requestSequence = 0;

  @override
  SearchUiState build() {
    ref.onDispose(() => _toastTimer?.cancel());

    ref.listen<AsyncValue<Set<String>>>(favoriteIdsControllerProvider, (
      _,
      next,
    ) {
      _applyFavoriteIds(next.valueOrNull);
    });

    return const SearchUiState();
  }

  Future<void> setQuery(String query) async {
    _requestSequence += 1;
    final currentRequestId = _requestSequence;
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      _toastTimer?.cancel();
      state = state.copyWith(
        query: query,
        results: const AsyncData(<StockSearchItem>[]),
        selectedItemId: null,
        toast: null,
      );
      return;
    }

    // 지우기 버튼(hasQuery)처럼 즉시 반영돼야 하는 부분만 먼저 갱신한다.
    state = state.copyWith(query: query, selectedItemId: null, toast: null);

    // ac.stock.naver.com은 비공식 엔드포인트라 키 입력마다 요청을 쏘면
    // 불필요한 트래픽/레이스가 늘어난다. 타이핑이 잠시 멎을 때까지 기다렸다가,
    // 그 사이 더 최신 입력이 들어왔으면(_requestSequence 증가) 조용히 포기한다.
    // 별도 Timer 없이 기존 _requestSequence 가드를 그대로 재사용한다.
    await Future<void>.delayed(_searchDebounceDuration);
    if (currentRequestId != _requestSequence) {
      return;
    }

    final existingResults = state.results;
    final loadingResults = existingResults.hasValue
        ? const AsyncLoading<List<StockSearchItem>>().copyWithPrevious(
            existingResults,
          )
        : const AsyncLoading<List<StockSearchItem>>();

    state = state.copyWith(results: loadingResults);

    final result = await AsyncValue.guard(
      () => _repository.searchStocks(query: trimmedQuery),
    );
    if (currentRequestId != _requestSequence) {
      return;
    }

    final favoriteIds = ref.read(favoriteIdsControllerProvider).valueOrNull;

    state = state.copyWith(
      results: result.whenData(
        (items) => _mapFavoriteIds(items, favoriteIds ?? const <String>{}),
      ),
      selectedItemId: null,
    );
  }

  void clearQuery() {
    _requestSequence += 1;
    _toastTimer?.cancel();
    state = state.copyWith(
      query: '',
      results: const AsyncData(<StockSearchItem>[]),
      selectedItemId: null,
      toast: null,
    );
  }

  void setFocused(bool isFocused) {
    if (state.isFocused == isFocused) {
      return;
    }
    state = state.copyWith(isFocused: isFocused);
  }

  void toggleSelection(StockSearchItem item) {
    state = state.copyWith(
      selectedItemId: state.selectedItemId == item.id ? null : item.id,
    );
  }

  void clearSelection() {
    if (state.selectedItemId == null) {
      return;
    }
    state = state.copyWith(selectedItemId: null);
  }

  Future<bool> toggleFavorite(StockSearchItem item) async {
    final isAdded = await ref
        .read(favoriteIdsControllerProvider.notifier)
        .toggle(item.id);

    _applyFavoriteIds(ref.read(favoriteIdsControllerProvider).valueOrNull);

    if (isAdded) {
      _showToast(
        const SearchToastData(
          leadingText: '\uad00\uc2ec\uadf8\ub8f9',
          trailingText: '\uc5d0 \ucd94\uac00\ub418\uc5c8\uc2b5\ub2c8\ub2e4.',
        ),
      );
    } else {
      dismissToast();
    }

    return isAdded;
  }

  void dismissToast() {
    _toastTimer?.cancel();
    if (state.toast == null) {
      return;
    }
    state = state.copyWith(toast: null);
  }

  void _showToast(SearchToastData toast) {
    _toastTimer?.cancel();
    state = state.copyWith(toast: toast);
    _toastTimer = Timer(const Duration(seconds: 2), dismissToast);
  }

  void _applyFavoriteIds(Set<String>? favoriteIds) {
    if (favoriteIds == null) {
      return;
    }

    final results = state.results.whenData(
      (items) => _mapFavoriteIds(items, favoriteIds),
    );
    final items = results.valueOrNull;
    final selectedItemId = state.selectedItemId;

    state = state.copyWith(
      results: results,
      selectedItemId:
          items == null ||
              selectedItemId == null ||
              items.any((item) => item.id == selectedItemId)
          ? selectedItemId
          : null,
    );
  }

  List<StockSearchItem> _mapFavoriteIds(
    List<StockSearchItem> items,
    Set<String> favoriteIds,
  ) {
    return [
      for (final item in items)
        item.copyWith(isFavorite: favoriteIds.contains(item.id)),
    ];
  }
}

@immutable
class SearchUiState {
  const SearchUiState({
    this.query = '',
    this.results = const AsyncData(<StockSearchItem>[]),
    this.selectedItemId,
    this.isFocused = false,
    this.toast,
  });

  final String query;
  final AsyncValue<List<StockSearchItem>> results;
  final String? selectedItemId;
  final bool isFocused;
  final SearchToastData? toast;

  SearchUiState copyWith({
    String? query,
    AsyncValue<List<StockSearchItem>>? results,
    Object? selectedItemId = _sentinel,
    bool? isFocused,
    Object? toast = _sentinel,
  }) {
    return SearchUiState(
      query: query ?? this.query,
      results: results ?? this.results,
      selectedItemId: selectedItemId == _sentinel
          ? this.selectedItemId
          : selectedItemId as String?,
      isFocused: isFocused ?? this.isFocused,
      toast: toast == _sentinel ? this.toast : toast as SearchToastData?,
    );
  }
}

@immutable
class SearchToastData {
  const SearchToastData({
    required this.leadingText,
    required this.trailingText,
  });

  final String leadingText;
  final String trailingText;

  String get message => '$leadingText$trailingText';
}

const _sentinel = Object();
