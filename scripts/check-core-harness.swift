// Support for check-core.sh on Macs where Command Line Tools lacks XCTest.
import Foundation

private var failureCount = 0
private var testCount = 0
class XCTestCase {}

private func fail(_ message: String, file: StaticString, line: UInt) {
    failureCount += 1
    print("FAIL \(file):\(line): \(message)")
}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T,
                                  file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { fail("\(actual) != \(expected)", file: file, line: line) }
}
func XCTAssertNotEqual<T: Equatable>(_ actual: T, _ expected: T,
                                     file: StaticString = #filePath, line: UInt = #line) {
    if actual == expected { fail("\(actual) == \(expected)", file: file, line: line) }
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { fail("Expected true", file: file, line: line) }
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if value { fail("Expected false", file: file, line: line) }
}
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { fail("Expected nil", file: file, line: line) }
}
func XCTAssertLessThan<T: Comparable>(_ actual: T, _ expected: T,
                                     file: StaticString = #filePath, line: UInt = #line) {
    if !(actual < expected) { fail("\(actual) is not less than \(expected)", file: file, line: line) }
}
func XCTAssertGreaterThan<T: Comparable>(_ actual: T, _ expected: T,
                                        file: StaticString = #filePath, line: UInt = #line) {
    if !(actual > expected) { fail("\(actual) is not greater than \(expected)", file: file, line: line) }
}
private func run(_ name: String, body: () -> Void) {
    testCount += 1
    let before = failureCount
    body()
    print("\(failureCount == before ? "PASS" : "FAIL") \(name)")
}
