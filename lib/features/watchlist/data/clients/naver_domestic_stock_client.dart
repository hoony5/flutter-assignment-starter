// ignore_for_file: unused_element, unused_field

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../dtos/naver_stock_dtos.dart';

abstract interface class NaverStockDataClient {
  Future<List<NaverAutocompleteItemDto>> searchStocks(String query);

  Future<Map<String, NaverRealtimeQuoteDto>> fetchRealtimeQuotes(
    Iterable<String> symbols,
  );

  Future<NaverChartMetadataDto> fetchChartMetadata(String symbol);

  Future<NaverDailyHistoryPageDto> fetchDailyHistoryPage({
    required String symbol,
    required int page,
  });
}

class NaverDomesticStockClient implements NaverStockDataClient {
  const NaverDomesticStockClient(this._dio);

  final Dio _dio;

  static const Map<String, String> _defaultHeaders = {
    'accept': 'application/json, text/plain, */*',
    'referer': 'https://m.stock.naver.com/',
    'accept-language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
    'user-agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/123.0.0.0 Safari/537.36',
  };

  static Map<String, dynamic> _decodeJsonObjectBody(
    Object? data,
    String contextLabel,
  ) {
    if (data == null) {
      throw FormatException('$contextLabel response body is empty');
    }

    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw FormatException('$contextLabel response is not a JSON object');
    }

    if (data is List<int>) {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw FormatException('$contextLabel response is not a JSON object');
    }

    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }

    throw FormatException('$contextLabel response body has unsupported shape');
  }

  static Map<String, dynamic> _asStringKeyedMap(
    Object? value,
    String contextLabel,
  ) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    throw FormatException('$contextLabel is not a JSON object');
  }

  @override
  Future<List<NaverAutocompleteItemDto>> searchStocks(String query) async {
    const String context = 'searchStocks';
    try {
      final response = await _dio.get<Object?>(
        'https://ac.stock.naver.com/ac',
        queryParameters: {
          'q': query,
          'target': 'stock,ipo,index,marketindicator',
        },
        options: Options(
          headers: _defaultHeaders,
          responseType: ResponseType.plain,
        ),
      );

      final body = _decodeJsonObjectBody(response.data, context);
      final items = body['items'];
      if (items is! List) {
        throw FormatException('$context response is missing "items"');
      }

      final parsedItems = <NaverAutocompleteItemDto>[];
      for (final (index, item) in items.indexed) {
        try {
          parsedItems.add(
            NaverAutocompleteItemDto.fromJson(
              _asStringKeyedMap(item, '$context.items'),
            ),
          );
        } on FormatException catch (error) {
          // TODO(today): 깨진 자동완성 row 하나가 전체 검색을 실패시키지 않게 한다.
          // 자동완성은 혼합 타입 응답이라 깨진 개별 row만 건너뛴다.
          debugPrint(
            'Skipping malformed searchStocks item[$index] for "$query": '
            '$error\nraw=$item',
          );
          continue;
        }
      }
      return parsedItems;
    } catch (error, stackTrace) {
      debugPrint('searchStocks failed for "$query": $error\n$stackTrace');
      rethrow;
    }
  }

  @override
  Future<Map<String, NaverRealtimeQuoteDto>> fetchRealtimeQuotes(
    Iterable<String> symbols,
  ) async {
    const String context = 'fetchRealtimeQuotes';

    try {
      final String query = symbols
          .map((symbol) => 'SERVICE_ITEM:$symbol')
          .join(',');

      final response = await _dio.get<Object?>(
        'https://polling.finance.naver.com/api/realtime',
        queryParameters: {'query': query},
        options: Options(
          headers: _defaultHeaders,
          responseType: ResponseType.plain,
        ),
      );

      // 목표 : response.areas.datas > NaverRealtimeQuoteDto
      final body = _decodeJsonObjectBody(response.data, context);
      final result = _asStringKeyedMap(body['result'], '$context.result');
      final areas = result['areas'];
      if (areas is! List) {
        throw FormatException('$context response is missing "result.areas"');
      }

      final quotes = <String, NaverRealtimeQuoteDto>{};
      for (final area in areas) {
        final datas = _asStringKeyedMap(area, '$context.result.areas')['datas'];
        if (datas is! List) {
          continue;
        }

        for (final quote in datas
            .map(_parseRealtimeQuoteItem)
            .whereType<NaverRealtimeQuoteDto>()) {
          quotes[quote.symbol] = quote;
        }
      }

      return quotes;
    } catch (error, stackTrace) {
      debugPrint(
        'fetchRealtimeQuotes failed for "$symbols": $error\n$stackTrace',
      );
      rethrow;
    }
  }

  // 깨진 개별 실시간 시세 row 하나가 배치 전체(다른 심볼들의 시세까지)를
  // 실패시키지 않게 한다. _parseHistoricalPriceRow와 동일하게 null을 반환해
  // 호출부에서 .whereType()으로 걸러내는 패턴을 쓴다.
  static NaverRealtimeQuoteDto? _parseRealtimeQuoteItem(Object? data) {
    try {
      return NaverRealtimeQuoteDto.fromJson(
        _asStringKeyedMap(data, 'fetchRealtimeQuotes.result.areas.datas'),
      );
    } on FormatException catch (error) {
      debugPrint('Skipping malformed realtime quote: $error\nraw=$data');
      return null;
    }
  }

  @override
  Future<NaverChartMetadataDto> fetchChartMetadata(String symbol) async {
    const String context = 'fetchChartMetadata';
    try {
      final response = await _dio.get<Object?>(
        'https://stock.naver.com/api/securityFe/api/fchart/domestic/stock/$symbol',
        options: Options(
          headers: _defaultHeaders,
          responseType: ResponseType.plain,
        ),
      );

      final body = _decodeJsonObjectBody(response.data, context);
      return NaverChartMetadataDto.fromJson(_asStringKeyedMap(body, context));
    } catch (error, stackTrace) {
      debugPrint(
        'fetchChartMetadata failed for "$symbol": $error\n$stackTrace',
      );
      rethrow;
    }
  }

  @override
  Future<NaverDailyHistoryPageDto> fetchDailyHistoryPage({
    required String symbol,
    required int page,
  }) async {
    if (page < 1) {
      throw ArgumentError.value(page, 'page', 'must be >= 1');
    }
    const String context = 'fetchDailyHistoryPage';
    try {
      final response = await _dio.get<Object?>(
        'https://finance.naver.com/item/sise_day.naver',
        queryParameters: {'code': symbol, 'page': page},
        options: Options(
          headers: _defaultHeaders,
          responseType: ResponseType.bytes,
        ),
      );

      // html_parser.parse()는 UTF-8을 기본으로 사용하므로, Naver의 EUC-KR 페이지를 처리하기 위해 latin1.decode()를 사용합니다.
      final body = latin1.decode(response.data as List<int>);
      final document = html_parser.parse(body);

      final priceInfos = document
          .querySelectorAll('table.type2 tr')
          .map(_parseHistoricalPriceRow)
          .whereType<NaverHistoricalPriceDto>()
          .toList(growable: false);
      if (priceInfos.isEmpty) {
        throw FormatException('$context found no rows for "$symbol"');
      }

      final lastPage = _parseLastPage(document, currentPage: page);

      return NaverDailyHistoryPageDto(
        symbol: symbol,
        page: page,
        lastPage: lastPage,
        priceInfos: priceInfos,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'fetchDailyHistoryPage failed for "$symbol" page $page: '
        '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static NaverHistoricalPriceDto? _parseHistoricalPriceRow(Element row) {
    // 날짜, 종가, 전일비, 시가, 고가, 저가, 거래량, 예상 컬럼 수
    const int dateColumn = 0;
    const int closePriceColumn = 1;
    const int openPriceColumn = 3;
    const int highPriceColumn = 4;
    const int lowPriceColumn = 5;
    const int volumeColumn = 6;
    const int expectedColumnCount = 7;

    final cells = row.querySelectorAll('td');
    if (cells.length < expectedColumnCount) {
      return null;
    }

    final localDateText = cells[dateColumn].text.trim();
    if (localDateText.isEmpty) {
      return null;
    }

    return NaverHistoricalPriceDto.fromJson({
      'localDate': localDateText.replaceAll('.', ''),
      'closePrice': cells[closePriceColumn].text.trim(),
      'openPrice': cells[openPriceColumn].text.trim(),
      'highPrice': cells[highPriceColumn].text.trim(),
      'lowPrice': cells[lowPriceColumn].text.trim(),
      'accumulatedTradingVolume': cells[volumeColumn].text.trim(),
    });
  }

  static int _parseLastPage(Document document, {required int currentPage}) {
    final lastPageHref = document
        .querySelector('td.pgRR a')
        ?.attributes['href'];
    final lastPageMatch = lastPageHref == null
        ? null
        : RegExp(r'page=(\d+)').firstMatch(lastPageHref);
    if (lastPageMatch != null) {
      return int.parse(lastPageMatch.group(1)!);
    }

    final linkedPages = document
        .querySelectorAll('table.Nnavi a')
        .map((anchor) => anchor.attributes['href'])
        .whereType<String>()
        .map((href) => RegExp(r'page=(\d+)').firstMatch(href)?.group(1))
        .whereType<String>()
        .map(int.parse);

    // 마지막 링크가 생략되는 페이지가 있어 현재/노출 링크 기준으로 보정했습니다.
    var resolvedLastPage = currentPage;
    for (final linkedPage in linkedPages) {
      if (linkedPage > resolvedLastPage) {
        resolvedLastPage = linkedPage;
      }
    }
    return resolvedLastPage;
  }
}

double _parseDouble(String value) {
  return double.parse(value.replaceAll(',', ''));
}

int _parseInt(String value) {
  return int.parse(value.replaceAll(',', ''));
}

Map<String, String> naverDesktopLikeHeaders() =>
    Map<String, String>.unmodifiable(NaverDomesticStockClient._defaultHeaders);
