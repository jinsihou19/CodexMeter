// 海风小岛的独立地形、步行路线和原生 SceneKit 道具。
import AppKit
import SceneKit
import simd

/// 海岛在 x = 0 留出主路，与人物的通道改道逻辑共用同一个坐标约定。
enum OfficeIslandLayout {
    static let back: CGFloat = -7.30
    static let workshopX: CGFloat = -4.96
    static let toolStation = SCNVector3(3.72, 2.35, 0.94)
    static let figureScale: CGFloat = 1.24
    static let benchSeatOffset: CGFloat = 0.49

    /// 首间工坊与前景休息区之间留空，后续工坊在岛的前岸延伸段上排布。
    static func workshopZ(_ index: Int) -> CGFloat { index == 0 ? 0 : 10.12 + CGFloat(index - 1) * 6.68 }

    /// 第一张长椅朝向前景，溢出的长椅放在主路右侧，避开扩建的工坊。
    static func benchCenter(_ index: Int) -> CGPoint {
        if index == 0 { return CGPoint(x: -4.18, y: 5.15) }
        return CGPoint(x: index.isMultiple(of: 2) ? 6.36 : 2.83, y: 4.99 + CGFloat((index - 1) / 2) * 2.29)
    }

    /// 为最靠岸的房间和长椅留出可走的路肩。无在场会话时也有一座完整小岛。
    static func shoreEnd(workshops: Int, benches: Int) -> CGFloat {
        max(8.33, workshopZ(workshops - 1) + 4.48, benchCenter(benches - 1).y + 2.85)
    }

    /// 座位朝向相机侧，从椅子侧边接入走道，路线经过桌子的后方。
    static func deskDestination(for index: Int) -> OfficeDestination {
        let seat = index % CodexOfficeSeatBook.roomCapacity
        let seatOffsets: [(CGFloat, CGFloat, CGFloat)] = [(0, 1.14, 0.13), (2.24, 1.15, -0.10), (-2.26, 1.08, 0.06),
                                                          (2.24, -1.37, 0), (-0.02, -1.48, 0), (-2.30, -1.43, 0)]
        let (dx, dz, heading) = seatOffsets[seat]
        let x = workshopX + dx
        let centerZ = workshopZ(index / CodexOfficeSeatBook.roomCapacity)
        let z = centerZ + dz
        let aisleZ = centerZ + (seat < 3 ? 0.28 : -2.28)
        return OfficeDestination(route: [CGPoint(x: 0, y: aisleZ), CGPoint(x: x + 0.92, y: aisleZ),
                                         CGPoint(x: x + 0.92, y: z), CGPoint(x: x, y: z)],
                                 heading: heading, seated: true, kind: .desk)
    }

    /// 长椅从前方入座，避开椅背和同一排的另一张长椅。
    static func restDestination(for index: Int) -> OfficeDestination {
        let center = benchCenter(index / 2)
        let x = center.x + (index.isMultiple(of: 2) ? benchSeatOffset : -benchSeatOffset)
        return OfficeDestination(route: [CGPoint(x: 0, y: center.y + 1.01), CGPoint(x: x, y: center.y + 1.01),
                                         CGPoint(x: x, y: center.y)], heading: 0, seated: true, kind: .rest)
    }

    /// 主路双向分流，路口和椅子侧面的原有转弯点保持原位。
    static func walkingLanes(on path: [CGPoint]) -> [CGPoint] {
        guard let origin = path.first else { return path }
        var waypoints = [origin]
        for (start, end) in zip(path, path.dropFirst()) {
            let length = end.y - start.y
            if start.x == 0, end.x == 0, abs(length) > 1.05 {
                let direction: CGFloat = length > 0 ? 1 : -1
                waypoints.append(CGPoint(x: direction * 0.43, y: start.y + direction * 0.27))
                waypoints.append(CGPoint(x: direction * 0.43, y: end.y - direction * 0.27))
            }
            waypoints.append(end)
        }
        return waypoints
    }
}

/// 组装有真实体积的陶瓦、木作和海岸。静态布景与动态工位分开，方便状态刷新和昼夜切换。
@MainActor
final class OfficeIslandScenery {
    /// 可见表面的纹理和高光共用缓存。小物件仍可使用纯色陶塑。
    private enum Finish: Int { case matte, limestone, timber, ceramic, copper }

    private let night: Bool
    private var paints: [Int: SCNMaterial] = [:]
    private let plaster = 0xF2D8AC
    private let stone = 0xD9B887
    private let wood = 0xBB8249
    private let darkWood = 0x80502D
    private let terracotta = [0xCE683B, 0xDB7E47, 0xC7663C, 0xD87742]
    private let blueTiles = [0x556D9D, 0x667EAA, 0x586A97, 0x6E85B2]

    /// 光源颜色由场景导演统一管理，这里只处理窗灯、海色和道具材质。
    init(night: Bool) { self.night = night }

    /// 在完整岸线内布置三个用途区域，扩建时由同一条石板路串联。
    func build(on site: SCNNode, workshops: Int, benches: Int, end: CGFloat) {
        let land = group("island-land", in: site)
        buildShore(in: land, end: end)
        pave(in: site, from: CGPoint(x: 0, y: -3.05), to: CGPoint(x: 0, y: end - 0.94))
        for index in 0..<workshops {
            let z = OfficeIslandLayout.workshopZ(index)
            workshop(in: site, z: z)
            for aisle in [z - 2.28, z + 0.28] {
                pave(in: site, from: CGPoint(x: 0, y: aisle), to: CGPoint(x: -1.12, y: aisle))
            }
        }
        toolHut(in: site)
        pave(in: site, from: CGPoint(x: 0, y: 2.22), to: CGPoint(x: 8.63, y: 2.22))
        for index in 0..<benches {
            let center = OfficeIslandLayout.benchCenter(index)
            bench(in: site, at: center)
            if index == 0 || !index.isMultiple(of: 2) {
                let last = OfficeIslandLayout.benchCenter(index == 0 ? 0 : min(index + 1, benches - 1))
                let outerEdge: CGFloat = last.x < 0 ? -0.50 : 0.50
                pave(in: site, from: CGPoint(x: 0, y: center.y + 1.01),
                     to: CGPoint(x: last.x + outerEdge, y: last.y + 1.01))
            }
        }
        windmill(in: site)
        tree(in: site, x: -6.13, z: -5.30, scale: 1.20)
        tree(in: site, x: 4.51, z: -5.27, scale: 1.20)
        for (x, z) in [(-8.88, -1.65), (-8.85, 3.48), (-5.22, end - 1.31),
                       (1.34, -4.25), (7.36, -3.94), (8.49, 4.20), (2.08, end - 1.07)] {
            flowers(in: site, x: x, z: z)
        }
        for (x, z, size) in [(-8.85, -3.20, 0.63), (-8.19, 4.10, 0.84), (-7.91, end - 2.70, 0.56),
                             (-4.60, end - 1.29, 0.72), (-2.05, end - 0.89, 0.60),
                             (3.49, -4.45, 0.85), (7.70, -3.02, 0.76), (8.06, 3.48, 0.58), (5.13, end - 1.50, 0.70)] {
            shrubs(in: site, x: x, z: z, size: size)
        }
        lantern(in: site, at: SCNVector3(-2.31, 0, 5.45), height: 0.91)
        lantern(in: site, at: SCNVector3(1.72, 0, 4.38), height: 0.68)
        let shelter = OfficeIslandLayout.benchCenter(0)
        fence(in: site, x: shelter.x - 2.04, z: shelter.y - 0.43)
        barrel(in: site, at: SCNVector3(shelter.x + 1.30, 0, shelter.y - 0.16), size: 0.88)
        for (x, z, size) in [(-8.64, 3.12, 1.10), (-6.64, 5.31, 0.90), (-5.88, 6.58, 0.79),
                             (-2.57, 7.16, 0.65), (4.80, 3.71, 0.92), (7.38, 3.71, 0.82), (8.56, -2.21, 0.95)] {
            shrubs(in: site, x: x, z: z, size: size)
            flowers(in: site, x: x + 0.39, z: z + 0.29)
        }
        mergeStaticMeshes(in: site)
    }

    /// 工位的根节点带会话 ID，点人物、桌面或电脑都能打开同一个档案。
    func workstation(for id: String, index: Int, projectTint: Int) -> (SCNNode, OfficeDestination) {
        let destination = OfficeIslandLayout.deskDestination(for: index)
        let seat = destination.route[3]
        let root = SCNNode()
        root.name = "employee:" + id
        root.position = SCNVector3(seat.x, 0, seat.y)
        root.eulerAngles.y = destination.heading
        let main = index.isMultiple(of: CodexOfficeSeatBook.roomCapacity)
        let desk = group("island-workstation", in: root, at: SCNVector3(0, 0, 0.83))
        let width: CGFloat = main ? 1.73 : 1.47
        contactShadow(width + 0.41, 1.51, in: desk, at: SCNVector3(0.04, 0.055, 0.02), opacity: 0.72)
        if main {
            box(1.84, 0.021, 1.66, 0xD8BE83, in: root, at: SCNVector3(0, 0.057, 0.50), bevel: 0.02)
            box(1.71, 0.018, 1.52, 0x759D9D, in: root, at: SCNVector3(0, 0.069, 0.50), bevel: 0.02)
        }
        box(width, 0.16, 0.86, wood, in: desk, at: SCNVector3(0, 0.99, 0), bevel: 0.078, finish: .timber)
        box(width - 0.17, 0.16, 0.68, darkWood, in: desk, at: SCNVector3(0, 0.86, 0), finish: .timber)
        for x in [-width / 2 + 0.15, width / 2 - 0.15] {
            for z: CGFloat in [-0.31, 0.31] {
                box(0.17, 0.80, 0.17, darkWood, in: desk, at: SCNVector3(x, 0.40, z), bevel: 0.054, finish: .timber)
            }
        }
        box(0.82, 0.046, 0.48, 0x5B6562, in: desk, at: SCNVector3(-0.08, 1.091, -0.06))
        let lid = box(0.82, 0.51, 0.053, 0xACA99B, in: desk, at: SCNVector3(-0.08, 1.34, 0.145))
        lid.eulerAngles.x = 0.17
        let display = box(0.71, 0.39, 0.012, 0x456B75, in: lid, at: SCNVector3(0, 0, -0.033))
        glow(display, 0x7CC8BF, strength: night ? 0.65 : 0.28)
        box(0.34, 0.065, 0.23, projectTint, in: desk, at: SCNVector3(0.48, 1.108, -0.12))
        if main {
            box(0.40, 0.022, 0.46, 0x709798, in: desk, at: SCNVector3(0.33, 1.078, 0.20))
            box(0.40, 0.18, 0.028, 0x779C9C, in: desk, at: SCNVector3(0.33, 0.996, 0.439))
            desk.addChildNode(restCup(at: SCNVector3(-0.58, 1.075, 0.14)))
        } else {
            lantern(in: desk, at: SCNVector3(0.52, 1.068, 0.23), height: 0.37)
        }
        box(0.68, 0.14, 0.61, wood, in: root, at: SCNVector3(0, 0.54, 0), bevel: 0.065, finish: .timber)
        box(0.64, 0.34, 0.092, darkWood, in: root, at: SCNVector3(0, 0.80, -0.29), finish: .timber)
        for x: CGFloat in [-0.25, 0.25] {
            box(0.12, 0.51, 0.48, darkWood, in: root, at: SCNVector3(x, 0.255, 0), finish: .timber)
        }
        mergeStaticMeshes(in: root)
        return (root, destination)
    }

    /// 海水层、浅滩和草地都有各自的高度，船坞和岛壁从旋转视角也成立。
    private func buildShore(in root: SCNNode, end: CGFloat) {
        let waterSize = max(150, end * 2.3)
        let water = node(SCNPlane(width: waterSize, height: waterSize), night ? 0x123C5B : 0x168FA5,
                         in: root, at: SCNVector3(0, -1.25, (end + OfficeIslandLayout.back) / 2))
        water.name = "island-water"
        water.eulerAngles.x = -.pi / 2
        water.castsShadow = false
        let surface = constant(night ? 0x123C5B : 0x168FA5)
        water.geometry?.materials = [surface]
        if let texture = night ? Self.nightWater : Self.dayWater {
            let repeats = ceil(waterSize / 12)
            tile(texture, on: surface.diffuse, repeats: repeats)
            let period = waterSize / repeats
            // 每次平移恰好一个纹理周期，复位时保持水纹连续，并随场景暂停。
            water.runAction(.repeatForever(.sequence([.moveBy(x: period, y: 0, z: 0, duration: 33),
                                                      .moveBy(x: -period, y: 0, z: 0, duration: 0)])), forKey: "island-current")
        }
        let shore = coastline(end: end, margin: 0)
        let shallow = layer(coastline(end: end, margin: 0.73), depth: 0.041, y: -1.232,
                            color: night ? 0x185B73 : 0x5BD9BA, in: root)
        shallow.castsShadow = false
        shallow.opacity = 0.42
        shallow.geometry?.firstMaterial = constant(night ? 0x185B73 : 0x5BD9BA)
        for index in 0..<2 {
            let inset = CGFloat(index) * 0.26
            let foam = shoreRing(inner: coastline(end: end, margin: 0.13 + inset),
                                 outer: coastline(end: end, margin: 0.24 + inset), in: root)
            foam.opacity = night ? 0.27 : 0.70
            let flicker = SCNAction.sequence([.fadeOpacity(to: night ? 0.11 : 0.30, duration: 1.7 + Double(index) * 0.4),
                                              .fadeOpacity(to: foam.opacity, duration: 1.65)])
            foam.runAction(.repeatForever(flicker), forKey: "island-tide")
        }
        cliff(in: root, along: shore, centerZ: (end + OfficeIslandLayout.back) / 2)
        let grass = layer(shore, depth: 0.26, y: -0.13, color: 0x79A748, in: root)
        if let texture = Self.grass, let material = grass.geometry?.firstMaterial?.copy() as? SCNMaterial {
            tile(texture, on: material.diffuse, repeats: 2)
            grass.geometry?.materials = [material]
        }
        grassFringe(in: root, along: shore)
        for (index, offset) in [4, 14, 29, 40, 52, 58].enumerated() {
            let point = shore[offset]
            let rock = box(0.95 + CGFloat(index % 3) * 0.32, 0.61 + CGFloat(index % 3) * 0.18, 0.91,
                           [0xB3A28A, 0xA49883, 0xD4B692][index % 3], in: root,
                           at: SCNVector3(point.x * 1.048, -0.93, point.y + (point.y > 0 ? 0.22 : -0.24)),
                           bevel: 0.24, finish: .limestone)
            rock.eulerAngles = SCNVector3(0.12 * CGFloat(index % 3), CGFloat(index) * 0.54, -0.14)
        }
    }

    /// 倾斜的砂岩层与地面共用岸线，沿不同深度错落收放，形成连续崖壁。
    private func cliff(in parent: SCNNode, along outline: [CGPoint], centerZ: CGFloat) {
        let colors = [0xD5AC76, 0xC89C65, 0xDDB77E, 0xBA986F, 0xA98765, 0xC6A17A]
        let heights: [CGFloat] = [-0.07, -0.43, -0.87, -1.47]
        let rings = heights.indices.map { tier in
            outline.enumerated().map { index, point -> SCNVector3 in
                let shift: CGFloat = [0.994, 1.019, 0.982, 1.036][tier]
                let scallop = tier == 0 ? 0 : 0.019 * sin(CGFloat(index) * 2.27 + CGFloat(tier))
                let rise = tier == 0 ? 0 : 0.10 * cos(CGFloat(index) * 1.43 + CGFloat(tier) * 0.8)
                return SCNVector3(point.x * (shift + scallop), heights[tier] + rise,
                                  centerZ + (point.y - centerZ) * (shift + scallop))
            }
        }
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var faces = Array(repeating: [Int32](), count: colors.count)
        for tier in 0..<(rings.count - 1) {
            for index in outline.indices {
                let next = (index + 1) % outline.count
                let a = rings[tier][index]
                let b = rings[tier][next]
                let c = rings[tier + 1][index]
                let d = rings[tier + 1][next]
                let origin = Int32(vertices.count)
                vertices += [a, b, c, d]
                let tangent = SIMD3<Float>(b) - SIMD3<Float>(a)
                let down = SIMD3<Float>(c) - SIMD3<Float>(a)
                let normal = simd_normalize(simd_cross(tangent, down))
                normals += Array(repeating: SCNVector3(normal.x, normal.y, normal.z), count: 4)
                let u = CGFloat(index) * 0.51
                let v = CGFloat(tier) * 0.32
                texcoords += [CGPoint(x: u, y: v), CGPoint(x: u + 0.51, y: v),
                              CGPoint(x: u, y: v + 0.32), CGPoint(x: u + 0.51, y: v + 0.32)]
                let tint = tier == 0 ? index % 3 : (index + tier) % colors.count
                faces[tint] += [origin, origin + 1, origin + 2, origin + 1, origin + 3, origin + 2]
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                              SCNGeometrySource(textureCoordinates: texcoords)],
                                   elements: faces.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
        geometry.materials = colors.map { paint($0, finish: .limestone) }
        parent.addChildNode(SCNNode(geometry: geometry))
    }

    /// 草沿压住石崖上缘，细叶合成一块网格以减少细碎道具的绘制开销。
    private func grassFringe(in parent: SCNNode, along outline: [CGPoint]) {
        var vertices: [SCNVector3] = []
        var elements = Array(repeating: [Int32](), count: 3)
        for (index, point) in outline.enumerated() {
            let next = outline[(index + 1) % outline.count]
            for blade in 0..<6 {
                let t = CGFloat(blade) / 6
                let x = (point.x + (next.x - point.x) * t) * (blade.isMultiple(of: 2) ? 0.992 : 0.984)
                let z = point.y + (next.y - point.y) * t
                let lift = 0.045 + CGFloat((index * 7 + blade * 3) % 9) * 0.012
                let width = 0.07 + CGFloat(blade % 3) * 0.020
                let base = Int32(vertices.count)
                vertices += [SCNVector3(x - width, -0.012, z - 0.031), SCNVector3(x + width, -0.012, z + 0.038),
                             SCNVector3(x + width * 0.41, lift, z + 0.071)]
                elements[(index + blade) % elements.count] += [base, base + 1, base + 2]
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                                   elements: elements.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
        let colors = night ? [0x587638, 0x66843D, 0x728B43] : [0x7B9F39, 0x91AD44, 0x9FB74D]
        geometry.materials = colors.map {
            let blade = constant($0)
            blade.isDoubleSided = true
            return blade
        }
        let fringe = SCNNode(geometry: geometry)
        fringe.castsShadow = false
        parent.addChildNode(fringe)
    }

    private static let dayWater = waterTexture(night: false)
    private static let nightWater = waterTexture(night: true)
    private static let grass = texture { u, v in
        let patch = 0.42 * sin(3 * u + sin(4 * v)) * cos(4 * v + sin(3 * u))
            + 0.23 * sin(11 * u + 3 * sin(6 * v)) * cos(13 * v - 2 * sin(7 * u))
        let blades = 0.12 * sin(53 * u + 3 * sin(51 * v)) * sin(71 * v + 2 * sin(61 * u))
        let seed = pow(max(0, sin(79 * u + 17 * v) * sin(63 * v + 8 * u)), 9) * 0.57
        return SIMD3(129, 165, 68) + SIMD3(31, 29, 18) * (patch + blades + seed)
    }

    private static let stoneGrain = texture { u, v in
        let layers = sin(6 * v + 0.72 * sin(5 * u)) * 4.7 + cos(5 * u - 9 * v) * 4.0
        let grit = sin(39 * u + 51 * v) * cos(41 * v - 27 * u) * 7.0
        let pores = pow(max(0, sin(71 * u + 59 * v) * cos(51 * v + 47 * u)), 9) * 17
        return SIMD3(repeating: 244 + layers + grit - pores)
    }

    private static let woodGrain = texture { u, v in
        let fibers = sin(24 * v + 2.6 * sin(2 * u - v)) * 7.2 + cos(57 * v + 2 * u) * 3.2
        let streak = sin(5 * v + sin(3 * u + 2 * v)) * 5
        return SIMD3(245, 241, 230) + SIMD3(repeating: fibers + streak)
    }

    /// 周期网格内随机排列水纹单元，边界交汇形成细碎的透亮水花。
    private static func waterTexture(night: Bool) -> NSImage? {
        let base = night ? SIMD3<Double>(15, 57, 79) : SIMD3<Double>(18, 142, 164)
        let highlights = night ? SIMD3<Double>(25, 48, 53) : SIMD3<Double>(98, 72, 69)
        let cells = 8
        let count = Double(cells)
        /// 周期取样使纹理平铺边界沿用相同的种子，平移一块后仍连续。
        func seed(_ x: Int, _ y: Int, _ salt: Int) -> Double {
            let xx = (x % cells + cells) % cells
            let yy = (y % cells + cells) % cells
            var key = UInt32(xx * 439 + yy * 601 + salt * 347) &* 2_246_822_519
            key ^= key >> 15
            return Double(key & 1023) / 1023
        }
        return texture { u, v in
            let x = u * count / (2 * .pi) + 0.34 * sin(4 * v + u) + 0.13 * cos(7 * v - 2 * u)
            let y = v * count / (2 * .pi) + 0.31 * cos(4 * u - v) + 0.15 * sin(5 * u + 3 * v)
            let column = Int(floor(x))
            let row = Int(floor(y))
            var first = Double.infinity
            var second = Double.infinity
            for j in (row - 1)...(row + 1) {
                for i in (column - 1)...(column + 1) {
                    let dx = x - Double(i) - 0.14 - 0.72 * seed(i, j, 1)
                    let dy = y - Double(j) - 0.14 - 0.72 * seed(i, j, 2)
                    let distance = dx * dx + dy * dy
                    if distance < first {
                        second = first
                        first = distance
                    } else if distance < second {
                        second = distance
                    }
                }
            }
            let edge = pow(max(0, 1 - (sqrt(second) - sqrt(first)) * 7.8), 1.7)
            let swell = sin(3 * u + 2 * v + sin(u - 3 * v)) * 0.13
            let glint = pow(max(0, sin(23 * u + 11 * v) * sin(17 * v - 19 * u)), 22)
            return base * (1.05 + swell) + highlights * (edge * (0.33 + swell) + glint * 0.47)
        }
    }

    /// 周期取样保留首尾连续性，纹理缓存避免换工位时重新生成像素。
    private static func texture(_ colorAt: (Double, Double) -> SIMD3<Double>) -> NSImage? {
        let side = 192
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: side * 3, bitsPerPixel: 24),
              let bytes = bitmap.bitmapData else { return nil }
        let step = 2 * Double.pi / Double(side)
        for y in 0..<side {
            for x in 0..<side {
                let rgb = colorAt(Double(x) * step, Double(y) * step)
                let index = (y * side + x) * 3
                for channel in 0..<3 {
                    bytes[index + channel] = UInt8(max(0, min(255, rgb[channel].rounded())))
                }
            }
        }
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(bitmap)
        return image
    }

    /// 重复采样允许海面平移时保持相同的纹理密度，远处的细纹使用线性缩小。
    private func tile(_ texture: NSImage, on property: SCNMaterialProperty, repeats: CGFloat) {
        property.contents = texture
        property.wrapS = .repeat
        property.wrapT = .repeat
        property.mipFilter = .linear
        property.contentsTransform = SCNMatrix4MakeScale(repeats, repeats, 1)
    }

    /// 用圆角岸线容纳两侧的建筑和路线，形状随着前岸延伸而保留后岸的位置。
    private func coastline(end: CGFloat, margin: CGFloat) -> [CGPoint] {
        let center = (end + OfficeIslandLayout.back) / 2
        let radius = (end - OfficeIslandLayout.back) / 2
        return (0..<64).map { index in
            let a = 2 * CGFloat.pi * CGFloat(index) / 64
            let perturbation = 1 + 0.043 * sin(3 * a + 0.8) + 0.019 * cos(7 * a) + 0.012 * sin(11 * a - 0.6)
            let c = cos(a)
            let s = sin(a)
            return CGPoint(x: (10.03 + margin) * (c < 0 ? -1 : 1) * pow(abs(c), 0.58) * perturbation,
                           y: center + (radius + margin) * (s < 0 ? -1 : 1) * pow(abs(s), 0.60) * perturbation)
        }
    }

    /// 石板尺寸沿路线变化，保留自然边缘和稳定的步行宽度。
    private func pave(in parent: SCNNode, from start: CGPoint, to end: CGPoint) {
        let dx = end.x - start.x
        let dz = end.y - start.y
        let span = hypot(dx, dz)
        let count = max(1, Int(ceil(span / 0.76)))
        let hues = [0xE4CA9B, 0xD1B485, 0xECD2A4, 0xDDBE8D, 0xE8C596]
        let edges: [(CGFloat, CGFloat)] = [(-0.47, -0.23), (-0.22, -0.49), (0.36, -0.46),
                                          (0.50, -0.14), (0.42, 0.37), (-0.12, 0.51), (-0.50, 0.27)]
        let heading = atan2(dx, dz)
        for index in 0..<count {
            for side: CGFloat in [-1, 1] {
                let t = (CGFloat(index) + 0.52 + 0.16 * side) / CGFloat(count)
                let crossOffset = side * 0.36 + CGFloat(index % 3 - 1) * 0.078
                let x = start.x + dx * t + cos(heading) * crossOffset
                let z = start.y + dz * t - sin(heading) * crossOffset
                let width = 0.74 + CGFloat((index + Int(side) + 2) % 4) * 0.054
                let depth = max(0.50, span / CGFloat(count) - 0.018)
                let yaw = heading + CGFloat(index % 5 - 2) * 0.081 + side * 0.08
                let outline = edges.map { across, along in
                    CGPoint(x: x + across * width * cos(yaw) + along * depth * sin(yaw),
                            y: z - across * width * sin(yaw) + along * depth * cos(yaw))
                }
                let tint = hues[(index * 2 + (side > 0 ? 1 : 0)) % hues.count]
                let slab = layer(outline, depth: 0.077, y: 0.015 + CGFloat(index % 3) * 0.006,
                                 color: tint, in: parent, finish: .limestone)
                slab.castsShadow = false
            }
        }
    }

    /// 工坊采用厚石墙、暖木内饰和敞开的剖面，临主路的两条过道可通往实际工位。
    private func workshop(in parent: SCNNode, z: CGFloat) {
        let room = group("island-workshop", in: parent, at: SCNVector3(OfficeIslandLayout.workshopX, 0, z))
        box(8.02, 0.36, 6.31, stone, in: room, at: SCNVector3(0, -0.14, -0.12), bevel: 0.15, finish: .limestone)
        let planks = [0xCD9A5D, 0xD6A46B, 0xC39159, 0xCFA16A, 0xD9AE75]
        for index in 0..<18 {
            box(7.58, 0.042, 0.333, planks[(index * 3 + index / 4) % planks.count], in: room,
                at: SCNVector3(0, 0.027, -2.98 + CGFloat(index) * 0.333), bevel: 0.017, finish: .timber)
        }
        contactShadow(8.31, 4.85, in: room, at: SCNVector3(-0.12, 0.052, -1.68), opacity: 0.78)
        box(7.94, 3.04, 0.46, 0x95643D, in: room, at: SCNVector3(0, 1.50, -3.23), bevel: 0.10, finish: .timber)
        let interior = [0xA47146, 0xAA784A, 0x9E6C43, 0x98633D, 0xA6754D]
        for index in 0..<15 {
            box(0.49, 2.83, 0.074, interior[index % interior.count], in: room,
                at: SCNVector3(-3.54 + CGFloat(index) * 0.506, 1.52, -2.981), finish: .timber)
        }
        box(0.54, 2.94, 5.79, plaster, in: room, at: SCNVector3(-3.82, 1.45, -0.24), bevel: 0.22, finish: .limestone)
        box(7.60, 0.48, 0.43, plaster, in: room, at: SCNVector3(-0.04, 0.19, 2.89), bevel: 0.16, finish: .limestone)
        for (index, x) in [-3.54, -2.48, -1.39, -0.26, 0.88, 1.99, 3.12].enumerated() {
            box(1.03, 0.21, 0.46, index.isMultiple(of: 2) ? stone : 0xE2BE8C, in: room,
                at: SCNVector3(x, 0.032, 2.96), bevel: 0.075, finish: .limestone)
        }
        let side = group("island-workshop-side-window", in: room, at: SCNVector3(-4.095, 0, 1.48))
        side.eulerAngles.y = -.pi / 2
        window(in: side, x: 0, y: 1.45, z: 0.014)
        box(0.98, 0.25, 0.39, wood, in: side, at: SCNVector3(0, 0.87, 0.24), bevel: 0.06, finish: .timber)
        flowers(in: side, x: 0, z: 0.24, y: 1.0, scale: 0.74)
        masonry(in: side, at: SCNVector3(1.32, 0, 0.055), courses: 6)
        for index in 0..<12 {
            let y = 2.73 - CGFloat(index) * 0.118
            let x = -0.91 + 0.14 * sin(CGFloat(index) * 1.02)
            let leaf = oval(0.128, 0.187, 0.042, [0x658638, 0x72973F, 0x799646][index % 3], in: side,
                            at: SCNVector3(x + (index.isMultiple(of: 2) ? 0.074 : -0.067), y, 0.104))
            leaf.eulerAngles.z = index.isMultiple(of: 2) ? 0.61 : -0.53
        }
        for x: CGFloat in [-3.52, 0.02, 3.61] {
            box(0.24, 3.15, 0.24, darkWood, in: room, at: SCNVector3(x, 1.56, -2.94), finish: .timber)
        }
        let eaves = group("island-workshop-roof", in: room, at: SCNVector3(0, 0, -1.61))
        roof(in: eaves, width: 8.41, length: 3.08, eave: 3.04, rise: 1.42, colors: terracotta, openFront: true)
        for index in 0..<3 {
            box(0.62, 0.27, 0.59, index.isMultiple(of: 2) ? plaster : stone, in: room,
                at: SCNVector3(-2.34, 3.79 + CGFloat(index) * 0.27, -2.64), bevel: 0.065, finish: .limestone)
        }
        box(0.76, 0.17, 0.68, plaster, in: room, at: SCNVector3(-2.34, 4.47, -2.64), finish: .limestone)

        let porch = group("island-workshop-entry", in: room, at: SCNVector3(3.27, 0, 2.79))
        box(1.14, 2.38, 0.63, plaster, in: porch, at: SCNVector3(0, 1.13, 0), bevel: 0.16, finish: .limestone)
        roof(in: porch, width: 1.48, length: 0.94, eave: 2.31, rise: 0.42, colors: terracotta)
        door(in: porch, x: 0, z: 0.35, scale: 0.91)

        let cabinet = group("island-workshop-cabinet", in: room, at: SCNVector3(-2.46, 0, -3.02))
        box(1.02, 0.91, 0.44, darkWood, in: cabinet, at: SCNVector3(0, 0.45, 0), bevel: 0.062, finish: .timber)
        for y: CGFloat in [0.25, 0.48, 0.71] {
            box(0.88, 0.16, 0.083, wood, in: cabinet, at: SCNVector3(0, y, 0.225), finish: .timber)
            oval(0.035, 0.035, 0.030, 0xE5B55C, in: cabinet, at: SCNVector3(0, y, 0.276), finish: .copper)
        }
        let globe = node(SCNTorus(ringRadius: 0.23, pipeRadius: 0.024), 0xC99B49, in: cabinet,
                         at: SCNVector3(-0.09, 1.25, 0.014), finish: .copper)
        globe.eulerAngles = SCNVector3(1.33, 0, -0.21)
        oval(0.185, 0.187, 0.185, 0x548B8B, in: cabinet, at: SCNVector3(-0.09, 1.25, 0.013), finish: .ceramic)
        box(0.96, 0.69, 0.053, 0xE4BB77, in: room, at: SCNVector3(-1.59, 1.84, -2.88), finish: .limestone)
        for shelf: CGFloat in [1.12, 1.65, 2.18] {
            box(1.42, 0.092, 0.32, wood, in: room, at: SCNVector3(1.85, shelf, -2.87), finish: .timber)
            for index in 0..<7 {
                let height = 0.21 + CGFloat((index + Int(shelf * 5)) % 4) * 0.057
                box(0.136, height, 0.20, [0x719685, 0xB96C4D, 0xD3A150, 0xA98E61][index % 4], in: room,
                    at: SCNVector3(1.29 + CGFloat(index) * 0.178, shelf + 0.042 + height / 2, -2.84), bevel: 0.015)
            }
        }
        for x: CGFloat in [1.11, 2.59] {
            box(0.105, 1.56, 0.26, darkWood, in: room, at: SCNVector3(x, 1.65, -2.888), finish: .timber)
        }
        let lampStem = node(SCNCylinder(radius: 0.021, height: 0.64), darkWood, in: room,
                            at: SCNVector3(-1.24, 2.81, -1.08), finish: .copper)
        lampStem.castsShadow = false
        lantern(in: room, at: SCNVector3(-1.24, 2.02, -1.08), height: 0.51)
        warmLight(in: room, at: SCNVector3(-0.96, 2.40, -0.91), intensity: night ? 680 : 250, distance: 5.4)
        let crate = group("island-workshop-rope-crate", in: room, at: SCNVector3(-3.98, 0, 3.37))
        crate.eulerAngles.y = 0.16
        box(0.71, 0.59, 0.69, darkWood, in: crate, at: SCNVector3(0, 0.29, 0), bevel: 0.066, finish: .timber)
        for index in 0..<4 {
            box(0.166, 0.52, 0.061, wood, in: crate, at: SCNVector3(-0.26 + CGFloat(index) * 0.173, 0.29, 0.345), finish: .timber)
            node(SCNTorus(ringRadius: 0.226 - CGFloat(index) * 0.024, pipeRadius: 0.031), 0xD8B77E, in: crate,
                 at: SCNVector3(0.031, 0.62 + CGFloat(index) * 0.045, 0.013))
        }
    }

    /// 铜接收器与码头组成容易辨认的飞行终点，木板与立柱伸入水面。
    private func toolHut(in parent: SCNNode) {
        let hut = group("island-tool-station", in: parent, at: SCNVector3(6.35, 0, -0.92))
        contactShadow(5.33, 4.82, in: hut, at: SCNVector3(0.44, 0.008, -0.02), opacity: 0.78)
        box(3.52, 2.72, 3.08, plaster, in: hut, at: SCNVector3(0, 1.35, 0), bevel: 0.22, finish: .limestone)
        box(3.66, 0.27, 3.19, stone, in: hut, at: SCNVector3(0, 0.09, 0), bevel: 0.11, finish: .limestone)
        roof(in: hut, width: 3.94, length: 3.62, eave: 2.68, rise: 1.13, colors: blueTiles)
        masonry(in: hut, at: SCNVector3(-1.59, 0, 1.55), courses: 6)
        masonry(in: hut, at: SCNVector3(1.56, 0, 1.55), courses: 6)
        door(in: hut, x: 0.76, z: 1.55, scale: 0.95)
        window(in: hut, x: -0.73, y: 1.53, z: 1.56)
        let awning = group("island-tool-awning", in: hut, at: SCNVector3(0.76, 2.12, 1.91))
        awning.eulerAngles.x = 0.22
        for index in 0..<5 {
            box(0.267, 0.12, 0.83, index.isMultiple(of: 2) ? wood : 0xD09456, in: awning,
                at: SCNVector3(-0.54 + CGFloat(index) * 0.27, 0, 0), bevel: 0.045, finish: .timber)
        }
        for x: CGFloat in [0.22, 1.31] {
            box(0.13, 1.95, 0.13, darkWood, in: hut, at: SCNVector3(x, 1.0, 2.16), finish: .timber)
        }
        let side = group("island-tool-side-window", in: hut, at: SCNVector3(-1.78, 0, -0.15))
        side.eulerAngles.y = -.pi / 2
        window(in: side, x: 0, y: 1.53, z: 0)
        barrel(in: hut, at: SCNVector3(1.67, 0, 1.45), size: 0.73)
        lantern(in: hut, at: SCNVector3(-1.14, 1.84, 1.68), height: 0.42)

        let receiver = group("island-paper-plane-receiver", in: parent,
                             at: SCNVector3(OfficeIslandLayout.toolStation.x, 0, OfficeIslandLayout.toolStation.z))
        contactShadow(2.44, 2.12, in: receiver, at: SCNVector3(0.16, 0.009, -0.08), opacity: 0.80)
        node(SCNCylinder(radius: 0.85, height: 0.24), stone, in: receiver, at: SCNVector3(0, 0.12, 0), finish: .limestone)
        for tier in 0..<2 {
            for index in 0..<9 {
                let angle = CGFloat(index) * 2 * .pi / 9 + CGFloat(tier) * 0.34
                let block = box(0.46, 0.25, 0.28, index.isMultiple(of: 2) ? stone : 0xDEBD8B, in: receiver,
                                at: SCNVector3(cos(angle) * 0.70, 0.23 + CGFloat(tier) * 0.235, sin(angle) * 0.70),
                                bevel: 0.09, finish: .limestone)
                block.eulerAngles.y = -.pi / 2 - angle
            }
        }
        box(0.99, 0.39, 0.77, 0xA95B34, in: receiver, at: SCNVector3(0, 0.75, 0), bevel: 0.10, finish: .copper)
        box(0.79, 0.12, 0.62, 0xDB9A62, in: receiver, at: SCNVector3(0, 0.97, 0), finish: .copper)
        node(SCNCylinder(radius: 0.16, height: 0.48), 0xB87441, in: receiver, at: SCNVector3(0, 1.25, 0), finish: .copper)
        let dish = group("island-copper-dish", in: receiver, at: SCNVector3(0, 1.51, 0))
        dish.eulerAngles = SCNVector3(0.31, 0, 0.73)
        copperDish(in: dish)
        glow(oval(0.074, 0.075, 0.045, 0xA9E9AF, in: receiver, at: SCNVector3(0.25, 0.65, 0.37)),
             0x78CF92, strength: 0.55)

        let dock = group("island-dock", in: parent, at: SCNVector3(8.54, 0, 2.22))
        for index in 0..<11 {
            box(0.337, 0.16, 1.98, [wood, 0xC99055, 0xAC7043][index % 3], in: dock,
                at: SCNVector3(CGFloat(index) * 0.349, 0.012, 0), bevel: 0.040, finish: .timber)
        }
        for x: CGFloat in [0.18, 2.04, 3.56] {
            for z: CGFloat in [-0.82, 0.82] {
                node(SCNCylinder(radius: 0.154, height: 1.92), darkWood, in: dock, at: SCNVector3(x, -0.41, z), finish: .timber)
                for ring in 0..<3 {
                    node(SCNTorus(ringRadius: 0.135, pipeRadius: 0.027), 0xD9B482, in: dock,
                         at: SCNVector3(x, 0.29 + CGFloat(ring) * 0.047, z))
                }
            }
        }
        let supplies = group("island-dock-supplies", in: parent, at: SCNVector3(8.27, 0, 0.80))
        box(0.63, 0.49, 0.55, darkWood, in: supplies, at: SCNVector3(0, 0.25, 0), bevel: 0.048)
        for index in 0..<3 {
            box(0.17, 0.42, 0.059, wood, in: supplies,
                at: SCNVector3(-0.18 + CGFloat(index) * 0.18, 0.25, 0.27))
            node(SCNTorus(ringRadius: 0.18, pipeRadius: 0.035), 0xD7B787, in: supplies,
                 at: SCNVector3(0, 0.52 + CGFloat(index) * 0.042, -0.02))
        }
    }

    /// 旋转剖面生成真实的凹铜碟，反射方向随相机和灯光变化。
    private func copperDish(in parent: SCNNode) {
        let profile: [(CGFloat, CGFloat)] = [(0.024, 0), (0.20, 0.026), (0.40, 0.109), (0.57, 0.24), (0.68, 0.36)]
        let segments = 32
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for (ring, point) in profile.enumerated() {
            let before = profile[max(0, ring - 1)]
            let after = profile[min(profile.count - 1, ring + 1)]
            let slope = (after.1 - before.1) / (after.0 - before.0)
            let length = hypot(1, slope)
            for index in 0..<segments {
                let angle = CGFloat(index) * 2 * .pi / CGFloat(segments)
                let x = cos(angle)
                let z = sin(angle)
                vertices.append(SCNVector3(point.0 * x, point.1, point.0 * z))
                normals.append(SCNVector3(-x * slope / length, 1 / length, -z * slope / length))
                if ring < profile.count - 1 {
                    let a = Int32(ring * segments + index)
                    let b = Int32(ring * segments + (index + 1) % segments)
                    let step = Int32(segments)
                    indices += [a, b, a + step, b, b + step, a + step]
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let plate = node(geometry, 0xCF8252, in: parent, at: SCNVector3Zero, finish: .copper)
        if let finish = plate.geometry?.firstMaterial?.copy() as? SCNMaterial {
            finish.isDoubleSided = true
            plate.geometry?.materials = [finish]
        }
        node(SCNTorus(ringRadius: 0.676, pipeRadius: 0.049), 0xE2A369, in: parent,
             at: SCNVector3(0, 0.36, 0), finish: .copper)
        node(SCNCylinder(radius: 0.046, height: 0.69), 0xBA6E3E, in: parent,
             at: SCNVector3(0, 0.34, 0), finish: .copper)
        oval(0.116, 0.115, 0.116, 0xE4A35F, in: parent, at: SCNVector3(0, 0.70, 0), finish: .copper)
    }

    /// 长椅的座板高度与共用的坐姿相配，杯子摆在外侧给中间两个人留位置。
    private func bench(in parent: SCNNode, at point: CGPoint) {
        let bench = group("island-rest-bench", in: parent, at: SCNVector3(point.x, 0, point.y))
        contactShadow(2.87, 1.48, in: bench, at: SCNVector3(0.08, 0.009, -0.14), opacity: 0.70)
        for z: CGFloat in [-0.21, 0.00, 0.21] {
            box(2.39, 0.15, 0.21, wood, in: bench, at: SCNVector3(0, 0.54, z), bevel: 0.049, finish: .timber)
        }
        for x: CGFloat in [-1.00, 1.00] {
            box(0.21, 0.56, 0.54, darkWood, in: bench, at: SCNVector3(x, 0.28, 0), finish: .timber)
            box(0.17, 0.76, 0.19, darkWood, in: bench, at: SCNVector3(x, 0.76, -0.32), finish: .timber)
        }
        for y: CGFloat in [0.79, 1.02] {
            box(2.36, 0.18, 0.11, wood, in: bench, at: SCNVector3(0, y, -0.32), bevel: 0.052, finish: .timber)
        }
        box(0.45, 0.035, 0.66, 0x718FAE, in: bench, at: SCNVector3(-0.84, 0.632, -0.020), bevel: 0.02)
        box(0.45, 0.50, 0.025, 0x718FAE, in: bench, at: SCNVector3(-0.84, 0.865, -0.246), bevel: 0.020)
        for x: CGFloat in [-1.03, -0.66] {
            box(0.025, 0.50, 0.024, 0xE6D3A7, in: bench, at: SCNVector3(x, 0.865, -0.23))
        }
    }

    /// 陶杯可用于桌面道具或休息者手持，杯口保留咖啡色液面和圆环把手。
    func restCup(at position: SCNVector3 = SCNVector3Zero) -> SCNNode {
        let cup = SCNNode()
        cup.position = position
        node(SCNCone(topRadius: 0.092, bottomRadius: 0.073, height: 0.15), 0xEBD6B2, in: cup,
             at: SCNVector3(0, 0.075, 0), finish: .ceramic)
        oval(0.075, 0.006, 0.075, 0x966641, in: cup, at: SCNVector3(0, 0.148, 0))
        node(SCNTorus(ringRadius: 0.084, pipeRadius: 0.011), 0xF1D9B7, in: cup,
             at: SCNVector3(0, 0.150, 0), finish: .ceramic)
        let handle = node(SCNTorus(ringRadius: 0.052, pipeRadius: 0.015), 0xEBD6B2, in: cup,
                          at: SCNVector3(0.094, 0.08, 0), finish: .ceramic)
        handle.eulerAngles.x = .pi / 2
        return cup
    }

    /// 两段收腰木桶和铁箍提供圆形剪影，木盖略低于桶沿。
    private func barrel(in parent: SCNNode, at position: SCNVector3, size: CGFloat) {
        let barrel = group("island-barrel", in: parent, at: position)
        barrel.scale = SCNVector3(size, size, size)
        node(SCNCone(topRadius: 0.35, bottomRadius: 0.26, height: 0.36), wood, in: barrel,
             at: SCNVector3(0, 0.18, 0), finish: .timber)
        node(SCNCone(topRadius: 0.27, bottomRadius: 0.35, height: 0.38), wood, in: barrel,
             at: SCNVector3(0, 0.54, 0), finish: .timber)
        for (y, radius): (CGFloat, CGFloat) in [(0.12, 0.292), (0.33, 0.35), (0.60, 0.302), (0.725, 0.27)] {
            node(SCNTorus(ringRadius: radius, pipeRadius: 0.022), 0x6F6151, in: barrel,
                 at: SCNVector3(0, y, 0), finish: .copper)
        }
        node(SCNCylinder(radius: 0.26, height: 0.04), darkWood, in: barrel,
             at: SCNVector3(0, 0.71, 0), finish: .timber)
    }

    /// 短木栏只围住休息区背面，保留长椅正面的入座路径。
    private func fence(in parent: SCNNode, x: CGFloat, z: CGFloat) {
        for offset: CGFloat in [0, 1.14, 2.28] {
            box(0.14, 0.65, 0.16, darkWood, in: parent, at: SCNVector3(x + offset, 0.325, z), bevel: 0.046)
        }
        for height: CGFloat in [0.25, 0.47] {
            box(2.34, 0.084, 0.079, wood, in: parent, at: SCNVector3(x + 1.14, height, z - 0.026))
        }
    }

    /// 慢转的风车在没有会话时也给全景一点活动，随场景播放状态暂停。
    private func windmill(in parent: SCNNode) {
        let tower = group("island-windmill", in: parent, at: SCNVector3(0.45, 0, -5.29))
        node(SCNCylinder(radius: 0.96, height: 0.34), stone, in: tower,
             at: SCNVector3(0, 0.17, 0), finish: .limestone)
        for index in 0..<11 {
            let angle = CGFloat(index) * 2 * .pi / 11
            let block = box(0.42, 0.27, 0.22, index.isMultiple(of: 2) ? plaster : stone, in: tower,
                            at: SCNVector3(cos(angle) * 0.864, 0.217, sin(angle) * 0.864), bevel: 0.083, finish: .limestone)
            block.eulerAngles.y = -.pi / 2 - angle
        }
        node(SCNCone(topRadius: 0.54, bottomRadius: 0.79, height: 2.39), 0xA76D3E, in: tower,
             at: SCNVector3(0, 1.47, 0), finish: .timber)
        node(SCNCone(topRadius: 0.10, bottomRadius: 0.76, height: 0.82), darkWood, in: tower,
             at: SCNVector3(0, 2.91, 0), finish: .timber)
        door(in: tower, x: 0, z: 0.728, scale: 0.48)
        let rotor = group("island-windmill-sails", in: tower, at: SCNVector3(0, 2.61, 0.75))
        rotor.eulerAngles.z = 0.27
        for index in 0..<4 {
            let sail = group("island-sail", in: rotor)
            sail.eulerAngles.z = CGFloat(index) * .pi / 2
            box(0.12, 1.55, 0.13, darkWood, in: sail, at: SCNVector3(0, 0.79, 0), finish: .timber)
            box(0.49, 0.92, 0.079, 0xF0DBAC, in: sail, at: SCNVector3(0.12, 1.03, 0.057), bevel: 0.043)
            for y: CGFloat in [0.58, 1.00, 1.41] {
                box(0.50, 0.064, 0.094, wood, in: sail, at: SCNVector3(0.11, y, 0.112))
            }
        }
        oval(0.20, 0.20, 0.14, wood, in: rotor, at: SCNVector3(0, 0, 0.12))
        mergeStaticMeshes(in: rotor)
        rotor.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: -.pi * 2, duration: 16)), forKey: "island-breeze")
    }

    /// 斜屋面用叠瓦和圆脊瓦表现上釉陶土的体积。
    private func roof(in parent: SCNNode, width: CGFloat, length: CGFloat, eave: CGFloat, rise: CGFloat,
                      colors: [Int], openFront: Bool = false) {
        let half = width / 2
        let slope = hypot(half, rise)
        let rows = Int(ceil(slope / 0.64))
        let columns = Int(ceil(length / 0.58))
        for side: CGFloat in [-1, 1] {
            let panel = group("island-roof-slope", in: parent, at: SCNVector3(side * half / 2, eave + rise / 2, 0))
            panel.eulerAngles.z = -side * atan2(rise, half)
            box(slope, 0.21, length, darkWood, in: panel, at: SCNVector3Zero, bevel: 0.06, finish: .timber)
            for row in 0..<rows {
                for column in 0..<columns {
                    let step = slope / CGFloat(rows)
                    let pitch = length / CGFloat(columns)
                    let x = -slope / 2 + (CGFloat(row) + 0.5) * step
                    let z = -length / 2 + (CGFloat(column) + 0.5) * pitch
                    let geometry = SCNCapsule(capRadius: pitch * 0.493, height: max(pitch, step + 0.24))
                    geometry.radialSegmentCount = 10
                    geometry.capSegmentCount = 4
                    let tile = node(geometry, colors[(row * 3 + column) % colors.count], in: panel,
                                    at: SCNVector3(x, 0.15 + CGFloat((row + column) % 3) * 0.009, z), finish: .ceramic)
                    tile.scale = SCNVector3(0.73, 1, 1)
                    tile.eulerAngles.z = .pi / 2
                }
            }
        }
        let ridge = node(SCNCapsule(capRadius: 0.174, height: length + 0.28), colors[1], in: parent,
                         at: SCNVector3(0, eave + rise + 0.18, 0), finish: .ceramic)
        ridge.eulerAngles.x = .pi / 2
        let triangle = NSBezierPath()
        triangle.move(to: CGPoint(x: -half + 0.14, y: eave - 0.09))
        triangle.line(to: CGPoint(x: 0, y: eave + rise - 0.08))
        triangle.line(to: CGPoint(x: half - 0.14, y: eave - 0.09))
        triangle.close()
        if !openFront {
            node(SCNShape(path: triangle, extrusionDepth: 0.16), plaster, in: parent,
                 at: SCNVector3(0, 0, length / 2 - 0.14), finish: .limestone)
        }
        node(SCNShape(path: triangle, extrusionDepth: 0.16), openFront ? darkWood : plaster, in: parent,
             at: SCNVector3(0, 0, -length / 2 + 0.14), finish: openFront ? .timber : .limestone)
    }

    /// 夜景暖窗用自发光，仍保留窗框和十字木格以提供尺寸参照。
    private func window(in parent: SCNNode, x: CGFloat, y: CGFloat, z: CGFloat) {
        arch(width: 1.12, height: 1.18, depth: 0.16, tint: stone, finish: .limestone,
             in: parent, at: SCNVector3(x, y, z))
        arch(width: 0.91, height: 1.00, depth: 0.079, tint: darkWood, finish: .timber,
             in: parent, at: SCNVector3(x, y, z + 0.089))
        let pane = arch(width: 0.74, height: 0.83, depth: 0.028, tint: night ? 0xECA44F : 0x698B81,
                        finish: .ceramic, in: parent, at: SCNVector3(x, y, z + 0.137))
        glow(pane, night ? 0xFFC479 : 0x94C5BD, strength: night ? 0.86 : 0.13)
        box(0.066, 0.85, 0.065, wood, in: parent, at: SCNVector3(x, y, z + 0.159), finish: .timber)
        box(0.82, 0.073, 0.065, wood, in: parent, at: SCNVector3(x, y - 0.04, z + 0.161), finish: .timber)
        box(1.15, 0.13, 0.30, stone, in: parent, at: SCNVector3(x, y - 0.56, z + 0.112), bevel: 0.053, finish: .limestone)
    }

    /// 以同一拱线绘制木框、石套和玻璃，几何尺寸随建筑比例调整。
    @discardableResult
    private func arch(width: CGFloat, height: CGFloat, depth: CGFloat, tint: Int, finish: Finish,
                      in parent: SCNNode, at position: SCNVector3) -> SCNNode {
        let half = width / 2
        let path = NSBezierPath()
        path.move(to: CGPoint(x: -half, y: -height / 2))
        path.line(to: CGPoint(x: half, y: -height / 2))
        path.line(to: CGPoint(x: half, y: height / 2 - half))
        for step in 1...14 {
            let angle = CGFloat(step) * .pi / 14
            path.line(to: CGPoint(x: cos(angle) * half, y: height / 2 - half + sin(angle) * half))
        }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.chamferRadius = depth * 0.23
        return node(shape, tint, in: parent, at: position, finish: finish)
    }

    /// 拱门用不同长度的厚木板，横铁条和黄铜把手在小窗也有清楚的轮廓。
    private func door(in parent: SCNNode, x: CGFloat, z: CGFloat, scale: CGFloat) {
        let door = group("island-arched-door", in: parent, at: SCNVector3(x, 0, z))
        door.scale = SCNVector3(scale, scale, scale)
        arch(width: 1.16, height: 2.18, depth: 0.16, tint: stone, finish: .limestone,
             in: door, at: SCNVector3(0, 1.09, 0))
        arch(width: 0.91, height: 1.95, depth: 0.13, tint: darkWood, finish: .timber,
             in: door, at: SCNVector3(0, 0.976, 0.078))
        for index in 0..<5 {
            let x = -0.326 + CGFloat(index) * 0.163
            let height = 1.47 + sqrt(max(0, 0.37 * 0.37 - x * x))
            box(0.157, height, 0.071, index.isMultiple(of: 2) ? wood : 0xA96F3B, in: door,
                at: SCNVector3(x, height / 2 + 0.04, 0.135), bevel: 0.035, finish: .timber)
        }
        for y: CGFloat in [0.42, 1.36] {
            box(0.84, 0.097, 0.040, 0x705343, in: door, at: SCNVector3(0, y, 0.189), bevel: 0.018)
        }
        oval(0.061, 0.064, 0.038, 0xE5AB58, in: door, at: SCNVector3(0.25, 0.93, 0.209), finish: .copper)
    }

    /// 转角石的大小与色温略有变化，突出圆润灰泥墙的厚度。
    private func masonry(in parent: SCNNode, at point: SCNVector3, courses: Int) {
        let colors = [0xEAD0A2, 0xD9B984, 0xE5C592]
        for tier in 0..<courses {
            let offset = CGFloat(tier % 2) * 0.07
            box(0.37 + offset, 0.35, 0.16, colors[tier % colors.count], in: parent,
                at: SCNVector3(point.x - offset / 2, point.y + 0.20 + CGFloat(tier) * 0.398, point.z + 0.038),
                bevel: 0.070, finish: .limestone)
        }
    }

    /// 灯罩先提供可见的暖色玻璃，海边较高的路灯在夜间额外照亮周围。
    private func lantern(in parent: SCNNode, at position: SCNVector3, height: CGFloat) {
        let root = group("island-lantern", in: parent, at: position)
        let width = min(0.31, height * 0.42)
        let cap = width * 0.86
        node(SCNCylinder(radius: width * 0.16, height: height - width * 0.67), darkWood, in: root,
             at: SCNVector3(0, (height - width * 0.67) / 2, 0))
        let glass = box(width, cap, width, 0xF3C279, in: root, at: SCNVector3(0, height - cap / 2, 0), bevel: 0.047)
        glow(glass, 0xFFC366, strength: night ? 1.0 : 0.39)
        box(width * 1.19, 0.050, width * 1.19, darkWood, in: root, at: SCNVector3(0, height - cap, 0))
        node(SCNCone(topRadius: width * 0.18, bottomRadius: width * 0.80, height: width * 0.36), darkWood,
             in: root, at: SCNVector3(0, height + width * 0.15, 0))
        if night && height >= 0.68 { warmLight(in: root, at: SCNVector3(0, height, 0.14), intensity: 320, distance: 3.6) }
    }

    /// 少量衰减光源把暖色落到附近地面和墙上，避免夜景成为整体压暗的画面。
    private func warmLight(in parent: SCNNode, at position: SCNVector3, intensity: CGFloat, distance: CGFloat) {
        let light = SCNLight()
        light.type = .omni
        light.color = NSColor(officeHex: 0xFFC27D)
        light.intensity = intensity
        light.attenuationStartDistance = 0.27
        light.attenuationEndDistance = distance
        group("island-lamp-light", in: parent, at: position).light = light
    }

    private static let contactTexture = NSImage(size: NSSize(width: 96, height: 96), flipped: false) { rect in
        let gradient = NSGradient(starting: NSColor.black.withAlphaComponent(0.53), ending: NSColor.clear)
        gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
        return true
    }

    /// 接触阴影补足小窗里容易丢失的屋檐和木腿层次，使用同一张渐变贴图。
    private func contactShadow(_ width: CGFloat, _ depth: CGFloat, in parent: SCNNode,
                               at point: SCNVector3, opacity: CGFloat) {
        let plane = SCNPlane(width: width, height: depth)
        let finish = constant(0x171510)
        finish.diffuse.contents = Self.contactTexture
        finish.writesToDepthBuffer = false
        finish.blendMode = .alpha
        plane.materials = [finish]
        let shadow = SCNNode(geometry: plane)
        shadow.name = "island-contact-shade"
        shadow.position = point
        shadow.eulerAngles.x = -.pi / 2
        shadow.castsShadow = false
        shadow.opacity = opacity
        parent.addChildNode(shadow)
    }

    /// 多层圆润树冠留下剪影，枝叶的轻微摆动从树干顶端开始。
    private func tree(in parent: SCNNode, x: CGFloat, z: CGFloat, scale: CGFloat) {
        let root = group("island-tree", in: parent, at: SCNVector3(x, 0, z))
        root.scale = SCNVector3(scale, scale, scale)
        contactShadow(2.59, 2.28, in: root, at: SCNVector3(0.33, 0.008, -0.15), opacity: 0.81)
        node(SCNCone(topRadius: 0.17, bottomRadius: 0.34, height: 1.76), 0x956039, in: root,
             at: SCNVector3(0, 0.88, 0), finish: .timber)
        for index in 0..<5 {
            let angle = CGFloat(index) * 2 * .pi / 5
            let foot = oval(0.28, 0.135, 0.46, 0x9D6A3E, in: root,
                            at: SCNVector3(cos(angle) * 0.21, 0.081, sin(angle) * 0.21), finish: .timber)
            foot.eulerAngles.y = -.pi / 2 - angle
        }
        for side: CGFloat in [-1, 1] {
            let branch = node(SCNCapsule(capRadius: 0.10, height: 0.96), darkWood, in: root,
                              at: SCNVector3(side * 0.21, 1.25, 0.04))
            branch.eulerAngles.z = -side * 0.57
        }
        let crown = group("island-crown", in: root, at: SCNVector3(0, 1.49, 0))
        let canopy = SCNNode()
        let greens = [0x547B33, 0x72973B, 0x8AA845, 0x7D9B39, 0xA3B947, 0xB8C753]
        oval(1.14, 1.03, 1.05, greens[0], in: canopy, at: SCNVector3(0, 0.73, 0))
        for ring in 0..<5 {
            let count = [11, 13, 11, 8, 6][ring]
            for index in 0..<count {
                let angle = CGFloat(index) / CGFloat(count) * .pi * 2 + CGFloat(ring) * 0.47
                let reach: CGFloat = [0.98, 1.14, 1.03, 0.76, 0.42][ring]
                let y = 0.26 + CGFloat(ring) * 0.31 + CGFloat((index * 3) % 4) * 0.027
                let width = 0.29 + CGFloat(index % 4) * 0.021
                let tone = min(5, ring + (index % 3 == 0 ? 1 : 0))
                let leaf = oval(width, 0.195 + CGFloat(ring % 2) * 0.018, 0.51 - CGFloat(ring) * 0.031,
                                greens[tone], in: canopy, at: SCNVector3(cos(angle) * reach, y, sin(angle) * reach))
                leaf.eulerAngles = SCNVector3(0.45 + CGFloat(ring) * 0.06, .pi / 2 - angle, 0.10)
            }
        }
        crown.addChildNode(canopy.flattenedClone())
        let breeze = SCNAction.sequence([.rotateTo(x: 0.026, y: 0, z: -0.034, duration: 2.6),
                                         .rotateTo(x: -0.026, y: 0, z: 0.034, duration: 2.9)])
        crown.runAction(.repeatForever(breeze), forKey: "island-leaves")
    }

    /// 花草分布在路旁，留出连续的通路和点击人物所需的空地。
    private func flowers(in parent: SCNNode, x: CGFloat, z: CGFloat, y: CGFloat = 0, scale: CGFloat = 1) {
        let plant = group("island-flowers", in: parent, at: SCNVector3(x, y, z))
        plant.scale = SCNVector3(scale, scale, scale)
        for index in 0..<6 {
            let angle = CGFloat(index) * .pi / 3
            let leaf = oval(0.27, 0.082, 0.115, [0x6E963D, 0x89A84D, 0x558838][index % 3], in: plant,
                            at: SCNVector3(cos(angle) * 0.18, 0.095, sin(angle) * 0.18))
            leaf.eulerAngles = SCNVector3(0, -angle, 0.18)
        }
        for index in 0..<3 {
            let x = CGFloat(index - 1) * 0.21
            let y = 0.25 + CGFloat(index % 2) * 0.14
            let z = CGFloat(index % 2) * 0.19
            node(SCNCylinder(radius: 0.015, height: y), 0x57833C, in: plant, at: SCNVector3(x, y / 2, z))
            for petal in 0..<5 {
                let a = CGFloat(petal) * .pi * 2 / 5
                oval(0.058, 0.035, 0.058, 0xFFF0CB, in: plant,
                     at: SCNVector3(x + cos(a) * 0.076, y, z + sin(a) * 0.076))
            }
            oval(0.057, 0.042, 0.057, 0xE8AD43, in: plant, at: SCNVector3(x, y + 0.01, z))
        }
    }

    /// 低矮的叶团给岸边和长椅留出细节，座位与路线附近保持开阔。
    private func shrubs(in parent: SCNNode, x: CGFloat, z: CGFloat, size: CGFloat) {
        let greens = [0x577D31, 0x6E9234, 0x82A541, 0xA3B952]
        let root = group("island-shrubs", in: parent, at: SCNVector3(x, 0, z))
        oval(size * 0.67, size * 0.32, size * 0.56, greens[0], in: root, at: SCNVector3(0, size * 0.16, 0))
        for index in 0..<9 {
            let angle = CGFloat(index) * 2 * .pi / 9
            let leaf = oval(size * 0.18, size * 0.11, size * 0.36, greens[index % greens.count], in: root,
                            at: SCNVector3(cos(angle) * size * 0.32, size * (0.24 + CGFloat(index % 3) * 0.07),
                                           sin(angle) * size * 0.30))
            leaf.eulerAngles = SCNVector3(0.31 + CGFloat(index % 3) * 0.14, .pi / 2 - angle, 0.08)
        }
    }

    /// 头部沿用会话的稳定造型编号，独立于工位或当前工作状态。
    func characterHead(variation: Int, skin: Int) -> SCNNode {
        let root = SCNNode()
        let hair = [0x355956, 0x8F553A, 0x716A67, 0xB88342, 0x483B47, 0x563C34][variation]
        oval(0.291, 0.305, 0.265, skin, in: root, at: SCNVector3Zero)
        oval(0.298, 0.266, 0.260, hair, in: root, at: SCNVector3(0, 0.075, -0.063))
        for x: CGFloat in [-0.276, 0.276] {
            oval(0.073, 0.083, 0.064, skin, in: root, at: SCNVector3(x, -0.039, 0.005))
        }
        for x: CGFloat in [-0.102, 0.102] {
            oval(0.031, 0.047, 0.022, 0x262C2D, in: root, at: SCNVector3(x, -0.009, 0.244))
            oval(0.008, 0.011, 0.006, 0xFBF1DA, in: root, at: SCNVector3(x - 0.007, 0.007, 0.263))
        }
        oval(0.050, 0.039, 0.043, skin, in: root, at: SCNVector3(0, -0.059, 0.25))
        oval(0.039, 0.008, 0.011, 0x9F6053, in: root, at: SCNVector3(0, -0.122, 0.245))
        for index in 0..<4 {
            let lock = oval(0.085, 0.108, 0.094, hair, in: root,
                            at: SCNVector3(-0.18 + CGFloat(index) * 0.117, 0.184 + CGFloat(index % 3) * 0.017, 0.175))
            lock.eulerAngles.z = -0.44
        }
        switch variation {
        case 0:
            oval(0.123, 0.117, 0.111, hair, in: root, at: SCNVector3(-0.12, 0.313, -0.14))
            oval(0.062, 0.050, 0.054, 0xE8AC59, in: root, at: SCNVector3(-0.08, 0.287, -0.064))
        case 1:
            oval(0.386, 0.058, 0.356, 0xDAB26E, in: root, at: SCNVector3(0, 0.226, 0))
            oval(0.264, 0.143, 0.253, 0xE8C083, in: root, at: SCNVector3(0, 0.30, 0))
            oval(0.266, 0.033, 0.257, 0x456D87, in: root, at: SCNVector3(0, 0.253, 0))
        case 2:
            for x: CGFloat in [-0.107, 0.107] {
                let lens = node(SCNTorus(ringRadius: 0.068, pipeRadius: 0.010), 0x85674C, in: root,
                                at: SCNVector3(x, -0.013, 0.273))
                lens.eulerAngles.x = .pi / 2
            }
            box(0.074, 0.018, 0.018, 0x85674C, in: root, at: SCNVector3(0, -0.007, 0.28))
        case 3:
            let beret = oval(0.32, 0.10, 0.28, 0xAD574E, in: root, at: SCNVector3(-0.028, 0.291, -0.015))
            beret.eulerAngles.z = 0.22
            oval(0.042, 0.040, 0.043, 0xAD574E, in: root, at: SCNVector3(-0.068, 0.385, -0.016))
        case 4:
            for index in 0..<5 {
                oval(0.096, 0.108, 0.11, hair, in: root,
                     at: SCNVector3(-0.205 + CGFloat(index) * 0.101, 0.285 + CGFloat(index % 3) * 0.033, -0.051))
            }
        default:
            oval(0.304, 0.072, 0.271, 0x618C75, in: root, at: SCNVector3(0, 0.215, 0))
            oval(0.101, 0.053, 0.075, 0x618C75, in: root, at: SCNVector3(0.265, 0.183, -0.118))
        }
        mergeStaticMeshes(in: root)
        return root
    }

    /// 合并布景中的刚性网格，保留动画、灯、半透明阴影和会话点选所用的父节点。
    private func mergeStaticMeshes(in root: SCNNode) {
        let shadowed = SCNNode()
        let unshadowed = SCNNode()

        /// 跳过可动的整棵子树，把几何的变换转换到当前合并根节点的局部坐标。
        func collect(_ parent: SCNNode) {
            for child in parent.childNodes {
                guard child.actionKeys.isEmpty, child.constraints?.isEmpty != false,
                      !child.isHidden, child.opacity == 1, child.renderingOrder == 0 else { continue }
                if let geometry = child.geometry {
                    let mesh = SCNNode(geometry: geometry)
                    mesh.transform = child.convertTransform(SCNMatrix4Identity, to: root)
                    (child.castsShadow ? shadowed : unshadowed).addChildNode(mesh)
                    child.geometry = nil
                }
                collect(child)
                if child.name == nil && child.light == nil && child.childNodes.isEmpty {
                    child.removeFromParentNode()
                }
            }
        }

        collect(root)
        for (batch, castsShadow) in [(shadowed, true), (unshadowed, false)] where !batch.childNodes.isEmpty {
            let mesh = batch.flattenedClone()
            mesh.name = "island-scenery-mesh"
            mesh.castsShadow = castsShadow
            root.addChildNode(mesh)
        }
    }

    /// 基础组节点保留具名部件，便于验证画面和独立调整动画。
    private func group(_ name: String, in parent: SCNNode, at position: SCNVector3 = SCNVector3Zero) -> SCNNode {
        let group = SCNNode()
        group.name = name
        group.position = position
        parent.addChildNode(group)
        return group
    }

    /// 按颜色和表面质地共享材质，陶瓦、石材和木作各有自己的高光与细纹。
    private func paint(_ tint: Int, finish: Finish) -> SCNMaterial {
        let key = tint * 8 + finish.rawValue
        if let cached = paints[key] { return cached }
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(officeHex: tint)
        material.lightingModel = .blinn
        let gloss: CGFloat = finish == .copper ? 0.75 : finish == .ceramic ? 0.48 : 0.16
        material.specular.contents = NSColor(white: gloss, alpha: 1)
        material.shininess = finish == .copper ? 0.64 : finish == .ceramic ? 0.52 : 0.31
        if let grain = finish == .limestone ? Self.stoneGrain : finish == .timber ? Self.woodGrain : nil {
            tile(grain, on: material.multiply, repeats: finish == .limestone ? 1.4 : 1)
        }
        paints[key] = material
        return material
    }

    /// 重复物件使用同一材质实例，几何体保留自己的位置和朝向。
    @discardableResult
    private func node(_ geometry: SCNGeometry, _ tint: Int, in parent: SCNNode, at position: SCNVector3,
                      finish: Finish = .matte) -> SCNNode {
        geometry.materials = [paint(tint, finish: finish)]
        let result = SCNNode(geometry: geometry)
        result.position = position
        parent.addChildNode(result)
        return result
    }

    /// 木板和石墙采用受最短边限制的倒角，避免很薄的层板出现折面。
    @discardableResult
    private func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ tint: Int, in parent: SCNNode,
                     at position: SCNVector3, bevel: CGFloat = 0.037, finish: Finish = .matte) -> SCNNode {
        let geometry = SCNBox(width: w, height: h, length: d, chamferRadius: min(bevel, min(w, h, d) * 0.48))
        geometry.chamferSegmentCount = 3
        return node(geometry, tint, in: parent, at: position, finish: finish)
    }

    /// 压扁或拉长球体以统一黏土造型。重复的花瓣和小道具采用较低分段。
    @discardableResult
    private func oval(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ tint: Int, in parent: SCNNode,
                      at position: SCNVector3, finish: Finish = .matte) -> SCNNode {
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = max(x, y, z) > 0.2 ? 18 : 12
        let result = node(sphere, tint, in: parent, at: position, finish: finish)
        result.scale = SCNVector3(x, y, z)
        return result
    }

    /// 特效材质使用副本，窗灯和电脑亮起时不会把同色家具一起点亮。
    private func glow(_ node: SCNNode, _ tint: Int, strength: CGFloat) {
        guard let material = node.geometry?.firstMaterial?.copy() as? SCNMaterial else { return }
        material.emission.contents = NSColor(officeHex: tint)
        material.emission.intensity = strength
        node.geometry?.materials = [material]
    }

    /// 海水泡沫由一条窄网格沿岸生成，背面和正面都能从旋转视角看到。
    private func shoreRing(inner: [CGPoint], outer: [CGPoint], in parent: SCNNode) -> SCNNode {
        let vertices = zip(inner, outer).flatMap { a, b in [SCNVector3(a.x, -1.194, a.y), SCNVector3(b.x, -1.194, b.y)] }
        let indices = inner.indices.flatMap { index -> [Int32] in
            let a = Int32(index * 2)
            let b = Int32((index + 1) % inner.count * 2)
            return (index * 3 % 13 > 2) ? [a, a + 1, b, a + 1, b + 1, b] : []
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let material = constant(night ? 0x8EB5CB : 0xD6FCED)
        material.isDoubleSided = true
        geometry.materials = [material]
        let ring = SCNNode(geometry: geometry)
        ring.name = "island-shore-foam"
        ring.castsShadow = false
        parent.addChildNode(ring)
        return ring
    }

    /// 统一轮廓挤出不同高度的岸层，草皮压住岛壁的上沿。
    @discardableResult
    private func layer(_ outline: [CGPoint], depth: CGFloat, y: CGFloat, color: Int, in parent: SCNNode,
                       finish: Finish = .matte) -> SCNNode {
        let path = NSBezierPath()
        for (index, point) in outline.enumerated() {
            let mapped = CGPoint(x: point.x, y: -point.y)
            if index == 0 { path.move(to: mapped) } else { path.line(to: mapped) }
        }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.chamferRadius = depth * 0.21
        let result = node(shape, color, in: parent, at: SCNVector3(0, y, 0), finish: finish)
        result.eulerAngles.x = -.pi / 2
        return result
    }

    /// 水面和泡沫自己提供颜色，不受地形阴影覆盖。
    private func constant(_ tint: Int) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(officeHex: tint)
        material.lightingModel = .constant
        return material
    }
}
