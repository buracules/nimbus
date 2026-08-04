import XCTest
@testable import nimbus

final class FuzzyMatcherTests: XCTestCase {
    /// A device list shaped like what `simctl list devices` actually returns.
    private let devices = [
        "iPhone 17",
        "iPhone 17 Pro",
        "iPhone 17 Pro Max",
        "iPhone Air",
        "iPad Pro 11-inch (M4)",
        "iPad mini (A17 Pro)",
        "Apple Watch Series 10 (46mm)",
    ]

    // MARK: - levenshteinDistance

    func testLevenshteinDistanceBasics() {
        XCTAssertEqual(FuzzyMatcher.levenshteinDistance("", ""), 0)
        XCTAssertEqual(FuzzyMatcher.levenshteinDistance("abc", "abc"), 0)
        XCTAssertEqual(FuzzyMatcher.levenshteinDistance("abc", ""), 3)
        XCTAssertEqual(FuzzyMatcher.levenshteinDistance("kitten", "sitting"), 3)
    }

    func testLevenshteinDistanceIsCaseInsensitive() {
        XCTAssertEqual(FuzzyMatcher.levenshteinDistance("iPhone", "IPHONE"), 0)
    }

    // MARK: - defaultThreshold

    func testDefaultThresholdHasAFloorOfTwo() {
        XCTAssertEqual(FuzzyMatcher.defaultThreshold(for: ""), 2)
        XCTAssertEqual(FuzzyMatcher.defaultThreshold(for: "iPad"), 2)
        XCTAssertEqual(FuzzyMatcher.defaultThreshold(for: "iPhone 17 Pro"), 4)
    }

    // MARK: - findClosestMatches

    func testTypoStillSuggestsTheIntendedDevice() {
        let matches = FuzzyMatcher.findClosestMatches(target: "iPhon 17 Pro", candidates: devices)
        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches.first, "iPhone 17 Pro")
        XCTAssertTrue(
            matches.allSatisfy { $0.hasPrefix("iPhone 17") },
            "Only iPhone 17 family devices should be suggested, got \(matches)"
        )
    }

    func testNonsenseQueryYieldsNoSuggestions() {
        XCTAssertEqual(FuzzyMatcher.findClosestMatches(target: "zzzzzz", candidates: devices), [])
        XCTAssertEqual(FuzzyMatcher.findClosestMatches(target: "qwertyuiop", candidates: devices), [])
    }

    func testExactMatchIsReturnedFirst() {
        let matches = FuzzyMatcher.findClosestMatches(target: "iPhone Air", candidates: devices)
        XCTAssertEqual(matches.first, "iPhone Air")
    }

    func testRespectsMaxResults() {
        let matches = FuzzyMatcher.findClosestMatches(
            target: "iPhone 17 Pro",
            candidates: devices,
            maxResults: 2
        )
        XCTAssertLessThanOrEqual(matches.count, 2)
    }

    func testExplicitThresholdOverridesTheDefault() {
        let strict = FuzzyMatcher.findClosestMatches(
            target: "iPhon 17 Pro",
            candidates: devices,
            threshold: 0
        )
        XCTAssertEqual(strict, [], "A zero threshold must only accept exact matches")

        let loose = FuzzyMatcher.findClosestMatches(
            target: "iPhon 17 Pro",
            candidates: devices,
            threshold: 100
        )
        XCTAssertEqual(loose.count, 3, "A wide threshold falls back to the top-N behavior")
    }

    func testEmptyCandidateListYieldsNoSuggestions() {
        XCTAssertEqual(FuzzyMatcher.findClosestMatches(target: "iPhone", candidates: []), [])
    }
}
