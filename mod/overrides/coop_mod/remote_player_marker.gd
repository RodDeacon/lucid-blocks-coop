extends Node3D


var peer_id: int = -1
var display_name: String = ""

var body: MeshInstance3D
var label: Label3D


func _ready() -> void:
    top_level = true

    body = MeshInstance3D.new()
    var body_mesh: CapsuleMesh = CapsuleMesh.new()
    body_mesh.radius = 0.22
    body_mesh.mid_height = 0.9
    body.mesh = body_mesh
    body.position = Vector3(0, 0.92, 0)

    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = Color.from_hsv(fposmod(float(peer_id) * 0.17, 1.0), 0.55, 1.0)
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    body.material_override = material
    add_child(body)

    label = Label3D.new()
    label.text = "P%s" % peer_id
    label.position = Vector3(0, 2.05, 0)
    label.no_depth_test = true
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(label)

    visible = false


func setup(new_peer_id: int) -> void:
    peer_id = new_peer_id
    if is_node_ready():
        label.text = display_name if display_name != "" else "P%s" % peer_id
        var material: StandardMaterial3D = body.material_override as StandardMaterial3D
        if material != null:
            material.albedo_color = Color.from_hsv(fposmod(float(peer_id) * 0.17, 1.0), 0.55, 1.0)


func set_display_name(new_display_name: String) -> void:
    display_name = new_display_name.strip_edges()
    if label != null:
        label.text = display_name if display_name != "" else "P%s" % peer_id


func apply_state(active: bool, world_position: Vector3, yaw: float, crouching: bool) -> void:
    if body == null or label == null:
        call_deferred("apply_state", active, world_position, yaw, crouching)
        return

    visible = active
    if not active:
        return

    global_position = world_position
    rotation = Vector3(0, yaw, 0)
    body.scale = Vector3(1, 0.7 if crouching else 1.0, 1)
    label.position = Vector3(0, 1.75 if crouching else 2.05, 0)
