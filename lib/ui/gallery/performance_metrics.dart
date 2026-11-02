import 'package:flutter/scheduler.dart';

/// Performance metrics calculated over a rolling window of [FrameTiming] records.
class PerformanceMetrics {
  /// Average build duration in milliseconds.
  final double avgBuildMs;

  /// 95th percentile build duration in milliseconds.
  final double p95BuildMs;

  /// Average rasterization duration in milliseconds.
  final double avgRasterMs;

  /// 95th percentile rasterization duration in milliseconds.
  final double p95RasterMs;

  /// Percentage of frames exceeding the 16.7 ms threshold (60 fps budget).
  final double slowFramePercent;

  /// Total count of frames recorded in the window.
  final int totalFrames;

  /// Creates a [PerformanceMetrics] record.
  const PerformanceMetrics({
    this.avgBuildMs = 0.0,
    this.p95BuildMs = 0.0,
    this.avgRasterMs = 0.0,
    this.p95RasterMs = 0.0,
    this.slowFramePercent = 0.0,
    this.totalFrames = 0,
  });

  /// Computes performance metrics over [timings].
  ///
  /// Guaranteed safe against empty inputs with zero division or exceptions.
  static PerformanceMetrics compute(List<FrameTiming> timings) {
    if (timings.isEmpty) {
      return const PerformanceMetrics();
    }

    final total = timings.length;
    double sumBuild = 0.0;
    double sumRaster = 0.0;
    int slowCount = 0;

    final buildTimes = <double>[];
    final rasterTimes = <double>[];

    for (final timing in timings) {
      final buildMs = timing.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
      final totalMs = timing.totalSpan.inMicroseconds / 1000.0;

      sumBuild += buildMs;
      sumRaster += rasterMs;
      buildTimes.add(buildMs);
      rasterTimes.add(rasterMs);

      if (totalMs > 16.7) {
        slowCount++;
      }
    }

    buildTimes.sort();
    rasterTimes.sort();

    double percentile(List<double> sorted, double p) {
      if (sorted.isEmpty) return 0.0;
      final index =
          (p * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
      return sorted[index];
    }

    return PerformanceMetrics(
      avgBuildMs: sumBuild / total,
      p95BuildMs: percentile(buildTimes, 0.95),
      avgRasterMs: sumRaster / total,
      p95RasterMs: percentile(rasterTimes, 0.95),
      slowFramePercent: (slowCount / total) * 100.0,
      totalFrames: total,
    );
  }

  /// Formats these metrics into a clean plain-text block for clipboard export.
  String toExportString({
    required String qualityTier,
    required String buildMode,
  }) {
    return '''
Aestheticy Performance Report
-----------------------------
Quality Tier: $qualityTier
Build Mode: $buildMode
Frames in Window: $totalFrames
Avg Build Time: ${avgBuildMs.toStringAsFixed(2)} ms
P95 Build Time: ${p95BuildMs.toStringAsFixed(2)} ms
Avg Raster Time: ${avgRasterMs.toStringAsFixed(2)} ms
P95 Raster Time: ${p95RasterMs.toStringAsFixed(2)} ms
Slow Frames (>16.7ms): ${slowFramePercent.toStringAsFixed(1)}%
''';
  }
}
