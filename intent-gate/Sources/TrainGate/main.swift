// Entrena MLTextClassifier (transferLearning BERT, español) con split
// estratificado reproducible. Guarda .mlmodel + validation.csv + métricas.
import CreateML
import Foundation
import NaturalLanguage

struct Sample: Codable {
    let text: String
    let label: String
    let category: String
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let modelsDir = cwd.appendingPathComponent("models")
try fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)

let data = try Data(contentsOf: cwd.appendingPathComponent("data/dataset.json"))
var all = try JSONDecoder().decode([Sample].self, from: data)
print("dataset: \(all.count) filas")

// Split estratificado 80/20 reproducible (seed fija, sin barajar global con RNG del sistema).
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
func stratifiedSplit(_ samples: [Sample], ratio: Double, seed: UInt64) -> (train: [Sample], val: [Sample]) {
    var train: [Sample] = [], val: [Sample] = []
    for label in ["EDITOR_CONTROL", "DICTATION"] {
        var group = samples.filter { $0.label == label }
        var rng = SeededRNG(state: seed)
        group.shuffle(using: &rng)
        let nTrain = Int((Double(group.count) * ratio).rounded(.down))
        train += group.prefix(nTrain)
        val += group.dropFirst(nTrain)
    }
    var rng = SeededRNG(state: seed + 1)
    train.shuffle(using: &rng)
    return (train, val)
}
let (trainSamples, valSamples) = stratifiedSplit(all, ratio: 0.8, seed: 42)
print("train: \(trainSamples.count)  validation: \(valSamples.count)")

func table(_ samples: [Sample]) throws -> MLDataTable {
    try MLDataTable(dictionary: [
        "text": samples.map(\.text),
        "label": samples.map(\.label),
    ])
}
let train = try table(trainSamples)
let validation = try table(valSamples)

// Guarda validation.csv para selección de threshold (idéntico split).
var csv = "text,label,category\n"
for s in valSamples {
    let t = s.text.replacingOccurrences(of: "\"", with: "\"\"")
    csv += "\"\(t)\",\(s.label),\(s.category)\n"
}
try csv.write(to: modelsDir.appendingPathComponent("validation.csv"),
              atomically: true, encoding: .utf8)

let params = MLTextClassifier.ModelParameters(
    validation: .table(validation, textColumn: "text", labelColumn: "label"),
    algorithm: .transferLearning(.bertEmbedding, revision: 1),
    language: .spanish
)
print("algorithm=\(params.algorithm) language=\(params.language)")

let t0 = ContinuousClock().now
let model = try MLTextClassifier(trainingData: train, textColumn: "text",
                                 labelColumn: "label", parameters: params)
let trainSec = ContinuousClock().now - t0
print(String(format: "training time: %.1f s", Double(trainSec.components.seconds)))

let te = model.trainingMetrics
print(String(format: "train classificationError=%.4f", te.classificationError))
let ve = model.validationMetrics
print(String(format: "validation classificationError=%.4f", ve.classificationError))

let modelURL = modelsDir.appendingPathComponent("IntentGate.mlmodel")
try model.write(to: modelURL)
print("modelo escrito: \(modelURL.path)")
