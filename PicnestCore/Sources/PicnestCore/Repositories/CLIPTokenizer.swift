// CLIP byte-level BPE tokenizer.
//
// Vocabulary and merges: Resources/clip-vocab.json and Resources/clip-merges.txt, copied from
//   https://huggingface.co/openai/clip-vit-base-patch32/resolve/main/vocab.json
//   https://huggingface.co/openai/clip-vit-base-patch32/resolve/main/merges.txt
// They are the Hugging Face export of OpenAI CLIP's `bpe_simple_vocab_16e6`
// (https://github.com/openai/CLIP), MIT License, Copyright (c) 2021 OpenAI.
// The algorithm follows `clip/simple_tokenizer.py` from the same repository.

import Foundation

public struct CLIPTokenizer: Sendable {
    public enum Failure: Error, Equatable { case missingResource(String), malformedResource(String) }

    public static let contextLength = 77
    public static let startToken: Int32 = 49406
    public static let endToken: Int32 = 49407

    private let encoder: [String: Int32]
    private let bpeRanks: [String: Int]
    private let byteEncoder: [Character]
    private let pattern: NSRegularExpression

    public init() throws {
        guard let vocabURL = Bundle.module.url(forResource: "clip-vocab", withExtension: "json") else {
            throw Failure.missingResource("clip-vocab.json")
        }
        guard let mergesURL = Bundle.module.url(forResource: "clip-merges", withExtension: "txt") else {
            throw Failure.missingResource("clip-merges.txt")
        }
        guard let vocab = try JSONSerialization.jsonObject(with: Data(contentsOf: vocabURL)) as? [String: Int] else {
            throw Failure.malformedResource("clip-vocab.json")
        }
        encoder = vocab.mapValues { Int32($0) }

        var ranks: [String: Int] = [:]
        let lines = try String(contentsOf: mergesURL, encoding: .utf8).split(separator: "\n")
        for line in lines where !line.hasPrefix("#version") {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            ranks[parts[0] + " " + parts[1]] = ranks.count
        }
        bpeRanks = ranks
        byteEncoder = Self.bytesToUnicode()
        pattern = try NSRegularExpression(
            pattern: #"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+"#,
            options: [.caseInsensitive]
        )
    }

    /// Returns exactly 77 ids: start token, BPE tokens (at most 75), end token, then zeros.
    public func encode(_ text: String) -> [Int32] {
        var ids: [Int32] = [Self.startToken]
        ids += bpeTokens(text).prefix(Self.contextLength - 2)
        ids.append(Self.endToken)
        ids += Array(repeating: 0, count: Self.contextLength - ids.count)
        return ids
    }

    private func bpeTokens(_ text: String) -> [Int32] {
        let cleaned = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        let ns = cleaned as NSString
        var out: [Int32] = []
        for match in pattern.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: match.range)
            let encoded = word.utf8.map { byteEncoder[Int($0)] }
            out += bpe(encoded).compactMap { encoder[$0] }
        }
        return out
    }

    /// Merges the byte-encoded characters of one word, lowest-rank pair first.
    private func bpe(_ chars: [Character]) -> [String] {
        guard !chars.isEmpty else { return [] }
        var word = chars.map { String($0) }
        word[word.count - 1] += "</w>"
        while word.count > 1 {
            var best: (rank: Int, index: Int)?
            for i in 0..<(word.count - 1) {
                if let r = bpeRanks[word[i] + " " + word[i + 1]], r < (best?.rank ?? .max) {
                    best = (r, i)
                }
            }
            guard let best else { break }
            let first = word[best.index], second = word[best.index + 1]
            var merged: [String] = []
            merged.reserveCapacity(word.count)
            var i = 0
            while i < word.count {
                if i < word.count - 1, word[i] == first, word[i + 1] == second {
                    merged.append(first + second)
                    i += 2
                } else {
                    merged.append(word[i])
                    i += 1
                }
            }
            word = merged
        }
        return word
    }

    /// GPT-2 / CLIP reversible map from each byte to a printable unicode character.
    private static func bytesToUnicode() -> [Character] {
        let printable = Array(33...126) + Array(161...172) + Array(174...255)
        let printableSet = Set(printable)
        var table = [Character](repeating: " ", count: 256)
        var extra = 0
        for b in 0..<256 {
            let scalar: Int
            if printableSet.contains(b) {
                scalar = b
            } else {
                scalar = 256 + extra
                extra += 1
            }
            table[b] = Character(Unicode.Scalar(UInt32(scalar))!)
        }
        return table
    }
}
