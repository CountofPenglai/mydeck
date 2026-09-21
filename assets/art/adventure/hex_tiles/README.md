# 六边形地图格美术 v1

用途：地图背面，羊皮纸纹理、简约、高辨识度类型符号；正面暂用简单占位图。

## 文件与组合

- `parchment_base.png`：内置 image_gen 生成并已复制入库的共用羊皮纸底纹。
- `symbols/*.svg`：代码原生矢量符号，透明底，128×128，保证小尺寸轮廓一致。
- 起点 start、问号 mystery、普通战斗 battle、精英 elite、营地 camp、商店 shop、首领 boss。
- `symbols/high_value.svg`：独立高价值标记，不改变背面类型、不透露真实事件。
- `front_placeholder.svg`：已揭示图格的简易占位图，256×256，非最终正面美术。
- `preview.html`：仅美术检查用，不是游戏界面实现。
- `preview.png`：本机 Godot 实际渲染的组合预览，含 64/96/128 px 辨识检查。

组合方式：一个图格节点将底纹裁剪到顶点朝上的正六边形，再叠加对应符号（约占图格高度 48%）。描边、选中、可达、完成状态由节点负责；不要烘焙进共享纹理。禁止用方形按钮的透明角作为点击区域。

符号与底纹分离，可以保持所有类别完全一致的纸色、尺寸与状态反馈；无需为每个地图格复制独立纹理，但每格必须有独立状态和场景节点。

## 生成方法与完整提示词

底纹使用内置 image_gen；无 CLI/API fallback。符号直接以 SVG 绘制，未以 SVG 替代用户要求的羊皮纸纹理。

```text
Use case: stylized-concept. Generate a NEW production game UI material texture: a square fully opaque seamless close-up of pale warm ivory parchment. This is a close-up crop from the MIDDLE of an infinite sheet, not a paper object. The paper must cover EVERY pixel including all FOUR CORNERS. Uniform, even brightness with extremely subtle tan paper fibers and gentle organic grain. No vignette or shadow at all, no outline or border, no transparent or dark pixels at the edges, no rounded shape, no isolated sheet, no text, no symbols, no objects. Low contrast and light enough for dark UI symbols over it. Minimalist parchment texture, perfectly flat orthographic scan, same pale ivory color all the way from center to edge.
```

验收：在 64、96、128 像素图格高度检查；类型不只靠颜色区分。首领为冠骷髅，精英为战盔，普通战斗为双剑；问号必须保持未知类型。

已验证：9 个 SVG 经 xmllint 校验；Godot 4.7.2 Compatibility 渲染预览成功，退出码 0。预览不属于已完成的游戏地图界面。生成原图保留在工具输出目录，项目使用独立副本。

## 黑色笔触边框

`brush_border.png` 为内置 image_gen 生成的透明 PNG 独立叠加层；`brush_preview.png` 为 Godot 实际组合预览。中心与角落 alpha 均为 0；纸纹和类型符号不烘焙进边框。边框在正方形中的六边形高度约占 92%，绘制时叠加正方形尺寸为图格高度 / 0.92。游戏交互仍按规则六边形判断，不依赖笔触透明度。

完整生成提示词：

```text
Use case: stylized-concept. Asset type: transparent game UI overlay, a single hexagonal tile border. Draw ONLY the border of a precisely regular pointy-top hexagon in black Chinese calligraphy paintbrush ink. Six straight sides, top and bottom vertices centered, vertical left and right sides, height 92% of square canvas and width 79.67%; vertices normalized at (0.50,0.04),(0.8984,0.27),(0.8984,0.73),(0.50,0.96),(0.1016,0.73),(0.1016,0.27). Center and exterior must be genuinely fully transparent, no paper background, no white fill. Border medium thin, about 1.5% of canvas width: expressive controlled hand-painted sumi ink, subtle dry bristle breakup and natural tapered joins, restrained black irregular edges but clear hex geometry. Center empty for an existing parchment tile and type symbol. No text, no icons, no shadow, no color, no decorative flourishes, no extra shapes. Production isolated RGBA art asset, not a mockup. Black strokes only with alpha.
```
