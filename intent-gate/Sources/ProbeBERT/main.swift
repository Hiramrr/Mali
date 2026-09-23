// Sonda 3: miembros reales de MLClassifierMetrics.
import CreateML
import Foundation

let table = try MLDataTable(dictionary: [
    "text": (1...10).map { "orden número \($0) cambia el título" } +
            (1...10).map { "dictado número \($0) sobre interfaces" },
    "label": Array(repeating: "EDITOR_CONTROL", count: 10) + Array(repeating: "DICTATION", count: 10),
])
let m = try MLTextClassifier(trainingData: table, textColumn: "text", labelColumn: "label")
let metrics = m.trainingMetrics
print("TYPE: \(type(of: metrics))")
for child in Mirror(reflecting: metrics).children {
    print("member: \(child.label ?? "?") : \(type(of: child.value))")
}
