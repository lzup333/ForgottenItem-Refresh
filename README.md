# ForgottenItem-Refresh（遗忘之物 · Lua 版）

把 EternalFuture゙ 的 **ForgottenItem**（C++ / EFMod）移植为 **LuaLoader** Mod。

- 目标游戏版本：**Terraria 1.4.5.8**
- 支持平台：**Android（arm / arm64）**
- PC（Linux x64）暂不适配：实测会崩溃，`Info.json` 已关闭 PC 支持。
- 加载器：**LuaLoader 1.4.2**（在 1.4.1 基础上给 `mod.patch` 增加了 `get_inner_type`）。
  `mod.recipe` / `mod.item` 是 1.4.1 之后才加入的开发版功能，本 Mod 不依赖它们。

## 挂钩选择（很重要）

TEFKernel 的 hook 用 libffi 生成闭包，**只支持标量参数**；对结构体（`IL2CPP_TYPE_VALUETYPE`）
会按指针处理（见内核 `src/patchlib/common/method.c`）。因此本 Mod 遵循官方示例的约定：

- 物品属性：`Item.SetDefaults(int, ItemVariant)` postfix（参数均为引用/标量）
- 掉落表：`ItemDropDatabase.Populate()` postfix（0 参数）
- 配方：用 **0 参数** 的 `Player.ResetEffects` 作为每帧触发点，首帧 `numRecipes > 0` 后
  写入 `Recipe.currentRecipe` 字段并调用 `AddRecipe`，再刷新快速查询表

**不挂钩 `Main.Update(GameTime)` 等带结构体/高频参数的方法**——此前正是它导致崩溃：
崩溃栈为加载器 Lua 钩子参数编组 `push_hook_args → lua_rawseti → luaH_setint`
（崩在 1 参数的钩子上，即旧版的 `Main.Update` 后置）。

> 顺带确认：TEFKernel 自带的配方 API（`recipe_manager.c`）不可用——
> `set_crafting_station` 被错误赋值为 `CreateReverseWallRecipes`，且它把回调挂在
> `CreateReverseWallRecipes` 上。所以配方没有走内核那套。

## 与 C++ 版的关系

| 功能 | C++ 版 | 本 Refresh |
|---|---|---|
| 物品属性 | 钩 `Item.SetDefaults`（3 参） | 钩 `Item.SetDefaults`（**2 参**） |
| 禁装 / 微光 | 钩 `ItemID.Sets..cctor` | `get_inner_type` + 直接写 + 钩 `.cctor` |
| 词缀集合 | 钩 `PrefixLegacy.ItemSets..cctor` | `get_inner_type` + 直接写 + 钩 `.cctor` |
| 掉落 | 钩 `ItemDropDatabase.Populate` | 同 |
| 配方 | 钩 `Recipe.SetupRecipeGroups` 后置 | `Player.ResetEffects` 触发，首帧统一注册 |

## 针对 1.4.5.8 的适配

按 `Source-1.4.5.8`（PC C# 与 PE il2cpp）修正：

1. **`Item.SetDefaults` 只剩 `(int Type, ItemVariant variant)` 两个参数**。
2. **Android 下 `Item.useStyle` / `holdStyle` 是 `byte`** → 写字段用 `"uint8"`。
3. **`PrefixLegacy.ItemSets` 已把 `MagicAndSummon` 拆分为 `Magic` / `Summon`**。
4. **`Recipe.requiredTile` 由 `int[]` 改为 `int`**；且 1.4.5.8 的 `Main` 会在
   `SetupRecipeGroups()` 之后重置 `Main.recipe[]`，所以旧版「在 `SetupRecipeGroups`
   后置里 AddRecipe」会失效。

## 嵌套类型（需要 1.4.2）

`ItemID.Sets`、`PrefixLegacy.ItemSets` 是嵌套类型，`get_type("Terraria.ID", "ItemID.Sets")`
在 Android 上取不到。1.4.2 的 `mod.patch.get_inner_type` 解决这个问题：

```lua
local item_id = mod.patch.get_type("Terraria.ID", "ItemID")
local sets    = mod.patch.get_inner_type(item_id, "Sets")   -- Terraria.ID.ItemID.Sets
```

本 Mod 优先用 `get_inner_type`，取不到会自动回退（1.4.1 下会跳过「解除禁装 / 微光嬗变 /
词缀集合」并打日志）。

## 已知限制

- **睡觉图标（ID:5013）**：它的配方没有材料，这里跳过。

## 目录结构

```
ForgottenItem-Refresh/
├── Info.json
├── Manifest.json
├── luamod.json
└── Resources/
    └── lib/
        └── main.lua      # 全部逻辑
```

## 内容速览

- **武器**：第一分形（伤害 190→130，补配方）、相位扭曲弹射器、无趣弓、埃特尼亚标枪、
  骷髅头弓（伤害 8→30）。
- **工具**：四系夜明锤 / 斧 / 链锯（共 12 件），远古操纵机处用「对应碎片 x6 + 夜明锭 x5」合成。
- **食物**：苹果派切片（酒足饭饱 4 分钟）。
- **掉落**：火星飞碟核心、黑暗魔法师、哥布林、小妖魔等。

## 与原实现的取舍

**夜明工具配方方向**：原 C++ 的 `LuminousTools` 表把「碎片」当结果、把「工具」当材料，
且每组只取 `materials[0]`，实际会做出「用锤子换碎片」这种拿不到工具的死循环配方，
与 README 描述相反。本 Refresh 按 README 的设计意图实现：每件工具 = 其对应碎片 x6 +
夜明锭 x5，共 12 条。

## 使用

把 `ForgottenItem-Refresh` 作为 Mod 目录安装 / 启用即可。
