import Testing

// Small helpers keep fault-injection assertions readable, while using Swift Testing (included
// with current Command Line Tools) rather than requiring Xcode's separate XCTest runtime.
func checkEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T) {
    do { let actual = try a(); let expected = try b(); #expect(actual == expected) }
    catch { Issue.record(error) }
}
func checkNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T) {
    do { let actual = try a(); let expected = try b(); #expect(actual != expected) }
    catch { Issue.record(error) }
}
func checkNil<T>(_ value: @autoclosure () throws -> T?) {
    do { let actual = try value(); #expect(actual == nil) } catch { Issue.record(error) }
}
func checkNotNil<T>(_ value: @autoclosure () throws -> T?) {
    do { let actual = try value(); #expect(actual != nil) } catch { Issue.record(error) }
}
func checkTrue(_ value: @autoclosure () throws -> Bool) {
    do { let actual = try value(); #expect(actual) } catch { Issue.record(error) }
}
func checkFalse(_ value: @autoclosure () throws -> Bool) {
    do { let actual = try value(); #expect(!actual) } catch { Issue.record(error) }
}
func checkThrows<T>(_ value: @autoclosure () throws -> T, _ context: String = "") {
    do { _ = try value(); Issue.record("Expected an error: \(context)") } catch { }
}
