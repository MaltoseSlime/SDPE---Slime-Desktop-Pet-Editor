class_name PetEffects
extends Node2D
## 角色特效(全部用程式即時繪製,不需要任何圖檔):一群小愛心、頭上大愛心、惱怒火苗、心煩意亂(三條鋸齒線)、冒汗、閃閃發光、心花怒放、全身發光、移動殘影、睏倦氣泡。
## 大小一律依角色本體高度(判定框高度 × 角色縮放)換算,大隻小隻都合比例;位置以角色腳底為原點,粒子會跟著角色走。
## 用法:積木「播放特效」(effect_play,EFFECT = 下面的名稱或英文代號)、或自動觸發(auto_enabled:開心 → 小愛心與閃光、生氣 → 火苗、疲憊 → 冒汗、疲憊或休息中 → 睏倦氣泡)。
## 每個特效都能個別客製(styles,存在角色設定檔):顏色模式(單色 / 雙色 / 單色漸層 / 雙色漸層 / 彩虹)與兩個顏色、大小倍率、密度倍率(複數粒子的特效)、
## 殘影的暫留時長與拖尾距離。
## 光敏性癲癇防護:彩虹是柔和的粉彩色(飽和度 ≤ RAINBOW_SATURATION),色相變化很慢(每 1/RAINBOW_HUE_SPEED 秒才轉一圈),不做全畫面閃爍;
## 所有粒子的明暗變化都不超過每秒 3 次(火苗搖晃 ≈ 1.8 Hz、鋸齒抖動 ≈ 2.2 Hz、閃光每顆一次亮滅 ≥ 0.7 秒、愛心跳動 ≈ 1.4 Hz),發射密度也有上限(MAX_SPAWN_PER_SECOND)。
## 睡覺的 Zzz 是另一個節點(PetSleepZ)。特效是純裝飾:不擋滑鼠,但要在視窗可見範圍裡,所以在 Cutout 群組提供每顆粒子的矩形。

## 特效名稱(給積木下拉選單與 Schema 用)→ 內部代號。英文代號與中文名稱都認。
const NAMES := {
	"一群小愛心": "hearts", "hearts": "hearts",
	"頭上大愛心": "heart_big", "heart_big": "heart_big",
	"青筋": "vein", "vein": "vein",
	"惱怒火苗": "flame", "flame": "flame",
	"心煩意亂": "confused", "confused": "confused",
	"冒汗": "sweat", "sweat": "sweat",
	"閃閃發光": "sparkle", "sparkle": "sparkle",
	"心花怒放": "flowers", "flowers": "flowers",
	"全身發光": "glow", "glow": "glow",
	"移動殘影": "afterimage", "afterimage": "afterimage",
	"睏倦氣泡": "sleepy", "sleepy": "sleepy",
	"泡沫": "foam", "foam": "foam",
	"憂愁": "gloom", "gloom": "gloom",
	"哭泣": "cry", "cry": "cry",
}
## 顯示在 Schema 與設定畫面的清單(每個特效一個中文名稱)。
const CATALOG: Array[String] = ["一群小愛心", "頭上大愛心", "青筋", "惱怒火苗", "心煩意亂", "冒汗", "閃閃發光", "心花怒放", "全身發光", "移動殘影", "睏倦氣泡", "泡沫", "憂愁", "哭泣"]
## Schema 用:每個特效 {id 英文代號, name 目前語系的顯示名稱}。網頁的積木與語法一律存代號(不隨語系變),名稱只是下拉選單的顯示。
static func catalog_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for label: String in CATALOG:
		entries.append({"id": resolve(label), "name": TranslationServer.translate(label)})
	return entries


## 各特效預設持續秒數。
const DURATIONS := {"hearts": 3.0, "heart_big": 2.6, "vein": 3.2, "flame": 3.0, "confused": 3.0, "sweat": 2.6, "sparkle": 3.0, "flowers": 3.5, "glow": 3.0, "afterimage": 3.0, "sleepy": 8.0, "foam": 3.0, "gloom": 4.0, "cry": 1.6}
## 各特效發射粒子的間隔(秒,密度 1 倍時)。殘影不用時間間隔,用移動距離(見 style 的 trail)。
const SPAWN_EVERY := {"hearts": 0.16, "sweat": 0.35, "sparkle": 0.2, "flowers": 0.3, "sleepy": 2.2, "foam": 0.1, "cry": 0.26}
## 會發射複數粒子(密度設定有意義)的特效。
const MULTI := ["hearts", "sweat", "sparkle", "flowers", "sleepy", "foam", "cry"]
## 自動觸發(鏡片名稱 → 特效代號清單)。
const LENS_EFFECTS := {"開心": ["hearts", "sparkle"], "生氣": ["vein"], "疲憊": ["sweat", "sleepy"], "悲傷": ["gloom", "cry"], "悠哉": ["flowers"]}
## 自動觸發的「下一階段」:鏡片名稱 → [[特效代號, 幾秒後]]。生氣先冒青筋,還在生氣(狀態鏡還在)3 秒後才升級成火苗。
const LENS_ESCALATION := {"生氣": [["flame", 3.0]]}
const MAX_PARTICLES := 140
## 所有發射類特效加起來每秒最多發射幾顆(光敏防護 + 效能;粒子都很小,不是大面積閃爍)。
const MAX_SPAWN_PER_SECOND := 20.0

## 顏色模式:solid 單色純色、duo 雙色純色(每顆粒子隨機挑兩色之一)、gradient 單色漸層(由淡到濃)、duo_gradient 雙色漸層(隨壽命由第一色漸變到第二色)、rainbow 彩虹色調。
const COLOR_MODES: Array[String] = ["solid", "duo", "gradient", "duo_gradient", "rainbow"]
const COLOR_MODE_LABELS: Array[String] = ["單色", "雙色", "單色漸層", "雙色漸層", "彩虹色調"]
## 彩虹:色相每秒轉的圈數(0.12 = 約 8 秒一圈)、飽和度上限、亮度。這三個不開放調整(光敏防護)。
const RAINBOW_HUE_SPEED := 0.12
const RAINBOW_SATURATION := 0.5
const RAINBOW_VALUE := 1.0
## 客製化數值範圍。
const SIZE_RANGE := Vector2(0.4, 2.5)
const DENSITY_RANGE := Vector2(0.25, 3.0)
const HOLD_RANGE := Vector2(0.1, 1.5)
const TRAIL_RANGE := Vector2(0.05, 1.0)
## 生成點離角色的遠近倍率(1.0 = 預設距離);只對「在角色身邊某個位置生成粒子」的特效有意義,見 SPAWN_RANGE_UNUSED。
const RANGE_RANGE := Vector2(0.3, 3.0)
## 沒有「生成點」這個概念的特效:憂愁是持續的一圈光暈(半徑跟著「大小」調,不是生成點)、全身發光是貼在角色身上的著色器、移動殘影生成點就是角色本人的位置。這三個不開放調「範圍」。
const RANGE_UNUSED: Array[String] = ["gloom", "glow", "afterimage"]
## 各特效的預設外觀:mode + 兩個顏色。size / density / hold / trail 預設都是 1 / 1 / 0.45 / 0.12。
const DEFAULT_STYLES := {
	"hearts": {"mode": "solid", "c1": "#ff6b94", "c2": "#ffbfd9"},
	"heart_big": {"mode": "solid", "c1": "#ff4d73", "c2": "#ff99b3"},
	"vein": {"mode": "solid", "c1": "#e02626", "c2": "#ff7070"},
	"flame": {"mode": "duo", "c1": "#ff6b14", "c2": "#ffd940"},
	"confused": {"mode": "solid", "c1": "#806bd9", "c2": "#bfb3ff"},
	"sweat": {"mode": "solid", "c1": "#8cd1ff", "c2": "#ccf2ff"},
	"sparkle": {"mode": "solid", "c1": "#ffe64d", "c2": "#ffffcc"},
	"flowers": {"mode": "duo", "c1": "#ff9ec7", "c2": "#ffe666"},
	"glow": {"mode": "solid", "c1": "#fff28c", "c2": "#ffbf66"},
	"afterimage": {"mode": "solid", "c1": "#b3d9ff", "c2": "#ffccdd"},
	"sleepy": {"mode": "solid", "c1": "#cce6ff", "c2": "#ffffff"},
	"foam": {"mode": "solid", "c1": "#ffffff", "c2": "#e4f4ff"},
	"gloom": {"mode": "solid", "c1": "#5b8cff", "c2": "#b8d0ff"},
	"cry": {"mode": "solid", "c1": "#8fd0ff", "c2": "#d6f0ff"},
}
const DEFAULT_HOLD := 0.45
const DEFAULT_TRAIL := 0.12

## 全部特效的總開關(profile 存)與「自動觸發」開關。
var enabled := true
var auto_enabled := true
## 每個特效的客製化(只存和預設不同的):代號 → {mode, c1, c2, size, density, hold, trail, range}。取用請走 style_of()。
var styles: Dictionary = {}

var _pet: Node
var _back: Node2D
var _running: Dictionary = {}       # 代號 → {left, total, spawn_left}
var _particles: Array[Dictionary] = []
var _ghosts: Array[Dictionary] = []
var _last_ghost_position := Vector2.INF
var _spawn_budget := 0.0
## 排定要升級播放的特效:{key, left, lens}(狀態鏡還在才播)。
var _scheduled: Array[Dictionary] = []
var _front: Node2D
var _glow_layer: Node2D
var _glow_material: ShaderMaterial
## 全身發光用的「角色剪影」貼圖(四周補透明邊讓光暈有地方擴散),依畫面貼圖快取。
var _glow_textures: Dictionary = {}
const GLOW_PAD := 44
const GLOW_SHADER := "shader_type canvas_item;
uniform vec4 glow_color : source_color = vec4(1.0, 0.95, 0.55, 1.0);
uniform float radius_px = 28.0;
uniform float strength = 1.0;
uniform vec2 pixel_size = vec2(0.01, 0.01);
void fragment() {
	float total = 0.0;
	float weight_sum = 0.0;
	for (int ring = 1; ring <= 5; ring++) {
		float fr = float(ring) / 5.0;
		float weight = 1.0 - fr * 0.75;
		for (int k = 0; k < 14; k++) {
			float angle = 6.2831853 * float(k) / 14.0 + fr * 0.9;
			vec2 offset = vec2(cos(angle), sin(angle)) * radius_px * fr * pixel_size;
			total += texture(TEXTURE, UV + offset).a * weight;
			weight_sum += weight;
		}
	}
	float own = texture(TEXTURE, UV).a;
	float glow = clamp((total / weight_sum) * 2.4 + own * 0.6, 0.0, 1.0);
	COLOR = vec4(glow_color.rgb, glow * glow_color.a * strength);
}"

## 一個繪製圖層:只是把繪製工作轉給 PetEffects。front = 粒子(畫在角色上面)、back = 殘影(角色下面)、glow = 全身發光的剪影光暈(最下面,有模糊著色器)。
class Layer extends Node2D:
	var owner_effects: PetEffects
	var kind := "front"

	func _draw() -> void:
		if owner_effects != null:
			owner_effects._draw_layer(self, kind)


func setup(pet: Node) -> void:
	_pet = pet
	add_to_group("Cutout")
	# 圖層順序(相對角色):發光 −2、殘影 −1(都在角色下面)、粒子 +20(在角色上面)。
	_glow_layer = _make_layer("glow", -2)
	_glow_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = GLOW_SHADER
	_glow_material.shader = shader
	_glow_layer.material = _glow_material
	_back = _make_layer("back", -1)
	_front = _make_layer("front", 20)
	pet.active_state_lens_changed.connect(_on_lens_changed)


func _make_layer(kind: String, z: int) -> Node2D:
	var layer := Layer.new()
	layer.owner_effects = self
	layer.kind = kind
	layer.z_index = z
	add_child(layer)
	return layer


func _redraw_layers() -> void:
	_front.queue_redraw()
	_back.queue_redraw()
	_glow_layer.queue_redraw()



## 特效名稱轉內部代號(不認得回空字串)。
static func resolve(effect_name: String) -> String:
	return str(NAMES.get(effect_name.strip_edges(), NAMES.get(effect_name.strip_edges().to_lower(), "")))


## 內部代號對應的中文名稱(CATALOG 裡的那個)。
static func label_of(key: String) -> String:
	for label in CATALOG:
		if resolve(label) == key:
			return label
	return key


# --- 客製化 ---

## 這個特效目前的外觀(預設 + 使用者改過的),值都已經夾在合法範圍:{mode, c1(Color), c2(Color), size, density, hold, trail, range}。
func style_of(key: String) -> Dictionary:
	var base: Dictionary = DEFAULT_STYLES.get(key, DEFAULT_STYLES["hearts"])
	var override: Dictionary = styles.get(key, {})
	var mode := str(override.get("mode", base["mode"]))
	return {
		"mode": mode if COLOR_MODES.has(mode) else str(base["mode"]),
		"c1": _color_of(override.get("c1"), Color.html(str(base["c1"]))),
		"c2": _color_of(override.get("c2"), Color.html(str(base["c2"]))),
		"size": clampf(_number_of(override.get("size"), 1.0), SIZE_RANGE.x, SIZE_RANGE.y),
		"density": clampf(_number_of(override.get("density"), 1.0), DENSITY_RANGE.x, DENSITY_RANGE.y),
		"hold": clampf(_number_of(override.get("hold"), DEFAULT_HOLD), HOLD_RANGE.x, HOLD_RANGE.y),
		"trail": clampf(_number_of(override.get("trail"), DEFAULT_TRAIL), TRAIL_RANGE.x, TRAIL_RANGE.y),
		"range": clampf(_number_of(override.get("range"), 1.0), RANGE_RANGE.x, RANGE_RANGE.y),
	}


## 改某個特效的外觀(只傳要改的欄位);顏色可以傳 Color 或 "#rrggbb"。
func set_style(key: String, changes: Dictionary) -> void:
	if not DEFAULT_STYLES.has(key):
		return
	var entry: Dictionary = (styles.get(key, {}) as Dictionary).duplicate()
	for field: String in changes:
		if field in ["mode", "c1", "c2", "size", "density", "hold", "trail", "range"]:
			entry[field] = changes[field]
	styles[key] = entry
	var merged := style_of(key)
	styles[key] = {"mode": merged["mode"], "c1": (merged["c1"] as Color).to_html(false), "c2": (merged["c2"] as Color).to_html(false),
			"size": merged["size"], "density": merged["density"], "hold": merged["hold"], "trail": merged["trail"], "range": merged["range"]}
	if _is_default_style(key):
		styles.erase(key)


func reset_style(key: String) -> void:
	styles.erase(key)


func _is_default_style(key: String) -> bool:
	var base: Dictionary = DEFAULT_STYLES[key]
	var entry: Dictionary = styles.get(key, {})
	return str(entry.get("mode")) == str(base["mode"]) and str(entry.get("c1")).to_lower() == str(base["c1"]).to_lower() and str(entry.get("c2")).to_lower() == str(base["c2"]).to_lower() \
			and is_equal_approx(float(entry.get("size", 1.0)), 1.0) and is_equal_approx(float(entry.get("density", 1.0)), 1.0) \
			and is_equal_approx(float(entry.get("hold", DEFAULT_HOLD)), DEFAULT_HOLD) and is_equal_approx(float(entry.get("trail", DEFAULT_TRAIL)), DEFAULT_TRAIL) \
			and is_equal_approx(float(entry.get("range", 1.0)), 1.0)


## 持續殘影(企劃書第五階段第 6 項):不用每次都播「移動殘影」,可以讓它在移動時一直開著。
##  - trail_mode(角色設定「移動時自動殘影」,存檔):off 關閉 / run 奔跑時(run 開關開著,或狀態鏡讓它奔跑)/ move 只要在移動。
##  - 積木「開啟 / 關閉殘影」(set_trail_forced):不管上面的設定,一直開著直到關閉;被打斷時比照長期狀態回正。
## 殘影本身還是靠移動距離取樣(停下來就不留),樣式(顏色模式、拖尾、停留時間)用「移動殘影」的特效外觀設定。
const TRAIL_MODES: Array[String] = ["off", "run", "move"]
const TRAIL_LABELS := {"off": "關閉", "run": "奔跑時", "move": "只要在移動"}
var trail_mode := "off"
var _trail_forced := false


func set_trail_forced(on: bool) -> void:
	_trail_forced = on


func is_trail_forced() -> bool:
	return _trail_forced


func set_trail_mode(mode: String) -> void:
	trail_mode = mode if TRAIL_MODES.has(mode) else "off"


## 這一刻該不該讓殘影開著。
func trail_wanted() -> bool:
	if not enabled or _pet == null:
		return false
	if _trail_forced:
		return true
	match trail_mode:
		"run":
			return _pet.is_running()
		"move":
			return true
	return false


## 想要殘影時讓 afterimage 一直續命(沒在跑就開始),不想要就讓它自然結束。
func _tick_trail() -> void:
	if not trail_wanted():
		return
	if _running.has("afterimage"):
		_running["afterimage"]["left"] = maxf(float(_running["afterimage"]["left"]), 0.6)
	else:
		play("afterimage", 1.0)


## 連帶觸發特效:使用者互動時(不用寫積木)自動播的特效。鍵 = 互動種類,值 = 特效名稱(空白 = 不播)。
const LINK_KEYS: Array[String] = ["click", "pet", "drag", "follow"]
const LINK_LABELS := {"click": "被點擊", "pet": "被觸摸", "drag": "被拖曳(抓起來的瞬間)", "follow": "開始跟隨滑鼠"}
var interaction_links := {"click": "", "pet": "", "drag": "", "follow": ""}


## 互動發生時呼叫;有設定連帶特效(而且特效總開關開著)就播。回傳有沒有播。
func play_interaction(kind: String) -> bool:
	if not enabled:
		return false
	var linked := str(interaction_links.get(kind, ""))
	return linked != "" and play(linked)


func set_interaction_link(kind: String, effect_name: String) -> void:
	if LINK_KEYS.has(kind):
		interaction_links[kind] = resolve(effect_name)   # 存英文代號


## 存檔用:只含有設定的連帶特效。
func links_to_dict() -> Dictionary:
	var result := {}
	for kind: String in LINK_KEYS:
		if str(interaction_links[kind]) != "":
			result[kind] = interaction_links[kind]
	return result


func apply_links(data: Variant) -> void:
	for kind: String in LINK_KEYS:
		interaction_links[kind] = ""
	if data is Dictionary:
		for kind: Variant in data:
			set_interaction_link(str(kind), str(data[kind]))


## 存檔用:只含和預設不同的特效。
func styles_to_dict() -> Dictionary:
	return styles.duplicate(true)


## 讀檔:逐欄驗證,壞的欄位用預設,不認得的特效丟掉。
func apply_styles(data: Variant) -> void:
	styles.clear()
	if not data is Dictionary:
		return
	for key: Variant in data:
		if DEFAULT_STYLES.has(str(key)) and data[key] is Dictionary:
			set_style(str(key), data[key])


static func _color_of(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String and Color.html_is_valid(value):
		var parsed := Color.html(value)
		parsed.a = 1.0
		return parsed
	return fallback


static func _number_of(value: Variant, fallback: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return fallback


## 依外觀設定算一顆粒子在壽命進度 t(0~1)的基本顏色(不含淡出的透明度)。pick / hue 是這顆粒子出生時抽的 0~1 隨機數。
static func color_at(style: Dictionary, t: float, pick: float, hue: float, time_seconds: float) -> Color:
	var c1: Color = style["c1"]
	var c2: Color = style["c2"]
	match str(style["mode"]):
		"duo":
			return c1 if pick < 0.5 else c2
		"gradient":
			return c1.lerp(Color.WHITE, 0.65).lerp(c1, smoothstep(0.0, 1.0, t))
		"duo_gradient":
			return c1.lerp(c2, smoothstep(0.0, 1.0, t))
		"rainbow":
			return Color.from_hsv(fposmod(hue + time_seconds * RAINBOW_HUE_SPEED, 1.0), RAINBOW_SATURATION, RAINBOW_VALUE)
	return c1


## 火苗的兩層顏色(外焰、內焰):雙色模式外焰用第一色、內焰用第二色;其他模式內焰是外焰調亮。
static func flame_colors(style: Dictionary, t: float, hue: float, time_seconds: float) -> Array[Color]:
	var outer := color_at(style, t, 0.0, hue, time_seconds)
	var inner: Color = (style["c2"] as Color) if str(style["mode"]) in ["duo", "duo_gradient"] else outer.lightened(0.5)
	return [outer, inner]


# --- 播放 ---

## 播放一個特效;seconds < 0 用預設長度。回傳有沒有認得(沒開特效也回傳 true,只是不畫)。
func play(effect_name: String, seconds := -1.0) -> bool:
	var key := resolve(effect_name)
	if key == "":
		return false
	if not enabled:
		return true
	var total := seconds if seconds > 0.0 else float(DURATIONS[key])
	_running[key] = {"left": total, "total": total, "spawn_left": 0.0}
	if key == "heart_big":
		_spawn_big_heart(total)
	elif key == "flame":
		_spawn_flame(total)
	elif key == "vein":
		_spawn_vein(total)
	elif key == "confused":
		_spawn_confused(total)
	var state := get_node_or_null("/root/DesktopShellState")
	if state != null:
		state.effect_played.emit(_pet, key)
	return true


func stop_all() -> void:
	_trail_forced = false
	_running.clear()
	_particles.clear()
	_ghosts.clear()
	_last_ghost_position = Vector2.INF
	_scheduled.clear()
	_redraw_layers()


func is_playing(key: String) -> bool:
	return _running.has(key)


func particle_count() -> int:
	return _particles.size() + _ghosts.size()


func _on_lens_changed(lens_name: String) -> void:
	if not auto_enabled or not LENS_EFFECTS.has(lens_name):
		return
	for key: String in LENS_EFFECTS[lens_name]:
		play(key)
	for stage: Array in LENS_ESCALATION.get(lens_name, []):
		_scheduled.append({"key": str(stage[0]), "left": float(stage[1]), "lens": lens_name})


# --- 尺寸與位置 ---

## 角色本體高度(像素,已乘角色縮放);量不到就用 96。
func body_height() -> float:
	var height: float = _pet.effective_hitbox_size().y * _pet.params.scale_multiplier
	return height if height > 8.0 else 96.0


## 角色本體寬度(像素,已乘角色縮放);量不到就用 0.6 個身高。
func body_width() -> float:
	var width: float = _pet.effective_hitbox_size().x * _pet.params.scale_multiplier
	return width if width > 8.0 else body_height() * 0.6


## 頭頂中央(直立身體座標:以腳底為原點,攀爬時特效生成會再依 Pet.body_pose_transform() 轉過去)。
func head_point() -> Vector2:
	var offset: Vector2 = _pet.effective_hitbox_offset() * _pet.params.scale_multiplier
	return Vector2(offset.x, offset.y - body_height())


func body_center() -> Vector2:
	var offset: Vector2 = _pet.effective_hitbox_offset() * _pet.params.scale_multiplier
	return Vector2(offset.x, offset.y - body_height() * 0.5)


# --- 更新 ---

func _process(delta: float) -> void:
	if _pet == null:
		return
	_tick_trail()
	_auto_sleepy()
	_auto_sad(delta)
	_run_scheduled(delta)
	_update_glow_material()
	_spawn_budget = minf(_spawn_budget + MAX_SPAWN_PER_SECOND * delta, 3.0)
	for key: String in _running.keys():
		var entry: Dictionary = _running[key]
		entry["left"] = float(entry["left"]) - delta
		if float(entry["left"]) <= 0.0:
			_running.erase(key)
			continue
		if SPAWN_EVERY.has(key):
			entry["spawn_left"] = float(entry["spawn_left"]) - delta
			if float(entry["spawn_left"]) <= 0.0:
				entry["spawn_left"] = float(SPAWN_EVERY[key]) / float(style_of(key)["density"])
				if _spawn_budget >= 1.0:
					_spawn_budget -= float(_spawn(key))
		elif key == "afterimage":
			_spawn_ghost()
	for particle in _particles:
		particle["age"] = float(particle["age"]) + delta
	for ghost in _ghosts:
		ghost["age"] = float(ghost["age"]) + delta
	_particles = _particles.filter(func(p: Dictionary) -> bool: return float(p["age"]) < float(p["life"]))
	_ghosts = _ghosts.filter(func(g: Dictionary) -> bool: return float(g["age"]) < float(g["life"]))
	if _running.is_empty() and _particles.is_empty() and _ghosts.is_empty():
		_last_ghost_position = Vector2.INF
		return
	_redraw_layers()


## 排定的「升級」特效(例如生氣先冒青筋、3 秒後還在生氣才冒火苗)。
func _run_scheduled(delta: float) -> void:
	if _scheduled.is_empty():
		return
	for entry in _scheduled:
		entry["left"] = float(entry["left"]) - delta
	var due := _scheduled.filter(func(e: Dictionary) -> bool: return float(e["left"]) <= 0.0)
	_scheduled = _scheduled.filter(func(e: Dictionary) -> bool: return float(e["left"]) > 0.0)
	for entry in due:
		if auto_enabled and _pet.is_lens_active(str(entry["lens"])):
			play(str(entry["key"]))


## 悲傷狀態鏡生效中:背後一直有淡淡的藍色圓暈(憂愁),每隔幾秒撒一陣小水滴(哭泣)。
var _cry_left := 0.0
var _gloom_auto := false


func _auto_sad(delta: float) -> void:
	if not auto_enabled or not enabled or _pet.entering or not _pet.is_lens_active("悲傷"):
		_cry_left = 0.0
		if _gloom_auto:
			_gloom_auto = false
			_running.erase("gloom")   # 悲傷結束,圓暈跟著收掉
		return
	if not _running.has("gloom"):
		play("gloom", 60.0)   # 悲傷期間一直在(不然每隔幾秒淡出淡入會像在閃)
		_gloom_auto = true
	_cry_left -= delta
	if _cry_left <= 0.0:
		_cry_left = randf_range(8.0, 14.0)
		play("cry")


## 睏倦氣泡的自動觸發:疲憊狀態鏡生效中、或正在站著/坐著休息時,一直有氣泡慢慢飄(睡著時有 Zzz,不放氣泡)。
func _auto_sleepy() -> void:
	if not auto_enabled or not enabled or _running.has("sleepy") or _pet.entering:
		return
	var vitality: PetVitality = _pet.vitality
	var drowsy: bool = _pet.is_lens_active("疲憊") or (vitality != null and vitality.mode in [PetVitality.Mode.STANDING, PetVitality.Mode.RESTING])
	if drowsy and _pet.current_activity() != &"sleep":
		play("sleepy", 6.0)


func _new_particle(key: String, kind: String, life: float, position_now: Vector2, velocity: Vector2, size: float, extra := {}) -> Dictionary:
	var frame: Transform2D = _pet.body_pose_transform()   # 爬牆/天花板時身體轉了:位置與初速從「直立身體座標」轉成桌寵本地座標(重力仍是往下)
	var particle := {"fx": key, "kind": kind, "age": 0.0, "life": life, "pos": frame * position_now, "vel": frame.basis_xform(velocity), "size": size * float(style_of(key)["size"]),
			"phase": randf() * TAU, "pick": randf(), "hue": randf()}
	particle.merge(extra, true)
	return particle


## 發射一批粒子(依特效不同一次 1~2 顆);回傳實際發射幾顆(發射預算要照顆數扣)。
func _spawn(key: String) -> int:
	var h := body_height()
	if _particles.size() >= MAX_PARTICLES:
		return 0
	var before := _particles.size()
	# 生成點離角色多遠的倍率(1.0 = 預設距離,見 style_of 的 "range");只乘在「離身體多遠」的位移量上,粒子本身大小、速度不受影響。
	var reach := float(style_of(key)["range"])
	match key:
		"hearts":
			# 一團愛心:一次噴一兩顆、很小、往上四散。
			for i in (1 if randf() < 0.5 else 2):
				var side := 1.0 if randf() < 0.5 else -1.0
				_particles.append(_new_particle(key, "heart", randf_range(1.5, 2.3), body_center() + Vector2(side * randf_range(0.15, 0.7) * h * 0.6, randf_range(-0.25, 0.3) * h) * reach,
						Vector2(side * randf_range(0.0, 0.12) * h, -h * randf_range(0.2, 0.4)), h * randf_range(0.045, 0.085)))
		"sweat":
			# 汗滴:從額頭兩側甩出去(斜上一點點),然後受重力往下掉;水滴的尾巴順著運動方向拖(見 _draw_drop)。
			var side := 1.0 if randf() < 0.5 else -1.0
			_particles.append(_new_particle(key, "drop", randf_range(0.9, 1.3), head_point() + Vector2(side * h * 0.2, h * 0.08) * reach,
					Vector2(side * h * randf_range(0.18, 0.4), -h * randf_range(0.04, 0.16)), h * randf_range(0.04, 0.065), {"gravity": h * 2.4}))
		"sparkle":
			# 閃光:散在角色四周、離身體遠一點(繞著身體中心的橢圓環,半徑 0.5~1 個身高),很小。
			var angle := randf() * TAU
			var radius := h * randf_range(0.5, 1.0) * reach
			_particles.append(_new_particle(key, "star", randf_range(0.9, 1.4), body_center() + Vector2(cos(angle) * radius * 0.85, sin(angle) * radius),
					Vector2.ZERO, h * randf_range(0.03, 0.07)))
		"flowers":
			# 心花怒放:在角色四周冒出(判定框外面一圈,避開臉),慢慢往外飄。
			var angle_flower := randf() * TAU
			var direction := Vector2(cos(angle_flower), sin(angle_flower))
			var half_box := Vector2(body_width(), h) * 0.5
			var edge := minf(half_box.x / maxf(absf(direction.x), 0.001), half_box.y / maxf(absf(direction.y), 0.001))
			var start_point := body_center() + direction * (edge + h * randf_range(0.1, 0.3) * reach)
			_particles.append(_new_particle(key, "flower", randf_range(1.8, 2.6), start_point,
					direction * h * randf_range(0.05, 0.12) + Vector2(0.0, -h * 0.02), h * randf_range(0.08, 0.13)))
		"foam":
			# 泡沫(洗澡用的白色泡泡,有高光):在角色身上與四周密密地冒出,又小又快,往上飄的同時明顯往左右散開、來回晃。
			for i in 2:
				var foam_angle := randf() * TAU
				var foam_ring := randf_range(0.3, 1.15) * reach
				var foam_at := body_center() + Vector2(cos(foam_angle) * body_width() * 0.6 * foam_ring, sin(foam_angle) * h * 0.6 * foam_ring)
				var drift := randf_range(0.12, 0.32) * (1.0 if randf() < 0.5 else -1.0)
				_particles.append(_new_particle(key, "foam", randf_range(1.1, 1.9), foam_at, Vector2(drift * h, -h * randf_range(0.16, 0.36)), h * randf_range(0.03, 0.08)))
		"cry":
			# 哭泣:從眼睛的高度往兩側撒出零零散散的小水滴(比冒汗更小、更散),然後受重力往下掉。
			for i in 1:
				var cry_side := 1.0 if randf() < 0.5 else -1.0
				_particles.append(_new_particle(key, "drop", randf_range(0.8, 1.25), head_point() + Vector2(cry_side * h * randf_range(0.08, 0.22), h * 0.16) * reach,
						Vector2(cry_side * h * randf_range(0.1, 0.42), -h * randf_range(0.0, 0.14)), h * randf_range(0.02, 0.036), {"gravity": h * 2.6}))
		"sleepy":
			# 睏倦氣泡:一次一兩顆,從頭旁邊慢慢往上飄。
			for i in (1 if randf() < 0.6 else 2):
				var side := 1.0 if randf() < 0.5 else -1.0
				_particles.append(_new_particle(key, "bubble", randf_range(3.0, 4.2), head_point() + Vector2(side * h * randf_range(0.22, 0.4), h * randf_range(0.05, 0.25)) * reach,
						Vector2(side * h * 0.02, -h * randf_range(0.07, 0.13)), h * randf_range(0.028, 0.05)))
	return _particles.size() - before


## 移動殘影:以「走過的距離」決定要不要留一張(trail = 每隔本體高度的幾分之幾留一張,越小拖尾越密),每張停留 hold 秒。
func _spawn_ghost() -> void:
	if _pet.measured_speed() <= 25.0:
		_last_ghost_position = Vector2.INF
		return
	var style := style_of("afterimage")
	var spacing := float(style["trail"]) * body_height()
	var here: Vector2 = _pet.global_position
	if _last_ghost_position != Vector2.INF and here.distance_to(_last_ghost_position) < spacing:
		return
	if _ghosts.size() >= MAX_PARTICLES:
		return
	var snapshot: Dictionary = _pet.visual_snapshot()
	if snapshot.is_empty():
		return
	snapshot["age"] = 0.0
	snapshot["life"] = float(style["hold"])
	snapshot["pick"] = randf()
	snapshot["hue"] = randf()
	_ghosts.append(snapshot)
	_last_ghost_position = here


func _spawn_big_heart(total: float) -> void:
	# 大愛心浮在頭頂「判定框以上」:愛心底部離開判定框上緣約 0.14 個身高(乘上範圍倍率),不會蓋到頭。
	var h := body_height()
	var heart_size := h * 0.3 * float(style_of("heart_big")["size"])
	var reach := float(style_of("heart_big")["range"])
	_particles.append(_new_particle("heart_big", "heart", total, head_point() + Vector2(0.0, -h * 0.14 * reach - heart_size * 0.85), Vector2(0.0, -h * 0.04), h * 0.3, {"pulse": true}))


## 青筋:漫畫裡頭上冒出的紅色 # 形怒筋,畫在頭部左上方(和右上方的鋸齒線不同邊)。
func _spawn_vein(total: float) -> void:
	var h := body_height()
	_particles.append(_new_particle("vein", "vein", total, head_point() + Vector2(-h * 0.22, -h * 0.13) * float(style_of("vein")["range"]), Vector2.ZERO, h * 0.15))


func _spawn_flame(total: float) -> void:
	var h := body_height()
	_particles.append(_new_particle("flame", "flame", total, head_point() + Vector2(0.0, -h * 0.12) * float(style_of("flame")["range"]), Vector2.ZERO, h * 0.2))


## 心煩意亂:三條鋸齒線,畫在頭部右上方的斜角(彡 的感覺,見 _draw_zigzags)。
func _spawn_confused(total: float) -> void:
	var h := body_height()
	_particles.append(_new_particle("confused", "zigzag", total, head_point() + Vector2(h * 0.14, -h * 0.02) * float(style_of("confused")["range"]), Vector2.ZERO, h * 0.3))


# --- 繪製 ---

## 各圖層的繪製(front 粒子、back 殘影、glow 全身發光)。
func _draw_layer(canvas: CanvasItem, kind: String) -> void:
	if _pet == null:
		return
	match kind:
		"front":
			for particle in _particles:
				_draw_particle(canvas, particle)
		"back":
			_draw_gloom(canvas)
			_draw_ghosts(canvas)
		"glow":
			_draw_glow(canvas)


## 憂愁:角色背後一圈淡淡的藍色圓暈(柔邊放射漸層,亮度只有極慢的起伏,不閃爍)。
func _draw_gloom(canvas: CanvasItem) -> void:
	if not _running.has("gloom"):
		return
	var entry: Dictionary = _running["gloom"]
	var t := 1.0 - float(entry["left"]) / float(entry["total"])
	var fade := minf(t * 5.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, t))
	var style := style_of("gloom")
	var pose: Transform2D = _pet.body_pose_transform()
	var center: Vector2 = pose * body_center()
	var radius := maxf(body_height(), body_width()) * 0.95 * float(style["size"])
	var color: Color = color_at(style, 0.5, 0.0, 0.0, 0.0)
	color.a = 0.68 * fade * (0.93 + 0.07 * sin(Time.get_ticks_msec() / 1000.0 * 1.2))
	canvas.draw_texture_rect(PetLights.glow_texture(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)


## 移動殘影(在角色下面):每張是當時那一幀的畫面,依 afterimage 的顏色設定上色、逐漸淡出。
func _draw_ghosts(canvas: CanvasItem) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var ghost_style := style_of("afterimage")
	for ghost in _ghosts:
		var texture: Texture2D = ghost["texture"]
		if texture == null:
			continue
		var t := float(ghost["age"]) / float(ghost["life"])
		var tint := color_at(ghost_style, t, float(ghost["pick"]), float(ghost["hue"]), now)
		var to_local: Transform2D = get_global_transform().affine_inverse() * (ghost["xform"] as Transform2D)
		canvas.draw_set_transform_matrix(to_local)
		var position_offset: Vector2 = ghost["offset"]
		if bool(ghost["centered"]):
			position_offset -= texture.get_size() * 0.5
		canvas.draw_texture(texture, position_offset, Color(tint, 0.45 * (1.0 - t)))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## 全身發光:把角色目前這一幀的形狀(剪影)畫在角色後面,由著色器模糊、往四周放射出去(角色本體蓋在上面)。
func _draw_glow(canvas: CanvasItem) -> void:
	if not _running.has("glow"):
		return
	var snapshot: Dictionary = _pet.visual_snapshot()
	if snapshot.is_empty():
		return
	var padded := _glow_texture_for(snapshot["texture"])
	if padded == null:
		return
	var to_local: Transform2D = get_global_transform().affine_inverse() * (snapshot["xform"] as Transform2D)
	canvas.draw_set_transform_matrix(to_local)
	var top_left: Vector2 = snapshot["offset"]
	if bool(snapshot["centered"]):
		top_left -= (snapshot["texture"] as Texture2D).get_size() * 0.5
	canvas.draw_texture(padded, top_left - Vector2(GLOW_PAD, GLOW_PAD), Color.WHITE)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## 每影格把發光的顏色、強度、半徑、貼圖像素大小交給著色器。
func _update_glow_material() -> void:
	if _glow_material == null or not _running.has("glow"):
		return
	var entry: Dictionary = _running["glow"]
	var t := 1.0 - float(entry["left"]) / float(entry["total"])
	var style := style_of("glow")
	var fade := minf(t * 5.0, 1.0) * (1.0 - smoothstep(0.8, 1.0, t))
	var pulse := 0.85 + 0.15 * sin(t * TAU * 2.0)
	_glow_material.set_shader_parameter("glow_color", color_at(style, t, 0.0, 0.0, Time.get_ticks_msec() / 1000.0))
	_glow_material.set_shader_parameter("strength", fade * pulse)
	_glow_material.set_shader_parameter("radius_px", float(GLOW_PAD) * 0.62 * float(style["size"]))
	var snapshot: Dictionary = _pet.visual_snapshot()
	if not snapshot.is_empty():
		var padded := _glow_texture_for(snapshot["texture"])
		if padded != null:
			_glow_material.set_shader_parameter("pixel_size", Vector2(1.0 / padded.get_width(), 1.0 / padded.get_height()))


## 這一幀貼圖的「四周補透明邊」版本(光暈要有地方擴散);依貼圖快取,太多就清掉重來。AtlasTexture 的邊界(margin)也算進去,位置才對得上。
func _glow_texture_for(texture: Texture2D) -> ImageTexture:
	if texture == null:
		return null
	var cached: Variant = _glow_textures.get(texture.get_instance_id())
	if cached is ImageTexture:
		return cached
	var source := texture.get_image()
	if source == null or source.is_empty():
		return null
	source.convert(Image.FORMAT_RGBA8)
	var full := Vector2i(texture.get_size())
	var inner_offset := Vector2i.ZERO
	if texture is AtlasTexture:
		inner_offset = Vector2i((texture as AtlasTexture).margin.position)
	var padded := Image.create(full.x + GLOW_PAD * 2, full.y + GLOW_PAD * 2, false, Image.FORMAT_RGBA8)
	padded.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i(GLOW_PAD, GLOW_PAD) + inner_offset)
	if _glow_textures.size() > 48:
		_glow_textures.clear()
	var result := ImageTexture.create_from_image(padded)
	_glow_textures[texture.get_instance_id()] = result
	return result

func _draw_particle(canvas: CanvasItem, p: Dictionary) -> void:
	var t := float(p["age"]) / float(p["life"])
	var age := float(p["age"])
	var size := float(p["size"])
	var key := str(p["fx"])
	var style := style_of(key)
	var now := Time.get_ticks_msec() / 1000.0
	var color := color_at(style, t, float(p["pick"]), float(p["hue"]), now)
	var fade := minf(t * 8.0, 1.0) * (1.0 - smoothstep(0.7, 1.0, t))
	var position_now: Vector2 = p["pos"] + (p["vel"] as Vector2) * age
	if p.has("gravity"):
		position_now.y += 0.5 * float(p["gravity"]) * age * age
	match str(p["kind"]):
		"heart":
			position_now.x += sin(age * 3.0 + float(p["phase"])) * size * 0.4
			var pulse := 1.0 + (0.12 * sin(age * 9.0) if p.has("pulse") else 0.0)
			_draw_heart(canvas, position_now, size * pulse * lerpf(0.6, 1.0, minf(t * 4.0, 1.0)), Color(color, fade))
		"star":
			var twinkle := sin(t * PI)
			_draw_star(canvas, position_now, size * (0.4 + 0.9 * twinkle), Color(color, fade), float(p["phase"]) + age)
		"drop":
			_draw_drop(canvas, position_now, size, Color(color, fade * 0.95), (p["vel"] as Vector2 + Vector2(0.0, float(p["gravity"]) * age)))
		"flower":
			position_now.x += sin(age * 2.5 + float(p["phase"])) * size * 0.8
			_draw_flower(canvas, position_now, size * lerpf(0.5, 1.0, minf(t * 4.0, 1.0)), Color(color, fade), age * 1.5 + float(p["phase"]))
		"flame":
			var colors := flame_colors(style, t, float(p["hue"]), now)
			_draw_flame(canvas, position_now, size, fade, age, float(p["phase"]), colors[0], colors[1])
		"zigzag":
			_draw_zigzags(canvas, position_now, size, Color(color, fade), age, float(p["phase"]))
		"vein":
			_draw_vein(canvas, position_now, size * (1.0 + 0.1 * sin(age * 8.0)) * lerpf(0.6, 1.0, minf(t * 5.0, 1.0)), Color(color, fade))
		"foam":
			position_now.x += sin(age * 4.2 + float(p["phase"])) * size * 0.9
			_draw_foam(canvas, position_now, size * lerpf(0.7, 1.0, minf(t * 4.0, 1.0)), Color(color, fade))
		"bubble":
			position_now.x += sin(age * 1.6 + float(p["phase"])) * size * 0.9
			_draw_bubble(canvas, position_now, size * lerpf(0.8, 1.15, t), Color(color, fade))


## 愛心:兩個圓形的上半 + 圓角的底(底部是一顆小圓,不是尖角,鈍鈍的比較可愛);外圍先畫一圈淡色描邊。size ≈ 半寬。
func _draw_heart(canvas: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	for pass_index in 2:
		var grow := size * 0.09 if pass_index == 0 else 0.0
		var tint := Color(color.lightened(0.4), color.a * 0.9) if pass_index == 0 else color
		for polygon in heart_polygons(center, size, grow):
			canvas.draw_colored_polygon(polygon, tint)


## 愛心的兩塊凸多邊形(左半、右半;各是「上面的圓」與「底部小圓」的凸包),grow 是向外加粗多少(畫描邊用)。底部小圓的半徑夠大,所以底部是圓弧不是尖角。
static func heart_polygons(center: Vector2, size: float, grow := 0.0) -> Array[PackedVector2Array]:
	var lobe_radius := size * 0.54 + grow
	var bottom_radius := size * 0.26 + grow
	var bottom_center := center + Vector2(0.0, size * 0.5)
	var result: Array[PackedVector2Array] = []
	for side in [-1.0, 1.0]:
		var lobe_center: Vector2 = center + Vector2(side * size * 0.5, -size * 0.3)
		var points := PackedVector2Array()
		for i in 18:
			var a := TAU * float(i) / 18.0
			points.append(lobe_center + Vector2(cos(a), sin(a)) * lobe_radius)
			points.append(bottom_center + Vector2(cos(a), sin(a)) * bottom_radius)
		result.append(Geometry2D.convex_hull(points))
	return result

## 四角星(閃光):outer 外半徑,內半徑 = 外的 0.32,rotation 弧度。
func _draw_star(canvas: CanvasItem, center: Vector2, outer: float, color: Color, rotation: float) -> void:
	var points := PackedVector2Array()
	for i in 8:
		var radius := outer if i % 2 == 0 else outer * 0.32
		var a := rotation * 0.4 + TAU * float(i) / 8.0 - PI * 0.5
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	canvas.draw_colored_polygon(points, color)


## 水滴的尾巴方向:順著運動方向往後拖(掉下來時尖端朝上、往旁邊甩時尖端朝內側)。速度太小(幾乎沒動)時尖端朝上。
static func drop_tail_direction(velocity: Vector2) -> Vector2:
	return -velocity.normalized() if velocity.length() > 1.0 else Vector2.UP


## 水滴:圓肚在前、尖端在後(順著運動方向拖尾)。
func _draw_drop(canvas: CanvasItem, center: Vector2, size: float, color: Color, velocity: Vector2) -> void:
	var tail := drop_tail_direction(velocity)
	var side := Vector2(-tail.y, tail.x)
	var tip := center + tail * size * 2.1
	canvas.draw_circle(center, size, color)
	canvas.draw_colored_polygon(PackedVector2Array([center + side * size * 0.95, tip, center - side * size * 0.95]), color)


## 小花:五片花瓣繞著黃色花心。
func _draw_flower(canvas: CanvasItem, center: Vector2, size: float, color: Color, rotation: float) -> void:
	for i in 5:
		var a := rotation + TAU * float(i) / 5.0
		canvas.draw_circle(center + Vector2(cos(a), sin(a)) * size * 0.55, size * 0.42, color)
	canvas.draw_circle(center, size * 0.3, Color(1.0, 0.8, 0.2, color.a))


## 泡沫:白色的圓,淡淡的填色 + 亮一點的外圈,左上一道彎月形高光、右下一個小亮點(像肥皂泡上的反光)。
func _draw_foam(canvas: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	canvas.draw_circle(center, size, Color(color, color.a * 0.28))
	canvas.draw_arc(center, size, 0.0, TAU, 20, Color(color, color.a * 0.9), maxf(size * 0.11, 1.0), true)
	var shine := Color(1.0, 1.0, 1.0, color.a * 0.95)
	canvas.draw_arc(center, size * 0.68, PI * 1.05, PI * 1.55, 12, shine, maxf(size * 0.14, 1.5), true)
	canvas.draw_circle(center + Vector2(size * 0.42, size * 0.38), maxf(size * 0.09, 1.0), Color(shine, shine.a * 0.8))


## 氣泡:半透明的圓加淡淡的邊(不畫反光)。
func _draw_bubble(canvas: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	canvas.draw_circle(center, size, Color(color, color.a * 0.28))
	canvas.draw_arc(center, size, 0.0, TAU, 20, Color(color, color.a * 0.9), maxf(size * 0.16, 1.0), true)


## 火苗:外焰 + 內焰,尖端左右搖晃,旁邊兩顆小火星。
func _draw_flame(canvas: CanvasItem, base: Vector2, size: float, fade: float, age: float, phase: float, outer: Color, inner: Color) -> void:
	var sway := sin(age * 11.0 + phase) * size * 0.18
	_draw_flame_shape(canvas, base, size, size * 1.55, sway, Color(outer, fade))
	_draw_flame_shape(canvas, base + Vector2(0.0, size * 0.05), size * 0.6, size * 0.95, sway * 0.7, Color(inner, fade))
	_draw_flame_shape(canvas, base + Vector2(-size * 0.95, size * 0.1), size * 0.32, size * 0.7, -sway * 0.8, Color(outer, fade * 0.9))
	_draw_flame_shape(canvas, base + Vector2(size * 0.95, size * 0.1), size * 0.32, size * 0.7, sway * 1.1, Color(outer, fade * 0.9))


func _draw_flame_shape(canvas: CanvasItem, base: Vector2, half_width: float, flame_height: float, tip_sway: float, color: Color) -> void:
	var points := PackedVector2Array()
	var steps := 10
	for i in steps + 1:
		var u := float(i) / float(steps)
		points.append(base + Vector2(-half_width * sin(PI * pow(u, 0.6)) + tip_sway * u * u, -flame_height * u))
	for i in range(steps, -1, -1):
		var u := float(i) / float(steps)
		points.append(base + Vector2(half_width * sin(PI * pow(u, 0.6)) + tip_sway * u * u, -flame_height * u))
	canvas.draw_colored_polygon(points, color)


## 三條鋸齒線(彡):從頭部右上方一起往右上斜出,彼此隔開、方向微微放射狀(下面一條偏右、上面一條偏上),整組微微抖動。
func _draw_zigzags(canvas: CanvasItem, origin: Vector2, size: float, color: Color, age: float, phase: float) -> void:
	var width := maxf(size * 0.1, 1.5)
	for points in zigzag_paths(origin, size, age, phase):
		canvas.draw_polyline(points, color, width, true)


## 三條鋸齒線的折線點(畫和測試共用)。起點沿著垂直於主方向的軸排開(間隔 0.42 個 size),方向各差 0.24 弧度往外放射。
static func zigzag_paths(origin: Vector2, size: float, age: float, phase: float) -> Array[PackedVector2Array]:
	var main_direction := Vector2(1.0, -1.0).normalized()
	var result: Array[PackedVector2Array] = []
	for line in 3:
		var slot := float(line - 1)   # -1(右下)、0、+1(左上)
		var direction := main_direction.rotated(-slot * 0.24)
		var across_axis := Vector2(-direction.y, direction.x)
		var start := origin - main_direction.rotated(PI * 0.5) * (slot * size * 0.42)
		var length := size * (1.0 - 0.1 * absf(slot))
		var jitter := sin(age * 14.0 + phase + float(line)) * size * 0.04
		var points := PackedVector2Array()
		var segments := 5
		for i in segments + 1:
			var f := float(i) / float(segments)
			var zig := (size * 0.13 if i % 2 == 0 else -size * 0.13) * (0.4 if i == 0 or i == segments else 1.0)
			points.append(start + direction * length * f + across_axis * (zig + jitter))
		result.append(points)
	return result


## 青筋(╬):四個 L 形的粗線各在一個象限,拐角靠近中心、兩臂往外伸,中間留一個空的十字通道,像漫畫裡的怒筋。size ≈ 中心空隙的一半寬。
func _draw_vein(canvas: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	var width := maxf(size * 0.34, 2.0)
	for path in vein_paths(center, size):
		canvas.draw_polyline(path, color, width, true)
		for point in path:
			canvas.draw_circle(point, width * 0.5, color)   # 圓頭圓角


## 青筋四個 L 形的折線點(畫和測試共用):每個是 [外臂端點, 拐角, 外臂端點],拐角在 (±gap, ±gap),兩臂各長 arm 往外(左右、上下)。
static func vein_paths(center: Vector2, size: float) -> Array[PackedVector2Array]:
	var gap := size * 0.42
	var arm := size * 1.15
	var result: Array[PackedVector2Array] = []
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			result.append(PackedVector2Array([
				center + Vector2(sign_x * gap, sign_y * (gap + arm)),
				center + Vector2(sign_x * gap, sign_y * gap),
				center + Vector2(sign_x * (gap + arm), sign_y * gap)]))
	return result

# --- 穿透形狀 ---

func get_cutout_polygons() -> Array:
	var polygons: Array = []
	for particle in _particles:
		var age := float(particle["age"])
		var size := float(particle["size"])
		var position_now: Vector2 = particle["pos"] + (particle["vel"] as Vector2) * age
		if particle.has("gravity"):
			position_now.y += 0.5 * float(particle["gravity"]) * age * age
		var reach := size * (3.0 if str(particle["kind"]) in ["flame", "zigzag", "vein"] else 2.4)
		polygons.append(DialogueBubble._rect_polygon(Rect2(to_global(position_now - Vector2(reach, reach * 1.4)), Vector2(reach * 2.0, reach * 2.4))))
	if _running.has("gloom"):
		var gloom_reach := maxf(body_height(), body_width()) * 0.95 * float(style_of("gloom")["size"])
		var gloom_center: Vector2 = (_pet.body_pose_transform() as Transform2D) * body_center()
		polygons.append(DialogueBubble._rect_polygon(Rect2(to_global(gloom_center - Vector2(gloom_reach, gloom_reach)), Vector2(gloom_reach, gloom_reach) * 2.0)))
	if _running.has("glow"):
		var h := body_height() * (1.0 + 0.5 * float(style_of("glow")["size"]))
		var glow_center: Vector2 = (_pet.body_pose_transform() as Transform2D) * body_center()
		var glow_reach := h * 0.8
		polygons.append(DialogueBubble._rect_polygon(Rect2(to_global(glow_center - Vector2(glow_reach, glow_reach)), Vector2(glow_reach, glow_reach) * 2.0)))
	for ghost in _ghosts:
		var texture: Texture2D = ghost["texture"]
		if texture != null:
			var xform: Transform2D = ghost["xform"]
			var top_left: Vector2 = ghost["offset"] - (texture.get_size() * 0.5 if bool(ghost["centered"]) else Vector2.ZERO)
			polygons.append(DialogueBubble._rect_polygon(Rect2(xform * top_left, texture.get_size() * xform.get_scale()).abs()))
	return polygons
