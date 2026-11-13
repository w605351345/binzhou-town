# AI 生图能力说明

《宾州小镇》项目已具备可用的 AI 生图能力,用于产出**美术风格样板、概念图、场景参考**,
配合《视觉与平台升级设计》阶段 0 的风格统一工作。

## 一、能力来源与选型

本机 `api.openai.com` 不可达、也没有 `OPENAI_API_KEY`,所以内置 `image_gen` 工具不可用。
但 Codex 配置里已有的 **MiniMax provider key 可以直接调用生图接口**(`image-01`),
因此走 MiniMax 官方 HTTP 接口,无需额外申请 key。

已实测:
- `https://api.minimax.cn/v1/image_generation` 鉴权通过、路由正常
- `model: image-01`,`response_format` 支持 `base64` 与 `url`
- 1024×1024 单张约 15–20 秒

> 若将来拿到 `OPENAI_API_KEY`,可直接改用官方 imagegen skill 的 CLI 回退路径
> (`~/.codex/skills/.system/imagegen/scripts/image_gen.py`),产线更稳。

## 二、工具:`tools/ai_imagegen.py`

纯标准库实现(PNG 转换依赖 macOS 自带 `sips`,`--no-png` 可跳过)。

```bash
# 单张(内置风格预设)
python3 tools/ai_imagegen.py --style farm \
  --prompt "秋收后的黑土地农田,远处有木栅栏和低矮的土房" \
  --out assets/art/farm.png --aspect-ratio 16:9 --size 512x288

# 多候选(挑风格用)
python3 tools/ai_imagegen.py --style character --prompt "张晓芳" --out assets/art/npc_ --n 3

# 批量(prompt 每行一条)
python3 tools/ai_imagegen.py --prompt-file tools/prompts/style_board.txt \
  --out-dir assets/art/style_board --style dinner_scene --aspect-ratio 16:9
```

### 参数

| 参数 | 说明 |
|---|---|
| `--style` | 风格预设:`dinner_scene` / `character` / `tile` / `farm` / `portrait`,自动追加《饥荒》式手绘像素风关键词 |
| `--aspect-ratio` | `1:1` `16:9` `9:16` `4:3` `3:4` `21:9` `2:3` `3:2` |
| `--n` | 一次生成 1–9 张,多图自动加 `_1` `_2` 后缀 |
| `--seed` | 随机种子,同 seed 同 prompt 可复现 |
| `--optimizer` | 开启服务端 prompt 自动优化 |
| `--size` | 输出尺寸(如 `512x512`),用 sips 缩放 |
| `--extra` | 追加自定义描述到 prompt 末尾 |

### 鉴权优先级

1. 环境变量 `MINIMAX_API_KEY`
2. `~/.codex/config.toml` 的 `experimental_bearer_token`
3. 都没有则报错并提示 `export MINIMAX_API_KEY='...'`

## 三、内置 prompt 模板库

| 文件 | 用途 |
|---|---|
| `tools/prompts/style_board.txt` | 阶段 0 风格样板(主角 / 张晓芳 / 院子 / 一块地 / 对话框) |
| `tools/prompts/backgrounds.txt` | 场景背景参考 |
| `tools/prompts/characters.txt` | 角色立绘参考 |

## 四、必须知道的限制

1. **AI 出的是概念图,不是可直接进游戏的 sprite sheet。**
   实测出图是「暗调手绘绘本插画」,而不是低分辨率像素画。
   AI 不保证透明背景、帧对齐、等距网格、严格像素尺寸。
   正式精灵表仍需走 `tools/gen_sprites.py` 的程序化管线 + 人工修整,或以 AI 图为描摹底稿。

   **推荐工作流:AI 大图 → 降分辨率 → 像素描摹底稿 → 程序化上色/对齐。**
   用 `--size 32x48` 直接把 1024×1024 的成图缩到单帧尺寸,
   得到干净的缩略像素画,再在 `tools/gen_sprites.py` 框架里重绘配色与帧序。
   这样既省掉"凭空手绘一张好看的图"的时间,又能保证帧对齐与动画管线可用。
2. **AI 场景图不是瓦片图。** 背景参考只能定色调与氛围,实际地块仍要程序化拼瓦片。
3. **需求 4 的约束已内置:** 脚本检测 prompt 中的真实行政区划/专名
   (黑龙江、宾县、哈尔滨等)并剔除,保证游戏素材不出现真实地名。
4. **版权与授权:** 生成图建议仅作**风格参考与描摹底稿**,入库前需确认商用授权条款。

## 五、在 Codex 会话里直接用

`~/.codex/prompts/img.md` 注册了斜杠命令:

```
/img 风格样板:主角站在院子里,饥荒风格 --style dinner_scene
```

也可以直接说「用 AI 生图生成 X」,由 Codex 调用上述脚本。

## 六、安全建议

`~/.codex/config.toml` 里 `experimental_bearer_token` 与
`mcp_servers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN` 目前是**明文**。
建议改用环境变量注入,避免密钥随配置备份或同步泄露。
