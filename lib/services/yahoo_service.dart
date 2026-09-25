import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../indicators.dart';

const _userAgent = 'Mozilla/5.0';
const _timeout = Duration(seconds: 20);

const _dailyUrl =
    'https://query1.finance.yahoo.com/v8/finance/chart/{symbol}'
    '?interval=1d&period1={start}&period2={end}';
const _intradayUrl =
    'https://query1.finance.yahoo.com/v8/finance/chart/{symbol}'
    '?interval=5m&period1={start}&period2={end}';

bool _tzReady = false;

void ensureTimeZones() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

tz.Location get _et {
  ensureTimeZones();
  return tz.getLocation('America/New_York');
}

String _iso(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String formatDate(DateTime d) => _iso(dateOnly(d));

DateTime parseDate(String iso) {
  final p = iso.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

int _epochUtcMidnight(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 1000;

/// Yahoo daily timestamps are session opens (for example 13:30 UTC),
/// not UTC midnight. Convert to the America/New_York calendar date.
/// prices.py uses UTC date(); that matches ET only when the stamp is midnight.
String _etDate(int ts) {
  final utc = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
  return _iso(tz.TZDateTime.from(utc, _et));
}

String todayEt() => _iso(tz.TZDateTime.now(_et));

DateTime todayEtDate() {
  final now = tz.TZDateTime.now(_et);
  return DateTime(now.year, now.month, now.day);
}

class QuoteLoad {
  const QuoteLoad({
    required this.bars,
    required this.reconstructed,
    required this.backfillFailed,
    required this.liveFailed,
  });

  final List<RawBar> bars;
  final List<String> reconstructed;
  final bool backfillFailed;
  final bool liveFailed;
}

class YahooService {
  YahooService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> _getJson(String url) async {
    final response = await _client
        .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Yahoo HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final chart = data['chart'] as Map<String, dynamic>;
    if (chart['error'] != null) {
      throw Exception('Yahoo chart error');
    }
    final results = chart['result'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      throw Exception('No price data returned.');
    }
    return results[0] as Map<String, dynamic>;
  }

  Future<List<RawBar>> fetchDaily(String symbol, int startTs, int endTs) async {
    final url = _dailyUrl
        .replaceAll('{symbol}', symbol)
        .replaceAll('{start}', '$startTs')
        .replaceAll('{end}', '$endTs');
    final result = await _getJson(url);
    return _dailyBars(result);
  }

  List<RawBar> _dailyBars(Map<String, dynamic> result) {
    final timestamps = (result['timestamp'] as List<dynamic>?) ?? const [];
    final quote = _quote(result);
    final closes = (quote['close'] as List<dynamic>?) ?? const [];
    final volumes = (quote['volume'] as List<dynamic>?) ?? const [];
    final rows = <RawBar>[];
    for (var i = 0; i < timestamps.length; i++) {
      final close = i < closes.length ? closes[i] : null;
      if (close == null) continue;
      final volume = i < volumes.length ? volumes[i] : null;
      rows.add(
        RawBar(
          date: _etDate((timestamps[i] as num).toInt()),
          close: ((close as num).toDouble() * 100).round() / 100,
          volume: volume == null ? null : (volume as num).toInt(),
        ),
      );
    }
    return rows;
  }

  Future<RawBar?> fetchLiveToday(String symbol) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final url = _intradayUrl
        .replaceAll('{symbol}', symbol)
        .replaceAll('{start}', '${now - 3 * 86400}')
        .replaceAll('{end}', '$now');
    final result = await _getJson(url);
    final today = todayEt();
    final timestamps = (result['timestamp'] as List<dynamic>?) ?? const [];
    final quote = _quote(result);
    final closes = (quote['close'] as List<dynamic>?) ?? const [];
    final volumes = (quote['volume'] as List<dynamic>?) ?? const [];

    double? lastClose;
    var sessionVol = 0;
    var found = false;
    for (var i = 0; i < timestamps.length; i++) {
      if (_etDate((timestamps[i] as num).toInt()) != today) continue;
      final close = i < closes.length ? closes[i] : null;
      if (close != null) {
        lastClose = (close as num).toDouble();
        found = true;
      }
      final volume = i < volumes.length ? volumes[i] : null;
      if (volume != null) sessionVol += (volume as num).toInt();
    }
    if (!found || lastClose == null) return null;
    return RawBar(
      date: today,
      close: (lastClose * 100).round() / 100,
      volume: sessionVol,
      live: true,
    );
  }

  Future<Map<String, DayAgg>> fetch5mDaily(String symbol, {int days = 59}) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final url = _intradayUrl
        .replaceAll('{symbol}', symbol)
        .replaceAll('{start}', '${now - days * 86400}')
        .replaceAll('{end}', '$now');
    final result = await _getJson(url);
    final timestamps = (result['timestamp'] as List<dynamic>?) ?? const [];
    final quote = _quote(result);
    final opens = (quote['open'] as List<dynamic>?) ?? const [];
    final highs = (quote['high'] as List<dynamic>?) ?? const [];
    final lows = (quote['low'] as List<dynamic>?) ?? const [];
    final closes = (quote['close'] as List<dynamic>?) ?? const [];
    final volumes = (quote['volume'] as List<dynamic>?) ?? const [];

    final daily = <String, DayAgg>{};
    for (var i = 0; i < timestamps.length; i++) {
      final day = _etDate((timestamps[i] as num).toInt());
      final close = i < closes.length ? closes[i] : null;
      final volume = i < volumes.length ? volumes[i] : null;
      if (close == null) {
        if (volume != null) {
          daily.putIfAbsent(day, DayAgg.new).volume += (volume as num).toInt();
        }
        continue;
      }
      final entry = daily.putIfAbsent(day, DayAgg.new);
      final open = i < opens.length ? opens[i] : null;
      if (open != null && entry.open == null) {
        entry.open = ((open as num).toDouble() * 100).round() / 100;
      }
      final high = i < highs.length ? highs[i] : null;
      if (high != null) {
        final h = ((high as num).toDouble() * 100).round() / 100;
        entry.high = entry.high == null ? h : (h > entry.high! ? h : entry.high);
      }
      final low = i < lows.length ? lows[i] : null;
      if (low != null) {
        final lo = ((low as num).toDouble() * 100).round() / 100;
        entry.low = entry.low == null ? lo : (lo < entry.low! ? lo : entry.low);
      }
      entry.close = ((close as num).toDouble() * 100).round() / 100;
      if (volume != null) entry.volume += (volume as num).toInt();
    }
    daily.removeWhere((_, v) => v.close == null);
    return daily;
  }

  List<String> backfillMissingDaily(
    List<RawBar> rows,
    Map<String, DayAgg> daily5m,
    String today,
    String loDate,
    String hiDate,
  ) {
    final have = {for (final r in rows) r.date};
    final reconstructed = <String>[];
    final days = daily5m.keys.toList()..sort();
    for (final day in days) {
      if (day == today) continue;
      if (day.compareTo(loDate) < 0 || day.compareTo(hiDate) > 0) continue;
      if (have.contains(day)) continue;
      final agg = daily5m[day]!;
      rows.add(RawBar(date: day, close: agg.close!, volume: agg.volume));
      reconstructed.add(day);
    }
    rows.sort((a, b) => a.date.compareTo(b.date));
    return reconstructed;
  }

  List<RawBar> mergeLiveRow(List<RawBar> rows, RawBar? live) {
    if (live == null) return rows;
    if (rows.isNotEmpty && rows.last.date == live.date) {
      rows[rows.length - 1] = live;
      return rows;
    }
    if (rows.isNotEmpty && rows.last.date.compareTo(live.date) > 0) {
      return rows;
    }
    rows.add(live);
    return rows;
  }

  Future<QuoteLoad> load({
    required String symbol,
    required int rangeDays,
  }) async {
    ensureTimeZones();
    final ticker = symbol.trim().toUpperCase();
    if (ticker.isEmpty) {
      throw Exception('Ticker must not be empty.');
    }
    if (rangeDays < 1) {
      throw Exception('Range must be a positive number of days.');
    }

    // Use the ET calendar date so the range matches prices.py and the LIVE row.
    final endDate = todayEtDate();
    final startDate = endDate.subtract(Duration(days: rangeDays));
    final bufferStart = startDate.subtract(const Duration(days: 60));
    final queryEnd = endDate.add(const Duration(days: 1));
    final today = formatDate(endDate);
    final bufferIso = formatDate(bufferStart);
    final hiIso = today;

    final rows = await fetchDaily(
      ticker,
      _epochUtcMidnight(bufferStart),
      _epochUtcMidnight(queryEnd),
    );

    // Range always ends today, so 5m backfill always applies.
    // Failures fall back to daily closes only.
    var backfillFailed = false;
    var reconstructed = <String>[];
    try {
      final daily5m = await fetch5mDaily(ticker);
      reconstructed = backfillMissingDaily(rows, daily5m, today, bufferIso, hiIso);
    } catch (_) {
      backfillFailed = true;
    }

    // Range always ends today, so always merge the provisional LIVE row.
    var liveFailed = false;
    try {
      mergeLiveRow(rows, await fetchLiveToday(ticker));
    } catch (_) {
      liveFailed = true;
    }

    final warmed = rows
        .where((r) => r.date.compareTo(bufferIso) >= 0 && r.date.compareTo(hiIso) <= 0)
        .toList();
    if (warmed.isEmpty) {
      throw Exception('No price data returned.');
    }

    return QuoteLoad(
      bars: warmed,
      reconstructed: reconstructed,
      backfillFailed: backfillFailed,
      liveFailed: liveFailed,
    );
  }

  Map<String, dynamic> _quote(Map<String, dynamic> result) {
    final indicators = result['indicators'] as Map<String, dynamic>;
    final quotes = indicators['quote'] as List<dynamic>;
    return quotes[0] as Map<String, dynamic>;
  }

  void close() => _client.close();
}

class DayAgg {
  double? open;
  double? high;
  double? low;
  double? close;
  int volume = 0;
}
