extends Node

const GameplayPreferences = preload("res://src/view/app/gameplay_preferences.gd")
const PACK := "res://assets/sound_effects/Tabletop Games SFX Pack/JDSherbert - Tabletop Games SFX Pack - "
const CARD_PACK := "res://assets/sound_effects/Card Game SFX Lite (Free)/wav/oneshots/"
const TABLE_LOOP := "res://assets/sound_effects/Card Game SFX Lite (Free)/wav/loops/card_table_quiet_loop_01.wav"
const CUES := {
	&"hover": [CARD_PACK + "card_hover_01.wav", -21.0, 1.0, 0.0],
	&"select": [CARD_PACK + "card_select_01.wav", -17.0, 1.0, 0.0],
	&"flip": [CARD_PACK + "card_flip_01.wav", -15.0, 1.0, 0.0],
	&"shuffle": [CARD_PACK + "card_shuffle_overhand_01.wav", -11.0, 1.0, 0.0],
	&"drag": [CARD_PACK + "card_slide_01.wav", -17.0, 1.0, 0.0],
	&"drop": [CARD_PACK + "card_place_01.wav", -19.0, 1.0, 0.0],
	&"draw": [CARD_PACK + "card_draw_01.wav", -21.0, 1.0, 0.0],
	&"deal": [CARD_PACK + "card_deal_01.wav", -21.0, 1.0, 0.0],
	&"reveal": [CARD_PACK + "card_foil_shine_01.wav", -22.0, 1.0, 0.0],
	&"score": [CARD_PACK + "score_tick_01.wav", -22.0, 1.0, 0.0],
	&"score_milestone": [CARD_PACK + "dice_shake_01.wav", -17.0, 1.15, 0.0],
	&"score_multiplier": [CARD_PACK + "mult_up_01.wav", -20.0, 1.0, 0.0],
	&"round_win": [CARD_PACK + "hand_win_01.wav", -15.0, 1.0, 0.0],
	&"round_loss": [CARD_PACK + "hand_lose_01.wav", -19.0, 1.0, 0.0],
	&"prime": [PACK + "Deck Deal - 2.wav", -11.0, 1.36, 0.010],
	&"unprime": [PACK + "Dice Pickup - 2.wav", -16.0, 0.95, 0.045],
	&"play": [PACK + "Piece Impact - 2.wav", -10.0, 0.92, 0.041],
}
const HOVER_COOLDOWN_MSEC := 95

var _players: Dictionary[StringName, AudioStreamPlayer] = {}
var _mouse_motion_id := 0
var _last_hover_motion := -1
var _last_hover_msec := -HOVER_COOLDOWN_MSEC


func _ready() -> void:
	for cue in CUES:
		var settings: Array = CUES[cue]
		var path: String = settings[0]
		if ResourceLoader.exists(path):
			_add_player(cue, load(path) as AudioStream, settings[1], settings[2])
	_add_player(&"invalid", _soft_buzz(), -16.0, 1.0)
	for cue in [&"draw", &"deal"]:
		if _players.has(cue):
			_players[cue].max_polyphony = 2
	_start_ambience()


func _start_ambience() -> void:
	if not ResourceLoader.exists(TABLE_LOOP):
		return
	var source := load(TABLE_LOOP) as AudioStreamWAV
	if source == null:
		return
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var ambient := AudioStreamPlayer.new()
	ambient.name = "Ambient"
	ambient.stream = stream
	ambient.volume_db = -45.0
	ambient.bus = GameplayPreferences.AMBIENT
	add_child(ambient)
	ambient.play()
	create_tween().tween_property(ambient, "volume_db", -12.0, 0.65)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not event.relative.is_zero_approx():
		_mouse_motion_id += 1


func play(cue: StringName) -> void:
	var player: AudioStreamPlayer = _players.get(cue)
	if player == null:
		return
	if cue == &"hover":
		# A snapshot can replace the card under a stationary cursor.
		var now := Time.get_ticks_msec()
		if _last_hover_motion == _mouse_motion_id or now - _last_hover_msec < HOVER_COOLDOWN_MSEC:
			return
		_last_hover_msec = now
		_last_hover_motion = _mouse_motion_id
	var start := float(CUES[cue][3]) if CUES.has(cue) else 0.0
	player.play(start)


func _add_player(cue: StringName, stream: AudioStream, volume_db: float, pitch: float) -> void:
	var player := AudioStreamPlayer.new()
	player.name = str(cue)
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.bus = GameplayPreferences.SOUND_EFFECTS
	add_child(player)
	_players[cue] = player


func _soft_buzz() -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	const DURATION := 0.095
	var sample_count := roundi(DURATION * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var time := float(i) / SAMPLE_RATE
		var envelope := smoothstep(0.0, 0.012, time) * (1.0 - smoothstep(0.025, DURATION, time))
		var phase := TAU * 146.0 * time
		var tone := 0.68 * sin(phase) + 0.22 * sin(2.0 * phase) + 0.10 * sin(3.0 * phase)
		data.encode_s16(i * 2, roundi(16000.0 * envelope * tone))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream
