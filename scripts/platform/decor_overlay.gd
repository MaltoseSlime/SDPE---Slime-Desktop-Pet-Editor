class_name DecorOverlay
extends Node
## 「裝飾層」:一個和主視窗蓋住同一個螢幕、透明、滑鼠完全穿透(連別的程式也穿透,見 ClickThrough)的視窗,
## 給螢火蟲、之後的家具這類「只是好看、不該擋住使用者點擊後面內容」的東西畫在上面。
## 主視窗靠穿透多邊形決定可見與可點的範圍(兩者是同一個形狀),放在主視窗裡的東西一定會擋到點擊,所以這類東西改放這裡。
##
## 用法:DecorOverlay.instance(某個節點) 取得(沒有畫面或不是 Windows 回 null,呼叫端就退回畫在主視窗的舊做法);
## 內容節點加在 canvas 底下(座標 = 主視窗座標),用 set_wanted(自己, 有沒有東西要顯示) 告訴它;usable 為 true 才代表穿透已經生效(之前視窗是 1×1 像素)。
## 視窗建立後就一直開著:hide() 再 show() 會重建原生視窗、穿透樣式就沒了。沒人要顯示時縮成 1×1。
## 順序:這個視窗晚於主視窗建立,原本會蓋在桌寵上面;穿透生效後 keep_behind_main() 把主視窗重新拉到它前面(關掉再打開置頂旗標),
## 所以裝飾在主視窗裡所有東西(桌寵、氣泡、家具…)後面;浮動視窗是之後才開的,仍在最上面。

signal usable_changed(is_usable: bool)

const NODE_NAME := "DecorOverlay"
## 套用穿透最多等幾秒(PowerShell 第一次要編一小段 C#,約 1~2 秒);超過就當失敗,呼叫端維持舊做法。
const APPLY_TIMEOUT := 25.0
const SYNC_INTERVAL := 1.0

var window: Window
## 內容都加在這個節點底下。
var canvas: Node2D
var usable := false
var failed := false
var _job := {}
var _job_age := 0.0
var _wanted := {}
var _sync_left := 0.0


## 取得(必要時建立)全域唯一的裝飾層;無頭、非 Windows 回 null。
static func instance(from: Node) -> DecorOverlay:
	if DisplayServer.get_name() == "headless" or OS.get_name() != "Windows" or from == null or not from.is_inside_tree():
		return null
	var root := from.get_tree().root
	var existing := root.get_node_or_null(NODE_NAME) as DecorOverlay
	if existing != null:
		return existing
	var overlay := DecorOverlay.new()
	overlay.name = NODE_NAME
	root.add_child.call_deferred(overlay)
	return overlay


func _ready() -> void:
	var main := get_window()
	window = Window.new()
	window.name = "DecorWindow"
	window.set_meta("click_through", true)   # DesktopShell 不把它當成「蓋在桌寵上面的視窗」
	window.transparent = true
	window.transparent_bg = true
	window.borderless = true
	window.unfocusable = true
	window.always_on_top = true
	window.exclusive = false
	window.sharp_corners = true
	window.position = main.position
	window.size = Vector2i(1, 1)
	add_child(window)
	canvas = Node2D.new()
	canvas.name = "Canvas"
	window.add_child(canvas)
	_job = ClickThrough.start(window)
	if _job.is_empty():
		_fail()


## 某個使用者(通常是自己)要不要顯示裝飾;有任何一個要就把視窗放大成整個螢幕。
func set_wanted(who: Object, wanted: bool) -> void:
	if wanted:
		_wanted[who.get_instance_id()] = true
	else:
		_wanted.erase(who.get_instance_id())
	_apply_size()


func is_wanted() -> bool:
	return not _wanted.is_empty()


func _process(delta: float) -> void:
	if not _job.is_empty():
		_job_age += delta
		var result: Variant = ClickThrough.poll(_job)
		if result == true:
			_job = {}
			usable = true
			keep_behind_main()
			_apply_size()
			usable_changed.emit(true)
		elif result == false or _job_age > APPLY_TIMEOUT:
			_job = {}
			_fail()
	if usable and is_wanted():
		_sync_left -= delta
		if _sync_left <= 0.0:
			_sync_left = SYNC_INTERVAL
			_apply_size()


## 把主視窗重新排到裝飾層前面:兩個都是置頂視窗,誰最後被設成置頂誰在上面。主視窗被重設位置(緊急召回)後也要再叫一次。
func keep_behind_main() -> void:
	var main := get_window()
	main.always_on_top = false
	main.always_on_top = true


func _fail() -> void:
	failed = true
	if usable:
		usable = false
		usable_changed.emit(false)
	window.size = Vector2i(1, 1)


func _apply_size() -> void:
	if window == null:
		return
	var main := get_window()
	var target := main.size if (usable and is_wanted()) else Vector2i(1, 1)
	if window.position != main.position:
		window.position = main.position
	if window.size != target:
		window.size = target
