class_name HeldFood extends HeldItem

const COOP_CLIENT_FAST_EAT_TIME_SEC: float = 0.18
const COOP_CLIENT_FAST_EAT_ANIM_SPEED: float = 8.0

var current_eat_sound_effect: AudioStreamPlayer
var is_limiting_speed: bool = false
var eating_sounds_disabled: bool = false

func _ready() -> void :
    super._ready()
    Ref.save_file_manager.settings_updated.connect(_on_settings_updated)
    _on_settings_updated()
    %EatTimer.timeout.connect(_on_eat_timeout)

func _on_settings_updated() -> void :
    eating_sounds_disabled = Ref.save_file_manager.settings_file.get_data("eating_sounds_disabled", false)

func _on_eat_timeout() -> void :
    if not holding_interact:
        return
    eat()


func _process(delta: float) -> void :
    %AnimationOffset.position = lerp(%AnimationOffset.position, %FoodFollow.position, clamp(16 * delta, 0.0, 1.0))
    %AnimationOffset.rotation = lerp(%AnimationOffset.rotation, %FoodFollow.rotation, clamp(16 * delta, 0.0, 1.0))


func interact(sustain: bool = false, data: Dictionary = {}) -> bool:
    super.interact(sustain, data)

    if not sustain:
        return false

    if not is_limiting_speed:
        holder.static_speed_modifier -= 0.5
        is_limiting_speed = true
    holding_interact = sustain

    start_eating()
    return true


func interact_end() -> void :
    if is_limiting_speed:
        holder.static_speed_modifier += 0.5
        is_limiting_speed = false

    interrupt_eating()

    holding_interact = false


func _is_guest_player_in_coop() -> bool:
    return Ref.coop_manager != null \
        and holder == Ref.player \
        and Ref.coop_manager.has_active_session() \
        and Ref.coop_manager.is_client_session()


func start_eating() -> void :
    holding_animation = true

    if _is_guest_player_in_coop():
        %AnimationPlayer.speed_scale = COOP_CLIENT_FAST_EAT_ANIM_SPEED
        %EatTimer.start(COOP_CLIENT_FAST_EAT_TIME_SEC)
    else:
        %AnimationPlayer.speed_scale = 1.0
        %EatTimer.start()

    %AnimationPlayer.play("eat")

    if not eating_sounds_disabled:
        current_eat_sound_effect = %EatSoundEffect.duplicate()
        get_tree().get_root().add_child(current_eat_sound_effect)
        current_eat_sound_effect.finished.connect(current_eat_sound_effect.queue_free)
        current_eat_sound_effect.play()


func interrupt_eating() -> void :
    holding_animation = false

    if has_node("%AnimationPlayer"):
        %AnimationPlayer.stop()
        %AnimationPlayer.speed_scale = 1.0


    var old_eat_sound_effect: AudioStreamPlayer = current_eat_sound_effect
    current_eat_sound_effect = null
    if is_instance_valid(old_eat_sound_effect):
        var tween: Tween = get_tree().create_tween()
        tween.tween_property(old_eat_sound_effect, "volume_db", -80, 0.2)
        tween.finished.connect(old_eat_sound_effect.queue_free)


func eat() -> void :
    if holder.dead or holder.disabled:
        return

    inventory.change_amount(inventory_index, -1)


    if holder.health < holder.max_health:
        var heal_sound_effect: AudioStreamPlayer = %HealSoundEffect.duplicate()
        get_tree().get_root().add_child(heal_sound_effect)
        heal_sound_effect.finished.connect(heal_sound_effect.queue_free)
        heal_sound_effect.play()

    holder.health = min(holder.max_health, holder.health + item.recovery_amount)

    if holding_interact and inventory.items[inventory_index] != null and inventory.items[inventory_index].count > 0:
        %AnimationPlayer.stop()
        start_eating()


func can_interact(_data: Dictionary) -> bool:
    return true