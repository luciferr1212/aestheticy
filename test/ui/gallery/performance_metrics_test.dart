import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/ui/gallery/performance_metrics.dart';

void main() {
  group('PerformanceMetrics Tests', () {
    test('empty window returns zeroed metrics without division by zero', () {
      final metrics = PerformanceMetrics.compute(const []);
      expect(metrics.totalFrames, equals(0));
      expect(metrics.avgBuildMs, equals(0.0));
      expect(metrics.p95BuildMs, equals(0.0));
      expect(metrics.avgRasterMs, equals(0.0));
      expect(metrics.p95RasterMs, equals(0.0));
      expect(metrics.slowFramePercent, equals(0.0));

      final export = metrics.toExportString(
        qualityTier: 'LIGHT',
        buildMode: 'Release',
      );
      expect(export, contains('Quality Tier: LIGHT'));
      expect(export, contains('Build Mode: Release'));
      expect(export, contains('Frames in Window: 0'));
    });

    test('computes average, p95, and slow frame percentage accurately', () {
      // Create sample frame timings
      // FrameTiming constructor: vsyncStart, buildStart, buildFinish, rasterStart, rasterFinish
      final timings = <FrameTiming>[
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 8000, // 8.0 ms
          rasterStart: 8000,
          rasterFinish: 14000, // 6.0 ms raster, total 14.0 ms (fast)
          rasterFinishWallTime: 14000,
        ),
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 10000, // 10.0 ms
          rasterStart: 10000,
          rasterFinish: 20000, // 10.0 ms raster, total 20.0 ms (slow: >16.7ms)
          rasterFinishWallTime: 20000,
        ),
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 12000, // 12.0 ms
          rasterStart: 12000,
          rasterFinish: 18000, // 6.0 ms raster, total 18.0 ms (slow: >16.7ms)
          rasterFinishWallTime: 18000,
        ),
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 6000, // 6.0 ms
          rasterStart: 6000,
          rasterFinish: 10000, // 4.0 ms raster, total 10.0 ms (fast)
          rasterFinishWallTime: 10000,
        ),
      ];

      final metrics = PerformanceMetrics.compute(timings);
      expect(metrics.totalFrames, equals(4));

      // Avg build: (8 + 10 + 12 + 6) / 4 = 9.0 ms
      expect(metrics.avgBuildMs, closeTo(9.0, 0.01));

      // Avg raster: (6 + 10 + 6 + 4) / 4 = 6.5 ms
      expect(metrics.avgRasterMs, closeTo(6.5, 0.01));

      // Slow frames: 2 out of 4 = 50.0%
      expect(metrics.slowFramePercent, closeTo(50.0, 0.01));

      // P95 build: sorted [6, 8, 10, 12], index round(0.95 * 3) = 3 -> 12.0 ms
      expect(metrics.p95BuildMs, closeTo(12.0, 0.01));

      // P95 raster: sorted [4, 6, 6, 10], index round(0.95 * 3) = 3 -> 10.0 ms
      expect(metrics.p95RasterMs, closeTo(10.0, 0.01));
    });
  });
}
