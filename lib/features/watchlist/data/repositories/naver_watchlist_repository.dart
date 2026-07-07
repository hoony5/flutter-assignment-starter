// ignore_for_file: unused_element, unused_field

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/watchlist_models.dart';
import '../../domain/repositories/watchlist_repository.dart';
import '../../domain/services/watchlist_sorting.dart';
import '../clients/naver_domestic_stock_client.dart';
import '../clients/naver_stock_logo_url_resolver.dart';
import '../dtos/naver_stock_dtos.dart';
import 'favorite_ids_local_store.dart';

class NaverWatchlistRepository implements WatchlistRepository {
  NaverWatchlistRepository({
    required Dio dio,
    required FavoriteIdsLocalStore favoriteIdsLocalStore,
    NaverStockDataClient? client,
    NaverStockLogoUrlResolver? logoUrlResolver,
    this.realtimeCacheTtl = const Duration(seconds: 10),
    this.dailyHistoryFetchBatchSize = 4,
  }) : _client = client ?? NaverDomesticStockClient(dio),
       _favoriteIdsLocalStore = favoriteIdsLocalStore,
       _logoUrlResolver = logoUrlResolver ?? const NaverStockLogoUrlResolver();

  final NaverStockDataClient _client;
  final FavoriteIdsLocalStore _favoriteIdsLocalStore;
  final NaverStockLogoUrlResolver _logoUrlResolver;
  final Duration realtimeCacheTtl;
  // 일별 시세 페이지 하나에 들어있는 row 수, 그리고 페이지/심볼을 동시에 몇 개씩
  // 요청할지(batch size)는 서로 붙어있는 값이라 나란히 둔다.
  // dailyHistoryFetchBatchSize는 아래 _runInBatches 호출부와
  // _loadAvailableDates의 페이지네이션 루프가 함께 참조하는 단일 값이다.
  static const _historyRowsPerPage = 10;
  final int dailyHistoryFetchBatchSize;

  // metadata 조회가 실패해 fallback을 반환했을 때, 이 fallback을 얼마나
  // 오래 "성공한 값"처럼 재사용할지에 대한 TTL. 성공한 값은 TTL 없이
  // 세션 내내 재사용하지만, fallback은 일시적 장애일 수 있으므로 짧게만
  // 재사용하고 지나면 다시 실제 API를 호출해 복구 여부를 확인한다.
  static const _metadataFailureRetryTtl = Duration(seconds: 30);

  final Map<String, _MetadataCacheEntry> _metadataCache = {};
  final Map<String, NaverDailyHistoryPageDto> _dailyHistoryPageCache = {};
  final Map<String, _RealtimeQuoteCacheEntry> _realtimeQuoteCache = {};

  Set<String>? _favoriteIdsCache;
  List<DateTime>? _availableDatesCache;
  Future<List<DateTime>>? _availableDatesLoadFuture;

  // 관심종목 스냅샷 구성
  @override
  Future<WatchlistSnapshot> fetchWatchlist({DateTime? asOf}) async {
    // DONE(assignment): Build the watchlist snapshot from Naver data.
    //
    // Suggested flow:
    // 1. Load canonical favorite ids via loadFavoriteIds().
    // 2. Convert each id into a six-digit domestic symbol.
    // 3. Load metadata and realtime quotes for those symbols.
    // 4. When asOf is null, use the latest historical row for each symbol.
    // 5. When asOf is provided, resolve the selected trading day and build a
    //    one-day snapshot for that date.
    // 6. Map every symbol into WatchlistItem.
    //
    // Related tests:
    // - test/features/watchlist/data/naver_watchlist_repository_test.dart

    // 6자리 숫자 국내 주식 심볼로 변환
    final favoriteIds = await loadFavoriteIds();
    final symbolList = favoriteIds
        .map(domesticSymbolFromFavoriteId)
        .whereType<String>()
        .toList(growable: false);

    WatchlistSnapshot snapshot;
    if (asOf == null) {
      // 3. 메타데이터와 실시간 시세를 가져온다. 서로 의존성이 없으므로 병렬 실행한다.
      final (metaDataResults, realtimeQuoteResults) = await (
        _loadMetadataBatch(symbolList),
        _loadRealtimeQuotes(symbolList),
      ).wait;

      // 4. asOf가 null이면 각 symbol의 최신 historical row를 사용한다.
      final historicalEntries = await _runInBatches(
        items: symbolList,
        batchSize: dailyHistoryFetchBatchSize,
        action: _loadLatestHistoricalEntry,
      );

      DateTime? latestDate;
      for (final entry in historicalEntries) {
        if (entry == null) continue;
        final entryDate = normalizeAsOfDate(entry.row.localDate);
        if (latestDate == null || entryDate.isAfter(latestDate)) {
          latestDate = entryDate;
        }
      }

      // 6. 모든 symbol을 WatchlistItem으로 매핑한다.
      final watchlistItems = <WatchlistItem>[];
      for (var index = 0; index < symbolList.length; index++) {
        final symbol = symbolList[index];
        final metadata = metaDataResults[symbol];
        final historicalEntry = historicalEntries[index];
        if (metadata == null || historicalEntry == null) {
          continue;
        }
        watchlistItems.add(
          _buildWatchlistItem(
            symbol: symbol,
            metadata: metadata,
            historicalEntry: historicalEntry,
            realtimeQuote: realtimeQuoteResults[symbol],
            latestDate: latestDate,
          ),
        );
      }

      snapshot = WatchlistSnapshot(
        asOf: latestDate ?? normalizeAsOfDate(DateTime.now()),
        items: List<WatchlistItem>.unmodifiable(watchlistItems),
      );
    } else {
      // 3. 메타데이터, 실시간 시세, 거래일 목록은 서로 의존성이 없으므로
      //    병렬로 가져온다.
      // 5. asOf가 제공되면 선택된 거래일을 확정하고 해당 날짜의
      //    하루치 스냅샷을 만든다.
      final (metaDataResults, realtimeQuoteResults, availableDates) = await (
        _loadMetadataBatch(symbolList),
        _loadRealtimeQuotes(symbolList),
        fetchAvailableDates(),
      ).wait;

      final resolvedAsOf = _resolveAsOf(availableDates, asOf);
      final latestAvailableDate = availableDates.isEmpty
          ? null
          : availableDates.first; // 최신

      final historicalEntries = await _runInBatches(
        items: symbolList,
        batchSize: dailyHistoryFetchBatchSize,
        action: (symbol) => _loadHistoricalEntryForDate(
          symbol: symbol,
          availableDates: availableDates,
          asOf: resolvedAsOf,
        ),
      );

      // 6. 모든 symbol을 WatchlistItem으로 매핑한다.
      final watchlistItems = <WatchlistItem>[];
      for (var index = 0; index < symbolList.length; index++) {
        final symbol = symbolList[index];
        final metadata = metaDataResults[symbol];
        final historicalEntry = historicalEntries[index];
        if (metadata == null || historicalEntry == null) {
          continue;
        }
        watchlistItems.add(
          _buildWatchlistItem(
            symbol: symbol,
            metadata: metadata,
            historicalEntry: historicalEntry,
            realtimeQuote: realtimeQuoteResults[symbol],
            latestDate: latestAvailableDate,
          ),
        );
      }

      snapshot = WatchlistSnapshot(
        asOf: resolvedAsOf,
        items: List<WatchlistItem>.unmodifiable(watchlistItems),
        availableDates: availableDates,
      );
    }

    return snapshot;
  }

  // 선택 가능한 거래일 목록 조회
  @override
  Future<List<DateTime>> fetchAvailableDates() async {
    final cached = _availableDatesCache;
    if (cached != null) {
      return cached;
    }

    final inFlightLoad = _availableDatesLoadFuture;
    if (inFlightLoad != null) {
      return inFlightLoad;
    }

    final loadFuture = _loadAvailableDates();
    _availableDatesLoadFuture = loadFuture;
    try {
      final availableDates = await loadFuture;
      _availableDatesCache = availableDates;
      return availableDates;
    } finally {
      if (identical(_availableDatesLoadFuture, loadFuture)) {
        _availableDatesLoadFuture = null;
      }
    }
  }

  Future<List<DateTime>> _loadAvailableDates() async {
    final favoriteIds = await loadFavoriteIds();
    final referenceSymbol = favoriteIds
        .map(domesticSymbolFromFavoriteId)
        .whereType<String>()
        .firstOrNull;

    if (referenceSymbol == null) {
      return const [];
    }

    final firstPage = await _loadDailyHistoryPage(referenceSymbol, 1);
    final pages = [firstPage];

    for (
      var batchStart = 2;
      batchStart <= firstPage.lastPage;
      batchStart += dailyHistoryFetchBatchSize
    ) {
      final batchEnd = (batchStart + dailyHistoryFetchBatchSize - 1).clamp(
        batchStart,
        firstPage.lastPage,
      );
      final batchPages = await Future.wait([
        for (var page = batchStart; page <= batchEnd; page++)
          _loadDailyHistoryPage(referenceSymbol, page),
      ]);
      pages.addAll(batchPages);
    }

    final availableDates = [
      for (final page in pages)
        for (final row in page.priceInfos) row.localDate,
    ];

    return List<DateTime>.unmodifiable(availableDates);
  }

  // 종목 상세 데이터 구성
  @override
  Future<WatchlistDetail> fetchWatchlistDetail({
    required String symbol,
    required MarketType market,
    DateTime? asOf,
  }) async {
    // DONE(assignment): Build the detail panel from a 30-trading-day window.
    //
    // Requirements:
    // - Only domestic stocks are supported.
    // - When asOf is null, show the latest available detail.
    // - When asOf is set, resolve the requested trading day and collect the
    //   previous 30 trading days (including the selected day).
    // - Use realtime data only for the latest trading day.
    // - Compute changeAmount, changeRate, volumeRatio, and candles.
    if (market != MarketType.domestic) {
      throw UnsupportedError(
        'Naver repository only supports domestic watchlist detail.',
      );
    }

    final availableDates = await fetchAvailableDates();
    // resolvedAsOf는 거래일 목록에서 asOf를 기준으로 가장 가까운 거래일을 결정한다.
    final resolvedAsOf = _resolveAsOf(availableDates, asOf);
    final selectedIndex = _indexOfDate(availableDates, resolvedAsOf);
    if (selectedIndex == null) {
      throw StateError('No trading-day data available for "$symbol".');
    }

    final windowDatesDescending = availableDates
        .skip(selectedIndex)
        .take(30)
        .toList(growable: false);
    final pageNumbers = {
      for (
        var index = selectedIndex;
        index < selectedIndex + windowDatesDescending.length;
        index++
      )
        _pageNumberForIndex(index),
    }.toList(growable: false);
    final List<NaverDailyHistoryPageDto> pages = await Future.wait([
      for (final pageNumber in pageNumbers)
        _loadDailyHistoryPage(symbol, pageNumber),
    ]);
    final rowsByDate = <String, NaverHistoricalPriceDto>{
      for (final page in pages)
        for (final row in page.priceInfos) _dateKey(row.localDate): row,
    };

    final selectedDateKey = _dateKey(resolvedAsOf);
    final historicalRow = rowsByDate[selectedDateKey];
    if (historicalRow == null) {
      throw StateError(
        'Missing historical row for "$symbol" on $resolvedAsOf.',
      );
    }

    final previousClose = await _resolvePreviousClose(
      symbol: symbol,
      availableDates: availableDates,
      selectedIndex: selectedIndex,
      fallbackOpenPrice: historicalRow.openPrice,
      rowsByDate: rowsByDate,
    );

    final latestAvailableDate = availableDates.firstOrNull;
    final isLatest =
        latestAvailableDate != null && resolvedAsOf == latestAvailableDate;
    final realtimeQuote = isLatest
        ? (await _loadRealtimeQuotes([symbol]))[symbol]
        : null;

    if (realtimeQuote != null) {
      rowsByDate[selectedDateKey] = NaverHistoricalPriceDto(
        localDate: resolvedAsOf,
        closePrice: realtimeQuote.currentPrice,
        openPrice: realtimeQuote.openPrice,
        highPrice: realtimeQuote.highPrice,
        lowPrice: realtimeQuote.lowPrice,
        accumulatedTradingVolume: realtimeQuote.accumulatedTradingVolume,
      );
    }

    final selectedRow = rowsByDate[selectedDateKey]!;
    final currentPrice = selectedRow.closePrice;
    final changeAmount = currentPrice - previousClose;
    final changeRate = _percentChange(changeAmount, previousClose);

    return WatchlistDetail(
      itemId: canonicalDomesticFavoriteId(symbol),
      symbol: symbol,
      market: market,
      currency: 'KRW',
      currentPrice: currentPrice,
      changeAmount: changeAmount,
      changeRate: changeRate,
      tradeVolume: selectedRow.accumulatedTradingVolume,
      volumeRatio: _volumeRatio(
        windowDatesDescending: windowDatesDescending,
        rowsByDate: rowsByDate,
      ),
      openPrice: selectedRow.openPrice,
      openChangeRate: _percentChange(
        selectedRow.openPrice - previousClose,
        previousClose,
      ),
      highPrice: selectedRow.highPrice,
      highChangeRate: _percentChange(
        selectedRow.highPrice - previousClose,
        previousClose,
      ),
      lowPrice: selectedRow.lowPrice,
      lowChangeRate: _percentChange(
        selectedRow.lowPrice - previousClose,
        previousClose,
      ),
      candles: _candles(
        windowDatesDescending: windowDatesDescending,
        rowsByDate: rowsByDate,
      ),
    );
  }

  // 국내 종목 검색 결과 변환
  @override
  Future<List<StockSearchItem>> searchStocks({required String query}) async {
    // Requirements:
    // - Trim the query and return [] for empty input.
    // - Use _client.searchStocks(trimmedQuery).
    // - Keep only domestic six-digit stock results.
    // - Deduplicate duplicate symbols.
    // - Convert every symbol into canonical id: domestic:{symbol}
    // - Set isFavorite by comparing against loadFavoriteIds().
    // - Fill logoUrl via _logoUrlResolver.
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const [];
    }

    final (items, favoriteIds) = await (
      _client.searchStocks(trimmedQuery),
      loadFavoriteIds(),
    ).wait;
    final Set<String> seenSymbols = {};

    return items
        .where((item) => item.isDomesticStock && seenSymbols.add(item.code))
        .map(
          // make canonical id
          (item) => item.toStockSearchItem(
            isFavorite: favoriteIds.contains(
              canonicalDomesticFavoriteId(item.code),
            ),
            logoUrl: _logoUrlResolver.resolveDomesticStockLogoUrl(item.code),
          ),
        )
        .toList(growable: false);
  }

  // 저장된 관심종목 id 정리 후 반환
  @override
  Future<Set<String>> loadFavoriteIds() async {
    if (_favoriteIdsCache != null) {
      return Set<String>.unmodifiable(_favoriteIdsCache!);
    }

    final rawIds = await _favoriteIdsLocalStore.loadRawIds();
    final canonicalIds = rawIds.where(_isCanonicalFavoriteId).toSet();
    final hasLegacyOrInvalidIds =
        rawIds.isNotEmpty && canonicalIds.length != rawIds.length;

    final resolvedIds = !_favoriteIdsLocalStore.hasStoredIds
        ? <String>{...defaultNaverDomesticFavoriteIds}
        : hasLegacyOrInvalidIds
        ? <String>{...defaultNaverDomesticFavoriteIds}
        : canonicalIds;

    _favoriteIdsCache = resolvedIds;

    if (!setEquals(rawIds, resolvedIds)) {
      await _favoriteIdsLocalStore.saveRawIds(resolvedIds);
    }

    return Set<String>.unmodifiable(resolvedIds);
  }

  // 관심종목 추가 저장
  @override
  Future<void> addFavorite({required String itemId}) async {
    final canonicalId = _requireCanonicalFavoriteId(itemId);
    final favoriteIds = {...await loadFavoriteIds(), canonicalId};
    _favoriteIdsCache = favoriteIds;
    await _favoriteIdsLocalStore.saveRawIds(favoriteIds);
  }

  // 관심종목 제거 저장
  @override
  Future<void> removeFavorite({required String itemId}) async {
    final canonicalId = _requireCanonicalFavoriteId(itemId);
    final favoriteIds = {...await loadFavoriteIds()}..remove(canonicalId);
    _favoriteIdsCache = favoriteIds;
    await _favoriteIdsLocalStore.saveRawIds(favoriteIds);
  }

  // 메타데이터 여러 종목 로드
  Future<Map<String, NaverChartMetadataDto>> _loadMetadataBatch(
    List<String> symbols,
  ) async {
    final results = <String, NaverChartMetadataDto>{};
    for (final symbol in symbols) {
      try {
        results[symbol] = await _loadMetadata(symbol);
      } catch (error, stackTrace) {
        debugPrint('Skipping Naver metadata for $symbol: $error\n$stackTrace');
      }
    }
    return results;
  }

  // 메타데이터 캐시 조회 후 로드
  Future<NaverChartMetadataDto> _loadMetadata(String symbol) async {
    final cached = _metadataCache[symbol];
    if (cached != null) {
      // 성공 캐시는 TTL 없이 계속 재사용하고, fallback 캐시는
      // _metadataFailureRetryTtl이 지나기 전까지만 재사용한다.
      final isReusableFallback =
          cached.isFallback &&
          DateTime.now().difference(cached.fetchedAt) <
              _metadataFailureRetryTtl;
      if (!cached.isFallback || isReusableFallback) {
        return cached.metadata;
      }
    }

    NaverChartMetadataDto metadata;
    var isFallback = false;
    try {
      metadata = await _client.fetchChartMetadata(symbol);
    } catch (error) {
      // metadata는 라벨 보강값이므로 실패해도 가격 행까지 버리지 않는다.
      debugPrint('Using fallback Naver metadata for $symbol: $error');
      metadata = NaverChartMetadataDto(
        symbol: symbol,
        stockName: symbol,
        stockExchangeNameKor: '국내',
      );
      isFallback = true;
    }
    _metadataCache[symbol] = _MetadataCacheEntry(
      metadata: metadata,
      isFallback: isFallback,
      fetchedAt: DateTime.now(),
    );
    return metadata;
  }

  // 일별 시세 페이지 캐시 조회 후 로드
  Future<NaverDailyHistoryPageDto> _loadDailyHistoryPage(
    String symbol,
    int page,
  ) async {
    final cacheKey = _dailyHistoryPageCacheKey(symbol, page);
    final cached = _dailyHistoryPageCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final historyPage = await _client.fetchDailyHistoryPage(
      symbol: symbol,
      page: page,
    );
    _dailyHistoryPageCache[cacheKey] = historyPage;
    return historyPage;
  }

  // 실시간 시세 캐시 조회 후 배치 로드
  Future<Map<String, NaverRealtimeQuoteDto>> _loadRealtimeQuotes(
    Iterable<String> symbols,
  ) async {
    final requestedSymbols = symbols.toSet();
    final now = DateTime.now();
    final missingSymbols = <String>[];
    final quotes = <String, NaverRealtimeQuoteDto>{};

    for (final symbol in requestedSymbols) {
      final cached = _realtimeQuoteCache[symbol];
      final isFresh =
          cached != null &&
          now.difference(cached.fetchedAt) <= realtimeCacheTtl;
      if (isFresh) {
        quotes[symbol] = cached.quote;
      } else {
        missingSymbols.add(symbol);
      }
    }

    if (missingSymbols.isNotEmpty) {
      try {
        final fetchedQuotes = await _client.fetchRealtimeQuotes(missingSymbols);
        final fetchedAt = DateTime.now();
        for (final entry in fetchedQuotes.entries) {
          _realtimeQuoteCache[entry.key] = _RealtimeQuoteCacheEntry(
            quote: entry.value,
            fetchedAt: fetchedAt,
          );
          quotes[entry.key] = entry.value;
        }
      } catch (error, stackTrace) {
        debugPrint(
          'Falling back to historical-only Naver data for realtime batch: '
          '$error\n$stackTrace',
        );
      }
    }

    return quotes;
  }

  // 특정 거래일의 히스토리 엔트리 조회
  Future<_HistoricalEntry?> _loadHistoricalEntryForDate({
    required String symbol,
    required List<DateTime> availableDates,
    required DateTime asOf,
  }) async {
    final selectedIndex = _indexOfDate(availableDates, asOf);
    if (selectedIndex == null) {
      return null;
    }

    final selectedPageNumber = _pageNumberForIndex(selectedIndex);
    final selectedPage = await _loadDailyHistoryPage(
      symbol,
      selectedPageNumber,
    );
    final selectedRow = _rowForDate(selectedPage.priceInfos, asOf);
    if (selectedRow == null) {
      return null;
    }

    final previousClose = await _resolvePreviousClose(
      symbol: symbol,
      availableDates: availableDates,
      selectedIndex: selectedIndex,
      fallbackOpenPrice: selectedRow.openPrice,
      rowsByDate: {
        for (final row in selectedPage.priceInfos) _dateKey(row.localDate): row,
      },
    );

    return _HistoricalEntry(row: selectedRow, previousClose: previousClose);
  }

  // 최신 거래일 히스토리 엔트리 조회
  Future<_HistoricalEntry?> _loadLatestHistoricalEntry(String symbol) async {
    final firstPage = await _loadDailyHistoryPage(symbol, 1);
    if (firstPage.priceInfos.isEmpty) {
      return null;
    }

    final selectedRow = firstPage.priceInfos.first;
    double previousClose = selectedRow.openPrice;
    if (firstPage.priceInfos.length > 1) {
      previousClose = firstPage.priceInfos[1].closePrice;
    } else {
      final nextPageRows = (await _loadDailyHistoryPage(symbol, 2)).priceInfos;
      if (nextPageRows.isNotEmpty) {
        previousClose = nextPageRows.first.closePrice;
      }
    }

    return _HistoricalEntry(row: selectedRow, previousClose: previousClose);
  }

  // 전일 종가 계산
  Future<double> _resolvePreviousClose({
    required String symbol,
    required List<DateTime> availableDates,
    required int selectedIndex,
    required double fallbackOpenPrice,
    required Map<String, NaverHistoricalPriceDto> rowsByDate,
  }) async {
    if (selectedIndex >= availableDates.length - 1) {
      return fallbackOpenPrice;
    }

    final previousDate = availableDates[selectedIndex + 1];
    final previousRowFromCache = rowsByDate[_dateKey(previousDate)];
    if (previousRowFromCache != null) {
      return previousRowFromCache.closePrice;
    }

    final page = await _loadDailyHistoryPage(
      symbol,
      _pageNumberForIndex(selectedIndex + 1),
    );
    final previousRow = _rowForDate(page.priceInfos, previousDate);
    return previousRow?.closePrice ?? fallbackOpenPrice;
  }

  // 히스토리와 실시간 시세로 리스트 아이템 생성
  WatchlistItem _buildWatchlistItem({
    required String symbol,
    required NaverChartMetadataDto metadata,
    required _HistoricalEntry historicalEntry,
    required NaverRealtimeQuoteDto? realtimeQuote,
    required DateTime? latestDate,
  }) {
    final isLatest =
        latestDate != null &&
        normalizeAsOfDate(historicalEntry.row.localDate) == latestDate;
    final currentPrice = isLatest && realtimeQuote != null
        ? realtimeQuote.currentPrice
        : historicalEntry.row.closePrice;
    final changeRate = isLatest && realtimeQuote != null
        ? realtimeQuote.changeRate
        : _percentChange(
            currentPrice - historicalEntry.previousClose,
            historicalEntry.previousClose,
          );
    final tradeVolume = isLatest && realtimeQuote != null
        ? realtimeQuote.accumulatedTradingVolume
        : historicalEntry.row.accumulatedTradingVolume;
    final marketCap = realtimeQuote == null
        ? 0
        : (realtimeQuote.countOfListedStock * realtimeQuote.currentPrice)
              .round();

    return WatchlistItem(
      id: canonicalDomesticFavoriteId(symbol),
      market: MarketType.domestic,
      symbol: symbol,
      name: metadata.stockName,
      currency: 'KRW',
      currentPrice: currentPrice,
      changeRate: changeRate,
      tradeVolume: tradeVolume,
      marketCap: marketCap,
      logoUrl: _logoUrlResolver.resolveDomesticStockLogoUrl(symbol),
    );
  }

  // 요청 날짜를 실제 조회 날짜로 보정
  DateTime _resolveAsOf(
    List<DateTime> availableDates,
    DateTime? requestedAsOf,
  ) {
    if (availableDates.isEmpty) {
      return normalizeAsOfDate(requestedAsOf ?? DateTime.now());
    }

    if (requestedAsOf == null) {
      return availableDates.first;
    }

    final normalizedAsOf = normalizeAsOfDate(requestedAsOf);
    for (final date in availableDates) {
      if (date == normalizedAsOf) {
        return date;
      }
    }

    return availableDates.first;
  }

  // 거래일 목록에서 날짜 위치 찾기
  int? _indexOfDate(List<DateTime> availableDates, DateTime asOf) {
    final normalizedAsOf = normalizeAsOfDate(asOf);
    for (var index = 0; index < availableDates.length; index++) {
      if (availableDates[index] == normalizedAsOf) {
        return index;
      }
    }
    return null;
  }

  // 거래일 인덱스를 페이지 번호로 변환
  int _pageNumberForIndex(int index) {
    return (index ~/ _historyRowsPerPage) + 1;
  }

  // 항목들을 일정 개수씩 나눠 실행
  Future<List<T?>> _runInBatches<S, T>({
    required List<S> items,
    required int batchSize,
    required Future<T> Function(S item) action,
  }) async {
    final results = <T?>[];
    for (var i = 0; i < items.length; i += batchSize) {
      final batch = items.skip(i).take(batchSize);
      final batchResults = await Future.wait(
        batch.map((item) async {
          try {
            return await action(item);
          } catch (error, stackTrace) {
            debugPrint('Skipping batch item "$item": $error\n$stackTrace');
            return null;
          }
        }),
      );
      results.addAll(batchResults);
    }
    return results;
  }

  // 특정 날짜의 시세 row 찾기
  NaverHistoricalPriceDto? _rowForDate(
    Iterable<NaverHistoricalPriceDto> rows,
    DateTime date,
  ) {
    final dateKey = _dateKey(date);
    for (final row in rows) {
      if (_dateKey(row.localDate) == dateKey) {
        return row;
      }
    }
    return null;
  }

  // 거래량 비율 계산
  double _volumeRatio({
    required List<DateTime> windowDatesDescending,
    required Map<String, NaverHistoricalPriceDto> rowsByDate,
  }) {
    if (windowDatesDescending.isEmpty) {
      return 0;
    }

    final selectedRow = rowsByDate[_dateKey(windowDatesDescending.first)];
    if (selectedRow == null) {
      return 0;
    }

    final previousVolumes = <int>[];
    for (
      var index = 1;
      index < windowDatesDescending.length && previousVolumes.length < 5;
      index += 1
    ) {
      final row = rowsByDate[_dateKey(windowDatesDescending[index])];
      if (row != null) {
        previousVolumes.add(row.accumulatedTradingVolume);
      }
    }

    if (previousVolumes.isEmpty) {
      return 0;
    }

    final averageVolume =
        previousVolumes.reduce((left, right) => left + right) /
        previousVolumes.length;
    if (averageVolume == 0) {
      return 0;
    }

    return double.parse(
      (selectedRow.accumulatedTradingVolume / averageVolume).toStringAsFixed(2),
    );
  }

  // 캔들 차트용 데이터 생성
  List<CandlePoint> _candles({
    required List<DateTime> windowDatesDescending,
    required Map<String, NaverHistoricalPriceDto> rowsByDate,
  }) {
    return windowDatesDescending.reversed
        .map((date) => rowsByDate[_dateKey(date)])
        .whereType<NaverHistoricalPriceDto>()
        .map(
          (item) => CandlePoint(
            time: item.localDate,
            open: item.openPrice,
            high: item.highPrice,
            low: item.lowPrice,
            close: item.closePrice,
            direction: directionFromDelta(item.closePrice - item.openPrice),
          ),
        )
        .toList(growable: false);
  }

  // 관심종목 id 형식 확인
  bool _isCanonicalFavoriteId(String itemId) {
    return domesticSymbolFromFavoriteId(itemId) != null;
  }

  // 관심종목 id 형식 검증 후 정규화
  String _requireCanonicalFavoriteId(String itemId) {
    final symbol = domesticSymbolFromFavoriteId(itemId);
    if (symbol == null) {
      throw ArgumentError.value(
        itemId,
        'itemId',
        'Naver repository only accepts canonical domestic favorite ids',
      );
    }
    return canonicalDomesticFavoriteId(symbol);
  }

  // 일별 시세 페이지 캐시 키 생성
  String _dailyHistoryPageCacheKey(String symbol, int page) => '$symbol::$page';

  // 날짜를 내부 키 형식으로 변환
  String _dateKey(DateTime value) => formatApiDate(value);

  // 등락률 계산
  double _percentChange(double delta, double base) {
    if (base == 0) {
      return 0;
    }
    return double.parse(((delta / base) * 100).toStringAsFixed(2));
  }
}

class _RealtimeQuoteCacheEntry {
  const _RealtimeQuoteCacheEntry({
    required this.quote,
    required this.fetchedAt,
  });

  final NaverRealtimeQuoteDto quote;
  final DateTime fetchedAt;
}

class _MetadataCacheEntry {
  const _MetadataCacheEntry({
    required this.metadata,
    required this.isFallback,
    required this.fetchedAt,
  });

  final NaverChartMetadataDto metadata;
  final bool isFallback;
  final DateTime fetchedAt;
}

class _HistoricalEntry {
  const _HistoricalEntry({required this.row, required this.previousClose});

  final NaverHistoricalPriceDto row;
  final double previousClose;
}
