class_name PetRelax
extends RefCounted
## 放鬆模式(2026-10-11 使用者要求;系統匣「全體行為 → 放鬆模式」,見 DesktopShellState.relax_mode):
## 全部桌寵以「坐著待著」為主,盡量少動、少打擾、少耗效能。這個類別管一隻桌寵在放鬆模式下的
## 「什麼時候坐下、坐哪裡、要不要起身換位置」;其餘零散的開關(不追球/道具、不互相跟隨、閒聊變少…)
## 直接寫在 Pet / PetVitality / PetBallPlay / PetEffects 各自的判斷裡,都問 Pet.relaxing()。
##
## 數值怎麼來(使用者指定的做法):不另外開一組性格參數,而是「桌寵身上現有的數值加上幾 %」——見 scaled():
## 現有數值 > 0 就乘上 (1 + 百分比);現有數值是 0(這個性格本來沒有這種行為)就拿該參數的「1 個單位」當底再加百分比,
## 所以沒開「自己坐下」的性格在放鬆模式下一樣會坐。百分比與單位集中寫在下面的常數。
##
## 流程(地面上的桌寵):
##  - 平時每秒擲一次要不要坐下(SIT_*);要坐就挑座位(_pick_seat):原地、空著的家具座位、別隻桌寵旁邊、空曠處,
##    挑分數最高的走過去(走得比平常慢),到了就坐下(PetVitality.force_rest,之後每段結束走 _relax_round_finished)。
##  - 坐著的每一段結束時(PetVitality 問 wants_relocate()):低機率起身重新挑一個「不是原地」的座位。
##    只有這個時機會挑座位——討厭的對象坐到旁邊也不會讓牠起身(使用者指定:避免變成你跑我追)。
##  - 挑座位:性格特性優先(內向的先看空不空曠),其次才是好惡(喜歡的對象旁邊加分、討厭的對象旁邊扣分)。
##    以「判定框不跟別隻重疊」為原則,真的沒有不重疊的位置才允許擠;對象在別層平台也可以挑牠旁邊(走上去/跳下去)。
##  - 找不到座位:原地小範圍左右遊蕩 WANDER_SECONDS 秒(給使用者機會把佔位的桌寵移開)再挑一次,這次允許擠。
##  - 被使用者拖到別處放開:先站著發呆一下(SETTLE_SECONDS)再坐下;拖到家具上放開由既有的「拖到家具上就使用」處理。
##  - 好感度(使用者指定,冷卻 1 小時):走到喜歡的對象旁邊坐下 → 自己對牠的好感增加;討厭自己的對象被自己坐到旁邊 → 牠對自己的好感減少。
## 飛行:會降落的落地歇腳後就一直待著;兼具模式提早降落後照地面的規則;總是飛行、漂浮的盡量待在原地(見 Pet.relax_hovering())。
##
## 非放鬆模式(2026-10-13 使用者要求:平時也會找座位):只借用「挑座位 → 走過去 → 坐下」這一段——走在地上的桌寵
## 「沒事自己坐下」(PetVitality._maybe_idle_sit)那一刻先挑一次座位(seek_seat_casual),挑到別處就用平常的速度走過去才坐。
## 優先度最低(跟隨、追球/道具都排在前面,見 Pet._secondary_goal),被別的事打斷就算了;不遊蕩、不起身換位置、不結算好感,
## 其餘放鬆模式的行為(更常坐、坐更久、不跟隨…)都沒有。

enum State { NONE, SETTLE, SEEK, SEEK_FURNITURE, WANDER }

## 「現有數值加上幾 %」的百分比(1.0 = +100%)與數值是 0 時的底(該參數的 1 個單位)。
const SIT_CHANCE_PCT := 3.0          # 自己坐下的意願(性格 idle_sit_chance,每秒機率)+300%
const SIT_CHANCE_UNIT := 0.02        # 機率類的 1 個單位 = 1 個百分點的兩倍(每秒 2%);加成後每秒 8%,平均十幾秒內坐下
const SIT_DURATION_PCT := 1.5        # 每一段坐著的時間(性格 rest_duration)+150%
## 自動閒聊:2026-10-19 使用者改主意(原本 10-11 說照常):自動閒聊開著時倒數變慢 CHAT_INTERVAL_PCT(間隔 +100%,
## 見 Pet._tick_auto_chat),多隻之間的最短間隔也拉長(DesktopShellState.AUTO_CHAT_RELAX_GAP_SECONDS)。
## 互相邀請對戰的間隔不另外拉長;坐著休息時也照常開口/對戰,見 Pet.relax_seated()。
const CHAT_INTERVAL_PCT := 1.0
const SEEK_SPEED_PCT := -0.4         # 找座位時的移動速度 −40%
const PARTICLE_PCT := -0.5           # 特效粒子密度 −50%
## 坐著的一段結束時:起身換位置的機率(再乘 0.5 + 社交意願)、繼續坐著以外改成睡著的機率(懶惰/累了 ×LAZY_SLEEP_MULT)。
const RELOCATE_CHANCE := 0.12
const SLEEP_CHANCE := 0.06
const LAZY_SLEEP_MULT := 4.0
const CHECK_INTERVAL := 1.0
const SETTLE_SECONDS := 2.5
const SEEK_TIMEOUT := 18.0
const WANDER_SECONDS := 8.0
const WANDER_STEP := 30.0
const WANDER_TURN_SECONDS := 2.0
## 家具座位一次坐多久(秒),到了自動起身、之後再擲骰決定要不要坐(可能換地方)。
const FURNITURE_SIT_SECONDS := Vector2(120.0, 300.0)
## 挑座位:算「在旁邊」的距離、換位置至少要離原地多遠、兩隻判定框之間多留的空隙。
const NEAR_RADIUS := 220.0
const MIN_RELOCATE_DISTANCE := 80.0
const SEAT_GAP := 14.0
## 喜歡的對象可以貼得更近(2026-10-13 使用者要求:容許入座的判定更放鬆):跟牠之間不留空隙,好惡每高一級
## 還容許判定框多疊「兩隻半寬相加」的這個比例(有點喜歡 15%、喜歡 30%、超級喜歡 45%)。只看自己喜不喜歡對方。
const LIKED_OVERLAP_PER_LEVEL := 0.15
## 最喜歡的對象旁邊的座位加分(超級喜歡是 3 × 70 = 210;內向的對最喜歡的對象也不打折)。
const FAVORITE_SEAT_BONUS := 400.0
const SAME_LEVEL_Y := 60.0
## 空曠處的取樣間距(像素):每個站得上去的平面(地面、平臺頂)每隔這麼遠試一個位置。
## 2026-10-11 使用者實機回報「同一層遠一點明明有空位卻不去坐、也不往上往下找」:原本整層只取 7 個固定點、而且只看自己這一層,
## 桌寵一多,空隙剛好都落在取樣點之間就當成沒位置。
const OPEN_SPOT_STEP := 36.0
## 換到別層的座位扣一點分(同一層有位置就先坐同一層)。
const OTHER_LEVEL_PENALTY := 18.0
## 走到座位後還要多讓出來的距離:走路在離目標 Pet.FOLLOW_DEADZONE 以內就停,挑別隻旁邊的位置時要把這段誤差算進去,
## 不然停下來的地方會比挑的位置更靠近對方,被當成「太擠」。
const ARRIVE_SLACK := Pet.FOLLOW_DEADZONE + 4.0
## 好感事件:坐到對象旁邊才算(兩隻判定框之間的空隙不超過這個距離,見 beside);冷卻 1 小時(使用者指定)。
const FAVOR_GAP := 70.0
const FAVOR_COOLDOWN := 3600.0
## 社交意願低於這個值也算內向(沒有開「內向」心情規則的性格)。
const INTROVERT_SOCIABILITY := 0.35

var state: State = State.NONE
var _pet: Node
var _goal: Variant = null
var _left := 0.0
var _check_left := 0.0
var _turn_left := 0.0
var _wander_origin := 0.0
var _wander_dir := 1.0
## 這次走去的座位是為了坐到誰旁邊(可能是 null);到了才結算好感。
var _seat_near: Node
var _was_on := false
## 這次走去的座位是「允許擠」才挑到的(到了不再檢查擠不擠,直接坐;不然會走到→嫌擠→遊蕩→再挑同一個,永遠坐不下去)。
var _seat_crowded_ok := false


func _init(pet: Node) -> void:
	_pet = pet


## 「現有數值加上幾 %」:value > 0 → value × (1 + pct);value 是 0 → unit × (1 + pct)。
static func scaled(value: float, pct: float, unit: float = 1.0) -> float:
	return (value if value > 0.0 else unit) * (1.0 + pct)


## 正在走去座位/找不到座位遊蕩中(移動速度要放慢,見 Pet._walk_speed)。
func seeking() -> bool:
	return state == State.SEEK or state == State.SEEK_FURNITURE or state == State.WANDER


## 給 Pet._movement_goal:正要走去的地方(行動區座標);沒有就回 null。
func movement_goal() -> Variant:
	if state == State.SEEK or state == State.WANDER:
		return _goal
	return null


func reset() -> void:
	state = State.NONE
	_goal = null
	_seat_near = null
	_seat_crowded_ok = false


## 使用者把桌寵拖到別處放開:先發呆一下再坐下(拖到家具上會由既有的拖放邏輯直接使用家具,那邊優先)。
func on_dropped() -> void:
	if not _pet.relaxing():
		return
	if _pet.vitality != null and _pet.vitality.has_drag_resume():
		return   # 本來就在休息/睡覺的:落地後直接接回原本那一段(見 PetVitality._tick_drag_resume)
	state = State.SETTLE
	_left = SETTLE_SECONDS
	_goal = null
	_seat_near = null


## PetVitality 在坐著的一段結束時問:要不要起身換位置?回 true 表示已經挑好新座位、正要走過去(呼叫端負責結束這次休息)。
func wants_relocate() -> bool:
	if not _pet.relaxing() or not _pet.is_ground_mode() or _pet.is_using_furniture() or _pet.is_in_game():
		return false
	if randf() >= RELOCATE_CHANCE * (0.5 + clampf(_pet.sociability, 0.0, 1.0)):
		return false
	var seat := _pick_seat(false, false)
	if seat.is_empty():
		return false
	_go_to(seat)
	return true


## 非放鬆模式的找座位(見檔頭):PetVitality 決定「現在要自己坐下」時先問這裡。回 true = 挑到別處的座位、正要走過去
## (到了才坐,呼叫端這次先不要坐);回 false = 原地就是最好的位置或沒得挑,呼叫端照舊原地坐下。
func seek_seat_casual() -> bool:
	if _pet.relaxing() or state != State.NONE or not _pet.is_ground_mode() or not _free_to_sit():
		return false
	var seat := _pick_seat(true, false)
	if seat.is_empty() or bool(seat.get("here", false)):
		return false
	_go_to(seat)
	return state != State.NONE


## 非放鬆模式:只推進「正走去座位」的狀態;中途有別的事(被拖、跟隨、對戰、累了先休息…)就放棄。
func _tick_casual(delta: float) -> void:
	match state:
		State.SEEK:
			if _pet.dragging or _pet.entering or _pet.vitality == null or _pet.vitality.mode != PetVitality.Mode.ACTIVE \
					or _pet.is_following() or _pet.is_following_mouse() or _pet.is_in_game():
				reset()
			else:
				_tick_seek(delta)
		State.SEEK_FURNITURE:
			_tick_seek_furniture(delta)
		State.NONE:
			pass
		_:
			reset()


func tick(delta: float) -> void:
	var on: bool = _pet.relaxing()
	if on != _was_on:
		_was_on = on
		reset()
		if on and _pet.is_following():
			_pet.stop_follow()   # 放鬆模式下桌寵之間不互相跟隨
		if not on and _pet.vitality != null:
			_pet.vitality.relax_ended()   # 解除:正在坐的這一段縮回平常的長度,之後照平常的規則
	if not on:
		_tick_casual(delta)
		return
	if _pet.entering or _pet.move_mode == Pet.MoveMode.FIXED or _pet.move_mode == Pet.MoveMode.STATIONARY:
		return
	match state:
		State.SETTLE:
			_tick_settle(delta)
		State.SEEK:
			_tick_seek(delta)
		State.SEEK_FURNITURE:
			_tick_seek_furniture(delta)
		State.WANDER:
			_tick_wander(delta)
		_:
			_check_left -= delta
			if _check_left <= 0.0:
				_check_left = CHECK_INTERVAL
				_decide()


## 平時:每秒看一次要不要去坐。已經在休息/用家具/忙著就不管。
func _decide() -> void:
	if _pet.move_mode == Pet.MoveMode.FLYING and not _pet.is_ground_mode():
		_decide_flying()
		return
	if _pet.move_mode == Pet.MoveMode.FLOATING:
		return   # 漂浮:待在原地就好(見 Pet.relax_hovering)
	if not _free_to_sit():
		return
	var chance := scaled(_pet.vitality.idle_sit_chance, SIT_CHANCE_PCT, SIT_CHANCE_UNIT) * CHECK_INTERVAL
	if randf() >= clampf(chance, 0.0, 1.0):
		return
	_choose(true)


## 飛在空中的:會降落的找地方降落(落地後的歇腳會一直延長,見 Pet._fly_resting);兼具模式提早結束飛行。
func _decide_flying() -> void:
	if _pet.is_following_mouse() or _pet.is_busy_for_game():
		return
	if _pet.fly_behavior == Pet.FlyBehavior.LANDS:
		_pet.request_landing()
	elif _pet.fly_behavior == Pet.FlyBehavior.HYBRID:
		_pet.relax_end_hybrid_flight()


func _free_to_sit() -> bool:
	return _pet.vitality != null and _pet.vitality.mode == PetVitality.Mode.ACTIVE and not _pet.vitality.has_drag_resume() and _pet.is_on_floor() and not _pet.is_busy_for_game() and _pet.hold_left() <= 0.0 \
			and not _pet.is_using_furniture() and not _pet.heading_to_furniture() and not _pet.is_following_mouse() and not _pet.is_holding_still()


## 挑座位並出發;挑不到不擠的位置就先遊蕩。include_here = 原地也算一個候選。
func _choose(include_here: bool) -> void:
	var seat := _pick_seat(include_here, false)
	if seat.is_empty():
		_start_wander()
		return
	_go_to(seat)


func _go_to(seat: Dictionary) -> void:
	_seat_crowded_ok = false
	_seat_near = seat.get("near")
	var item: FurnitureItem = seat.get("item")
	if item != null:
		if _pet.use_furniture(item, "sit"):
			state = State.SEEK_FURNITURE
			_left = SEEK_TIMEOUT * 2.0
			return
		_seat_near = null
		if _pet.relaxing():
			_start_wander()
		return
	if bool(seat.get("here", false)):
		_sit_down(false)
		return
	_goal = seat["pos"]
	state = State.SEEK
	_left = SEEK_TIMEOUT


func _tick_settle(delta: float) -> void:
	if _pet.is_using_furniture() or _pet.heading_to_furniture():
		reset()   # 被拖到家具上:照既有的規則使用家具
		return
	if not _pet.is_ground_mode():
		reset()   # 飛行/漂浮的回到 _decide 的規則
		return
	if not _pet.is_on_floor():
		return
	if _left == SETTLE_SECONDS:
		_pet.relax_stand_idle(SETTLE_SECONDS)   # 落地那一刻:先站著發呆一次
	_left -= delta
	if _left > 0.0 or _pet.is_busy_for_game():
		return
	state = State.NONE
	if _crowded(_pet.position):
		_choose(false)
	else:
		_sit_down(false)


func _tick_seek(delta: float) -> void:
	if not (_goal is Vector2) or not _pet.is_ground_mode():
		reset()
		return
	_left -= delta
	var goal := _goal as Vector2
	var arrived: bool = absf(_pet.position.x - goal.x) <= Pet.FOLLOW_DEADZONE + 2.0 and absf(_pet.position.y - goal.y) < SAME_LEVEL_Y and _pet.is_on_floor()
	if arrived and not _pet.relaxing() and _pet.is_busy_for_game():
		# 非放鬆模式:到了但正好在忙(說話、被摸…),等一下再坐;等到逾時就算了。
		if _left <= 0.0:
			reset()
	elif arrived:
		# 走到了才發現位置被佔走:晃一下再挑。只看「判定框真的疊到」(不含預留的空隙,也扣掉走路停下來的誤差);
		# 本來就是允許擠才挑的位置不用再看(不然會走到→嫌擠→遊蕩→再挑同一個,永遠坐不下去)。
		# 非放鬆模式不遊蕩:走到了就坐。
		if _pet.relaxing() and not _seat_crowded_ok and _crowded(_pet.position, -ARRIVE_SLACK):
			_start_wander()
		else:
			_sit_down(true)
	elif _left <= 0.0:
		# 走太久到不了(被擋住、對象走掉…):這裡不擠就直接坐,不然遊蕩一下再挑。
		_seat_near = null
		if not _pet.relaxing():
			reset()   # 非放鬆模式:到不了就算了,下次想坐再挑
		# 腳下站得住就直接在這裡坐,不再挑(再挑很可能又挑到同一個到不了的地方,一直走不停)。
		elif _pet.is_on_floor():
			_sit_down(false)
		else:
			_start_wander()


func _tick_seek_furniture(delta: float) -> void:
	if _pet.is_using_furniture():
		_pet.extend_furniture_use(randf_range(FURNITURE_SIT_SECONDS.x, FURNITURE_SIT_SECONDS.y))
		if _pet.relaxing():
			_settle_favor()
		reset()
		return
	_left -= delta
	if not _pet.heading_to_furniture() or _left <= 0.0:
		if _left <= 0.0:
			_pet.stop_using_furniture()
		reset()


func _start_wander() -> void:
	state = State.WANDER
	_left = WANDER_SECONDS
	_turn_left = 0.0
	_wander_origin = _pet.position.x
	_wander_dir = 1.0 if randf() < 0.5 else -1.0
	_seat_near = null


## 找不到座位:原地小範圍左右走動,時間到再挑一次(這次允許跟別隻擠)。
func _tick_wander(delta: float) -> void:
	if not _pet.is_ground_mode():
		reset()
		return
	_left -= delta
	_turn_left -= delta
	if _turn_left <= 0.0:
		_turn_left = WANDER_TURN_SECONDS
		_wander_dir = -_wander_dir
		var area: Rect2 = _pet._bounds()
		_goal = Vector2(clampf(_wander_origin + _wander_dir * WANDER_STEP, area.position.x + 20.0, area.end.x - 20.0), _pet.position.y)
	if _left > 0.0:
		return
	state = State.NONE
	_goal = null
	var seat := _pick_seat(true, false)
	var crowded_ok := false
	if seat.is_empty():
		seat = _pick_seat(true, true)
		crowded_ok = true
	if seat.is_empty():
		_sit_down(false)
	else:
		_go_to(seat)
		_seat_crowded_ok = crowded_ok and state == State.SEEK


## 坐下。moved = 這次是特地走過來的(才結算好感)。坐不下去(正好在忙)就回到平時的判定,下一輪再試。
func _sit_down(moved: bool) -> void:
	var near := _seat_near
	reset()
	var relaxed: bool = _pet.relaxing()
	if not (_pet.vitality.force_rest() if relaxed else _pet.vitality.idle_sit_now()):
		return
	if moved and relaxed:   # 好感結算只在放鬆模式(使用者指定的範圍)
		_seat_near = near
		_settle_favor()
		_seat_near = null


## 走到座位坐下那一刻的好感結算(冷卻 FAVOR_COOLDOWN):
##  - 自己喜歡的對象就在旁邊 → 自己對牠的好感增加;
##  - 旁邊的桌寵討厭自己 → 牠對自己的好感減少(牠不會因此起身,見檔頭)。
func _settle_favor() -> void:
	for other: Node in _pet.get_tree().get_nodes_in_group("pets"):
		if other == _pet or not is_instance_valid(other) or other.is_queued_for_deletion() or other.entering:
			continue
		if not beside(other) or _pet.apart_from(other):
			continue
		var mine: int = _pet.bond_level(other)
		if mine > 0:
			PetFavor.bond(_pet, other, PetFavor.gain_amount(_pet, mine), mine, "relax_seat", FAVOR_COOLDOWN)
		var theirs: int = other.bond_level(_pet)
		if theirs < 0:
			PetFavor.bond(other, _pet, -PetFavor.loss_amount(other, theirs), theirs, "relax_crowded", FAVOR_COOLDOWN)


## other 就坐在自己旁邊嗎(同一層、判定框之間的空隙不超過 FAVOR_GAP)。
func beside(other: Node) -> bool:
	return absf(other.position.y - _pet.position.y) < SAME_LEVEL_Y \
			and absf(other.position.x - _pet.position.x) <= _half_width(_pet) + _half_width(other) + FAVOR_GAP


func is_introvert() -> bool:
	return _pet.vitality.introvert_mood_rule or _pet.sociability < INTROVERT_SOCIABILITY


## 判定框的半寬(行動區像素)。
static func _half_width(pet: Node) -> float:
	return pet.effective_hitbox_size().x * pet.params.scale_multiplier * 0.5


## 這隻桌寵算不算「佔位置」:貼底的半身立繪在一般桌寵後面一整排(見 PetLayering.manages),隱形的、抓在手上的、固定模式的(2026-10-11 使用者要求)也不算。
static func _occupies(other: Node) -> bool:
	return PetLayering.manages(other) and not other.invisible and not other.dragging and other.move_mode != Pet.MoveMode.FIXED


## 跟 other 坐在同一層時,兩隻的中心至少要隔多遠才不算擠。gap = 判定框之間要多留的空隙(負的 = 容許疊一點);
## 自己喜歡的對象不留空隙、還可以疊一點(見 LIKED_OVERLAP_PER_LEVEL)。
func _reach(other: Node, gap: float) -> float:
	var widths := _half_width(_pet) + _half_width(other)
	var level: int = _pet.bond_level(other)
	if level > 0:
		return maxf(widths * (1.0 - LIKED_OVERLAP_PER_LEVEL * float(mini(level, 3))) + minf(gap, 0.0), 4.0)
	return maxf(widths + gap, 4.0)


## spot 這個位置坐下去,判定框會不會跟別隻桌寵重疊。gap = 兩隻判定框之間要多留的空隙(負的 = 容許疊一點)。
func _crowded(spot: Vector2, gap: float = SEAT_GAP) -> bool:
	for other: Node in _pet.get_tree().get_nodes_in_group("pets"):
		if other == _pet or not is_instance_valid(other) or other.is_queued_for_deletion() or not _occupies(other):
			continue
		var reach := _reach(other, gap)
		if absf(other.position.y - spot.y) < SAME_LEVEL_Y and absf(other.position.x - spot.x) < reach:
			return true
		# 別隻正要走去的座位也算有人了(不然兩隻同時出發會挑到同一個位置)。
		var heading: Variant = other.relax.movement_goal() if other.relax != null and other.relax.state == State.SEEK else null
		if heading is Vector2 and absf((heading as Vector2).y - spot.y) < SAME_LEVEL_Y and absf((heading as Vector2).x - spot.x) < reach:
			return true
	return false


## 挑座位:回傳 {pos, item, near, here},沒有合格的回 {}。
## include_here = 原地也算候選(換位置時不算,而且新位置至少要離原地 MIN_RELOCATE_DISTANCE);allow_crowded = 允許跟別隻擠。
func _pick_seat(include_here: bool, allow_crowded: bool) -> Dictionary:
	var area: Rect2 = _pet._bounds()
	var mine := _half_width(_pet)
	var left := area.position.x + mine
	var right := area.end.x - mine
	var candidates: Array[Dictionary] = []
	if include_here:
		candidates.append({"pos": _pet.position, "item": null, "near": null, "here": true})
	var parent: Node = _pet.get_parent()
	# 空著的家具座位(行動區內、沒被藏起來的);交互行為關了「自己去用家具」的不挑。
	var skip_furniture := bool(_pet.interaction_rules.get("ignore_furniture", false))
	for node: Node in _pet.get_tree().get_nodes_in_group("furniture"):
		var item := node as FurnitureItem
		if skip_furniture or item == null or item.def == null or item.area_hidden or not area.has_point(_to_local(parent, item.global_position)):
			continue
		for i in item.def.anchors.size():
			if str((item.def.anchors[i] as Dictionary).get("type")) == "sit" and item.anchor_holder(i) == null:
				candidates.append({"pos": _to_local(parent, item.anchor_global_position(i)), "item": item, "near": null, "here": false})
				break
	# 別隻桌寵的左右兩邊(牠在哪一層就挑哪一層:可以往上或往下折衷)。
	for other: Node in _pet.get_tree().get_nodes_in_group("pets"):
		if other == _pet or not is_instance_valid(other) or other.is_queued_for_deletion() or other.entering or other.dragging or not other.is_on_floor():
			continue
		if not _occupies(other) or _pet.apart_from(other):   # 不交互的對象(2026-10-17)不會特地去坐牠旁邊
			continue
		var spacing := _reach(other, SEAT_GAP) + ARRIVE_SLACK
		for side: float in [-1.0, 1.0]:
			candidates.append({"pos": Vector2(other.position.x + side * spacing, other.position.y), "item": null, "near": other, "here": false})
	# 每個站得上去的平面(最底下的地面、跳得上去或在下面的平臺頂)的空曠處:自己這層滿了可以往上或往下找。
	for surface: Vector3 in _pet.relax_surfaces():
		var from := maxf(surface.y, left)
		var to := minf(surface.z, right)
		if to < from:
			continue
		var count := maxi(int((to - from) / OPEN_SPOT_STEP), 1)
		for i in count + 1:
			candidates.append({"pos": Vector2(lerpf(from, to, float(i) / float(count)), surface.x), "item": null, "near": null, "here": false})
	var best: Dictionary = {}
	var best_score := -INF
	for seat: Dictionary in candidates:
		var pos: Vector2 = seat["pos"]
		if seat["item"] == null and not bool(seat["here"]) and (pos.x < left or pos.x > right):
			continue
		if not include_here and pos.distance_to(_pet.position) < MIN_RELOCATE_DISTANCE:
			continue
		if not allow_crowded and _crowded(pos):
			continue
		var score := _score(seat)
		if score > best_score:
			best_score = score
			best = seat
	return best


static func _to_local(parent: Node, global_point: Vector2) -> Vector2:
	return (parent as Node2D).to_local(global_point) if parent is Node2D else global_point


## 座位分數(越高越想坐)。性格特性優先:內向的最看重「離最近的桌寵多遠」,喜歡的對象只算少量加分;
## 其他性格依社交意願喜歡坐在別人旁邊,喜歡的對象旁邊大加分。討厭的對象旁邊一律扣分。少走一點路、家具、原地各有小加分。
## 最喜歡的對象(2026-10-17)是例外:誰都最想坐到牠旁邊(FAVORITE_SEAT_BONUS),內向的也不把牠算進「離別人多遠」。
func _score(seat: Dictionary) -> float:
	var pos: Vector2 = seat["pos"]
	var introvert := is_introvert()
	var score := randf() * 20.0 - pos.distance_to(_pet.position) * 0.04
	if absf(pos.y - _pet.position.y) >= SAME_LEVEL_Y:
		score -= OTHER_LEVEL_PENALTY
	var nearest := 500.0
	for other: Node in _pet.get_tree().get_nodes_in_group("pets"):
		if other == _pet or not is_instance_valid(other) or other.is_queued_for_deletion() or not _occupies(other):
			continue
		var distance: float = other.position.distance_to(pos)
		var level: int = _pet.bond_level(other)
		if level != Pet.FAVORITE_LEVEL:
			nearest = minf(nearest, distance)
		if distance >= NEAR_RADIUS or _pet.apart_from(other):   # 不交互的對象:不加分也不扣分,當作沒看到
			continue
		var closeness := 1.0 - distance / NEAR_RADIUS
		if level == Pet.FAVORITE_LEVEL:
			score += FAVORITE_SEAT_BONUS * closeness
		elif level > 0:
			score += float(level) * 70.0 * closeness * (0.4 if introvert else 1.0)
		elif level < 0:
			score += float(level) * 90.0 * closeness
		elif not introvert:
			score += clampf(_pet.sociability, 0.0, 1.0) * 40.0 * closeness
	if introvert:
		score += nearest * 0.35
	if seat["item"] != null:
		score += 35.0
	if bool(seat.get("here", false)):
		score += 30.0
	return score
