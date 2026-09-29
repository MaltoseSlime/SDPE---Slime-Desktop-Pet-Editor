class_name Pet
extends CharacterBody2D
## 桌寵本體:CharacterBody2D 物理骨架 + 視覺根節點(主企劃書第四章、第七章)。
## 目前支援地面、飛行、漂浮三種移動模式;地面模式會偵測平臺邊緣並跳上較高的平臺。
## 滑鼠互動(點擊、拖曳、摸摸)由子節點 PetInteraction 處理,透過 begin_drag/end_drag/begin_interact 控制本體。
##
## 硬性規範:CharacterBody2D 本身的 Transform Scale 永遠是 (1, 1)。整體縮放與左右轉向鏡像
## 一律只作用在 VisualRoot,碰撞箱尺寸另外依縮放率換算。

signal move_mode_changed(mode: MoveMode)
## 桌寵選單的「查看狀態」「重複前一句」:對話系統與數值池完成後由它們連上這兩個訊號;
## 還沒有任何接收者時,選單中對應的項目會顯示為灰色不可用。
signal status_requested
signal repeat_last_requested
## 右鍵選單「桌寵管理…」:方便直接叫出管理視窗,不用特地開系統匣選單。
signal manage_requested
## 一個動作「被要求播放」的瞬間發出(同一個動作連續被要求不會重複發),邏輯直譯器的
## 「當角色正在 [動作] 時」事件積木就是掛在這裡。
signal action_started(action_name: StringName)
## 桌寵剛被置入、入場動作開始時發出,日後供「當角色正在 enter 時」的事件積木掛勾。
signal entered
## 使用者即時互動(拖曳、點擊、摸摸、interact)打斷了進行中的積木鏈與動作佔用;對話氣泡等據此收掉。
signal interrupted
## 編號改變(同角色多隻在場)時發出,系統匣選單、管理視窗據此更新名稱。
signal label_changed
## 生效中的狀態鏡(堆疊中優先度最高者)改變時發出;堆疊清空、回歸原始動作庫與數值時傳空字串。
signal active_state_lens_changed(lens_name: String)

## FIXED:釘在指定座標,不受重力與平臺影響,預設鎖定拖曳。STATIONARY:留在物理系統裡,
## 只是不自主走動(站在原地播放待機動作,被拖曳或平臺消失時照樣落下)。
enum MoveMode { GROUND, FLYING, FLOATING, FIXED, STATIONARY }
enum GroundState { IDLE, WALK }
## 攀爬(地面模式限定):貼著行動區的左/右邊界牆上下爬,爬到頂轉到天花板橫著爬,到另一邊的角落再沿牆爬下來。
enum ClimbState { NONE, WALL, CEILING }
## 飛行模式的狀態:巡航(含滯空)→ 降落(飛到落點正上方再下降)→ 休息(站在平臺上,耐力補滿)→ 起飛。
enum FlyState { CRUISE, LANDING, RESTING }
## 動作優先級:高的來源可以打斷低的,低的在高優先級佔用期間的播放請求會被忽略。
## AUTONOMOUS 自主行為(走路、待機、跳躍、落下…每影格重複請求);SCRIPTED 積木/事件/對話指定的動作(會佔用一段時間,
## 見 _hold_left);INTERACTION 使用者互動(拖曳、interact);SYSTEM 入場/退場保護。
enum ActionPriority { AUTONOMOUS, SCRIPTED, INTERACTION, SYSTEM }

const MODE_LABELS: Array[String] = ["地面模式", "飛行模式", "漂浮模式", "固定模式", "靜止模式"]
## 移動模式的積木用名稱(順序同 MoveMode)。
const MODE_KEYS: Array[String] = ["ground", "flying", "floating", "fixed", "stationary"]
const Layers := preload("res://scripts/common/physics_layers.gd")
const PetInteraction := preload("res://scripts/pet/pet_interaction.gd")
const LogicInterpreter := preload("res://scripts/logic/logic_interpreter.gd")

## 未縮放前的物理碰撞箱,刻意與貼圖邊界解耦(碰撞箱底邊貼齊角色軸心,軸心在貼圖底部中央)。
const BODY_SIZE := Vector2(46.0, 34.0)
const CUTOUT_PADDING := 4.0
## 距離目標落點在這個範圍內就視為到了,避免在目標旁邊來回抖動。
const FOLLOW_DEADZONE := 14.0
## 地面桌寵跟隨較高的空中目標時,嘗試跳躍的冷卻秒數區間(不是每影格狂跳)。
const FOLLOW_JUMP_COOLDOWN := Vector2(3.0, 5.0)
## 被拋出的飛行桌寵先依慣性滑行這麼久,期間速度以這個係數衰減,之後才回到自己的巡航。
const FLY_LAUNCH_TIME := 0.9
const FLY_LAUNCH_DRAG := 1.8
## 行動區底部地面條的厚度(要跟 ActionArea 一致),降落到地面時腳底的高度。
const GROUND_TOP_OFFSET := 6.0
## 飛行放棄目標:連續兩次檢查(各隔 1 秒)位移都不到這麼多像素,就判定飛不到、放棄這個目標。
const FLY_STUCK_DISTANCE := 30.0
## 換降落點時,離已放棄的落點這麼近的候選落點也一併排除。
const FLY_FAILED_SPOT_RADIUS := 60.0
const CUTOUT_LEAD_TIME := 0.1
## 預留距離上限(像素),以及穿透形狀四周固定多留的邊(貼圖抗鋸齒/次像素位置造成的 1~2 像素也不會被裁)。
const CUTOUT_LEAD_MAX := 200.0
## 2026-09-30 使用者實機回報:移動時偶爾還是看得到穿透形狀裁到貼圖邊緣的痕跡。這個值本來就是刻意留的
## 緩衝(動畫每一幀輪廓大小的微小變化、次像素定位),從 6px 加大到 10px 給多一點餘裕;純粹是形狀外擴,
## 不影響判定框大小,風險很低。
const CUTOUT_SAFETY_MARGIN := 10.0
const CUTOUT_SNAP := 8.0
## 入場保護期間把可點擊形狀放大這麼多像素,涵蓋掉落過程,避免身體被裁掉。
const ENTRANCE_CUTOUT_GROW := 60.0
## 邊緣偵測射線:從腳邊前方 EDGE_LOOKAHEAD 處、腳上方 EDGE_PROBE_RISE 高度往下打 EDGE_PROBE_DEPTH 長。
const EDGE_LOOKAHEAD := 4.0
const EDGE_PROBE_RISE := 6.0
const EDGE_PROBE_DEPTH := 22.0
## 跳躍規劃:平臺至少要比腳高這麼多才值得跳,並保留一點餘裕避免剛好擦過。
const MIN_JUMP_RISE := 14.0
const JUMP_CLEARANCE := 12.0
const MIN_BODY_SCALE := 0.1
const MAX_BODY_SCALE := 6.0
const PETTING_TAIL := 1.0
const DANCE_DURATION := Vector2(3.0, 6.0)
const DANCE_FOLLOW_CHANCE := 0.5
const AUTO_CHAT_RETRY_SECONDS := Vector2(8.0, 20.0)
const AUTO_CHAT_QUIET_MSEC := 10000
const MIN_HOLD_TIME := 0.5
## 自然眨眼的間隔範圍(秒)與眨眼差分的最短顯示時間。
const BLINK_INTERVAL := Vector2(2.5, 6.0)
const MIN_BLINK_TIME := 0.1
const THROW_GRACE := 0.12
const THROW_GRACE_MIN_SPEED := 60.0

@export var params: PetMovementParams
## 顯示名稱,系統匣選單等處用來辨識是哪一隻桌寵。
@export var display_name := "桌寵"
## 同角色多隻在場時的編號(0 = 不編號),由 PetRegistry 維護;介面請一律用 get_label()。
var instance_index := 0
## 角色辨識代號(公開識別碼,可自訂可重複):跟隨、在場判斷等跨角色邏輯都用它,不用系統 UUID。
@export var recognition_tag := ""
## 跟隨時與目標保持的距離;多隻跟隨同一目標時,每往後一個名額多加一份距離。
@export var follow_distance := 90.0
## 置入後的入場保護秒數:期間不可被抓取、原地播放 enter 動作(沒有該動作就退回 idle_0),
## 遮住剛置入時的掉落與形狀更新造成的破圖。
@export var entrance_duration := 5.0
## 自訂說話聲音(見 PetVoice):null = 用內建的說話音效;音高與音量微調(音量是 0~1 的倍率)。
var voice_stream: AudioStream
var voice_file := ""
var voice_pitch := 1.0
var voice_volume := 1.0
## 自主跳舞(見 _try_start_dance):開關與每次待機結束時的觸發機率。沒有負面狀態鏡時才會跳。
@export var auto_dance_enabled := true
## Status 面板要不要顯示精力條 / 心情條(預設不顯示,和其他數值一樣是創作者勾選才公開;見 StatusPanel、PetVitality)。
## 關鍵詞庫:這隻角色會想或提及的事物(台詞裡用 {keyword} / {kw:1} 取出來,見 LogicInterpreter);存在角色設定檔的 "keywords"。
var keywords: PackedStringArray = PackedStringArray()
## 使用者有興趣的關鍵詞(桌寵「想更了解你」時記下來的、或使用者自己在桌寵管理裡維護;台詞裡用 {keyword:user} / {kw:user:1});存在角色設定檔的 "userKeywords"。
## keywords 則是「桌寵有興趣的」(桌寵向使用者學來的新知識也記在這裡)。
var user_keywords: PackedStringArray = PackedStringArray()
## 睡著時頭上飄出的 Zzz(用角色字體畫,見 PetSleepZ)。
var sleep_z: PetSleepZ
## 程式繪製的角色特效(愛心、火苗、水滴、閃光、小花、發光、殘影…,見 PetEffects)。
var effects: PetEffects
var status_show_energy := false
var status_show_mood := false
@export_range(0.0, 1.0) var auto_dance_chance := 0.08
## 自動閒聊:開著的時候,隔一段隨機時間(秒,最小~最大)自己「說點什麼」。另外還有全域總開關
## (DesktopShellState.auto_chat_enabled,系統匣可切),兩個都開才會說。使用者正在互動、拖曳、入場中、
## 已經有對話進行中時不會開口,會過一會兒再試。
@export var auto_chat_enabled := true
@export var auto_chat_interval := Vector2(120.0, 300.0)
## 這隻桌寵擁有的狀態鏡定義;陣列順序就是優先度(越前面越高)。何時啟用/解除由積木決定。
@export var state_lenses: Array[PetStateLens] = []

var move_mode: MoveMode = MoveMode.GROUND

## 滑鼠互動元件(clicked、petted、drag_started、drag_ended、interact_triggered 與各計數器)。
var interaction: Node
## 是否正被滑鼠拖著;拖曳期間所有自主移動暫停。
var dragging := false
## 入場保護中(見 entrance_duration)。
var entering := false
## 奔跑開關:開啟時地面移動速度乘上 run_speed_multiplier 並改播 run 動作。
var run_enabled := false
## 局部數值與 Flag(邏輯直譯器讀寫);全域數值在 DesktopShellState。存檔系統完成前不持久化。
var local_values: Dictionary = {}
var flags: Dictionary = {}
## 邏輯直譯器(執行匯入的積木檔)。
var logic: Node
## 精力與情緒(疲勞、休息、睡覺、生氣、開心),預設全關;由性格調整,見 PetVitality。
var vitality: PetVitality
## 局部數值的定義(預設值、上下限、Status 白名單…),見 PetValueDef;讀寫請走 ValueGateway。
@export var value_defs: Array[PetValueDef] = []
## 這隻桌寵專屬的介面風格(對話氣泡配色、字體、縮放)。
var ui_style: PetUiStyle = PetUiStyle.new()
## 剩餘的連續小跳/大跳次數(見 perform_hops)。
var hops_left := 0
## 行為世代標記:每次即時互動(拖曳、interact)加一,讓稍後才醒來的等待協程能發現自己已被中斷。
var action_generation := 0

var _interact_left := 0.0
var _shell_state: Node
var _auto_chat_left := -1.0
var _dance_left := 0.0
var _measured_velocity := Vector2.ZERO
var _last_global_position := Vector2.ZERO
var _dialogue_open := false
var _last_user_msec := -1000000
## 啟用中的狀態鏡堆疊:鏡片名稱 → {since = 啟用時間戳(msec), deadline = 逾時解除時間戳,0 為不逾時}。
var _active_lenses: Dictionary = {}
## 目前生效的狀態鏡合起來的效果(見 LensBehavior):倍率相乘、加成相加、阻擋的事;每次啟用/解除時重算。
var _lens_mods: Dictionary = {}
var _lens_adds: Dictionary = {}
var _lens_block_set: Dictionary = {}
var _lens_gravity := 1.0
## 目前生效鏡片(堆疊最高優先度)的名稱與差分前綴,以及被它覆蓋前的原始數值(解除時還原)。
var _current_lens_name := ""
var _lens_prefix := ""
var _lens_base_values: Dictionary = {}
var _warned_lenses := {}
## 眨眼(_bl)與說話(_sp)子差分:_logical_animation 是「邏輯上正在播」的基底動畫(例如 idle_0),
## 子差分只是暫時蓋在上面顯示,結束後回到基底動畫原本的影格。
var _logical_animation: StringName = &""
var _overlay_shown := false
var _saved_frame := 0
var _saved_progress := 0.0
var _speaking := false
var _blink_left := 0.0
var _blink_next := 3.0
## 積木/事件指定的動作(SCRIPTED)佔用動畫與自主移動的剩餘秒數;佔用期間自主行為的動作請求被忽略,
## 地面模式原地站住。至少一個動畫循環,等待類積木會用 extend_hold() 延長。
var _hold_left := 0.0
var _hold_action: StringName = &""
var _context_rids: Array[RID] = []
var _fly_stuck_timer := 0.0
var _fly_stuck_count := 0
var _fly_check_pos := Vector2.ZERO
var _fly_failed_spots: Array[Vector2] = []
var _fly_state := FlyState.CRUISE
## 飛行模式的行為(桌寵管理 → 身體):LANDS 會落地(累了、道具交互才落地,其餘時候在飛,原本的設計);ALWAYS 總是飛行(做什麼都不落地,休息也在空中);
## HYBRID 行走與飛行兼具(以地面模式行為為主,大跳躍、從平臺下來、偶爾(心情好機率高)會改成飛行一小段,落地後接回走路)。
enum FlyBehavior { LANDS, ALWAYS, HYBRID }
const FLY_BEHAVIOR_NAMES := ["lands", "always", "hybrid"]
var fly_behavior := FlyBehavior.LANDS
## 桌寵不計算疲勞值(桌寵管理):打開 = 不會累、不會自己休息或睡覺,也不會因疲勞陷入負面狀態。
var fatigue_disabled := false
var _hybrid_airborne := false
var _hybrid_fly_left := 0.0
var _hybrid_air_checked := false
var _hybrid_check_left := 5.0
const HYBRID_FLY_SECONDS := Vector2(6.0, 14.0)
const HYBRID_CHECK_INTERVAL := 5.0
const HYBRID_RANDOM_BASE := 0.05
const HYBRID_DROP_CHANCE := 0.45
const HYBRID_BIG_JUMP_CHANCE := 0.6
const HYBRID_BIG_JUMP_SPEED := 250.0
var _fly_goal := Vector2.ZERO
var _fly_land_spot := Vector2.ZERO
var _fly_stamina := 0.0
var _fly_wait_left := 0.0
var _fly_rest_left := 0.0
var _fly_launch_left := 0.0
var _rise_anim_left := 0.0
var _follow_tag := ""
var _follow_started := 0
var _follow_jump_cooldown := 0.0
## 這次跟隨最長維持幾秒(見 start_follow/_tick_pet_follow_lifecycle);不管誰發起的都不會超過 FOLLOW_MAX_SECONDS。
var _follow_duration_cap := 0.0
## 連續多久碰不到跟隨對象(超過 FOLLOW_STUCK_SECONDS 就放棄這次跟隨)。
var _follow_stuck_left := 0.0
## 跟隨對象上一次檢查是不是在休息中(邊緣觸發用,只在「從沒在休息變成在休息」那一刻做一次加入/離開的決定)。
var _follow_leader_resting := false
## 跟隨對象上一次檢查是不是在跟著滑鼠走(邊緣觸發用):跟隨對象自己跟滑鼠走的時候,整條路隊會很自然地
## 跟著一起移動(既有的跟隨移動邏輯本來就是持續追蹤對象目前的位置,不用另外處理);等對象跟完滑鼠、
## 從「跟著滑鼠」變回「沒在跟滑鼠」的那一刻,算這趟「順道去見使用者」的行程結束,整條路隊直接解散。
var _follow_leader_seeking_mouse := false
var _seek_left := 0.0
## 拖曳中吸引:被吸引的目標座標(桌寵本地座標)與剩餘有效時間(持續呼叫 set_attract_goal 才會維持,0.3 秒沒更新就解除)。
var attractable := true
var _attract_goal: Variant = null
var _attract_left := 0.0
var _seek_away := false
## 正在使用的家具(坐/躺,見 use_furniture());走過去的路上 _furniture_target 不為 null 但 _furniture_seated 是 false,
## 走到定位後 _furniture_seated 變 true、原地播 sit/lay,用 hold_still_for 持續佔住不讓自主閒晃/跳舞蓋掉(見 _tick_furniture_seek)。
var _furniture_target: FurnitureItem = null
var _furniture_anchor := -1
var _furniture_seated := false
## >= 0 才會倒數(積木「延長使用家具的時間」設過),-1 = 沒設時限。
var _furniture_use_left := -1.0
## 這次使用期間要面向哪邊(1 = 朝右、-1 = 朝左),use_furniture() 依錨點的 facing 設定決定一次,使用期間不再變。
var _furniture_facing := 1
const FURNITURE_ARRIVE_DISTANCE := 16.0
var _requested_action: StringName = &""
var _hop_scale := 1.0
var _shiver_left := 0.0
var _warned_actions := {}
var _entrance_left := 0.0
var _airborne_grace := 0.0
var _action_area: Node2D
var _facing := 1
var _ground_state := GroundState.IDLE
var _state_timer := 0.0
var _walk_dir := 1
var _fly_time := 0.0
var _edge_committed := false
var _jump_target_x := NAN
var _edge_probe: RayCast2D
var _platform_manager: Node
var _current_action: StringName = &""
var _frame_size := Vector2(64.0, 64.0)
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)

@onready var _visual_root: Node2D = $VisualRoot
@onready var _sprite: AnimatedSprite2D = $VisualRoot/AnimatedSprite2D
@onready var _shape_node: CollisionShape2D = $CollisionShape2D


## 角色庫「桌寵管理」用的隱藏臨時實例(見 DesktopShell._spawn_sample_pet 的 ghost 參數):建立前就要設好這個旗標。
## 不算進 "pets"/"Cutout" 群組(不參與任何跨桌寵系統的掃描——猜拳大逃殺、拚骰全場、跟隨、對話排版、系統匣清單…都
## 用 get_nodes_in_group("pets") 找對象),也不觸發 pet_registered(不會被存進桌寵名單/開機自動召喚清單)。
## 其餘初始化(邏輯直譯器、數值、性格套用元件)照常建立,管理視窗的各個分頁才讀寫得到。
var ghost_edit := false


func _ready() -> void:
	if not ghost_edit:
		add_to_group("Cutout")
		add_to_group("pets")
	if params == null:
		params = PetMovementParams.new()
	floor_max_angle = deg_to_rad(5.0)
	collision_layer = Layers.PET
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.animation_looped.connect(_on_sprite_looped)
	_edge_probe = RayCast2D.new()
	_edge_probe.collision_mask = Layers.PLATFORM
	_edge_probe.target_position = Vector2(0.0, EDGE_PROBE_DEPTH)
	add_child(_edge_probe)
	_apply_scale()
	set_move_mode(MoveMode.GROUND)
	get_node("/root/DesktopShellState").emergency_recall_requested.connect(_on_emergency_recall)
	interaction = PetInteraction.new()
	add_child(interaction)
	interaction.setup(self)
	interaction.context_menu_requested.connect(open_context_menu)
	interaction.clicked.connect(_on_user_poked)
	interaction.double_clicked.connect(_on_double_clicked)
	interaction.petted.connect(_on_petted)
	interaction.petting_moved.connect(_on_petting_moved)
	logic =LogicInterpreter.new()
	add_child(logic)
	logic.setup(self)
	vitality = PetVitality.new()
	add_child(vitality)
	vitality.setup(self)
	ball_play = PetBallPlay.new()
	add_child(ball_play)
	ball_play.setup(self)
	pet_timer = PetTimer.new()
	add_child(pet_timer)
	pet_timer.setup(self)
	sleep_z = PetSleepZ.new()
	add_child(sleep_z)
	sleep_z.setup(self)
	effects = PetEffects.new()
	add_child(effects)
	effects.setup(self)
	_apply_hold_anchor(_sprite.sprite_frames)
	_apply_lights(_sprite.sprite_frames)   # set_sprite_frames 可能比 _ready 早(節點還沒進樹),這裡補一次
	ValueGateway.init_defaults(self)
	_shell_state = get_node("/root/DesktopShellState")
	_shell_state.dialogue_started.connect(func(pet: Node) -> void: _dialogue_open = _dialogue_open or pet == self)
	_shell_state.dialogue_finished.connect(func(pet: Node) -> void: _dialogue_open = _dialogue_open and pet != self)
	spawn_serial = _shell_state.next_pet_serial()
	_shell_state.pet_dance_started.connect(_on_dance_cue)
	PetRegistry.refresh_labels(get_tree())
	if ghost_edit:
		# 上面各個子系統(PetSleepZ/PetEffects/PetLights…)自己的 setup() 都各自無條件 add_to_group("Cutout"),
		# 不知道也不需要知道 ghost_edit 這回事——這裡收尾統一清掉,而不是逐一去改每個子系統。
		for node in find_children("*", "", true, false):
			node.remove_from_group("Cutout")
	else:
		_shell_state.pet_registered.emit(self)


## 雙人對話:面向對方並站定不走(見 converse)。seconds 之內不會自己走動;replace 為 false 時取較長者,true 時直接覆蓋(對話結束後縮短成短暫停留)。
var _converse_left := 0.0


func converse(target_x: float, seconds: float, replace := false) -> void:
	if move_mode != MoveMode.FIXED:
		_face(1 if target_x > global_position.x else -1)
	_converse_left = seconds if replace else maxf(_converse_left, seconds)


## 靜音(只靜音這隻桌寵自己的說話聲與效果音,不動全域音量;SoundManager 讀它)。
## auto_unmute_enabled:由「事件觸發的自主靜音」在觸發條件消失時是否自動解除(玩家/創作者可關,見管理視窗);
## 自主靜音本身不需要開關(創作者放了 pet_mute 積木就是要靜音)。
var muted := false
@export var auto_unmute_enabled := true
## 看到場內別的桌寵在跳舞時,自己也跟著考慮跳舞(見 _on_dance_cue)。
@export var auto_dance_follow_enabled := true
var _mute_stamp := 0
var _dance_cue_left := -1.0


func set_muted(on: bool) -> void:
	muted = on
	_mute_stamp += 1


func mute_stamp() -> int:
	return _mute_stamp


## 目前被要求播放的動作(其他桌寵的「狀態偵測」用;睡覺=sleep、跳舞=dance…)。
func current_activity() -> StringName:
	return _requested_action


## 積木裡寫的移動模式名稱 → MoveMode 數值;不認得回 -1。接受英文名稱與中文(地面、飛行、漂浮、固定、靜止,有沒有加「模式」都可以)。
static func parse_move_mode(text: String) -> int:
	var key := text.strip_edges().to_lower().trim_suffix("模式").trim_suffix("_mode")
	var index := MODE_KEYS.find(key)
	if index >= 0:
		return index
	return ["地面", "飛行", "漂浮", "固定", "靜止"].find(key)


## 目前的移動模式名稱(ground / flying / floating / fixed / stationary)。
func move_mode_key() -> String:
	return MODE_KEYS[int(move_mode)]


## 正在說話(有對話氣泡開著)。
func is_talking() -> bool:
	return _dialogue_open


func is_dancing() -> bool:
	return _dance_left > 0.0


# --- 小遊戲:擲骰判定與猜拳(右鍵選單或積木觸發,全程在對話氣泡裡,不開視窗) ---
## 右鍵「擲骰判定」的設定(存角色設定檔):骰面數、加值、檢定值(最大點數的百分比,0 = 不檢定)。
var dice_sides := 20
var dice_mod := 0
var dice_dc_percent := 50
const DICE_SIDES_CHOICES: Array[int] = [2, 4, 6, 8, 10, 12, 20, 100]
const DICE_DC_CHOICES: Array[int] = [0, 25, 50, 75, 100]
const DICE_MOD_CHOICES: Array[int] = [-5, -3, -2, -1, 0, 1, 2, 3, 5]
## 這一場的擲骰結果(KEY → {total, pass, …})與遊戲結果文字變數({roll:KEY}、{contest:…}、{rps:…}),都只存在執行期、不存檔。
var dice_results: Dictionary = {}
var game_vars: Dictionary = {}
## 目前互動的「對象」:角色 → {tag, name, stamp}。角色有 opponent(對手)、winner(贏家)、loser(輸家)、inviter(發起挑戰的人)、invitee(被邀請的人)。
## 小遊戲與邀請對戰在觸發事件之前填入,給「當對象是 XX」條件(cond_target_is)與 {other}、{opponent}… 這些對話標記用;只存在執行期,超過 COUNTERPART_TTL_MSEC 沒更新就當作失效。
var counterparts: Dictionary = {}
var _last_counterpart_role := ""
const COUNTERPART_TTL_MSEC := 120000


## 記下一個對象(other 是桌寵)。
func set_counterpart(role: String, other: Node) -> void:
	if is_instance_valid(other):
		set_counterpart_named(role, str(other.recognition_tag), str(other.display_name))


## 記下一個對象(tag 是辨識代號,使用者是 "user")。
func set_counterpart_named(role: String, tag: String, person_name: String) -> void:
	counterparts[role] = {"tag": tag, "name": person_name, "stamp": Time.get_ticks_msec()}
	_last_counterpart_role = role


func clear_counterpart(role: String) -> void:
	counterparts.erase(role)


## 這個角色目前的對象(還沒有或已失效回空字典)。
func counterpart(role: String) -> Dictionary:
	var entry: Variant = counterparts.get(role)
	if entry is Dictionary and Time.get_ticks_msec() - int((entry as Dictionary).get("stamp", 0)) <= COUNTERPART_TTL_MSEC:
		return entry
	return {}


## {other} 用:最近一次記下、還沒失效的對象名字(沒有回空字串)。
func latest_counterpart_name() -> String:
	return str(counterpart(_last_counterpart_role).get("name", "")) if _last_counterpart_role != "" else ""
## 連輸次數(遊戲內建反應用,連輸越氣;贏一次就歸零)。
var game_losses_in_row := 0
## 賽制(右鍵選單「賽制」,存角色設定檔):1 = 一戰定勝負、3 = 三戰兩勝、5 = 五戰三勝;猜拳與拚骰共用,積木可以個別指定。
var game_best_of := 1
const BEST_OF_CHOICES: Array[int] = [1, 3, 5]
const BEST_OF_NAMES := {1: "一戰定勝負", 3: "三戰兩勝", 5: "五戰三勝"}
## 戰績(存本體狀態檔):遊戲種類 rps / dice → {win, lose, tie},一「場」算一次(三戰兩勝打完才記一筆)。
var game_stats: Dictionary = {}
## 在場累計時長(分鐘):SaveScheduler 每分鐘替場上的桌寵加 1,存在狀態檔;疲勞消耗會依它略微加快(uptime_factor),睡飽一次歸零(見 PetVitality)。
var uptime_minutes := 0.0
const UPTIME_CAP_HOURS := 8.0
const UPTIME_FATIGUE_PER_HOUR := 0.04
## 這隻角色上次的移動模式(存本體狀態檔):從角色庫重新放上桌面(不是開機自動召喚,那個用名單裡的 mode)時,
## 拿這個當預設值取代 DesktopShell.sample_pet_move_mode;-1 = 沒存過(第一次放),用場景預設(地面)。
var remembered_move_mode := -1


func uptime_hours() -> float:
	return uptime_minutes / 60.0


## 疲勞消耗倍率:在場越久越累,最多加快 UPTIME_CAP_HOURS × UPTIME_FATIGUE_PER_HOUR(= 32%)。
func uptime_factor() -> float:
	return 1.0 + minf(uptime_hours(), UPTIME_CAP_HOURS) * UPTIME_FATIGUE_PER_HOUR
const GAME_KIND_NAMES := {"rps": "猜拳", "dice": "拚骰", "ttt": "井字棋"}


## 記一筆戰績(GameChat.react 在每場結束時呼叫)。kind = rps / dice,outcome = win / lose / tie。
func record_game_result(kind: String, outcome: String) -> void:
	if not GAME_KIND_NAMES.has(kind) or not ["win", "lose", "tie"].has(outcome):
		return
	var entry: Dictionary = game_stats.get(kind, {"win": 0, "lose": 0, "tie": 0})
	entry[outcome] = int(entry.get(outcome, 0)) + 1
	game_stats[kind] = entry


## 一種遊戲(或 all = 全部)的戰績 {win, lose, tie, total, rate}(rate = 勝率百分比,整數,一場都沒打過是 0)。
func game_record(kind: String) -> Dictionary:
	var result := {"win": 0, "lose": 0, "tie": 0}
	for key: String in GAME_KIND_NAMES:
		if kind == "all" or kind == key:
			var entry: Dictionary = game_stats.get(key, {})
			for outcome: String in ["win", "lose", "tie"]:
				result[outcome] += int(entry.get(outcome, 0))
	var total: int = result["win"] + result["lose"] + result["tie"]
	result["total"] = total
	result["rate"] = int(roundf(float(result["win"]) * 100.0 / float(total))) if total > 0 else 0
	return result


## 戰績的一行文字:猜拳:12 勝 5 負 3 平(勝率 60%)。
func game_record_line(kind: String) -> String:
	var record := game_record(kind)
	var kind_name: String = GAME_KIND_NAMES.get(kind, "全部")
	if int(record["total"]) == 0:
		return tr("%s:還沒有紀錄") % kind_name
	return tr("%s:%d 勝 %d 負 %d 平(勝率 %d%%)") % [kind_name, record["win"], record["lose"], record["tie"], record["rate"]]


## 對話的 {stats:種類:欄位} 換成什麼(種類 rps / dice / all,欄位 win / lose / tie / total / rate;rate 帶百分號)。
func game_stat_text(kind: String, field: String) -> String:
	if kind != "all" and not GAME_KIND_NAMES.has(kind):
		return ""
	var record := game_record(kind)
	if not record.has(field):
		return ""
	return "%d%%" % int(record["rate"]) if field == "rate" else str(record[field])


func show_game_record() -> void:
	GameChat.say(self, tr("[b]我的戰績[/b]\n%s\n%s\n%s") % [game_record_line("rps"), game_record_line("dice"), game_record_line("ttt")], 6.0)


func clear_game_record() -> void:
	game_stats = {}
	game_losses_in_row = 0
	GameChat.say(self, "戰績清空了,重新開始!", 3.0)


## 閒置時自己發起小遊戲(猜拳/拚骰,見 GameInvite):隔一段隨機時間,在不忙、場上有別隻桌寵、沒人在說話時邀請對方;
## 對方可能拒絕(見 game_refusal)。跟自動閒聊共用總開關(系統匣「自動閒聊」)與對話間隔。
var auto_game_enabled := true
## 使用者設定「一律拒絕對戰邀請」:別隻桌寵(自動或積木)邀請這隻時必定拒絕(睡覺以外的原因都算 declined);使用者從右鍵選單叫的遊戲不受影響。
var game_always_refuse := false
## 性格的狀態(見 PersonalityApplier):{choices:{區塊→性格 id}, ignore_own:{chat, reactions}, applied:{參數名→{baseline, applied}}};存在桌寵設定的 "personality" 區塊。
var personality: Dictionary = {}
## 這隻桌寵的預設內容(內建性格…)更新到哪一版(簽章,見 DefaultsUpdater)與「以前有過的狀態鏡 / 數值定義名稱」(使用者刪掉的不會在更新時加回來);存在桌寵設定的 "defaults" 區塊。
var defaults_signature := ""
var defaults_seen: Dictionary = {}
var auto_game_interval := Vector2(240.0, 600.0)
const AUTO_GAME_RETRY := Vector2(20.0, 45.0)
## 社交意願 0~1(0.5 = 中性,和沒有這個機制時一樣):越高越愛主動邀人對戰、越不容易拒絕別人的邀請;越低反過來。性格會調整它。
var sociability := 0.5
## 被邀請對戰時的拒絕機率(見 game_refusal):基底、正忙時加多少、處於負面狀態時加多少。性格會調整這三個數字(內向、懶惰偏高,友善偏低)。
var game_refuse_base := 0.15
var game_refuse_busy := 0.4
var game_refuse_negative := 0.35
var _auto_game_left := -1.0


func _tick_auto_game(delta: float) -> void:
	if _auto_game_left < 0.0:
		_auto_game_left = _roll_auto_game_wait()
	_auto_game_left -= delta * lens_mod("game_invite")
	if _auto_game_left > 0.0:
		return
	if not lens_blocks("game") and _can_auto_chat() and GameInvite.start_random(self):
		if is_following():   # 自己主動找對戰算「想去做別的事情」,先離開路隊(見 _tick_pet_follow_lifecycle 的說明)。
			stop_follow()
		_shell_state.note_auto_chat_started()
		_auto_game_left = _roll_auto_game_wait()
	else:
		_auto_game_left = randf_range(AUTO_GAME_RETRY.x, AUTO_GAME_RETRY.y)


## 下一次自己邀請對戰要等多久:在 auto_game_interval 範圍內隨機,再依社交意願縮放(0.5 不變、1.0 減半、0.1 變 5 倍,最多 5 倍)。
func _roll_auto_game_wait() -> float:
	return randf_range(minf(auto_game_interval.x, auto_game_interval.y), maxf(auto_game_interval.x, auto_game_interval.y)) / maxf(sociability * 2.0, 0.2)


## 主動問使用者要不要玩遊戲(目前只有猜拳):每隔 USER_GAME_ASK_WAIT 秒擲一次,機率 = 性格的 game_ask_chance 依社交意願、狀態鏡(開心更愛、負面與疲憊更少)與心情調整(見 user_game_ask_probability)。
## 用氣泡問「好啊 / 下次吧」,不開視窗;答應就開始跟使用者玩,回絕或沒理它就隔比較久再問。
const USER_GAMES: Array[String] = ["rps"]
const USER_GAME_ASK_WAIT := Vector2(240.0, 540.0)
const USER_GAME_ASK_LINES: Array[String] = ["要不要跟我玩猜拳?", "欸,我們來猜拳好不好?", "有點無聊……陪我猜個拳嘛?"]
var game_ask_chance := 0.3
var _user_game_left := -1.0
var _asking_user_game := false


func user_game_ask_probability() -> float:
	if lens_blocks("game") or is_sleeping() or is_in_game() or game_ask_chance <= 0.0:
		return 0.0
	var probability := game_ask_chance * (0.5 + sociability) * lens_mod("game_invite")
	if has_unlisted_negative_lens() or lens_add("game_refuse") > 0.0:
		probability *= 0.4
	if vitality != null:
		if vitality.mood >= vitality.mood_happy_threshold:
			probability *= 1.3
		elif vitality.mood <= vitality.mood_angry_threshold:
			probability *= 0.5
	return clampf(probability, 0.0, 1.0)


func _tick_ask_user_game(delta: float) -> void:
	if _user_game_left < 0.0:
		_user_game_left = randf_range(USER_GAME_ASK_WAIT.x, USER_GAME_ASK_WAIT.y)
	_user_game_left -= delta
	if _user_game_left > 0.0:
		return
	if _asking_user_game or not _can_auto_chat():
		_user_game_left = randf_range(AUTO_CHAT_RETRY_SECONDS.x, AUTO_CHAT_RETRY_SECONDS.y)   # 現在不方便開口(有人在說話…):很快再試,不要白白等下一輪
		return
	_user_game_left = randf_range(USER_GAME_ASK_WAIT.x, USER_GAME_ASK_WAIT.y)
	if randf() >= user_game_ask_probability():
		return
	_shell_state.note_auto_chat_started()
	_ask_user_game()


func _ask_user_game() -> void:
	_asking_user_game = true
	var choice: int = await GameChat.ask(self, tr(str(USER_GAME_ASK_LINES.pick_random())), [tr("好啊"), tr("下次吧")], 25.0)
	_asking_user_game = false
	if not is_instance_valid(self):
		return
	match choice:
		0:
			GameChat.say(self, speak_tr("耶!那就開始囉!"), 1.6)
			if not is_in_game():
				start_rps_with_user()
		1:
			GameChat.say(self, speak_tr("好吧,下次再約~"), 2.4)
			_user_game_left = maxf(_user_game_left, 60.0) * 2.0
		_:
			_user_game_left = maxf(_user_game_left, 60.0) * 1.5   # 沒人理:晚一點再說


## 現在正忙著嗎(被邀請時不想理人的狀況):被拖曳、入場、跳舞、被互動、動作被佔用、交談/對話中、爬牆。
## 正在進行對戰的場數(見 GameChat.enter / leave);> 0 就是「對戰中」,別人的邀請與使用者的遊戲要求都進不來。
var game_depth := 0


func is_in_game() -> bool:
	return game_depth > 0


func is_busy_for_game() -> bool:
	return game_depth > 0 or dragging or entering or _dance_left > 0.0 or _interact_left > 0.0 or _hold_left > 0.0 or _converse_left > 0.0 \
			or _dialogue_open or _speaking or _climb != ClimbState.NONE


## 被邀請玩遊戲時的反應 {chance = 拒絕機率, reason = sleep / busy / mood / plain}:
## 睡覺必定拒絕(1.0);正忙、處於負面狀態(狀態鏡有「負面」性質:生氣、疲勞、悲傷…)機率更高,兩者疊加。
func game_refusal() -> Dictionary:
	if is_sleeping():
		return {"chance": 1.0, "reason": "sleep"}
	if game_always_refuse:
		return {"chance": 1.0, "reason": "declined"}
	if lens_blocks("game"):
		return {"chance": 1.0, "reason": "mood"}   # 疲憊:不參與遊戲與對戰
	# 社交意願:0.5 = 不調整;越高越不容易拒絕(最多 −0.25),越低越容易拒絕(最多 +0.25)
	var chance := maxf(game_refuse_base + (0.5 - sociability) * 0.5, 0.0)
	var reason := "plain"
	if is_busy_for_game():
		chance += game_refuse_busy
		reason = "busy"
	if has_unlisted_negative_lens():
		chance += game_refuse_negative   # 使用者自己建的負面狀態鏡;內建的(生氣、悲傷、緊張)效果已寫在 LensBehavior
		reason = "mood"
	var lens_refuse := lens_add("game_refuse")
	if lens_refuse > 0.0:
		chance += lens_refuse
		reason = "mood"
	chance -= lens_add("game_accept")   # 開心、悠哉:更樂意接受邀請
	return {"chance": clampf(chance, 0.0, 0.95), "reason": reason}


func roll_dice_now() -> void:
	DiceGame.roll_and_show(self, dice_sides, 1, dice_mod, DiceGame.threshold(dice_sides, 1, dice_dc_percent), "roll")


## 跟其他桌寵拚骰(others = 對手,空 = 場上所有其他桌寵)。best_of 0 = 用自己右鍵選單的「賽制」。可以 await 等整場打完。
func start_dice_contest(others: Array, best_of := 0) -> void:
	var opponents: Array = others if not others.is_empty() else get_tree().get_nodes_in_group("pets").filter(func(p: Node) -> bool: return p != self and not p.is_queued_for_deletion())
	await DiceGame.contest(self, [self] + opponents, dice_sides, 1, dice_mod, "reroll", "contest", best_of if BEST_OF_CHOICES.has(best_of) else game_best_of)


func start_rps_with_user() -> void:
	RpsGame.play_user(self, game_best_of)


func start_rps_with(other: Node, best_of := 0) -> void:
	await RpsGame.play_pets(self, other, best_of if BEST_OF_CHOICES.has(best_of) else game_best_of)


func start_ttt_with_user() -> void:
	TttGame.play_user(self, game_best_of)


func start_ttt_with(other: Node, best_of := 0) -> void:
	await TttGame.play_pets(self, other, best_of if BEST_OF_CHOICES.has(best_of) else game_best_of)


## 桌寵自己發起對戰時自己決定的賽制(不看右鍵選單的「賽制」,那是使用者叫的遊戲用的);依權重隨機,權重可以調(之後性格預設會改它)。
var invite_best_of_weights := {1: 0.5, 3: 0.35, 5: 0.15}


func pick_invite_best_of() -> int:
	var roll := randf() * float(invite_best_of_weights.values().reduce(func(sum: float, w: float) -> float: return sum + w, 0.0))
	for count: int in invite_best_of_weights:
		roll -= float(invite_best_of_weights[count])
		if roll <= 0.0:
			return count
	return 1


func is_sleeping() -> bool:
	return chat_context() == &"sleep"


func _pet_by_serial(serial: int) -> Node:
	for other: Node in get_tree().get_nodes_in_group("pets"):
		if other != self and other.spawn_serial == serial and not other.is_queued_for_deletion():
			return other
	return null


## 右鍵選單的「擲骰判定」與「猜拳」子選單。設定(骰面/檢定值/加值)用單選項目,不開任何視窗。
func _add_game_menus(root: RID) -> void:
	var others: Array = get_tree().get_nodes_in_group("pets").filter(func(p: Node) -> bool: return p != self and not p.is_queued_for_deletion())
	var threshold := DiceGame.threshold(dice_sides, 1, dice_dc_percent)
	var dice_menu := NativeMenu.create_menu()
	_context_rids.append(dice_menu)
	NativeMenu.add_item(dice_menu, tr("擲一次(%s%s)") % [DiceGame.label(dice_sides, 1, dice_mod), (tr(",檢定 ≥ %d") % threshold) if threshold > 0 else ""], _on_context_item, Callable(), "dice_roll")
	var contest_menu := NativeMenu.create_menu()
	_context_rids.append(contest_menu)
	if others.is_empty():
		NativeMenu.set_item_disabled(contest_menu, NativeMenu.add_item(contest_menu, tr("(場上沒有其他桌寵)")), true)
	else:
		NativeMenu.add_item(contest_menu, tr("與場上所有桌寵拚骰"), _on_context_item, Callable(), "dice_contest:*")
		for other: Node in others:
			NativeMenu.add_item(contest_menu, other.get_label(), _on_context_item, Callable(), "dice_contest:%d" % other.spawn_serial)
	NativeMenu.add_submenu_item(dice_menu, tr("拚骰(比誰大)"), contest_menu)
	NativeMenu.add_separator(dice_menu)
	var sides_menu := NativeMenu.create_menu()
	_context_rids.append(sides_menu)
	for sides in DICE_SIDES_CHOICES:
		NativeMenu.set_item_checked(sides_menu, NativeMenu.add_radio_check_item(sides_menu, "1D%d" % sides, _on_context_item, Callable(), "dice_sides:%d" % sides), sides == dice_sides)
	NativeMenu.add_submenu_item(dice_menu, tr("骰子(1D幾)"), sides_menu)
	var dc_menu := NativeMenu.create_menu()
	_context_rids.append(dc_menu)
	for percent in DICE_DC_CHOICES:
		var dc_text := tr("不檢定") if percent == 0 else tr("≥ %d%%(點數 %d 以上)") % [percent, DiceGame.threshold(dice_sides, 1, percent)]
		NativeMenu.set_item_checked(dc_menu, NativeMenu.add_radio_check_item(dc_menu, dc_text, _on_context_item, Callable(), "dice_dc:%d" % percent), percent == dice_dc_percent)
	NativeMenu.add_submenu_item(dice_menu, tr("檢定值"), dc_menu)
	var mod_menu := NativeMenu.create_menu()
	_context_rids.append(mod_menu)
	for modifier in DICE_MOD_CHOICES:
		NativeMenu.set_item_checked(mod_menu, NativeMenu.add_radio_check_item(mod_menu, ("%+d" % modifier) if modifier != 0 else "0", _on_context_item, Callable(), "dice_mod:%d" % modifier), modifier == dice_mod)
	NativeMenu.add_submenu_item(dice_menu, tr("加值"), mod_menu)
	_add_match_items(dice_menu)
	NativeMenu.add_submenu_item(root, tr("擲骰判定"), dice_menu)
	var rps_menu := NativeMenu.create_menu()
	_context_rids.append(rps_menu)
	NativeMenu.add_item(rps_menu, tr("跟我猜拳"), _on_context_item, Callable(), "rps_user")
	var rps_pets_menu := NativeMenu.create_menu()
	_context_rids.append(rps_pets_menu)
	NativeMenu.add_item(rps_pets_menu, tr("與場上所有桌寵猜拳"), _on_context_item, Callable(), "rps_battle_royale")
	if others.is_empty():
		NativeMenu.set_item_disabled(rps_pets_menu, NativeMenu.add_item(rps_pets_menu, tr("(場上沒有其他桌寵)")), true)
	else:
		for other: Node in others:
			NativeMenu.add_item(rps_pets_menu, other.get_label(), _on_context_item, Callable(), "rps_pet:%d" % other.spawn_serial)
	NativeMenu.add_submenu_item(rps_menu, tr("跟其他桌寵猜拳"), rps_pets_menu)
	_add_match_items(rps_menu)
	NativeMenu.add_submenu_item(root, tr("猜拳"), rps_menu)
	var ttt_menu := NativeMenu.create_menu()
	_context_rids.append(ttt_menu)
	NativeMenu.add_item(ttt_menu, tr("跟我玩井字棋"), _on_context_item, Callable(), "ttt_user")
	var ttt_pets_menu := NativeMenu.create_menu()
	_context_rids.append(ttt_pets_menu)
	if others.is_empty():
		NativeMenu.set_item_disabled(ttt_pets_menu, NativeMenu.add_item(ttt_pets_menu, tr("(場上沒有其他桌寵)")), true)
	else:
		for other: Node in others:
			NativeMenu.add_item(ttt_pets_menu, other.get_label(), _on_context_item, Callable(), "ttt_pet:%d" % other.spawn_serial)
	NativeMenu.add_submenu_item(ttt_menu, tr("跟其他桌寵井字棋"), ttt_pets_menu)
	_add_match_items(ttt_menu)
	NativeMenu.add_submenu_item(root, tr("井字棋"), ttt_menu)


## 遊戲選單共用的尾巴:賽制(一戰/三戰兩勝/五戰三勝,猜拳與拚骰共用)、查看戰績、清除戰績。
func _add_match_items(menu: RID) -> void:
	NativeMenu.add_separator(menu)
	var best_menu := NativeMenu.create_menu()
	_context_rids.append(best_menu)
	for count in BEST_OF_CHOICES:
		NativeMenu.set_item_checked(best_menu, NativeMenu.add_radio_check_item(best_menu, tr(BEST_OF_NAMES[count]), _on_context_item, Callable(), "best_of:%d" % count), count == game_best_of)
	NativeMenu.add_submenu_item(menu, tr("賽制"), best_menu)
	NativeMenu.add_item(menu, tr("查看戰績"), _on_context_item, Callable(), "game_record")
	NativeMenu.add_item(menu, tr("清除戰績"), _on_context_item, Callable(), "game_record_clear")
	NativeMenu.set_item_checked(menu, NativeMenu.add_check_item(menu, tr("閒置時自己邀請對戰或找我玩遊戲"), _on_context_item, Callable(), "auto_game_toggle"), auto_game_enabled)
	NativeMenu.set_item_checked(menu, NativeMenu.add_check_item(menu, tr("一律拒絕對戰邀請"), _on_context_item, Callable(), "always_refuse_toggle"), game_always_refuse)


## 選單的字串標籤(格式「動作:參數」)在這裡處理;回傳 true 表示已處理。
func _on_game_menu_item(text: String) -> bool:
	var kind := text.get_slice(":", 0)
	var argument := text.get_slice(":", 1) if ":" in text else ""
	match kind:
		"dice_roll":
			roll_dice_now()
		"dice_contest":
			# 選單叫桌寵去找別的桌寵對戰:桌寵先用對話叫出對方的名字問他要不要(見 GameInvite),對方可能拒絕;自己正在對戰就無效。
			if is_in_game():
				return true
			if argument == "*":
				GameInvite.invite_all_dice(self)
			else:
				var opponent := _pet_by_serial(int(argument))
				if opponent != null:
					GameInvite.invite(self, opponent, "dice")
		"dice_sides":
			dice_sides = clampi(int(argument), DiceGame.MIN_SIDES, DiceGame.MAX_SIDES)
			PetProfile.save_pet(self)
		"dice_dc":
			dice_dc_percent = clampi(int(argument), 0, 100)
			PetProfile.save_pet(self)
		"dice_mod":
			dice_mod = clampi(int(argument), -100, 100)
			PetProfile.save_pet(self)
		"best_of":
			game_best_of = int(argument) if BEST_OF_CHOICES.has(int(argument)) else 1
			PetProfile.save_pet(self)
		"auto_game_toggle":
			auto_game_enabled = not auto_game_enabled
			PetProfile.save_pet(self)
		"always_refuse_toggle":
			game_always_refuse = not game_always_refuse
			PetProfile.save_pet(self)
		"game_record":
			show_game_record()
		"game_record_clear":
			clear_game_record()
		"rps_user":
			if not is_in_game():
				start_rps_with_user()   # 玩家的要求:桌寵正在對戰就直接無效
		"rps_battle_royale":
			if not is_in_game():
				RpsGame.play_battle_royale(self)
		"rps_pet":
			var rival := _pet_by_serial(int(argument))
			if rival != null and not is_in_game():
				GameInvite.invite(self, rival, "rps")
		"ttt_user":
			if not is_in_game() and not TttGame.has_active_board():
				start_ttt_with_user()
		"ttt_pet":
			var ttt_rival := _pet_by_serial(int(argument))
			if ttt_rival != null and not is_in_game() and not TttGame.has_active_board():
				GameInvite.invite(self, ttt_rival, "ttt")
		_:
			return false
	return true


# --- 半身立繪專用:圖層帶、呼吸動畫、浮動差分與配件 ---
## 呼吸動畫:視覺根節點的縱向縮放隨時間輕微起伏(腳底在根節點原點,所以圖像底部不動,只有上半身伸縮),
## 橫向反向縮一點點讓體積感覺守恆;配件是視覺根節點的子節點,跟著一起伸縮。每影格只改兩個縮放值,成本可忽略。
@export var breathing_enabled := false
@export var breath_amount := 0.012
@export var breath_period := 4.5
var _breath_time := 0.0
var _overlays: PetOverlays


func set_breathing(on: bool) -> void:
	breathing_enabled = on
	if not on:
		_apply_scale()
	set_process(on)


func _process(delta: float) -> void:
	if not breathing_enabled:
		set_process(false)
		return
	_breath_time += delta
	var wave := sin(_breath_time * TAU / maxf(breath_period, 0.5))
	var multiplier := params.scale_multiplier
	_visual_root.scale = Vector2(_visual_sign() * multiplier * (1.0 - breath_amount * 0.3 * wave), multiplier * (1.0 + breath_amount * wave))


## 這隻半身立繪在 DrawLayers.STILL 帶裡的第幾格(0 起算,依生成先後):本體的 z_index 由它決定,
## 配件用相對 z(-1 / 0 / +1),所以部件不會跑到別的桌寵前面。
func set_still_band(index: int) -> void:
	z_index = DrawLayers.still_z(index)


## 光源(見 PetLights):素材包 pack.json 的 lights 掛在視覺根節點底下;沒有光源就不建節點。
var _pet_lights: PetLights


func lights() -> PetLights:
	return _pet_lights


func _apply_lights(frames: SpriteFrames) -> void:
	if _visual_root == null:
		return
	var list: Array = frames.get_meta("lights", []) if frames != null else []
	if _pet_lights == null:
		if list.is_empty():
			return
		_pet_lights = PetLights.new()
		_visual_root.add_child(_pet_lights)
		_pet_lights.setup(self)
	_pet_lights.set_lights(list)


## 目前動畫對應的動作名稱(去掉 _編號 後綴,如 pose_05_0 → pose_05);配件依它決定顯示哪些。
func current_animation_action() -> StringName:
	var text := String(_logical_animation)
	var split := text.rfind("_")
	if split > 0 and text.substr(split + 1).is_valid_int():
		return StringName(text.substr(0, split))
	return _logical_animation


func is_speaking_now() -> bool:
	return _speaking


## 本體目前播到第幾幀(眨眼/說話差分動畫顯示中時,取切換前記下的本體幀),配件的逐幀錨點用它。
func body_frame() -> int:
	return _saved_frame if _overlay_shown else _sprite.frame


## 裝上浮動差分與配件(半身立繪的 overlays.json 內容,圖片相對於 base_dir)。回傳讀取報告;已經裝過的會先換掉。
func attach_overlays(spec: Dictionary, base_dir: String) -> Array[String]:
	if _overlays != null:
		_overlays.queue_free()
		_overlays = null
	var report: Array[String] = []
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(&"idle_0"):
		report.append("還沒有立繪圖片,無法裝配件。")
		return report
	var base_size := Vector2(_sprite.sprite_frames.get_frame_texture(&"idle_0", 0).get_size())
	_overlays = PetOverlays.new()
	_visual_root.add_child(_overlays)
	report = _overlays.setup(self, spec, base_dir, base_size, _sprite.position)
	_overlays.set_disabled(disabled_accessories)
	if _overlays.part_count() == 0:
		_overlays.queue_free()
		_overlays = null
	return report


func overlays() -> PetOverlays:
	return _overlays


## 右鍵選單「變更配件」關掉的配件名稱(存在角色設定檔的 "accessories")。
var disabled_accessories: Array[String] = []


func set_disabled_accessories(names: Variant) -> void:
	disabled_accessories.clear()
	if names is Array:
		for entry: Variant in names:
			if str(entry) != "" and not disabled_accessories.has(str(entry)) and disabled_accessories.size() < PetOverlays.MAX_PARTS:
				disabled_accessories.append(str(entry))
	if _overlays != null:
		_overlays.set_disabled(disabled_accessories)


## 開或關一個配件並存檔。
func set_accessory_enabled(part_name: String, enabled: bool) -> void:
	disabled_accessories.erase(part_name)
	if not enabled:
		disabled_accessories.append(part_name)
	if _overlays != null:
		_overlays.set_disabled(disabled_accessories)
	PetProfile.save_pet(self)


## 貼合行動框底部移動(右鍵選單開關;半身立繪預設開):腳底永遠貼著行動區底邊,拖曳與各種移動只沿著底邊橫向走。
## 固定模式的貼底角色由 DesktopShell 依在場數平均排開(見 _layout_bottom_pets);會動的桌寵(地面、飛行、漂浮)不排開,只是不離開底邊(不跳、不爬、不上平臺)。
var bottom_anchored := false


func set_bottom_anchored(on: bool) -> void:
	bottom_anchored = on
	if on and _action_area != null:
		position = clamp_to_bounds(position)
		velocity.y = 0.0
		if _climb != ClimbState.NONE:
			_exit_climb(false, false)

# --- 攀爬(Shimeji 式) ---
## 允許這隻桌寵(地面模式時)爬牆與天花板。關閉時走到邊界牆照舊是轉身。存在角色設定檔(body.climb)。
@export var climb_enabled := false
## 攀爬中的動作:先找 climb_wall / climb_ceiling 素材,沒有就用 walk 動畫並把整隻轉 90°/180° 貼在牆上。
const CLIMB_ACTION_WALL := &"climb_wall"
const CLIMB_ACTION_CEILING := &"climb_ceiling"
## 每一段攀爬(爬牆一段/天花板一段)的持續秒數區間;時間到會隨機:鬆手掉下去、反向、或停一下。
const CLIMB_SEGMENT_TIME := Vector2(4.0, 9.0)
const CLIMB_PAUSE_TIME := Vector2(0.8, 2.0)
const CLIMB_LET_GO_CHANCE := 0.3
const CLIMB_REVERSE_CHANCE := 0.5
## 鬆手時離開牆面/天花板的距離與水平彈開速度(像素、像素/秒)。
const CLIMB_RELEASE_GAP := 3.0
const CLIMB_RELEASE_SPEED := 60.0
var _climb := ClimbState.NONE
## 牆:1 = 右牆、-1 = 左牆。
var _climb_side := 1
## 牆:-1 往上、1 往下;天花板:-1 往左、1 往右(世界座標方向)。
var _climb_dir := -1
var _climb_timer := 0.0
var _climb_pause := 0.0


func is_climbing() -> bool:
	return _climb != ClimbState.NONE


func set_climb_enabled(on: bool) -> void:
	climb_enabled = on
	if not on and is_climbing():
		_exit_climb(true)
## 固定模式下也能隨時拖曳(不必先解除鎖定)。半身立繪預設開;貼底角色只能沿著底邊左右拖,放開後不會被重新排開(layout_pinned)。
@export var drag_when_fixed := false
var layout_pinned := false
## 素材本身的朝向與慣例(朝右)相反時打開:整隻左右鏡像。面向對話對象、走路方向等邏輯照舊以「朝右」為準,顯示時再翻過來。
var art_flipped := false


func set_art_flipped(on: bool) -> void:
	art_flipped = on
	_apply_scale()


## 目前面向(1 = 朝右、-1 = 朝左,不含 art_flipped 的鏡像)。
func facing_direction() -> int:
	return _facing


## 轉身(積木 pet_flip 用):direction 1 / -1 指定,0 = 轉向另一邊。地面模式的桌寵下次開始走路時仍會依走向重新面向。
func turn(direction: int) -> void:
	_face(direction if direction != 0 else -_facing)


## 面向某個 x 座標(對方在右邊就朝右)。
func turn_toward(target_x: float) -> void:
	if not is_equal_approx(target_x, global_position.x):
		_face(1 if target_x > global_position.x else -1)


## 角色整體尺寸(視覺根節點與碰撞箱的縮放倍率;物理身體本身的 Transform Scale 永遠是 1)。
func set_body_scale(multiplier: float) -> void:
	params.scale_multiplier = clampf(multiplier, MIN_BODY_SCALE, MAX_BODY_SCALE)
	_apply_scale()


## 大張立繪縮小顯示用平滑取樣(像素風小圖維持最近點取樣才不會糊)。
func set_smooth_scaling(smooth: bool) -> void:
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if smooth else CanvasItem.TEXTURE_FILTER_NEAREST


## 使用者輸入給桌寵記下來的文字(稱呼等,名稱 → 已消毒的字串)。只當資料存放與顯示,見 PetText。
var text_values: Dictionary = {}
## 記憶被重置(見 reset_memory)時發出;直譯器據此觸發「當記憶被重置時」事件。
signal memory_reset
## 使用者在右鍵選單按「幫我決定」(抽籤);對話介面接手詢問選項並抽出結果。
signal decide_requested


## 洗白記憶:局部數值回到宣告的預設值、所有 Flag 與使用者輸入的文字清空。**不動**動作、對話氣泡、狀態鏡定義與介面設定;
## 狀態鏡的啟用狀態預設也保留(include_lenses 才一併解除)。回傳重置前的備份,給「復原」用。
func reset_memory(include_lenses := false) -> Dictionary:
	var backup := {"values": local_values.duplicate(true), "flags": flags.duplicate(true), "texts": text_values.duplicate(true), "lenses": active_lens_names()}
	local_values = {}
	flags = {}
	text_values = {}
	ValueGateway.init_defaults(self)
	if include_lenses:
		for lens_name: String in active_lens_names():
			disable_lens(lens_name)
	memory_reset.emit()
	return backup


## 用 reset_memory 回傳的備份還原(復原上一次重置)。
func restore_memory(backup: Dictionary) -> void:
	local_values = backup.get("values", {}).duplicate(true)
	flags = backup.get("flags", {}).duplicate(true)
	text_values = backup.get("texts", {}).duplicate(true)
	for lens_name in backup.get("lenses", []):
		enable_lens(str(lens_name))


## 生成先後編號(越小越早),同角色複製品選「最早/最晚」本體用。
var spawn_serial := 0


## 目前啟用中的狀態鏡名稱(依鏡片優先度排序),複製品狀態比對與存檔用。
func active_lens_names() -> Array:
	var names: Array = []
	for lens: PetStateLens in state_lenses:
		if _active_lenses.has(lens.lens_name):
			names.append(lens.lens_name)
	return names


## 讓這隻的狀態(局部數值、Flag、啟用中的狀態鏡)變成跟 source 一樣(克隆本體)。
func adopt_state_from(source: Node) -> void:
	local_values = source.local_values.duplicate(true)
	flags = source.flags.duplicate(true)
	game_stats = source.game_stats.duplicate(true)
	uptime_minutes = source.uptime_minutes
	var wanted: Array = source.active_lens_names()
	for lens_name: String in _active_lenses.keys():
		if not wanted.has(lens_name):
			disable_lens(lens_name)
	for lens_name: String in wanted:
		enable_lens(lens_name)


## 新增一個局部數值定義並寫入預設值。
func add_value_def(def: PetValueDef) -> void:
	value_defs.append(def)
	ValueGateway.init_defaults(self)


## 說點什麼:隨機挑一段符合目前狀態的閒聊對話(積木檔裡的「當閒聊時」事件)來說。沒有可說的回傳 false。
func say_something() -> bool:
	return logic != null and logic.say_something()


## 自動閒聊倒數(只在開關都開著時才會被呼叫,條件式更新)。時間到了如果現在不適合開口就 10 秒後再試。
func _tick_auto_chat(delta: float) -> void:
	if _auto_chat_left < 0.0:
		_reset_auto_chat_timer()
	_auto_chat_left -= delta * lens_mod("chat")   # 悠哉比較常開口聊天、疲憊比較少
	if _auto_chat_left > 0.0:
		return
	if _can_auto_chat() and say_something():
		_shell_state.note_auto_chat_started()
		_reset_auto_chat_timer()
	else:
		# 現在不適合(自己正忙,或別隻剛說過/正在說):隨機等一下再試,不要固定秒數,
		# 否則被同一件事擋住的好幾隻會同時醒來再撞一次。
		_auto_chat_left = randf_range(AUTO_CHAT_RETRY_SECONDS.x, AUTO_CHAT_RETRY_SECONDS.y)


func _reset_auto_chat_timer() -> void:
	_auto_chat_left = randf_range(minf(auto_chat_interval.x, auto_chat_interval.y), maxf(auto_chat_interval.x, auto_chat_interval.y))


## 使用者剛互動過(10 秒內)、正在拖曳/入場/被互動中、有對話進行中、右鍵穿透中、動作被積木佔用中都不適合開口;
## 多隻桌寵同時在場時,還要輪到自己(沒有任何一隻在說話、距離上一次自動閒聊夠久),見 DesktopShellState.can_auto_chat()。
func _can_auto_chat() -> bool:
	if dragging or entering or _dialogue_open or _speaking or _shell_state.is_passthrough_frozen:
		return false
	if not _shell_state.can_auto_chat():
		return false
	return _interact_left <= 0.0 and _hold_left <= 0.0 and Time.get_ticks_msec() - _last_user_msec > AUTO_CHAT_QUIET_MSEC


## 目前的閒聊情境,決定哪些閒聊對話有資格被挑中:sleep 睡眠中、rest 休息中(坐下/躺下/飛行降落休息)、chat 其餘。
func chat_context() -> StringName:
	if _requested_action == &"sleep":
		return &"sleep"
	if _requested_action == &"sit" or _requested_action == &"lay" or (move_mode == MoveMode.FLYING and _fly_state == FlyState.RESTING):
		return &"rest"
	return &"chat"


## 使用者點擊或摸摸:即時互動優先於積木,中止舊的積木鏈與動作佔用(企劃書模組 D「事件打斷優先級」)。
## 睡著的桌寵被戳不會醒:連續點 3 次(SLEEP_POKE_WINDOW 秒內)才跳出氣泡選項問要不要叫醒(叫醒會讓懶惰的桌寵不高興,見 PetVitality.wake_mood_penalty)。
const SLEEP_POKES_TO_ASK := 3
const SLEEP_POKE_WINDOW_MSEC := 4000
var _sleep_pokes: Array[int] = []
var _asking_wake := false


func _on_user_poked() -> void:
	if vitality != null and vitality.mode == PetVitality.Mode.SLEEPING:
		_poke_sleeping()
		return
	_sleep_pokes.clear()
	_interrupt()
	effects.play_interaction("click")


func _poke_sleeping() -> void:
	var now := Time.get_ticks_msec()
	_last_user_msec = now
	_sleep_pokes.append(now)
	_sleep_pokes = _sleep_pokes.filter(func(stamp: int) -> bool: return now - stamp <= SLEEP_POKE_WINDOW_MSEC)
	effects.play_interaction("click")
	if _sleep_pokes.size() >= SLEEP_POKES_TO_ASK and not _asking_wake:
		_sleep_pokes.clear()
		_ask_wake_up()


func _ask_wake_up() -> void:
	_asking_wake = true
	var choice: int = await GameChat.ask(self, tr("(要叫醒%s嗎?)") % display_name, [tr("叫醒"), tr("還是不了")], 20.0)
	_asking_wake = false
	if not is_instance_valid(self) or vitality == null:
		return
	if choice == 0:
		vitality.wake_by_user()
	elif vitality.mode == PetVitality.Mode.ACTIVE:
		vitality.resume_sleep()   # 問話的過程中被吵醒了,選了讓牠繼續睡就躺回去


## 正在睡覺/休息(站著發呆、坐下、睡著)或在玩球時被摸摸:不該切去播 interact 打斷手上的事
## (2026-09-30 使用者實機回報,玩球時摸摸會讓桌寵放棄玩球、睡著/坐下休息時摸摸會讓桌寵站起來)。
## 這幾種情況下只在有「被觸摸」的專屬台詞(積木事件或性格反應)時才用 logic.fire_event() 觸發那段台詞
## (只發事件、不真的切動作,睡覺/休息/玩球的動畫照常播),完全沒有台詞就整次摸摸當作沒發生,連摸摸的
## 特效跟心情加成都不觸發。
func _is_petting_protected() -> bool:
	return is_sleeping() or is_resting_now() or (ball_play != null and ball_play.active())


## 摸摸是「短期突發」的互動:桌寵停下來播 interact,一直摸就一直播,停手後再持續 PETTING_TAIL 秒才恢復。
## 刻意不呼叫 _interrupt():不中止進行中的積木鏈、不動任何長期狀態(run 開關、狀態鏡、跟隨…),
## 停手後桌寵回到原本的行為(照 run 開著就跑、狀態鏡的動作前綴與數值覆蓋原封不動)。只解除積木指定動作的佔用,好讓 interact 顯示出來。
func _on_petted() -> void:
	if _is_petting_protected():
		if logic != null and logic.has_action_hat(&"interact"):
			logic.fire_event(&"interact")
			if vitality != null:
				vitality.on_petted()
		return
	effects.play_interaction("pet")
	_last_user_msec = Time.get_ticks_msec()
	release_hold()
	_dance_left = 0.0
	_interact_left = maxf(_interact_left, PETTING_TAIL)


## 摸摸中每次來回搖晃都把倒數重新拉回 PETTING_TAIL,所以是「停手後 1 秒」而不是「偵測到摸摸後 1 秒」。
func _on_petting_moved() -> void:
	if _interact_left > 0.0:
		_last_user_msec = Time.get_ticks_msec()
		_interact_left = maxf(_interact_left, PETTING_TAIL)


## 即時互動的打斷:世代標記加一(舊的等待協程醒來會發現並中止)、解除動作佔用、通知氣泡等收掉。
func _interrupt() -> void:
	_last_user_msec = Time.get_ticks_msec()
	interrupt_scripts()


## 中止所有進行中的積木鏈與動作佔用(不算使用者互動,不會影響自動閒聊的「剛互動過」判斷)。測試者模式強制觸發前也用它清場。
func interrupt_scripts() -> void:
	_dance_left = 0.0
	_converse_left = 0.0
	action_generation += 1
	release_hold()
	stop_using_furniture()
	interrupted.emit()


## 顯示用名稱:同一個角色(辨識代號相同)在場有多隻時,PetRegistry 會依先後編成「Mal (1)」「Mal (2)」;只有一隻就是原名。
func get_label() -> String:
	return display_name if instance_index == 0 else "%s (%d)" % [display_name, instance_index]


func set_instance_index(index: int) -> void:
	if index != instance_index:
		instance_index = index
		label_changed.emit()


## 身體範圍(全域座標),對話氣泡排版用來避開桌寵本身與判斷頭頂/腳底位置。
func get_body_rect() -> Rect2:
	var rect := _hit_rect()
	return Rect2(to_global(rect.position), rect.size)


## 由生成者呼叫:告知這隻桌寵所在的行動區,移動邊界取自它的 boundary_rect。
func bind_action_area(area: Node2D) -> void:
	_action_area = area


## 換上一組動畫。動畫命名遵循本專案規格「動作名稱_編號」(例如 idle_0、walk_0)。
## 動畫循環了一圈:設定了「從指定幀循環」(素材包 loop_by_action,見 PackLoop)的動作,把幀接回指定的循環起點(第一圈從頭播、之後從這一幀開始)。
func _on_sprite_looped() -> void:
	var frames := _sprite.sprite_frames
	if frames == null:
		return
	var starts: Variant = frames.get_meta("loop_starts", {})
	if not starts is Dictionary:
		return
	var start := int((starts as Dictionary).get(str(_sprite.animation), 0))
	if start > 0 and start < frames.get_frame_count(_sprite.animation):
		_sprite.set_frame_and_progress(start, 0.0)


func set_sprite_frames(frames: SpriteFrames) -> void:
	_sprite.sprite_frames = frames
	_apply_lights(frames)
	_apply_hold_anchor(frames)
	_visual_bounds_cache.clear()
	_visual_recent_rect = Rect2()
	if frames.has_animation(&"idle_0"):
		var idle_texture: Texture2D = frames.get_frame_texture(&"idle_0", 0)
		var cell := Vector2(idle_texture.get_size())
		# 素材包(SpritePackLoader)把所有幀以軸心(腳底中心點)對齊、補成同一個畫布(AtlasTexture 的 margin):
		# 畫布底邊可能在軸心下方 ground_below 像素(沒裁掉的名字標籤、影子),圖片位置要把它算進去,軸心才剛好踩在腳底;
		# 點擊範圍/攀爬尺寸用待機幀在軸心以上的實際內容大小(body_size),才不會比人物大一圈。
		var ground_below := float(frames.get_meta("ground_below", 0.0))
		var body_size: Variant = frames.get_meta("body_size", Vector2.ZERO)
		if body_size is Vector2 and body_size != Vector2.ZERO:
			_frame_size = body_size
		elif idle_texture is AtlasTexture and (idle_texture as AtlasTexture).atlas != null:
			_frame_size = Vector2((idle_texture as AtlasTexture).region.size)
		else:
			_frame_size = cell
		_sprite.position = Vector2(0.0, -cell.y * 0.5 + ground_below)
	else:
		_sprite.position = Vector2(0.0, -_frame_size.y * 0.5)
	_finish_set_sprite_frames()


## 素材包在精靈圖編輯器存檔後,桌面上的桌寵直接換上新的圖(不用移除再放):pack 是 SpritePackLoader.load_pack 的結果。
## 只換外觀相關(動畫、判定框、光源、持有錨點、平滑、配件);縮放、朝向、位置、狀態、設定都是桌寵自己的,不動。
func reload_pack(pack: Dictionary) -> void:
	if not bool(pack.get("ok", false)):
		return
	var meta: Dictionary = pack["meta"]
	var keep_action := _requested_action
	set_sprite_frames(pack["frames"])
	set_smooth_scaling(bool(meta["smooth"]))
	var spec: Dictionary = meta.get("overlays", {})
	if not spec.is_empty():
		for line: String in attach_overlays(spec, str(meta["path"])):
			push_warning("[桌寵配件 %s] %s" % [display_name, line])
	elif _overlays != null:
		_overlays.queue_free()
		_overlays = null
	if keep_action != &"":
		play_action(keep_action)


func _finish_set_sprite_frames() -> void:
	_current_action = &""
	play_action(&"idle")


## 動畫播放的公開入口。找不到該動作時安全降級為 idle_0;idle_0 也不存在就什麼都不做,不遞迴。
## force_override 為 false 是自主行為的請求(最低優先級,積木/事件佔用期間會被忽略);為 true 是積木、事件或
## 對話的指定呼叫(SCRIPTED),會打斷自主行為並佔用至少一個動畫循環(見 _hold_left / extend_hold)。
## 拖曳、interact、入場屬於更高優先級,由內部直接呼叫 _play()。
func play_action(action_name: StringName, variant_index: int = -1, force_override: bool = false) -> void:
	_play(action_name, variant_index, ActionPriority.SCRIPTED if force_override else ActionPriority.AUTONOMOUS)


## 只播動畫、不發「開始這個動作」的訊號:引擎自己借用某個動作的外觀時用(例如踢球借 interact),
## 否則會被當成「被摸」——觸發被摸的台詞、心情與狀態鏡加速消退。
var _silent_announce := false


func play_action_silently(action_name: StringName, variant_index: int = -1, force_override: bool = false) -> void:
	_silent_announce = true
	play_action(action_name, variant_index, force_override)
	_silent_announce = false


## 對「現在正是這個動作」的積木等待延長佔用時間:讓「播放動作 → 等待/說話」期間維持該姿勢。
func extend_hold(seconds: float) -> void:
	if _hold_action != &"" and _hold_action == _current_action:
		_hold_left = maxf(_hold_left, seconds)


## 立刻解除積木指定動作的佔用,把控制權還給自主行為。
func release_hold() -> void:
	_hold_left = 0.0
	_hold_action = &""


## 啟用狀態鏡。已在啟用中就維持原本的啟用時間戳與逾時(條件事件每秒重複啟用不會讓計時重來)。
## 找不到這個名稱的鏡片回傳 false(警告一次,不中斷)。
func enable_lens(lens_name: String) -> bool:
	lens_name = LensBehavior.canonical_name(lens_name)
	var lens := _find_lens(lens_name)
	if lens == null:
		if not _warned_lenses.has(lens_name):
			_warned_lenses[lens_name] = true
			push_warning("桌寵沒有狀態鏡 '%s',已略過" % lens_name)
		return false
	if _active_lenses.has(lens_name):
		return true
	var now := Time.get_ticks_msec()
	var timeout := lens.roll_timeout()
	_active_lenses[lens_name] = {"since": now, "deadline": now + int(timeout * 1000.0) if timeout > 0.0 else 0, "round": 1}
	_rebuild_lens_effects()
	if timeout > 0.0 and lens_name == "奔跑" and lens_mod("run_duration") != 1.0:
		_active_lenses[lens_name]["deadline"] = now + int(timeout * lens_mod("run_duration") * 1000.0)   # 緊張:跑的時間比較短
	_refresh_lens()
	return true


func disable_lens(lens_name: String) -> void:
	lens_name = LensBehavior.canonical_name(lens_name)
	if _active_lenses.erase(lens_name):
		_rebuild_lens_effects()
		_refresh_lens()


## 解除所有目前生效、被標記為「負面」的狀態鏡(食物等通用解除機制用)。
func disable_negative_lenses() -> void:
	var changed := false
	for lens in state_lenses:
		if lens.has_nature("負面") and _active_lenses.erase(lens.lens_name):
			changed = true
	if changed:
		_rebuild_lens_effects()
		_refresh_lens()


## 解除所有目前生效、標記為「正面」的狀態鏡。
func disable_positive_lenses() -> void:
	var changed := false
	for lens in state_lenses:
		if lens.has_nature("正面") and _active_lenses.erase(lens.lens_name):
			changed = true
	if changed:
		_rebuild_lens_effects()
		_refresh_lens()


## 重算目前狀態鏡合起來的效果。
func _rebuild_lens_effects() -> void:
	_lens_mods.clear()
	_lens_adds.clear()
	_lens_block_set.clear()
	for lens_name: String in _active_lenses:
		var entry := LensBehavior.of(lens_name)
		for key: String in entry:
			match key:
				"speed", "jump", "gravity", "mood_gain", "mood_loss", "fatigue", "run", "run_duration", "dance", "chat", "pause_time", "rest", "game_invite":
					_lens_mods[key] = float(_lens_mods.get(key, 1.0)) * float(entry[key])
				"game_accept", "game_refuse", "pause_chance", "mood_drift":
					_lens_adds[key] = float(_lens_adds.get(key, 0.0)) + float(entry[key])
				"block":
					for what: String in entry[key]:
						_lens_block_set[what] = true
		# 這個狀態鏡自己額外設定的「容易呼叫哪些行為」倍率(見 PetStateLens.behavior_overrides,不限六個內建名稱都能設,
		# 跟上面內建表的倍率相乘,不是取代)。
		var lens := _find_lens(lens_name)
		if lens != null:
			for key: String in lens.behavior_overrides:
				if PetStateLens.BEHAVIOR_KEYS.has(key):
					_lens_mods[key] = float(_lens_mods.get(key, 1.0)) * float(lens.behavior_overrides[key])
	_lens_gravity = float(_lens_mods.get("gravity", 1.0))


func lens_mod(key: String) -> float:
	return float(_lens_mods.get(key, 1.0))


func lens_add(key: String) -> float:
	return float(_lens_adds.get(key, 0.0))


## 生效中的狀態鏡有沒有擋掉這件事(climb 爬牆、dance 跳舞、run 奔跑、ball 玩球、game 遊戲與對戰)。
func lens_blocks(what: String) -> bool:
	return _lens_block_set.has(what)


## 有互動發生(touch 被摸、liked_prop 喜歡的道具、prop 任何道具)時,讓對應的狀態鏡更快結束:縮短剩餘時間;沒有逾時的(疲憊)改成恢復精力。
func hasten_lenses(event: String) -> void:
	var changed := false
	for lens_name: String in _active_lenses.keys():
		var amount := LensBehavior.hasten_amount(lens_name, event)
		if amount <= 0.0:
			continue
		var entry: Dictionary = _active_lenses[lens_name]
		if int(entry["deadline"]) > 0:
			entry["deadline"] = int(entry["deadline"]) - int(amount * 1000.0)
			changed = true
		elif lens_name == PetVitality.TIRED_LENS and vitality != null:
			vitality.restore_energy(amount)
	if changed:
		_tick_lenses()


func is_lens_active(lens_name: String) -> bool:
	return _active_lenses.has(LensBehavior.canonical_name(lens_name))


## 從啟用那一刻起算的秒數;沒啟用回傳 0(解除時時間戳重置,下次啟用重新起算)。
func lens_active_seconds(lens_name: String) -> float:
	lens_name = LensBehavior.canonical_name(lens_name)
	if not _active_lenses.has(lens_name):
		return 0.0
	return (Time.get_ticks_msec() - int(_active_lenses[lens_name]["since"])) / 1000.0


## 啟用時間戳(msec),沒啟用回傳 -1。限時啟用用它判斷「到期時還是不是同一次啟用」。
func lens_stamp(lens_name: String) -> int:
	lens_name = LensBehavior.canonical_name(lens_name)
	return int(_active_lenses[lens_name]["since"]) if _active_lenses.has(lens_name) else -1


func current_lens_name() -> String:
	return _current_lens_name


## 鏡片定義被編輯(改名、刪除、覆蓋數值、前綴…)後呼叫:丟掉已不存在的啟用項、還原舊覆蓋、重新仲裁並套用。
func reapply_lenses() -> void:
	for lens_name: String in _active_lenses.keys():
		if _find_lens(lens_name) == null:
			_active_lenses.erase(lens_name)
	for prop: String in _lens_base_values:
		params.set(prop, _lens_base_values[prop])
	_lens_base_values.clear()
	_lens_prefix = ""
	_current_lens_name = "<reapply>"
	_rebuild_lens_effects()
	_refresh_lens()


## 角色原始的行動物理數值(不含狀態鏡覆蓋);管理介面顯示「沒覆蓋時是多少」用。
func base_param(prop: StringName) -> float:
	return float(_lens_base_values.get(String(prop), params.get(prop)))


func find_lens(lens_name: String) -> PetStateLens:
	return _find_lens(lens_name)


func _find_lens(lens_name: String) -> PetStateLens:
	lens_name = LensBehavior.canonical_name(lens_name)
	for lens in state_lenses:
		if lens.lens_name == lens_name:
			return lens
	return null


## 重新仲裁堆疊:取優先度最高的啟用鏡片;變了才還原舊覆蓋、套用新覆蓋、重置動畫查找並發訊號。
func _refresh_lens() -> void:
	var top: PetStateLens = null
	for lens in state_lenses:
		if _active_lenses.has(lens.lens_name):
			top = lens
			break
	var top_name := top.lens_name if top != null else ""
	if top_name == _current_lens_name:
		return
	for prop: String in _lens_base_values:
		params.set(prop, _lens_base_values[prop])
	_lens_base_values.clear()
	_lens_prefix = top.prefix if top != null else ""
	if top != null:
		for prop: String in top.movement_overrides:
			if PetStateLens.OVERRIDABLE.has(StringName(prop)):
				_lens_base_values[prop] = params.get(prop)
				params.set(prop, float(top.movement_overrides[prop]))
	_current_lens_name = top_name
	if _hold_left <= 0.0:
		_current_action = &""
	active_state_lens_changed.emit(top_name)


## 只在有鏡片啟用時才會被呼叫(條件式更新):把到期的逾時鏡片解除。
func _tick_lenses() -> void:
	var now := Time.get_ticks_msec()
	var expired: Array[String] = []
	for lens_name: String in _active_lenses:
		var deadline: int = _active_lenses[lens_name]["deadline"]
		if deadline > 0 and now >= deadline:
			expired.append(lens_name)
	for lens_name in expired:
		var entry: Dictionary = _active_lenses[lens_name]
		var lens := _find_lens(lens_name)
		var rounds := int(entry.get("round", 1))
		if lens != null and lens.continues(rounds, randf()):
			entry["round"] = rounds + 1
			entry["deadline"] = now + int(maxf(lens.roll_timeout(), 0.5) * 1000.0)   # 延續執行判定:再來一輪
			continue
		disable_lens(lens_name)


## 目前生效狀態鏡的前綴差分池有這個動作就用它,沒有就用通用動作名稱。
func _lens_base(action: StringName) -> StringName:
	if _lens_prefix != "":
		var prefixed := StringName(_lens_prefix + action)
		if not _find_variants(prefixed).is_empty():
			return prefixed
	return action


func _play(action_name: StringName, variant_index: int, priority: ActionPriority) -> void:
	if _sprite.sprite_frames == null:
		return
	if priority == ActionPriority.AUTONOMOUS and _hold_left > 0.0:
		return
	if priority > ActionPriority.SCRIPTED:
		release_hold()
	# 「當角色正在 [動作] 時」事件以「被要求播放的動作」為準(素材缺該動作、實際退回別的動畫時也照樣觸發)。
	# 訊號要等動畫切換完才發:接著執行的積木鏈可能立刻呼叫 play_action,不能被這一次的切換覆蓋掉。
	var announce := action_name != _requested_action
	_requested_action = action_name
	_start_animation(action_name, variant_index, priority)
	if announce and not _silent_announce:
		action_started.emit(action_name)


func _start_animation(action_name: StringName, variant_index: int, priority: ActionPriority) -> void:
	# 查找順序:目前生效狀態鏡的前綴差分池 → 通用差分池 → lay 退回 sit → 最終退回 idle_0。
	var resolved := action_name
	if not interaction_rules["actions"].is_empty():
		# 交互行為頁籤:這個事件改用別的動作(素材沒有那個動作就照原本的)。
		var mapped := InteractionRules.mapped_action(interaction_rules, action_name)
		if mapped != action_name and not _find_variants(_lens_base(mapped)).is_empty():
			resolved = mapped
	var base := _lens_base(resolved)
	var variants := _find_variants(base)
	if variants.is_empty() and resolved == &"lay":
		# lay 與 sit 定義相似,缺 lay 素材時先退回 sit,再不行才退回 idle。
		resolved = &"sit"
		base = _lens_base(resolved)
		variants = _find_variants(base)
	if variants.is_empty() and (action_name == CLIMB_ACTION_WALL or action_name == CLIMB_ACTION_CEILING):
		# 攀爬沒有專屬素材:用 walk 動畫(整隻已被轉到貼牆的角度),再沒有才落到下面的 idle 降級。
		resolved = &"walk"
		base = _lens_base(resolved)
		variants = _find_variants(base)
	if variants.is_empty() and action_name == &"fly":
		# 沒有專屬的 fly 動作:往上飛播 rise、其餘播 fall(原本飛行模式的樣子),都沒有才退回 walk。
		for fallback: StringName in [&"rise" if velocity.y < -20.0 else &"fall", &"fall", &"walk"]:
			base = _lens_base(fallback)
			variants = _find_variants(base)
			if not variants.is_empty():
				resolved = fallback
				break
	if variants.is_empty() and action_name != &"idle":
		if not _warned_actions.has(action_name):
			_warned_actions[action_name] = true
			push_warning("桌寵沒有動作 '%s',降級為 idle_0" % action_name)
		resolved = &"idle"
		base = _lens_base(resolved)
		variants = _find_variants(base)
		variant_index = 0
	if variants.is_empty():
		return
	# 「播一次,停在指定幀」「循環 N 次」(PackLoop mode=once/repeat)播完就停在最後一幀,Godot 原生行為是
	# is_playing() 變 false(不是壞掉,是設計上就該停在那一幀);同一個動作沒指定新變體時再被呼叫一次(自主行為
	# 每輪都會重新確認「現在該演哪個動作」,不是只在動作真的換了才呼叫)不該被這個「已經播完」誤判成要重播,
	# 不然停格瞬間就被自己重新播放蓋掉,變成「停不住、一直從頭重播」(2026-09-27 修正)。
	var current_loops := _sprite.sprite_frames.has_animation(_sprite.animation) and _sprite.sprite_frames.get_animation_loop(_sprite.animation)
	if resolved == _current_action and variant_index < 0 and (_sprite.is_playing() or _overlay_shown or not current_loops):
		if priority == ActionPriority.SCRIPTED:
			_start_hold(resolved, _logical_animation)
		return
	var index: int = variant_index if variants.has(variant_index) else variants.pick_random()
	var animation := StringName("%s_%d" % [base, index])
	_current_action = resolved
	_logical_animation = animation
	_overlay_shown = false
	_blink_left = 0.0
	_sprite.play(animation)
	_apply_overlay()
	if priority == ActionPriority.SCRIPTED:
		_start_hold(resolved, animation)


## 積木指定的動作至少要完整播完一個循環才交還控制權(太短的動畫給下限,避免一閃而過)。
func _start_hold(action: StringName, animation: StringName) -> void:
	_hold_left = maxf(_animation_length(animation), MIN_HOLD_TIME)
	_hold_action = action


func _animation_length(animation: StringName) -> float:
	var frames := _sprite.sprite_frames
	var speed := frames.get_animation_speed(animation)
	var total := 0.0
	for i in frames.get_frame_count(animation):
		total += frames.get_frame_duration(animation, i)
	return total / speed if speed > 0.0 else 0.0


## 對話氣泡的打字機滾動期間為 true:目前動作有 _sp 說話差分就切過去,沒有就維持原樣(缺差分不報錯)。
func set_speaking(speaking: bool) -> void:
	if _speaking == speaking:
		return
	_speaking = speaking
	_apply_overlay()


## 決定畫面上該顯示基底動畫還是子差分(說話優先於眨眼)。只在事件發生時呼叫(動作切換、開始/結束說話、眨眼開始/結束)。
func _apply_overlay() -> void:
	if _logical_animation == &"" or _sprite.sprite_frames == null:
		return
	var frames := _sprite.sprite_frames
	var wanted := _logical_animation
	var speak := StringName("%s_sp" % _logical_animation)
	var blink := _blink_animation_name()
	if _speaking and frames.has_animation(speak):
		wanted = speak
	elif _blink_left > 0.0 and blink != &"":
		wanted = blink
	var overlaid := wanted != _logical_animation
	if overlaid == _overlay_shown and (not overlaid or _sprite.animation == wanted):
		return
	if overlaid and not _overlay_shown:
		_saved_frame = _sprite.frame
		_saved_progress = _sprite.frame_progress
	_sprite.play(wanted)
	if not overlaid:
		_sprite.set_frame_and_progress(_saved_frame, _saved_progress)
	_overlay_shown = overlaid


## 目前動畫的眨眼動畫名稱:優先用「對應本體目前這一幀」的 <動畫>_bl_f<k>(素材包的逐幀眨眼,身體不會在眨眼時跳格),
## 沒有再用整個動畫共用的 <動畫>_bl(Mal 那種);都沒有回空字串。
func _blink_animation_name() -> StringName:
	var frames := _sprite.sprite_frames
	if frames == null or _logical_animation == &"":
		return &""
	var body_frame := _saved_frame if _overlay_shown else _sprite.frame
	var synced := StringName("%s_bl_f%d" % [_logical_animation, body_frame])
	if frames.has_animation(synced):
		return synced
	var shared := StringName("%s_bl" % _logical_animation)
	return shared if frames.has_animation(shared) else &""


## 自然眨眼:隔一段隨機時間,目前動畫有 _bl 差分就短暫切過去(說話中不眨)。沒有差分的動畫只是空轉計時。
func _tick_blink(delta: float) -> void:
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0:
			_blink_left = 0.0
			_apply_overlay()
		return
	_blink_next -= delta
	if _blink_next > 0.0:
		return
	_blink_next = randf_range(BLINK_INTERVAL.x, BLINK_INTERVAL.y)
	var blink := _blink_animation_name()
	if not _speaking and _logical_animation != &"" and blink != &"":
		_blink_left = maxf(_animation_length(blink), MIN_BLINK_TIME)
		_apply_overlay()


## 進入固定/靜止模式前,使用者自己設定的「不會被其他桌寵跟隨」「不跟隨其他桌寵」「不主動使用家具」
## (見 InteractionRules 開頭的說明);離開固定/靜止模式時換回來。固定⇄靜止互相切換(兩種都算「受限」)
## 不會重新蓋掉這份備份,只在真正離開受限模式時才清掉、換回去。
var _move_mode_forced_backup: Dictionary = {}


func _apply_move_mode_interaction_defaults(new_mode: MoveMode) -> void:
	var was_restricted := move_mode == MoveMode.FIXED or move_mode == MoveMode.STATIONARY
	var will_be_restricted := new_mode == MoveMode.FIXED or new_mode == MoveMode.STATIONARY
	if not was_restricted and not will_be_restricted:
		return
	var rules := interaction_rules.duplicate(true)
	if will_be_restricted:
		if not was_restricted:
			_move_mode_forced_backup = {"no_follow_target": bool(rules.get("no_follow_target", false)),
				"no_follow_source": bool(rules.get("no_follow_source", false)), "ignore_furniture": bool(rules.get("ignore_furniture", false))}
		rules["no_follow_target"] = true
		rules["no_follow_source"] = true
		rules["ignore_furniture"] = new_mode == MoveMode.FIXED or bool(_move_mode_forced_backup.get("ignore_furniture", false))
	elif not _move_mode_forced_backup.is_empty():
		rules["no_follow_target"] = bool(_move_mode_forced_backup.get("no_follow_target", false))
		rules["no_follow_source"] = bool(_move_mode_forced_backup.get("no_follow_source", false))
		rules["ignore_furniture"] = bool(_move_mode_forced_backup.get("ignore_furniture", false))
		_move_mode_forced_backup = {}
	set_interaction_rules(rules)


func set_move_mode(mode: MoveMode) -> void:
	_apply_move_mode_interaction_defaults(mode)
	_exit_climb(false, false)
	move_mode = mode
	_hybrid_airborne = false
	velocity = Vector2.ZERO
	_current_action = &""
	_walk_dir = 1 if randf() < 0.5 else -1
	match mode:
		MoveMode.GROUND, MoveMode.STATIONARY:
			collision_mask = Layers.PLATFORM | Layers.BOUNDARY_WALL
			_enter_idle()
		MoveMode.FIXED:
			collision_mask = 0
		MoveMode.FLYING:
			collision_mask = Layers.PLATFORM | Layers.BOUNDARY_WALL
			_fly_reset()
			if fly_behavior == FlyBehavior.HYBRID:
				_enter_idle()   # 兼具模式從地面開始
		MoveMode.FLOATING:
			# 漂浮模式完全無視站立平臺,只與行動區邊界牆、視窗邊界牆碰撞。
			collision_mask = Layers.BOUNDARY_WALL | Layers.WINDOW_WALL
	move_mode_changed.emit(mode)


## 目前持有的小道具名稱(可持有的道具被拾取後記在這裡;空 = 沒有);積木條件「目前持有道具」讀它。設定時手上會畫出那個道具(見 PetHeldProp)。
var held_prop := "":
	set(value):
		held_prop = value
		_refresh_held_visual()
var _held_visual: PetHeldProp
var _held_def: PropDef
var _held_size := 40.0
## 素材包 pack.json 的 hold_anchor(相對腳底線中心、縮放前像素,面向右時的位置);null = 沒設,用預設位置。
var _hold_anchor: Variant = null


## 手拿東西的位置:素材包設的持有錨點,沒設就在判定框前側、約胸口的高度。
func hold_anchor() -> Vector2:
	if _hold_anchor is Vector2:
		return _hold_anchor
	var box := effective_hitbox_size()
	return Vector2(box.x * 0.5, -box.y * 0.4)


func _apply_hold_anchor(frames: SpriteFrames) -> void:
	var value: Variant = frames.get_meta("hold_anchor") if frames != null and frames.has_meta("hold_anchor") else null
	_hold_anchor = value if value is Vector2 else null
	if _held_visual != null:
		_held_visual.position = _held_position()


## 持有物畫的位置:道具設定「手上」用持有錨點,「頭頂」用判定框頭頂(道具底邊坐在頭上)。
func _held_position() -> Vector2:
	var def := _held_def
	if def != null and def.hold_place == "head":
		var box := effective_hitbox_size()
		var offset := effective_hitbox_offset()
		return Vector2(offset.x, offset.y - box.y - _held_size * 0.5)
	return hold_anchor()


func _refresh_held_visual() -> void:
	if _visual_root == null:
		return
	if _held_visual != null:
		_held_visual.queue_free()
		_held_visual = null
	if held_prop == "":
		return
	var def := PropLibrary.find_by_name(held_prop)
	_held_def = def
	_held_size = clampf(effective_hitbox_size().y * 0.32, 18.0, 60.0)
	_held_visual = PetHeldProp.new()
	_visual_root.add_child(_held_visual)
	_held_visual.setup(held_prop, PropLibrary.texture_of(def) if def != null else null, _held_size)
	_held_visual.position = _held_position()


## 放下手上的道具:可以撿的道具(丟入拾取)從手的位置掉到地上(2 秒內同一隻不會馬上又撿起來),不能撿的直接消失。沒拿東西回 false。
func drop_held_prop() -> bool:
	if held_prop == "":
		return false
	var def := PropLibrary.find_by_name(held_prop)
	var hand_position := _held_visual.global_position if _held_visual != null else global_position
	held_prop = ""
	if def != null and def.toss:
		for manager: Node in get_tree().get_nodes_in_group("prop_manager"):
			var item: PropItem = manager.spawn(def, hand_position + Vector2(0.0, PropItem.SIZE * 0.5))
			item.pickup_delay = 2.0
			break
	return true
## 累計被道具觸發的次數(拾取或摩擦都算,不管有沒有反應)。
var prop_interactions := 0
## 交互行為頁籤的設定(見 InteractionRules):事件 → 動作的對應、對其他角色與道具的反應。存在角色設定檔的 "interaction"。
var interaction_rules: Dictionary = InteractionRules.empty()
## 道具交互中持續播的動作(持續到道具用完 / 離開判定,見 begin_prop_action);空 = 沒有。
var _prop_action := &""
var _prop_action_left := 0.0


## 套用交互行為設定(整理過);對話部分編譯後交給解譯器的規則層。
func set_interaction_rules(raw: Variant) -> void:
	interaction_rules = InteractionRules.clean(raw)
	if logic != null:
		logic.set_rule_layer(InteractionRules.compile(interaction_rules))


## 這隻桌寵素材裡有的動作名稱(去掉 _編號;眨眼/說話差分、狀態鏡前綴以外的都算),依字母排序;交互行為頁籤的動作下拉選單用。
func action_names() -> Array[String]:
	var found := {}
	if _sprite != null and _sprite.sprite_frames != null:
		for animation: StringName in _sprite.sprite_frames.get_animation_names():
			var text := String(animation)
			var split := text.rfind("_")
			if split <= 0 or not text.substr(split + 1).is_valid_int() or "_bl" in text or text.ends_with("_sp"):
				continue
			found[text.substr(0, split)] = true
	var names: Array[String] = []
	for key: String in found:
		names.append(key)
	names.sort()
	return names


## 道具交互時播一個動作:persist = false 只做一次;true = 持續播,直到被 keep_prop_action 續命的時間到(道具用完、離開判定後再多一小段,像摸摸移開那樣)。
## seconds = 一開始就保證持續多久(道具的使用動畫長度)。動作是積木等級(SCRIPTED)的,會蓋過自主行為。
func begin_prop_action(action: StringName, persist: bool, seconds := 0.0) -> void:
	if action == &"":
		return
	play_action(action, -1, true)
	if persist:
		_prop_action = action
		_prop_action_left = maxf(seconds, PROP_ACTION_TAIL)
		hold_still_for(_prop_action_left)


## 道具還在(壓在身上、被摩擦中…)時每個物理影格呼叫,讓持續動作不要結束。
func keep_prop_action(seconds := PROP_ACTION_TAIL) -> void:
	if _prop_action != &"":
		_prop_action_left = maxf(_prop_action_left, seconds)
		hold_still_for(seconds)


const PROP_ACTION_TAIL := 0.6


func _tick_prop_action(delta: float) -> void:
	if _prop_action_left <= 0.0:
		return
	_prop_action_left -= delta
	if _prop_action_left <= 0.0:
		_prop_action = &""
		release_hold()
		return
	play_action(_prop_action, -1, true)
	extend_hold(0.3)


## 飛行模式:道具交互(被拿來洗澡、使用道具、道具壓在身上)時先降落,交互完再起飛;關掉就原地懸停。桌寵設定可調。
var land_for_props := true
## 道具交互中原地不動的倒數(秒),見 hold_still_for。
var _prop_still_left := 0.0


## 穿過平臺往下:站在平臺上(不是行動區最底下的地面)、想去的地方(滑鼠、喜歡的道具、跟隨對象)在正下方卻被平臺擋住時,每秒有 DROP_THROUGH_CHANCE 的機率決定往下穿:
## 暫時不和平臺碰撞 DROP_THROUGH_SECONDS 秒,落到下面再恢復(最底下的地面不會被穿)。機率刻意設低,主要是不讓桌寵被平臺堵住去路。
const DROP_THROUGH_CHANCE := 0.3
const DROP_THROUGH_SECONDS := 0.35
const DROP_THROUGH_MIN_DEPTH := 40.0
const DROP_THROUGH_REACH_X := 70.0
var _drop_through_left := 0.0
var _drop_check_left := 0.0


## 該不該往下穿:回傳有沒有真的開始穿(給測試用)。roll = 0~1 的隨機數,負數 = 現場擲。
func maybe_drop_through(goal: Vector2, delta: float, roll := -1.0) -> bool:
	if _drop_through_left > 0.0 or not is_on_floor() or _climb != ClimbState.NONE or move_mode == MoveMode.FLOATING or move_mode == MoveMode.FIXED:
		return false
	if goal.y <= position.y + DROP_THROUGH_MIN_DEPTH or absf(goal.x - position.x) > DROP_THROUGH_REACH_X:
		return false
	if _action_area == null or position.y >= _bounds().end.y - GROUND_TOP_OFFSET - 18.0:
		return false   # 已經在最底下的地面
	_drop_check_left -= delta
	if _drop_check_left > 0.0:
		return false
	_drop_check_left = 1.0
	if (randf() if roll < 0.0 else roll) >= DROP_THROUGH_CHANCE:
		return false
	_drop_through_left = DROP_THROUGH_SECONDS
	collision_mask &= ~Layers.PLATFORM
	velocity.y = 160.0
	position.y += 2.0
	_airborne_grace = maxf(_airborne_grace, 0.15)
	return true


func _tick_drop_through(delta: float) -> void:
	if _drop_through_left <= 0.0:
		return
	_drop_through_left -= delta
	if _drop_through_left <= 0.0 and _climb == ClimbState.NONE and (move_mode == MoveMode.GROUND or move_mode == MoveMode.STATIONARY or move_mode == MoveMode.FLYING):
		collision_mask |= Layers.PLATFORM


## 道具交互時讓桌寵原地不動 seconds 秒(重複呼叫取較長的);地面不走、飛行降落或懸停、漂浮停下來。
func hold_still_for(seconds: float) -> void:
	_prop_still_left = maxf(_prop_still_left, seconds)


## 雙擊:正在幫使用者計時的話,停下來報出計時狀況並問要做什麼(見 PetTimer.open_menu)。
func _on_double_clicked() -> void:
	if pet_timer != null and pet_timer.has_timing() and not _timer_menu_open:
		_timer_menu_open = true
		await pet_timer.open_menu()
		_timer_menu_open = false


var _timer_menu_open := false


## 提前結束「原地不動」(hold_still_for 設的倒數)。
func release_still() -> void:
	_prop_still_left = 0.0


## 現在該原地不動嗎:跳舞中、或道具交互中。這時不接受朝滑鼠/跟隨/道具吸引的移動目標,也不會自己開始走。
func is_holding_still() -> bool:
	return _dance_left > 0.0 or _prop_still_left > 0.0


## 桌寵本體的互動範圍(全域座標,判定框依縮放與攀爬姿勢轉過的外接矩形):小道具的拾取判定用。
func interaction_rect() -> Rect2:
	var size := effective_hitbox_size() * params.scale_multiplier
	var offset := effective_hitbox_offset() * params.scale_multiplier
	var local := Rect2(-size.x * 0.5 + offset.x, -size.y + offset.y, size.x, size.y)
	var rotated: Rect2 = body_pose_transform() * local
	return Rect2(global_position + rotated.position, rotated.size)


## 全域座標的點是否落在桌寵身上(點擊、拖曳、摸摸的命中範圍,跟穿透多邊形用同一塊矩形)。
func hit_test(global_point: Vector2) -> bool:
	return not entering and _hit_rect().has_point(to_local(global_point))


## 這個全域座標的點落在目前這一幀「有畫東西(不透明)」的像素上嗎?重疊的桌寵用它決定抓到哪一隻:
## 點在透明區域(例如角色旁邊的空白)不算,這樣能穿過上面那隻的空白處抓到下面那隻。讀不到像素資料時一律當作有。
static var _alpha_images: Dictionary = {}
const MAX_ALPHA_CACHE := 256


func pixel_hit(global_point: Vector2) -> bool:
	if _sprite == null or _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(_sprite.animation):
		return true
	var texture: Texture2D = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	if texture == null:
		return true
	var point := _sprite.to_local(global_point) - _sprite.offset + Vector2(texture.get_size()) * 0.5
	var source: Texture2D = texture
	var region_origin := Vector2.ZERO
	var region_size := Vector2(texture.get_size())
	if texture is AtlasTexture and (texture as AtlasTexture).atlas != null:
		var atlas := texture as AtlasTexture
		source = atlas.atlas
		point -= atlas.margin.position
		region_origin = atlas.region.position
		region_size = atlas.region.size
	if point.x < 0.0 or point.y < 0.0 or point.x >= region_size.x or point.y >= region_size.y:
		return false
	var key := source.get_instance_id()
	if not _alpha_images.has(key):
		if _alpha_images.size() >= MAX_ALPHA_CACHE:
			_alpha_images.clear()
		_alpha_images[key] = source.get_image()
	var image: Image = _alpha_images[key]
	if image == null or image.is_compressed():
		return true
	var pixel := region_origin + point
	return image.get_pixelv(Vector2i(int(pixel.x), int(pixel.y))).a > 0.1


## 目前允許被拖曳嗎?固定模式預設鎖定,要在選單勾「固定時可隨時拖曳」才拖得動。
func can_drag() -> bool:
	return not entering and (move_mode != MoveMode.FIXED or drag_when_fixed)


## 由生成者在置入後呼叫:進入入場保護,期間不可抓取並播放 enter 動作。
func begin_entrance() -> void:
	entering = true
	_entrance_left = entrance_duration
	_current_action = &""
	_play(&"enter", -1, ActionPriority.SYSTEM)
	entered.emit()


## 把座標限制在行動區內(碰撞箱不會超出邊界),拖曳與漂浮模式共用。
func clamp_to_bounds(point: Vector2) -> Vector2:
	var rect := _bounds()
	var half_width := BODY_SIZE.x * params.scale_multiplier * 0.5
	var height := BODY_SIZE.y * params.scale_multiplier
	var clamped := point.clamp(rect.position + Vector2(half_width, height), rect.end - Vector2(half_width, 0.0))
	if bottom_anchored:
		clamped.y = rect.end.y
	return clamped


func begin_drag() -> void:
	_exit_climb(false, false)
	dragging = true
	_interrupt()
	velocity = Vector2.ZERO
	_interact_left = 0.0
	_edge_committed = false
	_jump_target_x = NAN
	_play(&"drag", -1, ActionPriority.INTERACTION)
	effects.play_interaction("drag")


## 放開拖曳:把拖曳速度當成初速度拋出,之後交還給目前移動模式(地面/飛行順著重力落下或飛回巡航高度)。
func end_drag(throw_velocity: Vector2) -> void:
	dragging = false
	if move_mode == MoveMode.FIXED:
		velocity = Vector2.ZERO
		if bottom_anchored:
			layout_pinned = true
		return
	velocity = throw_velocity
	if move_mode == MoveMode.FLYING:
		# 飛行桌寵被拋出時保留慣性(見 _process_flying),滑行完再回到巡航。
		_fly_state = FlyState.CRUISE
		_fly_launch_left = FLY_LAUNCH_TIME
	# 拖曳前的「站在地面上」旗標是舊的,放開後第一個物理步驟會誤把水平速度當成待機歸零;
	# 被拋出時先短暫視為在空中,讓拋擲速度留到真的落地為止。
	_airborne_grace = THROW_GRACE if throw_velocity.length() > THROW_GRACE_MIN_SPEED else 0.0
	_current_action = &""
	if move_mode == MoveMode.GROUND or move_mode == MoveMode.STATIONARY:
		_enter_idle()


## 開始跟隨辨識代號為 tag 的桌寵。找不到目標,或會形成循環跟隨(A 跟 B、B 又跟 A,或更長的環)
## 時拒絕並回傳 false。跟隨對固定與靜止模式不生效。
## 不管這次跟隨是誰叫的(積木、選單、還是自己自主決定),一條路隊最長都是 FOLLOW_MAX_SECONDS(見
## _tick_pet_follow_lifecycle);自主決定跟隨時另外會把這個上限縮短成性格抽到的秒數。
func start_follow(tag: String) -> bool:
	var target := _find_pet_by_tag(tag)
	if target == null or target == self:
		push_warning("找不到要跟隨的桌寵 '%s'" % tag)
		return false
	var visited: Array[Node] = [self]
	var current: Node = target
	while current != null:
		if visited.has(current):
			push_warning("跟隨 '%s' 會形成循環,已拒絕" % tag)
			return false
		visited.append(current)
		current = _find_pet_by_tag(current._follow_tag, false) if current._follow_tag != "" else null
	_follow_tag = tag
	_follow_started = Time.get_ticks_usec()
	_follow_duration_cap = FOLLOW_MAX_SECONDS
	_follow_stuck_left = 0.0
	_follow_leader_resting = false
	_follow_leader_seeking_mouse = false
	interaction.follow_count += 1
	return true


## 目前這次跟隨的開始時間戳(沒在跟隨回傳 -1),限時跟隨用它判斷「到期時還是不是同一次跟隨」。
func follow_stamp() -> int:
	return _follow_started if _follow_tag != "" else -1


func stop_follow() -> void:
	_follow_tag = ""


func is_following() -> bool:
	return _follow_tag != ""


## 目前有沒有任何一隻桌寵正跟著自己走(領路人視角,給積木「當自己作為領路人時」用)。掃場上所有桌寵找
## 跟隨目標是自己的,不維護反向索引——路隊人數不多,現掃便宜,也不用煩惱跟隨關係變動時兩邊要同步更新。
func is_followed() -> bool:
	for other: Node in get_tree().get_nodes_in_group("pets"):
		if other != self and is_instance_valid(other) and other.is_following() and other._follow_tag == recognition_tag:
			return true
	return false


## 「跟著我」:跟著滑鼠走 follow_me_seconds 秒(選單指令與測試者面板用);性格參數 follow_me_seconds 可調,預設 1 分鐘。
var follow_me_seconds := 60.0
## 自己選擇跟著滑鼠:每 20~45 秒抽一次,機率 mouse_follow_chance(黏人的性格最高,0 = 不會),跟的秒數在 mouse_follow_duration 範圍內隨機。
var auto_mouse_follow_enabled := true
var mouse_follow_chance := 0.08
var mouse_follow_duration := Vector2(15.0, 45.0)
var _auto_mouse_left := -1.0
const AUTO_MOUSE_FOLLOW_CHECK := Vector2(20.0, 45.0)


## 這隻現在能不能跟著滑鼠:固定與靜止模式不動,其他(地面、飛行、漂浮)可以。
func can_follow_mouse() -> bool:
	return move_mode != MoveMode.FIXED and move_mode != MoveMode.STATIONARY


## 開始跟著滑鼠 seconds 秒(不給就用 follow_me_seconds)。不能動的模式回傳 false。
## 跟著別隻桌寵走的路隊到這裡算「想去做別的事情」,先自己離開跟隨(見 _tick_pet_follow_lifecycle 的說明)。
func follow_mouse(seconds := -1.0) -> bool:
	if not can_follow_mouse():
		return false
	if is_following():
		stop_follow()
	seek_mouse(seconds if seconds > 0.0 else follow_me_seconds, false)
	effects.play_interaction("follow")
	return true


func stop_follow_mouse() -> void:
	_seek_left = 0.0


func is_following_mouse() -> bool:
	return _seek_left > 0.0 and not _seek_away


## 依性格偶爾自己決定跟著滑鼠:睡著、被拖曳、忙著、攀爬中、心情差(負面狀態鏡)時不會。
func _tick_auto_mouse_follow(delta: float) -> void:
	if not auto_mouse_follow_enabled or mouse_follow_chance <= 0.0 or _seek_left > 0.0:
		return
	if _auto_mouse_left < 0.0:
		_auto_mouse_left = randf_range(AUTO_MOUSE_FOLLOW_CHECK.x, AUTO_MOUSE_FOLLOW_CHECK.y)
	_auto_mouse_left -= delta
	if _auto_mouse_left > 0.0:
		return
	_auto_mouse_left = randf_range(AUTO_MOUSE_FOLLOW_CHECK.x, AUTO_MOUSE_FOLLOW_CHECK.y)
	if not can_follow_mouse() or is_sleeping() or has_negative_lens() or is_busy_for_game():
		return
	if randf() < mouse_follow_chance:
		follow_mouse(randf_range(minf(mouse_follow_duration.x, mouse_follow_duration.y), maxf(mouse_follow_duration.x, mouse_follow_duration.y)))


# --- 路隊:自己選擇跟著別隻桌寵走(見 start_follow/_movement_goal 既有的跟隨移動與排隊間距) ---

## 自己選擇跟著別隻桌寵走:每 20~45 秒抽一次,機率 pet_follow_chance(黏人最高,內向、懶惰偏低;0 = 不會)。
var auto_pet_follow_enabled := true
var pet_follow_chance := 0.0
var pet_follow_duration := Vector2(60.0, 180.0)
var _auto_pet_follow_left := -1.0
const AUTO_PET_FOLLOW_CHECK := Vector2(20.0, 45.0)
## 一條路隊(不管是自己選的還是積木/選單叫的)最長維持這麼久,到了自動解散,見 start_follow。
const FOLLOW_MAX_SECONDS := 480.0
## 跟隨中連續這麼久、距離都超過這個範圍碰不到跟隨對象,就放棄這次跟隨。
const FOLLOW_STUCK_SECONDS := 20.0
const FOLLOW_STUCK_DISTANCE := 260.0


## 依性格偶爾自己決定跟著場上另一隻桌寵走:已經在跟(不管誰叫的)、跟著滑鼠、睡著、忙著、心情差時不會抽。
## 挑離自己最近、跟了不會形成循環的桌寵;跟隨秒數在 pet_follow_duration 範圍內隨機,但不會超過 FOLLOW_MAX_SECONDS。
func _tick_auto_pet_follow(delta: float) -> void:
	if not auto_pet_follow_enabled or pet_follow_chance <= 0.0 or is_following() or _seek_left > 0.0:
		return
	if _auto_pet_follow_left < 0.0:
		_auto_pet_follow_left = randf_range(AUTO_PET_FOLLOW_CHECK.x, AUTO_PET_FOLLOW_CHECK.y)
	_auto_pet_follow_left -= delta
	if _auto_pet_follow_left > 0.0:
		return
	_auto_pet_follow_left = randf_range(AUTO_PET_FOLLOW_CHECK.x, AUTO_PET_FOLLOW_CHECK.y)
	if move_mode == MoveMode.FIXED or move_mode == MoveMode.STATIONARY or is_sleeping() or is_resting_now() \
			or has_negative_lens() or is_busy_for_game() or dragging or entering or bool(interaction_rules.get("no_follow_source", false)):
		return
	if randf() >= pet_follow_chance:
		return
	var candidate := _nearest_followable_pet()
	if candidate == null:
		return
	if start_follow(candidate.recognition_tag):
		_follow_duration_cap = minf(randf_range(minf(pet_follow_duration.x, pet_follow_duration.y), maxf(pet_follow_duration.x, pet_follow_duration.y)), FOLLOW_MAX_SECONDS)


## 場上離自己最近、可以跟隨的桌寵(排除自己、正在入場/被收起的、設了「不會被其他桌寵跟隨」的、跟了會形成循環的);找不到回 null。
func _nearest_followable_pet() -> Node:
	var best: Node = null
	var best_distance := INF
	for other: Node in get_tree().get_nodes_in_group("pets"):
		if other == self or not is_instance_valid(other) or other.is_queued_for_deletion() or other.entering \
				or bool(other.interaction_rules.get("no_follow_target", false)):
			continue
		var distance := global_position.distance_to(other.global_position)
		if distance < best_distance:
			best_distance = distance
			best = other
	return best


## 路隊的生命週期,對這次跟隨是自己選的還是積木/選單叫的都一體適用:到了時間上限、太久碰不到人、
## 跟隨對象被收起來(找不到了)就自動解散;跟隨對象去休息/睡覺時考慮要不要一起休息,去使用家具時考慮
## 要不要一起用(都用/都不用,這次跟隨到此結束),去玩球時考慮要不要一起加入(一起玩就不用再跟著走了);
## 跟隨對象在跟別人一對一拚骰/猜拳時不影響跟隨判定(反正跟隨者本來就不能參與),什麼都不做。
func _tick_pet_follow_lifecycle(delta: float) -> void:
	if not is_following():
		_follow_stuck_left = 0.0
		_follow_leader_resting = false
		_follow_leader_seeking_mouse = false
		return
	var target := _find_pet_by_tag(_follow_tag)
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		stop_follow()
		return
	if (Time.get_ticks_usec() - _follow_started) / 1000000.0 >= _follow_duration_cap:
		stop_follow()
		return
	if global_position.distance_to(target.global_position) > FOLLOW_STUCK_DISTANCE:
		_follow_stuck_left += delta
		if _follow_stuck_left >= FOLLOW_STUCK_SECONDS:
			stop_follow()
			return
	else:
		_follow_stuck_left = 0.0
	if target.is_in_game():
		return
	if target.is_following_mouse():
		_follow_leader_seeking_mouse = true
		return
	if _follow_leader_seeking_mouse:
		# 跟隨對象剛結束跟滑鼠走(前一刻還在跟、這一刻不跟了):這趟「順道去見使用者」的行程結束,路隊直接解散,
		# 不用再判斷要不要加入或離開別的活動(既有的跟隨移動邏輯這段期間本來就會自然跟著對象一起移動到滑鼠旁邊)。
		_follow_leader_seeking_mouse = false
		stop_follow()
		return
	var target_resting: bool = target.is_resting_now()
	if target_resting and not _follow_leader_resting:
		_follow_leader_resting = true
		_react_to_leader_resting()
		return
	if not target_resting:
		_follow_leader_resting = false
	if target.is_using_furniture() and not is_using_furniture():
		_react_to_leader_furniture(target)
		return
	if target.ball_play != null and target.ball_play.active() and (ball_play == null or not ball_play.active()):
		_react_to_leader_ball_play(target)


## 跟隨對象開始休息/睡覺:依社交意願決定要不要也跟著休息(維持跟隨關係,對方醒了再一起走),不然就離開跟隨。
func _react_to_leader_resting() -> void:
	if vitality == null or is_resting_now() or is_busy_for_game() or not is_ground_mode() \
			or randf() >= clampf(sociability, 0.0, 1.0) or not vitality.force_rest():
		stop_follow()


## 跟隨對象開始使用家具:跟著用同一件(用同一種錨點類型);滿座用不了就離開跟隨。不管用不用得了這次跟隨都結束——
## 用得了的話家具的移動優先權比跟隨高(見 _movement_goal),用完自然會接回去繼續跟,不用特地保留 _follow_tag。
func _react_to_leader_furniture(target: Node) -> void:
	var item: FurnitureItem = target.furniture_target()
	if item == null or not use_furniture(item, target.furniture_anchor_kind()):
		stop_follow()


## 跟隨對象開始玩球:借用既有的「別隻桌寵邀請一起玩」流程決定要不要加入(有興趣就加入,沒興趣就婉拒,
## 都會照常發對話);不管結果如何都結束這次跟隨(加入的話要自己去追球,不能再原地跟著對方走)。
func _react_to_leader_ball_play(target: Node) -> void:
	if ball_play != null and is_instance_valid(target.ball_play.ball):
		ball_play.receive_invite(target.ball_play.ball)
	stop_follow()


## 限時朝(或遠離)滑鼠位置移動 seconds 秒,時間到就把移動決策交還給下一層(跟隨或原本的自主邏輯)。
## 優先權高於跟隨。滑鼠位置取自作業系統,游標在視窗外或沒有收到滑鼠事件時也有效。
func seek_mouse(seconds: float, away: bool = false) -> void:
	_seek_left = seconds
	_seek_away = away


## 拖曳中的道具吸引這隻桌寵:global_point 是道具的全域座標。固定、靜止模式與不可被吸引的桌寵不理會。
func set_attract_goal(global_point: Vector2) -> void:
	if not attractable or move_mode == MoveMode.FIXED or move_mode == MoveMode.STATIONARY:
		return
	_attract_goal = get_parent().to_local(global_point) if get_parent() is Node2D else global_point
	_attract_left = 0.3


func clear_attract_goal() -> void:
	_attract_goal = null
	_attract_left = 0.0


# --- 家具:坐/躺(見 FurnitureItem.claim_anchor;不湊人數,自己挑一個當下沒人用的錨點過去,不中途換位置) ---

## 想去使用一件家具的某種錨點("sit"/"lay")。已經在用/走去用別的家具會先放掉。錨點都滿了會用思考泡泡回應並回傳 false;
## 這批(桌寵行為的錨點+坐臥地基)還沒有積木能觸發,呼叫端(測試者面板、之後的「加入使用家具」積木)自己決定什麼時候呼叫。
func use_furniture(item: FurnitureItem, wanted_type: String) -> bool:
	if item == null or not is_instance_valid(item) or entering or dragging or move_mode == MoveMode.FIXED or move_mode == MoveMode.STATIONARY:
		return false
	# 家具可以被放在行動區框架之外(這個表現保留,不修,見使用者回饋);但桌寵不該想去搆不到的地方——
	# 行動區改大小、緊急召回時桌寵會被拉回框架內,那個家具就再也走不到了,乾脆一開始就不考慮選它。
	if _action_area != null and "boundary_rect" in _action_area:
		var rect: Rect2 = _action_area.boundary_rect
		var bounds := Rect2(_action_area.to_global(rect.position), rect.size)
		if not bounds.has_point(item.global_position):
			return false
	stop_using_furniture()
	var anchor := item.claim_anchor(self, wanted_type)
	if anchor < 0:
		GameChat.think(self, tr("雖然想加入,但看來已經滿座了……"))
		return false
	_furniture_target = item
	_furniture_anchor = anchor
	_furniture_seated = false
	_furniture_use_left = -1.0
	# 面向:"both" 每次使用時隨機擇一方向(不是左右來回切換,選定後這次使用期間不會再變),"left"/"right" 固定面向。
	match item.anchor_facing(anchor):
		"left":
			_furniture_facing = -1
		"right":
			_furniture_facing = 1
		_:
			_furniture_facing = 1 if randf() < 0.5 else -1
	return true


## 結束使用家具(不管還在走過去的路上,還是已經坐/躺著):讓出錨點、恢復正常自主行為。沒在用什麼都不做。
func stop_using_furniture() -> void:
	if _furniture_target == null:
		return
	var was_seated := _furniture_seated
	var item := _furniture_target
	var anchor_kind := item.anchor_type(_furniture_anchor) if is_instance_valid(item) else ""
	if is_instance_valid(item):
		item.release_anchor(self)
	_furniture_target = null
	_furniture_anchor = -1
	_furniture_seated = false
	_furniture_use_left = -1.0
	if was_seated:
		_shell_state.furniture_use_changed.emit(self, item, anchor_kind, false)


## 正在使用家具(已經走到定位、坐著/躺著);走去的路上算「還沒」。
func is_using_furniture() -> bool:
	return _furniture_seated


## 目前正在使用的家具(已經走到定位坐/躺著才算,走去的路上回傳 null),給「共用家具」這類積木條件判斷用。
func furniture_target() -> FurnitureItem:
	return _furniture_target if _furniture_seated and is_instance_valid(_furniture_target) else null


## 目前正在使用的錨點類型("sit"/"lay"),沒在用回傳空字串;給路隊「跟著一起用同一件家具」判斷用同一種錨點。
func furniture_anchor_kind() -> String:
	return _furniture_target.anchor_type(_furniture_anchor) if _furniture_seated and is_instance_valid(_furniture_target) else ""


## 延長使用家具的時間(積木「延長使用家具的時間」用):seconds 加到剩餘時間上(第一次呼叫時,原本無限時的使用會從現在開始倒數)。
## 沒在使用家具時什麼都不做。
func extend_furniture_use(seconds: float) -> void:
	if _furniture_target == null or seconds <= 0.0:
		return
	_furniture_use_left = maxf(_furniture_use_left, 0.0) + seconds


## 移動決策要不要往家具的錨點走:走去的路上回傳目標(本地座標),已經坐定或沒有目標時回傳 null。
func _furniture_goal() -> Variant:
	if _furniture_target == null:
		return null
	if not is_instance_valid(_furniture_target) or _furniture_anchor < 0 or _furniture_target.anchor_holder(_furniture_anchor) != self:
		stop_using_furniture()
		return null
	if _furniture_seated:
		return null
	var world := _furniture_target.anchor_global_position(_furniture_anchor)
	return get_parent().to_local(world) if get_parent() is Node2D else world


## 每個物理影格檢查:走到錨點附近就算「到了」,直接對齊到錨點的精確位置(不是「差不多近就好」)、原地播 sit/lay、
## 持續佔住不讓自主閒晃/跳舞蓋掉動畫(hold_still_for 同一招,見 PropManager._update_drag_interaction 的貼身摩擦);
## 坐/躺著的每個影格都重新對齊一次位置(便宜、保險,防止任何外力把它推離錨點);家具或錨點失效(被收走、被搶)
## 就自己清掉,恢復正常行為。_furniture_use_left >= 0(積木「延長使用家具的時間」設過)才會倒數到期自動放開;
## 預設 -1 = 沒設時限,一直固定在錨點上直到被拖曳(begin_drag → stop_using_furniture)或被中斷。
func _tick_furniture_seek() -> void:
	if _furniture_target == null:
		return
	if not is_instance_valid(_furniture_target) or _furniture_anchor < 0 or _furniture_target.anchor_holder(_furniture_anchor) != self:
		stop_using_furniture()
		return
	if _furniture_seated:
		if _furniture_use_left >= 0.0:
			_furniture_use_left -= get_physics_process_delta_time()
			if _furniture_use_left <= 0.0:
				stop_using_furniture()
				return
		hold_still_for(0.5)
		global_position = _furniture_target.anchor_global_position(_furniture_anchor)
		velocity = Vector2.ZERO
		_face(_furniture_facing)
		play_action(_furniture_target.anchor_action(_furniture_anchor, self), -1, true)
		return
	if global_position.distance_to(_furniture_target.anchor_global_position(_furniture_anchor)) <= FURNITURE_ARRIVE_DISTANCE:
		_furniture_seated = true
		global_position = _furniture_target.anchor_global_position(_furniture_anchor)
		velocity = Vector2.ZERO
		_shell_state.furniture_use_changed.emit(self, _furniture_target, _furniture_target.anchor_type(_furniture_anchor), true)


## 玩球(見 PetBallPlay):性格參數「玩球意願」= 每秒起玩的機率(0 = 不會玩);預設 0.05。
var ball_play_chance := 0.05
var ball_play: PetBallPlay
## 幫使用者計時(見 PetTimer);選單「幫我設定計時器…」「幫我計時…」由 ui_manager 開輸入視窗後呼叫。
var pet_timer: PetTimer
signal timer_input_requested(kind: int)
## 計時時間到的提醒音效(內建音效名稱;右鍵選單「計時提醒音效」選,存在角色設定)。
var timer_sound := "ring1"

## 對使用者的稱呼(交互行為分頁,逗號分隔輸入多筆;{user} 每次用時從裡面隨機挑一個)。預設只有「使用者」這一筆;
## 還是這個預設值時,桌寵有比較高的機率主動開口問「該怎麼稱呼你」(見 _tick_ask_user_nickname),問到答案就存進來、
## 之後不再是預設值,自動詢問也就停了(已經問過、使用者也答過了,不用一直煩)。
const DEFAULT_USER_NICKNAME := "使用者"
const MAX_USER_NICKNAMES := 8
var user_nicknames: Array[String] = [DEFAULT_USER_NICKNAME]
const USER_NICKNAME_ASK_WAIT := Vector2(180.0, 420.0)
## 還是預設稱呼時,主動詢問的機率比一般的「主動問要不要玩遊戲」明顯高一點(每次檢查擲一次)。
const USER_NICKNAME_ASK_CHANCE := 0.6
const USER_NICKNAME_ASK_LINES: Array[String] = ["對了,我該怎麼稱呼你呢?", "欸,還沒問過你耶——我可以怎麼叫你?", "我一直都叫你「使用者」,有沒有想要的稱呼呀?"]
var _user_nickname_left := -1.0
var _asking_user_nickname := false


func nickname_is_default() -> bool:
	return user_nicknames.size() == 1 and user_nicknames[0] == DEFAULT_USER_NICKNAME


## {user} 每次要用時從稱呼清單裡隨機挑一個;清單不該是空的(clean_user_nicknames 保證至少一筆),空了就退回預設。
func pick_user_nickname() -> String:
	return str(user_nicknames.pick_random()) if not user_nicknames.is_empty() else DEFAULT_USER_NICKNAME


## 逗號分隔的原始輸入 → 清理過的稱呼清單:去頭尾空白、消毒(擋 BBCode/控制字元)、丟空字串、去重、上限
## MAX_USER_NICKNAMES 筆;清完是空的就退回只有預設值那一筆(不會讓桌寵沒有稱呼可以用)。
static func clean_user_nicknames(raw: String) -> Array[String]:
	var result: Array[String] = []
	for part: String in raw.split(","):
		var cleaned := PetText.sanitize(part.strip_edges(), PetText.DEFAULT_MAX_LENGTH)
		if cleaned != "" and not result.has(cleaned) and result.size() < MAX_USER_NICKNAMES:
			result.append(cleaned)
	if result.is_empty():
		result.append(DEFAULT_USER_NICKNAME)   # 三元運算子兩邊型別不一致(一邊 Array[String]、一邊沒標型別的陣列常值)會讓回傳值整個變回沒型別的 Array,改成這樣才會維持 Array[String]
	return result


func _tick_ask_user_nickname(delta: float) -> void:
	if _user_nickname_left < 0.0:
		_user_nickname_left = randf_range(USER_NICKNAME_ASK_WAIT.x, USER_NICKNAME_ASK_WAIT.y)
	_user_nickname_left -= delta
	if _user_nickname_left > 0.0:
		return
	if not nickname_is_default() or logic == null:
		return   # 已經有自訂稱呼了,不用再問;不是「一直重問」的功能
	if _asking_user_nickname or not _can_auto_chat():
		_user_nickname_left = randf_range(AUTO_CHAT_RETRY_SECONDS.x, AUTO_CHAT_RETRY_SECONDS.y)
		return
	_user_nickname_left = randf_range(USER_NICKNAME_ASK_WAIT.x, USER_NICKNAME_ASK_WAIT.y)
	if randf() >= USER_NICKNAME_ASK_CHANCE:
		return
	_shell_state.note_auto_chat_started()
	_ask_user_nickname()


func _ask_user_nickname() -> void:
	_asking_user_nickname = true
	var prompt := str(USER_NICKNAME_ASK_LINES.pick_random())
	var result: Array = await logic._ask_user_text(prompt, PetText.escape_bbcode(prompt), "", PetText.DEFAULT_MAX_LENGTH)
	_asking_user_nickname = false
	if not is_instance_valid(self):
		return
	var accepted := bool(result[1])
	var text := str(result[0]).strip_edges()
	if accepted and text != "":
		user_nicknames = clean_user_nicknames(text)
	else:
		_user_nickname_left = maxf(_user_nickname_left, 60.0) * 2.0   # 沒回答:晚一點再問,不要一直煩
## 桌寵語系(這隻角色存在多種語系的對話文本時用來切換,見「介面與自動行為 > 字體與對話」);"" = 預設(原始語言版本)。
## 翻譯內容本身要靠 HTML 端(積木編輯器)另外製作,這裡先只是存這隻角色目前選哪個代碼,實際套用等有翻譯檔案可讀再接上。
var dialogue_locale := ""


## 內建(非使用者自訂)台詞專用的翻譯查詢:跟 LogicInterpreter._resolve_text 同一個「dialogue_locale 優先，
## 沒設就跟介面語系走」原則,只是那邊查的是使用者自訂的 dialogueTranslations,這裡查的是寫在原始碼裡、
## 進了 translations/ui_strings.csv 的內建台詞(遊戲邀請/拒絕、計時器提醒…)。找不到這個語系的翻譯就退回原文,
## 不強制轉換(跟專案「翻譯缺漏一律退回原文,不中斷」的一貫原則一樣)。
func speak_tr(text: String) -> String:
	if dialogue_locale == "" or dialogue_locale.replace("_", "-") == TranslationServer.get_locale().replace("_", "-"):
		return tr(text)
	var translation := TranslationServer.get_translation_object(dialogue_locale)
	if translation:
		var message := translation.get_message(text)
		if str(message) != "":
			return str(message)
	return text


## 喜歡的道具(交互行為頁籤的喜好列表):場上有掉在地上、可以撿的喜歡道具,就走過去撿(最低優先,跟隨、朝滑鼠、吸引都比它優先)。每 LIKED_SCAN_INTERVAL 秒找一次最近的。
const LIKED_SCAN_INTERVAL := 0.5
var _liked_target: PropItem
var _liked_scan_left := 0.0


## 交互行為分頁「整體交互開關」的 ignore_props 蓋掉個別道具的喜好設定,對任何道具都當作「不與此道具交互」(ignore)。
func prop_preference(def: PropDef) -> String:
	if def == null:
		return ""
	if bool(interaction_rules.get("ignore_props", false)):
		return "ignore"
	return InteractionRules.preference_of(interaction_rules, def.id)


## 最低優先的移動目標:正在玩的球 > 喜歡的道具(已經掉在地上、能直接撿) > 容器裡有庫存的喜歡道具(要走過去拿)。
func _secondary_goal() -> Variant:
	var play_goal: Variant = ball_play.goal() if ball_play != null else null
	if play_goal != null:
		return play_goal
	var liked: Variant = _liked_prop_goal()
	if liked != null:
		return liked
	return _container_goal()


func _liked_prop_goal() -> Variant:
	# is_busy_for_game():對戰中(井字棋等)的桌寵不會自己跑去撿喜歡的道具,見 TttGame 的說明。
	if (interaction_rules["prefs"] as Array).is_empty() or move_mode == MoveMode.FIXED or move_mode == MoveMode.STATIONARY or is_sleeping() or has_negative_lens() or is_busy_for_game():
		return null
	_liked_scan_left -= get_physics_process_delta_time()
	if _liked_scan_left <= 0.0:
		_liked_scan_left = LIKED_SCAN_INTERVAL
		_liked_target = null
		var best := INF
		for node: Node in get_tree().get_nodes_in_group("props"):
			var item := node as PropItem
			if item == null or item.def == null or not item.def.toss or item.consuming or item.dragging or item.collected or not item.landed:
				continue
			if prop_preference(item.def) != "like":
				continue
			var distance := global_position.distance_to(item.global_position)
			if distance < best:
				best = distance
				_liked_target = item
	if _liked_target == null or not is_instance_valid(_liked_target) or _liked_target.consuming or _liked_target.collected or _liked_target.dragging:
		_liked_target = null
		return null
	return get_parent().to_local(_liked_target.global_position) if get_parent() is Node2D else _liked_target.global_position


## 容器家具(見 FurnitureItem.container_*):喜歡的道具已經掉在地上時優先撿那個(_liked_prop_goal 排在前面),
## 沒得撿才考慮去附近有庫存的容器拿。跟 CONTAINER_WITHDRAW_COOLDOWN 冷卻中的桌寵不會去找新目標,但已經在路上的
## 不會被冷卻中斷(冷卻只擋「開始找下一個」,不擋「已經在走過去的這一次」)。
const CONTAINER_SCAN_INTERVAL := 0.5
## 同一隻桌寵拿完一次容器道具後,這麼多秒內不會再去找下一個容器(不分容器、不分道具種類),防止一直開來開去洗版桌面。
const CONTAINER_WITHDRAW_COOLDOWN := 15.0
## 桌面上同一種道具(不分來源)到這個數量,容器就不會再讓桌寵繼續拿這一種(還是可以拿別種);跟 Minecraft 一疊上限
## 同一個數字,純粹好玩,沒有特殊涵義。
const CONTAINER_DESKTOP_CAP := 64
var _container_target: FurnitureItem
var _container_prop_id := ""
var _container_scan_left := 0.0
var _container_cooldown_until_msec := 0


func _container_goal() -> Variant:
	# 「整體交互開關」的 ignore_furniture 只擋「自己決定要不要去用」;使用者手動拖曳去用、或積木明確指定使用不受影響。
	# is_busy_for_game():對戰中(井字棋等)的桌寵不會自己跑去拿容器家具的道具,見 TttGame 的說明。
	if bool(interaction_rules.get("ignore_furniture", false)) or is_busy_for_game():
		return null
	if (interaction_rules["prefs"] as Array).is_empty() or move_mode == MoveMode.FIXED or move_mode == MoveMode.STATIONARY or is_sleeping() or has_negative_lens():
		return null
	if _container_target != null and (not is_instance_valid(_container_target) or not _container_target.is_container() or _container_target.container_remaining_of(_container_prop_id) <= 0):
		_container_target = null
		_container_prop_id = ""
	if _container_target == null:
		_container_scan_left -= get_physics_process_delta_time()
		if _container_scan_left > 0.0 or Time.get_ticks_msec() < _container_cooldown_until_msec:
			return null
		_container_scan_left = CONTAINER_SCAN_INTERVAL
		_find_container_target()
	if _container_target == null:
		return null
	# 走去「碰撞箱底邊」(貼地那一邊),不是家具貼圖原點(通常在圖片左上角,大件家具會在半空中,誤觸發跳躍邏輯)。
	var rect := _container_target.touch_rect()
	var target := Vector2(rect.position.x, rect.end.y)
	return get_parent().to_local(target) if get_parent() is Node2D else target


## 找一個有這隻桌寵喜歡、有庫存、桌面同種還沒到上限的道具的容器,挑最近的一個。
func _find_container_target() -> void:
	var best := INF
	for node: Node in get_tree().get_nodes_in_group("furniture"):
		var item := node as FurnitureItem
		if item == null or not item.is_container():
			continue
		var prop_id := _pick_wanted_container_prop(item)
		if prop_id == "":
			continue
		var distance := global_position.distance_to(item.global_position)
		if distance < best:
			best = distance
			_container_target = item
			_container_prop_id = prop_id


## 這個容器裡第一個「這隻桌寵喜歡、有庫存、桌面還沒到上限」的道具 id;都不符合回空字串。
func _pick_wanted_container_prop(item: FurnitureItem) -> String:
	for entry: Dictionary in item.def.container_items:
		var id := str(entry["id"])
		if item.container_remaining_of(id) <= 0:
			continue
		var def := PropLibrary.load_def(id)
		if def == null or prop_preference(def) != "like":
			continue
		if _desktop_prop_count(id) >= CONTAINER_DESKTOP_CAP:
			continue
		return id
	return ""


func _desktop_prop_count(prop_id: String) -> int:
	var count := 0
	for manager: Node in get_tree().get_nodes_in_group("prop_manager"):
		for item: PropItem in manager.items:
			if is_instance_valid(item) and item.def != null and item.def.id == prop_id:
				count += 1
	return count


## 每個物理影格檢查:走到容器附近(互動範圍與家具碰撞箱重疊,不是精確的錨點)就觸發拿一個——扣庫存、家具播
## interacted_0、在桌寵腳邊生出這個道具並直接算「遞交」給它(不受一般道具的拾取冷卻限制,見
## PropManager._can_collect 的 delivered 例外),接下來桌寵會照一般道具反應流程自己撿起來。之後這隻桌寵要等
## CONTAINER_WITHDRAW_COOLDOWN 秒才會再去找下一個容器。
func _tick_container_seek(_delta: float) -> void:
	if _container_target == null:
		return
	if not is_instance_valid(_container_target) or not _container_target.is_container():
		_container_target = null
		_container_prop_id = ""
		return
	if not interaction_rect().intersects(_container_target.touch_rect()):
		return
	var prop_id := _container_prop_id
	var item := _container_target
	_container_target = null
	_container_prop_id = ""
	if not item.container_take(prop_id):
		return
	item.play_interacted()
	_container_cooldown_until_msec = Time.get_ticks_msec() + int(CONTAINER_WITHDRAW_COOLDOWN * 1000.0)
	var def := PropLibrary.load_def(prop_id)
	if def == null:
		return
	for manager: Node in get_tree().get_nodes_in_group("prop_manager"):
		var spawned: PropItem = manager.spawn(def, global_position)
		spawned.delivered_to = self
		break


## 目前移動決策想去的座標(行動區座標);沒有任何目標導向的來源時回傳 null。
## 優先層級:拖曳中吸引 > 走去使用家具的路上 > 限時朝/離滑鼠(含「跟著我」)> 跟隨 > 各移動模式原本的自主邏輯。
## 已經坐/躺定位(is_holding_still() 靠 hold_still_for 持續維持)算「沒有目標」,原地不動。
func _movement_goal() -> Variant:
	if entering or dragging or is_holding_still():
		return null
	if _attract_goal is Vector2:
		return _attract_goal
	var furniture_goal: Variant = _furniture_goal()
	if furniture_goal != null:
		return furniture_goal
	if _seek_left > 0.0:
		var mouse := Vector2(DisplayServer.mouse_get_position()) - Vector2(get_window().position)
		if _seek_away:
			return position + (position - mouse).normalized() * 300.0
		return mouse
	if _follow_tag == "" or move_mode == MoveMode.FIXED or move_mode == MoveMode.STATIONARY:
		return _secondary_goal()
	var target := _find_pet_by_tag(_follow_tag)
	if target == null:
		return _secondary_goal()
	# 多隻跟隨同一目標時依開始跟隨的先後排隊,先跟隨的離目標最近;名額即時運算,不快取。
	var slot := 0
	for other in get_tree().get_nodes_in_group("pets"):
		if other != self and other._follow_tag == _follow_tag and other._follow_started < _follow_started:
			slot += 1
	var side := signf(position.x - target.position.x)
	if side == 0.0:
		side = 1.0
	var goal: Vector2 = target.position + Vector2(side * follow_distance * (1 + slot), 0.0)
	if move_mode != MoveMode.GROUND:
		goal.y -= 60.0
	return goal


func _find_pet_by_tag(tag: String, exclude_self: bool = true) -> Node:
	for other in get_tree().get_nodes_in_group("pets"):
		if (other != self or not exclude_self) and other.recognition_tag == tag:
			return other
	return null


## 把 A-Z、a-z、0-9 換成數學粗體字元(選單頂端的名字用;其他文字不變)。
static func _bold_letters(text: String) -> String:
	var result := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= 65 and code <= 90:
			result += String.chr(0x1D5D4 + code - 65)
		elif code >= 97 and code <= 122:
			result += String.chr(0x1D5EE + code - 97)
		elif code >= 48 and code <= 57:
			result += String.chr(0x1D7EC + code - 48)
		else:
			result += text[i]
	return result


## 在游標位置打開桌寵選單(原生選單,跟系統匣同一套)。
func open_context_menu() -> void:
	if not NativeMenu.has_feature(NativeMenu.FEATURE_POPUP_MENU):
		return
	_free_context_menu()
	var root := _build_context_menu()
	NativeMenu.popup(root, DisplayServer.mouse_get_position())


## 選單內容:查看狀態、重複前一句(尚無接收者時灰色)、固定時可隨時拖曳、貼合行動框底部移動、移動模式子選單。
func _build_context_menu() -> RID:
	var root := NativeMenu.create_menu()
	_context_rids.append(root)
	# 頂端裝飾行:這是誰的選單(原生選單沒有粗體,拉丁字母用數學粗體字元,灰色不可點)。
	var header_index := NativeMenu.add_item(root, "▍" + _bold_letters(get_label()))
	NativeMenu.set_item_disabled(root, header_index, true)
	NativeMenu.add_separator(root)
	var status_index := NativeMenu.add_item(root, tr("查看狀態"), _on_context_item, Callable(), "status")
	NativeMenu.set_item_disabled(root, status_index, status_requested.get_connections().is_empty())
	NativeMenu.add_item(root, tr("幫我決定(抽籤)…"), _on_context_item, Callable(), "decide")
	if pet_timer != null and pet_timer.active():
		NativeMenu.add_item(root, tr("停止計時(%s)") % pet_timer.status_text(), _on_context_item, Callable(), "timer_stop")
	else:
		var timer_disabled := timer_input_requested.get_connections().is_empty()
		NativeMenu.set_item_disabled(root, NativeMenu.add_item(root, tr("幫我設定計時器…"), _on_context_item, Callable(), "timer_countdown"), timer_disabled)
		NativeMenu.set_item_disabled(root, NativeMenu.add_item(root, tr("幫我計時(碼表)…"), _on_context_item, Callable(), "timer_stopwatch"), timer_disabled)
		var sound_menu := NativeMenu.create_menu()
		_context_rids.append(sound_menu)
		for sound_name in SoundManager.BUILTIN_SOUNDS:
			NativeMenu.set_item_checked(sound_menu, NativeMenu.add_radio_check_item(sound_menu, sound_name, _on_context_item, Callable(), "timer_sound:" + sound_name), sound_name == timer_sound)
		# 使用者在全局設定「音效」分頁匯入的提醒音效(AlarmSounds):不綁定特定桌寵,跟內建音效並列選擇。
		if not AlarmSounds.list().is_empty():
			NativeMenu.add_separator(sound_menu)
			for file_name: String in AlarmSounds.list():
				NativeMenu.set_item_checked(sound_menu, NativeMenu.add_radio_check_item(sound_menu, AlarmSounds.display_name(file_name), _on_context_item, Callable(), "timer_sound:" + file_name), file_name == timer_sound)
		NativeMenu.add_submenu_item(root, tr("計時提醒音效"), sound_menu)
	var say_index := NativeMenu.add_item(root, tr("說點什麼"), _on_context_item, Callable(), "say")
	NativeMenu.set_item_disabled(root, say_index, logic == null or not logic.has_chat_lines())
	var repeat_index := NativeMenu.add_item(root, tr("重複前一句"), _on_context_item, Callable(), "repeat")
	NativeMenu.set_item_disabled(root, repeat_index, repeat_last_requested.get_connections().is_empty())
	var manage_index := NativeMenu.add_item(root, tr("桌寵管理…"), _on_context_item, Callable(), "manage")
	NativeMenu.set_item_disabled(root, manage_index, manage_requested.get_connections().is_empty())
	if can_follow_mouse():
		NativeMenu.add_item(root, tr("停止跟著我") if is_following_mouse() else tr("跟著我"), _on_context_item, Callable(), "follow_me")
	if move_mode == MoveMode.FIXED:
		var drag_index := NativeMenu.add_check_item(root, tr("固定時可隨時拖曳"), _on_context_item, Callable(), "drag_fixed")
		NativeMenu.set_item_checked(root, drag_index, drag_when_fixed)
	if move_mode == MoveMode.GROUND:
		var climb_index := NativeMenu.add_check_item(root, tr("允許爬牆與天花板"), _on_context_item, Callable(), "climb")
		NativeMenu.set_item_checked(root, climb_index, climb_enabled)
	var bottom_index := NativeMenu.add_check_item(root, tr("貼合行動框底部移動"), _on_context_item, Callable(), "bottom_stick")
	NativeMenu.set_item_checked(root, bottom_index, bottom_anchored)
	var flip_index := NativeMenu.add_check_item(root, tr("鏡像翻轉"), _on_context_item, Callable(), "flip_art")
	NativeMenu.set_item_checked(root, flip_index, art_flipped)
	_add_accessory_menu(root)
	_add_game_menus(root)
	NativeMenu.add_separator(root)
	var modes := NativeMenu.create_menu()
	_context_rids.append(modes)
	for mode in MODE_LABELS.size():
		var index := NativeMenu.add_radio_check_item(modes, tr(MODE_LABELS[mode]), _on_context_item, Callable(), mode)
		NativeMenu.set_item_checked(modes, index, mode == move_mode)
	NativeMenu.add_submenu_item(root, tr("移動模式"), modes)
	return root


## 「變更配件」:這隻桌寵的素材包有配件(overlays.json 裡 role = part 的部件)才有,每個配件一個開關;詳細調整之後再做。
func _add_accessory_menu(root: RID) -> void:
	if _overlays == null:
		return
	var names := _overlays.accessory_names()
	if names.is_empty():
		return
	var menu := NativeMenu.create_menu()
	_context_rids.append(menu)
	for part_name in names:
		var index := NativeMenu.add_check_item(menu, part_name, _on_context_item, Callable(), "acc:" + part_name)
		NativeMenu.set_item_checked(menu, index, _overlays.is_accessory_enabled(part_name))
	NativeMenu.add_submenu_item(root, tr("變更配件"), menu)


func _on_context_item(tag: Variant) -> void:
	if tag is int:
		set_move_mode(tag)
		return
	if tag is String and tag.begins_with("acc:") and _overlays != null:
		var part_name: String = tag.trim_prefix("acc:")
		set_accessory_enabled(part_name, not _overlays.is_accessory_enabled(part_name))
		return
	if tag is String and tag.begins_with("timer_sound:"):
		timer_sound = tag.trim_prefix("timer_sound:")
		get_node("/root/DesktopShellState").sound_requested.emit(self, timer_sound)   # 選了就播一下試聽
		PetProfile.save_pet(self)
		return
	if tag is String and _on_game_menu_item(tag):
		return
	match tag:
		"status":
			status_requested.emit()
		"say":
			say_something()
		"follow_me":
			if is_following_mouse():
				stop_follow_mouse()
			else:
				follow_mouse()
		"decide":
			decide_requested.emit()
		"timer_countdown":
			timer_input_requested.emit(PetTimer.Kind.COUNTDOWN)
		"timer_stopwatch":
			timer_input_requested.emit(PetTimer.Kind.STOPWATCH)
		"timer_stop":
			pet_timer.stop()
		"repeat":
			repeat_last_requested.emit()
		"manage":
			manage_requested.emit()
		"bottom_stick":
			set_bottom_anchored(not bottom_anchored)
			PetProfile.save_pet(self)
		"drag_fixed":
			drag_when_fixed = not drag_when_fixed
			PetProfile.save_pet(self)
		"climb":
			set_climb_enabled(not climb_enabled)
			PetProfile.save_pet(self)
		"flip_art":
			set_art_flipped(not art_flipped)
			PetProfile.save_pet(self)


func _free_context_menu() -> void:
	for rid in _context_rids:
		NativeMenu.free_menu(rid)
	_context_rids.clear()


func _exit_tree() -> void:
	_free_context_menu()
	# 離開樹時自己還在 group 裡,所以等這一影格結束再重新編號(剩一隻就拿掉編號)。
	PetRegistry.refresh_labels.bind(get_tree()).call_deferred()


## 觸發 interact 動作一段時間:期間原地播放 interact,不自主走動或跳躍。
func begin_interact(duration: float) -> void:
	_interrupt()
	_interact_left = duration


# --- 兩種範圍的分工:互動判定框 vs 顯示範圍 ---
## 互動判定框(_hit_rect):點擊、拖曳、摸摸、右鍵選單、氣泡避讓用,只包住「本體」,翅膀、特效、寬大的武器不必算進去。
## 單位是「縮放前」的像素,底邊中心 + hitbox_offset 是錨點(腳底線的中心點,x 向右、y 向下);
## hitbox_size 為零向量 = 自動(素材包 pack.json 的 hitbox,再來是待機幀的 body_size / 圖片大小)。使用者設定存在角色設定檔。
## 顯示範圍(_stable_visual_rect):畫面上實際有畫東西的範圍,只用來決定穿透形狀(Windows 的穿透區域同時也是繪圖區域,
## 沒算進去的像素會被裁掉),不影響能不能點。用「目前動畫所有幀的不透明範圍聯集」,不必每一幀重算,
## 動畫切換時再保留前一個的範圍一小段時間,避免視窗形狀慢一影格造成的一閃而過的裁切。
var hitbox_size := Vector2.ZERO
var hitbox_offset := Vector2.ZERO
const VISUAL_HOLD_MSEC := 300
var _visual_bounds_cache: Dictionary = {}
var _visual_recent_rect := Rect2()
var _visual_recent_msec := 0


## 目前這一幀的畫面快照(移動殘影用):{texture, xform(全域變換)、offset、centered};沒有畫面回空字典。
func visual_snapshot() -> Dictionary:
	if _sprite == null or _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(_sprite.animation):
		return {}
	var texture := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	if texture == null:
		return {}
	return {"texture": texture, "xform": _sprite.global_transform, "offset": _sprite.offset, "centered": _sprite.centered}


## 「直立站著的身體座標」→ 這隻桌寵本地座標的變換:爬牆時身體轉 90°、天花板上倒過來(專屬天花板素材則是上下翻)時,
## 特效的「頭頂」「身邊」位置要依它轉過去,才會跟著頭走(見 PetEffects;和 body_frame() 不同,那個是素材幀的編號)。沒在攀爬就是單位變換。
func body_pose_transform() -> Transform2D:
	if _climb == ClimbState.NONE:
		return Transform2D.IDENTITY
	if _climb == ClimbState.CEILING and _ceiling_dedicated():
		return Transform2D(Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2.ZERO)
	return Transform2D(_climb_rotation(), Vector2.ZERO)


## 這一刻實際的位移速度(像素/秒,平滑值);精力機制用它判斷是走著還是站著。
func measured_speed() -> float:
	return _measured_velocity.length()


## 目前動作佔用還剩幾秒(積木、休息、睡覺指定的動作會佔用一段時間)。
func hold_left() -> float:
	return _hold_left


## 飛行模式的桌寵現在是不是穩穩站在地上(降落完成的休息狀態,或兼具模式的行走階段)——可以坐下、躺下、睡覺的條件。
func is_flight_grounded() -> bool:
	if move_mode != MoveMode.FLYING or not is_on_floor():
		return false
	if fly_behavior == FlyBehavior.HYBRID:
		return not _hybrid_airborne
	return _fly_state == FlyState.RESTING


## 想休息卻還在空中:飛行的桌寵開始找地方降落(總是飛行、兼具模式的行走階段不需要)。
func request_landing() -> void:
	if move_mode == MoveMode.FLYING and fly_behavior == FlyBehavior.LANDS and _fly_state == FlyState.CRUISE and _fly_launch_left <= 0.0:
		_fly_begin_landing()


## 正在休息(站著發呆、坐下、睡著)?休息中的桌寵不亂飄、不亂走。
func is_resting_now() -> bool:
	return vitality != null and vitality.mode != PetVitality.Mode.ACTIVE


func is_ground_mode() -> bool:
	return move_mode == MoveMode.GROUND or (move_mode == MoveMode.FLYING and fly_behavior == FlyBehavior.HYBRID and not _hybrid_airborne)


## 有沒有這個名稱的狀態鏡(不管有沒有啟用)。
func has_lens(lens_name: String) -> bool:
	return _find_lens(lens_name) != null


## 目前生效的判定框大小(縮放前像素):使用者設定 > 素材包設定 > 待機幀本體大小。
func effective_hitbox_size() -> Vector2:
	if hitbox_size != Vector2.ZERO:
		return hitbox_size
	var pack_size: Variant = _sprite.sprite_frames.get_meta("hitbox_size", Vector2.ZERO) if _sprite != null and _sprite.sprite_frames != null else Vector2.ZERO
	if pack_size is Vector2 and pack_size != Vector2.ZERO:
		return pack_size
	return _frame_size


func effective_hitbox_offset() -> Vector2:
	if hitbox_size != Vector2.ZERO or hitbox_offset != Vector2.ZERO:
		return hitbox_offset
	var pack_offset: Variant = _sprite.sprite_frames.get_meta("hitbox_offset", Vector2.ZERO) if _sprite != null and _sprite.sprite_frames != null else Vector2.ZERO
	return pack_offset if pack_offset is Vector2 else Vector2.ZERO


## 一張貼圖裡有畫東西的範圍(貼圖「虛擬畫布」座標,左上角為原點;讀不到像素就回整張)。
func _texture_opaque_rect(texture: Texture2D) -> Rect2:
	var full := Rect2(Vector2.ZERO, Vector2(texture.get_size()))
	var source: Texture2D = texture
	var region := Rect2i()
	var origin := Vector2.ZERO
	var has_region := false
	if texture is AtlasTexture and (texture as AtlasTexture).atlas != null:
		var atlas := texture as AtlasTexture
		source = atlas.atlas
		region = Rect2i(atlas.region)
		origin = atlas.margin.position
		has_region = true
	var key := source.get_instance_id()
	if not _alpha_images.has(key):
		if _alpha_images.size() >= MAX_ALPHA_CACHE:
			_alpha_images.clear()
		_alpha_images[key] = source.get_image()
	var image: Image = _alpha_images[key]
	if image == null or image.is_compressed():
		return full
	var used := (image.get_region(region) if has_region else image).get_used_rect()
	if used.size == Vector2i.ZERO:
		return Rect2(full.get_center(), Vector2.ZERO)
	return Rect2(Vector2(used.position) + origin, Vector2(used.size))


## 一個動畫所有幀的不透明範圍聯集(以精靈中心為原點的精靈座標)。快取,切換素材時清掉。
func _animation_bounds(animation: StringName) -> Rect2:
	if _visual_bounds_cache.has(animation):
		return _visual_bounds_cache[animation]
	var frames := _sprite.sprite_frames
	var bounds := Rect2()
	var found := false
	if frames != null and frames.has_animation(animation):
		for i in frames.get_frame_count(animation):
			var texture := frames.get_frame_texture(animation, i)
			if texture == null:
				continue
			var rect := _texture_opaque_rect(texture)
			rect.position -= Vector2(texture.get_size()) * 0.5
			bounds = rect if not found else bounds.merge(rect)
			found = true
	_visual_bounds_cache[animation] = bounds
	return bounds


## 目前畫面上有畫東西的範圍(桌寵本地座標,已含縮放/翻轉/旋轉),並保留短時間內出現過的範圍。
func _stable_visual_rect() -> Rect2:
	if _sprite == null or _sprite.sprite_frames == null:
		return Rect2()
	var sprite_rect := _animation_bounds(_sprite.animation)
	if _logical_animation != &"" and _logical_animation != _sprite.animation:
		var logical_rect := _animation_bounds(_logical_animation)
		if logical_rect.size != Vector2.ZERO:
			sprite_rect = logical_rect if sprite_rect.size == Vector2.ZERO else sprite_rect.merge(logical_rect)
	if sprite_rect.size == Vector2.ZERO:
		return _visual_recent_rect
	var to_pet := get_global_transform().affine_inverse() * _sprite.get_global_transform()
	var current: Rect2 = to_pet * (Rect2(sprite_rect.position + _sprite.offset, sprite_rect.size))
	if _overlays != null:
		var extra := _overlays.union_rect()
		if extra.size != Vector2.ZERO:
			current = current.merge(extra)
	var now := Time.get_ticks_msec()
	if _visual_recent_rect.size == Vector2.ZERO or now - _visual_recent_msec > VISUAL_HOLD_MSEC:
		_visual_recent_rect = current
		_visual_recent_msec = now
	else:
		_visual_recent_rect = _visual_recent_rect.merge(current)
	return _visual_recent_rect


## Cutout group 介面:回傳這隻桌寵目前可被點到的形狀(全域座標)。
## 穿透形狀往移動方向預留的位移。穿透區域是作業系統層的視窗形狀,更新總會慢畫面約一影格;桌寵快速移動(例如剛生成時掉落)
## 時,身體前緣會超出還沒更新的形狀而被裁掉、看起來變透明。所以把形狀往速度方向多預留一小段(跟著桌寵的對話氣泡也用這個)。
## 用「速度」和「實際位移量」兩者中較大的當預留方向:被滑鼠拖著甩的時候 velocity 是 0(座標直接跟著滑鼠走),
## 光看 velocity 就完全沒有預留,快速拋飛時前緣的貼圖會被還沒更新的形狀裁出鋸齒/色塊。
func cutout_lead() -> Vector2:
	var motion := velocity if velocity.length_squared() >= _measured_velocity.length_squared() else _measured_velocity
	return (motion * CUTOUT_LEAD_TIME).limit_length(CUTOUT_LEAD_MAX)


## 矩形的邊往外貼齊格線:呼吸、微小擺動造成的每影格小變化不會讓穿透形狀跟著每影格變(見 DesktopShell._process)。
static func _snap_out(rect: Rect2, grid: float) -> Rect2:
	var start := (rect.position / grid).floor() * grid
	var finish := (rect.end / grid).ceil() * grid
	return Rect2(start, finish - start)


func get_cutout_polygons() -> Array:
	var lead := cutout_lead()
	# 穿透形狀 = 判定框 ∪ 顯示範圍(翅膀、揮舞的武器等畫在判定框外的部分也要算進來,不然會被視窗區域裁掉)。
	var rect := _snap_out(_hit_rect().merge(_stable_visual_rect()).grow(CUTOUT_SAFETY_MARGIN), CUTOUT_SNAP)
	rect = rect.merge(Rect2(rect.position + lead, rect.size))
	if entering:
		rect = rect.grow(ENTRANCE_CUTOUT_GROW)
	return [
		PackedVector2Array(
			[
				to_global(rect.position),
				to_global(Vector2(rect.end.x, rect.position.y)),
				to_global(rect.end),
				to_global(Vector2(rect.position.x, rect.end.y)),
			]
		)
	]


## 緊急召回:座標重設到行動區中央,從那裡重新開始。
func _on_emergency_recall() -> void:
	if _action_area == null:
		return
	_exit_climb(false, false)
	position = _bounds().get_center()
	velocity = Vector2.ZERO


func _hit_rect() -> Rect2:
	var scale_factor := params.scale_multiplier
	var size := effective_hitbox_size() * scale_factor + Vector2.ONE * CUTOUT_PADDING * 2.0
	var offset := effective_hitbox_offset() * scale_factor
	var rect := Rect2(-size.x * 0.5 + offset.x, CUTOUT_PADDING - size.y + offset.y, size.x, size.y)
	if _climb == ClimbState.NONE:
		return rect
	if _climb == ClimbState.CEILING and _ceiling_dedicated():
		# 專屬天花板素材是倒掛的樣子,身體在軸心(天花板)下方,判定框上下翻過來。
		return Rect2(rect.position.x, -rect.end.y, rect.size.x, rect.size.y)
	# 貼牆/貼天花板時整隻轉了 90°/180°:點擊範圍與穿透形狀跟著轉(以腳底 = 原點為軸心,取外接矩形)。
	return Transform2D(_climb_rotation(), Vector2.ZERO) * rect


## 自主移動時的動作播放:互動(interact)進行中一律播放 interact。
func _play_locomotion(action: StringName) -> void:
	if entering:
		_play(&"enter", -1, ActionPriority.SYSTEM)
	elif _interact_left > 0.0:
		_play(&"interact", -1, ActionPriority.INTERACTION)
	else:
		play_action(action)


## _measured_velocity 平滑用的每秒收斂率(在 MEASURED_VELOCITY_REF_HZ 那個影格率下,相當於原本每個
## physics tick 用 0.6 的 lerp 權重)。2026-09-30 把 physics_ticks_per_second 從 60 降到 30(省 CPU)
## 之後,如果權重還是寫死 0.6,tick 變少但每個 tick 間隔變長,同樣秒數內收斂的圈數變少、追速度突然變化
## (剛被丟出去那一瞬間)會比原本更慢一拍,反而讓「移動時貼圖邊緣被穿透形狀裁到」這個使用者剛回報的
## 問題更明顯。改用跟影格時間無關的公式(指數收斂),不管 physics tick 開多快,同樣的真實時間內收斂
## 的程度都一樣,在原本 60Hz 下算出來的權重跟舊寫法完全相同,純粹是把「跟 tick rate 綁在一起」這件事
## 修掉,不是改變原本調好的平滑手感。
const MEASURED_VELOCITY_REF_HZ := 60.0
const MEASURED_VELOCITY_REF_WEIGHT := 0.6


func _physics_process(delta: float) -> void:
	if _action_area == null:
		return
	# 實際位移速度(給穿透形狀預留用,見 get_cutout_polygons);用平滑值避免單影格的跳動讓形狀忽大忽小。
	if delta > 0.0:
		var weight := 1.0 - pow(1.0 - MEASURED_VELOCITY_REF_WEIGHT, delta * MEASURED_VELOCITY_REF_HZ)
		_measured_velocity = _measured_velocity.lerp((global_position - _last_global_position) / delta, weight)
	_last_global_position = global_position
	if not _active_lenses.is_empty():
		_tick_lenses()
	if dragging:
		_play(&"drag", -1, ActionPriority.INTERACTION)
		return
	_hold_left = maxf(_hold_left - delta, 0.0)
	_tick_blink(delta)
	if auto_chat_enabled and _shell_state.auto_chat_enabled:
		_tick_auto_chat(delta)
		_tick_ask_user_nickname(delta)
		if auto_game_enabled:
			_tick_auto_game(delta)
			_tick_ask_user_game(delta)
	_interact_left = maxf(_interact_left - delta, 0.0)
	_converse_left = maxf(_converse_left - delta, 0.0)
	_airborne_grace = maxf(_airborne_grace - delta, 0.0)
	_seek_left = maxf(_seek_left - delta, 0.0)
	_prop_still_left = maxf(_prop_still_left - delta, 0.0)
	_tick_drop_through(delta)
	_tick_prop_action(delta)
	_tick_auto_mouse_follow(delta)
	_tick_auto_pet_follow(delta)
	_tick_pet_follow_lifecycle(delta)
	_tick_furniture_seek()
	_tick_container_seek(delta)
	if _attract_left > 0.0:
		_attract_left -= delta
		if _attract_left <= 0.0:
			_attract_goal = null
	if not _active_lenses.is_empty() and _active_lenses.has("緊張"):
		_visual_root.position.x = randf_range(-1.4, 1.4)   # 緊張:一直小幅度顫抖
	elif _shiver_left > 0.0:
		_shiver_left -= delta
		_visual_root.position.x = randf_range(-3.0, 3.0)
	elif _visual_root.position.x != 0.0:
		_visual_root.position.x = 0.0
	_follow_jump_cooldown = maxf(_follow_jump_cooldown - delta, 0.0)
	if entering:
		_entrance_left -= delta
		if _entrance_left <= 0.0:
			entering = false
	match move_mode:
		MoveMode.FIXED:
			velocity = Vector2.ZERO
			_play_locomotion(&"idle")
		MoveMode.GROUND, MoveMode.STATIONARY:
			_process_ground(delta)
		MoveMode.FLYING:
			if fly_behavior == FlyBehavior.HYBRID and not _hybrid_airborne:
				_process_ground(delta)
				_hybrid_ground_tick(delta)
			else:
				_process_flying(delta)
		MoveMode.FLOATING:
			_process_floating(delta)
	if bottom_anchored and not dragging and (move_mode == MoveMode.FLYING or move_mode == MoveMode.FLOATING):
		position.y = _bounds().end.y   # 貼底:飛行、漂浮也只沿著底邊橫向移動
		velocity.y = 0.0


## 地面模式的目標導向移動(跟隨或朝滑鼠):水平朝目標走,到了就待機;目標明顯比自己高時,
## 以冷卻時間嘗試往目標方向跳一次(優先跳上規劃得到的平臺),冷卻中不重複起跳。
func _process_ground_seek(delta: float, goal: Vector2) -> void:
	maybe_drop_through(goal, delta)
	velocity.y = minf(velocity.y + _gravity * params.gravity_scale * _lens_gravity * delta, params.terminal_fall_velocity)
	if is_on_floor() and _airborne_grace <= 0.0:
		_jump_target_x = NAN
		var dx := goal.x - position.x
		if absf(dx) > FOLLOW_DEADZONE and _interact_left <= 0.0 and _hold_left <= 0.0 and _converse_left <= 0.0:
			var direction := 1 if dx > 0.0 else -1
			velocity.x = direction * _walk_speed()
			_walk_dir = direction
			_face(direction)
			_ground_state = GroundState.WALK
			if goal.y < position.y - 40.0 and _follow_jump_cooldown <= 0.0:
				# 目標在高處:先用「剛好夠高」的力道跳;連續兩次跳完都沒有比上次高,下一次才放開用最大力道。
				if position.y >= _seek_last_y - 12.0:
					_seek_jump_failures += 1
				else:
					_seek_jump_failures = 0
				_seek_last_y = position.y
				var jump_dx := _find_jump_dx(direction)
				if is_nan(jump_dx):
					jump_dx = direction * minf(absf(dx), 90.0)
					_planned_jump_speed = _goal_jump_speed(position.y - goal.y)
				if _seek_jump_failures >= 2:
					_planned_jump_speed = maxf(params.max_jump_velocity, params.jump_velocity)
				_jump(jump_dx)
				_follow_jump_cooldown = randf_range(FOLLOW_JUMP_COOLDOWN.x, FOLLOW_JUMP_COOLDOWN.y)
			elif goal.y >= position.y - 40.0:
				_seek_jump_failures = 0
				_seek_last_y = INF
		else:
			velocity.x = 0.0
			_ground_state = GroundState.IDLE
	else:
		release_hold()
		_steer_toward_jump_target()
	move_and_slide()
	if entering:
		_play(&"enter", -1, ActionPriority.SYSTEM)
	elif not is_on_floor():
		play_action(&"rise" if velocity.y < 0.0 else &"fall")
	elif _ground_state == GroundState.WALK:
		play_action(&"run" if is_running() else &"walk")
	else:
		_play_locomotion(&"idle")


## 現在是不是在奔跑:積木/測試者開了 run,或有啟用中的狀態鏡勾了「啟用期間奔跑」。
func is_running() -> bool:
	if run_enabled:
		return true
	for lens_name: String in _active_lenses:
		var lens := _find_lens(lens_name)
		if lens != null and lens.force_run:
			return true
	return false


func _walk_speed() -> float:
	return params.move_speed * (params.run_speed_multiplier if is_running() else 1.0) * (vitality.speed_factor() if vitality != null else 1.0) * lens_mod("speed")


## 地面/靜止模式下連續起跳 count 次(大跳用完整初速度,小跳用約 55%);每次落地後才起跳下一次。
func perform_hops(count: int, big: bool) -> void:
	if bottom_anchored:
		return
	hops_left = maxi(count, 0)
	_hop_scale = 1.0 if big else 0.55


## 讓視覺根節點在原地隨機抖動 seconds 秒(只動畫面,不影響實際座標與物理)。
func shiver(seconds: float) -> void:
	_shiver_left = seconds


func _process_ground(delta: float) -> void:
	if _climb != ClimbState.NONE:
		_process_climb(delta)
		return
	if move_mode == MoveMode.GROUND or (move_mode == MoveMode.FLYING and fly_behavior == FlyBehavior.HYBRID):
		var goal: Variant = _movement_goal()
		if goal is Vector2:
			_process_ground_seek(delta, goal)
			return
	if _prop_still_left > 0.0 and _ground_state == GroundState.WALK:
		_enter_idle()   # 道具交互中:停下來,不要邊走邊被洗澡
	if _dance_cue_left >= 0.0:
		_tick_dance_cue(delta)
	if _dance_left > 0.0 and (_interact_left > 0.0 or _hold_left > 0.0 or entering or not auto_dance_enabled or lens_blocks("dance")):
		# 被互動、被積木佔用、入場、開關關掉、或身上出現負面狀態鏡:立刻收舞(狀態鏡的疲倦等優先於自主跳舞)。
		_dance_left = 0.0
		_state_timer = 0.0
	velocity.y = minf(velocity.y + _gravity * params.gravity_scale * _lens_gravity * delta, params.terminal_fall_velocity)
	if is_on_floor() and _airborne_grace <= 0.0:
		_jump_target_x = NAN
		_state_timer -= delta
		_dance_left = maxf(_dance_left - delta, 0.0)
		if _ground_state == GroundState.WALK:
			velocity.x = _walk_dir * _walk_speed()
			if _state_timer <= 0.0:
				_enter_idle()
			else:
				_consider_edge_and_hop(delta)
		elif _state_timer <= 0.0:
			if _try_start_dance():
				pass
			elif move_mode == MoveMode.STATIONARY or _prop_still_left > 0.0:
				_enter_idle()
			else:
				_enter_walk()
		if _ground_state == GroundState.IDLE or _interact_left > 0.0 or _hold_left > 0.0 or _converse_left > 0.0 or entering:
			velocity.x = 0.0
		# 站著發呆(或站著休息)時偶爾原地小跳一下;被互動、對話、跳舞、爬牆或被積木佔用(站著休息除外)時不跳。
		if _ground_state == GroundState.IDLE and hops_left == 0 and not entering and not dragging and _interact_left <= 0.0 and _converse_left <= 0.0 and _dance_left <= 0.0 \
				and (_hold_left <= 0.0 or (vitality != null and vitality.mode == PetVitality.Mode.STANDING)) and not _dialogue_open and randf() < params.idle_hop_chance * delta:
			perform_hops(1, false)
		if hops_left > 0 and not entering:
			hops_left -= 1
			velocity = Vector2(0.0, -_normal_jump_speed() * _hop_scale)
	else:
		_edge_committed = false
		_dance_left = 0.0
		release_hold()
		_steer_toward_jump_target()
	move_and_slide()
	if is_on_wall() and _ground_state == GroundState.WALK:
		if not _try_start_climb():
			_walk_dir = -_walk_dir
			_face(_walk_dir)
	if _climb != ClimbState.NONE:
		return
	if entering:
		_play(&"enter", -1, ActionPriority.SYSTEM)
	elif not is_on_floor():
		play_action(&"rise" if velocity.y < 0.0 else &"fall")
	elif _ground_state == GroundState.WALK and _interact_left <= 0.0 and _converse_left <= 0.0:
		play_action(&"run" if is_running() else &"walk")
	else:
		_play_locomotion(&"dance" if _dance_left > 0.0 else &"idle")


## 走到行動區的左/右邊界牆時,有機會改成爬上去(而不是轉身)。條件:開了攀爬、地面模式、沒在互動/被積木佔用/入場、
## 沒有負面狀態鏡(累了不爬),擲中 params.climb_chance,而且真的是頂著行動區的左右邊界(平臺的側面不算)。
func _try_start_climb() -> bool:
	if not climb_enabled or move_mode != MoveMode.GROUND or entering or dragging or bottom_anchored:
		return false
	if _interact_left > 0.0 or _hold_left > 0.0 or _converse_left > 0.0 or lens_blocks("climb"):
		return false
	if randf() >= params.climb_chance:
		return false
	var rect := _bounds()
	var half := BODY_SIZE.x * params.scale_multiplier * 0.5
	var side := 0
	if position.x <= rect.position.x + half + 3.0 and _walk_dir < 0:
		side = -1
	elif position.x >= rect.end.x - half - 3.0 and _walk_dir > 0:
		side = 1
	if side == 0:
		return false
	_begin_wall_climb(side, -1, minf(position.y, rect.end.y - _climb_length() * 0.5), false)
	return true


## 貼在牆上/天花板上時,沿著牆(或天花板)方向的身體長度;腳底 = 貼牆的那一邊。
func _climb_length() -> float:
	return _frame_size.x * params.scale_multiplier


## 有專屬的爬牆動畫(climb_wall 素材,畫的是直立貼在牆邊的樣子)就不轉 90°,直立貼著牆爬;沒有才用 walk 轉 90° 湊。
func _wall_upright() -> bool:
	return not _find_variants(_lens_base(CLIMB_ACTION_WALL)).is_empty()


func _climb_height() -> float:
	return _frame_size.y * params.scale_multiplier


## 有專屬的天花板動畫(climb_ceiling 素材,畫的是倒掛在天花板上的樣子,軸心 = 抓著天花板的那一點)就直接播、不旋轉;
## 沒有就維持原本的做法:用 walk 動畫整隻倒過來(180°)走。
func _ceiling_dedicated() -> bool:
	return not _find_variants(_lens_base(CLIMB_ACTION_CEILING)).is_empty()


func _climb_rotation() -> float:
	if _climb == ClimbState.CEILING:
		return 0.0 if _ceiling_dedicated() else PI
	if _wall_upright():
		return 0.0
	return -PI * 0.5 if _climb_side > 0 else PI * 0.5


## y 是「轉 90° 貼牆」時身體中心的高度;直立貼牆時改用腳底高度(從天花板轉下來 = 頭貼著天花板,其餘 = 現在的高度)。
func _begin_wall_climb(side: int, direction: int, y: float, from_ceiling: bool) -> void:
	_climb = ClimbState.WALL
	_climb_side = side
	_climb_dir = direction
	_enter_climb_common()
	var rect := _bounds()
	if _wall_upright():
		var half_width := _climb_length() * 0.5
		position = Vector2(rect.end.x - half_width if side > 0 else rect.position.x + half_width, rect.position.y + _climb_height() if from_ceiling else minf(position.y, rect.end.y))
	else:
		position = Vector2(rect.end.x if side > 0 else rect.position.x, y)


func _begin_ceiling_climb(direction: int, x: float) -> void:
	_climb = ClimbState.CEILING
	_climb_dir = direction
	_enter_climb_common()
	position = Vector2(x, _bounds().position.y)


func _enter_climb_common() -> void:
	collision_mask = 0
	velocity = Vector2.ZERO
	_dance_left = 0.0
	_edge_committed = false
	_ground_state = GroundState.IDLE
	_climb_timer = randf_range(CLIMB_SEGMENT_TIME.x, CLIMB_SEGMENT_TIME.y)
	_apply_climb_pose()


## 依目前貼的面決定整隻的旋轉角度,以及讓「往前」剛好是想爬的方向(牆:右牆 facing +1 = 往上、左牆 facing +1 = 往下;天花板:facing +1 = 往左)。
func _apply_climb_pose() -> void:
	var facing := -_climb_dir
	if _climb == ClimbState.WALL and _climb_side < 0:
		facing = _climb_dir
	if _climb == ClimbState.WALL and _wall_upright():
		facing = _climb_side
	if _climb == ClimbState.CEILING and _ceiling_dedicated():
		facing = _climb_dir
	_face(facing)
	_visual_root.rotation = _climb_rotation()


## 離開攀爬:恢復直立、碰撞與重力。fall = true 是鬆手掉落(離開牆面/天花板一小段再落下);
## place = false 表示位置由呼叫者處理(被拖曳、切換移動模式)。
func _exit_climb(fall: bool, place := true) -> void:
	if _climb == ClimbState.NONE:
		return
	var was := _climb
	var side := _climb_side
	_climb = ClimbState.NONE
	_climb_pause = 0.0
	_visual_root.rotation = 0.0
	if move_mode == MoveMode.GROUND or move_mode == MoveMode.STATIONARY:
		collision_mask = Layers.PLATFORM | Layers.BOUNDARY_WALL
	if place and _action_area != null:
		var rect := _bounds()
		var half := BODY_SIZE.x * params.scale_multiplier * 0.5
		var height := BODY_SIZE.y * params.scale_multiplier
		if was == ClimbState.CEILING:
			position.y = rect.position.y + height + CLIMB_RELEASE_GAP
		else:
			position.x = rect.end.x - half - CLIMB_RELEASE_GAP if side > 0 else rect.position.x + half + CLIMB_RELEASE_GAP
		position = clamp_to_bounds(position)
	if fall:
		velocity = Vector2(-side * CLIMB_RELEASE_SPEED if was == ClimbState.WALL else 0.0, 0.0)
		_airborne_grace = THROW_GRACE
	else:
		velocity = Vector2.ZERO
	_enter_idle()
	_walk_dir = -side if was == ClimbState.WALL else _walk_dir
	_face(_walk_dir)


func _process_climb(delta: float) -> void:
	if lens_blocks("climb") or _movement_goal() is Vector2 or move_mode != MoveMode.GROUND or not climb_enabled:
		_exit_climb(true)
		return
	var rect := _bounds()
	var half_len := _climb_length() * 0.5
	var upright := _climb == ClimbState.WALL and _wall_upright()
	# 沿牆方向:轉 90° 時身體長度是寬(以中心為準),直立時是高(以腳底為準,頭在上面)。
	var top_extent := _climb_height() if upright else half_len
	var bottom_extent := 0.0 if upright else half_len
	var busy := _interact_left > 0.0 or _hold_left > 0.0 or _converse_left > 0.0
	_climb_pause = maxf(_climb_pause - delta, 0.0)
	var moving := not busy and _climb_pause <= 0.0
	if _climb == ClimbState.WALL:
		if upright:
			position.x = rect.end.x - half_len if _climb_side > 0 else rect.position.x + half_len
		else:
			position.x = rect.end.x if _climb_side > 0 else rect.position.x
	else:
		position.y = rect.position.y
	if moving:
		var step := _walk_speed() * params.climb_speed_multiplier * delta
		if _climb == ClimbState.WALL:
			position.y += _climb_dir * step
			if _climb_dir < 0 and position.y - top_extent <= rect.position.y:
				# 爬到頂:轉到天花板,往遠離這面牆的方向爬。
				_begin_ceiling_climb(-_climb_side, rect.end.x - half_len if _climb_side > 0 else rect.position.x + half_len)
				return
			if _climb_dir > 0 and position.y + bottom_extent >= rect.end.y:
				# 爬到底:踩回地面。
				_exit_climb(false)
				position = clamp_to_bounds(Vector2(position.x, rect.end.y))
				return
		else:
			position.x += _climb_dir * step
			if _climb_dir < 0 and position.x - half_len <= rect.position.x:
				_begin_wall_climb(-1, 1, rect.position.y + half_len, true)
				return
			if _climb_dir > 0 and position.x + half_len >= rect.end.x:
				_begin_wall_climb(1, 1, rect.position.y + half_len, true)
				return
	# 位置被行動區縮小等情況推到範圍外時拉回來。
	if _climb == ClimbState.WALL:
		position.y = clampf(position.y, rect.position.y + top_extent, maxf(rect.end.y - bottom_extent, rect.position.y + top_extent))
	else:
		position.x = clampf(position.x, rect.position.x + half_len, maxf(rect.end.x - half_len, rect.position.x + half_len))
	_climb_timer -= delta
	if _climb_timer <= 0.0 and not busy:
		_climb_timer = randf_range(CLIMB_SEGMENT_TIME.x, CLIMB_SEGMENT_TIME.y)
		var roll := randf()
		if roll < CLIMB_LET_GO_CHANCE:
			_exit_climb(true)
			return
		if roll < CLIMB_LET_GO_CHANCE + (1.0 - CLIMB_LET_GO_CHANCE) * CLIMB_REVERSE_CHANCE:
			_climb_dir = -_climb_dir
			_apply_climb_pose()
		else:
			_climb_pause = randf_range(CLIMB_PAUSE_TIME.x, CLIMB_PAUSE_TIME.y)
	if busy:
		_play_locomotion(&"idle")
	elif _climb_pause > 0.0:
		if upright or (_climb == ClimbState.CEILING and _ceiling_dedicated()):
			_sprite.pause()
		else:
			_play_locomotion(&"idle")
	else:
		play_action(CLIMB_ACTION_WALL if _climb == ClimbState.WALL else CLIMB_ACTION_CEILING)


## 自主跳舞(新的系統動作 dance):待機時間結束時,沒有負面狀態鏡、開關開著、素材有 dance 動作,
## 就有 auto_dance_chance 的機率改成原地跳一段舞(DANCE_DURATION 秒)再繼續原本的行程。
## 沒有 dance 素材就不跳(不退回 idle,免得桌寵站著不動卻被當成在跳舞)。地面/靜止模式限定,跟隨中不會跳。
func _try_start_dance() -> bool:
	if not auto_dance_enabled or entering or _dance_left > 0.0 or _interact_left > 0.0 or _hold_left > 0.0:
		return false
	var dance_mod := lens_mod("dance")
	var dance_chance := maxf(auto_dance_chance * dance_mod, 0.12 if dance_mod > 1.0 else 0.0)   # 開心、悠哉:更愛跳舞(平常不跳舞的性格也有一點點機會);疲憊擋掉(見 _start_dance)
	if randf() >= dance_chance:
		return false
	return _start_dance()


## 開始跳一段舞(自己待機結束擲中、或看到別人跳舞被帶動時共用)。沒有素材、有負面狀態鏡、正在做別的事就不跳。
func _start_dance() -> bool:
	if not auto_dance_enabled or entering or _dance_left > 0.0 or _interact_left > 0.0 or _hold_left > 0.0:
		return false
	if lens_blocks("dance") or _find_variants(_lens_base(&"dance")).is_empty():
		return false
	var duration := randf_range(DANCE_DURATION.x, DANCE_DURATION.y)
	_dance_left = duration
	_state_timer = duration
	_ground_state = GroundState.IDLE
	_shell_state.pet_dance_started.emit(self)
	return true


## 場內別的桌寵開始跳舞:自己(開著「跟著跳」、沒有負面狀態鏡)隔 0.5~2 秒後有 DANCE_FOLLOW_CHANCE 的機率也跳,
## 只在站著待機時才會加入。這是內建的自主行為,不需要積木。
func _on_dance_cue(source: Node) -> void:
	if source == self or not auto_dance_follow_enabled or not auto_dance_enabled or _dance_left > 0.0:
		return
	_dance_cue_left = randf_range(0.5, 2.0)


func _tick_dance_cue(delta: float) -> void:
	_dance_cue_left -= delta
	if _dance_cue_left > 0.0:
		return
	_dance_cue_left = -1.0
	if _ground_state == GroundState.IDLE and is_on_floor() and randf() < DANCE_FOLLOW_CHANCE:
		_start_dance()


## 有沒有生效中、標記為「負面」而且不在 LensBehavior 效果表裡的狀態鏡(使用者自己建的)。
func has_unlisted_negative_lens() -> bool:
	for lens: PetStateLens in state_lenses:
		if lens.has_nature("負面") and _active_lenses.has(lens.lens_name) and LensBehavior.of(lens.lens_name).is_empty():
			return true
	return false


## 身上有沒有任何生效中的「負面」狀態鏡(疲倦之類)。
func has_negative_lens() -> bool:
	for lens: PetStateLens in state_lenses:
		if lens.has_nature("負面") and _active_lenses.has(lens.lens_name):
			return true
	return false


## 走路時的邊緣與跳躍決策。走到平臺邊緣:優先跳上前方較高的平臺,否則依機率轉身或直接走下去
## (順著重力落到較低的平臺);平常走路時,前方有跳得到的較高平臺也會隨機順手跳上去。
func _consider_edge_and_hop(delta: float) -> void:
	if _interact_left > 0.0 or _hold_left > 0.0 or _converse_left > 0.0 or entering:
		return
	if _edge_ahead():
		if _edge_committed:
			return
		_edge_committed = true
		var dx := _find_jump_dx(_walk_dir)
		if not is_nan(dx) and randf() < 0.7:
			_jump(dx)
		elif randf() >= params.edge_drop_chance:
			_walk_dir = -_walk_dir
			_face(_walk_dir)
			_edge_committed = false
	else:
		_edge_committed = false
		if randf() < params.hop_chance_per_second * delta:
			var dx := _find_jump_dx(_walk_dir)
			if not is_nan(dx):
				_jump(dx)


## 行走方向前面是不是沒有可站的平臺了(超出行動區邊界的那一側由邊界牆處理,不算邊緣)。
func _edge_ahead() -> bool:
	var offset := _walk_dir * (BODY_SIZE.x * params.scale_multiplier * 0.5 + EDGE_LOOKAHEAD)
	var area := _bounds()
	if position.x + offset <= area.position.x or position.x + offset >= area.end.x:
		return false
	_edge_probe.position = Vector2(offset, -EDGE_PROBE_RISE)
	_edge_probe.force_raycast_update()
	return not _edge_probe.is_colliding()


## 在 direction 方向上找一個跳得到的較高平臺,回傳起跳後要水平位移的距離;找不到回傳 NAN。
## 跳得到的條件:平臺高度差在最大跳躍高度內、頭不會撞到行動區頂端,而且以空中水平速度
## 在「下落穿過該平臺高度」之前能夠飛到平臺範圍內(單向平臺允許從下方穿過)。
func _find_jump_dx(direction: int) -> float:
	var manager := _get_platform_manager()
	if manager == null:
		return NAN
	var gravity := _gravity * params.gravity_scale * _lens_gravity
	# 跳得到的判斷用「最大跳躍力道」;真正起跳時每個平臺只用它需要的力道(至少是平時跳躍),不會每次都跳到最高。
	var max_speed := maxf(params.max_jump_velocity, params.jump_velocity)
	var max_rise := max_speed * max_speed / (2.0 * gravity) - JUMP_CLEARANCE
	var best_speed := 0.0
	var air_speed := params.move_speed * params.jump_air_speed_multiplier
	var half_width := BODY_SIZE.x * params.scale_multiplier * 0.5
	var body_height := BODY_SIZE.y * params.scale_multiplier
	var area := _bounds()
	var best := NAN
	for rect: Rect2 in manager.platform_rects:
		var rise := position.y - rect.position.y
		if rise < MIN_JUMP_RISE or rise > max_rise:
			continue
		if rect.position.y - body_height < area.position.y + JUMP_CLEARANCE:
			continue
		var left := rect.position.x + half_width
		var right := rect.end.x - half_width
		if right <= left:
			continue
		var dx := clampf(position.x, left, right) - position.x
		if dx != 0.0 and signf(dx) != float(direction):
			continue
		var speed_y := clampf(maxf(sqrt(2.0 * gravity * (rise + JUMP_CLEARANCE + 12.0)) * 1.04, params.jump_velocity), 1.0, max_speed)
		var flight := (speed_y + sqrt(maxf(speed_y * speed_y - 2.0 * gravity * rise, 0.0))) / gravity
		if absf(dx) > air_speed * flight - JUMP_CLEARANCE:
			continue
		if is_nan(best) or absf(dx) < absf(best):
			best = dx
			best_speed = speed_y
	_planned_jump_speed = best_speed if not is_nan(best) else 0.0
	return best


## 平時跳躍的力道:jump_velocity 上下浮動 jump_variance(比例)。
func _normal_jump_speed() -> float:
	return params.jump_velocity * (1.0 + randf_range(-params.jump_variance, params.jump_variance)) * lens_mod("jump")


## 要跳上 rise 像素高的地方需要的起跳力道(至少是平時跳躍,最多是最大跳躍力道)。
func _goal_jump_speed(rise: float) -> float:
	var needed := sqrt(2.0 * _gravity * params.gravity_scale * _lens_gravity * (maxf(rise, 0.0) + JUMP_CLEARANCE + 20.0)) * 1.04
	return clampf(maxf(needed, _normal_jump_speed()), 1.0, maxf(params.max_jump_velocity, params.jump_velocity))


## 下一次跳要用的力道(由 _find_jump_dx 或目標導向移動排定,用一次就清掉;0 = 用平時跳躍)。
var _planned_jump_speed := 0.0
var _seek_jump_failures := 0
var _seek_last_y := INF


func _jump(dx: float) -> void:
	if bottom_anchored:
		_planned_jump_speed = 0.0
		return   # 貼底:不跳
	velocity.y = -(_planned_jump_speed if _planned_jump_speed > 0.0 else _normal_jump_speed())
	_planned_jump_speed = 0.0
	_jump_target_x = position.x + dx
	if absf(dx) > 1.0:
		velocity.x = signf(dx) * params.move_speed * params.jump_air_speed_multiplier
		_walk_dir = 1 if dx > 0.0 else -1
		_face(_walk_dir)
	else:
		velocity.x = 0.0


## 空中飛到目標落點的正上方就把水平速度歸零,避免衝過頭。
func _steer_toward_jump_target() -> void:
	if is_nan(_jump_target_x) or velocity.x == 0.0:
		return
	if (_jump_target_x - position.x) * velocity.x <= 0.0:
		velocity.x = 0.0
		_jump_target_x = NAN


func _get_platform_manager() -> Node:
	if _platform_manager == null or not is_instance_valid(_platform_manager):
		_platform_manager = get_tree().get_first_node_in_group("platform_manager")
	return _platform_manager


func _process_flying(delta: float) -> void:
	if fly_behavior == FlyBehavior.ALWAYS and is_resting_now():
		# 總是飛行的桌寵不落地:休息、睡覺都停在空中(輕輕上下飄)。
		_fly_time += delta
		velocity = Vector2(0.0, cos(_fly_time * params.fly_bob_frequency) * params.fly_bob_amplitude * params.fly_bob_frequency * 0.5)
		move_and_slide()
		_play_locomotion(&"fly")
		return
	if fly_behavior == FlyBehavior.ALWAYS and is_resting_now():
		# 總是飛行的桌寵不落地:休息、睡覺都停在空中(輕輕上下飄)。
		_fly_time += delta
		velocity = Vector2(0.0, cos(_fly_time * params.fly_bob_frequency) * params.fly_bob_amplitude * params.fly_bob_frequency * 0.5)
		move_and_slide()
		_play_locomotion(&"fly")
		return
	var goal: Variant = _movement_goal()
	if goal is Vector2:
		var to_goal: Vector2 = goal - position
		maybe_drop_through(goal, delta)
		velocity = (to_goal * 3.0).limit_length(params.move_speed * 1.5) if to_goal.length() > FOLLOW_DEADZONE else Vector2.ZERO
		move_and_slide()
		if absf(velocity.x) > 1.0:
			_face(1 if velocity.x > 0.0 else -1)
		_play_locomotion(&"fly")
		return
	if _prop_still_left > 0.0:
		if land_for_props and fly_behavior == FlyBehavior.LANDS:
			if _fly_state == FlyState.CRUISE and _fly_launch_left <= 0.0:
				_fly_begin_landing()
		else:
			velocity = Vector2.ZERO   # 不降落:原地懸停等交互結束
			move_and_slide()
			_play_locomotion(&"fly")
			return
	_fly_time += delta
	_rise_anim_left = maxf(_rise_anim_left - delta, 0.0)
	if _fly_launch_left > 0.0:
		# 剛被拋出:依慣性滑行、速度逐漸衰減,滑完才回到自己的巡航(這樣才拋得高、拋得遠)。
		_fly_launch_left -= delta
		velocity *= maxf(1.0 - FLY_LAUNCH_DRAG * delta, 0.0)
		move_and_slide()
		_face_by_velocity()
		_play_locomotion(&"fly")
		if _fly_launch_left <= 0.0:
			velocity = Vector2.ZERO
			_fly_pick_goal()
		return
	match _fly_state:
		FlyState.CRUISE:
			_fly_cruise(delta)
		FlyState.LANDING:
			_fly_landing(delta)
		FlyState.RESTING:
			_fly_resting(delta)
	if fly_behavior == FlyBehavior.HYBRID and _hybrid_airborne:
		_hybrid_flight_tick(delta)


## 進入飛行模式時的初始化:耐力補滿,先飛到初始巡航高度。
func _fly_reset() -> void:
	_fly_state = FlyState.CRUISE
	_fly_stamina = params.fly_stamina
	_fly_wait_left = 0.0
	_fly_launch_left = 0.0
	_fly_goal = Vector2(position.x, _bounds().end.y - params.fly_hover_height) if _action_area != null else position


## 巡航:在行動區內飛向隨機目標(有時在較高平臺上方),抵達後有機率滯空一會兒;
## 途中隨時可能臨場改變目標(轉彎)、撞牆也會改目標。耐力隨時間消耗,低了就找地方降落休息。
func _fly_cruise(delta: float) -> void:
	_fly_stamina -= delta
	if _fly_wait_left > 0.0:
		_fly_wait_left -= delta
		velocity = Vector2(0.0, cos(_fly_time * params.fly_bob_frequency) * params.fly_bob_amplitude * params.fly_bob_frequency)
	else:
		var to_goal := _fly_goal - position
		if to_goal.length() < FOLLOW_DEADZONE * 2.0:
			if randf() < params.fly_pause_chance:
				_fly_wait_left = randf_range(1.0, 3.0)
			_fly_pick_goal()
		else:
			velocity = to_goal.normalized() * params.move_speed
			velocity.y += cos(_fly_time * params.fly_bob_frequency) * params.fly_bob_amplitude * params.fly_bob_frequency
			if randf() < 0.12 * delta:
				_fly_pick_goal()
	move_and_slide()
	if is_on_wall() or (_fly_wait_left <= 0.0 and _fly_gave_up(delta)):
		_fly_pick_goal()
	_face_by_velocity()
	_play_locomotion(&"rise" if _rise_anim_left > 0.0 else &"fly")
	if fly_behavior != FlyBehavior.LANDS:
		return   # 總是飛行 / 兼具:不因耐力自己降落(兼具的降落由 _hybrid_flight_tick 決定)
	var tired := _fly_stamina <= params.fly_stamina * 0.3
	if _fly_stamina <= 0.0 or (tired and randf() < 0.5 * delta) or randf() < 0.01 * delta:
		_fly_begin_landing()


func _fly_pick_goal() -> void:
	var area := _bounds()
	var half_width := BODY_SIZE.x * params.scale_multiplier * 0.5
	var height := BODY_SIZE.y * params.scale_multiplier
	var y_min := area.position.y + height + 20.0
	var goal := Vector2(
		randf_range(area.position.x + half_width, area.end.x - half_width),
		randf_range(y_min, maxf(y_min, area.end.y - 90.0))
	)
	var manager := _get_platform_manager()
	if manager != null and not manager.platform_rects.is_empty() and randf() < 0.4:
		var rect: Rect2 = manager.platform_rects.pick_random()
		goal.x = clampf(randf_range(rect.position.x, rect.end.x), area.position.x + half_width, area.end.x - half_width)
		goal.y = maxf(rect.position.y - 90.0, y_min)
	_fly_goal = goal
	_fly_reset_progress()


func _fly_reset_progress() -> void:
	_fly_stuck_timer = 0.0
	_fly_stuck_count = 0
	_fly_check_pos = position


## 每秒檢查一次位移;連續兩次都幾乎沒動(被牆、平臺擋住等)就回傳 true,表示該放棄目前的目標。
func _fly_gave_up(delta: float) -> bool:
	_fly_stuck_timer += delta
	if _fly_stuck_timer < 1.0:
		return false
	_fly_stuck_timer = 0.0
	if position.distance_to(_fly_check_pos) < FLY_STUCK_DISTANCE:
		_fly_stuck_count += 1
	else:
		_fly_stuck_count = 0
	_fly_check_pos = position
	return _fly_stuck_count >= 2


## 挑一個落點(地面或某個視窗上緣)開始降落。
func _fly_begin_landing() -> void:
	var area := _bounds()
	var half_width := BODY_SIZE.x * params.scale_multiplier * 0.5
	var spots: Array[Vector2] = [
		Vector2(randf_range(area.position.x + half_width, area.end.x - half_width), area.end.y - GROUND_TOP_OFFSET)
	]
	var manager := _get_platform_manager()
	if manager != null:
		for rect: Rect2 in manager.platform_rects:
			var left := rect.position.x + half_width
			var right := rect.end.x - half_width
			var x := rect.get_center().x if right <= left else randf_range(left, right)
			spots.append(Vector2(x, rect.position.y))
	# 排除先前飛不到而放棄的落點;全部都被排除的話就重新開始算,不會沒地方可降。
	var candidates := spots.filter(
		func(spot: Vector2) -> bool:
			return not _fly_failed_spots.any(func(failed: Vector2) -> bool: return spot.distance_to(failed) < FLY_FAILED_SPOT_RADIUS)
	)
	if candidates.is_empty():
		_fly_failed_spots.clear()
		candidates = spots
	_fly_land_spot = candidates.pick_random()
	_fly_state = FlyState.LANDING
	_fly_reset_progress()


## 降落:先飛到落點正上方,對準後再垂直下降,碰到站立面就開始休息。
func _fly_landing(delta: float) -> void:
	if _fly_gave_up(delta):
		# 這個落點飛不到:記下來、放棄,轉向尋找其他降落點。
		_fly_failed_spots.append(_fly_land_spot)
		_fly_begin_landing()
		return
	var aligned := absf(_fly_land_spot.x - position.x) < 24.0
	# 只有已經在落點上方才往下降;從平臺下方對準了水平位置時要先飛到上方,
	# 否則會穿過單向平臺、卡在它下面永遠碰不到站立面。
	var above := position.y <= _fly_land_spot.y + 4.0
	var aim := Vector2(_fly_land_spot.x, _fly_land_spot.y + 12.0) if (aligned and above) else Vector2(_fly_land_spot.x, _fly_land_spot.y - 70.0)
	velocity = (aim - position).limit_length(params.move_speed)
	move_and_slide()
	_face_by_velocity()
	_play_locomotion(&"fall")
	if aligned and is_on_floor():
		_fly_failed_spots.clear()
		_fly_state = FlyState.RESTING
		_fly_rest_left = randf_range(params.fly_rest_duration_min, params.fly_rest_duration_max)
		velocity = Vector2.ZERO


## 休息:站在平臺上原地播放 sit(素材沒有就退回 idle);腳下平臺消失就順著重力落下,落到新的站立面再繼續休息。
## 休息完耐力補滿,往上起飛(播放 rise)。
func _fly_resting(delta: float) -> void:
	velocity.y = minf(velocity.y + _gravity * params.gravity_scale * _lens_gravity * delta, params.terminal_fall_velocity)
	velocity.x = 0.0
	move_and_slide()
	if not is_on_floor():
		_play_locomotion(&"fly")
		return
	_play_locomotion(&"sit")
	if _prop_still_left > 0.0 or is_resting_now():
		_fly_rest_left = maxf(_fly_rest_left, 0.5)   # 道具交互還沒結束,先不起飛
	_fly_rest_left -= delta
	if _fly_rest_left <= 0.0:
		_fly_stamina = params.fly_stamina
		_fly_state = FlyState.CRUISE
		_rise_anim_left = 0.8
		var area := _bounds()
		var height := BODY_SIZE.y * params.scale_multiplier
		_fly_goal = Vector2(position.x + randf_range(-80.0, 80.0), maxf(position.y - 160.0, area.position.y + height + 20.0))


## 兼具模式的地面階段:從平臺走下來(下墜)、大跳躍、或每 HYBRID_CHECK_INTERVAL 秒擲一次(心情好機率高)都可能改成飛行。
func _hybrid_ground_tick(delta: float) -> void:
	if is_on_floor():
		_hybrid_air_checked = false
	elif not _hybrid_air_checked and not dragging and not entering and not is_resting_now():
		if velocity.y < -HYBRID_BIG_JUMP_SPEED:
			_hybrid_air_checked = true
			if randf() < HYBRID_BIG_JUMP_CHANCE:
				_hybrid_begin_flight()
		elif velocity.y > 120.0:
			_hybrid_air_checked = true
			if randf() < HYBRID_DROP_CHANCE:
				_hybrid_begin_flight()
	_hybrid_check_left -= delta
	if _hybrid_check_left <= 0.0:
		_hybrid_check_left = HYBRID_CHECK_INTERVAL
		if is_on_floor() and hybrid_can_take_off() and randf() < hybrid_random_chance():
			_hybrid_begin_flight()


## 兼具模式隨機起飛的機率(每次檢查):基本 5%,心情越好越高(心情 50 以上開始加,最多再加 15%)。
func hybrid_random_chance() -> float:
	var mood_bonus := 0.0
	if vitality != null:
		mood_bonus = clampf((vitality.mood - 50.0) / 50.0, 0.0, 1.0) * 0.15
	return HYBRID_RANDOM_BASE + mood_bonus


func hybrid_can_take_off() -> bool:
	return not (dragging or entering or is_resting_now() or _interact_left > 0.0 or _hold_left > 0.0 or _converse_left > 0.0 or _prop_still_left > 0.0 or bottom_anchored or _climb != ClimbState.NONE or _dance_left > 0.0)


func _hybrid_begin_flight() -> void:
	if _hybrid_airborne:
		return
	_hybrid_airborne = true
	_hybrid_fly_left = randf_range(HYBRID_FLY_SECONDS.x, HYBRID_FLY_SECONDS.y)
	_fly_state = FlyState.CRUISE
	_fly_stamina = params.fly_stamina
	_fly_wait_left = 0.0
	_fly_launch_left = 0.0
	_rise_anim_left = 0.8
	_current_action = &""
	var area := _bounds()
	var height := BODY_SIZE.y * params.scale_multiplier
	_fly_goal = Vector2(clampf(position.x + randf_range(-160.0, 160.0), area.position.x + 40.0, area.end.x - 40.0), maxf(position.y - randf_range(80.0, 200.0), area.position.y + height + 20.0))
	_fly_reset_progress()


## 兼具模式的飛行階段:時間到就找地方降落,一碰到站立面就回到走路(不用坐下休息)。
func _hybrid_flight_tick(delta: float) -> void:
	_hybrid_fly_left -= delta
	if _hybrid_fly_left <= 0.0 and _fly_state == FlyState.CRUISE:
		_fly_begin_landing()
	if _fly_state == FlyState.RESTING or (is_on_floor() and _fly_state != FlyState.CRUISE):
		_hybrid_airborne = false
		_hybrid_air_checked = true
		_hybrid_check_left = HYBRID_CHECK_INTERVAL
		_fly_state = FlyState.CRUISE
		velocity = Vector2.ZERO
		_enter_idle()


func _face_by_velocity() -> void:
	if absf(velocity.x) > 8.0:
		_face(1 if velocity.x > 0.0 else -1)


func _process_floating(delta: float) -> void:
	if is_resting_now():
		# 漂浮的桌寵休息、睡覺時慢慢停下來,原地不動。
		velocity = velocity.lerp(Vector2.ZERO, minf(4.0 * delta, 1.0))
		move_and_collide(velocity * delta)
		_play_locomotion(&"idle")
		return
	if _prop_still_left > 0.0:
		velocity = velocity.lerp(Vector2.ZERO, minf(5.0 * delta, 1.0))
		move_and_collide(velocity * delta)
		_play_locomotion(&"idle")
		return
	var goal: Variant = _movement_goal()
	var seeking := goal is Vector2
	if seeking:
		var to_goal: Vector2 = goal - position
		var desired := Vector2.ZERO if to_goal.length() < FOLLOW_DEADZONE else to_goal.normalized() * params.move_speed * 1.5
		velocity = velocity.lerp(desired, 2.5 * delta)
	if not seeking and velocity.length() < params.float_min_speed:
		var direction := velocity.normalized() if velocity != Vector2.ZERO else Vector2.from_angle(randf() * TAU)
		velocity = direction * params.float_min_speed
	var collision := move_and_collide(velocity * delta)
	if collision:
		velocity = velocity.bounce(collision.get_normal()) * params.restitution
	# move_and_collide 已對單步位移做掃描式碰撞偵測,這裡的座標鉗制是防止高速穿模的最後一道防線。
	position = clamp_to_bounds(position)
	if absf(velocity.x) > 1.0:
		_face(signi(int(velocity.x)))
	_play_locomotion(&"idle")


func _enter_idle() -> void:
	_ground_state = GroundState.IDLE
	_state_timer = randf_range(params.idle_duration_min, params.idle_duration_max) * lens_mod("pause_time")


func _enter_walk() -> void:
	if lens_add("pause_chance") > 0.0 and randf() < lens_add("pause_chance"):
		_enter_idle()   # 悲傷、疲憊:走一段之後更常停下來發呆
		return
	_ground_state = GroundState.WALK
	_state_timer = randf_range(params.walk_duration_min, params.walk_duration_max)
	_walk_dir = 1 if randf() < 0.5 else -1
	_face(_walk_dir)


func _bounds() -> Rect2:
	return _action_area.boundary_rect


func _face(direction: int) -> void:
	if direction == 0:
		return
	_facing = direction
	_visual_root.scale.x = _visual_sign() * params.scale_multiplier


func _visual_sign() -> float:
	return -float(_facing) if art_flipped else float(_facing)


func _apply_scale() -> void:
	var multiplier := params.scale_multiplier
	_visual_root.scale = Vector2(_visual_sign() * multiplier, multiplier)
	var shape := RectangleShape2D.new()
	shape.size = BODY_SIZE * multiplier
	_shape_node.shape = shape
	_shape_node.position = Vector2(0.0, -BODY_SIZE.y * multiplier * 0.5)


func _find_variants(action_name: StringName) -> Array[int]:
	var variants: Array[int] = []
	var prefix := "%s_" % action_name
	for animation in _sprite.sprite_frames.get_animation_names():
		if animation.begins_with(prefix):
			var suffix := animation.trim_prefix(prefix)
			if suffix.is_valid_int():
				variants.append(suffix.to_int())
	return variants
