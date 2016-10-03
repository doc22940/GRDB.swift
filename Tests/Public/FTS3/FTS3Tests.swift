import XCTest
#if USING_SQLCIPHER
    import GRDBCipher
#elseif USING_CUSTOMSQLITE
    import GRDBCustomSQLite
#else
    import GRDB
#endif

class FTS3Tests: GRDBTestCase {
    
    override func setup(_ dbWriter: DatabaseWriter) throws {
        try dbWriter.write { db in
            try db.execute("CREATE VIRTUAL TABLE books USING fts4(title, author, body)")
            try db.execute("INSERT INTO books (title, author, body) VALUES (?, ?, ?)", arguments: ["Moby Dick", "Herman Melville", "Call me Ishmael. Some years ago--never mind how long precisely--having little or no money in my purse, and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world."])
            try db.execute("INSERT INTO books (title, author, body) VALUES (?, ?, ?)", arguments: ["Red Mars", "Kim Stanley Robinson", "History is not evolution! It is a false analogy! Evolution is a matter of environment and chance, acting over millions of years. But history is a matter of environment and choice, acting within lifetimes, and sometimes within years, or months, or days! History is Lamarckian!"])
            try db.execute("INSERT INTO books (title, author, body) VALUES (?, ?, ?)", arguments: ["Querelle de Brest", "Jean Genet", "L’idée de mer évoque souvent l’idée de mer, de marins. Mer et marins ne se présentent pas alors avec la précision d’une image, le meurtre plutôt fait en nous l’émotion déferler par vagues."])
            try db.execute("INSERT INTO books (title, author, body) VALUES (?, ?, ?)", arguments: ["Éden, Éden, Éden", "Pierre Guyotat", "/ Les soldats, casqués, jambes ouvertes, foulent, muscles retenus, les nouveau-nés emmaillotés dans les châles écarlates, violets : les bébés roulent hors des bras des femmes accroupies sur les tôles mitraillées des G. M. C. ;"])
        }
    }
    
    func testValidFTS3Pattern() {
        assertNoError {
            let dbQueue = try makeDatabaseQueue()
            try dbQueue.inDatabase { db in
                // Couples (raw pattern, expected count of matching rows)
                let validRawPatterns: [(String, Int)] = [
                    // Empty query
                    ("", 0),
                    // Token queries
                    ("Moby", 1),
                    ("écarlates", 1),
                    ("fooéı👨👨🏿🇫🇷🇨🇮", 0),
                    // Prefix queries
                    ("*", 0),
                    ("Robin*", 1),
                    // Document prefix queries
                    ("^", 0),
                    ("^Moby", 1),
                    ("^Dick", 0),
                    // Phrase queries
                    ("\"foulent muscles\"", 1),
                    ("\"Kim Stan* Robin*\"", 1),
                    // NEAR queries
                    ("history NEAR evolution", 1),
                    // Logical queries
                    ("years NOT months", 1),
                    ("years AND months", 1),
                    ("years OR months", 2),
                ]
                for (rawPattern, expectedCount) in validRawPatterns {
                    let pattern = try FTS3Pattern(rawPattern: rawPattern)
                    let count = Int.fetchOne(db, "SELECT COUNT(*) FROM books WHERE books MATCH ?", arguments: [pattern])!
                    XCTAssertEqual(count, expectedCount, "Expected pattern \(String(reflecting: rawPattern)) to yield \(expectedCount) results")
                }
            }
        }
    }
    
    func testInvalidFTS3Pattern() {
        let invalidRawPatterns = ["NOT", "(", "AND", "OR", "\""]
        for rawPattern in invalidRawPatterns {
            do {
                _ = try FTS3Pattern(rawPattern: rawPattern)
                XCTFail("Expected pattern to be invalid: \(String(reflecting: rawPattern))")
            } catch is DatabaseError {
                
            } catch {
                XCTFail("Expected DatabaseError, not \(error)")
            }
        }
    }
    
    func testFTS3PatternWithAnyToken() {
        let wrongInputs = ["", "*", "^", " ", "(", "()", "\""]
        for string in wrongInputs {
            if let pattern = FTS3Pattern(matchingAnyTokenIn: string) {
                let rawPattern = String.fromDatabaseValue(pattern.databaseValue)
                XCTFail("Unexpected raw pattern \(String(reflecting: rawPattern)) from string \(String(reflecting: string))")
            }
        }
        
        assertNoError {
            let dbQueue = try makeDatabaseQueue()
            dbQueue.inDatabase { db in
                // Couples (pattern, expected raw pattern, expected count of matching rows)
                let cases = [
                    ("Moby", "moby", 1),
                    ("^Moby*", "moby", 1),
                    (" \t\nyears \t\nmonths \t\n", "years OR months", 2),
                    ("\"years months days\"", "years OR months OR days", 2),
                    ("FOOÉı👨👨🏿🇫🇷🇨🇮", "fooÉı👨👨🏿🇫🇷🇨🇮", 0),
                ]
                for (string, expectedRawPattern, expectedCount) in cases {
                    if let pattern = FTS3Pattern(matchingAnyTokenIn: string) {
                        let rawPattern = String.fromDatabaseValue(pattern.databaseValue)
                        XCTAssertEqual(rawPattern, expectedRawPattern)
                        let count = Int.fetchOne(db, "SELECT COUNT(*) FROM books WHERE books MATCH ?", arguments: [pattern])!
                        XCTAssertEqual(count, expectedCount, "Expected pattern \(String(reflecting: rawPattern)) to yield \(expectedCount) results")
                    }
                }
            }
        }
    }
    
    func testFTS3PatternWithAllTokens() {
        let wrongInputs = ["", "*", "^", " ", "(", "()", "\""]
        for string in wrongInputs {
            if let pattern = FTS3Pattern(matchingAllTokensIn: string) {
                let rawPattern = String.fromDatabaseValue(pattern.databaseValue)
                XCTFail("Unexpected raw pattern \(String(reflecting: rawPattern)) from string \(String(reflecting: string))")
            }
        }
        
        assertNoError {
            let dbQueue = try makeDatabaseQueue()
            dbQueue.inDatabase { db in
                // Couples (pattern, expected raw pattern, expected count of matching rows)
                let cases = [
                    ("Moby", "moby", 1),
                    ("^Moby*", "moby", 1),
                    (" \t\nyears \t\nmonths \t\n", "years AND months", 1),
                    ("\"years months days\"", "years AND months AND days", 1),
                    ("FOOÉı👨👨🏿🇫🇷🇨🇮", "fooÉı👨👨🏿🇫🇷🇨🇮", 0),
                    ]
                for (string, expectedRawPattern, expectedCount) in cases {
                    if let pattern = FTS3Pattern(matchingAllTokensIn: string) {
                        let rawPattern = String.fromDatabaseValue(pattern.databaseValue)
                        XCTAssertEqual(rawPattern, expectedRawPattern)
                        let count = Int.fetchOne(db, "SELECT COUNT(*) FROM books WHERE books MATCH ?", arguments: [pattern])!
                        XCTAssertEqual(count, expectedCount, "Expected pattern \(String(reflecting: rawPattern)) to yield \(expectedCount) results")
                    }
                }
            }
        }
    }
    
    func testFTS3PatternWithPhrase() {
        let wrongInputs = ["", "*", "^", " ", "(", "()", "\""]
        for string in wrongInputs {
            if let pattern = FTS3Pattern(matchingPhrase: string) {
                let rawPattern = String.fromDatabaseValue(pattern.databaseValue)
                XCTFail("Unexpected raw pattern \(String(reflecting: rawPattern)) from string \(String(reflecting: string))")
            }
        }
        
        assertNoError {
            let dbQueue = try makeDatabaseQueue()
            dbQueue.inDatabase { db in
                // Couples (pattern, expected raw pattern, expected count of matching rows)
                let cases = [
                    ("Moby", "\"moby\"", 1),
                    ("^Moby*", "\"moby\"", 1),
                    (" \t\nyears \t\nmonths \t\n", "\"years months\"", 0),
                    ("\"years months days\"", "\"years months days\"", 0),
                    ("FOOÉı👨👨🏿🇫🇷🇨🇮", "\"fooÉı👨👨🏿🇫🇷🇨🇮\"", 0),
                    ]
                for (string, expectedRawPattern, expectedCount) in cases {
                    if let pattern = FTS3Pattern(matchingPhrase: string) {
                        let rawPattern = String.fromDatabaseValue(pattern.databaseValue)
                        XCTAssertEqual(rawPattern, expectedRawPattern)
                        let count = Int.fetchOne(db, "SELECT COUNT(*) FROM books WHERE books MATCH ?", arguments: [pattern])!
                        XCTAssertEqual(count, expectedCount, "Expected pattern \(String(reflecting: rawPattern)) to yield \(expectedCount) results")
                    }
                }
            }
        }
    }
}
