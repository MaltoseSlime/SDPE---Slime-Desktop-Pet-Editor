class_name PetVitality
extends Node
## 桌寵的「精力與情緒」(疲勞、休息、睡覺、生氣、開心)。這是引擎內建的機制,由性格的參數調整(見 PersonalityParams);
## 預設全部關閉(fatigue_rate = 0、各種情緒傾向 = 0),所以沒套性格的桌寵行為和以前完全一樣。
##
## 精力(energy,0~100):活動時慢慢消耗,消耗速度 = fatigue_rate(每分鐘;走路 ×1、奔跑 ×2、跳舞 ×2.5、站著發呆 ×0.25)。
##  - 低於 tired_threshold:進入「疲憊」——啟用「疲憊」狀態鏡(要有這個名稱的狀態鏡,性格會附上)、移動變慢(tired_move_factor)、
##    觸發一次 tired 事件,閒下來時自己坐下休息(rest_duration 秒,每分鐘恢復 rest_recovery_rate)。
##  - 低於 exhausted_threshold:直接睡覺(sleep_duration 秒,恢復速度是休息的 3 倍),睡醒觸發一次 wake 事件。
##  - 只有地面模式的桌寵會自己休息/睡覺(飛行、漂浮、固定、靜止只計精力);被使用者拖曳、點擊、有對話進行時不會硬睡,睡到一半被打斷就醒。
## 情緒:用既有的狀態鏡表現——「生氣」(負面)與「開心」(正面)兩個名稱固定,性格會附上這兩個狀態鏡;沒有這個狀態鏡就沒有效果。
##  - 被摸:開心的機率 = 0.3 × joy_proneness + max(touch_affinity, 0) × 0.5;不喜歡被摸(touch_affinity < 0)反而可能生氣 = −touch_affinity × 0.6。
##  - 被拖曳:生氣的機率 = 0.3 × anger_proneness。遊戲輸:0.5 × anger_proneness 生氣;遊戲贏:0.5 × joy_proneness 開心。
## 還有 sociability(社交意願,0~1,0.5 = 中性):越高越愛主動邀人對戰、越不會拒絕別人的邀請(見 Pet.game_refusal / _tick_auto_game)。
## 休息分三個階段,由淺到深:站住不動(STANDING)→ 坐下(RESTING)→ 睡著(SLEEPING),越深恢復精力的效率越好(倍率見 STAGE_RECOVERY)。
##  - 開始休息時依累的程度選階段:剛過疲憊門檻(還差不到 MILD_MARGIN)先站著、疲憊坐下、累到極限直接睡。
##  - 每一段休息結束(rest_duration / sleep_duration)時擲一次骰決定下一步:繼續同一階段的機率 = REST_STAY_BASE × REST_STAY_DECAY^(已休息的段數 − 1),一段比一段低,
##    連續休息滿 MAX_REST_ROUNDS 段一定醒來;沒有繼續的話,剩下的機率分給「進入更深一階」「回到淺一階」「醒來」(權重見 DEEPER_WEIGHT / SHALLOWER_WEIGHT / WAKE_WEIGHT,做不到的方向權重不算);精力補滿了也直接醒來。
## 心情(mood,0~100,預設 50 附近):被摸、贏遊戲上升,被拖曳、輸遊戲下降,平時慢慢飄回「基準」;會不會進入「開心/生氣」狀態鏡由心情與門檻決定:
##  - 心情 ≥ mood_happy_threshold(預設 65):每 2 秒有機會進入開心,越高越容易;心情 ≤ mood_angry_threshold(預設 35):同理進入生氣;掉回門檻附近(差 5 點)就結束。機率上限 = mood_swing × 0.5,mood_swing = 0 表示心情不會影響狀態(維持舊的「被摸/被拖曳當下擲骰」行為)。
##  - **好感度**(名稱固定「好感度」的數值,沒有就當中性 0.5)決定升降幅度與基準:好感度高 → 上升幅度大、下降慢(下降 ×0.3)、基準比中性高(最高 60);好感度低 → 上升幅度小(最小只加 0.2)、下降快(×1.5)、基準低(最低 40)、也慢慢才回得來。
## 精力與心情都不存檔:每次啟動都是精力飽滿、心情在基準。

const TIRED_LENS := "疲憊"
const ANGRY_LENS := "生氣"
const HAPPY_LENS := "開心"
## 悲傷(背後淡藍圓暈 + 偶爾哭泣)、緊張(一直小幅度顫抖)、悠哉(更愛跳舞、聊天、接受對戰;進入時播一次心花怒放)。行為都寫在引擎裡,狀態鏡本身只要有這個名字(性格會附上)。
const SAD_LENS := "悲傷"
const NERVOUS_LENS := "緊張"
const RELAXED_LENS := "悠哉"
## 自己決定要跑一下時啟用的狀態鏡(時間長短、要不要延續、跑的速度都在這個狀態鏡的設定裡調,見 PetStateLens 的延續執行判定與「啟用期間奔跑」)。
const RUN_LENS := "奔跑"
## 一次奔跑結束後這麼多秒內不會又自己決定跑。
const RUN_COOLDOWN := 20.0
## 奔跑最長持續幾秒(保底出口:不計算疲勞的桌寵不會因為累了而停下來,狀態鏡沒設逾時也會在這之後收跑)。
const RUN_MAX_SECONDS := 15.0
## 贏了遊戲之後這麼多秒內算「成為贏家」,可以觸發奔跑判定。
const WINNER_SECONDS := 60.0
const MAX_ENERGY := 100.0
## 疲憊狀態要回到「門檻 + 這麼多」才解除,避免在門檻上下來回閃。
const TIRED_HYSTERESIS := 10.0
## 睡醒或被打斷之後,這麼多秒內不會又自己去休息。
const REST_COOLDOWN := 30.0
const MOVING_SPEED := 8.0
const IDLE_DRAIN := 0.25
const RUN_DRAIN := 2.0
const DANCE_DRAIN := 2.5
## 各階段恢復精力的倍率(乘上 rest_recovery_rate):站著 0.5、坐下 1、睡著 3。
const STAGE_RECOVERY := {Mode.STANDING: 0.5, Mode.RESTING: 1.0, Mode.SLEEPING: 3.0}
## 剛過疲憊門檻、還差不到這麼多精力就到門檻以下時,先站著休息而不是坐下。
const MILD_MARGIN := 10.0
const REST_STAY_BASE := 0.7
const REST_STAY_DECAY := 0.6
const MAX_REST_ROUNDS := 6
const DEEPER_WEIGHT := 0.4
const SHALLOWER_WEIGHT := 0.2
const WAKE_WEIGHT := 0.4
## 精力到這麼滿就不用再休息了。
const FULL_ENOUGH := MAX_ENERGY - 0.5
## 心情相關常數。
const MOOD_NEUTRAL := 50.0
const AFFINITY_KEY := "好感度"
const MOOD_CHECK_INTERVAL := 2.0
## 每分鐘飄回基準多少點(再乘上好感度係數)。
const MOOD_DRIFT_PER_MINUTE := 3.0
## 正面事件的最小增幅(好感度再低也至少加這麼多)。
const MOOD_MIN_GAIN := 0.2
## 開心/生氣狀態要退到門檻外這麼多才解除。
const MOOD_LENS_HYSTERESIS := 5.0
## mood_swing = 1、心情到極端時,每次檢查進入開心/生氣的機率上限。
const MOOD_MAX_CHECK_CHANCE := 0.5
## 黏人 / 內向的「兩小時」規則。
const TRAIT_IDLE_MSEC := 2 * 60 * 60 * 1000
## 內向:這麼久之內被邀請 3 次以上就算太常被邀請。
const INVITE_WINDOW_MSEC := 10 * 60 * 1000
## 對戰連敗生氣:桌寵之間互相對戰後,同一隻這麼久之內最多因為對戰生氣一次(避免電腦閒置時大家互相打到全部在生氣)。
const GAME_ANGER_COOLDOWN_MSEC := 10 * 60 * 1000
## 兩次「決定要不要休息」之間的檢查間隔(秒),不必每一影格檢查。
const CHECK_INTERVAL := 1.0

## RESTING = 坐下休息(舊名稱保留);STANDING 放在最後,數值不動舊的。
enum Mode { ACTIVE, RESTING, SLEEPING, STANDING }

## 疲勞:每分鐘消耗多少精力(0 = 關閉整個疲勞機制)。
var fatigue_rate := 0.0
var rest_recovery_rate := 30.0
var tired_threshold := 35.0
var exhausted_threshold := 12.0
var sleep_duration := Vector2(60.0, 120.0)
var rest_duration := Vector2(15.0, 40.0)
var tired_move_factor := 0.6
## 情緒(0 = 沒有這種情緒反應)。
var anger_proneness := 0.0
var joy_proneness := 0.0
var touch_affinity := 0.0
## 心情起伏:0 = 心情不影響開心/生氣狀態(舊行為);> 0 = 由心情與門檻決定,數字是進入狀態機率的倍率(0~1)。
var mood_swing := 0.0
var mood_happy_threshold := 65.0
var mood_angry_threshold := 35.0
## 心情低於這個值容易悲傷(要有「悲傷」狀態鏡且 mood_swing > 0);比生氣的門檻低,悲傷會取代生氣。
var mood_sad_threshold := 20.0
## 進入正面狀態時,選「悠哉」而不是「開心」的比例(要有「悠哉」狀態鏡);被拖曳時進入「緊張」的傾向(要有「緊張」狀態鏡)。
var relax_share := 0.0
var nervous_proneness := 0.0
## 奔跑判定(性格參數):每秒擲一次,符合條件時起跑的機率;0 = 自己不會跑。條件 = 開心(有「開心」狀態鏡生效)或剛贏了遊戲;run_any_mood = true 的性格(活潑)不管心情都可能跑。
var run_chance := 0.0
var run_any_mood := false
## 個性帶來的心情規則(性格參數):黏人 = 兩小時沒有任何互動扣一次心情、平時互動多加一點;內向 = 兩小時沒被邀請加一次心情、太常被邀請扣心情;
## wake_mood_penalty = 睡著時被使用者叫醒扣多少心情(懶惰)。
var clingy_mood_rule := false
var introvert_mood_rule := false
var wake_mood_penalty := 0.0
## 沒事自己坐下休息一下的意願(每秒機率,0 = 不會):不像疲憊觸發的休息,不疲憊時也會,只坐下(不會自己躺著睡著),
## 跟疲憊觸發的休息共用同一套休息鏈與冷卻,判定見 _idle_sit_process()。
var idle_sit_chance := 0.0

var energy := MAX_ENERGY
var mode: Mode = Mode.ACTIVE
var tired := false
## 目前的休息是不是「強制休息」(右鍵選單)叫起來的,不是真的疲憊觸發——疲勞機制關掉時 _process 要不要自動取消休息
## 就看這個(見 force_rest())。
var _manual_rest := false
## 目前心情(0~100)。第一次 _process 時放到基準。
var mood := MOOD_NEUTRAL

var _pet: CharacterBody2D
var _mode_elapsed := 0.0
var _mode_length := 0.0
var _cooldown := 0.0
var _check_left := 0.0
## 這一輪連續休息已經過了幾段(每段結束擲一次骰,見 next_stage)。
var _rest_round := 0
var _mood_started := false
var _mood_check_left := 0.0
var _run_check_left := 0.0
var _run_cooldown := 0.0
var _was_running := false
var _run_elapsed := 0.0
var _winner_until_msec := 0
var _trait_check_left := 10.0
var _trait_anchor_msec := 0
var _invited_times: Array[int] = []
var _last_invited_msec := -1000000000000
var _game_anger_until_msec := 0
## 被心情門檻叫出來的狀態鏡(名稱 → true);只有它們會在心情走回門檻附近時解除。
var _mood_called: Dictionary = {}


func setup(pet: CharacterBody2D) -> void:
	_pet = pet
	_trait_anchor_msec = Time.get_ticks_msec()
	pet.action_started.connect(_on_action_started)


func fatigue_enabled() -> bool:
	return fatigue_rate > 0.0 and not _pet.fatigue_disabled


## 目前的移動速度倍率(疲憊時變慢;沒開疲勞機制就是 1)。
func speed_factor() -> float:
	return clampf(tired_move_factor, 0.1, 1.0) if tired and fatigue_enabled() else 1.0


func _process(delta: float) -> void:
	if _pet == null:
		return
	_mood_process(delta)
	_run_process(delta)
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not fatigue_enabled():
		if tired:
			_set_tired(false)
		if mode != Mode.ACTIVE:
			# 疲勞機制關掉時原本一律強制醒來(mode 只可能是殘留);但「強制休息」右鍵選單不管有沒有開疲勞都能用,
			# 手動叫起來的休息要照正常的休息鏈(_recover/_round_finished)跑,不能一進來就被這裡取消掉。
			if _manual_rest:
				_recover(delta)
			else:
				_end_rest(false)
			return
		# 疲勞機制關掉不代表 idle_sit_chance(沒事自己坐下)也要跟著關掉——它本來就設計成跟疲憊無關
		# (見宣告處的說明「不疲憊時也會」),一樣要照週期性判定跑;呼叫整個 _decide() 而不是只呼叫
		# _maybe_idle_sit(),這樣 cooldown/_can_rest() 的門檻照樣有效,tired/exhausted 那幾段因為
		# energy 在疲勞關閉時永遠停在滿血不會被消耗,自然不會誤觸發,不用另外特判。
		_check_left -= delta
		if _check_left <= 0.0:
			_check_left = CHECK_INTERVAL
			_decide()
		return
	match mode:
		Mode.ACTIVE:
			_drain(delta)
			_check_left -= delta
			if _check_left <= 0.0:
				_check_left = CHECK_INTERVAL
				_decide()
		_:
			_recover(delta)


## 依目前在做什麼消耗精力。
func _drain(delta: float) -> void:
	var factor := IDLE_DRAIN
	if _pet.is_dancing():
		factor = DANCE_DRAIN
	elif _pet.measured_speed() > MOVING_SPEED:
		factor = RUN_DRAIN if _pet.is_running() else 1.0
	energy = maxf(energy - fatigue_rate * factor * _pet.lens_mod("fatigue") * _pet.uptime_factor() * delta / 60.0, 0.0)


func _decide() -> void:
	if not tired and energy <= tired_threshold:
		_set_tired(true)
		_pet.logic.fire_event(&"tired")
	elif tired and energy >= minf(tired_threshold + TIRED_HYSTERESIS, MAX_ENERGY):
		_set_tired(false)
	if _cooldown > 0.0:
		return
	if not _can_rest():
		# 累了、想休息卻還在空中:飛行的桌寵先降落,落地了下一次檢查再躺下。
		if energy <= exhausted_threshold or (tired and energy <= tired_threshold):
			_pet.request_landing()
		return
	if energy <= exhausted_threshold:
		_begin_chain(Mode.SLEEPING)
		return
	elif tired and energy <= tired_threshold:
		_begin_chain(Mode.STANDING if energy > tired_threshold - MILD_MARGIN else Mode.RESTING)
		return
	_maybe_idle_sit()


## 不疲憊時也可能自己坐下休息一下(尤其坐下——不是只有疲憊時才會做這些動作):跟疲憊觸發的休息共用同一套
## 休息鏈與冷卻,但只從坐下開始,不會自己躺著睡著(睡著該是真的累了才對);性格沒開 idle_sit_chance(0)就不會。
## 只有從 _decide() 呼叫得到(疲勞機制關掉時 _process() 一律提早 return,不會走到這裡),所以不用額外處理
## 「疲勞關掉卻在休息中」的情形(那是 force_rest 的 _manual_rest 在管)。
func _maybe_idle_sit() -> void:
	if idle_sit_chance <= 0.0 or tired:
		return
	if randf() < clampf(idle_sit_chance * CHECK_INTERVAL, 0.0, 1.0):
		_begin_chain(Mode.RESTING)


## 奔跑判定:每秒檢查一次。跑到一半累了(疲憊)或進入休息就立刻停;結束一輪後有冷卻。開始條件見 run_chance。
func _run_process(delta: float) -> void:
	_run_cooldown = maxf(_run_cooldown - delta, 0.0)
	_run_check_left -= delta
	if _run_check_left > 0.0:
		return
	_run_check_left = CHECK_INTERVAL
	var running: bool = _pet.is_lens_active(RUN_LENS)
	if running and (tired or mode != Mode.ACTIVE or _pet.lens_blocks("run")):
		_pet.disable_lens(RUN_LENS)
		running = false
	if running:
		_run_elapsed += CHECK_INTERVAL
		if _run_elapsed >= RUN_MAX_SECONDS:
			_pet.disable_lens(RUN_LENS)
			running = false
	else:
		_run_elapsed = 0.0
	if _was_running and not running:
		_run_cooldown = RUN_COOLDOWN
	_was_running = running
	var run_mod: float = _pet.lens_mod("run")
	var base_chance := run_chance if run_chance > 0.0 else (0.03 if run_mod > 1.0 else 0.0)   # 緊張、生氣、開心:沒有跑步習慣的性格也有一點點機會起跑
	if running or base_chance <= 0.0 or _run_cooldown > 0.0 or tired or mode != Mode.ACTIVE or _pet.lens_blocks("run"):
		return
	if not _pet.has_lens(RUN_LENS) or not _pet.is_ground_mode() or _pet.is_busy_for_game():
		return
	if run_any_mood or is_winner() or run_mod > 1.0:
		if randf() < clampf(base_chance * run_mod, 0.0, 1.0) and _pet.enable_lens(RUN_LENS):
			_was_running = true


## 恢復精力(疲憊狀態下與喜歡的道具互動、吃恢復疲勞的東西用)。
func restore_energy(amount: float) -> void:
	energy = minf(energy + amount, MAX_ENERGY)


func is_winner() -> bool:
	return Time.get_ticks_msec() < _winner_until_msec


## 現在能不能自己躺下:沒有任何事在忙,而且姿態允許——地面模式要站在地上;飛行模式要已經降落(總是飛行的桌寵直接在空中休息);
## 漂浮、固定、靜止模式原地就能休息。
func _can_rest() -> bool:
	if _pet.is_busy_for_game():
		return false
	match _pet.move_mode:
		Pet.MoveMode.GROUND:
			return _pet.is_on_floor()
		Pet.MoveMode.FLYING:
			return _pet.fly_behavior == Pet.FlyBehavior.ALWAYS or _pet.is_flight_grounded()
	return true


## 開始一輪連續休息:從指定階段起跳,段數歸零。autonomous = 這是自己(不是路隊反應)決定要休息的——
## 算「想去做別的事情」,先離開路隊(見 Pet._tick_pet_follow_lifecycle 的說明);force_rest() 是路隊反應
## 用的「跟著一起休息」,傳 false 不要把自己剛決定維持的跟隨關係又拆掉。
func _begin_chain(first_stage: Mode, autonomous: bool = true) -> void:
	if autonomous and _pet.is_following():
		_pet.stop_follow()
	_rest_round = 0
	_enter_stage(first_stage)


## 進入(或換到)某個休息階段:排這一段的長度、播對應的動作並佔住動作。
## 桌寵正在幫你計時的話不會睡著:可以站著、坐著(躺著),但「睡著」自動改成坐下休息。
func _enter_stage(new_mode: Mode) -> void:
	if new_mode == Mode.SLEEPING and _pet.pet_timer != null and _pet.pet_timer.active():
		new_mode = Mode.RESTING
	mode = new_mode
	_mode_elapsed = 0.0
	var range_seconds := sleep_duration if new_mode == Mode.SLEEPING else rest_duration
	_mode_length = randf_range(minf(range_seconds.x, range_seconds.y), maxf(range_seconds.x, range_seconds.y))
	_pet.play_action(stage_action(new_mode), -1, true)
	_pet.extend_hold(_mode_length)


## 休息階段對應的動作:站著 idle、坐下 sit、睡著 sleep。
static func stage_action(stage: Mode) -> StringName:
	match stage:
		Mode.SLEEPING:
			return &"sleep"
		Mode.RESTING:
			return &"sit"
	return &"idle"


## 一段休息結束時決定下一步(純函式,方便測試):rounds_done = 已經休息完的段數(≥ 1),roll_stay / roll_pick 是兩個 0~1 的隨機數。
## 回傳下一個階段;ACTIVE = 醒來。繼續同一階段的機率一段比一段低,滿 MAX_REST_ROUNDS 段或精力補滿一定醒來。
static func next_stage(current: Mode, rounds_done: int, current_energy: float, roll_stay: float, roll_pick: float) -> Mode:
	if rounds_done >= MAX_REST_ROUNDS or current_energy >= FULL_ENOUGH:
		return Mode.ACTIVE
	if roll_stay < REST_STAY_BASE * pow(REST_STAY_DECAY, rounds_done - 1):
		return current
	var deeper := {Mode.STANDING: Mode.RESTING, Mode.RESTING: Mode.SLEEPING}.get(current, Mode.ACTIVE) as Mode
	var shallower := {Mode.SLEEPING: Mode.RESTING, Mode.RESTING: Mode.STANDING}.get(current, Mode.ACTIVE) as Mode
	var deeper_weight := DEEPER_WEIGHT if deeper != Mode.ACTIVE else 0.0
	var shallower_weight := SHALLOWER_WEIGHT if shallower != Mode.ACTIVE else 0.0
	var pick := roll_pick * (deeper_weight + shallower_weight + WAKE_WEIGHT)
	if pick < deeper_weight:
		return deeper
	if pick < deeper_weight + shallower_weight:
		return shallower
	return Mode.ACTIVE


## 休息/睡覺中:恢復精力;時間到、或中途被使用者打斷(動作被換掉、佔用被解除)就結束。
func _recover(delta: float) -> void:
	var rate := rest_recovery_rate * float(STAGE_RECOVERY.get(mode, 1.0))
	energy = minf(energy + rate * delta / 60.0, MAX_ENERGY)
	_mode_elapsed += delta
	# 時間快到就算自然結束(動作佔用可能比這裡的計時早一點點結束,不能被誤判成被打斷)
	if _mode_elapsed >= _mode_length - 0.5:
		_round_finished()
		return
	var expected := stage_action(mode)
	var activity: StringName = _pet.current_activity()
	if _pet.hold_left() <= 0.0 or (activity != expected and activity != &"lay"):
		_end_rest(false)


## 一段休息自然結束:擲骰決定繼續、換階段還是醒來。從睡著換到淺一點的階段也算睡醒(觸發 wake 事件)。
func _round_finished() -> void:
	_rest_round += 1
	var next := next_stage(mode, _rest_round, energy, randf(), randf())
	if next == Mode.ACTIVE:
		_end_rest(true)
		return
	var was_sleeping := mode == Mode.SLEEPING
	_enter_stage(next)
	if was_sleeping and next != Mode.SLEEPING:
		_pet.logic.fire_event(&"wake")


func _end_rest(finished: bool) -> void:
	var was_sleeping := mode == Mode.SLEEPING
	mode = Mode.ACTIVE
	_manual_rest = false
	_cooldown = REST_COOLDOWN / maxf(_pet.lens_mod("rest"), 0.2)
	_check_left = CHECK_INTERVAL
	if finished:
		_pet.release_hold()
		if was_sleeping:
			_pet.logic.fire_event(&"wake")
			_pet.uptime_minutes = 0.0   # 睡飽了,在場累計時長重新算
	if tired and energy >= minf(tired_threshold + TIRED_HYSTERESIS, MAX_ENERGY):
		_set_tired(false)


func _set_tired(on: bool) -> void:
	tired = on
	if on:
		_pet.enable_lens(TIRED_LENS)
	else:
		_pet.disable_lens(TIRED_LENS)


# --- 情緒 ---

func _on_action_started(action: StringName) -> void:
	match action:
		&"interact":
			on_petted()
		&"drag":
			on_dragged()


## 被摸:心情 + (2 + 4 × 對被摸的好惡)(討厭被摸時變成扣分;黏人的多加一點),正的乘 (1 + 0.5 × 易開心),負的乘 (1 + 0.5 × 易怒)。摸摸也會讓「生氣、悲傷」這類狀態更快消退。
## mood_swing = 0 時另外走舊行為:當下擲骰決定要不要立刻開心/生氣。
func on_petted() -> void:
	change_mood(_scaled(2.0 + 4.0 * clampf(touch_affinity, -1.0, 1.0) + (1.0 if clingy_mood_rule else 0.0)))
	_pet.hasten_lenses("touch")
	if mood_swing > 0.0:
		return
	if touch_affinity < 0.0 and randf() < clampf(-touch_affinity * 0.6, 0.0, 1.0):
		make_angry()
	elif randf() < clampf(0.3 * joy_proneness + maxf(touch_affinity, 0.0) * 0.5, 0.0, 1.0):
		make_positive()


func on_dragged() -> void:
	change_mood(_scaled(-5.0))
	if randf() < clampf(nervous_proneness, 0.0, 1.0):
		make_nervous()
	if mood_swing > 0.0:
		return
	if randf() < clampf(0.3 * anger_proneness, 0.0, 1.0):
		make_angry()


## 遊戲結果(win / lose / tie):贏 +5、輸只扣 2(再乘易開心/易怒)、平手 +1。輸了本身不會生氣,要「連敗」(見 game_losses_in_row,已包含這一場)才有機率生氣;
## 機率隨連敗場數上升、乘上易怒程度;和其他桌寵對戰(vs_user = false)時機率打折,而且同一隻 10 分鐘內最多因為對戰生氣一次,
## 免得電腦閒置時桌寵們互相對戰到全部在生氣。
func on_game_result(outcome: String, vs_user := true) -> void:
	match outcome:
		"win":
			_winner_until_msec = Time.get_ticks_msec() + int(WINNER_SECONDS * 1000.0)
			change_mood(_scaled(5.0))
		"lose":
			change_mood(_scaled(-2.0))
		"tie":
			change_mood(_scaled(1.0))
	if outcome == "lose":
		var chance := loss_streak_anger_chance(_pet.game_losses_in_row, anger_proneness, vs_user)
		var now := Time.get_ticks_msec()
		if chance > 0.0 and (vs_user or now >= _game_anger_until_msec) and randf() < chance:
			if make_angry() and not vs_user:
				_game_anger_until_msec = now + GAME_ANGER_COOLDOWN_MSEC
		return
	if mood_swing > 0.0:
		return
	if outcome == "win" and randf() < clampf(0.5 * joy_proneness, 0.0, 1.0):
		make_positive()


## 連敗生氣的機率(純函式,方便測試):連敗 1 場不會;第 2 場起每多一場多 0.25(最多 3 級),乘 (0.5 + 易怒程度);和其他桌寵對戰乘 0.35。
static func loss_streak_anger_chance(streak: int, proneness: float, vs_user: bool) -> float:
	if streak < 2:
		return 0.0
	var chance := 0.25 * float(mini(streak - 1, 3)) * (0.5 + maxf(proneness, 0.0))
	return clampf(chance * (1.0 if vs_user else 0.35), 0.0, 0.9)


# --- 心情 ---

## 事件的基本幅度乘上性格的易開心/易怒:正的看 joy_proneness、負的看 anger_proneness。
func _scaled(raw: float) -> float:
	return raw * (1.0 + 0.5 * (joy_proneness if raw >= 0.0 else anger_proneness))


## 好感度(0~1):名稱「好感度」的數值在它自己的範圍裡的位置;沒有這個數值就是 0.5(中性)。沒有上限的數值以 100 為滿。
func affinity() -> float:
	if _pet == null:
		return 0.5
	var def := ValueGateway.find_def(_pet, AFFINITY_KEY)
	if def == null:
		return 0.5
	var value := ValueGateway.get_value(_pet, AFFINITY_KEY)
	if def.has_finite_range() and def.max_value > def.min_value:
		return clampf((value - def.min_value) / (def.max_value - def.min_value), 0.0, 1.0)
	return clampf(value / 100.0, 0.0, 1.0)


## 心情平時飄回的基準:中性 50,好感度高 → 最高 60,低 → 最低 40。
static func mood_baseline(aff: float) -> float:
	return MOOD_NEUTRAL + (clampf(aff, 0.0, 1.0) - 0.5) * 20.0


## 好感度如何調整心情的升降幅度(純函式,方便測試)。
## 正的:raw × (0.05 + 1.45 × 好感度),至少 MOOD_MIN_GAIN(好感度 0 → 約 5%、0.5 → 約 0.78 倍、1 → 1.5 倍)。
## 負的:raw × (1.5 − 1.2 × 好感度)(好感度 0 → 1.5 倍、0.5 → 0.9 倍、1 → 0.3 倍,下降慢)。
static func mood_delta(raw: float, aff: float) -> float:
	var a := clampf(aff, 0.0, 1.0)
	if raw >= 0.0:
		return maxf(raw * (0.05 + 1.45 * a), MOOD_MIN_GAIN) if raw > 0.0 else 0.0
	return raw * (1.5 - 1.2 * a)


## 用事件(被摸、贏…)調整心情;回傳實際加減的點數。
func change_mood(raw: float) -> float:
	var before := mood
	var delta := mood_delta(raw, affinity())
	delta *= _pet.lens_mod("mood_gain" if delta >= 0.0 else "mood_loss")   # 開心、悠哉少扣、悲傷少加、生氣加倍…(見 LensBehavior)
	mood = clampf(mood + delta, 0.0, 100.0)
	return mood - before


## 越過門檻後,每次檢查進入開心 / 生氣的機率(純函式,方便測試):剛過門檻 = 上限的 20%,越極端越高,到極端(100 / 0)= 上限 × mood_swing。
static func happy_chance(current_mood: float, happy_threshold: float, swing: float) -> float:
	if swing <= 0.0 or current_mood < happy_threshold:
		return 0.0
	var ratio := clampf((current_mood - happy_threshold) / maxf(100.0 - happy_threshold, 1.0), 0.0, 1.0)
	return clampf(swing, 0.0, 1.0) * MOOD_MAX_CHECK_CHANCE * (0.2 + 0.8 * ratio)


static func angry_chance(current_mood: float, angry_threshold: float, swing: float) -> float:
	if swing <= 0.0 or current_mood > angry_threshold:
		return 0.0
	var ratio := clampf((angry_threshold - current_mood) / maxf(angry_threshold, 1.0), 0.0, 1.0)
	return clampf(swing, 0.0, 1.0) * MOOD_MAX_CHECK_CHANCE * (0.2 + 0.8 * ratio)


## 每影格:心情慢慢飄回基準(在基準上方時,好感度越高飄得越慢;在下方時,好感度越低回得越慢),並定期檢查要不要進入/離開開心、生氣。
func _mood_process(delta: float) -> void:
	var aff := affinity()
	var baseline := mood_baseline(aff)
	if not _mood_started:
		_mood_started = true
		mood = baseline
	var factor := (1.5 - aff) if mood > baseline else (0.5 + aff)
	mood = move_toward(mood, baseline, MOOD_DRIFT_PER_MINUTE * factor * delta / 60.0)
	var drift: float = _pet.lens_add("mood_drift")
	if drift != 0.0:
		mood = clampf(mood + drift * delta / 60.0, 0.0, 100.0)   # 疲憊:心情緩慢持續下降一點點
	_trait_process(delta)
	if mood_swing <= 0.0:
		return
	_mood_check_left -= delta
	if _mood_check_left > 0.0:
		return
	_mood_check_left = MOOD_CHECK_INTERVAL
	_mood_lens_check(randf(), randf())


## 依心情決定進入哪個狀態鏡(roll_* 是 0~1 隨機數,獨立成函式方便測試)。
## 心情偏高(≥ 開心門檻)→ 「心情高時的狀態鏡」(性格頁指定;沒指定就在勾了「可以被心情門檻叫出來」的正面狀態鏡裡隨機挑);
## 心情偏低(≤ 生氣門檻)→ 「心情低時的狀態鏡」(同理挑負面的;心情掉到悲傷門檻以下且沒有指定,優先悲傷)。
## 被心情門檻叫出來的狀態鏡,心情走回門檻附近就解除(條件見 LensBehavior.end_mood),不管有沒有逾時。
func _mood_lens_check(roll_happy: float, roll_angry: float, roll_sad := 1.0) -> void:
	var high_on := _mood_lens_active(true)
	var low_on := _mood_lens_active(false)
	var low_chance := angry_chance(mood, mood_angry_threshold, mood_swing)
	if not low_on and mood <= mood_sad_threshold and roll_sad < angry_chance(mood, mood_sad_threshold, mood_swing) and _enter_mood_lens(false, true):
		pass
	elif not high_on and roll_happy < happy_chance(mood, mood_happy_threshold, mood_swing) and _enter_mood_lens(true, false):
		pass
	elif not high_on and not low_on and roll_angry < low_chance:
		_enter_mood_lens(false, false)
	var thresholds := {"happy": mood_happy_threshold, "angry": mood_angry_threshold, "sad": mood_sad_threshold}
	for lens: PetStateLens in _pet.state_lenses:
		if not _mood_called.has(lens.lens_name):
			continue
		if not _pet.is_lens_active(lens.lens_name):
			_mood_called.erase(lens.lens_name)
		elif LensBehavior.mood_ended(lens.lens_name, mood, thresholds, MOOD_LENS_HYSTERESIS, lens.has_nature("正面")):
			_pet.disable_lens(lens.lens_name)
			_mood_called.erase(lens.lens_name)


## 有沒有「被心情叫出來」而且還生效中的正面 / 負面狀態鏡。
func _mood_lens_active(positive: bool) -> bool:
	for lens_name: String in _mood_called:
		var lens: PetStateLens = _pet.find_lens(lens_name)
		if lens != null and lens.has_nature("正面") == positive and _pet.is_lens_active(lens_name):
			return true
	return false


## 挑心情高 / 低時要進入的狀態鏡名稱:性格頁指定的優先(可能複選了好幾個,真的存在的裡面隨機挑一個);
## 沒指定(或指定的都不存在)就在勾了「可以被心情門檻叫出來」的正面 / 負面狀態鏡裡隨機挑。找不到回傳空字串。
func pick_mood_lens(high: bool, prefer_sad := false) -> String:
	var chosen_pool: Array[String] = PersonalityApplier.mood_lens_choices(_pet, high).filter(func(name: String) -> bool: return _pet.has_lens(name))
	if not chosen_pool.is_empty():
		return chosen_pool.pick_random()
	var pool: Array[String] = []
	for lens: PetStateLens in _pet.state_lenses:
		if lens.has_nature("正面" if high else "負面") and lens.is_mood_callable() and lens.lens_name != TIRED_LENS:
			pool.append(lens.lens_name)
	if pool.is_empty():
		return ""
	if not high and prefer_sad and pool.has(SAD_LENS):
		return SAD_LENS
	if high and pool.has(HAPPY_LENS) and pool.has(RELAXED_LENS) and pool.size() == 2:
		return RELAXED_LENS if randf() < (relax_share if relax_share > 0.0 else 0.5) else HAPPY_LENS
	return pool.pick_random()


func _enter_mood_lens(high: bool, prefer_sad: bool) -> bool:
	var lens_name := pick_mood_lens(high, prefer_sad)
	if lens_name == "" or not _enter_exclusive(lens_name):
		return false
	_mood_called[lens_name] = true
	return true


## 進入一個心情類狀態鏡:同性質的其他心情狀態鏡與相反性質的都先結束(同一時間只有一種心情狀態;疲憊、奔跑、使用者自己建而沒勾「心情叫出」的不受影響)。
func _enter_exclusive(lens_name: String) -> bool:
	var lens: PetStateLens = _pet.find_lens(lens_name)
	if lens == null:
		return false
	if lens.has_nature("正面") or lens.has_nature("負面"):
		for other: PetStateLens in _pet.state_lenses:
			if other != lens and other.lens_name != TIRED_LENS and other.is_mood_callable() and (other.has_nature("正面") or other.has_nature("負面")):
				_pet.disable_lens(other.lens_name)
	return _pet.enable_lens(lens_name)


## 心情的白話描述(給 Status 面板與性格分頁):偏開心 / 平靜 / 煩躁。
func mood_text() -> String:
	if mood >= mood_happy_threshold:
		return "開心"
	if mood <= mood_angry_threshold:
		return "煩躁"
	return "平靜"


func make_sad() -> bool:
	return _enter_exclusive(SAD_LENS)


func make_nervous() -> bool:
	return _enter_exclusive(NERVOUS_LENS)


func make_relaxed() -> bool:
	return _enter_exclusive(RELAXED_LENS)


## 進入正面狀態:有「悠哉」狀態鏡時依 relax_share 的比例選悠哉,否則開心。
func make_positive() -> bool:
	if _pet.has_lens(RELAXED_LENS) and randf() < clampf(relax_share, 0.0, 1.0):
		return make_relaxed()
	return make_happy()


## 進入生氣;桌寵沒有「生氣」狀態鏡就什麼都不做,回傳有沒有真的生效。
func make_angry() -> bool:
	return _enter_exclusive(ANGRY_LENS)


func make_happy() -> bool:
	return _enter_exclusive(HAPPY_LENS)


# --- 個性帶來的心情規則 ---

## 每 10 秒檢查:黏人的兩小時沒任何互動 −6 心情、內向的兩小時沒被邀請 +6 心情(各自每兩小時最多一次)。
func _trait_process(delta: float) -> void:
	_trait_check_left -= delta
	if _trait_check_left > 0.0:
		return
	_trait_check_left = 10.0
	var now := Time.get_ticks_msec()
	if clingy_mood_rule and now - maxi(_pet._last_user_msec, _trait_anchor_msec) > TRAIT_IDLE_MSEC:
		_trait_anchor_msec = now
		change_mood(-6.0)
	if introvert_mood_rule:
		if now - maxi(_last_invited_msec, _trait_anchor_msec) > TRAIT_IDLE_MSEC:
			_trait_anchor_msec = now
			change_mood(6.0)


## 被別隻桌寵邀請(對戰、玩球):內向的太常被邀請(10 分鐘內 3 次)會扣心情。
func note_invited() -> void:
	var now := Time.get_ticks_msec()
	_last_invited_msec = now
	_invited_times.append(now)
	_invited_times = _invited_times.filter(func(stamp: int) -> bool: return now - stamp <= INVITE_WINDOW_MSEC)
	if introvert_mood_rule and _invited_times.size() >= 3:
		_invited_times.clear()
		_invited_times.append(now)
		change_mood(-3.0)


## 積木「依性質啟用狀態鏡」:依心情高 / 低指定或隨機挑一個進入(算「被心情叫出來」的,會在心情走回門檻附近時解除)。
func enter_mood_lens(high: bool) -> bool:
	return _enter_mood_lens(high, false)


## 積木「去休息」:立刻進入某個休息階段(standing 站著 / resting 坐下 / sleeping 睡覺)。要開了疲勞機制、在地面上、沒在忙才做得到。
func rest_now(stage_name: String) -> bool:
	if not fatigue_enabled() or mode != Mode.ACTIVE or not _can_rest():
		return false
	var stage := {"standing": Mode.STANDING, "resting": Mode.RESTING, "sleeping": Mode.SLEEPING}.get(stage_name, Mode.RESTING) as Mode
	_begin_chain(stage)
	return true


## 桌寵右鍵選單「強制休息」用:不管有沒有開疲勞機制、精力夠不夠都能叫桌寵坐下休息(手動需要看到桌寵休息動作時用,
## 例如素材包缺覺/坐/睡動畫時想確認效果),進去之後照正常的休息鏈判斷(每段結束擲骰決定站/坐/睡哪個方向、要不要醒來),
## 跟真的因為疲憊觸發的休息完全同一套邏輯,只是起點固定是坐下、不需要 fatigue_enabled()。
## 一樣要求沒在忙、姿態允許(見 _can_rest);已經在休息中就不重複觸發。
func force_rest() -> bool:
	if mode != Mode.ACTIVE or not _can_rest():
		return false
	_manual_rest = true
	_begin_chain(Mode.RESTING, false)   # 不算「自己想去做別的事情」,不動跟隨關係(休息中維持跟隨無害,見 _begin_chain 的說明)。
	return true


## 悄悄叫醒(計時器提醒用):不扣心情、不算被使用者叫醒。
func wake_quietly() -> void:
	if mode == Mode.ACTIVE:
		return
	_end_rest(false)
	_pet.release_hold()


## 問話時被吵醒、使用者選了「讓牠繼續睡」:重新睡下去。
func resume_sleep() -> void:
	if mode == Mode.ACTIVE and fatigue_enabled() and _can_rest():
		_begin_chain(Mode.SLEEPING)


## 睡著時被使用者叫醒(選單確認後):立刻醒來;性格有「被叫醒扣心情」(懶惰)就扣。
func wake_by_user() -> void:
	if mode == Mode.ACTIVE:
		return
	_end_rest(false)
	_pet.release_hold()
	if wake_mood_penalty > 0.0:
		change_mood(-wake_mood_penalty)
	_pet.logic.fire_event(&"wake")