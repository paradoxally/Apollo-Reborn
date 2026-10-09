import Foundation

// Every answer the fast path gives must equal Foundation's `contains`, which is
// what Apollo would have called. -1 (deferred) is always allowed.

var checked = 0, decided = 0, failures = 0

func check(_ haystack: String, _ needle: String, line: UInt = #line) {
    checked += 1
    let fast = apolloFastContainsDecision(haystack: haystack, needle: needle)
    guard fast >= 0 else { return }
    decided += 1
    let foundation = haystack.contains(needle)
    if (fast == 1) != foundation {
        failures += 1
        if failures <= 20 {
            print("MISMATCH line \(line): haystack=\(haystack.debugDescription) needle=\(needle.debugDescription) fast=\(fast) foundation=\(foundation)")
        }
    }
}

func expectDeferred(_ haystack: String, _ needle: String, line: UInt = #line) {
    if apolloFastContainsDecision(haystack: haystack, needle: needle) != -1 {
        failures += 1
        print("NOT DEFERRED line \(line): haystack=\(haystack.debugDescription) needle=\(needle.debugDescription)")
    }
}

func expectDecided(_ haystack: String, _ needle: String, _ expected: Bool, line: UInt = #line) {
    let fast = apolloFastContainsDecision(haystack: haystack, needle: needle)
    if fast != (expected ? 1 : 0) {
        failures += 1
        print("WRONG line \(line): haystack=\(haystack.debugDescription) needle=\(needle.debugDescription) fast=\(fast) expected=\(expected)")
    }
    check(haystack, needle, line: line)
}

// The keyword-filter shape Apollo produces: lowercased title, flair and URL
// against a lowercased keyword.
expectDecided("why tiktok is banned again", "tiktok", true)
expectDecided("why tiktok is banned again", "kanye", false)
expectDecided("https://www.reddit.com/r/politics/comments/abc/", "politics", true)
expectDecided("https://i.redd.it/x9k2.jpeg", "elon", false)
expectDecided("stop killing games is live", "stop killing games", true)
expectDecided("short", "a much longer needle", false)
expectDecided("tiktok", "tiktok", true)
expectDecided("", "x", false)
expectDecided("caf\u{e9} trump night", "trump", true)
expectDecided("emoji \u{1F600} then elon", "elon", true)
expectDecided("\u{201C}quoted\u{201D} title", "missing", false)
expectDecided("line one\r\nline two", "line two", true)

// Deferred to Foundation.
expectDeferred("anything", "")
expectDeferred("caf\u{e9}", "caf\u{e9}")
expectDeferred("abc", "b\nc")
expectDeferred("abc", "a\r")
expectDeferred("cafe\u{301}", "cafe")
expectDeferred("\u{600}abc", "abc")
expectDeferred("x\u{212A}elvin", "kelvin")
expectDeferred("semi\u{37E}colon", ";")
expectDeferred("grave\u{1FEF}", "`")
check(NSString(string: "a title long enough to stay a bridged NSString") as String, "bridged")

let tricky: [String] = [
    "", "a", "A", "ab", "abc", "e", "\u{e9}", "e\u{301}", "\u{301}", "\r", "\n", "\r\n", "\u{200D}",
    "\u{1F468}\u{200D}\u{1F469}", "\u{1F1FA}\u{1F1F8}", "\u{FE0F}", "\u{600}", "\u{212A}", "\u{37E}", "\u{1FEF}",
    "k", ";", "`", "\u{301}a", "a\u{308}", "\u{e4}", "\u{1100}\u{1161}", "\u{AC00}", "\u{FB01}", "fi", "\u{DF}", "ss",
    "\u{130}", "i\u{307}", "\u{3A3}", "\u{3C3}", "x", " ", "-", "/", ".", "0", "9", "\t", "\u{A0}",
]
for a in tricky {
    for b in tricky {
        for c in tricky {
            check(a + b + c, b)
            check(a + b + c, a + b)
            check(a + b + c, c)
            check(a + b, b + c)
        }
    }
}

var rng = SystemRandomNumberGenerator()
let asciiAlphabet = Array("abcdeKk;` \r\n-./").map(String.init)
for _ in 0..<200_000 {
    func piece(_ length: Int, allowTricky: Bool) -> String {
        var s = ""
        for _ in 0..<length {
            if allowTricky && Int.random(in: 0..<5, using: &rng) == 0 {
                s += tricky.randomElement(using: &rng)!
            } else {
                s += asciiAlphabet.randomElement(using: &rng)!
            }
        }
        return s
    }
    let haystack = piece(Int.random(in: 0..<24, using: &rng), allowTricky: true)
    let needle: String
    if !haystack.isEmpty, Bool.random(using: &rng) {
        let utf8 = Array(haystack.utf8)
        let start = Int.random(in: 0..<utf8.count, using: &rng)
        let end = Int.random(in: start...min(utf8.count, start + 6), using: &rng)
        needle = String(decoding: utf8[start..<end], as: UTF8.self)
    } else {
        needle = piece(Int.random(in: 0..<4, using: &rng), allowTricky: Int.random(in: 0..<4, using: &rng) == 0)
    }
    check(haystack, needle)
}

print("fast_string_contains: checked=\(checked) decided=\(decided) failures=\(failures)")
if failures > 0 { exit(1) }
if decided < 100_000 { print("fast path decided too few cases"); exit(1) }
