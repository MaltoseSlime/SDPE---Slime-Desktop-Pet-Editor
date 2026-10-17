class_name SharpPixel
extends RefCounted
## 像素風桌寵放大成非整數倍(1.5 倍、素材自帶倍率 × 使用者倍率…)時的「清晰像素」取樣(2026-10-16 使用者回報 1.5/2 倍看得到拉伸錯位)。
## 最近點取樣在非整數倍時,每個原圖像素在螢幕上有的佔 1 格、有的佔 2 格,看起來粗細不一;這裡改成每個像素內部照樣是純色,
## 只在像素與像素的交界處做約 1 個螢幕像素寬的混色,所有像素大小一致、邊緣不糊。整數倍(含 1 倍)最近點本來就均勻,不套用。
## 節點本身維持最近點取樣,著色器自己取四個像素中心做預乘 alpha 的雙線性混合(透明邊不會混出黑邊);取樣範圍限制在
## 這一幀的區域內(AtlasTexture 的 region),不會混到原圖裡被裁掉的部分。光照照常(沒有覆寫 light())。

const SHADER := """
shader_type canvas_item;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

vec4 premul(vec4 c) {
	return vec4(c.rgb * c.a, c.a);
}

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 px = UV * size;
	vec2 seam = floor(px + 0.5);
	vec2 fw = max(fwidth(px), vec2(0.0001));
	px = seam + clamp((px - seam) / fw, -0.5, 0.5);
	vec2 r0 = REGION_RECT.xy * size;
	vec2 r1 = (REGION_RECT.xy + REGION_RECT.zw) * size;
	vec2 lo = round(min(r0, r1));   // 區域邊界本來就在整數像素上(傳進來是半精度,四捨五入回去)
	vec2 hi = round(max(r0, r1)) - 1.0;
	vec2 p = px - 0.5;
	vec2 i = floor(p);
	vec2 f = p - i;
	// 內建的 TEXTURE 不能當參數傳進自訂函式,四個像素中心直接在這裡取
	vec2 a = (clamp(i, lo, hi) + 0.5) / size;
	vec2 b = (clamp(i + 1.0, lo, hi) + 0.5) / size;
	vec4 c = mix(mix(premul(texture(TEXTURE, a)), premul(texture(TEXTURE, vec2(b.x, a.y))), f.x),
			mix(premul(texture(TEXTURE, vec2(a.x, b.y))), premul(texture(TEXTURE, b)), f.x), f.y);
	COLOR = (c.a > 0.0 ? vec4(c.rgb / c.a, c.a) : vec4(0.0)) * tint;
}
"""

static var _material: ShaderMaterial


## 所有像素風桌寵共用同一份材質(沒有參數,不用每隻各一份)。
static func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = shader
	return _material


## 道具、家具共用(2026-10-18 使用者要求跟桌寵一樣):smooth = 大張圖(平滑取樣,同 Pet.set_smooth_scaling 的判斷);
## 像素風用最近點,顯示倍率不是整數倍、而且開關開著時套清晰像素材質。
static func apply_to(node: CanvasItem, smooth: bool, enabled: bool, display_scale: float) -> void:
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if smooth else CanvasItem.TEXTURE_FILTER_NEAREST
	node.material = material() if enabled and not smooth and wanted(display_scale) else null


## 素材包讀進來的 SpriteFrames 是不是大張圖(平滑取樣):PropLibrary / FurnitureLibrary.load_sprite 記在 meta "smooth"。
static func frames_smooth(frames: SpriteFrames) -> bool:
	return frames != null and bool(frames.get_meta("smooth", false))


## 單張貼圖(道具的簡單版貼圖):跟素材包同一個預設判斷,高度超過 200 像素算大張圖。
static func texture_smooth(texture: Texture2D) -> bool:
	return texture != null and texture.get_height() > 200


## 這個顯示倍率需不需要清晰像素取樣:整數倍(誤差 1% 內)用最近點就好。
static func wanted(display_scale: float) -> bool:
	var s := absf(display_scale)
	return s > 0.0 and absf(s - roundf(s)) > 0.01
