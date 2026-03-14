extends SceneTree


func _init() -> void:
    var scene_path := "res://coop_mod/avatar_assets/rigged_default/low_poly_character.glb"
    var resource := load(scene_path)
    print("resource:", resource)
    print("type:", resource.get_class() if resource != null else "null")
    if resource is PackedScene:
        var inst: Node = resource.instantiate()
        _dump(inst, 0)
        inst.free()
    quit()


func _dump(node: Node, depth: int) -> void:
    var indent := "  ".repeat(depth)
    print(indent, node.name, " [", node.get_class(), "]")
    if node is Node3D:
        print(indent, "  pos:", node.position, " rot:", node.rotation_degrees, " scale:", node.scale)
    if node is MeshInstance3D:
        print(indent, "  visible:", node.visible, " mesh:", node.mesh, " materials:", node.get_surface_override_material_count())
        print(indent, "  aabb:", node.get_aabb())
    if node is Skeleton3D:
        print(indent, "  bones:", node.get_bone_count())
        for bone_index in range(node.get_bone_count()):
            print(indent, "   - ", bone_index, ": ", node.get_bone_name(bone_index))
    for child in node.get_children():
        _dump(child, depth + 1)
