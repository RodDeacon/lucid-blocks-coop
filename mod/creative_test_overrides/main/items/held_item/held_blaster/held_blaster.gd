class_name HeldBlaster extends HeldItem

@export var blast_scene: PackedScene


func interact(sustain: bool = false, data: Dictionary = {}) -> bool:
    super.interact(sustain, data)

    var blast: Blast = blast_scene.instantiate()
    blast.position = holder.hand.global_position
    get_tree().get_root().add_child(blast)
    blast.shoot(holder.velocity, holder.get_look_direction())
    _sync_visual_blast(blast)
    holder.decrease_held_item_durability(1)

    var new_player: AudioStreamPlayer3D = %BurstPlayer.duplicate()
    new_player.finished.connect(new_player.queue_free)
    get_tree().get_root().add_child(new_player)
    new_player.global_position = holder.hand.global_position
    new_player.play()

    return true


func _sync_visual_blast(blast: Blast) -> void:
    if Ref.coop_manager == null:
        return
    if not Ref.coop_manager.has_active_session():
        return
    if multiplayer.is_server():
        if Ref.coop_manager.is_remote_player_proxy(holder):
            return
        if Ref.coop_manager.has_method("broadcast_host_visual_blast"):
            Ref.coop_manager.call("broadcast_host_visual_blast", blast.global_position, holder.velocity, holder.get_look_direction())
        return
    if holder == Ref.player and Ref.coop_manager.has_method("send_guest_visual_blast"):
        Ref.coop_manager.call("send_guest_visual_blast", blast.global_position, holder.velocity, holder.get_look_direction())


func can_interact(_data: Dictionary) -> bool:
    return true
