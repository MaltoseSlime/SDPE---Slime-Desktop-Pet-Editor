class_name PetMovementParams
extends Resource
## 角色專屬行動物理數值(主企劃書第四章「角色專屬行動物理數值配置」)。
## 每隻桌寵各自一份,由 Pet 節點讀取;之後狀態鏡的「移動數值覆蓋」也是覆寫這裡的欄位。

## 水平移動速度(像素/秒)。
@export var move_speed := 120.0
## 奔跑開關開啟時,移動速度的倍率(同時改播 run 動作)。
@export var run_speed_multiplier := 2.0
## 重力縮放與最大下落速度。
@export var gravity_scale := 1.0
@export var terminal_fall_velocity := 900.0
## 地面模式待機與行走的持續秒數隨機區間。
@export var idle_duration_min := 1.5
@export var idle_duration_max := 4.0
@export var walk_duration_min := 2.0
@export var walk_duration_max := 5.0
## 地面模式的跳躍:起跳初速度(決定跳得多高)、空中水平速度相對於 move_speed 的倍率、
## 平時走路時每秒有多少機率順手跳上前方較高的平臺,以及走到邊緣時選擇直接走下去(而不是轉身)的機率。
## jump_velocity = 平時跳躍(順手小跳、原地跳)的力道,每次跳會在 ±jump_variance(比例)內浮動;max_jump_velocity = 角色能嘗試的最大跳躍力道:
## 只有要上平台、被要求跟隨(目標在高處)、或連續幾次跳都沒到想去的位置時,下一次跳才會用到(需要多少用多少,不會超過它)。
@export var jump_velocity := 520.0
@export_range(0.0, 0.6) var jump_variance := 0.15
@export var max_jump_velocity := 760.0
@export var jump_air_speed_multiplier := 1.5
@export var hop_chance_per_second := 0.4
## 站著發呆(或站著休息)時,每秒有多少機率原地小跳一下(增加鮮活感)。
@export var idle_hop_chance := 0.1
@export_range(0.0, 1.0) var edge_drop_chance := 0.35
## 攀爬(桌寵開了攀爬時):走到邊界牆時改成爬上去的機率,以及爬行速度相對於走路速度的倍率。
@export_range(0.0, 1.0) var climb_chance := 0.5
@export var climb_speed_multiplier := 0.6
## 漂浮模式撞牆後保留的動能比例(0.0 至 1.0),以及維持漂移所需的最低速度。
@export_range(0.0, 1.0) var restitution := 0.9
@export var float_min_speed := 100.0
## 飛行模式:剛切換到飛行時離行動區底部的初始高度,以及上下浮動的振幅與頻率。
@export var fly_hover_height := 180.0
## 飛行耐力(可連續巡航的秒數)。耐力低時會找平臺或地面降落休息,休息完耐力補滿再起飛。
@export var fly_stamina := 25.0
@export var fly_rest_duration_min := 5.0
@export var fly_rest_duration_max := 10.0
## 抵達巡航目標後,停在原地滯空(只做上下浮動)一小段時間的機率。
@export_range(0.0, 1.0) var fly_pause_chance := 0.25
@export var fly_bob_amplitude := 8.0
@export var fly_bob_frequency := 2.0
## 個別桌寵整體縮放率,只作用於視覺根節點與碰撞箱尺寸換算,物理身體的 Transform Scale 永遠是 (1, 1)。
@export var scale_multiplier := 2.0
