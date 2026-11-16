import DebugDrawerMetricKitPlugin
import Foundation

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// Sample MetricKit payloads, since MetricKit delivers none in the simulator and a device's come
/// a day later: one of metrics and one of diagnostics, in the shape `jsonRepresentation()` gives,
/// covering the day up to now, so each press adds a pair the plugin hasn't kept.
enum ExampleMetricKit {
    /// Launched with this argument, the app adds a sample pair at startup, so the plugin can be
    /// checked without a hand.
    static let launchArgument = "-AddSampleMetricKitPayloads"

    /// Adds a sample metric payload and a sample diagnostic payload to the MetricKit plugin.
    @MainActor
    static func addSamples() {
        let end = Date()
        let begin = end.addingTimeInterval(-86400)
        MetricKitPayloads.add(json: Data(metrics(from: begin, to: end).utf8), kind: .metrics)
        MetricKitPayloads.add(json: Data(diagnostics(at: end).utf8), kind: .diagnostics)
    }

    /// A timestamp as MetricKit writes it.
    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.string(from: date)
    }

    private static func metrics(from begin: Date, to end: Date) -> String {
        """
        {
          "appVersion": "1.0",
          "timeStampBegin": "\(timestamp(begin))",
          "timeStampEnd": "\(timestamp(end))",
          "metaData": {
            "appBuildVersion": "1",
            "osVersion": "iPhone OS 26.1 (23B85)",
            "platformArchitecture": "arm64e",
            "deviceType": "iPhone17,1",
            "bundleIdentifier": "com.debugdrawer.example.ios"
          },
          "applicationLaunchMetrics": {
            "histogrammedTimeToFirstDrawKey": {
              "histogramNumBuckets": 3,
              "histogramValue": {
                "0": {"bucketStart": "1000 ms", "bucketEnd": "1010 ms", "bucketCount": 50},
                "1": {"bucketStart": "2000 ms", "bucketEnd": "2010 ms", "bucketCount": 60},
                "2": {"bucketStart": "3000 ms", "bucketEnd": "3010 ms", "bucketCount": 30}
              }
            }
          },
          "applicationResponsivenessMetrics": {
            "histogrammedAppHangTime": {
              "histogramNumBuckets": 2,
              "histogramValue": {
                "0": {"bucketStart": "0 ms", "bucketEnd": "100 ms", "bucketCount": 50},
                "1": {"bucketStart": "100 ms", "bucketEnd": "400 ms", "bucketCount": 60}
              }
            }
          },
          "cpuMetrics": {"cumulativeCPUTime": "100 sec", "cumulativeCPUInstructions": "100 kiloinstructions"},
          "diskIOMetrics": {"cumulativeLogicalWrites": "1,300 kB"},
          "memoryMetrics": {
            "peakMemoryUsage": "200,000 kB",
            "averageSuspendedMemory": {"averageValue": "100,000 kB", "standardDeviation": 0, "sampleCount": 500}
          },
          "applicationExitMetrics": {
            "foregroundExitData": {"cumulativeNormalAppExitCount": 1, "cumulativeAppWatchdogExitCount": 1},
            "backgroundExitData": {"cumulativeNormalAppExitCount": 1, "cumulativeMemoryPressureExitCount": 1}
          }
        }
        """
    }

    private static func diagnostics(at date: Date) -> String {
        """
        {
          "timeStampBegin": "\(timestamp(date))",
          "timeStampEnd": "\(timestamp(date))",
          "hangDiagnostics": [
            {
              "version": "1.0.0",
              "diagnosticMetaData": {
                "appVersion": "1.0",
                "appBuildVersion": "1",
                "osVersion": "iPhone OS 26.1 (23B85)",
                "deviceType": "iPhone17,1",
                "hangDuration": "1.2 sec"
              },
              "callStackTree": {
                "callStackPerThread": true,
                "callStacks": [
                  {
                    "threadAttributed": true,
                    "callStackRootFrames": [
                      {
                        "binaryUUID": "70B89F27-1634-3580-A695-57CDB41D7743",
                        "offsetIntoBinaryTextSegment": 123,
                        "sampleCount": 20,
                        "binaryName": "DebugDrawerExample",
                        "address": 74565
                      }
                    ]
                  }
                ]
              }
            }
          ],
          "diskWriteExceptionDiagnostics": [
            {
              "version": "1.0.0",
              "diagnosticMetaData": {
                "appVersion": "1.0",
                "appBuildVersion": "1",
                "osVersion": "iPhone OS 26.1 (23B85)",
                "deviceType": "iPhone17,1",
                "writesCaused": "2,000 MB"
              },
              "callStackTree": {"callStackPerThread": false, "callStacks": []}
            }
          ]
        }
        """
    }
}
