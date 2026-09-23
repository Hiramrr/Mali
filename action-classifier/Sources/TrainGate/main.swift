// Action classifier: mismo algoritmo exacto, 15 clases.
import CreateML
import Foundation
import NaturalLanguage

struct Sample: Codable {
    let text: String
    let label: String
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let modelsDir = cwd.appendingPathComponent("models")
try fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)

let data = try Data(contentsOf: cwd.appendingPathComponent("data/train.json"))
let trainSamples = try JSONDecoder().decode([Sample].self, from: data)
print("train: \(trainSamples.count)")

let train = try MLDataTable(dictionary: [
    "text": trainSamples.map(\.text),
    "label": trainSamples.map(\.label),
])
let params = MLTextClassifier.ModelParameters(
    algorithm: .transferLearning(.bertEmbedding, revision: 1),
    language: .spanish
)
print("algorithm=\(params.algorithm) language=\(params.language)")

let t0 = ContinuousClock().now
let model = try MLTextClassifier(trainingData: train, textColumn: "text",
                                 labelColumn: "label", parameters: params)
let comps = (ContinuousClock().now - t0).components
print(String(format: "training time: %.1f s", Double(comps.seconds)))
print(String(format: "train classificationError=%.4f", model.trainingMetrics.classificationError))

let modelURL = modelsDir.appendingPathComponent("ActionClassifier.mlmodel")
try model.write(to: modelURL)
print("modelo escrito: \(modelURL.path)")
