# 中立与诅咒牌表

> 本表收录没有职业归属的中立牌，以及所有诅咒牌。当前资源全部为诅咒牌。

- 当前收录：15 张
- “不进入奖励池”只描述 `reward_eligible = false`；诅咒牌本身也会被通用奖励过滤逻辑排除。

## 普通

| 名称 | 类型 | AP | 目标/射程 | 特殊 | 说明 | 资源 |
| --- | --- | ---: | --- | --- | --- | --- |
| 病症 | 诅咒 | 0 | 无需目标 | — | 本牌不能打出。持有者的回合结束时，若本牌仍在其手牌中，将本牌移入放逐区，然后持有者失去 2 点生命并获得 1 点咒波。 | [curse_disease.tres](../../resources/cards/curse_disease.tres) |

## 史诗

| 名称 | 类型 | AP | 目标/射程 | 特殊 | 说明 | 资源 |
| --- | --- | ---: | --- | --- | --- | --- |
| 不休之业 | 诅咒 | 0 | 无需目标 | — | 将你的当前生命设为 1。直到本回合结束，对你的致命伤害或生命损失最低将生命降至 1。你获得 2+D AP，然后抽 D 张牌。 | [curse_industry_unrest.tres](../../resources/cards/curse_industry_unrest.tres) |
| 兼爱之业 | 诅咒 | 0 | 无需目标 | — | 你弃置所有其他手牌。令其他存活队友合计抽取队友数量 +D 张牌，每次由当前手牌最少的队友抽 1 张；然后每名其他队友获得 2D 护甲。 | [curse_industry_universal_love.tres](../../resources/cards/curse_industry_universal_love.tres) |
| 凭依之业 | 诅咒 | 0 | 单体；范围 3 | — | 令范围 3 内 1 名敌人立即对距离最近的另一名同阵营单位进行 1 次获得 +2D 伤害加值的武器打击；若没有合法目标，令该敌人对自己造成等同于其当前攻击值的伤害。 | [curse_industry_possession.tres](../../resources/cards/curse_industry_possession.tres) |
| 孽生之业 | 诅咒 | 0 | 指定范围；范围 3 | — | 你在范围 3 内选择 1 个空格，召唤具有 10+5D 生命的友方活根；召唤失败时效果结束。召唤成功后，以每名其他友方各 1 次、该活根 2 次为原点，对各原点范围 1 内每名敌人造成 3+D 点固定伤害，然后你恢复等同于这些伤害造成的实际生命损失总和的生命。 | [curse_industry_offspring.tres](../../resources/cards/curse_industry_offspring.tres) |
| 守成之业 | 诅咒 | 0 | 单体；范围 3 | — | 你选择另一张深度低于 3 的诅咒并将其加深 1，然后令范围 3 内 1 名敌人获得该诅咒当前深度的报效果，持续到该敌人的下回合结束。所有其他存活敌人获得 2+D 层眩晕。 | [curse_industry_preservation.tres](../../resources/cards/curse_industry_preservation.tres) |
| 无羁之业 | 诅咒 | 0 | 无需目标 | — | 本牌结算后结束你的当前回合，跳过下一名敌人的抽牌与行动，然后你获得 1 个额外行动阶段；该阶段的当前 AP 改为 2+D，而非在原 AP 上增加。 | [curse_industry_unbound.tres](../../resources/cards/curse_industry_unbound.tres) |
| 痼病之业 | 诅咒 | 0 | 单体；范围 3 | — | 你失去等同于当前手牌数的生命，然后向范围 3 内 1 名敌人的牌库洗入 D+2 张病症，并令其抽 D 张牌。 | [curse_industry_disease.tres](../../resources/cards/curse_industry_disease.tres) |
| 福音之业 | 诅咒 | 0 | 无需目标 | 不进入奖励池 | 你须拥有多于 3D 点生命才能打出。你失去 3D 点生命，然后对范围 3 内每个其他单位造成 4+2D 加你的智力伤害加值的伤害。每名实际失去生命的单位获得 D 点咒波，并将 1 张临时辐照咒害洗入其牌库。 | [curse_industry_gospel.tres](../../resources/cards/curse_industry_gospel.tres) |
| 贪欲之业 | 诅咒 | 0 | 无需目标 | — | 你预先从所有单位的弃牌堆和你的牌库选择至多 2+D 张牌；若候选不足则选择全部。你磨空牌库，然后将所选牌从其当前弃牌堆移入你的手牌。 | [curse_industry_greed.tres](../../resources/cards/curse_industry_greed.tres) |
| 赝作之业 | 诅咒 | 0 | 无需目标 | — | 你选择另一张深度低于 3 的诅咒和 1 张非诅咒手牌。将所选诅咒加深 1，然后复制所选手牌并将副本加入你的手牌；副本 AP 消耗 -D，最低为 0，打出后或本回合结束时放逐。 | [curse_industry_counterfeit.tres](../../resources/cards/curse_industry_counterfeit.tres) |
| 跛行之业 | 诅咒 | 0 | 指定范围；范围 6 | — | 你获得 4 层眩晕，并选择距你不超过 3+D 格的目标格。若目标格合法且空置，你传送至该格；否则留在原位。然后你获得 2+D AP。 | [curse_industry_cripple.tres](../../resources/cards/curse_industry_cripple.tres) |
| 遗逝之业 | 诅咒 | 0 | 无需目标 | — | 你弃置所有其他手牌，然后从任意单位当前弃牌堆选择至多 D+1 张牌，在你的手牌中生成其 0 AP 副本；副本打出后或本回合结束时放逐。 | [curse_industry_passing.tres](../../resources/cards/curse_industry_passing.tres) |
| 饕餮之业 | 诅咒 | 0 | 单体；范围 1 | — | 选择范围 1 内 1 名敌人。若其当前生命不高于你的当前生命 +5×（D-1），令其失去全部生命，并使你恢复等同于其实际生命损失的生命；否则你失去全部生命。 | [curse_industry_gluttony.tres](../../resources/cards/curse_industry_gluttony.tres) |
| 鲜血之业 | 诅咒 | 0 | 无需目标 | — | 你须拥有多于 3+2D 点生命才能打出。你失去 3+2D 点生命，然后对范围 3 内每名敌人造成 8+4D 点固定伤害；每名敌人实际损失多少生命，你便恢复多少生命。 | [curse_industry_blood.tres](../../resources/cards/curse_industry_blood.tres) |
