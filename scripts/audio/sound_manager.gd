class_name SoundManager
extends Node
## 音效管理器(企劃書「音效最大發聲數與頻率節流」):
## - 訂閱 DesktopShellState.sound_requested(積木「播放音效」),用固定數量的播放器播放,同時發聲數有上限(超過就忽略新的請求)。
## - 訂閱 speech_tick_requested(說話打字機每顯示一個字),用獨立播放器並強制最小觸發間隔,避免高頻連發爆音。
## - 音量/靜音/說話音效開關存在 DesktopShellState,這裡負責套用到 Master 匯流排並存到 user://settings.cfg。
## 缺檔或載入失敗一律靜默略過(企劃書「遺失的音效靜默略過」),絕不往上拋錯。

const SFX_DIR := "res://assets/sfx/"
## 可被積木呼叫、也會導出到 Schema 的內建音效名稱(檔名不含副檔名)。speak 是引擎內部的說話音效,不對創作者開放。
## "next" 已改成之後計畫,先移除(assets/sfx/next.ogg 已不存在;之後可能換別的音效,或做「使用者自行上傳音效」功能取代——原理比照 pet.voice_stream)。
const BUILTIN_SOUNDS: Array[String] = ["coin", "ring1"]
const SPEAK_SOUND := "speak"
const MAX_POLYPHONY := 3
const SPEAK_MIN_INTERVAL := 0.08
## 效果音的重複播放保護(秒):同一個音效的最小間隔。
const SAME_SOUND_MIN_INTERVAL := 0.15
const SETTINGS_PATH := "user://settings.cfg"

var _state: Node
var _players: Array[AudioStreamPlayer] = []
var _speak_players: Dictionary = {}
var _last_speak_by_pet: Dictionary = {}
var _streams: Dictionary = {}
var _last_played_msec: Dictionary = {}


func _ready() -> void:
	_state = get_node("/root/DesktopShellState")
	for i in MAX_POLYPHONY:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_load_settings()
	_apply_settings()
	_state.sound_requested.connect(_on_sound_requested)
	_state.speech_tick_requested.connect(_on_speech_tick)
	_state.audio_settings_changed.connect(_on_settings_changed)


static func has_sound(sound_name: String) -> bool:
	return BUILTIN_SOUNDS.has(sound_name) or AlarmSounds.exists(sound_name)


func _on_sound_requested(pet: Node, sound_name: String) -> void:
	# pet.muted:這隻桌寵被(自己的積木或別隻的反應)單獨靜音,不影響其他桌寵與全域音量。
	if _state.audio_muted or not has_sound(sound_name) or (is_instance_valid(pet) and pet.muted):
		return
	# 重複播放的間隔保護:同一個音效要隔 SAME_SOUND_MIN_INTERVAL,太密的請求直接丟掉,
	# 避免積木迴圈或多隻桌寵同時觸發把同一個波形疊到爆音。不同音效之間不限制(積木「音效 A、音效 B」要能同時響),
	# 總量由最大發聲數控制。
	var now := Time.get_ticks_msec()
	if now - int(_last_played_msec.get(sound_name, -1000000)) < int(SAME_SOUND_MIN_INTERVAL * 1000.0):
		return
	var stream := _get_stream(sound_name)
	if stream == null:
		return
	for player in _players:
		if not player.playing:
			player.stream = stream
			player.play()
			_last_played_msec[sound_name] = now
			return
	# 全部發聲中:超過最大發聲數,直接忽略這次請求(比頂替舊音效更不會出現破音/爆音)。


func _on_speech_tick(pet: Node) -> void:
	if _state.audio_muted or not _state.speak_sound_enabled or (is_instance_valid(pet) and pet.muted):
		return
	if not is_instance_valid(pet):
		return
	# 每隻桌寵各有自己的說話播放器與節流計時:雙人對話兩邊同時打字時,聲音各響各的、不會互相截斷。
	var id := pet.get_instance_id()
	var now := Time.get_ticks_msec()
	if now - int(_last_speak_by_pet.get(id, -1000000)) < int(SPEAK_MIN_INTERVAL * 1000.0):
		return
	# 這隻桌寵有自訂說話聲音就用它(含音高/音量微調),沒有或壞掉就退回內建的 speak.ogg。
	var custom: AudioStream = pet.voice_stream
	var stream := custom if custom != null else _get_stream(SPEAK_SOUND)
	if stream == null:
		return
	_last_speak_by_pet[id] = now
	var player := _speak_player_for(id)
	player.stream = stream
	# 音高與音量微調對內建聲音也有效(同一個 speak.ogg 調高調低就是不同角色的聲線)。
	player.pitch_scale = pet.voice_pitch
	player.volume_db = linear_to_db(maxf(pet.voice_volume, 0.0001))
	player.play()


func _speak_player_for(id: int) -> AudioStreamPlayer:
	if not _speak_players.has(id):
		# 順手清掉已經不存在的桌寵留下的播放器。
		for old_id: int in _speak_players.keys():
			if not is_instance_id_valid(old_id):
				_speak_players[old_id].queue_free()
				_speak_players.erase(old_id)
				_last_speak_by_pet.erase(old_id)
		var player := AudioStreamPlayer.new()
		add_child(player)
		_speak_players[id] = player
	return _speak_players[id]


func _get_stream(sound_name: String) -> AudioStream:
	if not _streams.has(sound_name):
		# speak 不在 BUILTIN_SOUNDS(那份清單是給積木呼叫/Schema 匯出用,speak 是引擎內部說話音效,不對創作者開放,
		# 見上面 SPEAK_SOUND 的說明),但它跟 BUILTIN_SOUNDS 一樣是 assets/sfx/ 底下的內建檔案,要走同一條載入路徑,
		# 不然會被誤判成「使用者自訂鬧鐘音效」名稱去 AlarmSounds 找,永遠找不到、桌寵永遠沒有說話聲(2026-09-28 修好的坑)。
		if BUILTIN_SOUNDS.has(sound_name) or sound_name == SPEAK_SOUND:
			var path := "%s%s.ogg" % [SFX_DIR, sound_name]
			_streams[sound_name] = load(path) as AudioStream if ResourceLoader.exists(path) else null
		else:
			_streams[sound_name] = AlarmSounds.load_stream(sound_name)
	return _streams[sound_name]


func _on_settings_changed() -> void:
	_apply_settings()
	_save_settings()


## 音量與靜音直接套用在 Master 匯流排,之後加背景音樂等也會一起受控。
func _apply_settings() -> void:
	AudioServer.set_bus_mute(0, _state.audio_muted)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_state.audio_volume, 0.0001)))


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	_state.audio_volume = clampf(float(config.get_value("audio", "volume", 1.0)), 0.0, 1.0)
	_state.audio_muted = bool(config.get_value("audio", "muted", false))
	_state.speak_sound_enabled = bool(config.get_value("audio", "speak_enabled", true))


## 只覆寫自己那個區段,將來其他系統也用同一個 settings.cfg 時不會互相蓋掉。
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("audio", "volume", _state.audio_volume)
	config.set_value("audio", "muted", _state.audio_muted)
	config.set_value("audio", "speak_enabled", _state.speak_sound_enabled)
	config.save(SETTINGS_PATH)
