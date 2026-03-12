import Foundation

/// Provides fuzzy string matching utilities for suggesting similar strings
enum FuzzyMatcher {
    /// Calculates the Levenshtein distance between two strings (case-insensitive)
    ///
    /// The Levenshtein distance is the minimum number of single-character edits
    /// (insertions, deletions, or substitutions) needed to transform one string into another.
    ///
    /// - Parameters:
    ///   - s1: The first string to compare
    ///   - s2: The second string to compare
    /// - Returns: The Levenshtein distance as an integer
    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Lower = s1.lowercased()
        let s2Lower = s2.lowercased()

        let s1Array = Array(s1Lower)
        let s2Array = Array(s2Lower)

        let m = s1Array.count
        let n = s2Array.count

        // Create a 2D array for dynamic programming
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        // Initialize base cases
        for i in 0...m {
            dp[i][0] = i
        }
        for j in 0...n {
            dp[0][j] = j
        }

        // Fill the dp table
        for i in 1...m {
            for j in 1...n {
                if s1Array[i - 1] == s2Array[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = 1 + min(
                        dp[i - 1][j],      // deletion
                        dp[i][j - 1],      // insertion
                        dp[i - 1][j - 1]   // substitution
                    )
                }
            }
        }

        return dp[m][n]
    }

    /// Finds the closest matching strings from a list of candidates
    ///
    /// - Parameters:
    ///   - target: The target string to match against
    ///   - candidates: Array of candidate strings to search through
    ///   - maxResults: Maximum number of results to return (default: 3)
    /// - Returns: Array of closest matching strings, sorted by similarity (best match first)
    static func findClosestMatches(target: String, candidates: [String], maxResults: Int = 3) -> [String] {
        // Calculate distance for each candidate
        let candidatesWithDistance = candidates.map { candidate in
            (candidate: candidate, distance: levenshteinDistance(target, candidate))
        }

        // Sort by distance (ascending) - lower distance means better match
        let sorted = candidatesWithDistance.sorted { $0.distance < $1.distance }

        // Return top N matches
        return Array(sorted.prefix(maxResults).map { $0.candidate })
    }
}
