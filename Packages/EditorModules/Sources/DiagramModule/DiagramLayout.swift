import Foundation

/// Layout por capas (no es un Sugiyama completo): ciclos invertidos para ordenar, rango por el camino más largo,
/// nodos virtuales en las aristas que saltan capas, barycenter para reducir cruces y coordenadas con separación mínima.
/// Determinista: los empates se resuelven por orden de aparición en el bloque.
public struct DiagramLayout: Equatable, Sendable {
    public struct Route: Equatable, Sendable {
        public var points: [CGPoint]
        public var label: String?
        public var labelCenter: CGPoint?
    }

    public var size: CGSize
    public var frames: [CGRect]
    public var routes: [Route]

    public static let margin: CGFloat = 16
    public static let nodeGap: CGFloat = 40
    public static let layerGap: CGFloat = 80

    public init(graph: DiagramGraph, sizes: [CGSize]) {
        precondition(sizes.count == graph.nodes.count)
        let horizontal = graph.direction == .leftRight
        // Eje de capas (rank) y eje dentro de la capa (cross); en LR se intercambian.
        let crossSize = sizes.map { horizontal ? $0.height : $0.width }
        let rankSize = sizes.map { horizontal ? $0.width : $0.height }
        let count = graph.nodes.count
        let position = Dictionary(graph.nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        // 1. Aristas por índice, sin duplicados exactos.
        var edges: [(from: Int, to: Int, label: String?)] = []
        for edge in graph.edges {
            guard let from = position[edge.from], let to = position[edge.to] else { continue }
            if !edges.contains(where: { $0.from == from && $0.to == to && $0.label == edge.label }) {
                edges.append((from, to, edge.label))
            }
        }

        // 2. Aristas de retroceso con DFS en orden de aparición.
        var outgoing = Array(repeating: [Int](), count: count)
        for (index, edge) in edges.enumerated() where edge.from != edge.to { outgoing[edge.from].append(index) }
        var state = Array(repeating: 0, count: count)
        var back = Set<Int>()
        func visit(_ node: Int) {
            state[node] = 1
            for index in outgoing[node] {
                let target = edges[index].to
                if state[target] == 1 { back.insert(index) } else if state[target] == 0 { visit(target) }
            }
            state[node] = 2
        }
        for node in 0..<count where state[node] == 0 { visit(node) }

        // 3. Rango por el camino más largo sobre el DAG (retrocesos invertidos).
        let dagEdges: [(Int, Int)?] = edges.enumerated().map { index, edge in
            guard edge.from != edge.to else { return nil }
            return back.contains(index) ? (edge.to, edge.from) : (edge.from, edge.to)
        }
        var rank = Array(repeating: 0, count: count)
        var indegree = Array(repeating: 0, count: count)
        var successors = Array(repeating: [Int](), count: count)
        for case let (from, to)? in dagEdges {
            indegree[to] += 1
            successors[from].append(to)
        }
        var ready = (0..<count).filter { indegree[$0] == 0 }
        while !ready.isEmpty {
            let node = ready.removeFirst()
            for next in successors[node] {
                rank[next] = max(rank[next], rank[node] + 1)
                indegree[next] -= 1
                if indegree[next] == 0 {
                    ready.append(next)
                    ready.sort()
                }
            }
        }

        // 4. Vértices: nodos reales y virtuales (uno por capa intermedia de cada arista larga).
        var vertexRank = rank
        var vertexCross = crossSize
        var chains: [[Int]?] = []
        for dag in dagEdges {
            guard let (from, to) = dag else { chains.append(nil); continue }
            var chain = [from]
            for layer in stride(from: rank[from] + 1, to: rank[to], by: 1) {
                chain.append(vertexRank.count)
                vertexRank.append(layer)
                vertexCross.append(0)
            }
            chain.append(to)
            chains.append(chain)
        }
        let vertexCount = vertexRank.count
        var up = Array(repeating: [Int](), count: vertexCount)
        var down = Array(repeating: [Int](), count: vertexCount)
        for case let chain? in chains {
            for (a, b) in zip(chain, chain.dropFirst()) {
                down[a].append(b)
                up[b].append(a)
            }
        }
        let layerCount = (vertexRank.max() ?? 0) + 1
        var layers = Array(repeating: [Int](), count: layerCount)
        for vertex in 0..<vertexCount { layers[vertexRank[vertex]].append(vertex) }

        // 5. Orden dentro de cada capa: barridos de barycenter, conservando el de menos cruces.
        func slots(_ layers: [[Int]]) -> [Int] {
            var slot = Array(repeating: 0, count: vertexCount)
            for layer in layers { for (index, vertex) in layer.enumerated() { slot[vertex] = index } }
            return slot
        }
        func crossings(_ layers: [[Int]]) -> Int {
            let slot = slots(layers)
            var total = 0
            for layer in layers.dropLast() {
                let segments = layer.flatMap { a in down[a].map { (slot[a], slot[$0]) } }
                for i in segments.indices {
                    for j in segments.indices where j > i {
                        if (segments[i].0 - segments[j].0) * (segments[i].1 - segments[j].1) < 0 { total += 1 }
                    }
                }
            }
            return total
        }
        var best = layers
        var bestCrossings = crossings(layers)
        for pass in 0..<8 where bestCrossings > 0 {
            let downward = pass % 2 == 0
            let slot = slots(layers)
            let order = downward ? Array(1..<layerCount) : Array((0..<max(0, layerCount - 1)).reversed())
            var current = slot
            for layerIndex in order {
                let keyed = layers[layerIndex].map { vertex -> (Int, Double) in
                    let neighbours = downward ? up[vertex] : down[vertex]
                    guard !neighbours.isEmpty else { return (vertex, Double(current[vertex])) }
                    return (vertex, Double(neighbours.map { current[$0] }.reduce(0, +)) / Double(neighbours.count))
                }
                layers[layerIndex] = keyed.enumerated()
                    .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
                    .map(\.element.0)
                for (index, vertex) in layers[layerIndex].enumerated() { current[vertex] = index }
            }
            let score = crossings(layers)
            if score < bestCrossings {
                best = layers
                bestCrossings = score
            }
        }
        layers = best

        // 6. Coordenada cruzada: cada vértice hacia la media de sus vecinos, sin invadir a los de al lado.
        func separation(_ a: Int, _ b: Int) -> CGFloat {
            let gap = vertexCross[a] == 0 || vertexCross[b] == 0 ? Self.nodeGap / 2 : Self.nodeGap
            return vertexCross[a] / 2 + vertexCross[b] / 2 + gap
        }
        var cross = Array(repeating: CGFloat(0), count: vertexCount)
        for layer in layers {
            var cursor: CGFloat = 0
            for (index, vertex) in layer.enumerated() {
                if index > 0 { cursor += separation(layer[index - 1], vertex) }
                cross[vertex] = cursor
            }
        }
        func place(_ layer: [Int], desired: [CGFloat]) {
            guard !layer.isEmpty else { return }
            var left = desired
            for index in layer.indices.dropFirst() {
                left[index] = max(desired[index], left[index - 1] + separation(layer[index - 1], layer[index]))
            }
            var right = desired
            for index in layer.indices.dropLast().reversed() {
                right[index] = min(desired[index], right[index + 1] - separation(layer[index], layer[index + 1]))
            }
            for (index, vertex) in layer.enumerated() { cross[vertex] = (left[index] + right[index]) / 2 }
        }
        for pass in 0..<6 {
            let downward = pass % 2 == 0
            let order = downward ? Array(layers.indices) : Array(layers.indices.reversed())
            for layerIndex in order {
                let layer = layers[layerIndex]
                let desired = layer.map { vertex -> CGFloat in
                    let neighbours = (downward ? up[vertex] : down[vertex]) + (pass >= 4 ? (downward ? down[vertex] : up[vertex]) : [])
                    guard !neighbours.isEmpty else { return cross[vertex] }
                    return neighbours.map { cross[$0] }.reduce(0, +) / CGFloat(neighbours.count)
                }
                place(layer, desired: desired)
            }
        }
        let minCross = (0..<vertexCount).map { cross[$0] - vertexCross[$0] / 2 }.min() ?? 0
        for vertex in 0..<vertexCount { cross[vertex] += Self.margin - minCross }

        // 7. Eje de capas: cada capa ocupa el alto de su nodo mayor.
        var bandStart = Array(repeating: CGFloat(0), count: layerCount)
        var bandSize = Array(repeating: CGFloat(0), count: layerCount)
        for node in 0..<count { bandSize[rank[node]] = max(bandSize[rank[node]], rankSize[node]) }
        var cursor = Self.margin
        for layer in 0..<layerCount {
            bandStart[layer] = cursor
            cursor += bandSize[layer] + Self.layerGap
        }
        func point(cross c: CGFloat, rank r: CGFloat) -> CGPoint { horizontal ? CGPoint(x: r, y: c) : CGPoint(x: c, y: r) }
        func center(_ node: Int) -> CGFloat { bandStart[rank[node]] + bandSize[rank[node]] / 2 }

        frames = (0..<count).map { node in
            let origin = point(cross: cross[node] - crossSize[node] / 2, rank: center(node) - rankSize[node] / 2)
            return CGRect(origin: origin, size: sizes[node])
        }

        // 8. Puertos: cada arista que sale o entra por el mismo lado tiene su propio punto a lo ancho del nodo,
        // también las de ida y vuelta entre los mismos nodos.
        func ports(_ node: Int, _ ends: [(edge: Int, vertex: Int)]) -> [Int: CGFloat] {
            let sorted = ends.sorted { (cross[$0.vertex], $0.edge) < (cross[$1.vertex], $1.edge) }
            guard sorted.count > 1 else { return Dictionary(uniqueKeysWithValues: sorted.map { ($0.edge, cross[node]) }) }
            let step = min(18, crossSize[node] * 0.5 / CGFloat(sorted.count - 1))
            return Dictionary(uniqueKeysWithValues: sorted.enumerated().map { index, end in
                (end.edge, cross[node] + (CGFloat(index) - CGFloat(sorted.count - 1) / 2) * step)
            })
        }
        var exits = Array(repeating: [(edge: Int, vertex: Int)](), count: count)
        var entries = Array(repeating: [(edge: Int, vertex: Int)](), count: count)
        for (index, chain) in chains.enumerated() {
            guard let chain else { continue }
            exits[chain[0]].append((index, chain[1]))
            entries[chain[chain.count - 1]].append((index, chain[chain.count - 2]))
        }
        let exitPorts = (0..<count).map { ports($0, exits[$0]) }
        let entryPorts = (0..<count).map { ports($0, entries[$0]) }
        // Distancia del centro al borde, en el eje de capas, a una altura del eje cruzado.
        func border(_ node: Int, at port: CGFloat) -> CGFloat {
            let half = rankSize[node] / 2
            let offset = abs(port - cross[node])
            switch graph.nodes[node].shape {
            case .rounded, .stadium: return half
            case .decision: return half * max(0, 1 - 2 * offset / crossSize[node])
            case .terminal: return (max(0, half * half - offset * offset)).squareRoot()
            }
        }

        routes = edges.enumerated().map { index, edge in
            guard let chain = chains[index] else {
                // Bucle sobre sí mismo por el lado de salida del eje cruzado.
                let node = edge.from
                let side = cross[node] + crossSize[node] / 2
                let middle = center(node)
                let points = [
                    point(cross: side, rank: middle - 8), point(cross: side + 24, rank: middle - 8),
                    point(cross: side + 24, rank: middle + 8), point(cross: side, rank: middle + 8),
                ]
                return Route(points: points, label: edge.label, labelCenter: edge.label.map { _ in point(cross: side + 24, rank: middle) })
            }
            var points: [CGPoint] = []
            func append(_ next: CGPoint) {
                if points.last.map({ abs($0.x - next.x) < 0.5 && abs($0.y - next.y) < 0.5 }) != true { points.append(next) }
            }
            let first = chain[0]
            let exit = exitPorts[first][index] ?? cross[first]
            append(point(cross: exit, rank: center(first) + border(first, at: exit)))
            // Rombos y círculos salen en diagonal desde su borde, sin un tramo recto hasta el final de la capa.
            let curved = { (node: Int) in graph.nodes[node].shape == .decision || graph.nodes[node].shape == .terminal }
            if !curved(first) { append(point(cross: exit, rank: bandStart[rank[first]] + bandSize[rank[first]])) }
            for vertex in chain.dropFirst().dropLast() {
                append(point(cross: cross[vertex], rank: bandStart[vertexRank[vertex]]))
                append(point(cross: cross[vertex], rank: bandStart[vertexRank[vertex]] + bandSize[vertexRank[vertex]]))
            }
            let last = chain[chain.count - 1]
            let entry = entryPorts[last][index] ?? cross[last]
            if !curved(last) { append(point(cross: entry, rank: bandStart[rank[last]])) }
            append(point(cross: entry, rank: center(last) - border(last, at: entry)))
            // La etiqueta va en el primer hueco entre capas del sentido del DAG.
            let gapStart = point(cross: exit, rank: bandStart[rank[first]] + bandSize[rank[first]])
            let nextVertex = chain[1]
            let gapEnd = point(cross: nextVertex < count ? entry : cross[nextVertex], rank: bandStart[vertexRank[nextVertex]])
            let labelCenter = CGPoint(x: (gapStart.x + gapEnd.x) / 2, y: (gapStart.y + gapEnd.y) / 2)
            if back.contains(index) { points.reverse() }
            return Route(points: points, label: edge.label, labelCenter: edge.label == nil ? nil : labelCenter)
        }

        let maxCross = (0..<vertexCount).map { cross[$0] + vertexCross[$0] / 2 }.max() ?? 0
        let selfLoopExtra: CGFloat = edges.contains { $0.from == $0.to } ? 32 : 0
        let extent = point(cross: maxCross + Self.margin + selfLoopExtra, rank: cursor - Self.layerGap + Self.margin)
        size = CGSize(width: extent.x, height: extent.y)
    }
}
