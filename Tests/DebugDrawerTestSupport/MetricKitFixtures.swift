import Foundation

/// MetricKit payloads as `jsonRepresentation()` writes them, for code that can't make MetricKit
/// deliver one: the system sends payloads on its own schedule, and none in a test runner or the
/// simulator. Hand-written in the shape and key names of Apple's documented samples
/// (`MXDiagnosticPayload`, `MXMetricPayload`), not captured from a device.
public enum MetricKitFixtures {
    /// The email address the crash's exception message and arguments hold.
    public static let crashCustomerEmail = "jane.appleseed@example.com"

    /// A diagnostic payload holding one crash: `SIGSEGV` (signal 11, `EXC_BAD_ACCESS`) in
    /// `ExampleApp`, version 1.2 (34), whose Objective-C exception's message and arguments hold
    /// ``crashCustomerEmail``.
    public static let crashDiagnosticPayload = Data(#"""
    {
      "timeStampBegin" : "2026-11-18 09:12:00 +0000",
      "timeStampEnd" : "2026-11-18 09:12:00 +0000",
      "crashDiagnostics" : [
        {
          "version" : "1.0.0",
          "callStackTree" : {
            "callStackPerThread" : true,
            "callStacks" : [
              {
                "threadAttributed" : true,
                "callStackRootFrames" : [
                  {
                    "binaryUUID" : "70B89F27-1634-3580-A695-57CDB41D7743",
                    "offsetIntoBinaryTextSegment" : 123456,
                    "sampleCount" : 1,
                    "binaryName" : "ExampleApp",
                    "address" : 4310052416,
                    "subFrames" : [
                      {
                        "binaryUUID" : "70B89F27-1634-3580-A695-57CDB41D7743",
                        "offsetIntoBinaryTextSegment" : 98304,
                        "sampleCount" : 1,
                        "binaryName" : "ExampleApp",
                        "address" : 4310027264,
                        "subFrames" : [
                          {
                            "binaryUUID" : "9A87F143-AA55-3A15-8D7F-8C8FA3D6C1B9",
                            "offsetIntoBinaryTextSegment" : 20480,
                            "sampleCount" : 1,
                            "binaryName" : "dyld",
                            "address" : 6444847104
                          }
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "threadAttributed" : false,
                "callStackRootFrames" : [
                  {
                    "binaryUUID" : "1B3A5F2C-7D9E-3C41-9A8B-2E6F4D0C8A17",
                    "offsetIntoBinaryTextSegment" : 4096,
                    "sampleCount" : 1,
                    "binaryName" : "libsystem_kernel.dylib",
                    "address" : 7516192768
                  }
                ]
              }
            ]
          },
          "diagnosticMetaData" : {
            "appBuildVersion" : "34",
            "appVersion" : "1.2",
            "bundleIdentifier" : "com.example.ExampleApp",
            "deviceType" : "iPhone17,1",
            "exceptionCode" : 0,
            "exceptionType" : 1,
            "isTestFlightApp" : false,
            "lowPowerModeEnabled" : false,
            "osVersion" : "iPhone OS 26.1 (23B85)",
            "platformArchitecture" : "arm64e",
            "regionFormat" : "US",
            "signal" : 11,
            "terminationReason" : "Namespace SIGNAL, Code 11 Segmentation fault: 11",
            "virtualMemoryRegionInfo" : "0x10 is not in any region.",
            "objectiveCexceptionReason" : {
              "arguments" : ["jane.appleseed@example.com"],
              "className" : "NSException",
              "composedMessage" : "Can't save the profile of jane.appleseed@example.com",
              "exceptionName" : "NSInternalInconsistencyException",
              "exceptionType" : "NSException",
              "formatString" : "Can't save the profile of %@"
            }
          }
        }
      ]
    }
    """#.utf8)

    /// A day's metric payload of `ExampleApp` 1.2: launch times, CPU, memory and a signpost.
    public static let metricPayload = Data(#"""
    {
      "appVersion" : "1.2",
      "timeStampBegin" : "2026-11-17 00:00:00 +0000",
      "timeStampEnd" : "2026-11-17 23:59:00 +0000",
      "metaData" : {
        "appBuildVersion" : "34",
        "bundleIdentifier" : "com.example.ExampleApp",
        "deviceType" : "iPhone17,1",
        "isTestFlightApp" : false,
        "lowPowerModeEnabled" : false,
        "osVersion" : "iPhone OS 26.1 (23B85)",
        "platformArchitecture" : "arm64e",
        "regionFormat" : "US"
      },
      "applicationLaunchMetrics" : {
        "histogrammedTimeToFirstDrawKey" : {
          "histogramNumBuckets" : 1,
          "histogramValue" : {
            "0" : { "bucketCount" : 12, "bucketStart" : "400 ms", "bucketEnd" : "410 ms" }
          }
        }
      },
      "cpuMetrics" : {
        "cumulativeCPUTime" : "1200 sec",
        "cumulativeCPUInstructions" : "8000000 kiloinstructions"
      },
      "memoryMetrics" : {
        "peakMemoryUsage" : "212000 kB",
        "averageSuspendedMemory" : {
          "averageValue" : "48000 kB",
          "standardDeviation" : 0,
          "sampleCount" : 20
        }
      },
      "signpostMetrics" : [
        {
          "signpostName" : "LoadFeed",
          "signpostCategory" : "Feed",
          "totalCount" : 30
        }
      ]
    }
    """#.utf8)
}
