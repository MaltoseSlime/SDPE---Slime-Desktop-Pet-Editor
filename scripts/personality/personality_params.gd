class_name PersonalityParams
extends RefCounted
## 性格可以調整的「參數」:每一項對應桌寵身上一個既有的旋鈕,附型別、合法範圍與預設值(判斷「使用者有沒有自己改過」用)。
## 性格檔的 params 區塊只認這裡列出的鍵;不認得的鍵、型別或範圍不對的值都略過並報告,不會讓程式壞掉。
## 名詞見 docs/專有名詞表.md;格式說明見 docs/性格檔格式.md。

## kind:float(單一數字)、range([最小, 最大] 兩個數字,最小 ≤ 最大)、bool、weights({賽制: 權重},賽制只能是 1 / 3 / 5)。
const SPECS := {
	"move_speed": {"kind": "float", "min": 20.0, "max": 600.0, "default": 120.0, "label": "移動速度"},
	"run_speed_multiplier": {"kind": "float", "min": 1.0, "max": 5.0, "default": 2.0, "label": "奔跑速度倍率"},
	"idle_duration": {"kind": "range", "min": 0.2, "max": 60.0, "default": Vector2(1.5, 4.0), "label": "站著發呆的時間(秒)"},
	"walk_duration": {"kind": "range", "min": 0.2, "max": 60.0, "default": Vector2(2.0, 5.0), "label": "每次走路的時間(秒)"},
	"hop_chance": {"kind": "float", "min": 0.0, "max": 3.0, "default": 0.4, "label": "自己跳一下的頻率(每秒機率)"},
	"jump_velocity": {"kind": "float", "min": 200.0, "max": 1200.0, "default": 520.0, "label": "平時跳躍力道(值越大跳越高)"},
	"jump_variance": {"kind": "float", "min": 0.0, "max": 0.6, "default": 0.15, "label": "平時跳躍高度的浮動(比例,0.15 = 上下 15%)"},
	"max_jump_velocity": {"kind": "float", "min": 300.0, "max": 1400.0, "default": 760.0, "label": "最大跳躍力道(跳躍嘗試失敗多次時才會呼叫)"},
	"idle_hop_chance": {"kind": "float", "min": 0.0, "max": 2.0, "default": 0.1, "label": "站著發呆時原地小跳的頻率(每秒機率)"},
	"follow_distance": {"kind": "float", "min": 20.0, "max": 400.0, "default": 90.0, "label": "跟隨時保持的距離"},
	"auto_chat_interval": {"kind": "range", "min": 10.0, "max": 7200.0, "default": Vector2(120.0, 300.0), "label": "自動閒聊間隔(秒)"},
	"auto_game_interval": {"kind": "range", "min": 20.0, "max": 14400.0, "default": Vector2(240.0, 600.0), "label": "自己邀請對戰的間隔(秒)"},
	"auto_dance_enabled": {"kind": "bool", "default": true, "label": "會自己跳舞"},
	"invite_best_of_weights": {"kind": "weights", "default": {1: 0.5, 3: 0.35, 5: 0.15}, "label": "自己發起對戰時的賽制偏好"},
	"game_refuse_base": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.15, "label": "被邀請對戰的基底拒絕機率"},
	"game_refuse_busy": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.4, "label": "正忙時額外的拒絕機率"},
	"game_refuse_negative": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.35, "label": "心情差時額外的拒絕機率"},
	# --- 精力與情緒(見 PetVitality):fatigue_rate = 0 代表整個疲勞機制關閉 ---
	"fatigue_rate": {"kind": "float", "min": 0.0, "max": 60.0, "default": 0.0, "label": "疲勞速度(每分鐘消耗精力,0 = 不會累)"},
	"rest_recovery_rate": {"kind": "float", "min": 0.0, "max": 300.0, "default": 30.0, "label": "休息時每分鐘恢復的精力"},
	"tired_threshold": {"kind": "float", "min": 0.0, "max": 100.0, "default": 35.0, "label": "精力低於多少就覺得累"},
	"exhausted_threshold": {"kind": "float", "min": 0.0, "max": 100.0, "default": 12.0, "label": "精力低於多少直接睡著"},
	"sleep_duration": {"kind": "range", "min": 5.0, "max": 3600.0, "default": Vector2(60.0, 120.0), "label": "每次睡多久(秒)"},
	"rest_duration": {"kind": "range", "min": 3.0, "max": 1800.0, "default": Vector2(15.0, 40.0), "label": "每次坐著休息多久(秒)"},
	"tired_move_factor": {"kind": "float", "min": 0.1, "max": 1.0, "default": 0.6, "label": "累的時候移動速度倍率"},
	"anger_proneness": {"kind": "float", "min": 0.0, "max": 3.0, "default": 0.0, "label": "易怒程度(被拖曳、遊戲輸時生氣的傾向,0 = 不會)"},
	"joy_proneness": {"kind": "float", "min": 0.0, "max": 3.0, "default": 0.0, "label": "易開心程度(被摸、遊戲贏時開心的傾向,0 = 不會)"},
	"touch_affinity": {"kind": "float", "min": -1.0, "max": 1.0, "default": 0.0, "label": "對被摸的好惡(正 = 喜歡、負 = 討厭)"},
	"sociability": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.5, "label": "社交意願(越高越愛邀人對戰、越不拒絕邀請)"},
	"mouse_follow_chance": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.08, "label": "自己跟著滑鼠的意願(每 20~45 秒抽一次的機率,0 = 不會;黏人的最高)"},
	"mouse_follow_duration": {"kind": "range", "min": 3.0, "max": 600.0, "default": Vector2(15.0, 45.0), "label": "自己跟著滑鼠的時間(秒)"},
	"follow_me_seconds": {"kind": "float", "min": 5.0, "max": 3600.0, "default": 60.0, "label": "選單「跟著我」跟多久(秒)"},
	"pet_follow_chance": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.0, "label": "自己跟著別隻桌寵走的意願(每 20~45 秒抽一次的機率,0 = 不會;黏人最高、內向懶惰偏低)"},
	"pet_follow_duration": {"kind": "range", "min": 3.0, "max": 480.0, "default": Vector2(60.0, 180.0), "label": "自己跟著別隻桌寵走的時間(秒;不管這裡設多少,一條路隊最長都是 8 分鐘)"},
	# --- 奔跑判定(見 PetVitality):要有名叫「奔跑」的狀態鏡,跑多久、要不要延續在那個狀態鏡裡調 ---
	"run_chance": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.0, "label": "自己跑一下的意願(符合條件時每秒起跑的機率,0 = 不會;條件 = 開心或剛贏了遊戲)"},
	"run_any_mood": {"kind": "bool", "default": false, "label": "不管心情都可能自己跑(活潑的性格)"},
	"ball_play_chance": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.05, "label": "玩球意願(場上有球時每秒起玩的機率,0 = 不會玩;心情不好時也不玩)"},
	"mood_sad_threshold": {"kind": "float", "min": 0.0, "max": 50.0, "default": 20.0, "label": "心情低於此值容易悲傷(要有「悲傷」狀態鏡)"},
	"relax_share": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.0, "label": "進入正面狀態時選「悠哉」而不是「開心」的比例(要有「悠哉」狀態鏡)"},
	"nervous_proneness": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.0, "label": "被拖曳時變得緊張的傾向(要有「緊張」狀態鏡)"},
	# --- 心情(見 PetVitality):mood_swing = 0 代表心情不會讓角色進入開心/生氣狀態(數值照樣升降) ---
	"mood_swing": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.0, "label": "心情起伏(心情越過門檻後進入開心/生氣的傾向,0 = 心情不影響狀態)"},
	"mood_happy_threshold": {"kind": "float", "min": 50.0, "max": 100.0, "default": 65.0, "label": "心情高於多少容易開心"},
	"mood_angry_threshold": {"kind": "float", "min": 0.0, "max": 50.0, "default": 35.0, "label": "心情低於多少容易生氣"},
	"game_ask_chance": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.3, "label": "主動問你要不要玩遊戲的意願(每 4~9 分鐘擲一次的機率,0 = 不會;心情好更常問,累或心情差更少)"},
	"clingy_mood_rule": {"kind": "bool", "default": false, "label": "黏人:超過兩小時沒有任何互動扣一次心情,平時互動多加一點"},
	"introvert_mood_rule": {"kind": "bool", "default": false, "label": "內向:超過兩小時沒被邀請加一次心情,太常被邀請扣心情"},
	"wake_mood_penalty": {"kind": "float", "min": 0.0, "max": 20.0, "default": 0.0, "label": "睡著時被使用者叫醒扣多少心情(懶惰)"},
	"idle_sit_chance": {"kind": "float", "min": 0.0, "max": 1.0, "default": 0.0, "label": "沒事自己坐下休息一下的意願(不疲憊時也會,每秒機率,0 = 不會;要有沒在忙、姿態允許)"},
}
const WEIGHT_KEYS: Array[int] = [1, 3, 5]


static func keys() -> Array[String]:
	var result: Array[String] = []
	for key: String in SPECS:
		result.append(key)
	return result


static func label_of(key: String) -> String:
	return str((SPECS.get(key, {}) as Dictionary).get("label", key))


static func default_of(key: String) -> Variant:
	var spec: Dictionary = SPECS.get(key, {})
	var value: Variant = spec.get("default")
	return (value as Dictionary).duplicate() if value is Dictionary else value


## 驗證並整理一個參數值(來自性格檔的 JSON);不合格回 null。數字夾在合法範圍內。
static func normalize(key: String, raw: Variant) -> Variant:
	if not SPECS.has(key):
		return null
	var spec: Dictionary = SPECS[key]
	match str(spec["kind"]):
		"float":
			if not (raw is float or raw is int):
				return null
			return clampf(float(raw), float(spec["min"]), float(spec["max"]))
		"range":
			if not (raw is Array and (raw as Array).size() >= 2 and _is_number(raw[0]) and _is_number(raw[1])):
				return null
			var low := clampf(float(raw[0]), float(spec["min"]), float(spec["max"]))
			var high := clampf(float(raw[1]), float(spec["min"]), float(spec["max"]))
			return Vector2(minf(low, high), maxf(low, high))
		"bool":
			return bool(raw) if raw is bool else null
		"weights":
			if not raw is Dictionary:
				return null
			var weights := {}
			var total := 0.0
			for weight_key: Variant in raw:
				var count := int(str(weight_key)) if str(weight_key).is_valid_int() else -1
				if not WEIGHT_KEYS.has(count) or not _is_number(raw[weight_key]) or float(raw[weight_key]) < 0.0:
					return null
				weights[count] = float(raw[weight_key])
				total += float(raw[weight_key])
			return weights if total > 0.0 else null
	return null


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


## 目前桌寵身上這個參數的值。
static func get_value(pet: Node, key: String) -> Variant:
	match key:
		"move_speed":
			return pet.params.move_speed
		"run_speed_multiplier":
			return pet.params.run_speed_multiplier
		"idle_duration":
			return Vector2(pet.params.idle_duration_min, pet.params.idle_duration_max)
		"walk_duration":
			return Vector2(pet.params.walk_duration_min, pet.params.walk_duration_max)
		"hop_chance":
			return pet.params.hop_chance_per_second
		"jump_velocity":
			return pet.params.jump_velocity
		"jump_variance":
			return pet.params.jump_variance
		"max_jump_velocity":
			return pet.params.max_jump_velocity
		"idle_hop_chance":
			return pet.params.idle_hop_chance
		"follow_distance":
			return pet.follow_distance
		"auto_chat_interval":
			return pet.auto_chat_interval
		"auto_game_interval":
			return pet.auto_game_interval
		"auto_dance_enabled":
			return pet.auto_dance_enabled
		"invite_best_of_weights":
			return (pet.invite_best_of_weights as Dictionary).duplicate()
		"game_refuse_base":
			return pet.game_refuse_base
		"game_refuse_busy":
			return pet.game_refuse_busy
		"game_refuse_negative":
			return pet.game_refuse_negative
		"fatigue_rate":
			return pet.vitality.fatigue_rate
		"rest_recovery_rate":
			return pet.vitality.rest_recovery_rate
		"tired_threshold":
			return pet.vitality.tired_threshold
		"exhausted_threshold":
			return pet.vitality.exhausted_threshold
		"sleep_duration":
			return pet.vitality.sleep_duration
		"rest_duration":
			return pet.vitality.rest_duration
		"tired_move_factor":
			return pet.vitality.tired_move_factor
		"anger_proneness":
			return pet.vitality.anger_proneness
		"joy_proneness":
			return pet.vitality.joy_proneness
		"touch_affinity":
			return pet.vitality.touch_affinity
		"sociability":
			return pet.sociability
		"mouse_follow_chance":
			return pet.mouse_follow_chance
		"mouse_follow_duration":
			return pet.mouse_follow_duration
		"follow_me_seconds":
			return pet.follow_me_seconds
		"pet_follow_chance":
			return pet.pet_follow_chance
		"pet_follow_duration":
			return pet.pet_follow_duration
		"ball_play_chance":
			return pet.ball_play_chance
		"mood_sad_threshold":
			return pet.vitality.mood_sad_threshold
		"relax_share":
			return pet.vitality.relax_share
		"nervous_proneness":
			return pet.vitality.nervous_proneness
		"run_chance":
			return pet.vitality.run_chance
		"run_any_mood":
			return pet.vitality.run_any_mood
		"mood_swing":
			return pet.vitality.mood_swing
		"mood_happy_threshold":
			return pet.vitality.mood_happy_threshold
		"mood_angry_threshold":
			return pet.vitality.mood_angry_threshold
		"game_ask_chance":
			return pet.game_ask_chance
		"clingy_mood_rule":
			return pet.vitality.clingy_mood_rule
		"introvert_mood_rule":
			return pet.vitality.introvert_mood_rule
		"wake_mood_penalty":
			return pet.vitality.wake_mood_penalty
		"idle_sit_chance":
			return pet.vitality.idle_sit_chance
	return null


## 把(已經 normalize 過的)值設到桌寵身上。自動閒聊的計時器會重新抽一次,新的間隔才會馬上生效。
static func set_value(pet: Node, key: String, value: Variant) -> void:
	match key:
		"move_speed":
			pet.params.move_speed = value
		"run_speed_multiplier":
			pet.params.run_speed_multiplier = value
		"idle_duration":
			pet.params.idle_duration_min = (value as Vector2).x
			pet.params.idle_duration_max = (value as Vector2).y
		"walk_duration":
			pet.params.walk_duration_min = (value as Vector2).x
			pet.params.walk_duration_max = (value as Vector2).y
		"hop_chance":
			pet.params.hop_chance_per_second = value
		"jump_velocity":
			pet.params.jump_velocity = value
		"jump_variance":
			pet.params.jump_variance = value
		"max_jump_velocity":
			pet.params.max_jump_velocity = value
		"idle_hop_chance":
			pet.params.idle_hop_chance = value
		"follow_distance":
			pet.follow_distance = value
		"auto_chat_interval":
			pet.auto_chat_interval = value
			pet._auto_chat_left = -1.0
		"auto_game_interval":
			pet.auto_game_interval = value
			pet._auto_game_left = -1.0
		"auto_dance_enabled":
			pet.auto_dance_enabled = value
		"invite_best_of_weights":
			pet.invite_best_of_weights = (value as Dictionary).duplicate()
		"game_refuse_base":
			pet.game_refuse_base = value
		"game_refuse_busy":
			pet.game_refuse_busy = value
		"game_refuse_negative":
			pet.game_refuse_negative = value
		"fatigue_rate":
			pet.vitality.fatigue_rate = value
		"rest_recovery_rate":
			pet.vitality.rest_recovery_rate = value
		"tired_threshold":
			pet.vitality.tired_threshold = value
		"exhausted_threshold":
			pet.vitality.exhausted_threshold = value
		"sleep_duration":
			pet.vitality.sleep_duration = value
		"rest_duration":
			pet.vitality.rest_duration = value
		"tired_move_factor":
			pet.vitality.tired_move_factor = value
		"anger_proneness":
			pet.vitality.anger_proneness = value
		"joy_proneness":
			pet.vitality.joy_proneness = value
		"touch_affinity":
			pet.vitality.touch_affinity = value
		"sociability":
			pet.sociability = value
		"mouse_follow_chance":
			pet.mouse_follow_chance = value
		"mouse_follow_duration":
			pet.mouse_follow_duration = value
		"follow_me_seconds":
			pet.follow_me_seconds = value
		"pet_follow_chance":
			pet.pet_follow_chance = value
		"pet_follow_duration":
			pet.pet_follow_duration = value
		"ball_play_chance":
			pet.ball_play_chance = value
		"mood_sad_threshold":
			pet.vitality.mood_sad_threshold = value
		"relax_share":
			pet.vitality.relax_share = value
		"nervous_proneness":
			pet.vitality.nervous_proneness = value
		"run_chance":
			pet.vitality.run_chance = value
		"run_any_mood":
			pet.vitality.run_any_mood = value
		"mood_swing":
			pet.vitality.mood_swing = value
		"mood_happy_threshold":
			pet.vitality.mood_happy_threshold = value
		"mood_angry_threshold":
			pet.vitality.mood_angry_threshold = value
		"game_ask_chance":
			pet.game_ask_chance = value
		"clingy_mood_rule":
			pet.vitality.clingy_mood_rule = value
		"introvert_mood_rule":
			pet.vitality.introvert_mood_rule = value
		"wake_mood_penalty":
			pet.vitality.wake_mood_penalty = value
		"idle_sit_chance":
			pet.vitality.idle_sit_chance = value


## 兩個參數值是不是一樣(浮點數容許誤差,範圍、權重逐項比)。
static func same(a: Variant, b: Variant) -> bool:
	if a is Vector2 and b is Vector2:
		return (a as Vector2).is_equal_approx(b)
	if _is_number(a) and _is_number(b):
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for weight_key: Variant in a:
			if not (b as Dictionary).has(weight_key) or not is_equal_approx(float(a[weight_key]), float(b[weight_key])):
				return false
		return true
	return a == b


## 給預覽與 JSON 用的文字。
static func to_text(value: Variant) -> String:
	if value is Vector2:
		return "%s ~ %s" % [snappedf((value as Vector2).x, 0.01), snappedf((value as Vector2).y, 0.01)]
	if value is float:
		return str(snappedf(value, 0.01))
	if value is Dictionary:
		var parts: Array[String] = []
		for weight_key: Variant in value:
			parts.append(TranslationServer.translate("%s戰:%s") % [weight_key, snappedf(float(value[weight_key]), 0.01)])
		return "、".join(parts)
	return str(value)


## 存成 JSON 用的值(Vector2 → [最小, 最大],權重的鍵轉成字串)。
static func to_json(value: Variant) -> Variant:
	if value is Vector2:
		return [(value as Vector2).x, (value as Vector2).y]
	if value is Dictionary:
		var result := {}
		for weight_key: Variant in value:
			result[str(weight_key)] = value[weight_key]
		return result
	return value
