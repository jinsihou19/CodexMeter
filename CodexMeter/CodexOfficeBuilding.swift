// 公司建筑、公共区和室外庭院的原生 SceneKit 几何；只消费外观和房间布局。
import AppKit
import SceneKit

/// 外墙的窗、立柱和上梁供镜头淡出，实体墙脚始终留在建筑边界上。法向量使用世界坐标的 X、Z 分量。
struct OfficeFacadeSide {
    let upper: SCNNode
    let normal: SIMD2<Float>
}

/// 统一绘制建筑外墙、共享隔断和室内家具。沙发、工位与机柜坐标供人物和纸飞机复用。
@MainActor
struct OfficeBuilding {
    let root: SCNNode
    let night: Bool

    private static let entranceEdge: CGFloat = -15.30
    static let wingCenter: CGFloat = 5.42
    static let wingHalfWidth: CGFloat = 4.60
    static let foundationOverhang: CGFloat = 0.8
    private static let facadeHalfWidth = wingCenter + wingHalfWidth
    private static let facadeThickness: CGFloat = 0.16
    private static let facadeHeight: CGFloat = 2.70
    private static let partitionThickness: CGFloat = 0.13
    private static let partitionHeight: CGFloat = 2.48
    private static let headerHeight: CGFloat = 0.17
    static let firstRoomStart: CGFloat = entranceEdge + 8.75
    static let defaultYardFront: CGFloat = entranceEdge - 5.45
    static let entrance = CGPoint(x: 0, y: entranceEdge - 2.10)
    static let toolStation = SCNVector3(7.84, 2.13, entranceEdge + 6.67)
    private static let sofaCushions: [CGFloat] = [0, -1.22, 1.22]
    private static let receptionSofaX: CGFloat = -5.74
    private static let receptionSofas: [(z: CGFloat, heading: CGFloat)] = [
        (entranceEdge + 1.50, 0), (entranceEdge + 6.62, .pi)
    ]
    static let indoorRestSeats = sofaCushions.count * receptionSofas.count

    var background: NSColor { NSColor(officeHex: night ? 0x111C27 : 0xD9E4DA) }
    private var trim: Int { night ? 0x293C4E : 0x516F68 }
    private var wood: Int { night ? 0x996E4C : 0xB7885F }
    private var paving: Int { night ? 0x48515F : 0xBDC5B8 }
    private var exteriorCladding: Int { night ? 0x364555 : 0x8D9F96 }
    private var interiorCladding: Int { night ? 0x708093 : 0xC2CDC5 }

    /// 休息编号先用前台两组沙发，满座后才去入口外。进出路线沿沙发正面通行。
    static func restDestination(for index: Int) -> OfficeDestination {
        if index < indoorRestSeats {
            let sofa = receptionSofas[index / sofaCushions.count]
            let x = receptionSofaX + sofaCushions[index % sofaCushions.count]
            let approach = sofa.z + 1.18 * cos(sofa.heading)
            return OfficeDestination(
                route: [CGPoint(x: 0, y: approach), CGPoint(x: x, y: approach), CGPoint(x: x, y: sofa.z)],
                heading: sofa.heading, seated: true, kind: .rest
            )
        }
        let outside = index - indoorRestSeats
        let side: CGFloat = outside.isMultiple(of: 2) ? -1 : 1
        let x = side * (2.45 + CGFloat((outside / 2) % 10) * 0.91)
        let z = entranceEdge - 3.10 - CGFloat(outside / 20) * 1.15
        return OfficeDestination(route: [CGPoint(x: 0, y: z), CGPoint(x: x, y: z)],
                                 heading: 0, seated: false, kind: .rest)
    }

    /// 铺设地基和绿化，并返回四个朝向的外墙上部。后墙随仍需通行的地基一起收拢。
    func site(front: CGFloat, officeEnd: CGFloat) -> [OfficeFacadeSide] {
        let yard = SCNNode()
        yard.name = "office-garden"
        root.addChildNode(yard)
        let back = officeEnd + 3.1
        let middle = (front + back) / 2
        box(yard, 29.1, 0.25, back - front, night ? 0x233F39 : 0x7EAA79, at: SCNVector3(0, -0.33, middle))
        box(yard, 29.16, 0.16, back - front + 0.05, night ? 0x1A302D : 0x577E5B, at: SCNVector3(0, -0.54, middle))
        let entranceEdge = Self.entranceEdge
        box(root, 20.72, 0.20, officeEnd - entranceEdge, night ? 0x454957 : 0xD7CBBA,
            at: SCNVector3(0, -0.10, (officeEnd + entranceEdge) / 2))
        box(root, 1.55, 0.02, officeEnd - entranceEdge, night ? 0x554E50 : 0xAD8F70,
            at: SCNVector3(0, 0.012, (officeEnd + entranceEdge) / 2))
        box(yard, 24.25, 0.15, entranceEdge - front - 0.4, paving,
            at: SCNVector3(0, -0.13, (front + entranceEdge + 0.4) / 2))
        box(yard, 24.24, 0.10, 1.6, paving, at: SCNVector3(0, -0.15, officeEnd + 0.91))
        box(yard, 3.35, 0.09, 2.5, night ? 0x677382 : 0xD7DFD3, at: SCNVector3(0, -0.073, entranceEdge - 0.87))
        for side: CGFloat in [-1, 1] {
            box(yard, 1.83, 0.10, back - front - 1.2, paving, at: SCNVector3(side * 11.27, -0.15, middle))
            for z in stride(from: front + 1.8, through: back - 1.2, by: 1.85) {
                box(yard, 1.82, 0.008, 0.028, night ? 0x3C4554 : 0xAAB9AA, at: SCNVector3(side * 11.27, -0.095, z))
            }
            for (index, z) in stride(from: entranceEdge - 1.8, through: back - 1.2, by: 5.1).enumerated() {
                let x = side * (index.isMultiple(of: 2) ? 13.27 : 13.53)
                tree(yard, x: x, z: z, size: index.isMultiple(of: 3) ? 1 : 0.84)
                shrub(yard, x: side * 12.72, z: z + 1.22, scale: 0.78)
                if index.isMultiple(of: 2) {
                    lampPost(yard, x: side * 10.68, z: z + 0.7)
                }
            }
            bench(yard, x: side * 5.18, z: entranceEdge - 1.62, width: 2.35, color: wood, facing: 0)
            box(yard, 2.05, 0.23, 0.75, trim, at: SCNVector3(side * 7.76, -0.01, entranceEdge - 0.84))
            for dx: CGFloat in [-0.58, 0, 0.58] {
                shrub(yard, x: side * 7.76 + dx, z: entranceEdge - 0.84, scale: 0.52)
            }
        }
        for x in stride(from: CGFloat(-9.6), through: 9.6, by: 2.4) {
            box(yard, 0.025, 0.008, entranceEdge - front - 0.43, night ? 0x363E4C : 0xA9B6AA,
                at: SCNVector3(x, -0.052, (front + entranceEdge + 0.4) / 2))
        }
        reception()
        return facade(endingAt: officeEnd - Self.foundationOverhang)
    }

    /// 外墙按整栋楼的边界绘制。转角处端墙抵住侧墙的内沿，入口只留一道通往前台的开口。
    private func facade(endingAt back: CGFloat) -> [OfficeFacadeSide] {
        let walls = SCNNode()
        walls.name = "office-facade"
        root.addChildNode(walls)
        let front = Self.entranceEdge
        let halfWidth = Self.facadeHalfWidth
        let halfThickness = Self.facadeThickness / 2
        let innerEdge = halfWidth - halfThickness
        let sides: [SIMD2<Float>] = [SIMD2(-1, 0), SIMD2(1, 0), SIMD2(0, -1), SIMD2(0, 1)]
        return sides.map { normal in
            let upper = SCNNode()
            upper.name = "office-facade-upper"
            walls.addChildNode(upper)
            if normal.x != 0 {
                glass(walls, from: front - halfThickness, to: back + halfThickness,
                      at: CGFloat(normal.x) * halfWidth, alongZ: true, sill: 0.58, upper: upper)
            } else if normal.y < 0 {
                glass(walls, from: -innerEdge, to: -1.7, at: front, alongZ: false, sill: 0.58, upper: upper)
                glass(walls, from: 1.7, to: innerEdge, at: front, alongZ: false, sill: 0.58, upper: upper)
                header(upper, length: 3.4, x: 0, z: front, alongZ: false, exterior: true)
            } else {
                glass(walls, from: -innerEdge, to: innerEdge, at: back, alongZ: false, sill: 0.58, upper: upper)
            }
            return OfficeFacadeSide(upper: upper, normal: normal)
        }
    }

    /// 每间房只生成靠入口的一道横向隔断。首排和前台共用这道墙，后排和相邻房间共用。
    func partition(x: CGFloat, z: CGFloat) {
        let halfWidth = Self.wingHalfWidth
        let inset = Self.facadeThickness / 2
        let start = x - halfWidth + (x < 0 ? inset : 0)
        let end = x + halfWidth - (x > 0 ? inset : 0)
        glass(root, from: start, to: end, at: z, alongZ: false, sill: 0.76)
    }

    /// 没有部门的翼位留作庭院，让在场部门减少时仍有完整的空间。
    func courtyard(x: CGFloat, z: CGFloat, depth: CGFloat) {
        let patio = SCNNode()
        patio.position = SCNVector3(x, 0, z)
        root.addChildNode(patio)
        box(patio, 8.75, 0.045, depth - 0.36, night ? 0x35504D : 0x90AE84, at: SCNVector3(0, 0.024, 0))
        box(patio, 5.8, 0.035, 3.1, paving, at: SCNVector3(0, 0.055, -0.12))
        bench(patio, x: 0, z: -1.17, width: 2.85, color: wood, facing: 0)
        table(patio, x: -0.1, z: 0.57, radius: 0.54, height: 0.69, color: wood)
        for xx: CGFloat in [-3.18, 3.18] {
            patio.addChildNode(officePlant(at: SCNVector3(xx, 0.05, -2.39)))
            box(patio, 1.35, 0.32, 1.08, trim, at: SCNVector3(xx, 0.19, 2.13))
            shrub(patio, x: xx - 0.28, z: 2.13, scale: 0.9)
            shrub(patio, x: xx + 0.34, z: 2.13, scale: 0.65)
        }
    }

    /// 工作区只生成朝走廊的玻璃门面。门牌向室内错开，避免与走廊对面的门牌相叠。
    func workroom(_ room: SCNNode, title: String, depth: CGFloat, innerSide: CGFloat, entranceOffset: CGFloat, tint: NSColor) {
        let width = Self.wingHalfWidth * 2
        box(room, width, 0.06, depth, night ? 0x454B62 : 0xE6DCCE, at: SCNVector3(0, 0.037, 0))
        let floor = officeNode(SCNPlane(width: width, height: depth), color: .white, at: SCNVector3(0, 0.070, 0))
        floor.eulerAngles.x = -.pi / 2
        floor.castsShadow = false
        if let material = floor.geometry?.firstMaterial {
            material.diffuse.contents = night ? Self.nightFloorTile : Self.dayFloorTile
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(width / 0.92, depth / 0.92, 1)
        }
        room.addChildNode(floor)
        let rug = tint.blended(withFraction: night ? 0.62 : 0.61, of: NSColor(officeHex: night ? 0x2E3849 : 0xE7E0D2)) ?? tint
        let carpet = officeNode(SCNBox(width: 7.0, height: 0.025, length: 5.2, chamferRadius: 0.015),
                                color: rug, at: SCNVector3(0, 0.077, -0.05))
        carpet.name = "office-room-rug"
        room.addChildNode(carpet)
        let innerX = innerSide * Self.wingHalfWidth
        let opening = entranceOffset - depth / 2
        let edgeInset = Self.partitionThickness / 2
        glass(room, from: -depth / 2 + edgeInset, to: opening - 0.75, at: innerX, alongZ: true)
        glass(room, from: opening + 0.75, to: depth / 2 - edgeInset, at: innerX, alongZ: true)
        header(room, length: 1.5, x: innerX, z: opening, alongZ: true)
        box(room, 0.62, 0.016, 1.43, night ? 0xA17C52 : 0xA78869, at: SCNVector3(innerX, 0.083, opening))
        sign(room, title: String(title.prefix(18)), at: SCNVector3(innerX - innerSide * 1.25, 2.66, opening),
             width: 2.65, tint: tint)
        room.addChildNode(officePlant(at: SCNVector3(-innerSide * 3.99, 0.05, 2.76)))
        bookcase(room, x: -innerSide * 3.38, z: -2.99, width: 1.34)
        fixture(room, x: 0, z: 0, height: 2.61, radius: 2.55)
    }

    /// 墙边补上办公用品。打印柜和白板避开桌组后方通道，饮水机贴在外墙一侧。
    func officeFurniture(in room: SCNNode, depth: CGFloat, innerSide: CGFloat) {
        let cabinetZ = -depth / 2 + 0.36
        let cabinetX = -innerSide * 0.18
        box(room, 2.24, 0.55, 0.44, night ? 0x777A7C : 0xB6BEB8, at: SCNVector3(cabinetX, 0.35, cabinetZ))
        box(room, 2.30, 0.063, 0.48, wood, at: SCNVector3(cabinetX, 0.65, cabinetZ))
        for offset: CGFloat in [-0.72, 0, 0.72] {
            let x = cabinetX + offset
            box(room, 0.66, 0.46, 0.027, night ? 0x9DA4A8 : 0xE0E4DB,
                at: SCNVector3(x, 0.355, cabinetZ + 0.232))
            box(room, 0.15, 0.023, 0.035, trim, at: SCNVector3(x, 0.46, cabinetZ + 0.257))
        }
        let printerX = cabinetX - innerSide * 0.67
        box(room, 0.52, 0.22, 0.36, 0xB9C5CF, at: SCNVector3(printerX, 0.79, cabinetZ))
        box(room, 0.36, 0.053, 0.03, 0x334557, at: SCNVector3(printerX, 0.80, cabinetZ + 0.185))
        box(room, 0.31, 0.015, 0.23, 0xE5E8E1, at: SCNVector3(printerX + 0.018, 0.911, cabinetZ + 0.024))
        box(room, 0.034, 0.017, 0.02, 0x82C9A3, at: SCNVector3(printerX + 0.197, 0.861, cabinetZ + 0.185))
        box(room, 0.37, 0.069, 0.25, 0x708AAB, at: SCNVector3(cabinetX + innerSide * 0.52, 0.72, cabinetZ + 0.03))
        box(room, 0.33, 0.039, 0.23, 0xDDDACD, at: SCNVector3(cabinetX + innerSide * 0.55, 0.77, cabinetZ + 0.025))

        let board = SCNNode()
        board.position = SCNVector3(innerSide * 2.50, 0, -depth / 2 + 0.54)
        room.addChildNode(board)
        box(board, 1.62, 0.91, 0.066, trim, at: SCNVector3(0, 1.31, 0))
        box(board, 1.50, 0.80, 0.025, 0xDAE4E1, at: SCNVector3(0, 1.31, 0.04))
        box(board, 1.57, 0.042, 0.12, 0x8398A9, at: SCNVector3(0, 0.85, 0.047))
        for x: CGFloat in [-0.62, 0.62] {
            box(board, 0.058, 0.93, 0.058, 0x7F919E, at: SCNVector3(x, 0.59, -0.015))
            box(board, 0.07, 0.047, 0.45, 0x7F919E, at: SCNVector3(x, 0.15, -0.014))
            for z: CGFloat in [-0.19, 0.16] {
                let wheel = officeNode(SCNCylinder(radius: 0.043, height: 0.045), color: NSColor(officeHex: trim),
                                       at: SCNVector3(x, 0.11, z))
                wheel.eulerAngles.z = .pi / 2
                board.addChildNode(wheel)
            }
        }
        for (index, color) in [0xC48A62, 0x769DB5, 0x85A998].enumerated() {
            box(board, 0.175, 0.15, 0.012, color, at: SCNVector3(-0.53 + CGFloat(index) * 0.25, 1.49, 0.057))
        }
        box(board, 0.73, 0.021, 0.012, 0x748DA2, at: SCNVector3(-0.19, 1.21, 0.057))
        box(board, 0.56, 0.021, 0.012, 0x9EAFAF, at: SCNVector3(-0.27, 1.08, 0.057))

        let coolerX = -innerSide * 4.10
        let coolerZ: CGFloat = -0.90
        box(room, 0.37, 0.98, 0.36, night ? 0xA8B8C7 : 0xD9E3E6, at: SCNVector3(coolerX, 0.56, coolerZ))
        box(room, 0.26, 0.24, 0.032, trim, at: SCNVector3(coolerX, 0.75, coolerZ + 0.184))
        box(room, 0.12, 0.041, 0.055, 0xCBD9E1, at: SCNVector3(coolerX, 0.813, coolerZ + 0.208))
        room.addChildNode(officeNode(SCNCylinder(radius: 0.14, height: 0.32), color: NSColor(officeHex: 0x5486BD),
                                     at: SCNVector3(coolerX, 1.25, coolerZ)))
        room.addChildNode(officeNode(SCNCylinder(radius: 0.074, height: 0.075), color: NSColor(officeHex: 0x8FB7DA),
                                     at: SCNVector3(coolerX, 1.065, coolerZ)))
    }

    /// 工位以桌面中心为原点，椅心仍在本地 Z=0.70。身份挂在根节点，点击桌面或脚轮都能选中同事。
    func workstation(for id: String, tint: NSColor) -> SCNNode {
        let desk = SCNNode()
        desk.name = "employee:" + id
        let frame = 0x485764
        let dark = 0x303D48
        box(desk, 2.15, 0.085, 1.05, night ? 0xC2A17D : 0xCFAD87, at: SCNVector3(0, 0.8575, 0))
        for x: CGFloat in [-0.95, 0.95] {
            box(desk, 0.075, 0.76, 0.72, frame, at: SCNVector3(x, 0.44, -0.035))
            box(desk, 0.092, 0.041, 0.75, dark, at: SCNVector3(x, 0.092, -0.035))
        }
        box(desk, 1.82, 0.18, 0.048, frame, at: SCNVector3(0, 0.71, -0.42))
        box(desk, 0.71, 0.064, 0.15, dark, at: SCNVector3(0, 0.773, -0.27))

        // 由会话 ID 固定单双屏，布局刷新时不会换设备。
        let hasSecondScreen = CodexOfficeEmployee.stableHash(id) % 3 == 0
        monitor(on: desk, x: hasSecondScreen ? -0.23 : 0, width: 0.91, height: 0.56)
        if hasSecondScreen {
            monitor(on: desk, x: 0.57, width: 0.62, height: 0.40, yaw: -0.29, chart: true)
        }

        box(desk, 0.69, 0.032, 0.23, 0xE1E8E8, at: SCNVector3(-0.12, 0.916, 0.19))
        for (row, length): (CGFloat, CGFloat) in [(0.123, 0.59), (0.169, 0.59), (0.215, 0.59), (0.259, 0.31)] {
            box(desk, length, 0.010, 0.029, 0xAEBCC5, at: SCNVector3(-0.12, 0.937, row)).castsShadow = false
        }
        box(desk, 0.24, 0.009, 0.25, dark, at: SCNVector3(0.43, 0.907, 0.22))
        box(desk, 0.112, 0.058, 0.163, 0xDDE3E3, at: SCNVector3(0.43, 0.94, 0.22))
        box(desk, 0.021, 0.010, 0.043, 0x8B9AA8, at: SCNVector3(0.43, 0.972, 0.183)).castsShadow = false

        let mugColor = tint.blended(withFraction: 0.24, of: .white) ?? tint
        desk.addChildNode(officeNode(SCNCylinder(radius: 0.066, height: 0.125), color: mugColor,
                                     at: SCNVector3(0.81, 0.963, 0.24)))
        desk.addChildNode(officeNode(SCNCylinder(radius: 0.053, height: 0.006), color: NSColor(officeHex: 0x594033),
                                     at: SCNVector3(0.81, 1.027, 0.24)))
        let handle = officeNode(SCNTorus(ringRadius: 0.044, pipeRadius: 0.010), color: mugColor,
                                at: SCNVector3(0.888, 0.966, 0.24))
        handle.eulerAngles.x = .pi / 2
        handle.castsShadow = false
        desk.addChildNode(handle)
        let notebook = box(desk, 0.24, 0.041, 0.29, 0x667F9E, at: SCNVector3(-0.69, 0.922, 0.19))
        notebook.eulerAngles.y = 0.17
        box(notebook, 0.20, 0.007, 0.248, 0xE4DDC7, at: SCNVector3(0.008, 0.022, 0.005)).castsShadow = false
        let pen = box(notebook, 0.023, 0.018, 0.175, dark, at: SCNVector3(0.044, 0.034, 0.03))
        pen.eulerAngles.y = -0.34
        pen.castsShadow = false

        let lampX: CGFloat = -0.81
        desk.addChildNode(officeNode(SCNCylinder(radius: 0.098, height: 0.029), color: NSColor(officeHex: dark),
                                     at: SCNVector3(lampX, 0.916, -0.27)))
        desk.addChildNode(officeNode(SCNCylinder(radius: 0.019, height: 0.31), color: NSColor(officeHex: frame),
                                     at: SCNVector3(lampX, 1.078, -0.27)))
        let shade = officeNode(SCNCone(topRadius: 0.040, bottomRadius: 0.106, height: 0.11),
                               color: NSColor(officeHex: 0xA77656), at: SCNVector3(lampX, 1.24, -0.24))
        shade.eulerAngles.x = -0.31
        desk.addChildNode(shade)
        let bulb = officeNode(SCNSphere(radius: 0.040), color: NSColor(officeHex: 0xFFD9A7),
                              at: SCNVector3(lampX, 1.192, -0.222))
        bulb.geometry?.firstMaterial?.lightingModel = .constant
        bulb.castsShadow = false
        desk.addChildNode(bulb)

        desk.addChildNode(Self.taskChair.clone())
        return desk
    }

    /// 显示器按底座、支臂和屏幕分层。第二块屏幕朝向键盘，贴图只展示示意内容。
    private func monitor(on desk: SCNNode, x: CGFloat, width: CGFloat, height: CGFloat, yaw: CGFloat = 0, chart: Bool = false) {
        let monitor = SCNNode()
        monitor.position = SCNVector3(x, 0.90, -0.265)
        monitor.eulerAngles.y = yaw
        desk.addChildNode(monitor)
        box(monitor, 0.30, 0.031, 0.22, 0x364552, at: SCNVector3(0, 0.019, 0.037))
        box(monitor, 0.068, 0.27, 0.060, 0x536575, at: SCNVector3(0, 0.166, -0.023))
        let centerY = 0.222 + height / 2
        box(monitor, width, height, 0.066, 0x27333E, at: SCNVector3(0, centerY, -0.025))
        let panel = officeNode(SCNPlane(width: width - 0.075, height: height - 0.076),
                               color: .white, at: SCNVector3(0, centerY + 0.010, 0.010))
        panel.geometry?.firstMaterial?.diffuse.contents = chart ? Self.chartScreen : Self.editorScreen
        panel.geometry?.firstMaterial?.lightingModel = .constant
        panel.castsShadow = false
        monitor.addChildNode(panel)
        let indicator = box(monitor, 0.025, 0.011, 0.007, 0x85C7AA,
                            at: SCNVector3(width / 2 - 0.062, 0.240, 0.011))
        indicator.geometry?.firstMaterial?.lightingModel = .constant
        indicator.castsShadow = false
    }

    /// 工位复用同一椅子模型。脚轮与地毯顶面相接，五星脚收在人物状态环的内侧。
    private static let taskChair: SCNNode = {
        let chair = SCNNode()
        chair.name = "office-task-chair"
        chair.position = SCNVector3(0, 0, 0.70)
        let furniture = OfficeBuilding(root: chair, night: false)
        let metal = 0x94A4B2
        let frame = 0x354652
        furniture.box(chair, 0.59, 0.084, 0.55, frame, at: SCNVector3(0, 0.438, 0))
        furniture.box(chair, 0.55, 0.079, 0.51, 0x637C91, at: SCNVector3(0, 0.4805, -0.017))
        let backrest = SCNNode()
        backrest.position = SCNVector3(0, 0.765, 0.275)
        backrest.eulerAngles.x = 0.11
        chair.addChildNode(backrest)
        furniture.box(backrest, 0.58, 0.54, 0.087, 0xA5B6C9, at: SCNVector3Zero)
        furniture.box(backrest, 0.52, 0.475, 0.078, 0x556D83, at: SCNVector3(0, 0.004, -0.042))
        furniture.box(chair, 0.11, 0.30, 0.067, frame, at: SCNVector3(0, 0.522, 0.263))
        for x: CGFloat in [-0.34, 0.34] {
            furniture.box(chair, 0.052, 0.189, 0.050, frame, at: SCNVector3(x, 0.548, 0.122))
            furniture.box(chair, 0.074, 0.040, 0.31, frame, at: SCNVector3(x, 0.650, 0.047))
        }
        furniture.box(chair, 0.23, 0.057, 0.22, frame, at: SCNVector3(0, 0.387, 0))
        chair.addChildNode(officeNode(SCNCylinder(radius: 0.039, height: 0.23), color: NSColor(officeHex: metal),
                                      at: SCNVector3(0, 0.277, 0)))
        chair.addChildNode(officeNode(SCNCylinder(radius: 0.068, height: 0.132), color: NSColor(officeHex: frame),
                                      at: SCNVector3(0, 0.190, 0)))
        for index in 0..<5 {
            let spoke = SCNNode()
            spoke.eulerAngles.y = CGFloat(index) * 2 * .pi / 5 + .pi / 5
            chair.addChildNode(spoke)
            furniture.box(spoke, 0.069, 0.043, 0.334, metal, at: SCNVector3(0, 0.177, 0.163))
            let wheelShape = SCNCylinder(radius: 0.053, height: 0.069)
            wheelShape.radialSegmentCount = 12
            let wheel = officeNode(wheelShape, color: NSColor(officeHex: 0x242D36), at: SCNVector3(0, 0.143, 0.326))
            wheel.name = "office-chair-caster"
            wheel.eulerAngles.z = .pi / 2
            spoke.addChildNode(wheel)
            let hub = officeNode(SCNCylinder(radius: 0.018, height: 0.075), color: NSColor(officeHex: metal),
                                 at: SCNVector3(0, 0.143, 0.326))
            hub.eulerAngles.z = .pi / 2
            hub.castsShadow = false
            spoke.addChildNode(hub)
        }
        return chair
    }()

    private static let editorScreen = screenImage(chart: false)
    private static let chartScreen = screenImage(chart: true)
    private static let nightFloorTile = tileImage(fill: 0x454B62, seam: 0x3B4256)
    private static let dayFloorTile = tileImage(fill: 0xE6DCCE, seam: 0xD4CBBC)

    /// 屏幕内容只绘制一次。代码色块和图表是装饰，实际会话内容仍由工作档案呈现。
    private static func screenImage(chart: Bool) -> NSImage {
        let size = NSSize(width: 288, height: 176)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(officeHex: chart ? 0xE4EDF3 : 0x17232D).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor(officeHex: chart ? 0x91AFCB : 0x354753).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 153, width: size.width, height: 23)).fill()
        if chart {
            NSColor(officeHex: 0xBCCDDC).setFill()
            for y in [33, 58, 83, 108] {
                NSBezierPath(rect: NSRect(x: 23, y: y, width: 240, height: 2)).fill()
            }
            let trend = NSBezierPath()
            trend.move(to: NSPoint(x: 23, y: 44))
            for (x, y) in [(64, 64), (105, 54), (145, 92), (188, 78), (224, 101), (262, 119)] {
                trend.line(to: NSPoint(x: x, y: y))
            }
            trend.lineWidth = 5
            NSColor(officeHex: 0x547EAB).setStroke()
            trend.stroke()
        } else {
            for (index, length) in [148, 91, 178, 114, 137, 74, 156].enumerated() {
                let color = [0x83ADC2, 0xA6C496, 0xD5AA87][index % 3]
                NSColor(officeHex: color).setFill()
                NSBezierPath(rect: NSRect(x: 21 + index % 3 * 13, y: 128 - index * 15, width: length, height: 5)).fill()
            }
        }
        image.unlockFocus()
        return image
    }

    /// 地面用可重复的细缝贴图，铺满不同大小的房间时只增加一个面。
    private static func tileImage(fill: Int, seam: Int) -> NSImage {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(officeHex: fill).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor(officeHex: seam).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: size.width, height: 1.5)).fill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1.5, height: size.height)).fill()
        image.unlockFocus()
        return image
    }

    /// 前台占入口后的整段空间，左侧为沙发区，右侧安排柜台和工具间，中间直通办公室。
    private func reception() {
        let front = Self.entranceEdge
        let reception = SCNNode()
        reception.name = "office-reception"
        root.addChildNode(reception)
        let back = Self.firstRoomStart
        box(reception, Self.facadeHalfWidth * 2, 0.05, back - front, night ? 0x39485A : 0xC8D2CF,
            at: SCNVector3(0, 0.024, (back + front) / 2))
        box(reception, 3.16, 0.023, 1.67, night ? 0x35495B : 0x718B7D, at: SCNVector3(0, 0.055, front + 1.01))
        for side: CGFloat in [-1, 1] {
            reception.addChildNode(officePlant(at: SCNVector3(side * 1.62, 0, front + 0.75)))
        }
        sign(reception, title: "CODEX & CO.", at: SCNVector3(0, 2.92, front + 0.20),
             width: 4.18, tint: NSColor(officeHex: 0x527B71))
        fixture(reception, x: 0, z: front + 0.03, height: 2.1, radius: 2.2)

        let sofaX = Self.receptionSofaX
        let tableZ = front + 4.06
        box(reception, 6.35, 0.025, 7.0, night ? 0x334D68 : 0x9BB5C6,
            at: SCNVector3(sofaX, 0.054, tableZ))
        for seat in Self.receptionSofas {
            sofa(reception, x: sofaX, z: seat.z, heading: seat.heading, color: night ? 0x52889C : 0x4F8795)
        }
        table(reception, x: sofaX, z: tableZ, radius: 0.66, height: 0.44, color: wood)
        box(reception, 0.28, 0.035, 0.22, 0xD5B374, at: SCNVector3(sofaX - 0.12, 0.50, tableZ))
        fixture(reception, x: sofaX, z: tableZ, height: 2.64, radius: 3.15, illuminate: true)
        bookcase(reception, x: -8.75, z: front + 0.75, width: 1.45)
        reception.addChildNode(officePlant(at: SCNVector3(-8.77, 0, front + 6.87)))

        let counterZ = front + 1.78
        box(reception, 4.36, 0.89, 0.93, night ? 0x8E8273 : 0xD4C5B1, at: SCNVector3(5.64, 0.50, counterZ))
        box(reception, 4.48, 0.12, 1.02, wood, at: SCNVector3(5.64, 1.0, counterZ))
        box(reception, 4.16, 0.07, 0.025, 0x71978F, at: SCNVector3(5.64, 0.76, counterZ - 0.47))
        box(reception, 0.17, 0.22, 0.10, trim, at: SCNVector3(5.8, 1.17, counterZ + 0.10))
        box(reception, 0.64, 0.41, 0.07, trim, at: SCNVector3(5.8, 1.43, counterZ + 0.10))
        reception.addChildNode(officePlant(at: SCNVector3(8.77, 0, counterZ)))
        tools(in: reception)
    }

    /// 空出的基础房间可以做会议室。家具以房间中心定位，左右翼复用同一种布置。
    func meeting(in room: SCNNode) {
        box(room, 4.24, 0.13, 1.53, wood, at: SCNVector3(0, 0.84, 0))
        for x: CGFloat in [-1.53, 1.53] {
            box(room, 0.14, 0.82, 1.12, trim, at: SCNVector3(x, 0.42, 0))
        }
        let chairColor = night ? 0x667B91 : 0x7B93A3
        for x: CGFloat in [-1.44, 0, 1.44] {
            chair(room, x: x, z: -1.09, heading: 0, color: chairColor)
            chair(room, x: x, z: 1.09, heading: .pi, color: chairColor)
        }
        box(room, 2.6, 1.31, 0.09, trim, at: SCNVector3(0, 1.47, -3.47))
        box(room, 2.42, 1.14, 0.04, night ? 0xAEBCC1 : 0xEBECDD, at: SCNVector3(0, 1.47, -3.41))
        for (row, width): (CGFloat, CGFloat) in [(1.65, 1.36), (1.38, 1.74), (1.13, 0.94)] {
            box(room, width, 0.038, 0.018, 0x627E97, at: SCNVector3(-0.14, row, -3.38))
        }
    }

    /// 没有工位时，第一间房用球桌与长椅形成活动区。
    func games(in room: SCNNode) {
        bench(room, x: 0, z: -2.53, width: 3.38, color: night ? 0x756089 : 0x917DA6, facing: 0)
        box(room, 3.12, 0.10, 1.57, night ? 0x45786E : 0x579B82, at: SCNVector3(0, 0.79, 0))
        for dx: CGFloat in [-1.16, 1.16] {
            for dz: CGFloat in [-0.53, 0.53] {
                box(room, 0.075, 0.76, 0.075, trim, at: SCNVector3(dx, 0.39, dz))
            }
        }
        box(room, 3.01, 0.016, 0.035, 0xCFDDD0, at: SCNVector3(0, 0.848, 0))
        box(room, 0.035, 0.18, 1.59, 0x9EACB4, at: SCNVector3(0, 0.94, 0))
        for dx: CGFloat in [-0.86, 0.99] {
            room.addChildNode(officeNode(SCNCylinder(radius: 0.13, height: 0.035),
                                         color: NSColor(officeHex: dx < 0 ? 0xDC896E : 0x637BA8),
                                         at: SCNVector3(dx, 0.865, 0.26)))
        }
    }

    /// 工具间复用建筑侧墙和首排隔断，只绘制余下两边。机柜上方是纸飞机的收发点。
    private func tools(in reception: SCNNode) {
        let room = SCNNode()
        room.name = "office-tool-room"
        reception.addChildNode(room)
        let front = Self.entranceEdge + 3.48
        let back = Self.firstRoomStart
        let inner: CGFloat = 2.65
        let outer = Self.facadeHalfWidth
        let middle = (front + back) / 2
        box(room, outer - inner, 0.035, back - front, night ? 0x3E5761 : 0xA4BEB9,
            at: SCNVector3((inner + outer) / 2, 0.061, middle))
        let inset = Self.partitionThickness / 2
        glass(room, from: inner - inset, to: outer - Self.facadeThickness / 2, at: front, alongZ: false)
        glass(room, from: front + inset, to: middle - 0.84, at: inner, alongZ: true)
        glass(room, from: middle + 0.84, to: back - inset, at: inner, alongZ: true)
        header(room, length: 1.68, x: inner, z: middle, alongZ: true)
        sign(room, title: officeText("工具间", "TOOLS"), at: SCNVector3(inner, 2.66, middle),
             width: 2.10, tint: NSColor(officeHex: 0x538DAB))

        let p = Self.toolStation
        for x in [p.x, p.x + 1.04] {
            box(room, 0.85, 1.68, 0.77, trim, at: SCNVector3(x, 0.90, p.z))
            for y: CGFloat in [0.55, 0.81, 1.07, 1.33, 1.55] {
                box(room, 0.69, 0.14, 0.035, 0x526C7D, at: SCNVector3(x, y, p.z + 0.39))
                let led = box(room, 0.08, 0.036, 0.04, 0x8EDCC5, at: SCNVector3(x + 0.21, y, p.z + 0.42))
                led.geometry?.firstMaterial?.lightingModel = .constant
            }
        }
        let benchZ = back - 0.64
        box(room, 2.82, 0.78, 0.70, trim, at: SCNVector3(4.84, 0.48, benchZ))
        box(room, 3.02, 0.10, 0.84, wood, at: SCNVector3(4.84, 0.92, benchZ))
        box(room, 0.81, 0.32, 0.39, 0xA96B56, at: SCNVector3(4.10, 1.13, benchZ))
        box(room, 0.48, 0.14, 0.29, 0x88A8B5, at: SCNVector3(5.77, 1.05, benchZ))
        fixture(room, x: 6.34, z: middle, height: 2.53, radius: 2.65, illuminate: true)
    }

    /// 墙脚固定在楼层上。外墙的玻璃、立柱和上梁可独立淡出，单层玻璃避免透明面叠色。
    private func glass(_ parent: SCNNode, from start: CGFloat, to end: CGFloat, at fixed: CGFloat,
                       alongZ: Bool, sill: CGFloat = 0.26, upper: SCNNode? = nil) {
        let length = end - start
        guard length > 0 else { return }
        let exterior = upper != nil
        let thickness = exterior ? Self.facadeThickness : Self.partitionThickness
        let height = exterior ? Self.facadeHeight : Self.partitionHeight
        let mid = (start + end) / 2
        let width = alongZ ? thickness : length
        let depth = alongZ ? length : thickness
        let x = alongZ ? fixed : mid
        let z = alongZ ? mid : fixed
        let cladding = exterior ? exteriorCladding : interiorCladding
        let base = box(parent, width, sill, depth, cladding, at: SCNVector3(x, sill / 2, z))
        base.name = "office-wall-sill"
        let cap: CGFloat = 0.044
        box(parent, width, cap, depth, exterior || sill > 0.5 ? wood : trim,
            at: SCNVector3(x, sill + cap / 2, z))

        let panel = upper ?? parent
        let glassHeight = height - Self.headerHeight - sill - cap
        let glassY = sill + cap + glassHeight / 2
        let glassTint = NSColor(officeHex: night ? 0x789BB8 : 0x9EC1CA)
            .withAlphaComponent(exterior ? 0.24 : 0.16)
        let pane = officeNode(SCNPlane(width: length, height: glassHeight), color: glassTint,
                              at: SCNVector3(x, glassY, z))
        if alongZ { pane.eulerAngles.y = .pi / 2 }
        pane.castsShadow = false
        pane.geometry?.firstMaterial?.writesToDepthBuffer = false
        pane.geometry?.firstMaterial?.isDoubleSided = true
        pane.geometry?.firstMaterial?.lightingModel = .constant
        panel.addChildNode(pane)

        let sections = max(1, Int((length / (exterior ? 2.05 : 1.58)).rounded()))
        let postWidth = min(length / 2, exterior ? 0.11 : 0.068)
        for i in 0...sections {
            let p = start + postWidth / 2 + (length - postWidth) * CGFloat(i) / CGFloat(sections)
            let post = box(panel, alongZ ? thickness : postWidth, glassHeight, alongZ ? postWidth : thickness,
                           trim, at: SCNVector3(alongZ ? fixed : p, glassY, alongZ ? p : fixed))
            if exterior { post.castsShadow = false }
        }
        header(panel, length: length, x: x, z: z, alongZ: alongZ, exterior: exterior)
    }

    /// 门洞和相邻玻璃共用同高的上梁，入口宽度保持实际通行尺寸。
    private func header(_ parent: SCNNode, length: CGFloat, x: CGFloat, z: CGFloat, alongZ: Bool, exterior: Bool = false) {
        let height = exterior ? Self.facadeHeight : Self.partitionHeight
        let thickness = exterior ? Self.facadeThickness : Self.partitionThickness
        let beam = box(parent, alongZ ? thickness : length, Self.headerHeight, alongZ ? length : thickness,
                       exterior ? exteriorCladding : interiorCladding,
                       at: SCNVector3(x, height - Self.headerHeight / 2, z))
        if exterior { beam.castsShadow = false }
    }

    /// 室外树冠由共享形状组成，颜色在同一主题内有层次。
    private func tree(_ parent: SCNNode, x: CGFloat, z: CGFloat, size: CGFloat) {
        let trunk = officeNode(SCNCylinder(radius: size * 0.13, height: size * 2.17), color: NSColor(officeHex: 0x806247),
                               at: SCNVector3(x, size * 1.04 - 0.12, z))
        parent.addChildNode(trunk)
        for (offset, height, radius, tint): (CGFloat, CGFloat, CGFloat, Int) in [
            (-0.36, 2.25, 0.93, night ? 0x305B50 : 0x5C996F),
            (0.42, 2.52, 0.78, night ? 0x407463 : 0x76AB76),
            (-0.12, 3.06, 0.72, night ? 0x4A7F6D : 0x8FB881)
        ] {
            parent.addChildNode(officeNode(SCNSphere(radius: radius * size), color: NSColor(officeHex: tint),
                                           at: SCNVector3(x + offset * size, height * size - 0.11, z + offset * 0.38)))
        }
    }

    /// 草坪和种植槽共用低矮灌木，不在主路径中央放障碍。
    private func shrub(_ parent: SCNNode, x: CGFloat, z: CGFloat, scale: CGFloat) {
        let node = officeNode(SCNSphere(radius: 0.42 * scale), color: NSColor(officeHex: night ? 0x426B56 : 0x73A471),
                              at: SCNVector3(x, 0.17 * scale, z))
        node.scale = SCNVector3(1.12, 0.84, 0.87)
        parent.addChildNode(node)
    }

    /// 路灯在夜间投射低成本的地面光晕，白天只保留灯具。
    private func lampPost(_ parent: SCNNode, x: CGFloat, z: CGFloat) {
        box(parent, 0.21, 0.21, 0.21, trim, at: SCNVector3(x, 0, z))
        parent.addChildNode(officeNode(SCNCylinder(radius: 0.052, height: 2.06), color: NSColor(officeHex: trim),
                                       at: SCNVector3(x, 0.98, z)))
        fixture(parent, x: x, z: z, height: 2.12, radius: 1.78, groundHeight: -0.088)
    }

    /// 吊灯和街灯使用发光灯芯与软边地面贴图，只有重点公共区启用局部光源。
    private func fixture(_ parent: SCNNode, x: CGFloat, z: CGFloat, height: CGFloat, radius: CGFloat,
                         groundHeight: CGFloat = 0.10, illuminate: Bool = false) {
        let shade = officeNode(SCNCone(topRadius: 0.12, bottomRadius: 0.29, height: 0.24),
                               color: NSColor(officeHex: night ? 0x607080 : 0xB48E68), at: SCNVector3(x, height + 0.11, z))
        shade.castsShadow = false
        parent.addChildNode(shade)
        let bulb = officeNode(SCNSphere(radius: 0.129), color: NSColor(officeHex: night ? 0xFFDF9E : 0xF1E2CA),
                              at: SCNVector3(x, height - 0.018, z))
        bulb.castsShadow = false
        bulb.geometry?.firstMaterial?.lightingModel = .constant
        parent.addChildNode(bulb)
        guard night else { return }
        let halo = SCNPlane(width: radius * 2, height: radius * 2)
        halo.firstMaterial?.diffuse.contents = Self.glowTexture
        halo.firstMaterial?.lightingModel = .constant
        halo.firstMaterial?.blendMode = .add
        halo.firstMaterial?.writesToDepthBuffer = false
        let glow = SCNNode(geometry: halo)
        glow.eulerAngles.x = -.pi / 2
        glow.position = SCNVector3(x, groundHeight, z)
        glow.castsShadow = false
        parent.addChildNode(glow)
        let bloom = SCNPlane(width: 0.78, height: 0.78)
        bloom.firstMaterial = halo.firstMaterial
        let shine = SCNNode(geometry: bloom)
        shine.position = bulb.position
        shine.castsShadow = false
        shine.constraints = [SCNBillboardConstraint()]
        parent.addChildNode(shine)
        if illuminate {
            let light = SCNLight()
            light.type = .omni
            light.color = NSColor(officeHex: 0xFFD7AA)
            light.intensity = 315
            light.attenuationStartDistance = 0.75
            light.attenuationEndDistance = 5.8
            bulb.light = light
        }
    }

    /// 一张纹理重复用于各盏灯，避免逐帧生成灯光贴图。
    private static let glowTexture: NSImage = {
        let size = NSSize(width: 144, height: 144)
        let image = NSImage(size: size)
        image.lockFocus()
        let warm = NSColor(officeHex: 0xFFD591)
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        NSGradient(colors: [warm.withAlphaComponent(0.34), warm.withAlphaComponent(0.095), warm.withAlphaComponent(0)])?
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: size.width / 2,
                  options: [.drawsAfterEndingLocation])
        image.unlockFocus()
        return image
    }()

    /// 长椅与沙发复用贴合人物坐高的靠背和座面。
    private func bench(_ parent: SCNNode, x: CGFloat, z: CGFloat, width: CGFloat, color: Int, facing: CGFloat) {
        let seat = SCNNode()
        seat.position = SCNVector3(x, 0, z)
        seat.eulerAngles.y = facing
        parent.addChildNode(seat)
        box(seat, width, 0.12, 0.64, color, at: SCNVector3(0, 0.44, 0))
        box(seat, width, 0.45, 0.10, color, at: SCNVector3(0, 0.67, -0.33))
        for leg in [-width * 0.39, width * 0.39] {
            box(seat, 0.11, 0.42, 0.50, trim, at: SCNVector3(leg, 0.20, 0))
        }
    }

    /// 沙发在本地坐标布置靠垫和扶手，旋转后仍与前台坐席的方向对齐。
    private func sofa(_ parent: SCNNode, x: CGFloat, z: CGFloat, heading: CGFloat, color: Int) {
        let couch = SCNNode()
        couch.name = "office-sofa"
        couch.position = SCNVector3(x, 0, z)
        couch.eulerAngles.y = heading
        parent.addChildNode(couch)
        box(couch, 3.96, 0.35, 0.93, color, at: SCNVector3(0, 0.26, 0))
        for cushion in Self.sofaCushions {
            box(couch, 1.15, 0.12, 0.78, color, at: SCNVector3(cushion, 0.45, 0.04))
            box(couch, 1.16, 0.53, 0.24, color, at: SCNVector3(cushion, 0.71, -0.41))
        }
        for side: CGFloat in [-1, 1] {
            box(couch, 0.28, 0.54, 0.94, color, at: SCNVector3(side * 1.91, 0.48, 0))
        }
    }

    /// 单椅用长椅的相同结构，便于统一调整视感。
    private func chair(_ parent: SCNNode, x: CGFloat, z: CGFloat, heading: CGFloat, color: Int) {
        bench(parent, x: x, z: z, width: 0.61, color: color, facing: heading)
    }

    /// 圆形桌面和吧凳都采用窄底座，给椅子周边留出通行空间。
    private func table(_ parent: SCNNode, x: CGFloat, z: CGFloat, radius: CGFloat, height: CGFloat, color: Int) {
        parent.addChildNode(officeNode(SCNCylinder(radius: 0.06, height: height), color: NSColor(officeHex: trim),
                                       at: SCNVector3(x, height / 2, z)))
        parent.addChildNode(officeNode(SCNCylinder(radius: radius * 0.72, height: 0.055), color: NSColor(officeHex: trim),
                                       at: SCNVector3(x, 0.051, z)))
        parent.addChildNode(officeNode(SCNCylinder(radius: radius, height: 0.09), color: NSColor(officeHex: color),
                                       at: SCNVector3(x, height, z)))
    }

    /// 低书柜填补墙角，书脊颜色固定，主题切换时布局一致。
    private func bookcase(_ parent: SCNNode, x: CGFloat, z: CGFloat, width: CGFloat) {
        box(parent, width, 1.55, 0.36, wood, at: SCNVector3(x, 0.81, z))
        for (row, y) in [CGFloat(0.44), 0.87, 1.30].enumerated() {
            box(parent, width - 0.11, 0.34, 0.035, trim, at: SCNVector3(x, y, z + 0.19))
            for index in 0..<5 {
                let hue = [0xA87974, 0xD2AE76, 0x78958C, 0x8F94AE, 0xB8AAA1][(row + index) % 5]
                box(parent, width * 0.12, 0.20 + CGFloat(index % 3) * 0.036, 0.05, hue,
                    at: SCNVector3(x + width * (CGFloat(index) - 2) * 0.16, y - 0.04, z + 0.22))
            }
        }
    }

    /// 标牌随主题调色，沿用人物名牌的单次纹理绘制。
    private func sign(_ parent: SCNNode, title: String, at position: SCNVector3, width: CGFloat, tint: NSColor) {
        let label = officeLabel(title, color: tint, width: width, height: 0.49, dark: night)
        label.position = position
        parent.addChildNode(label)
    }

    /// 将基本家具接入指定节点，外部仍可单独配置灯材质等属性。
    @discardableResult
    private func box(_ parent: SCNNode, _ width: CGFloat, _ height: CGFloat, _ depth: CGFloat, _ color: Int, at position: SCNVector3) -> SCNNode {
        let node = officeBox(width, height, depth, color: color, at: position)
        parent.addChildNode(node)
        return node
    }
}
