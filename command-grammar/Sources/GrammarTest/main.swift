// Runner: `test` (unit), `live` (mic), `protocol` (lista live).
import Foundation

@main
struct Runner {
    static func main() async {
        let args = CommandLine.arguments
        if args.contains("live") {
            await runLive()
        } else if args.contains("protocol") {
            printLiveProtocol()
        } else if let i = args.firstIndex(of: "transcribe"), i + 1 < args.count {
            await transcribeCommand(path: args[i + 1])
        } else {
            let (p1, f1) = runGrammarTests()
            let (p2, f2) = runGrammarTests2()
            let total = grammarTests.count + grammarTests2.count
            print("grammar tests: \(p1 + p2)/\(total)")
            for (input, exp, got) in f1 + f2 {
                print("FAIL input=[\(input)]\n  exp=\(exp)\n  got=\(got)")
            }
        }
    }

    static func transcribeCommand(path: String) async {
        let url = URL(fileURLWithPath: path)
        let locale = Locale(identifier: "es_MX")
        do {
            let (text, ms) = try await transcribeFile(url, locale: locale)
            print("RAW: \(text)")
            print("NORM: \(normalizeUtterance(text))")
            let p0 = ContinuousClock().now
            let parsed = parseCommand(raw: text)
            let c = ContinuousClock().now
            let pms = Double((c - p0).components.seconds) * 1000.0
            print("PARSED: \(parsed)")
            print(String(format: "STT: %.0f ms  parser: %.3f ms", ms, pms))
        } catch {
            print("STT error: \(error)")
        }
    }

    static func printLiveProtocol() {
        print("Protocolo en vivo: 48 órdenes x2 + 15 unsupported + 15 unknown.")
        print("El runner `live` guía la captura. Ver README.")
    }

    /// Sesión guiada: muestra cada frase, graba mic, transcribe, parsea, registra.
    /// Requiere permiso de micrófono (Ajustes > Privacidad > Micrófono).
    static func runLive() async {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard let proto = try? String(contentsOf: base.appendingPathComponent("data/live_protocol.csv"), encoding: .utf8) else {
            print("falta data/live_protocol.csv")
            return
        }
        let locale = Locale(identifier: "es_MX")
        let outURL = base.appendingPathComponent("live_results.csv")
        let header = "id,kind,expected_spoken,expected,raw,norm,parsed,stt_ms,parse_ms\n"
        if !FileManager.default.fileExists(atPath: outURL.path) {
            try? header.write(to: outURL, atomically: true, encoding: .utf8)
        }
        var n = 0
        for line in proto.components(separatedBy: "\n").dropFirst() {
            let p = splitCSVLine(line)
            guard p.count >= 4, !p[0].isEmpty else { continue }
            n += 1
            print("\n[\(p[0]) \(p[1])] DI:")
            print(p[2])
            print("Enter para grabar...")
            _ = readLine()
            let wav = FileManager.default.temporaryDirectory.appendingPathComponent("cmd.wav")
            do {
                try await recordMic(to: wav)
                let s = ContinuousClock().now
                let (text, sttMs) = try await transcribeFile(wav, locale: locale)
                let p0 = ContinuousClock().now
                let parsed = parseCommand(raw: text)
                let c = ContinuousClock().now
                let pms = Double((c - p0).components.seconds) * 1000.0
                _ = s
                let norm = normalizeUtterance(text)
                print("RAW: \(text)")
                print("PARSED: \(parsed)  esperado: \(p[3])")
                print(String(format: "STT %.0f ms parser %.3f ms", sttMs, pms))
                let row = "\(p[0]),\(p[1]),\"\(p[2])\",\(p[3]),\"\(text)\",\"\(norm)\",\"\(parsed)\",\(Int(sttMs)),\(pms)\n"
                if let fh = try? FileHandle(forWritingTo: outURL) {
                    fh.seekToEndOfFile()
                    fh.write(Data(row.utf8))
                    try? fh.close()
                }
            } catch {
                print("error: \(error)")
            }
        }
        print("\nSesión completa (\(n) utterances). Resultados en live_results.csv")
    }

    static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var f = ""
        var q = false
        for c in line {
            if q {
                if c == "\"" { q = false }
                else { f.append(c) }
            } else if c == "\"" { q = true }
            else if c == "," { fields.append(f); f = "" }
            else { f.append(c) }
        }
        fields.append(f)
        return fields
    }
}
