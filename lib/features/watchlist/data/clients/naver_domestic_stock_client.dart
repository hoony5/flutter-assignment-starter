// ignore_for_file: unused_element, unused_field

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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

      final body = _decodeJsonObjectBody(response.data, 'searchStocks');
      final items = body['items'];
      if (items is! List) {
        throw FormatException('searchStocks response is missing "items"');
      }

      return items
          .map(
            (item) => NaverAutocompleteItemDto.fromJson(
              _asStringKeyedMap(item, 'searchStocks.items'),
            ),
          )
          .toList(growable: false);
    } catch (error, stackTrace) {
      debugPrint('searchStocks failed for "$query": $error\n$stackTrace');
      rethrow;
    }
  }

  @override
  Future<Map<String, NaverRealtimeQuoteDto>> fetchRealtimeQuotes(
    Iterable<String> symbols,
  ) async {
    final dedupedSymbols = symbols.toSet();
    if (dedupedSymbols.isEmpty) {
      return {};
    }

    try {
      final query = dedupedSymbols
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

      final body = _decodeJsonObjectBody(response.data, 'fetchRealtimeQuotes');
      final result = _asStringKeyedMap(
        body['result'],
        'fetchRealtimeQuotes.result',
      );
      final areas = result['areas'];
      if (areas is! List) {
        throw FormatException(
          'fetchRealtimeQuotes response is missing "result.areas"',
        );
      }

      final quotes = <String, NaverRealtimeQuoteDto>{};
      for (final area in areas) {
        final areaMap = _asStringKeyedMap(
          area,
          'fetchRealtimeQuotes.result.areas',
        );
        final datas = areaMap['datas'];
        if (datas is! List) {
          continue;
        }

        for (final data in datas) {
          final quote = NaverRealtimeQuoteDto.fromJson(
            _asStringKeyedMap(data, 'fetchRealtimeQuotes.result.areas.datas'),
          );
          quotes[quote.symbol] = quote;
        }
      }

      return quotes;
    } catch (error, stackTrace) {
      debugPrint(
        'fetchRealtimeQuotes failed for "$dedupedSymbols": $error\n$stackTrace',
      );
      rethrow;
    }
  }

  @override
  Future<NaverChartMetadataDto> fetchChartMetadata(String symbol) async {
    // TODO(assignment): Implement the chart metadata request.
    //
    // Goal:
    // - Call
    //   https://stock.naver.com/api/securityFe/api/fchart/domestic/stock/{symbol}
    // - Decode the JSON object with _decodeJsonObjectBody.
    // - Convert the payload with NaverChartMetadataDto.fromJson.
    //
    // Required fields for the DTO:
    // - symbolCode
    // - stockName
    // - stockExchangeNameKor
    throw UnimplementedError(
      'TODO(assignment): implement NaverDomesticStockClient.fetchChartMetadata',
    );
  }

  @override
  Future<NaverDailyHistoryPageDto> fetchDailyHistoryPage({
    required String symbol,
    required int page,
  }) async {
    // TODO(assignment): Implement parsing for the legacy daily history page.
    //
    // Goal:
    // - Validate that page >= 1.
    // - Request https://finance.naver.com/item/sise_day.naver
    //   with code=<symbol> and page=<page>.
    // - Use ResponseType.bytes and decode the HTML with latin1.
    // - Parse one page of historical rows from the HTML table.
    // - For each row, extract:
    //   - localDate (yyyyMMdd)
    //   - closePrice
    //   - openPrice
    //   - highPrice
    //   - lowPrice
    //   - accumulatedTradingVolume
    // - Also extract lastPage from the pagination area.
    //
    // Hint:
    // - The rendered table order is close, change, open, high, low, volume.
    // - You can keep using NaverHistoricalPriceDto.fromJson to build rows.
    throw UnimplementedError(
      'TODO(assignment): implement NaverDomesticStockClient.fetchDailyHistoryPage',
    );
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
