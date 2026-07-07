// ignore_for_file: unused_element

import 'package:sample/features/watchlist/domain/models/watchlist_models.dart';

import '../../domain/services/watchlist_sorting.dart';

/// 검색어 자동 완성 DTO:
/// - code : 종목코드
/// - name : 종목명
/// - typeCode : KOSPI, KOSDAQ 등
/// - typeName : typeCode 한글명
/// - url : 종목 상세 페이지 URL
/// - nationCode : 국가 코드 (KOR 만 가져올 것)
/// category : stock, index 등 (주식만 가져올 것)
class NaverAutocompleteItemDto {
  const NaverAutocompleteItemDto({
    required this.code,
    required this.name,
    required this.typeCode,
    required this.typeName,
    required this.url,
    required this.nationCode,
    required this.category,
  });

  factory NaverAutocompleteItemDto.fromJson(Map<String, dynamic> json) {
    const String conetxt = 'NaverAutocompleteItemDto';
    return NaverAutocompleteItemDto(
      code: _readString(json['code'], context: '$conetxt.code'),
      name: _readString(json['name'], context: '$conetxt.name'),
      typeCode: _readString(json['typeCode'], context: '$conetxt.typeCode'),
      typeName: _readString(json['typeName'], context: '$conetxt.typeName'),
      url: _readString(json['url'], context: '$conetxt.url'),
      nationCode: _readString(
        json['nationCode'],
        context: '$conetxt.nationCode',
      ),
      category: _readString(json['category'], context: '$conetxt.category'),
    );
  }

  final String code;
  final String name;
  final String typeCode;
  final String typeName;
  final String url;
  final String nationCode;
  final String category;

  bool get isDomesticStock =>
      category == 'stock' &&
      nationCode == 'KOR' &&
      RegExp(r'^\d{6}$').hasMatch(code) &&
      url.contains('/domestic/stock/');

  // todo : isFavorite, logoUrl 등은 외부에서 처리한걸 가져올수있는지 확인
  StockSearchItem toStockSearchItem({
    bool isFavorite = false,
    String? logoUrl,
  }) {
    return StockSearchItem(
      id: 'domestic:$code',
      market: MarketType.domestic,
      marketLabel: typeName,
      symbol: code,
      name: name,
      isFavorite: isFavorite,
      logoUrl: logoUrl,
    );
  }
}

/// 실시간 시세 DTO:
/// - cd : 종목코드 (symbol)
/// - nv : 현재가
/// - pcv : 전일대비 종가
/// - ov : 시가
/// - hv : 고가
/// - lv : 저가
/// - aq : 누적거래량
/// - countOfListedStock : 상장주식수
class NaverRealtimeQuoteDto {
  const NaverRealtimeQuoteDto({
    required this.symbol,
    required this.currentPrice,
    required this.previousClose,
    required this.openPrice,
    required this.highPrice,
    required this.lowPrice,
    required this.accumulatedTradingVolume,
    required this.countOfListedStock,
  });

  factory NaverRealtimeQuoteDto.fromJson(Map<String, dynamic> json) {
    const String context = 'NaverRealtimeQuoteDto';
    return NaverRealtimeQuoteDto(
      symbol: _readString(json['cd'], context: '$context.symbol'),
      currentPrice: _readDouble(json['nv'], context: '$context.currentPrice'),
      previousClose: _readDouble(
        json['pcv'],
        context: '$context.previousClose',
      ),
      openPrice: _readDouble(json['ov'], context: '$context.openPrice'),
      highPrice: _readDouble(json['hv'], context: '$context.highPrice'),
      lowPrice: _readDouble(json['lv'], context: '$context.lowPrice'),
      accumulatedTradingVolume: _readInt(
        json['aq'],
        context: '$context.accumulatedTradingVolume',
      ),
      countOfListedStock: _readInt(
        json['countOfListedStock'],
        context: '$context.countOfListedStock',
      ),
    );
  }

  final String symbol;
  final double currentPrice;
  final double previousClose;
  final double openPrice;
  final double highPrice;
  final double lowPrice;
  final int accumulatedTradingVolume;
  final int countOfListedStock;

  double get changeAmount => currentPrice - previousClose;

  double get changeRate {
    if (previousClose == 0) {
      return 0;
    }
    return double.parse(
      (((currentPrice - previousClose) / previousClose) * 100).toStringAsFixed(
        2,
      ),
    );
  }
}

class NaverChartMetadataDto {
  const NaverChartMetadataDto({
    required this.symbol,
    required this.stockName,
    required this.stockExchangeNameKor,
  });

  factory NaverChartMetadataDto.fromJson(Map<String, dynamic> json) {
    const String context = 'NaverChartMetadataDto';
    return NaverChartMetadataDto(
      symbol: _readString(json['itemCode'], context: '$context.itemCode'),
      stockName: _readString(json['stockName'], context: '$context.stockName'),
      stockExchangeNameKor: _readString(
        json['stockExchangeNameKor'],
        context: '$context.stockExchangeNameKor',
      ),
    );
  }

  final String symbol;
  final String stockName;
  final String stockExchangeNameKor;
}

class NaverHistoricalPriceDto {
  const NaverHistoricalPriceDto({
    required this.localDate,
    required this.closePrice,
    required this.openPrice,
    required this.highPrice,
    required this.lowPrice,
    required this.accumulatedTradingVolume,
  });

  factory NaverHistoricalPriceDto.fromJson(Map<String, dynamic> json) {
    const String context = 'NaverHistoricalPriceDto';
    return NaverHistoricalPriceDto(
      localDate: _readLocalDate(
        json['localDate'],
        context: '$context.localDate',
      ),
      closePrice: _readDouble(
        json['closePrice'],
        context: '$context.closePrice',
      ),
      openPrice: _readDouble(json['openPrice'], context: '$context.openPrice'),
      highPrice: _readDouble(json['highPrice'], context: '$context.highPrice'),
      lowPrice: _readDouble(json['lowPrice'], context: '$context.lowPrice'),
      accumulatedTradingVolume: _readInt(
        json['accumulatedTradingVolume'],
        context: '$context.accumulatedTradingVolume',
      ),
    );
  }

  final DateTime localDate;
  final double closePrice;
  final double openPrice;
  final double highPrice;
  final double lowPrice;
  final int accumulatedTradingVolume;
}

class NaverHistoricalChartDto {
  const NaverHistoricalChartDto({
    required this.symbol,
    required this.periodType,
    required this.priceInfos,
  });

  factory NaverHistoricalChartDto.fromJson(Map<String, dynamic> json) {
    const String context = 'NaverHistoricalChartDto';
    return NaverHistoricalChartDto(
      symbol: _readString(json['code'], context: '$context.code'),
      periodType: _readString(
        json['periodType'],
        context: '$context.periodType',
      ),
      priceInfos: (json['priceInfos'] as List<dynamic>)
          .map(
            (p) => NaverHistoricalPriceDto.fromJson(p as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  final String symbol;
  final String periodType;
  final List<NaverHistoricalPriceDto> priceInfos;
}

class NaverDailyHistoryPageDto {
  const NaverDailyHistoryPageDto({
    required this.symbol,
    required this.page,
    required this.lastPage,
    required this.priceInfos,
  });

  final String symbol;
  final int page;
  final int lastPage;
  final List<NaverHistoricalPriceDto> priceInfos;
}

// 이하 핼퍼함수들에 context를 추가했습니다.
// 즉시 문제 위치를 파악할 수 있도록, JSON Object의 key를 명시적으로 표시했습니다.

DateTime _readLocalDate(Object? value, {String context = 'JSON Object'}) {
  final text = _readString(value, context: context);
  if (text.length != 8) {
    throw FormatException('[$context] Invalid Naver localDate "$text"');
  }

  return normalizeAsOfDate(
    DateTime(
      int.parse(text.substring(0, 4)),
      int.parse(text.substring(4, 6)),
      int.parse(text.substring(6, 8)),
    ),
  );
}

String _readString(Object? value, {String context = 'JSON Object'}) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    throw FormatException('[$context] Missing string value for "$value"');
  }
  return text;
}

double _readDouble(Object? value, {String context = 'JSON Object'}) {
  if (value is num) {
    return value.toDouble();
  }
  return double.parse(_readString(value, context: context).replaceAll(',', ''));
}

int _readInt(Object? value, {String context = 'JSON Object'}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.parse(_readString(value, context: context).replaceAll(',', ''));
}

int? _readNullableInt(Object? value, {String context = 'JSON Object'}) {
  if (value == null) {
    return null;
  }
  return _readInt(value, context: context);
}
