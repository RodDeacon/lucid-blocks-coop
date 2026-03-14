extends Node


const CONFIG_PATH: String = "user://lucid_blocks_coop_config.json"
const DEFAULT_PORT: int = 24567
const MAX_CLIENTS: int = 4
const SEND_INTERVAL: float = 0.05
const PANEL_WIDTH: float = 224.0
const SNAPSHOT_CHUNK_SIZE: int = 60000
const DEFAULT_AVATAR_ID: String = "default_blocky"


var config: Dictionary = {
    "address": "127.0.0.1",
    "port": DEFAULT_PORT,
    "avatar_id": DEFAULT_AVATAR_ID,
}

var peer_states: Dictionary = {}
var markers: Dictionary = {}
var send_timer: float = 0.0
var status_message: String = "Idle"
var panel_visible: bool = false
var restore_capture_on_close: bool = false
var receiving_host_world: bool = false
var incoming_snapshot_register_json: String = ""
var incoming_snapshot_chunk_count: int = 0
var incoming_snapshot_chunks: Dictionary = {}
var incoming_snapshot_host_position: Vector3 = Vector3.ZERO

var hud: CanvasLayer
var overlay: Control
var panel: PanelContainer
var local_ip_label: Label
var status_label: Label
var address_input: LineEdit
var port_input: SpinBox
var command_input: LineEdit


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _load_config()
    _build_hud()

    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)

    print("[lucid-blocks-coop] manager ready")
    _update_status_text()


func _input(event: InputEvent) -> void:
    if not (event is InputEventKey):
        return
    if not event.pressed or event.echo:
        return

    match event.keycode:
        KEY_F5:
            toggle_panel()
        KEY_F6:
            host_session()
        KEY_F7:
            if event.shift_pressed:
                _load_config(true)
            else:
                join_session()
        KEY_F8:
            disconnect_session()
        KEY_F9:
            teleport_to_connected_player()


func _physics_process(delta: float) -> void:
    if not _has_live_peer():
        _hide_all_markers()
        return

    send_timer += delta
    if send_timer < SEND_INTERVAL:
        return
    send_timer = 0.0

    var local_state: Dictionary = _capture_local_state()
    if multiplayer.is_server():
        peer_states[1] = local_state
        _refresh_markers(peer_states, multiplayer.get_unique_id())
        server_snapshot.rpc(_serialize_peer_states())
    else:
        submit_client_state.rpc_id(
            1,
            local_state.get("active", false),
            local_state.get("dimension", -1),
            local_state.get("position", Vector3.ZERO),
            local_state.get("yaw", 0.0),
            local_state.get("pitch", 0.0),
            local_state.get("crouching", false),
            local_state.get("grounded", true),
            local_state.get("move_speed", 0.0),
            local_state.get("held_item_id", -1),
            local_state.get("action_state", 0),
            str(local_state.get("name", "guest")),
            str(local_state.get("avatar_id", DEFAULT_AVATAR_ID)),
            local_state.get("skin_color", Color.WHITE)
        )


func toggle_panel(force_visible: Variant = null) -> void:
    var next_visible: bool = not panel_visible if force_visible == null else bool(force_visible)
    if next_visible == panel_visible:
        return

    panel_visible = next_visible
    panel.visible = panel_visible

    if panel_visible:
        restore_capture_on_close = MouseHandler.captured
        MouseHandler.release()
        _refresh_local_ip_label()
        _sync_inputs_from_config()
        address_input.grab_focus()
        address_input.caret_column = address_input.text.length()
    else:
        _apply_ui_to_config()
        get_viewport().gui_release_focus()
        if restore_capture_on_close:
            MouseHandler.capture()

    _update_status_text()


func host_session() -> void:
    if not _can_share_loaded_world():
        status_message = "Open LAN from inside a loaded world"
        _update_status_text()
        return

    _apply_ui_to_config()
    disconnect_session(false)

    var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
    var err: Error = peer.create_server(int(config.get("port", DEFAULT_PORT)), MAX_CLIENTS)
    if err != OK:
        status_message = "Host failed (%s)" % err
        push_warning("[lucid-blocks-coop] host failed: %s" % err)
        _update_status_text()
        return

    multiplayer.multiplayer_peer = peer
    peer_states.clear()
    status_message = "Hosting on port %s" % int(config.get("port", DEFAULT_PORT))
    print("[lucid-blocks-coop] %s" % status_message)
    _update_status_text()


func join_session() -> void:
    _apply_ui_to_config()
    disconnect_session(false)

    var address: String = str(config.get("address", "127.0.0.1")).strip_edges()
    var port: int = int(config.get("port", DEFAULT_PORT))
    var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
    var err: Error = peer.create_client(address, port)
    if err != OK:
        status_message = "Join failed (%s)" % err
        push_warning("[lucid-blocks-coop] join failed: %s" % err)
        _update_status_text()
        return

    multiplayer.multiplayer_peer = peer
    peer_states.clear()
    status_message = "Joining %s:%s" % [address, port]
    print("[lucid-blocks-coop] %s" % status_message)
    _update_status_text()


func disconnect_session(announce: bool = true) -> void:
    if multiplayer.multiplayer_peer != null:
        multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

    peer_states.clear()
    _clear_markers()
    send_timer = 0.0

    if announce:
        status_message = "Disconnected"
        print("[lucid-blocks-coop] disconnected")
    else:
        status_message = "Idle"

    _update_status_text()


func _has_live_peer() -> bool:
    return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func has_active_session() -> bool:
    return _has_live_peer()


func teleport_to_connected_player() -> void:
    if not _can_sample_player():
        return

    var target_peer_id: int = -1
    var target_state: Dictionary = {}
    for peer_id in peer_states.keys():
        var int_peer_id: int = int(peer_id)
        if int_peer_id == multiplayer.get_unique_id():
            continue

        var state: Dictionary = peer_states[peer_id]
        if not bool(state.get("active", false)):
            continue
        if int(state.get("dimension", -1)) != int(Ref.world.current_dimension):
            continue

        target_peer_id = int_peer_id
        target_state = state
        break

    if target_peer_id == -1:
        status_message = "No connected player to teleport to"
        _update_status_text()
        return

    _teleport_local_player_near(target_state.get("position", Ref.player.global_position))
    status_message = "Teleported to peer %s" % target_peer_id
    _update_status_text()


func execute_command(raw_text: String) -> void:
    var text: String = raw_text.strip_edges()
    if text == "":
        return

    var parts: PackedStringArray = text.split(" ", false)
    var command: String = parts[0].to_lower()

    match command:
        "/tp":
            _execute_tp_command(parts)
        "/host", "/lan":
            if parts.size() >= 2 and parts[1].is_valid_int():
                config["port"] = clampi(int(parts[1]), 1, 65535)
                _sync_inputs_from_config()
            host_session()
        "/join":
            if parts.size() >= 2:
                config["address"] = parts[1]
            if parts.size() >= 3 and parts[2].is_valid_int():
                config["port"] = clampi(int(parts[2]), 1, 65535)
            _sync_inputs_from_config()
            join_session()
        "/avatar":
            if parts.size() < 2:
                status_message = "Usage: /avatar <id>"
            else:
                config["avatar_id"] = _normalize_avatar_id(parts[1])
                _save_config()
                status_message = "Avatar set to %s" % config["avatar_id"]
            _update_status_text()
        _:
            status_message = "Unknown command: %s" % text
            _update_status_text()


func _execute_tp_command(parts: PackedStringArray) -> void:
    if parts.size() < 2:
        status_message = "Usage: /tp host or /tp <peer>"
        _update_status_text()
        return

    var query: String = " ".join(parts.slice(1)).strip_edges()
    var target_peer_id: int = -1
    var target_state: Dictionary = {}

    for peer_id in peer_states.keys():
        var int_peer_id: int = int(peer_id)
        if int_peer_id == multiplayer.get_unique_id():
            continue

        var state: Dictionary = peer_states[peer_id]
        var peer_name: String = str(state.get("name", "Peer %s" % int_peer_id))
        if query.to_lower() == "host" and int_peer_id == 1:
            target_peer_id = int_peer_id
            target_state = state
            break
        if query.to_lower() == ("p%s" % int_peer_id).to_lower() or query == str(int_peer_id) or peer_name.to_lower() == query.to_lower() or peer_name.to_lower().contains(query.to_lower()):
            target_peer_id = int_peer_id
            target_state = state
            break

    if target_peer_id == -1:
        status_message = "Peer not found: %s" % query
        _update_status_text()
        return

    if int(target_state.get("dimension", -1)) != int(Ref.world.current_dimension):
        status_message = "Peer %s is in another dimension" % query
        _update_status_text()
        return

    _teleport_local_player_near(target_state.get("position", Ref.player.global_position))
    status_message = "Teleported to %s" % str(target_state.get("name", "peer %s" % target_peer_id))
    _update_status_text()


func sync_local_block_place(block_position: Vector3i, block_id: int, inventory, inventory_index: int) -> bool:
    if not _has_live_peer():
        return false

    if multiplayer.is_server():
        _apply_network_place(block_position, block_id)
        if inventory != null:
            inventory.change_amount(inventory_index, -1)
        sync_place_block.rpc(block_position, block_id)
        return true

    if inventory != null:
        inventory.change_amount(inventory_index, -1)
    request_place_block.rpc_id(1, block_position, block_id)
    status_message = "Requested place at %s" % block_position
    _update_status_text()
    return true


func sync_local_block_break(break_behavior, block_position: Vector3i) -> bool:
    if not _has_live_peer():
        return false
    if break_behavior == null or break_behavior.entity != Ref.player:
        return false
    if multiplayer.is_server():
        return false

    _apply_client_break_feedback(break_behavior, block_position)
    request_break_block.rpc_id(1, block_position)
    status_message = "Requested break at %s" % block_position
    _update_status_text()
    return true


func broadcast_host_block_break(block_position: Vector3i) -> void:
    if not _has_live_peer() or not multiplayer.is_server():
        return
    sync_break_block.rpc(block_position)


func _can_share_loaded_world() -> bool:
    return is_instance_valid(Ref.main) and is_instance_valid(Ref.world) and Ref.main.loaded and Ref.world.load_enabled and Ref.save_file_manager.loaded_file_register != null and Ref.save_file_manager.loaded_file != null


func _capture_local_state() -> Dictionary:
    var state: Dictionary = {
        "active": false,
        "dimension": -1,
        "position": Vector3.ZERO,
        "yaw": 0.0,
        "pitch": 0.0,
        "crouching": false,
        "grounded": true,
        "move_speed": 0.0,
        "held_item_id": -1,
        "action_state": 0,
        "name": _get_local_player_name(),
        "avatar_id": _normalize_avatar_id(str(config.get("avatar_id", DEFAULT_AVATAR_ID))),
        "skin_color": _get_local_skin_color(),
    }

    if not _can_sample_player():
        return state

    var rotation_pivot: Node3D = _get_rotation_pivot()
    var camera: Camera3D = Ref.player.get_node_or_null("%Camera3D") as Camera3D
    state["active"] = true
    state["dimension"] = int(Ref.world.current_dimension)
    state["position"] = Ref.player.global_position
    state["yaw"] = rotation_pivot.rotation.y if rotation_pivot != null else Ref.player.rotation.y
    state["pitch"] = camera.rotation.x if camera != null else 0.0
    state["crouching"] = Ref.player.is_crouching
    state["grounded"] = not Ref.player.in_air
    state["move_speed"] = Vector3(Ref.player.velocity.x, 0.0, Ref.player.velocity.z).length()
    var held_item_state = Ref.player.held_item_inventory.items[Ref.player.held_item_index]
    state["held_item_id"] = held_item_state.id if held_item_state != null else -1
    state["action_state"] = _get_local_action_state()
    return state


func _normalize_avatar_id(raw_avatar_id: String) -> String:
    var normalized: String = raw_avatar_id.strip_edges().to_lower()
    return normalized if normalized != "" else DEFAULT_AVATAR_ID


func _get_local_player_name() -> String:
    var steam_name: String = str(Steamworks.get_username())
    if steam_name.strip_edges() != "":
        return steam_name
    return "Peer %s" % multiplayer.get_unique_id()


func _get_local_skin_color() -> Color:
    if Ref.save_file_manager == null or Ref.save_file_manager.settings_file == null:
        return Color.WHITE
    return Ref.save_file_manager.settings_file.get_data("skin_modulate", Color.WHITE)


func _get_local_action_state() -> int:
    var player_hand = Ref.player.get_node_or_null("%PlayerHand")
    if player_hand == null or player_hand.current_hand == null:
        return 0
    return int(player_hand.current_hand.state)


func _can_sample_player() -> bool:
    return is_instance_valid(Ref.main) and is_instance_valid(Ref.world) and is_instance_valid(Ref.player) and Ref.main.loaded and Ref.world.load_enabled


func _get_rotation_pivot() -> Node3D:
    return Ref.player.get_node_or_null("%RotationPivot") as Node3D


func _serialize_peer_states() -> Array:
    var snapshot: Array = []
    for peer_id in peer_states.keys():
        var state: Dictionary = peer_states[peer_id]
        snapshot.append([
            int(peer_id),
            bool(state.get("active", false)),
            int(state.get("dimension", -1)),
            state.get("position", Vector3.ZERO),
            float(state.get("yaw", 0.0)),
            float(state.get("pitch", 0.0)),
            bool(state.get("crouching", false)),
            bool(state.get("grounded", true)),
            float(state.get("move_speed", 0.0)),
            int(state.get("held_item_id", -1)),
            int(state.get("action_state", 0)),
            str(state.get("name", "Peer %s" % int(peer_id))),
            str(state.get("avatar_id", DEFAULT_AVATAR_ID)),
            state.get("skin_color", Color.WHITE),
        ])
    return snapshot


func _refresh_markers(states: Dictionary, local_peer_id: int) -> void:
    var visible_ids: Dictionary = {}
    for peer_id in states.keys():
        var int_peer_id: int = int(peer_id)
        if int_peer_id == local_peer_id:
            continue

        visible_ids[int_peer_id] = true
        var state: Dictionary = states[peer_id]
        var marker: Node = _ensure_marker(int_peer_id)
        marker.set_avatar_id(str(state.get("avatar_id", DEFAULT_AVATAR_ID)))
        marker.set_display_name(str(state.get("name", "Peer %s" % int_peer_id)))
        marker.set_held_item_id(int(state.get("held_item_id", -1)))
        marker.set_skin_color(state.get("skin_color", Color.WHITE))
        var same_dimension: bool = _can_sample_player() and int(state.get("dimension", -1)) == int(Ref.world.current_dimension)
        marker.apply_state(
            bool(state.get("active", false)) and same_dimension,
            state.get("position", Vector3.ZERO),
            float(state.get("yaw", 0.0)),
            float(state.get("pitch", 0.0)),
            bool(state.get("crouching", false)),
            bool(state.get("grounded", true)),
            float(state.get("move_speed", 0.0)),
            int(state.get("action_state", 0))
        )

    for peer_id in markers.keys().duplicate():
        if not visible_ids.has(peer_id):
            markers[peer_id].queue_free()
            markers.erase(peer_id)


func _ensure_marker(peer_id: int) -> Node:
    if markers.has(peer_id):
        return markers[peer_id]

    var marker_script: GDScript = load("res://coop_mod/remote_player_marker.gd")
    var marker: Node = marker_script.new()
    marker.name = "RemotePeer%s" % peer_id
    add_child(marker)
    marker.setup(peer_id)
    markers[peer_id] = marker
    return marker


func _clear_markers() -> void:
    for peer_id in markers.keys():
        markers[peer_id].queue_free()
    markers.clear()


func _hide_all_markers() -> void:
    for peer_id in markers.keys():
        markers[peer_id].visible = false


func _build_hud() -> void:
    hud = CanvasLayer.new()
    hud.layer = 64
    add_child(hud)

    overlay = Control.new()
    overlay.anchor_right = 1.0
    overlay.anchor_bottom = 1.0
    overlay.offset_left = 0.0
    overlay.offset_top = 0.0
    overlay.offset_right = 0.0
    overlay.offset_bottom = 0.0
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hud.add_child(overlay)

    panel = PanelContainer.new()
    panel.visible = false
    panel.anchor_left = 0.5
    panel.anchor_right = 0.5
    panel.offset_left = -PANEL_WIDTH * 0.5
    panel.offset_right = PANEL_WIDTH * 0.5
    panel.offset_top = 12
    panel.offset_bottom = 194
    panel.clip_contents = true
    overlay.add_child(panel)

    var outer_margin: MarginContainer = MarginContainer.new()
    outer_margin.add_theme_constant_override("margin_left", 8)
    outer_margin.add_theme_constant_override("margin_right", 8)
    outer_margin.add_theme_constant_override("margin_top", 8)
    outer_margin.add_theme_constant_override("margin_bottom", 8)
    panel.add_child(outer_margin)

    var column: VBoxContainer = VBoxContainer.new()
    column.add_theme_constant_override("separation", 6)
    outer_margin.add_child(column)

    var title_row: HBoxContainer = HBoxContainer.new()
    title_row.add_theme_constant_override("separation", 6)
    column.add_child(title_row)

    var title: Label = Label.new()
    title.text = "Lucid Co-op"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 12)
    title_row.add_child(title)

    var close_button: Button = Button.new()
    close_button.text = "x"
    close_button.custom_minimum_size = Vector2(24, 0)
    close_button.add_theme_font_size_override("font_size", 10)
    close_button.pressed.connect(toggle_panel.bind(false))
    title_row.add_child(close_button)

    var help: Label = Label.new()
    help.text = "Minecraft-style LAN: host opens the current world. F5 closes. F9 or /tp teleports, /avatar changes your shared avatar id."
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    help.add_theme_font_size_override("font_size", 9)
    column.add_child(help)

    local_ip_label = Label.new()
    local_ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    local_ip_label.add_theme_font_size_override("font_size", 10)
    column.add_child(local_ip_label)

    var address_title: Label = Label.new()
    address_title.text = "Join IP"
    address_title.add_theme_font_size_override("font_size", 10)
    column.add_child(address_title)

    address_input = LineEdit.new()
    address_input.placeholder_text = "192.168.x.x"
    address_input.text = str(config.get("address", "127.0.0.1"))
    address_input.custom_minimum_size = Vector2(0, 22)
    address_input.add_theme_font_size_override("font_size", 10)
    address_input.text_changed.connect(_on_address_changed)
    address_input.text_submitted.connect(_on_join_text_submitted)
    column.add_child(address_input)

    var port_row: HBoxContainer = HBoxContainer.new()
    port_row.add_theme_constant_override("separation", 6)
    column.add_child(port_row)

    var port_title: Label = Label.new()
    port_title.text = "Port"
    port_title.custom_minimum_size = Vector2(34, 0)
    port_title.add_theme_font_size_override("font_size", 10)
    port_row.add_child(port_title)

    port_input = SpinBox.new()
    port_input.min_value = 1
    port_input.max_value = 65535
    port_input.step = 1
    port_input.rounded = true
    port_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    port_input.custom_minimum_size = Vector2(0, 22)
    port_input.add_theme_font_size_override("font_size", 10)
    port_input.value = int(config.get("port", DEFAULT_PORT))
    port_input.value_changed.connect(_on_port_changed)
    port_row.add_child(port_input)

    var button_row: HBoxContainer = HBoxContainer.new()
    button_row.add_theme_constant_override("separation", 6)
    column.add_child(button_row)

    var host_button: Button = Button.new()
    host_button.text = "Host"
    host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    host_button.add_theme_font_size_override("font_size", 10)
    host_button.pressed.connect(host_session)
    button_row.add_child(host_button)

    var join_button: Button = Button.new()
    join_button.text = "Join"
    join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    join_button.add_theme_font_size_override("font_size", 10)
    join_button.pressed.connect(join_session)
    button_row.add_child(join_button)

    var disconnect_button: Button = Button.new()
    disconnect_button.text = "Leave"
    disconnect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    disconnect_button.add_theme_font_size_override("font_size", 10)
    disconnect_button.pressed.connect(disconnect_session)
    button_row.add_child(disconnect_button)

    command_input = LineEdit.new()
    command_input.placeholder_text = "/tp host  /avatar default_blocky"
    command_input.custom_minimum_size = Vector2(0, 22)
    command_input.add_theme_font_size_override("font_size", 10)
    command_input.text_submitted.connect(_on_command_submitted)
    column.add_child(command_input)

    status_label = Label.new()
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status_label.custom_minimum_size = Vector2(0, 40)
    status_label.add_theme_font_size_override("font_size", 9)
    column.add_child(status_label)

    _refresh_local_ip_label()
    _sync_inputs_from_config()


func _refresh_local_ip_label() -> void:
    if local_ip_label == null:
        return

    var best_ip: String = _get_best_local_ipv4()
    local_ip_label.text = "Host IP: %s" % best_ip


func _get_best_local_ipv4() -> String:
    var best_ip: String = "127.0.0.1"
    var best_score: int = 999

    for address in IP.get_local_addresses():
        if ":" in address:
            continue
        if address.begins_with("127."):
            continue

        var score: int = _score_ipv4(address)
        if score < best_score:
            best_score = score
            best_ip = address

    return best_ip


func _score_ipv4(address: String) -> int:
    if address.begins_with("192.168."):
        return 0
    if address.begins_with("10."):
        return 1
    if address.begins_with("172."):
        var second_octet_text: String = address.get_slice(".", 1)
        var second_octet: int = int(second_octet_text)
        if second_octet >= 16 and second_octet <= 31:
            if second_octet == 17 or second_octet == 18:
                return 4
            return 2
    if address.begins_with("100."):
        return 3
    return 5


func _sync_inputs_from_config() -> void:
    if address_input != null:
        address_input.text = str(config.get("address", "127.0.0.1"))
    if port_input != null:
        port_input.value = int(config.get("port", DEFAULT_PORT))


func _apply_ui_to_config() -> void:
    var normalized_address: String = str(config.get("address", "127.0.0.1"))
    var normalized_port: int = int(config.get("port", DEFAULT_PORT))

    if address_input != null:
        var address: String = address_input.text.strip_edges()
        normalized_address = address if address != "" else "127.0.0.1"
    if port_input != null:
        normalized_port = clampi(int(port_input.value), 1, 65535)

    config["address"] = normalized_address
    config["port"] = normalized_port
    _save_config()

    if address_input != null and address_input.text != normalized_address:
        address_input.text = normalized_address
    if port_input != null and int(port_input.value) != normalized_port:
        port_input.value = normalized_port


func _on_address_changed(_new_text: String) -> void:
    _apply_ui_to_config()
    _update_status_text()


func _on_join_text_submitted(_new_text: String) -> void:
    join_session()


func _on_command_submitted(command_text: String) -> void:
    execute_command(command_text)
    if command_input != null:
        command_input.clear()


func _on_port_changed(_new_value: float) -> void:
    _apply_ui_to_config()
    _update_status_text()


func _update_status_text() -> void:
    if status_label == null:
        return

    var mode: String = "offline"
    if _has_live_peer():
        mode = "host" if multiplayer.is_server() else "client"

    var peers: int = peer_states.size()
    if peer_states.has(multiplayer.get_unique_id()):
        peers -= 1
    peers = max(peers, 0)

    status_label.text = "Status: %s\nMode: %s\nJoin target: %s:%s\nVisible peers: %s" % [
        status_message,
        mode,
        str(config.get("address", "127.0.0.1")),
        int(config.get("port", DEFAULT_PORT)),
        peers,
    ]


func _load_config(announce: bool = false) -> void:
    config = {
        "address": "127.0.0.1",
        "port": DEFAULT_PORT,
        "avatar_id": DEFAULT_AVATAR_ID,
    }

    if not FileAccess.file_exists(CONFIG_PATH):
        _save_config()
        if announce:
            status_message = "Created config at %s" % OS.get_user_data_dir().path_join("lucid_blocks_coop_config.json")
            _sync_inputs_from_config()
            _update_status_text()
        return

    var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
    if file == null:
        return

    var data: Variant = JSON.parse_string(file.get_as_text())
    if data is Dictionary:
        config.merge(data, true)
    config["avatar_id"] = _normalize_avatar_id(str(config.get("avatar_id", DEFAULT_AVATAR_ID)))

    _sync_inputs_from_config()
    _refresh_local_ip_label()

    if announce:
        status_message = "Reloaded config"
        print("[lucid-blocks-coop] reloaded config: %s" % config)
        _update_status_text()


func _save_config() -> void:
    var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
    if file == null:
        return
    file.store_string(JSON.stringify(config, "  "))


func _on_peer_connected(id: int) -> void:
    status_message = "Peer %s connected" % id
    print("[lucid-blocks-coop] %s" % status_message)
    _update_status_text()


func _on_peer_disconnected(id: int) -> void:
    peer_states.erase(id)
    if markers.has(id):
        markers[id].queue_free()
        markers.erase(id)
    status_message = "Peer %s disconnected" % id
    print("[lucid-blocks-coop] %s" % status_message)
    _update_status_text()


func _on_connected_to_server() -> void:
    status_message = "Connected as peer %s, waiting for host world" % multiplayer.get_unique_id()
    print("[lucid-blocks-coop] %s" % status_message)
    _update_status_text()
    request_host_world_snapshot.rpc_id(1)


func _on_connection_failed() -> void:
    disconnect_session(false)
    status_message = "Connection failed"
    push_warning("[lucid-blocks-coop] connection failed")
    _update_status_text()


func _on_server_disconnected() -> void:
    disconnect_session(false)
    status_message = "Server disconnected"
    print("[lucid-blocks-coop] %s" % status_message)
    _update_status_text()


func _teleport_local_player_near(target_position: Vector3) -> void:
    if not _can_sample_player():
        return

    Ref.player.global_position = target_position + Vector3(1.5, 0.0, 0.0)
    Ref.player.movement_velocity = Vector3.ZERO
    Ref.player.gravity_velocity = Vector3.ZERO
    Ref.player.knockback_velocity = Vector3.ZERO
    Ref.player.rope_velocity = Vector3.ZERO


func _send_world_snapshot_to_peer(peer_id: int) -> void:
    if not _can_share_loaded_world():
        return

    status_message = "Sending world to peer %s" % peer_id
    _update_status_text()

    await Ref.save_file_manager.save_file(false)

    var register_json: String = JSON.stringify(JSON.from_native(Ref.save_file_manager.loaded_file_register.data))
    var save_json: String = JSON.stringify(JSON.from_native(Ref.save_file_manager.loaded_file.data))
    var save_buffer: PackedByteArray = save_json.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
    var chunk_count: int = maxi(1, int(ceil(float(save_buffer.size()) / float(SNAPSHOT_CHUNK_SIZE))))

    begin_host_world_snapshot.rpc_id(peer_id, register_json, chunk_count, Ref.player.global_position)
    for chunk_index in range(chunk_count):
        var start: int = chunk_index * SNAPSHOT_CHUNK_SIZE
        var end: int = mini(start + SNAPSHOT_CHUNK_SIZE, save_buffer.size())
        host_world_snapshot_chunk.rpc_id(peer_id, chunk_index, save_buffer.slice(start, end))
    finish_host_world_snapshot.rpc_id(peer_id)

    status_message = "Peer %s joined host world" % peer_id
    _update_status_text()


func _apply_received_host_world() -> void:
    if incoming_snapshot_register_json == "":
        receiving_host_world = false
        return

    for chunk_index in range(incoming_snapshot_chunk_count):
        if not incoming_snapshot_chunks.has(chunk_index):
            status_message = "Missing world chunk %s" % chunk_index
            receiving_host_world = false
            _update_status_text()
            return

    var compressed_buffer: PackedByteArray = PackedByteArray()
    for chunk_index in range(incoming_snapshot_chunk_count):
        compressed_buffer.append_array(incoming_snapshot_chunks[chunk_index])

    var save_json: String = compressed_buffer.decompress_dynamic(4000000000, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
    var register_parse: Variant = JSON.parse_string(incoming_snapshot_register_json)
    var save_parse: Variant = JSON.parse_string(save_json)
    if not (register_parse is Dictionary) or not (save_parse is Dictionary):
        status_message = "Failed to parse host world"
        receiving_host_world = false
        _update_status_text()
        return

    await _load_host_world_snapshot(JSON.to_native(register_parse), JSON.to_native(save_parse), incoming_snapshot_host_position)


func _load_host_world_snapshot(register_data: Dictionary, save_data: Dictionary, host_position: Vector3) -> void:
    receiving_host_world = true
    status_message = "Loading host world"
    _update_status_text()

    await Ref.trans.open()

    if Ref.world.load_enabled:
        await Ref.main.quit_game(false, false)

    var register: SaveFileRegister = SaveFileRegister.new()
    register.is_dimensional = false
    register.data = register_data.duplicate_deep()

    var save_file: SaveFile = SaveFile.new()
    save_file.data = save_data.duplicate_deep()

    Ref.save_file_manager.loaded_file_register = register
    Ref.save_file_manager.loaded_file = save_file
    Ref.audio_manager.stop_song(Ref.main.main_menu_music)
    Ref.save_file_manager.load_file(register, false)

    await Ref.main.enter_game()
    _teleport_local_player_near(host_position)

    receiving_host_world = false
    status_message = "Joined host world"
    _update_status_text()


func _apply_network_place(block_position: Vector3i, block_id: int) -> void:
    if not is_instance_valid(Ref.world):
        return
    Ref.world.place_block_at(block_position, ItemMap.map(block_id), true, true)


func _apply_network_break(block_position: Vector3i) -> void:
    if not is_instance_valid(Ref.world):
        return
    var block = Ref.world.get_block_type_at(block_position)
    if block.id == 0 and block.internal_name != "cutscene block":
        return
    Ref.world.break_block_at(block_position, true, false)


func _apply_client_break_feedback(break_behavior, block_position: Vector3i) -> void:
    if break_behavior.entity == null or break_behavior.entity.disabled or not break_behavior.enabled:
        return

    var block = ItemMap.map(Ref.world.get_block_type_at(block_position).id)
    var held_item = break_behavior.entity.held_item_inventory.items[break_behavior.entity.held_item_index]
    if break_behavior.decrease_held_item_durability and not (held_item != null and ItemMap.map(held_item.id).internal_name == "super drill"):
        if block.pickaxe_affinity and break_behavior.pickaxe or block.axe_affinity and break_behavior.axe or block.shovel_affinity and break_behavior.shovel or block.meat_affinity and break_behavior.meat or block.plant_affinity and break_behavior.plant:
            break_behavior.entity.decrease_held_item_durability(1)

    Steamworks.increment_statistic("blocks_broken")


@rpc("any_peer", "call_remote", "unreliable")
func submit_client_state(active: bool, dimension: int, position: Vector3, yaw: float, pitch: float, crouching: bool, grounded: bool, move_speed: float, held_item_id: int, action_state: int, player_name: String, avatar_id: String, skin_color: Color) -> void:
    if not multiplayer.is_server():
        return

    var sender_id: int = multiplayer.get_remote_sender_id()
    if sender_id <= 0:
        return

    peer_states[sender_id] = {
        "active": active,
        "dimension": dimension,
        "position": position,
        "yaw": yaw,
        "pitch": pitch,
        "crouching": crouching,
        "grounded": grounded,
        "move_speed": move_speed,
        "held_item_id": held_item_id,
        "action_state": action_state,
        "name": player_name,
        "avatar_id": _normalize_avatar_id(avatar_id),
        "skin_color": skin_color,
    }
    _refresh_markers(peer_states, multiplayer.get_unique_id())


@rpc("any_peer", "call_remote", "reliable")
func request_place_block(block_position: Vector3i, block_id: int) -> void:
    if not multiplayer.is_server():
        return

    var sender_id: int = multiplayer.get_remote_sender_id()
    if sender_id <= 0:
        return

    _apply_network_place(block_position, block_id)
    sync_place_block.rpc(block_position, block_id)


@rpc("any_peer", "call_remote", "reliable")
func request_host_world_snapshot() -> void:
    if not multiplayer.is_server():
        return

    var sender_id: int = multiplayer.get_remote_sender_id()
    if sender_id <= 0:
        return

    _send_world_snapshot_to_peer.call_deferred(sender_id)


@rpc("authority", "call_remote", "reliable")
func begin_host_world_snapshot(register_json: String, chunk_count: int, host_position: Vector3) -> void:
    if multiplayer.is_server():
        return

    incoming_snapshot_register_json = register_json
    incoming_snapshot_chunk_count = chunk_count
    incoming_snapshot_chunks.clear()
    incoming_snapshot_host_position = host_position
    receiving_host_world = true
    status_message = "Receiving host world (%s chunks)" % chunk_count
    _update_status_text()


@rpc("authority", "call_remote", "reliable")
func host_world_snapshot_chunk(chunk_index: int, data: PackedByteArray) -> void:
    if multiplayer.is_server() or not receiving_host_world:
        return

    incoming_snapshot_chunks[chunk_index] = data
    status_message = "Receiving host world (%s/%s)" % [incoming_snapshot_chunks.size(), incoming_snapshot_chunk_count]
    _update_status_text()


@rpc("authority", "call_remote", "reliable")
func finish_host_world_snapshot() -> void:
    if multiplayer.is_server() or not receiving_host_world:
        return

    _apply_received_host_world.call_deferred()


@rpc("authority", "call_remote", "reliable")
func sync_place_block(block_position: Vector3i, block_id: int) -> void:
    if multiplayer.is_server():
        return
    _apply_network_place(block_position, block_id)


@rpc("any_peer", "call_remote", "reliable")
func request_break_block(block_position: Vector3i) -> void:
    if not multiplayer.is_server():
        return

    var sender_id: int = multiplayer.get_remote_sender_id()
    if sender_id <= 0:
        return

    _apply_network_break(block_position)
    sync_break_block.rpc(block_position)


@rpc("authority", "call_remote", "reliable")
func sync_break_block(block_position: Vector3i) -> void:
    if multiplayer.is_server():
        return
    _apply_network_break(block_position)


@rpc("authority", "call_remote", "unreliable")
func server_snapshot(snapshot: Array) -> void:
    if multiplayer.is_server():
        return

    peer_states.clear()
    for entry in snapshot:
        if not (entry is Array) or entry.size() < 14:
            continue

        peer_states[int(entry[0])] = {
            "active": bool(entry[1]),
            "dimension": int(entry[2]),
            "position": entry[3],
            "yaw": float(entry[4]),
            "pitch": float(entry[5]),
            "crouching": bool(entry[6]),
            "grounded": bool(entry[7]),
            "move_speed": float(entry[8]),
            "held_item_id": int(entry[9]),
            "action_state": int(entry[10]),
            "name": str(entry[11]),
            "avatar_id": _normalize_avatar_id(str(entry[12])),
            "skin_color": entry[13] if entry[13] is Color else Color.WHITE,
        }

    _refresh_markers(peer_states, multiplayer.get_unique_id())
