class_name PetStateLens
extends Resource
## 狀態鏡資源定義(企劃書第四章「數值狀態鏡」):生效時,日常動作的差分查找先加上專屬前綴(找不到才退回通用差分池),
## 並可選擇性覆蓋角色的行動物理數值。多個狀態鏡同時啟用時只取優先度最高者(Pet.state_lenses 陣列中越前面越高)。
## 何時啟用/解除完全由積木決定(啟用狀態鏡、解除狀態鏡、條件事件),這裡只放靜態定義。

## 允許被狀態鏡覆蓋的 PetMovementParams 欄位(不含 scale_multiplier,那會牽動視覺與碰撞箱重算)。
const OVERRIDABLE: Array[StringName] = [
	&"move_speed", &"run_speed_multiplier", &"gravity_scale", &"terminal_fall_velocity",
	&"idle_duration_min", &"idle_duration_max", &"walk_duration_min", &"walk_duration_max",
	&"jump_velocity", &"jump_variance", &"max_jump_velocity", &"jump_air_speed_multiplier", &"hop_chance_per_second", &"edge_drop_chance",
	&"restitution", &"float_min_speed",
]
const NATURES: Array[String] = ["正面", "負面", "持續"]
## 這個狀態鏡生效時,「容易呼叫哪些行為」可以額外覆蓋的倍率鍵(跟 LensBehavior.TABLE 的倍率鍵共用同一套,只是這裡是
## 每個狀態鏡各自能調、不限於六個內建名稱)。key = 行為代號,value = 倍率(1 = 不變,跟性格在一般狀態下的值相乘)。
const BEHAVIOR_KEYS: Array[String] = ["dance", "run", "rest", "game_invite"]
const BEHAVIOR_LABELS := {"dance": "跳舞", "run": "奔跑", "rest": "休息系列(睡醒後多久可以再休息)", "game_invite": "對戰(主動邀請頻率)"}

## 鏡片名稱(積木下拉選單、Status 面板顯示用)。
@export var lens_name := ""
## 差分命名前綴,例如 "tired_" → 優先找 tired_idle_0、tired_walk_0。
@export var prefix := ""
## 性質標籤(可複選):純粹作為查詢依據,例如「解除所有負面狀態鏡」。
@export var nature: PackedStringArray = []
## 移動數值覆蓋:PetMovementParams 欄位名稱 → 覆蓋值;沒列的欄位維持角色原始數值。
@export var movement_overrides: Dictionary = {}
## 這個狀態鏡生效時「容易呼叫哪些行為」的倍率覆蓋(見 BEHAVIOR_KEYS):key → 倍率,沒列的鍵不受這個狀態鏡影響
## (內建六個名稱本來就有的效果見 LensBehavior.TABLE,這裡的覆蓋跟它相乘,不是取代)。
@export var behavior_overrides: Dictionary = {}
## 自動逾時解除(可選,秒):兩者都是 0 表示不設逾時;max 大於 min 時每次啟用在區間內隨機取值。
@export var timeout_min := 0.0
@export var timeout_max := 0.0
## 延續執行判定(有設逾時才有意義,和睡覺的「再睡一輪」同一種做法):每次逾時到期時擲骰,決定要不要再延續一輪(時間重新在逾時區間內抽);
## 延續機率 = continue_chance × continue_decay^(已經完成的輪數 − 1),一輪比一輪低;滿 max_rounds 輪一定結束。continue_chance = 0 = 不延續(舊行為)。
@export var continue_chance := 0.0
@export var continue_decay := 0.6
@export var max_rounds := 6
## 啟用期間桌寵一律用奔跑的速度與動作(走路變成 run);只要有一個啟用中的鏡片勾了就算。
@export var force_run := false
## 是否可以被「心情門檻」叫出來:-1 = 依名稱(開心、悠哉、緊張、生氣、悲傷預設會,其他不會);0 = 不會;1 = 會。要不要用哪個看性格的「心情高/低時的狀態鏡」,沒指定就在勾了的正面/負面狀態鏡裡隨機挑。
@export var mood_callable := -1
## 這個狀態鏡是誰帶進來的:空字串 = 使用者自己建的;"personality:<性格 id>" = 套用性格時加入的。source_hash = 加入當下內容的雜湊,
## 用來判斷使用者後來有沒有改過(改過就視為使用者自己的,換性格時不會被動到)。見 PersonalityApplier。
@export var source := ""
@export var source_hash := 0


func has_nature(tag: String) -> bool:
	return nature.has(tag)


func is_mood_callable() -> bool:
	if mood_callable >= 0:
		return mood_callable == 1
	return LensBehavior.MOOD_DEFAULT_CALLABLE.has(lens_name)


## 逾時到期、已經完成 rounds_done 輪(≥ 1)時要不要再延續一輪;roll 是 0~1 的隨機數(獨立成函式方便測試)。
func continues(rounds_done: int, roll: float) -> bool:
	if continue_chance <= 0.0 or rounds_done >= max_rounds:
		return false
	return roll < clampf(continue_chance, 0.0, 1.0) * pow(clampf(continue_decay, 0.0, 1.0), maxi(rounds_done - 1, 0))


## 這次啟用要倒數的秒數,0 表示不逾時。
func roll_timeout() -> float:
	if timeout_min <= 0.0 and timeout_max <= 0.0:
		return 0.0
	return randf_range(minf(timeout_min, timeout_max), maxf(timeout_min, timeout_max))
