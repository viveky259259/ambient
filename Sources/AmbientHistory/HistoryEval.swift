import Foundation

/// Scores history on questions whose answers are known, so a change to prompts, models or retrieval can be judged by
/// what it does to correctness and not by how it reads.
public enum HistoryEval {
    public struct Question: Codable, Equatable, Sendable {
        public var ask: String
        /// A file to ask about, as `--file` would give it.
        public var file: String?
        /// The start of the id of the chat that holds the answer.
        public var expectSession: String
        /// When given, the card found must have changed one of these.
        public var expectFiles: [String]
        /// Words a right answer contains, compared without case. Each entry may give alternatives separated by "|".
        public var expectWords: [String]

        public init(ask: String, file: String? = nil, expectSession: String, expectFiles: [String] = [],
                    expectWords: [String] = []) {
            self.ask = ask
            self.file = file
            self.expectSession = expectSession
            self.expectFiles = expectFiles
            self.expectWords = expectWords
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            ask = try values.decode(String.self, forKey: .ask)
            file = try values.decodeIfPresent(String.self, forKey: .file)
            expectSession = try values.decode(String.self, forKey: .expectSession)
            expectFiles = try values.decodeIfPresent([String].self, forKey: .expectFiles) ?? []
            expectWords = try values.decodeIfPresent([String].self, forKey: .expectWords) ?? []
        }
    }

    struct File: Codable {
        var questions: [Question]
    }

    public struct Result: Equatable, Sendable {
        public var question: Question
        /// The right card was among the first few retrieved.
        public var found: Bool
        /// The answer held every expected word; nil when answers weren't asked for.
        public var answered: Bool?
        public var depth: HistoryAnswer.Depth?

        public init(question: Question, found: Bool, answered: Bool?, depth: HistoryAnswer.Depth?) {
            self.question = question
            self.found = found
            self.answered = answered
            self.depth = depth
        }
    }

    public static func load(_ data: Data) throws -> [Question] {
        do { return try JSONDecoder().decode(File.self, from: data).questions } catch {
            throw HistoryError.message("The questions file isn't readable: \(error)")
        }
    }

    /// True when one of the first `top` cards is from the expected chat and, if files are expected, changed one.
    public static func found(_ question: Question, in hits: [IndexHit], top: Int = 5) -> Bool {
        hits.prefix(top).contains { hit in
            hit.chat.session.id.hasPrefix(question.expectSession)
                && (question.expectFiles.isEmpty || !Set(hit.card.files).isDisjoint(with: question.expectFiles))
        }
    }

    public static func answered(_ question: Question, by text: String) -> Bool {
        let lowered = text.lowercased()
        return question.expectWords.allSatisfy { entry in
            entry.lowercased().split(separator: "|").contains { lowered.contains($0.trimmingCharacters(in: .whitespaces)) }
        }
    }

    public static func summary(_ results: [Result]) -> String {
        let found = results.filter(\.found).count
        var text = "Retrieval: \(found)/\(results.count) questions found their chat in the first five cards."
        let judged = results.filter { $0.answered != nil }
        if !judged.isEmpty {
            let right = judged.filter { $0.answered == true }.count
            let deep = judged.filter { $0.depth == .deep }.count
            text += "\nAnswers: \(right)/\(judged.count) held the expected words; \(deep) needed the deep pass."
        }
        return text
    }
}
