// 原生公司场景：借鉴 agent-floor 的部门、工位和人物动作，以 SceneKit 绘制，无需网页或后台服务。
import AppKit
import SceneKit
import SwiftUI
import simd

/// 按在用工位分配项目房间。优先保留已有位置，收回整间房或整排时才迁入前方空位。
struct CodexOfficeSeatBook: Equatable {
    /// 每个项目可有多间六席办公室，房间身份独立于所在楼层位置。
    struct Room: Hashable {
        let project: String
        let index: Int
    }

    static let roomCapacity = 6
    private(set) var rooms: [Room: Int] = [:]
    private(set) var seats: [String: [String: Int]] = [:]

    /// 在岗或尚未离开工位的会话占用座席。公司按项目分配，海岛由所有项目共用工坊。
    mutating func assign(_ employees: [CodexOfficeEmployee], byProject: Bool = true) {
        let grouped = Dictionary(grouping: employees) { byProject ? $0.projectPath : "" }
        seats = seats.filter { grouped[$0.key] != nil }
        for (project, people) in grouped {
            let present = Set(people.map(\.id))
            let seatLimit = ((people.count + Self.roomCapacity - 1) / Self.roomCapacity) * Self.roomCapacity
            var reserved = seats[project, default: [:]].filter { present.contains($0.key) && $0.value < seatLimit }
            var used = Set(reserved.values)
            var next = 0
            for person in people.sorted(by: { $0.id < $1.id }) where reserved[person.id] == nil {
                while used.contains(next) { next += 1 }
                reserved[person.id] = next
                used.insert(next)
            }
            seats[project] = reserved
        }
        let needed = Set(seats.flatMap { project, seats in
            seats.values.map { Room(project: project, index: $0 / Self.roomCapacity) }
        })
        // 两间并列为一排；仅在缩短楼层时收回后排，其余房间保持原位。
        let roomLimit = max(1, (needed.count + 1) / 2) * 2
        rooms = rooms.filter { needed.contains($0.key) && $0.value < roomLimit }
        var occupied = Set(rooms.values)
        var slot = 0
        for room in needed.sorted(by: { $0.project == $1.project ? $0.index < $1.index : $0.project < $1.project })
            where rooms[room] == nil {
            while occupied.contains(slot) { slot += 1 }
            rooms[room] = slot
            occupied.insert(slot)
        }
    }
}

/// 同事的目的地及对应姿势。路线从主走廊或入口出发。
struct OfficeDestination: Equatable {
    enum Kind { case desk, rest, exit }
    let route: [CGPoint]
    let heading: CGFloat
    let seated: Bool
    let kind: Kind
}

/// 办公室的路径从中央走廊通往门口和目标位置，平面坐标的 y 对应 SceneKit 的 z。
enum OfficeWalkRoute {
    /// 从当前画面位置接上原有通道，再去新地点。中途改道沿最近的路径段回到走廊。
    static func itinerary(from current: CGPoint, leaving oldPath: [CGPoint], entering newPath: [CGPoint]) -> [CGPoint] {
        var path = [current]
        if current.x != 0, let first = oldPath.firstIndex(where: { $0.x == 0 }),
           let last = oldPath.lastIndex(where: { $0.x == 0 }) {
            let segment = oldPath.indices.dropLast().min {
                distance(from: current, toSegment: oldPath[$0], oldPath[$0 + 1])
                    < distance(from: current, toSegment: oldPath[$1], oldPath[$1 + 1])
            }
            if let segment, segment < first {
                path.append(contentsOf: oldPath[(segment + 1)...first])
            } else if let segment, segment >= last {
                path.append(contentsOf: oldPath[last...segment].reversed())
            }
        }
        for point in newPath where path.last != point {
            path.append(point)
        }
        return path
    }

    /// 用点到线段的距离辨认人物正在经过的通道，避免改道时穿过邻室隔墙。
    private static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - start.x - t * dx, point.y - start.y - t * dy)
    }
}

// 房间按相同进深首尾相接，门口在桌组侧边。
private let officeEntranceOffset: CGFloat = 3.36
private let officeRoomDepth: CGFloat = 7.6

/// 管理一个原生三维场景的镜头、人物和工具飞行。布局依主题而定，会话状态来自页面的数据层。
@MainActor
final class CodexOfficeScene: ObservableObject {
    let scene = SCNScene()
    let camera = SCNNode()
    private let environment = SCNNode()
    private let site = SCNNode()
    private let people = SCNNode()
    private let traffic = SCNNode()
    private let ambient = SCNNode()
    private let sun = SCNNode()
    private let isIsland: Bool
    private var seatBook = CodexOfficeSeatBook()
    private var characters: [String: OfficeCharacter] = [:]
    private var trackedPeople: [String: CodexOfficeEmployee] = [:]
    private var deskDestinations: [String: OfficeDestination] = [:]
    private var islandWorkstations: [String: (seat: Int, tint: Int, node: SCNNode)] = [:]
    private var restSlots: [String: Int] = [:]
    private var toolTraffic = OfficeToolTraffic()
    private var layoutReady = false
    private var yardFront = OfficeBuilding.defaultYardFront
    private var drawnSite: (front: CGFloat, end: CGFloat, night: Bool)?
    private var drawnWorkshops = 0
    private var drawnBenches = 0
    private var facadeSides: [OfficeFacadeSide] = []
    private var night = false
    private var selectedID: String?
    private var center = SCNVector3Zero
    private var lastCameraRequest = 0
    private var demoMode: Bool?
    private var floorBounds = (minimum: SCNVector3(-11, 0, -7.5), maximum: SCNVector3(11, 3.5, 10))
    weak var view: OfficeCanvasView? {
        didSet {
            oldValue?.onCameraChanged = nil
            view?.pointOfView = camera
            view?.onCameraChanged = { [weak self] in self?.updateCameraPresentation() }
            if isIsland {
                view?.preferredFramesPerSecond = 60
                view?.antialiasingMode = .multisampling2X
            }
        }
    }

    /// 每个主题持有自己的镜头和场景，进入画布后才按会话与外观配置布景。
    init(isIsland: Bool = false) {
        self.isIsland = isIsland
        scene.rootNode.addChildNode(environment)
        environment.name = "office-building"
        environment.addChildNode(site)
        people.name = "office-people"
        scene.rootNode.addChildNode(people)
        scene.rootNode.addChildNode(traffic)
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.zFar = 500
        camera.camera?.screenSpaceAmbientOcclusionIntensity = isIsland ? 0.44 : 0.35
        scene.rootNode.addChildNode(camera)
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        scene.rootNode.addChildNode(ambient)
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 950
        sun.light?.castsShadow = true
        sun.light?.shadowMode = isIsland ? .forward : .deferred
        sun.light?.shadowColor = NSColor.black.withAlphaComponent(isIsland ? 0.37 : 0.17)
        sun.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        sun.light?.shadowSampleCount = isIsland ? 6 : 8
        sun.eulerAngles = isIsland ? SCNVector3(-CGFloat.pi / 3.37, -CGFloat.pi / 3.8, 0)
            : SCNVector3(-CGFloat.pi / 3, -CGFloat.pi / 5, 0)
        scene.rootNode.addChildNode(sun)
    }

    /// 根据名册更新家具和在场人物，直接使用已分配的昵称。人员离场后再收回多出的地面。
    func update(employees: [CodexOfficeEmployee], selected: String?, isNight: Bool, paused: Bool, cameraRequest: Int, reduceMotion: Bool, isDemo: Bool) {
        let initialPopulation = demoMode != isDemo
        let playing = !paused && !reduceMotion
        if initialPopulation {
            seatBook = CodexOfficeSeatBook()
            characters.values.forEach { $0.root.removeFromParentNode() }
            characters = [:]
            trackedPeople = [:]
            restSlots = [:]
            traffic.childNodes.forEach { $0.removeFromParentNode() }
            toolTraffic = OfficeToolTraffic()
            layoutReady = false
            selectedID = nil
            demoMode = isDemo
        }
        let present = employees.filter(\.isOnSite)
        let presentIDs = Set(present.map(\.id))
        let roster = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })
        var visible = present
        for id in Array(characters.keys) where !presentIDs.contains(id) {
            if playing, characters[id]?.root.isHidden == false, let person = roster[id] ?? trackedPeople[id] {
                visible.append(person)
            } else {
                characters.removeValue(forKey: id)?.root.removeFromParentNode()
            }
        }
        let resting = present.filter { $0.status == .idle }
        let restingIDs = Set(resting.map(\.id))
        restSlots = restSlots.filter { restingIDs.contains($0.key) }
        var used = Set(restSlots.values)
        for person in resting.sorted(by: { $0.id < $1.id }) where restSlots[person.id] == nil {
            var slot = (0..<OfficeBuilding.indoorRestSeats).first { !used.contains($0) } ?? OfficeBuilding.indoorRestSeats
            while used.contains(slot) { slot += 1 }
            restSlots[person.id] = slot
            used.insert(slot)
        }
        let destinations = restSlots.mapValues {
            isIsland ? OfficeIslandLayout.restDestination(for: $0) : OfficeBuilding.restDestination(for: $0)
        }
        let front: CGFloat
        if isIsland {
            front = OfficeIslandLayout.back
        } else {
            front = destinations.values.compactMap { $0.route.last?.y }.reduce(OfficeBuilding.defaultYardFront) {
                min($0, $1 - 1.8)
            }
        }
        // 工位会保留到离开的步行动作结束，避免隔墙或门口在人物经过时被移除。
        let occupants = visible.filter { person in
            (presentIDs.contains(person.id) && person.status != .idle)
                || (!reduceMotion && characters[person.id]?.reservesDesk == true)
        }
        let previousSeats = seatBook
        seatBook.assign(occupants, byProject: !isIsland)
        let rows = (seatBook.rooms.values.max() ?? 0) / 2 + 1
        let workshops = (seatBook.seats[""]?.values.max() ?? 0) / CodexOfficeSeatBook.roomCapacity + 1
        let benches = (restSlots.values.max() ?? 0) / 2 + 1
        let islandShapeChanged = isIsland && (drawnWorkshops != workshops || drawnBenches != benches)
        let roomEnd = isIsland ? OfficeIslandLayout.shoreEnd(workshops: workshops, benches: benches)
            : OfficeBuilding.firstRoomStart + CGFloat(rows) * officeRoomDepth + OfficeBuilding.foundationOverhang
        let previousEnd = drawnSite?.end ?? roomEnd
        let keepFloor = !reduceMotion && previousEnd > roomEnd && characters.values.contains {
            $0.needsFloor(beyond: roomEnd, includeStationary: !paused)
        }
        let end = keepFloor ? previousEnd : roomEnd
        if !layoutReady || previousSeats != seatBook || isNight != night || front != yardFront || end != drawnSite?.end || islandShapeChanged {
            let initialLayout = !layoutReady
            let priorZ = floorBounds.maximum.z
            let priorFront = yardFront
            yardFront = front
            night = isNight
            if isIsland {
                buildIsland(occupants, workshops: workshops, benches: benches, end: end)
            } else {
                buildOffice(occupants, rows: rows, end: end)
            }
            layoutReady = true
            if initialLayout || (selected == nil && view?.cameraWasMoved != true &&
                (priorZ != floorBounds.maximum.z || priorFront != yardFront)) {
                resetCamera()
            }
        }
        trackedPeople = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        let entrance = isIsland ? CGPoint(x: 0, y: end - 1.0) : OfficeBuilding.entrance
        let exit = OfficeDestination(route: [entrance], heading: .pi, seated: false, kind: .exit)
        let benchLift = isIsland ? islandBenchBadgeLift : 0
        for person in visible {
            let isNew = characters[person.id] == nil
            let character = characters[person.id] ?? OfficeCharacter(employee: person, isIsland: isIsland)
            if isNew {
                characters[person.id] = character
                people.addChildNode(character.root)
                character.root.position = SCNVector3(entrance.x, 0, entrance.y)
                character.onReleasedLocation = { [weak self] in self?.objectWillChange.send() }
            }
            var destination = exit
            if presentIDs.contains(person.id) {
                if let resting = destinations[person.id] {
                    destination = resting
                } else if let desk = deskDestinations[person.id] {
                    destination = desk
                }
            }
            let sharesBench = isIsland && restSlots[person.id].map { !$0.isMultiple(of: 2) && used.contains($0 - 1) } == true
            character.update(person, destination: destination, selected: selected == person.id,
                             animated: !reduceMotion, placeImmediately: paused || (isNew && initialPopulation),
                             restBadgeLift: sharesBench ? benchLift : 0)
        }
        let flights = toolTraffic.observe(employees, now: Date(), animated: !paused && !reduceMotion)
        if reduceMotion { traffic.childNodes.forEach { $0.removeFromParentNode() } }
        for flight in flights.prefix(max(0, 6 - traffic.childNodes.count)) {
            guard let desk = deskDestinations[flight.employeeID]?.route.last else { continue }
            let workstation = isIsland ? SCNVector3(desk.x, 2.16, desk.y + 0.74) : SCNVector3(desk.x, 2.36, desk.y)
            let station = isIsland ? OfficeIslandLayout.toolStation : OfficeBuilding.toolStation
            let start = flight.returning ? station : workstation
            let end = flight.returning ? workstation : station
            let color = NSColor(officeHex: flight.failed ? 0xFF9D86 : flight.returning ? 0xD4C6FF : 0xACE2FF)
            traffic.addChildNode(officePaperPlane(from: start, to: end, color: color))
        }
        if selected != selectedID {
            selectedID = selected
            if let selected, presentIDs.contains(selected), let node = characters[selected]?.root { focus(node.presentation.position) }
        }
        if cameraRequest != lastCameraRequest {
            lastCameraRequest = cameraRequest
            resetCamera()
        }
        if scene.isPaused == playing { scene.isPaused = !playing }
        if let view, view.isPlaying != playing { view.isPlaying = playing }
    }

    /// 按画布尺寸恢复默认构图；画布尚无尺寸时，保留当前缩放，等待布局回调重新取景。
    func resetCamera() {
        // 外墙容器与场景共用坐标。以外墙取景，庭院仍使用原边界处理裁剪平面。
        let facade = isIsland ? nil : facadeSides.first?.upper.parent?.boundingBox
        let minimum = facade?.min ?? floorBounds.minimum
        let maximum = facade?.max ?? floorBounds.maximum
        let target = isIsland ? SCNVector3(center.x, 0.81, center.z)
            : SCNVector3((minimum.x + maximum.x) / 2, (minimum.y + maximum.y) / 2, (minimum.z + maximum.z) / 2)
        camera.position = isIsland ? SCNVector3(target.x - 6.5, target.y + 16.8, target.z + 27)
            // 公司保留约 30° 俯角，让建筑在宽画布里横向铺开。
            : SCNVector3(target.x + 24, target.y + 19.6, target.z + 24)
        // 显式指定世界竖直方向，避免复位时带入上一次视角的横滚。
        camera.look(at: target, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        view?.orbitTarget = SIMD3<Float>(target)
        if let view, view.bounds.width > 0, view.bounds.height > 0 {
            // 直接投影包围盒，避免使用上一帧镜头或 Retina 像素尺寸。
            let extent = SIMD3<Float>(maximum) - SIMD3<Float>(minimum)
            let projectedWidth = CGFloat(simd_dot(simd_abs(camera.simdWorldRight), extent))
            let projectedHeight = CGFloat(simd_dot(simd_abs(camera.simdWorldUp), extent))
            let aspect = view.bounds.width / view.bounds.height
            let widthFill: CGFloat = isIsland ? 0.96 : 0.98
            let heightFill: CGFloat = isIsland ? 0.94 : 0.98
            let fit = max(projectedWidth / (2 * aspect * widthFill), projectedHeight / (2 * heightFill))
            // 小岛仅在单工坊且长椅较少时收紧构图。
            let crop: CGFloat = isIsland && drawnWorkshops == 1 && drawnBenches <= 2 ? 0.79 : 1
            camera.camera?.orthographicScale = Double(fit * crop)
            view.overviewScale = camera.camera?.orthographicScale ?? 25
            view.cameraWasMoved = false
        }
        updateCameraPresentation()
    }

    /// 原生画布得到真实尺寸后再取景，防止零尺寸布局把镜头拉得过远。
    func viewportChanged() {
        if selectedID == nil, view?.cameraWasMoved != true { resetCamera() }
    }

    /// 聚焦同事时沿当前朝向移动镜头，保留俯角和方位，缩小正交范围。
    private func focus(_ point: SCNVector3) {
        let target = SIMD3(Float(point.x), 0.6, Float(point.z))
        SCNTransaction.begin()
        SCNTransaction.animationDuration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.5
        camera.simdWorldPosition = target - camera.simdWorldFront * 18
        // 宽画布的默认构图可能已经很近，人物特写仍需有足够的放大幅度让前墙淡出。
        camera.camera?.orthographicScale = isIsland ? 5.7 : min(7.6, (view?.overviewScale ?? 25) * 0.56)
        updateCameraPresentation()
        SCNTransaction.commit()
        view?.orbitTarget = target
    }

    /// 把地台包围盒留在裁剪平面之间。正交相机沿视线后移不改变画面大小或位置。
    /// 近景按朝向淡出前方外墙的上部，墙脚和室内隔断始终可见。
    private func updateCameraPresentation() {
        guard let lens = camera.camera else { return }
        let minimum = SIMD3<Float>(floorBounds.minimum)
        let maximum = SIMD3<Float>(floorBounds.maximum)
        let forward = camera.simdWorldFront
        let depth = simd_dot((minimum + maximum) / 2 - camera.simdWorldPosition, forward)
        let reach = simd_dot((maximum - minimum) / 2, simd_abs(forward))
        let retreat = max(0, Float(lens.zNear) + 0.75 - (depth - reach))
        if retreat > 0 { camera.simdWorldPosition -= forward * retreat }
        let far = max(500, Double(depth + reach + retreat + 4))
        if lens.zFar != far { lens.zFar = far }

        let overview = view?.overviewScale ?? lens.orthographicScale
        let close = min(1, max(0, (0.82 - lens.orthographicScale / overview) / 0.24))
        let facingCamera = SIMD2(-forward.x, -forward.z)
        for side in facadeSides {
            let facing = min(1, max(0, Double(simd_dot(side.normal, facingCamera) - 0.06) / 0.32))
            let opacity = CGFloat(1 - 0.88 * close * facing)
            if side.upper.opacity != opacity { side.upper.opacity = opacity }
        }
        if isIsland {
            let occupiedSlots = Set(restSlots.values)
            let lift = islandBenchBadgeLift
            for (id, slot) in restSlots where !slot.isMultiple(of: 2) {
                characters[id]?.setRestBadgeLift(occupiedSlots.contains(slot - 1) ? lift : 0)
            }
        }
    }

    /// 用镜头的屏幕上方向补偿两个座位的横向投影，留出大号选中名牌的垂直间距。
    private var islandBenchBadgeLift: CGFloat {
        let up = camera.simdWorldUp
        let seatGap = Float(2 * OfficeIslandLayout.benchSeatOffset)
        return CGFloat(max(0.20, (0.78 + seatGap * up.x) / max(0.20, up.y)))
    }

    /// 点击人物或其工位时向上查找会话身份；家具本身不冒充同事。
    func employee(at point: CGPoint) -> String? {
        guard let view else { return nil }
        for hit in view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, name.hasPrefix("employee:") { return String(name.dropFirst(9)) }
                node = current.parent
            }
        }
        return nil
    }

    /// 送咖啡仅在人物身旁播放杯子与蒸汽，不改变其真实工作状态。
    func sendCoffee(to id: String) {
        guard let character = characters[id] else { return }
        let cup = SCNNode()
        let mug = SCNCylinder(radius: 0.13, height: 0.24)
        let body = officeNode(mug, color: .white, at: SCNVector3Zero)
        cup.addChildNode(body)
        let handle = officeNode(SCNTorus(ringRadius: 0.09, pipeRadius: 0.025), color: .white, at: SCNVector3(0.16, 0, 0))
        handle.eulerAngles.x = .pi / 2
        cup.addChildNode(handle)
        cup.position = SCNVector3(0.6, 1.2, 0)
        character.root.addChildNode(cup)
        for index in 0..<3 {
            let steam = officeNode(SCNSphere(radius: 0.04), color: NSColor.white.withAlphaComponent(0.65), at: SCNVector3(0, 0.18, 0))
            cup.addChildNode(steam)
            steam.runAction(.sequence([.wait(duration: Double(index) * 0.3), .group([.moveBy(x: 0.04, y: 0.5, z: 0, duration: 1.3), .fadeOut(duration: 1.3)])]))
        }
        cup.runAction(.sequence([.moveBy(x: 0, y: 0.3, z: 0, duration: 0.4), .wait(duration: 2), .fadeOut(duration: 0.5), .removeFromParentNode()]))
    }

    /// 下班前伸展是短暂的视觉互动，完成后仍显示真实的 Hook 状态。
    func stretch() {
        for character in characters.values {
            character.body.runAction(.sequence([.moveBy(x: 0, y: 0.25, z: 0, duration: 0.2), .wait(duration: 0.5), .moveBy(x: 0, y: -0.25, z: 0, duration: 0.3)]), forKey: "stretch")
        }
    }

    /// 布景按岛的尺寸和外观更新，工位仅在会话离席、挪位或材质变更时替换。
    private func buildIsland(_ employees: [CodexOfficeEmployee], workshops: Int, benches: Int, end: CGFloat) {
        let art = OfficeIslandScenery(night: night)
        let appearanceChanged = drawnSite?.night != night
        if drawnSite?.end != end || appearanceChanged || drawnWorkshops != workshops || drawnBenches != benches {
            site.childNodes.forEach { $0.removeFromParentNode() }
            art.build(on: site, workshops: workshops, benches: benches, end: end)
            drawnSite = (yardFront, end, night)
            drawnWorkshops = workshops
            drawnBenches = benches
        }
        if appearanceChanged {
            scene.background.contents = NSColor(officeHex: night ? 0x123C5B : 0x168FA5)
            ambient.light?.color = NSColor(officeHex: night ? 0xA8C0DA : 0xF4F7EE)
            ambient.light?.intensity = night ? 555 : 505
            sun.light?.color = NSColor(officeHex: night ? 0xC7DEF4 : 0xFFF0CD)
            sun.light?.intensity = night ? 410 : 1080
        }
        floorBounds = (SCNVector3(-10.72, -1.25, yardFront - 0.45), SCNVector3(12.58, 4.88, end + 0.65))
        center = SCNVector3(0.83, 0, (floorBounds.minimum.z + floorBounds.maximum.z) / 2)
        let occupants = Set(employees.map(\.id))
        let released = islandWorkstations.keys.filter { appearanceChanged || !occupants.contains($0) }
        for id in released {
            islandWorkstations.removeValue(forKey: id)?.node.removeFromParentNode()
            deskDestinations.removeValue(forKey: id)
        }
        let accents = [0x77A797, 0xD79D64, 0x799EBB, 0xC08794, 0x918FB7, 0xBDAD70]
        for employee in employees {
            guard let seat = seatBook.seats[""]?[employee.id] else { continue }
            let tint = accents[Int(CodexOfficeEmployee.stableHash(employee.projectPath) % UInt64(accents.count))]
            if let previous = islandWorkstations[employee.id], previous.seat == seat, previous.tint == tint { continue }
            islandWorkstations[employee.id]?.node.removeFromParentNode()
            let (desk, destination) = art.workstation(for: employee.id, index: seat, projectTint: tint)
            environment.addChildNode(desk)
            islandWorkstations[employee.id] = (seat, tint, desk)
            deskDestinations[employee.id] = destination
        }
        updateCameraPresentation()
    }

    /// 按已分配的行数绘制房间。办公室内的对坐桌与侧桌跟随座位编号，主题刷新时位置稳定。
    private func buildOffice(_ employees: [CodexOfficeEmployee], rows: Int, end: CGFloat) {
        for node in environment.childNodes where node !== site { node.removeFromParentNode() }
        deskDestinations = [:]
        let building = OfficeBuilding(root: environment, night: night)
        scene.background.contents = building.background
        ambient.light?.color = night ? NSColor(officeHex: 0xB2C9EC) : NSColor(officeHex: 0xF4F8FF)
        ambient.light?.intensity = night ? 410 : 520
        sun.light?.intensity = night ? 310 : 790
        sun.light?.color = night ? NSColor(officeHex: 0xBBC9EE) : NSColor(officeHex: 0xFFF2DC)

        let bySlot = Dictionary(uniqueKeysWithValues: seatBook.rooms.map { ($0.value, $0.key) })
        floorBounds = (SCNVector3(-14.55, -0.55, yardFront), SCNVector3(14.55, 4.0, end + 3.1))
        center = SCNVector3(0, 0, (floorBounds.minimum.z + floorBounds.maximum.z) / 2)
        if drawnSite?.front != yardFront || drawnSite?.end != end || drawnSite?.night != night {
            site.childNodes.forEach { $0.removeFromParentNode() }
            facadeSides = OfficeBuilding(root: site, night: night).site(front: yardFront, officeEnd: end)
            drawnSite = (yardFront, end, night)
        }
        updateCameraPresentation()

        let grouped = Dictionary(grouping: employees, by: \.projectPath)
        for slot in 0..<(rows * 2) {
            let z = OfficeBuilding.firstRoomStart + CGFloat(slot / 2) * officeRoomDepth
            let innerSide: CGFloat = slot.isMultiple(of: 2) ? 1 : -1
            let x = -innerSide * OfficeBuilding.wingCenter
            let middleZ = z + officeRoomDepth / 2
            building.partition(x: x, z: z)
            if slot >= 2 && bySlot[slot] == nil {
                building.courtyard(x: x, z: middleZ, depth: officeRoomDepth)
                continue
            }
            let room = SCNNode()
            room.name = "office-room"
            room.position = SCNVector3(x, 0, middleZ)
            environment.addChildNode(room)
            guard let roomID = bySlot[slot] else {
                let isGameRoom = slot == 0 && bySlot.isEmpty
                let title = isGameRoom ? officeText("活动区", "REC ROOM") : officeText("会议室", "MEETING")
                let tint = NSColor(officeHex: isGameRoom ? 0x795F86 : 0x61799F)
                building.workroom(room, title: title, depth: officeRoomDepth, innerSide: innerSide,
                                  entranceOffset: officeEntranceOffset, tint: tint)
                if isGameRoom { building.games(in: room) } else { building.meeting(in: room) }
                continue
            }
            let project = grouped[roomID.project]?.first?.project ?? ""
            let title = roomID.index == 0 ? project : project + " · " + String(roomID.index + 1)
            let tint = OfficePalette.shirts[Int(CodexOfficeEmployee.stableHash(roomID.project) % 6)]
            building.workroom(room, title: title, depth: officeRoomDepth, innerSide: innerSide,
                              entranceOffset: officeEntranceOffset, tint: tint)
            building.officeFurniture(in: room, depth: officeRoomDepth, innerSide: innerSide)

            let doorway = z + officeEntranceOffset
            for (id, index) in seatBook.seats[roomID.project] ?? [:]
                where index / CodexOfficeSeatBook.roomCapacity == roomID.index {
                let localSeat = index % CodexOfficeSeatBook.roomCapacity
                let desk = building.workstation(for: id, tint: tint)
                deskDestinations[id] = placeDesk(desk, seat: localSeat, in: room, innerSide: innerSide,
                                                 doorway: doorway)
            }
        }
    }

    /// 六个固定座位中，第二和第六席转 90° 放在桌组侧端。左右房间镜像，侧桌从外侧椅背通道入座。
    private func placeDesk(_ desk: SCNNode, seat: Int, in room: SCNNode, innerSide: CGFloat,
                           doorway: CGFloat) -> OfficeDestination {
        let x = room.position.x
        let z = room.position.z
        let aisle = x + innerSide * 4.16
        var route = [CGPoint(x: 0, y: doorway), CGPoint(x: aisle, y: doorway)]
        let yaw: CGFloat
        if seat == 1 || seat == 5 {
            let deskX = -innerSide * 1.87
            let deskZ: CGFloat = seat == 1 ? 0 : 2.18
            desk.position = SCNVector3(deskX, 0, deskZ)
            yaw = -innerSide * .pi / 2
            let seatX = x + deskX - innerSide * 0.70
            let seatZ = z + deskZ
            let approachX = x - innerSide * 3.37
            let behindPod = z - 2.34
            route += [CGPoint(x: aisle, y: behindPod), CGPoint(x: approachX, y: behindPod),
                      CGPoint(x: approachX, y: seatZ), CGPoint(x: seatX, y: seatZ)]
        } else {
            let podSeat = max(0, seat - 1)
            let deskX = innerSide * CGFloat(podSeat / 2) * 2.17
            let nearSide = podSeat.isMultiple(of: 2)
            let side: CGFloat = nearSide ? 1 : -1
            let deskZ = side * 0.535
            desk.position = SCNVector3(deskX, 0, deskZ)
            yaw = nearSide ? 0 : .pi
            let seatX = x + deskX
            let seatZ = z + deskZ + side * 0.70
            let approachX = seatX + innerSide * 0.73
            let approachZ = z + side * 2.23
            route += [CGPoint(x: aisle, y: approachZ), CGPoint(x: approachX, y: approachZ),
                      CGPoint(x: approachX, y: seatZ), CGPoint(x: seatX, y: seatZ)]
        }
        desk.eulerAngles.y = yaw
        room.addChildNode(desk)
        return OfficeDestination(route: route, heading: yaw + .pi, seated: true, kind: .desk)
    }

}

/// 可独立更新的黏土小人；四肢动画与移动分层，状态刷新不会导致人物回到出生位置。
@MainActor
private final class OfficeCharacter {
    let root = SCNNode()
    let body = SCNNode()
    private let leftArm = SCNNode()
    private let rightArm = SCNNode()
    private let leftLeg = SCNNode()
    private let rightLeg = SCNNode()
    private let leftKnee = SCNNode()
    private let rightKnee = SCNNode()
    private let head = SCNNode()
    private let badge = SCNNode()
    private let badgeHeight: CGFloat
    private let isIsland: Bool
    private var restMug: SCNNode?
    private let statusRing: SCNNode
    private let selection: SCNNode
    private(set) var reservesDesk = false
    var onReleasedLocation: (() -> Void)?
    private var status = CodexOfficeStatus.idle
    private var destination: OfficeDestination?
    private var walkPath: [CGPoint] = []
    private var walkRevision = 0
    private var signalExpired = false
    private var labelKey = ""
    private var motionEnabled = true

    /// 会话编号决定衣着和肤色。海岛小人的大头与帽饰沿用同一套步态和姿势节点。
    init(employee: CodexOfficeEmployee, isIsland: Bool) {
        self.isIsland = isIsland
        badgeHeight = isIsland ? 2.43 : 1.91
        root.name = "employee:" + employee.id
        selection = officeNode(SCNTorus(ringRadius: 0.51, pipeRadius: 0.023), color: .white, at: SCNVector3(0, 0.10, 0))
        statusRing = officeNode(SCNTorus(ringRadius: 0.42, pipeRadius: 0.036), color: .clear, at: SCNVector3(0, 0.10, 0))
        statusRing.geometry?.firstMaterial?.lightingModel = .constant
        statusRing.castsShadow = false
        root.addChildNode(statusRing)
        root.addChildNode(selection)
        root.addChildNode(body)
        let islandArt = isIsland ? OfficeIslandScenery(night: false) : nil
        if isIsland {
            let scale = OfficeIslandLayout.figureScale
            body.scale = SCNVector3(scale, scale, scale)
        }
        let shirt = OfficePalette.shirts[employee.appearance]
        let skin = [0xE9BB91, 0xB77D55, 0xF0CFAC, 0xC99771, 0xE0AC7D, 0x986B50][employee.appearance]
        body.addChildNode(officeNode(SCNBox(width: 0.44, height: 0.44, length: 0.29, chamferRadius: isIsland ? 0.13 : 0.07), color: shirt, at: SCNVector3(0, 0.86, 0)))
        head.position = SCNVector3(0, 1.25, 0)
        if let islandArt {
            head.addChildNode(islandArt.characterHead(variation: employee.appearance, skin: skin))
            head.scale = SCNVector3(1.13, 1.13, 1.13)
            let collar = officeNode(SCNTorus(ringRadius: 0.101, pipeRadius: 0.023), color: NSColor(officeHex: 0xE8C491), at: SCNVector3(0, 1.045, 0.008))
            collar.scale.z = 0.78
            body.addChildNode(collar)
            let pocket = officeBox(0.15, 0.12, 0.035, color: 0xCC9B66, at: SCNVector3(0.083, 0.84, 0.151))
            body.addChildNode(pocket)
        } else {
            head.addChildNode(officeBox(0.38, 0.38, 0.35, color: skin, at: SCNVector3Zero))
            head.addChildNode(officeBox(0.4, 0.14, 0.37, color: employee.appearance % 2 == 0 ? 0x473A34 : 0x302E31, at: SCNVector3(0, 0.17, -0.01)))
            for x: CGFloat in [-0.085, 0.085] {
                head.addChildNode(officeNode(SCNSphere(radius: 0.024), color: NSColor(officeHex: 0x302E31), at: SCNVector3(x, 0.01, 0.18)))
            }
        }
        body.addChildNode(head)
        for (arm, x) in [(leftArm, CGFloat(-0.28)), (rightArm, CGFloat(0.28))] {
            arm.position = SCNVector3(x, 1.03, 0)
            arm.addChildNode(officeNode(SCNCapsule(capRadius: 0.07, height: 0.35), color: shirt, at: SCNVector3(0, -0.13, 0)))
            arm.addChildNode(officeBox(0.12, 0.12, 0.13, color: skin, at: SCNVector3(0, -0.32, 0)))
            body.addChildNode(arm)
        }
        for (leg, knee, x) in [(leftLeg, leftKnee, CGFloat(-0.13)), (rightLeg, rightKnee, CGFloat(0.13))] {
            leg.position = SCNVector3(x, 0.65, 0)
            leg.addChildNode(officeBox(0.14, 0.25, 0.16, color: 0x37484C, at: SCNVector3(0, -0.11, 0)))
            knee.position.y = -0.23
            knee.addChildNode(officeBox(0.13, 0.25, 0.15, color: 0x37484C, at: SCNVector3(0, -0.12, 0)))
            knee.addChildNode(officeBox(0.19, 0.12, 0.27, color: isIsland ? 0x744C33 : 0xE7E9DD, at: SCNVector3(0, -0.26, 0.045)))
            leg.addChildNode(knee)
            body.addChildNode(leg)
        }
        badge.position = SCNVector3(0, badgeHeight, 0)
        if isIsland { badge.name = "island-status-badge" }
        root.addChildNode(badge)
        if let islandArt {
            let mug = islandArt.restCup(at: SCNVector3(0.015, -0.31, 0.065))
            mug.eulerAngles.x = 1.13
            mug.isHidden = true
            rightArm.addChildNode(mug)
            restMug = mug
        }
    }

    /// 用名册昵称更新名牌，按状态、选中和长椅位置调整外观；行走时继续使用当前位置。
    func update(_ employee: CodexOfficeEmployee, destination next: OfficeDestination,
                selected: Bool, animated: Bool, placeImmediately: Bool, restBadgeLift: CGFloat) {
        let poseChanged = status != employee.status || signalExpired != employee.signalExpired || motionEnabled != animated
        let routeChanged = destination != next || motionEnabled != animated
        if next.kind == .desk { reservesDesk = true }
        status = employee.status
        signalExpired = employee.signalExpired
        motionEnabled = animated
        selection.isHidden = !selected
        setRestBadgeLift(restBadgeLift)
        let badgeScale: CGFloat = selected ? 1.20 : 1
        badge.scale = SCNVector3(badgeScale, badgeScale, badgeScale)
        let badgeStatus = employee.signalExpired ? .idle : status
        let statusTitle = employee.statusTitle
        let nextLabel = employee.name + "\n" + statusTitle + "\n" + badgeStatus.rawValue
        if labelKey != nextLabel {
            let tint = badgeStatus == .working ? NSColor(officeHex: 0x399AC7) : badgeStatus.officeColor
            badge.childNodes.forEach { $0.removeFromParentNode() }
            let label = officeLabel(employee.name, color: tint, width: 3.8, height: isIsland ? 0.51 : 0.49, status: statusTitle)
            if isIsland {
                label.geometry?.firstMaterial?.readsFromDepthBuffer = false
                label.renderingOrder = 12
            }
            badge.addChildNode(label)
            statusRing.geometry?.firstMaterial?.diffuse.contents = tint.withAlphaComponent(0.86)
            labelKey = nextLabel
        }
        if routeChanged {
            move(to: next, immediately: !animated || placeImmediately)
        } else if poseChanged && walkPath.isEmpty {
            applyStatusPose()
        }
    }

    /// 镜头旋转也可重算名牌高度，无需重新生成名牌纹理或改变人物姿势。
    func setRestBadgeLift(_ lift: CGFloat) {
        let height = badgeHeight + (selection.isHidden ? 0 : 0.15) + lift
        if badge.position.y != height { badge.position.y = height }
    }

    /// 用当前呈现的位置接续路线。路段按距离计时，转弯期间保持走动，旧动作回调不能覆盖新路线。
    private func move(to next: OfficeDestination, immediately: Bool) {
        guard let target = next.route.last else { return }
        let position = walkPath.isEmpty ? root.position : root.presentation.position
        let rotation = walkPath.isEmpty ? root.eulerAngles : root.presentation.eulerAngles
        let current = CGPoint(x: position.x, y: position.z)
        let itinerary = OfficeWalkRoute.itinerary(from: current, leaving: walkPath.isEmpty ? destination?.route ?? [] : walkPath, entering: next.route)
        let path = isIsland ? OfficeIslandLayout.walkingLanes(on: itinerary) : itinerary
        walkRevision += 1
        let revision = walkRevision
        root.removeAction(forKey: "walk")
        destination = next
        root.position = position
        root.eulerAngles = rotation
        if immediately || current == target {
            root.position = SCNVector3(target.x, 0, target.y)
            root.eulerAngles = SCNVector3(0, next.heading, 0)
            finishWalk()
            return
        }
        root.isHidden = false
        walkPath = path
        clearPose()
        for (limb, angle) in [(leftLeg, CGFloat(0.40)), (rightLeg, -0.40), (leftArm, -0.30), (rightArm, 0.30)] {
            let forward = SCNAction.rotateTo(x: angle, y: 0, z: 0, duration: 0.15)
            let backward = SCNAction.rotateTo(x: -angle, y: 0, z: 0, duration: 0.15)
            forward.timingMode = .easeInEaseOut
            backward.timingMode = .easeInEaseOut
            limb.runAction(.repeatForever(.sequence([forward, backward])))
        }
        var steps = zip(path, path.dropFirst()).compactMap { start, end -> SCNAction? in
            let dx = end.x - start.x
            let dz = end.y - start.y
            let distance = hypot(dx, dz)
            guard distance > 0.001 else { return nil }
            let seconds = distance / 3.8
            return .group([
                .move(to: SCNVector3(end.x, 0, end.y), duration: seconds),
                .rotateTo(x: 0, y: atan2(dx, dz), z: 0, duration: min(0.17, seconds), usesShortestUnitArc: true)
            ])
        }
        steps.append(.rotateTo(x: 0, y: next.heading, z: 0, duration: 0.17, usesShortestUnitArc: true))
        root.runAction(.sequence(steps), forKey: "walk") { [weak self] in
            Task { @MainActor in
                guard let self, self.walkRevision == revision else { return }
                self.finishWalk()
            }
        }
    }

    /// 判断缩短楼层时是否还需要这段地面。暂停时，新目的地会直接定位，只有进行中的路线需要保留。
    func needsFloor(beyond end: CGFloat, includeStationary: Bool) -> Bool {
        guard !root.isHidden else { return false }
        if !walkPath.isEmpty { return walkPath.contains { $0.y > end } }
        return includeStationary && root.position.z > end
    }

    /// 到达后释放原路线，去公共区或出口时也释放工位。通知场景收回空出的地面。
    private func finishWalk() {
        let finishedRoute = !walkPath.isEmpty
        walkPath = []
        let hasDesk = destination?.kind == .desk
        let leaving = destination?.kind == .exit
        let released = reservesDesk && !hasDesk
        reservesDesk = hasDesk
        root.isHidden = leaving
        applyStatusPose()
        if finishedRoute || released || leaving {
            Task { @MainActor [weak self] in self?.onReleasedLocation?() }
        }
    }

    /// 切换走路、坐姿和状态动作时，清掉上一个姿势的局部变换。
    private func clearPose() {
        for node in [body, head, leftArm, rightArm, leftLeg, rightLeg, leftKnee, rightKnee] {
            node.removeAllActions()
            node.eulerAngles = SCNVector3Zero
        }
        body.position = SCNVector3Zero
        restMug?.isHidden = true
    }

    /// 工位、沙发和公共区椅子共用坐姿；减少动态效果时仍保留可辨认的静态姿势。
    private func applyStatusPose() {
        clearPose()
        guard destination?.kind != .exit else { return }
        if destination?.seated == true {
            body.position.y = isIsland ? -0.20 : -0.15
            leftLeg.eulerAngles.x = -.pi / 2
            rightLeg.eulerAngles.x = -.pi / 2
            leftKnee.eulerAngles.x = .pi / 2
            rightKnee.eulerAngles.x = .pi / 2
        }
        guard !signalExpired else { return }
        switch status {
        case .working:
            for (arm, delay) in [(leftArm, 0.0), (rightArm, 0.13)] {
                arm.eulerAngles.x = isIsland ? -1.43 : -0.85
                guard motionEnabled else { continue }
                arm.runAction(.repeatForever(.sequence([.wait(duration: delay), .rotateBy(x: 0.18, y: 0, z: 0, duration: 0.16), .rotateBy(x: -0.18, y: 0, z: 0, duration: 0.16)])))
            }
        case .thinking:
            rightArm.eulerAngles = SCNVector3(-1.5, 0, -0.4)
            guard motionEnabled else { return }
            head.runAction(.repeatForever(.sequence([.rotateBy(x: 0.08, y: 0.12, z: 0, duration: 1.2), .rotateBy(x: -0.08, y: -0.12, z: 0, duration: 1.2)])))
        case .waiting:
            rightArm.eulerAngles.z = -2.5
            guard motionEnabled else { return }
            rightArm.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0, z: 0.35, duration: 0.3), .rotateBy(x: 0, y: 0, z: -0.35, duration: 0.3), .wait(duration: 0.7)])))
        case .completed:
            guard motionEnabled else { return }
            for (arm, angle) in [(leftArm, CGFloat(2.25)), (rightArm, -2.25)] {
                arm.runAction(.sequence([.rotateTo(x: -0.6, y: 0, z: angle, duration: 0.24), .wait(duration: 0.45),
                                         .rotateTo(x: 0, y: 0, z: 0, duration: 0.32)]))
            }
        case .failed:
            head.eulerAngles.x = 0.18
            guard motionEnabled else { return }
            head.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0.2, z: 0, duration: 0.25), .rotateBy(x: 0, y: -0.4, z: 0, duration: 0.5), .rotateBy(x: 0, y: 0.2, z: 0, duration: 0.25), .wait(duration: 1)])))
        case .idle:
            if destination?.kind == .rest, let restMug {
                restMug.isHidden = false
                rightArm.eulerAngles.x = -1.13
                body.position.z = -0.092
                leftKnee.eulerAngles.x = 1.14
                rightKnee.eulerAngles.x = 1.23
            }
            guard motionEnabled else { return }
            body.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0, z: 0.035, duration: 1.7), .rotateBy(x: 0, y: 0, z: -0.035, duration: 1.7)])), forKey: "status")
        }
    }
}

/// 采用原生 SceneKit 视图保留旋转、缩放和点击命中；移出页面即断开渲染器。
struct CodexOfficeSceneView: NSViewRepresentable {
    @ObservedObject var director: CodexOfficeScene
    let employees: [CodexOfficeEmployee]
    let selected: String?
    let night: Bool
    let paused: Bool
    let cameraRequest: Int
    let reduceMotion: Bool
    let isDemo: Bool
    let onSelect: (String?) -> Void

    /// 原生画布负责分派鼠标输入，SceneKit 只负责渲染和镜头变换。
    func makeNSView(context: Context) -> OfficeCanvasView {
        let view = OfficeCanvasView()
        view.scene = director.scene
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        director.view = view
        view.onResize = { [weak director] in director?.viewportChanged() }
        return view
    }

    /// SwiftUI 只把真实输入变化交给场景，不在渲染线程读取 Hook 文件。
    func updateNSView(_ view: OfficeCanvasView, context: Context) {
        view.onClick = { [weak director, onSelect] location in
            guard let director else { return }
            onSelect(director.employee(at: location))
        }
        director.update(employees: employees, selected: selected, isNight: night, paused: paused, cameraRequest: cameraRequest, reduceMotion: reduceMotion, isDemo: isDemo)
    }

    /// 拆除视图时终止绘制，防止关闭页面后仍消耗图形资源。
    static func dismantleNSView(_ view: OfficeCanvasView, coordinator: ()) {
        view.isPlaying = false
        view.scene = nil
    }
}

/// 接管鼠标与缩放手势。平移带动旋转中心，右键仅绕竖轴转动，缩放由正交镜头负责。
final class OfficeCanvasView: SCNView {
    var onResize: (() -> Void)?
    var onCameraChanged: (() -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var overviewScale: Double = 25
    var cameraWasMoved = false
    var orbitTarget = SIMD3<Float>.zero
    private var previousSize = NSSize.zero
    private static let panThreshold: CGFloat = 3
    private var leftPress: CGPoint?
    private var lastPan: CGPoint?
    private var lastOrbit: CGPoint?

    /// 首次与真正的尺寸变化才调整镜头，避免普通状态更新打断用户旋转。
    override func layout() {
        super.layout()
        guard bounds.size != previousSize, bounds.width > 0, bounds.height > 0 else { return }
        previousSize = bounds.size
        onResize?()
    }

    /// 记录左键按下位置，等待单击或平移手势成立。
    override func mouseDown(with event: NSEvent) {
        leftPress = event.locationInWindow
        lastPan = nil
    }

    /// 按当前正交比例沿屏幕平面移动镜头，让场景跟随鼠标。
    override func mouseDragged(with event: NSEvent) {
        guard let leftPress, let camera = pointOfView, let lens = camera.camera, bounds.height > 0 else { return }
        let current = event.locationInWindow
        guard lastPan != nil || hypot(current.x - leftPress.x, current.y - leftPress.y) >= Self.panThreshold else { return }
        let previous = lastPan ?? leftPress
        lastPan = current
        let unitsPerPoint = Float(2 * lens.orthographicScale / Double(bounds.height))
        let offset = camera.simdWorldRight * Float(previous.x - current.x) * unitsPerPoint
            + camera.simdWorldUp * Float(previous.y - current.y) * unitsPerPoint
        camera.simdWorldPosition += offset
        orbitTarget += offset
        cameraWasMoved = true
        needsDisplay = true
    }

    /// 短按在画布内完成时才命中人物；拖动结束只清除手势状态。
    override func mouseUp(with event: NSEvent) {
        let start = leftPress
        let panned = lastPan != nil
        leftPress = nil
        lastPan = nil
        let current = event.locationInWindow
        guard let start, !panned, hypot(current.x - start.x, current.y - start.y) < Self.panThreshold else { return }
        let location = convert(current, from: nil)
        if bounds.contains(location) { onClick?(location) }
    }

    /// 记录右键拖动起点，右键短按不会触发人物选择。
    override func rightMouseDown(with event: NSEvent) {
        lastOrbit = event.locationInWindow
    }

    /// 水平拖动绕世界竖轴旋转，垂直分量不改变俯角，防止地台在斜拖时伸缩。
    override func rightMouseDragged(with event: NSEvent) {
        guard let lastOrbit, let camera = pointOfView else { return }
        let current = event.locationInWindow
        self.lastOrbit = current
        let angle = Float(lastOrbit.x - current.x) * .pi / 600
        guard angle != 0 else { return }
        let rotation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
        camera.simdWorldPosition = orbitTarget + rotation.act(camera.simdWorldPosition - orbitTarget)
        camera.look(at: SCNVector3(orbitTarget.x, orbitTarget.y, orbitTarget.z),
                    up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        cameraWasMoved = true
        onCameraChanged?()
        needsDisplay = true
    }

    /// 结束右键拖动，下次按下时以新位置起算。
    override func rightMouseUp(with event: NSEvent) {
        lastOrbit = nil
    }

    /// 消费场景内的垂直滚动。触控板像素和机械滚轮刻度使用不同灵敏度。
    override func scrollWheel(with event: NSEvent) {
        let sensitivity = event.hasPreciseScrollingDeltas ? 0.008 : 0.10
        zoom(by: Double(event.scrollingDeltaY) * sensitivity)
    }

    /// 捏合与滚轮共用同一缩放上下限，手势不改变镜头中心。
    override func magnify(with event: NSEvent) {
        zoom(by: Double(event.magnification))
    }

    /// 以比例改变正交取景范围，并同步窗框的近景淡出。上限随全景大小增长。
    private func zoom(by amount: Double) {
        guard let camera = pointOfView?.camera, camera.usesOrthographicProjection, amount.isFinite, amount != 0 else { return }
        let factor = exp(-max(-0.6, min(0.6, amount)))
        camera.orthographicScale = max(2.5, min(max(18, overviewScale * 2.0), camera.orthographicScale * factor))
        cameraWasMoved = true
        onCameraChanged?()
        needsDisplay = true
    }
}

/// 在可见场景中识别新到达的工具调用和返回。只消费已有结构化事件，不推断同事之间的通信。
struct OfficeToolTraffic {
    /// 一次飞行对应工位和工具站之间的一个已观测事件。
    struct Flight {
        let employeeID: String
        let returning: Bool
        let failed: Bool
    }

    private var openedAt: TimeInterval?
    private var consumed: [String: TimeInterval] = [:]

    /// 首次观察只建立时间基线；暂停时也消费事件，恢复后不会补播历史。
    mutating func observe(_ employees: [CodexOfficeEmployee], now: Date, animated: Bool) -> [Flight] {
        let timestamp = now.timeIntervalSince1970
        guard let openedAt else {
            self.openedAt = timestamp
            return []
        }
        let threshold = max(openedAt, timestamp - 8)
        consumed = consumed.filter { $0.value > threshold }
        var flights: [(date: TimeInterval, flight: Flight)] = []
        for person in employees {
            for event in person.details?.history ?? [] where event.date > threshold && event.tool != nil {
                let returning = event.event == "PostToolUse" || event.event == "TranscriptToolReturn"
                guard returning || event.event == "PreToolUse" else { continue }
                let key = person.id + ":" + event.id
                guard consumed[key] == nil else { continue }
                consumed[key] = event.date
                if animated {
                    flights.append((event.date, Flight(employeeID: person.id, returning: returning, failed: event.state == .failed)))
                }
            }
        }
        return flights.sorted { $0.date < $1.date }.map(\.flight)
    }
}

/// 以四片轻量三角面绘制折纸，纸飞机沿弧线飞行，航迹在经过后逐段淡出。
@MainActor
private func officePaperPlane(from start: SCNVector3, to end: SCNVector3, color: NSColor) -> SCNNode {
    let flight = SCNNode()
    flight.name = "office-tool-flight"
    let source = SCNGeometrySource(vertices: [
        SCNVector3(0, 0, 0.58), SCNVector3(-0.44, 0.04, -0.32), SCNVector3(-0.08, 0, -0.18),
        SCNVector3(0.44, 0.04, -0.32), SCNVector3(0.08, 0, -0.18), SCNVector3(0, -0.11, -0.42)
    ])
    let facets: [[Int32]] = [[0, 1, 2], [0, 4, 3], [0, 2, 5], [0, 5, 4]]
    let geometry = SCNGeometry(sources: [source], elements: facets.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
    geometry.materials = [NSColor.white, color, color, color.blended(withFraction: 0.28, of: .gray) ?? color].map { tint in
        let material = SCNMaterial()
        material.diffuse.contents = tint
        material.lightingModel = .constant
        material.isDoubleSided = true
        return material
    }
    let plane = SCNNode(geometry: geometry)
    plane.castsShadow = false
    plane.position = start
    flight.addChildNode(plane)

    let distance = hypot(end.x - start.x, end.z - start.z)
    let seconds = max(0.72, min(1.65, distance / 9))
    let height = min(1.65, 0.62 + distance * 0.055)
    let heading = atan2(end.x - start.x, end.z - start.z)
    plane.eulerAngles = SCNVector3(-atan2(end.y - start.y + 4 * height, distance), heading, 0)
    let count = 16
    var actions: [SCNAction] = []
    for index in 1...count {
        let t = CGFloat(index) / CGFloat(count)
        let position = SCNVector3(start.x + (end.x - start.x) * t,
                                  start.y + (end.y - start.y) * t + 4 * height * t * (1 - t),
                                  start.z + (end.z - start.z) * t)
        let pitch = -atan2(end.y - start.y + 4 * height * (1 - 2 * t), distance)
        let step = seconds / Double(count)
        actions.append(.group([
            .move(to: position, duration: step),
            .rotateTo(x: pitch, y: heading, z: sin(t * .pi) * 0.12, duration: step, usesShortestUnitArc: true)
        ]))
        if index % 2 == 0 && index < count {
            let trace = officeNode(SCNBox(width: 0.034, height: 0.024, length: 0.34, chamferRadius: 0.01), color: color, at: position)
            trace.castsShadow = false
            trace.opacity = 0
            trace.geometry?.firstMaterial?.lightingModel = .constant
            trace.eulerAngles = SCNVector3(pitch, heading, 0)
            flight.addChildNode(trace)
            trace.runAction(.sequence([.wait(duration: seconds * Double(t)), .fadeOpacity(to: 0.7, duration: 0.04), .fadeOut(duration: 0.34)]))
        }
    }
    plane.runAction(.sequence(actions + [.fadeOut(duration: 0.15)]))
    flight.runAction(.sequence([.wait(duration: seconds + 0.40), .removeFromParentNode()]))
    return flight
}

/// 人物衣服与部门标牌共享柔和的六色调色盘。
private enum OfficePalette {
    static let shirts = [0x538B7A, 0xD2995F, 0x6E8FA8, 0xAE7E8C, 0x8D89AD, 0xB1A16A].map(NSColor.init(officeHex:))
}

extension CodexOfficeStatus {
    /// 颜色与动作、文字三重表达状态，避免只靠颜色判断。
    var officeColor: NSColor {
        switch self {
        case .working: return NSColor(officeHex: 0x347B62)
        case .thinking: return NSColor(officeHex: 0x627DA3)
        case .waiting: return NSColor(officeHex: 0xC18A27)
        case .completed: return NSColor(officeHex: 0x4F9565)
        case .failed: return NSColor(officeHex: 0xBF6258)
        case .idle: return NSColor(officeHex: 0x888D88)
        }
    }
}

extension NSColor {
    /// 场景使用固定 sRGB 色值，不依赖系统强调色或当前外观。
    convenience init(officeHex: Int) {
        self.init(srgbRed: CGFloat((officeHex >> 16) & 255) / 255, green: CGFloat((officeHex >> 8) & 255) / 255, blue: CGFloat(officeHex & 255) / 255, alpha: 1)
    }
}

/// 创建共享风格的圆角几何体；材质使用漫反射以保持低成本的黏土质感。
@MainActor
func officeNode(_ geometry: SCNGeometry, color: NSColor, at position: SCNVector3) -> SCNNode {
    let material = SCNMaterial()
    material.diffuse.contents = color
    material.lightingModel = .lambert
    geometry.materials = [material]
    let node = SCNNode(geometry: geometry)
    node.position = position
    return node
}

/// 家具共用小倒角，长度参数以米为近似单位，不加载额外模型资源。
@MainActor
func officeBox(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat, color: Int, at position: SCNVector3) -> SCNNode {
    officeNode(SCNBox(width: width, height: height, length: length, chamferRadius: min(0.045, min(width, min(height, length)) / 3)), color: NSColor(officeHex: color), at: position)
}

/// 盆栽使用少量球体和圆锥，给公共区与部门提供方向参照。
@MainActor
func officePlant(at position: SCNVector3) -> SCNNode {
    let plant = SCNNode()
    plant.position = position
    plant.addChildNode(officeNode(SCNCone(topRadius: 0.25, bottomRadius: 0.19, height: 0.42), color: NSColor(officeHex: 0xC39473), at: SCNVector3(0, 0.22, 0)))
    plant.addChildNode(officeNode(SCNCylinder(radius: 0.035, height: 0.72), color: NSColor(officeHex: 0x7F8060), at: SCNVector3(0, 0.65, 0)))
    for (x, y, z): (CGFloat, CGFloat, CGFloat) in [(-0.18, 0.9, 0), (0.15, 1.1, 0.04), (0, 1.35, 0)] {
        plant.addChildNode(officeNode(SCNSphere(radius: 0.31), color: NSColor(officeHex: 0x668E62), at: SCNVector3(x, y, z)))
    }
    return plant
}

/// 绘制朝向镜头的一次性纹理。有状态时按人物名牌排版，长昵称优先缩略以保留完整状态。
@MainActor
func officeLabel(_ text: String, color: NSColor, width: CGFloat, height: CGFloat, status: String? = nil, dark: Bool = false) -> SCNNode {
    let badge = status != nil
    let density: CGFloat = 180
    let textureHeight = height * density
    let font = NSFont.systemFont(ofSize: textureHeight * (badge ? 0.54 : 0.43), weight: .semibold)
    let inset = badge ? textureHeight * 0.67 : 10
    let trailing = badge ? textureHeight * 0.26 : 12
    let labelText = text as NSString
    let statusFont = NSFont.systemFont(ofSize: textureHeight * 0.46, weight: .medium)
    let statusText = status.map { $0 as NSString }
    let statusWidth = statusText.map { ceil($0.size(withAttributes: [.font: statusFont]).width) + 2 } ?? 0
    let statusSpace = badge ? statusWidth + textureHeight * 0.19 : 0
    let nameWidth = labelText.size(withAttributes: [.font: font]).width
    let textureWidth = badge ? min(width * density, ceil(inset + nameWidth + statusSpace + trailing)) : width * density
    let size = NSSize(width: textureWidth, height: textureHeight)
    let image = NSImage(size: size)
    image.lockFocus()
    let radius: CGFloat = badge ? size.height / 2 : 12
    let background = NSColor(officeHex: badge || dark ? 0x172830 : 0xFFFEF7)
    background.withAlphaComponent(0.95).setFill()
    let bounds = NSRect(origin: .zero, size: size)
    let pill = NSBezierPath(roundedRect: badge ? bounds.insetBy(dx: 1, dy: 1) : bounds, xRadius: radius, yRadius: radius)
    pill.fill()
    if badge {
        NSColor.white.withAlphaComponent(0.16).setStroke()
        pill.lineWidth = 2
        pill.stroke()
        let diameter = size.height * 0.27
        let frame = NSRect(x: size.height * 0.23, y: (size.height - diameter) / 2, width: diameter, height: diameter)
        (color.blended(withFraction: 0.16, of: .white) ?? color).setFill()
        NSBezierPath(ovalIn: frame).fill()
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = badge ? .left : .center
    paragraph.lineBreakMode = badge ? .byTruncatingMiddle : .byTruncatingTail
    let foreground = dark ? color.blended(withFraction: 0.65, of: .white) ?? .white : color
    labelText.draw(in: NSRect(x: inset, y: (size.height - font.boundingRectForFont.height) / 2,
                             width: size.width - inset - statusSpace - trailing, height: font.boundingRectForFont.height + 4),
                   withAttributes: [.font: font, .foregroundColor: badge ? NSColor.white : foreground, .paragraphStyle: paragraph])
    if let statusText {
        statusText.draw(in: NSRect(x: size.width - trailing - statusWidth,
                                   y: (size.height - statusFont.boundingRectForFont.height) / 2,
                                   width: statusWidth, height: statusFont.boundingRectForFont.height + 4),
                        withAttributes: [.font: statusFont, .foregroundColor: NSColor(officeHex: 0xB7C6D1)])
    }
    image.unlockFocus()
    let plane = SCNPlane(width: size.width / density, height: height)
    plane.firstMaterial?.diffuse.contents = image
    plane.firstMaterial?.lightingModel = .constant
    plane.firstMaterial?.isDoubleSided = true
    let label = SCNNode(geometry: plane)
    label.castsShadow = false
    label.constraints = [SCNBillboardConstraint()]
    return label
}
