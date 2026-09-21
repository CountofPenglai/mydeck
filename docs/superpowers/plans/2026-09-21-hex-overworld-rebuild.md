# 六边形事件地图全面重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完整替换旧大地图的状态、生成、导航和渲染架构，实施已定稿危险、畸变、侦察、商店和事件占位规则，每格具有独立对象。
**Architecture:** 每格独立 Resource 状态实例和独立 AdventureHexTile 场景节点；地图容器只管理空间集合和节点协调。保留 AdventureRoomState / AdventureFloorState 公共类名以减少与无关系统的重命名耦合，但内部字段、邻接、生成和 UI 全部采用新 schema，不保留旧道路运行分支。危险、旅行、侦察、库存、战斗适配、事件变体按职责拆分。
**Tech Stack:** Godot 4.7 / GDScript / Resource / Control 独立场景 / PNG 底纹 + SVG 符号 / JSON 存档。
**Spec:** `docs/superpowers/specs/2026-09-21-hex-overworld-danger-design.md`
**Execution:** 用户指定 multi-agent；实现与审查子智能体均用 Terra，监督者保留当前配置模型。共享当前项目，未经要求不另建工作区、不推送。
**Status:** 全部实施与交叉审查完成；54 个非视觉诊断（含 3,200 地图组合与两种子跨章旅程）及真实 GPU 视觉检查通过。保留历史退出资源泄漏告警；人工完整通关未执行。当前工作区未提交、未推送。详见 `docs/superpowers/reports/2026-09-21-hex-overworld-verification.md`。

## Global Constraints

- 全图背面可见，问号隐藏真实类型；相邻六边形直接互通；每格独立状态对象和独立场景节点。
- 标准 40～55 格，样本 48 格：起点 1、首领 1、普通战斗 18、精英 5、营地 5、可见商店 1、问号 17（含另一商店）。
- 起点到首领最短首次探索 8～12 格；首领在对角小范围随机、开局标明；可见商店中央小范围随机。
- 首次进入 +1 危险且立即触发；一般重走不增加；危险按图重置。
- 0～5 无强化，6～11 +10%，12～17 +20%，18～23 +40%，24+ +60%；档位替换，生命与伤害相同。
- 危险 6 仅开场最高最大生命敌人获得一个危险畸变，12+ 全体及增援各一个；首领适用，形态切换不重抽。
- 两章五项畸变及权重严格沿设计第 4.3/4.4 节，过滤永久重复与无效触发；不改变原畸变语义。
- 危险 6 标记 1 格、12 额外标记 2 格；只标背面、不揭示，候选不足不补发。
- 标准侦察范围 3、至多 2 个未揭示格，不移动、不加危险。
- 隐者之家、冒险者遗骨、大自然的恩惠在危险 18+ 完整替换为普通战斗，仅发卡牌奖励。
- 两店共享整局商店 RNG；跨地图不重置，查看和购买已有商品不推进。每店最多两次重访补货，各 +1 危险、+1 商品。
- 背面羊皮纸纹理、简约深色高辨识符号；正面简单占位图；不能用集中绘制或普通方形按钮冒充独立六边形对象。
- 修改使用 apply_patch；不改写用户存档、不清理无关文件。代码完成前不宣称实现。

## 本计划提出的实施裁定（随计划一起审阅）

1. **旧存档隔离**：新局使用 `adventure_hex_run` 槽及 schema 7。保留 `adventure_run.json`、备份及未完成旧事务原样；旧档不能继续在新架构游玩。检测到旧档时说明并要求点击“开始新地图冒险”，不静默重建或覆盖旧进度。不保留旧地图运行模式。
2. **地图形状**：首版 offset 六边形布局，8 列、按目标格数计算行数；末行保留连续格。可镜像方向；首领从远角几何距离 1 的候选中选择，并验证路线 8～12。中央商店从中心几何距离 1 的合法格中选择。
3. **内容初值**：剩余问号按约 3:1 分配奇遇/普通战斗，隐藏商店占其中一格。精英、两家商店及“堕落”带 high_value 标签；其余不擅自赋予高价值。占位事件以默认普通遭遇选择逻辑预生成固定候选。
4. **初始库存**：按稳定 tile_id 顺序在地图初始化时生成两家库存，之后 getter 纯读。重访必须离开商店格再回来并主动确认；关闭界面不算离开。新增随机商店统一为 SHOP 类型，不再额外生成第三家“荒野游商”。
5. **补给清理**：移除行军 provisions 的消费、产出、购买和缺补给伏击；保留独立的 camp_supplies、camp_points 及其职业活动。旧守夜选项移除；游荡者原赌博的“补给 +2”改成“金币 +5”，文案同步，避免空奖励。
6. **侦察入口**：复用现有营地“侦察”活动，消耗 1 营地点后选择至多 2 格；取消或无合法选择不扣费。同一营地首次访问期间可按剩余营地点执行活动；离开后不再开放新休整/侦察，避免免费重访收益。
7. **数值边界**：生命向上取整；伤害在攻击者修正后、受击者减免前按倍率四舍五入，正伤害最低 1。涵盖敌人作为明确来源的直接/固定伤害，不放大无来源环境地表伤害、生命支付、自损或纯生命流失。既有测试生命滑杆和危险倍率各只应用一次。
8. **形态生命**：固定基础生命也适用危险；吸收其他单位已经强化的当前生命不重复放大。例：圣骑合体采用“强化后的基础 75 + 圣像当时当前生命”，而不是把后者再乘一遍。一次性畸变标记保留。
9. **畸变预览**：每格预存固定分配种子；按明确标注的预计进入危险给只读预览（未访问格为当前危险 +1；已锁定战斗用其快照），不消费随机状态。真正开战时固定目标与词缀进 pending payload。召唤按本场种子+固定召唤序号派生，重建相同过程得到相同结果；不增加本项目尚不存在的任意战斗中存档功能。
10. **无改动范围**：此前行动栈审查问题不顺带修复；未列出的事件保留原效果，不擅自补齐全新危险变体。

## Review Focus

1. 隐藏商店/战斗的标题、tooltip、可用按钮泄露正面信息：任务 7 通过实际 UI 状态验证。
2. 在移动/补货提交之间中断，危险、标记、商品重复结算：任务 2/3/8 做事务重放测试。
3. 首领固定生命覆盖、变身重建和召唤绕过危险规则：任务 4 覆盖真实机制，不只测倍率函数。
4. 同名临时畸变消失、形态切换重置一次性能力：任务 4 覆盖来源与 battle_flags。
5. 旧存档被自动初始化流程覆盖，或 64 位 RNG JSON 精度丢失：任务 8 以真实文件字节比较和字符串状态 round-trip 验证。

## 文件职责与并行边界

保留并全面重写：
- `scripts/adventure/adventure_room_state.gd`：每格独立状态，back_type 与 room_type 分离。
- `scripts/adventure/adventure_floor_state.gd`：占位集合、索引、危险及阈值记录；不持久化 neighbor_ids。
- `scripts/adventure/adventure_map_generator.gd`、`adventure_definition.gd`：新生成入口与配置。
- `scripts/adventure/adventure_map_view.gd`：增量维护独立图格节点，不绘制道路。
- `scripts/adventure/adventure_map_scene.gd`：顶栏、选格与弹窗协调。

新增：
- `scripts/adventure/adventure_hex_geometry.gd`：包装 BattleHexGrid 的纯几何，无 BattleController 依赖。
- `scripts/adventure/adventure_map_validator.gd`、`adventure_content_allocator.gd`：校验/配额分配。
- `scripts/adventure/adventure_danger_service.gd`、`adventure_travel_service.gd`、`adventure_reveal_service.gd`。
- `scripts/adventure/adventure_shop_service.gd`、`adventure_event_variant_service.gd`。
- `scripts/adventure/adventure_battle_danger_service.gd`：敌人倍率、畸变适用与快照适配。
- `scripts/adventure/adventure_hex_tile.gd`、`scenes/adventure/adventure_hex_tile.tscn`：独立图格控件。
- `scripts/adventure/adventure_save_schema.gd`：新 schema 与旧档检测。
- `assets/art/adventure/hex_tiles/`：背面底纹、符号、正面占位及生成说明。

主代理负责所有 `adventure_session.gd` 集成；其余文件按任务独占。共享模型接口先完成并审查，才并行委派不重叠模块；不得让多个代理同时改 Session 或 BattleController。

下文缩写文件名均使用上述 `scripts/adventure/` 前缀；例外的完整路径为 `scripts/curses/party_run_state.gd`、`scripts/battle/battle_scenario.gd`、`scripts/battle/battle_unit_state.gd`、`scripts/battle/battle_controller.gd`、`scripts/enemies/enemy_state.gd`、`scripts/enemies/chapter_one_enemy_rules.gd`、`scripts/enemies/chapter_two_enemy_rules.gd`。新增背面枚举置于 `scripts/adventure/adventure_enums.gd`：`BackType { START, MYSTERY, BATTLE, ELITE, CAMP, SHOP, BOSS }`，不复用真实 RoomType 判断未知内容。

诊断局部变量由每个诊断自己的夹具初始化，不依赖真实自动加载单例：`definition = AdventureDefinition.new()`；`floor = AdventureMapGenerator.new().generate(20260921, 0, definition)`；`run = PartyRunState.new()` 后调用 `initialize_adventure(20260921, [], definition)` 并设置 `run.floor_state = floor`。`room` 取本测试指定类型的合法格。商店用例先初始化库存、模拟首次访问完成及离开后返回，再测试重访。Session 用例在 `add_child` 前替换 `save_store = AdventureSaveStore.new("hex_diagnostic_<case>")`，注入该 run；`next_id` 选起点邻接的未探索事件格，`other_id` 选其邻接格。空队伍夹具仅用于状态/纯服务；实际战斗与奖励诊断深复制 Session.HERO_PATHS 中角色并初始化，不使用空队伍验证奖励。所有用例只读写各自诊断槽。

## 验证命令

真实仓库：`/Users/zhengce/projects/my_deck/mydeck`。
每项新增诊断包含对应 `.gd` 与仅实例化该脚本的 `.tscn`，输出唯一 completed/PASS 标记，失败退出码非零。

```sh
MYDECK_GODOT='/Users/zhengce/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot'
MYDECK_ROOT='/Users/zhengce/projects/my_deck/mydeck'
"$MYDECK_GODOT" --headless --disable-crash-handler --path "$MYDECK_ROOT" res://tools/diagnostics/adventure_hex_map_check.tscn --quit-after 600
```

各任务替换场景路径执行；现有经验是沙箱会导致 Godot 启动失败，应通过正常权限审批运行，不把启动限制当作代码失败。无输出的超时退出不是 PASS。

---

### Task 0: 背面美术及正面占位（用户要求先完成）

**Files:** `assets/art/adventure/hex_tiles/parchment_base.png`、`symbols/{start,mystery,battle,elite,camp,shop,boss,high_value}.svg`、`front_placeholder.svg`、`preview.html`、`README.md`。
**Interfaces:** 同一底纹+独立符号层，128×128 SVG，正面 256×256；图格节点负责正六边形裁切和交互，不烘焙状态到纹理。

- [x] 使用内置 image_gen 生成轻淡羊皮纸底纹；深色类型符号采用原生 SVG。
- [x] 检查透明/不透明边界，重新生成全幅不透明版本，未用外部脚本修改生成图像。
- [x] 图像复制进项目，记录提示词；Godot 实际渲染 64/96/128 px 预览并检查。
- [x] 用 `xmllint --noout` 校验 9 个 SVG；Godot 预览退出码 0。此阶段未修改运行时代码。
- [x] 用户补充的独立黑色毛笔边框 `brush_border.png` 已生成，透明中心与角落 alpha=0，组合预览 `brush_preview.png` 已检查。

### Task 1: 独立图格数据、几何与生成器

**Files:** 重写 room_state/floor_state/map_generator/definition；新增 hex_geometry/map_validator/content_allocator；测试 `tools/diagnostics/adventure_hex_map_check.gd/.tscn`。
**Interfaces:**
- `AdventureRoomState` 显式字段：room_id:String、cell:Vector2i、back_type:int、room_type:int、content_id:String、visited/completed/content_revealed/high_value/high_value_marked:bool、danger_variant_id:String、shop_stock:Array[Dictionary]、shop_initialized:bool、shop_restock_count:int、camp_visit_closed:bool。
- `AdventureFloorState.rooms:Array[AdventureRoomState]`、current_room_id:String、danger:int、triggered_thresholds:PackedInt32Array；保留 `get_room(id)`、`get_room_at(cell)`、`get_adjacent_rooms(id)`、`are_connected(a,b)`、`graph_distance(a,b)` 方法，改为六边形占位计算。
- `AdventureMapGenerator.generate(seed:int, floor_index:int, definition:AdventureDefinition)->AdventureFloorState`。
- `AdventureMapValidator.validate(floor:AdventureFloorState)->PackedStringArray`。

- [x] 先写失败测试：
```gdscript
var definition := AdventureDefinition.new()
definition.min_rooms = 48
definition.max_rooms = 48
var floor := AdventureMapGenerator.new().generate(20260921, 0, definition)
assert(floor.rooms.size() == 48)
assert(AdventureMapValidator.validate(floor).is_empty())
assert(floor.rooms[0] != floor.rooms[1])
var clone := AdventureFloorState.from_dict(floor.to_dict())
clone.rooms[0].content_revealed = not floor.rooms[0].content_revealed
assert(clone.rooms[0].content_revealed != floor.rooms[0].content_revealed)
```
- [x] 运行该诊断，记录旧生成器/缺字段导致的预期失败。
- [x] 删除四向主轴生成和旧 neighbor_ids 持久化；六邻接唯一真源为几何模块。生成先分配角色位置，再精确配额，再内容，不从随机尝试静默回退到错误数量。
```gdscript
static func neighbors(cell: Vector2i) -> Array[Vector2i]:
    return BattleHexGrid.neighbors(cell)
static func distance(a: Vector2i, b: Vector2i) -> int:
    return BattleHexGrid.distance(a, b)
```
- [x] 加入 40/48/55 格、100 个种子、两章、唯一 cell/id、全连通、两商店和高价值>=3测试，全部通过后独立审查。

### Task 2: 旅行、危险与侦察规则

**Files:** 新增 travel/danger/reveal_service；主代理接入 session；测试 `adventure_danger_travel_check.gd/.tscn`。
**Interfaces:**
- `AdventureTravelService.plan(floor, target_id:String)->Array[String]`：只用已探索格作为中间路径，最后最多一个新格。
- `AdventureDangerService.bonus_percent(danger:int)->int`；`advance(floor, excluded_tile_id:String)->Dictionary` 返回前后危险与新增标记 ID。
- `AdventureRevealService.get_candidates(floor, origin_id:String, radius:int)->Array[String]`；`reveal(floor, ids:Array[String], radius:int=3, limit:int=2)->bool` 全量校验后一次应用。

- [x] 先写失败断言并运行：
```gdscript
for row in [[0,0],[5,0],[6,10],[11,10],[12,20],[17,20],[18,40],[23,40],[24,60],[99,60]]:
    assert(AdventureDangerService.bonus_percent(row[0]) == row[1])
var before := floor.danger
assert(not AdventureRevealService.reveal(floor, ["missing"], 3, 2))
assert(floor.danger == before)
```
- [x] 按明确档位实现，不用多次倍率累加：
```gdscript
static func bonus_percent(danger: int) -> int:
    if danger >= 24: return 60
    if danger >= 18: return 40
    if danger >= 12: return 20
    if danger >= 6: return 10
    return 0
```
- [x] 阈值记录与标记一次性提交；排除正在进入格，候选不足不补发。travel 不穿过未探索格。
- [x] 覆盖 5→6/11→12/17→18、重走免费、侦察不移动、不收取、跨空白几何范围、重复ID拒绝、未完成事件阻止移动。
- [x] 主代理使 request_move 成为协调流程：先验证并记录事务结果，再应用危险与进入；重复 operation_id 不再应用。诊断绿后审查。

### Task 3: 全局商店随机流与重访事务

**Files:** 新增 shop_service；修改 party_run_state/reward_service/save_store；session 由主代理集成；测试 `adventure_shop_stream_check.gd/.tscn`。
**Interfaces:**
- 局字段 `shop_rng_seed:String`、`shop_rng_state:String`，十进制字符串避免 JSON 精度损失。
- `AdventureShopService.initialize_map(run:PartyRunState)->bool` 按 ID 顺序初始化。
- `get_stock(room:AdventureRoomState)->Array[Dictionary]` 返回深拷贝纯读。
- `restock(run:PartyRunState, tile_id:String, operation_id:String)->Dictionary` 校验当前主动重访、次数和候选，再返回完整事务结果。

- [x] 红测：
```gdscript
var saved_state := run.shop_rng_state
var stock := AdventureShopService.get_stock(room)
stock.clear()
assert(run.shop_rng_state == saved_state)
assert(not room.shop_stock.is_empty())
assert(AdventureShopService.restock(run, room.room_id, "r1").ok)
var after := run.shop_rng_state
assert(AdventureShopService.restock(run, room.room_id, "r1").ok)
assert(run.shop_rng_state == after)
assert(room.shop_restock_count == 1)
```
- [x] 从局状态恢复 RNG，明确生成入口才推进；以独立实例试算，再将商品和 RNG 新状态一起提交：
```gdscript
var rng := RandomNumberGenerator.new()
rng.seed = int(run.shop_rng_seed)
rng.state = int(run.shop_rng_state)
# 货物生成只使用这个 rng；getter 不调用生成器。
```
- [x] 两次各加危险及一个商品；第三次仅开放旧库存。无候选/无效状态不扣费、不推进。
- [x] 覆盖 A/B 店访问顺序、跨图连续、战斗 RNG 独立、侦察不消费、UI重开和 JSON round-trip。审查通过后合入。

### Task 4: 战斗危险快照与畸变适配

**Files:** 新增 battle_danger_service；修改 battle_scenario/enemy_state/battle_unit_state、chapter_one_enemy_rules/chapter_two_enemy_rules；BattleController 仅留调用；主代理 session 接入；测试 `adventure_battle_danger_check.gd/.tscn`。
**Interfaces:**
- payload `danger_snapshot`：danger:int、bonus_percent:int、seed:int、initial_assignments:Array[Dictionary]、spawn_serial:int。
- `AdventureBattleDangerService.create_snapshot(danger:int, chapter:int, enemies:Array[EnemyState], seed:int)->Dictionary`。
- `apply_enemy(state:EnemyState, snapshot:Dictionary, slot:int, reinforcement:bool=false)->void`；`scale_damage(amount:int, source:BattleUnitState, metadata:Dictionary)->int`；`transfer_form(old_state:EnemyState, new_state:EnemyState)->void`。
- 畸变 ID 来源单独保存到 EnemyState，不修改共享 EnemyData；安装时与 permanent_fields 去重。

- [x] 红测倍率、重复应用和快照：
```gdscript
var state := ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 12)
var snap := AdventureBattleDangerService.create_snapshot(18, 1, [state], 91)
AdventureBattleDangerService.apply_enemy(state, snap, 0)
var once := state.get_max_health()
AdventureBattleDangerService.apply_enemy(state, snap, 0)
assert(state.get_max_health() == once)
assert(snap.initial_assignments.size() == 1)
```
- [x] 生命从未缩放基数计算；正常、固定直接伤害在共同入口仅乘一次，环境伤害和生命流失排除；不能复写基础资源。
- [x] 候选过滤表覆盖所有原型：兽心限咒波利用/畸变牌；启明限能自产咒波；辐照限造物；静态圣像只保留空目；去除原生永久重复。无合法候选报告配置错误，不静默无词条。
- [x] 真实重现鱼人逆位、腐心二阶段、圣骑合体和血肉召唤。复制畸变一次性状态，不因为 reset_for_battle 重新披夜。
- [x] 覆盖并列最高者、第一阶段增援无词条、第二阶段增援一个、同名显化消失、固定生命与吸收当前生命不二次缩放。通过后双审查。

### Task 5: 事件变体与仅卡牌奖励

**Files:** 新增 event_variant_service；修改 content_catalog/reward_service；session 集成；测试 `adventure_danger_event_check.gd/.tscn`。
**Interfaces:**
- `AdventureEventVariantService.resolve(content_id:String, danger:int)->Dictionary` 返回 `variant_id, auto_battle, reward_mode, normal_text, danger_text`。
- `AdventureRewardService.create_cards_only_reward(run, room, tier:int)->Dictionary`，不调用原事件回调或固定奖励。
- pending payload `reward_mode="cards_only"`、`event_variant_id`；领取后才 room.completed。

- [x] 红测：
```gdscript
for id in ["hermit_house", "adventurer_remains", "nature_blessing"]:
    assert(not AdventureEventVariantService.resolve(id, 17).auto_battle)
    assert(AdventureEventVariantService.resolve(id, 18).reward_mode == "cards_only")
var reward := AdventureRewardService.new().create_cards_only_reward(run, room, AdventureEnums.EncounterTier.WEAK)
for key in ["gold", "provisions", "camp_supplies", "ritual_points", "max_equipment"]:
    assert(int(reward.get(key, 0)) == 0)
assert((reward.get("equipment", []) as Array).is_empty())
```
- [x] resolver 使用内容白名单；普通遭遇而非现有 start_event_battle 硬编码精英。奖励按卡牌白名单构造，不先发全奖励再减去。
- [x] 战斗事件事务切换到 REWARD，不让外层 commit 吞掉新事务；卡牌领完/跳过后完成一次。
- [x] 覆盖 17→18 当格生效、无遗骨资格、无原治疗或诅咒处理、战败不奖励、读档不重复发放；绿后审查。

### Task 6: 会话整合与旧行军机制清理

**Files:** 主代理修改 session、economy_config、party_run_state、content_catalog；测试 `adventure_hex_session_check.gd/.tscn`。
**Interfaces:** 保留外部 new/run/equipment/camp/battle 函数，地图动作新增 `request_scout(tile_ids:Array[String])->Dictionary`、`request_shop_revisit(tile_id:String)->Dictionary`；内部只编排各服务。

- [x] 红测用真实 session：首次探索 +1、自动启动战斗、事件弹窗不能绕过、已探索路径不扣资源、商店路过不收费。
```gdscript
var before := session.current_run.floor_state.danger
var result := session.request_move(next_id)
assert(result.ok)
assert(session.current_run.floor_state.danger == before + 1)
assert(not session.request_move(other_id).ok) # 未处理当格事件/战斗时
```
- [x] 移除 request_move 的补给/伏击分支；创建战斗前固定危险快照和奖励策略，再进入场景。
- [x] 更新补给奖励、商店购买、游荡者赌博和守夜文案/选项；独立扎营物资及职业活动保持。
- [x] 营地侦察确认时扣 1 点，取消不扣；离开后关闭当格营地活动，不能重访刷新营地点。
- [x] 维护既有 inventory、ranger_dig、druid_infusion、卡牌奖励诊断，不能把失败断言直接删除来变绿。审查主流程不重新膨胀为单体逻辑。

### Task 7: 独立六边形图格场景与地图 UI

**Files:** 新增 hex_tile.gd/.tscn；重写 map_view/map_scene 的地图部分；保留队伍、背包与诅咒弹窗；测试 `adventure_hex_tile_ui_check.gd/.tscn`。
**Interfaces:**
- `AdventureHexTile.bind(room:AdventureRoomState)->void`；`refresh(presentation:Dictionary)->void`；selected/hovered(room_id:String)。
- `_has_point(local:Vector2)->bool` 使用六边形多边形。
- MapView.room_buttons 改为 room_nodes:Dictionary，每个 room_id 一个 AdventureHexTile；状态刷新保留节点 identity。

- [x] 红测：
```gdscript
var view := AdventureMapView.new()
add_child(view)
view.set_floor_state(floor)
var tile := view.room_nodes[floor.rooms[0].room_id] as AdventureHexTile
view.set_floor_state(floor)
assert(view.room_nodes[floor.rooms[0].room_id] == tile)
assert(not tile._has_point(Vector2.ZERO))
assert(tile._has_point(tile.size / 2))
assert(view.room_nodes.size() == floor.rooms.size())
```
- [x] 图格节点自行绘制裁剪纹理、背面符号/正面占位、高价值、选中/当前位置/完成态；输入区域严格六边形，不被透明子节点吞点击。
- [x] 父地图只排版、缩放和维护实例，无道路、无集中全图绘制；全图缩放至可见区域，不隐藏类型。
- [x] 顶栏危险替换补给/伏击；详情依 revealed 决定内容，不从实际 room_type 泄露隐藏商店；侦察选格独立确认。
- [x] 分别在 1280×720、窄窗、64px缩略检查，保存真实渲染截图；检查文本、符号辨识与点击角落。审查后合入。

### Task 8: 新存档与幂等恢复

**Files:** 新增 save_schema；修改 save_store、session 初始化与 map_scene 启动分流；测试 `adventure_hex_save_check.gd/.tscn`。
**Interfaces:** `AdventureSaveSchema.VERSION=7`、`SLOT="adventure_hex_run"`；`is_legacy(data:Dictionary)->bool`；旧数据只读检测，不调用新 floor.from_dict。

- [x] 红测在诊断专用临时路径生成旧 schema fixture；加载新系统后验证旧档字节完全不变，且未生成/覆盖旧 pending。
- [x] 新 schema 全字段 round-trip，房间为独立实例；RNG 字符串保存：
```gdscript
var encoded := JSON.stringify({"state": "9223372036854775806"})
assert(str(JSON.parse_string(encoded).state) == "9223372036854775806")
var restored := AdventureFloorState.from_dict(floor.to_dict())
assert(restored.to_dict() == floor.to_dict())
```
- [x] 对移动和补货注入“已记录、未应用”“已应用、未提交”中断；重放同 operation_id 不追加危险、标记或商品。
- [x] 损坏主档回退同 schema 备份；未来 schema 拒绝而非重建；旧档仅说明并等待明确新局操作。
- [x] 删除/迁移旧生产存档不在任务范围内；全部测试文件写到独立诊断槽。绿后审查。

### Task 9: 全量回归与最终审查

**Files:** 维护现有 `adventure_system_check.gd` 和 `adventure_inventory_ui_check.gd`；新增上述各诊断；记录设计落实状态。
**Interfaces:** 所有任务产物集成；无新玩法接口。

- [x] 替换现有地图 18～24 格、主轴、补给断言为新规则；保留职业、装备和奖励无关覆盖。
- [x] 运行 Godot editor 导入/解析检查，再运行全部非视觉诊断（原有 41 项基线和新增项）；逐场景保留输出与退出码，任何 Parse/Script Error 不能忽略。
- [x] 两个种子、两章自动化 Session 冒险流程：探索→6→侦察→12→商店重访→18+→首领→下一图→读档。危险18事件另有真实 Session 专项测试；战斗胜利由夹具结算，未冒称人工完整通关。真实 GPU 宽窄窗口另行检查。
- [x] 三名 Terra reviewer 分别审查“数据/存档”“危险/畸变/奖励”“节点/UI/美术”，主代理核实结论；修复当前任务内问题并重跑相关诊断。
- [x] 检查 `git diff --check`、资源引用、无旧图运行分支、无只存在于生成工具目录的资源。
- [x] 提交策略按用户后续指令执行；默认不推送。最终明确已实现/测试情况及旧档不支持继续游玩的限制。

## 执行顺序与并行安排

0 美术先完成 → 1 数据接口 → 8 的新槽隔离与版本拒绝先落地 → 2/3/4/5 在独占文件中可并行（最多三名 Terra 同时工作）→ 主代理 6 集成 → 7 UI → 8 的全字段及中断恢复验收 → 9 回归与交叉审查。任何新运行时接入前先隔离旧存档。
任何任务进入实现前都要先提交红测证据；子代理只改授权文件，结束给出修改清单、测试日志与剩余风险。设计接口变化先同步主代理和消费该接口的任务，不各自发明不同 API。

## 自审记录

- 已将新“每格独立对象”和背面/正面美术纳入任务 0/1/7，而非仅换旧 Button 外观。
- 设计各章分别对应任务 1～8；三项事件占位、商店独立序列、跨阈值先计费及两章畸变池都有测试任务。
- 上述实施裁定是为消除设计第 12 节缺口提出的明确选择，必须随本文得到用户审阅后才执行。
- 本计划没有启动产品代码；保留用户选择的 multi-agent 执行方式。
