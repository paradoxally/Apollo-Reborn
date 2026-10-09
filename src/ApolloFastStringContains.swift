//
//  ApolloFastStringContains.swift
//  Apollo-Reborn
//
//  Decides Foundation's `StringProtocol.contains(_:)` for the String/String
//  calls Apollo's keyword filter makes, without walking Characters. Returns
//  1 or 0 only when a byte search provably gives Foundation's answer, and -1
//  (ask Foundation) for everything else. ApolloFastStringContains.m routes
//  Apollo's calls here.
//

import Foundation

// Characters whose canonical form is a single ASCII scalar. A Character-wise
// search treats them as equal to that ASCII letter, so a byte search could
// miss a match: U+037E (;), U+1FEF (`), U+212A (K).
private func containsASCIISingleton(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
    let count = bytes.count
    var i = 0
    while i < count {
        let b = bytes[i]
        if b == 0xCD, i + 1 < count, bytes[i + 1] == 0xBE { return true }
        if b == 0xE1, i + 2 < count, bytes[i + 1] == 0xBF, bytes[i + 2] == 0xAF { return true }
        if b == 0xE2, i + 2 < count, bytes[i + 1] == 0x84, bytes[i + 2] == 0xAA { return true }
        i += 1
    }
    return false
}

private func decide(_ h: UnsafeBufferPointer<UInt8>, _ n: UnsafeBufferPointer<UInt8>) -> Int32 {
    // Foundation answers false for an empty needle; leave that to it.
    guard !n.isEmpty else { return -1 }
    // An ASCII needle without CR or LF is a run of single-scalar Characters,
    // and a byte match of it can never split a CR LF pair.
    for b in n where b >= 0x80 || b == 0x0A || b == 0x0D { return -1 }
    for b in h where b >= 0x80 {
        if containsASCIISingleton(h) { return -1 }
        break
    }
    guard h.count >= n.count,
          let hit = memmem(h.baseAddress!, h.count, n.baseAddress!, n.count) else { return 0 }
    let start = h.baseAddress!.distance(to: hit.assumingMemoryBound(to: UInt8.self))
    let end = start + n.count
    // Between two ASCII scalars (other than CR LF) there is always a grapheme
    // break. A non-ASCII neighbor may be a prepend or an extending mark that
    // merges into the Character, and a later hit might still match, so ask
    // Foundation.
    let startIsBoundary = start == 0 || h[start - 1] < 0x80
    let endIsBoundary = end == h.count || h[end] < 0x80
    return startIsBoundary && endIsBoundary ? 1 : -1
}

func apolloFastContainsDecision(haystack: String, needle: String) -> Int32 {
    // Lazily bridged NSStrings have no contiguous UTF-8 and stay with Foundation.
    let result = needle.utf8.withContiguousStorageIfAvailable { n in
        haystack.utf8.withContiguousStorageIfAvailable { h in decide(h, n) }
    }
    return (result ?? nil) ?? -1
}

@_cdecl("ApolloFastContainsDecide")
public func ApolloFastContainsDecide(_ haystack: UnsafeRawPointer, _ needle: UnsafeRawPointer) -> Int32 {
    apolloFastContainsDecision(haystack: haystack.load(as: String.self),
                               needle: needle.load(as: String.self))
}
