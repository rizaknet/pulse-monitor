import Foundation

public enum PulseCoreSelfTest {
    public static func run() {
        print("Running PulseCore Self-Tests...")

        // 1. Format tests
        assert(Format.bytes(0) == "0 B")
        assert(Format.bytes(1024) == "1.0 KB")
        assert(Format.bytes(1024 * 1024) == "1.0 MB")
        assert(Format.bytes(1024, compact: true) == "1 KB")
        assert(Format.rate(500) == "500 B/s")
        assert(Format.duration(3600) == "1h 0m")
        print("✅ Format tests passed")

        // 2. RingBuffer tests
        var buffer = RingBuffer<Int>(capacity: 3)
        assert(buffer.isEmpty)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        assert(buffer.elements == [1, 2, 3])
        buffer.append(4)
        assert(buffer.elements == [2, 3, 4])
        assert(buffer.first == 2)
        assert(buffer.last == 4)
        print("✅ RingBuffer tests passed")

        // 3. AppGrouper tests
        let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        assert(AppGrouper.outermostApp(chromePath) == "/Applications/Google Chrome.app")
        let helperPath = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        assert(AppGrouper.outermostApp(helperPath) == "/Applications/Google Chrome.app")
        assert(AppGrouper.outermostApp("/usr/bin/git") == nil)
        print("✅ AppGrouper tests passed")

        print("🎉 All PulseCore self-tests passed successfully!\n")
    }
}
