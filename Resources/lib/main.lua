-- ============================================================================
-- ForgottenItem-Refresh（遗忘之物 · Lua 版）
-- ----------------------------------------------------------------------------
-- 由 EternalFuture゙ 的 ForgottenItem（C++ / EFMod）移植而来，改用 LuaLoader 的
-- mod.patch 能力（基于 LuaLoader 1.4.2）。
--
-- 目标：Terraria 1.4.5.8（Android arm/arm64）
--
-- 挂钩选择（很重要）：
--   内核的 hook 用 libffi 生成闭包，只支持标量参数；对结构体按值参数会按
--   指针处理（见 TEFKernel src/patchlib/common/method.c: il2cpp_type_to_patch_type
--   把 IL2CPP_TYPE_VALUETYPE 映射成 PATCH_POINTER）。因此这里**不挂**带结构体
--   参数的方法，也不挂高频的 Main.Update(GameTime)：
--     * 物品属性  -> Item.SetDefaults(int, ItemVariant)  postfix（都是引用/标量）
--     * 掉落表    -> ItemDropDatabase.Populate()         postfix（0 参数）
--     * 配方      -> 用 0 参数的 Player.ResetEffects 作为每帧触发点，
--                    首帧等 numRecipes > 0 后统一写入 Recipe.currentRecipe + AddRecipe。
--
-- 针对 1.4.5.8 的适配：
--   1. Item.SetDefaults 只剩 (int Type, ItemVariant variant) 两个参数。
--   2. Android/IL2CPP 下 Item.useStyle / holdStyle 是 byte -> 写 "uint8"。
--   3. PrefixLegacy.ItemSets 已把 MagicAndSummon 拆分为 Magic / Summon。
--   4. Recipe.requiredTile 由 int[] 改为 int。
--
-- 加载器要求：
--   本 Mod 基于 **LuaLoader 1.4.2**（该版本给 mod.patch 增加了 get_inner_type）。
--   ItemID.Sets / PrefixLegacy.ItemSets 是嵌套类型，只能用
--   get_inner_type(ItemID, "Sets") / get_inner_type(PrefixLegacy, "ItemSets") 获取；
--   若加载器没有 get_inner_type（1.4.1），会自动退回旧写法（Android 上取不到），
--   此时「解除禁装 / 微光嬗变 / 词缀集合」会跳过并打日志。
--
-- 说明：睡觉图标(ID:5013) 的配方无材料，被跳过。
-- ============================================================================

mod.meta = {
    pkg_id = "lzup.lua.forgottenitem",
    version = "1.2.1",
    version_code = 20250517,
    api_version = 1,
}

local P = mod.patch

-- Android/IL2CPP 下 useStyle 是 byte；桌面端是 int
local T_USE_STYLE = (mod.platform == "android") and "uint8" or "int32"

-- ============================================================================
-- 工具
-- ============================================================================

local function first_type(candidates)
    for _, c in ipairs(candidates) do
        local t = P.get_type(c[1], c[2])
        if t then return t end
    end
    return nil
end

-- ============================================================================
-- 1) Item.SetDefaults —— 补回被移除物品 / 调整已有物品
-- ============================================================================

local item_type
local item_fields = {}
local buy_price
local set_weapon_values
local default_to_food

local ITEM_FIELD_TYPES = {
    useStyle      = T_USE_STYLE,
    useAnimation  = "int32",
    useTime       = "int32",
    width         = "int32",
    height        = "int32",
    shoot         = "int32",
    useAmmo       = "int32",
    damage        = "int32",
    shootSpeed    = "float",
    noMelee       = "bool",
    value         = "int32",
    ranged        = "bool",
    channel       = "bool",
    rare          = "int32",
    autoReuse     = "bool",
    mana          = "int32",
    magic         = "bool",
    noUseGraphic  = "bool",
}

local function iset(name, inst, value)
    local f = item_fields[name]
    if f then
        P.set_field_value(f, inst, value, ITEM_FIELD_TYPES[name])
    end
end

local function price(platinum, gold, silver, copper)
    if not buy_price then return 0 end
    local v = P.invoke(buy_price, platinum, gold, silver, copper)
    if type(v) == "number" then return v end
    return 0
end

local statics_ready = false

function on_set_defaults(inst, args)
    if not statics_ready then
        local a = apply_itemid_sets()
        local b = apply_prefix_sets()
        statics_ready = (a or b)
    end

    local t = args[1]

    if t == 2881 then
        -- 相位扭曲弹射器
        iset("useStyle", inst, 5)
        iset("useAnimation", inst, 20)
        iset("useTime", inst, 80)
        iset("shootSpeed", inst, 500.0)
        iset("width", inst, 20)
        iset("height", inst, 12)
        iset("damage", inst, 550)
        iset("shoot", inst, 79)
        iset("mana", inst, 100)
        iset("rare", inst, 8)
        iset("value", inst, price(0, 10, 0, 0))       -- 10 金
        iset("noMelee", inst, true)
        iset("channel", inst, true)
        iset("magic", inst, true)

    elseif t == 3850 then
        -- 埃特尼亚标枪
        iset("useStyle", inst, 1)
        iset("shootSpeed", inst, 55.5)
        iset("shoot", inst, 680)
        iset("damage", inst, 71)
        iset("width", inst, 0)
        iset("height", inst, 30)
        iset("useAnimation", inst, 17)
        iset("useTime", inst, 17)
        iset("noUseGraphic", inst, true)
        iset("noMelee", inst, true)
        iset("value", inst, price(0, 5, 0, 0))        -- 5 金
        iset("ranged", inst, true)
        iset("rare", inst, 6)

    elseif t == 3853 then
        -- 无趣弓
        iset("useStyle", inst, 5)
        iset("useAnimation", inst, 25)
        iset("useAmmo", inst, 40)
        iset("width", inst, 20)
        iset("height", inst, 34)
        iset("shoot", inst, 1)
        iset("damage", inst, 72)
        iset("shootSpeed", inst, 50.0)
        iset("noMelee", inst, true)
        iset("value", inst, 180000)
        iset("ranged", inst, true)
        iset("useTime", inst, 12)
        iset("channel", inst, true)
        iset("rare", inst, 6)
        iset("autoReuse", inst, true)

    elseif t == 4058 then
        -- 骷髅头弓：基础伤害 8 -> 30，击退 5.0
        iset("damage", inst, 40)
        if set_weapon_values then
            P.invoke(set_weapon_values, inst, 30, 5.0, 0)
        end

    elseif t == 4722 then
        -- 第一分形：伤害 190 -> 130
        iset("noMelee", inst, false)
        iset("damage", inst, 130)

    elseif t == 4010 then
        -- 苹果派切片：酒足饭饱 4 分钟
        if default_to_food then
            P.invoke(default_to_food, inst, 22, 22, 207, 14400, false, 17)
        end
        iset("rare", inst, 3)
        iset("value", inst, price(0, 0, 70, 5))       -- 70 银 5 铜
    end
end

-- ============================================================================
-- 2) ItemID.Sets（嵌套类型，Lua 侧取不到 -> 目前仅尝试并告警）
-- ============================================================================

local itemid_fields = {}

function apply_itemid_sets()
    local applied = false

    for _, name in ipairs({ "Deprecated", "ItemsThatShouldNotBeInInventory" }) do
        local f = itemid_fields[name]
        if f then
            local arr = P.get_field_value(f, nil, "object")
            if arr then
                P.array_fill(arr, false, "bool")
                applied = true
            end
        end
    end

    local f = itemid_fields.ShimmerTransformToItem
    if f then
        local arr = P.get_field_value(f, nil, "object")
        if arr then
            applied = true
            local pairs_to_set = {
                { 3357, 3331 }, { 3868, 3861 }, { 3862, 3867 }, { 2881, 3358 },
                { 3847, 3865 }, { 3854, 3853 }, { 2901, 2989 }, { 2990, 2902 },
                { 3404, 1649 }, { 3398, 1648 }, { 1569, 1571 },
            }
            for _, pr in ipairs(pairs_to_set) do
                P.array_set(arr, pr[1], pr[2], "int32")
                P.array_set(arr, pr[2], pr[1], "int32")
            end
        end
    end

    return applied
end

-- ============================================================================
-- 3) PrefixLegacy.ItemSets（嵌套类型，同上）
-- ============================================================================

local prefix_fields = {}

function apply_prefix_sets()
    local applied = false

    local function mark(name, id)
        local f = prefix_fields[name]
        if f then
            local arr = P.get_field_value(f, nil, "object")
            if arr then
                P.array_set(arr, id, true, "bool")
                applied = true
            end
        end
    end

    mark("SwordsHammersAxesPicks", 4722)
    mark("Magic", 2881)
    mark("GunsBows", 3850)
    mark("GunsBows", 3853)
    mark("GunsBows", 4058)

    return applied
end

-- ============================================================================
-- 4) ItemDropDatabase.Populate —— 掉落表
-- ============================================================================

local drop_common
local drop_register

local function drop_to(db, npc, item, chance)
    if not (drop_common and drop_register) then return end
    local rule = P.invoke(drop_common, item, chance, 1, 1)
    if rule then
        P.invoke(drop_register, db, npc, rule)
    end
end

function on_populate(db)
    drop_to(db, 395, 2881, 50)                                   -- 火星飞碟核心
    drop_to(db, 564, 3853, 10)
    drop_to(db, 565, 3853, 10)
    drop_to(db, 561, 3850, 10)
    drop_to(db, 562, 3850, 10)
    drop_to(db, 563, 3850, 10)
    for _, npc in ipairs({ 552, 553, 554, 555, 556, 557 }) do
        drop_to(db, npc, 3848, 10)
    end
    for _, npc in ipairs({ 555, 556, 557 }) do
        drop_to(db, npc, 3849, 10)
    end
    drop_to(db, 572, 3851, 10)
    drop_to(db, 573, 3851, 10)
end

-- ============================================================================
-- 5) 合成配方
-- ============================================================================

local RECIPES = {
    -- 夜明工具组：对应碎片 x6 + 夜明锭 x5，远古操纵机(LunarCraftingStation = 412)
    { result = 2785, ingredients = { { item = 3458, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2775, ingredients = { { item = 3456, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2780, ingredients = { { item = 3457, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 3465, ingredients = { { item = 3459, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2782, ingredients = { { item = 3458, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2772, ingredients = { { item = 3456, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2777, ingredients = { { item = 3457, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 3462, ingredients = { { item = 3459, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2783, ingredients = { { item = 3458, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2773, ingredients = { { item = 3456, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2778, ingredients = { { item = 3457, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 3463, ingredients = { { item = 3459, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },

    -- 旧礼物（无工作站）
    { result = 599, ingredients = { { item = 1869, stack = 1 } } },
    { result = 600, ingredients = { { item = 1869, stack = 1 } } },
    { result = 601, ingredients = { { item = 1869, stack = 1 } } },

    -- 骷髅头弓（工作台 = 18）
    { result = 4058, ingredients = { { item = 1274, stack = 1 }, { item = 154, stack = 50 } }, tile = 18 },
    -- 彩色染料（染缸 = 228）
    { result = 3978, ingredients = { { item = 3385, stack = 1 }, { item = 3386, stack = 1 }, { item = 3387, stack = 1 }, { item = 3388, stack = 1 } }, tile = 228 },
    -- 苹果派切片（无工作站，一次 4 个）
    { result = 4010, stack = 4, ingredients = { { item = 4011, stack = 1 } } },
    -- 苹果派（无工作站）
    { result = 4011, ingredients = { { item = 4010, stack = 4 } } },
    -- 第一分形（秘银砧 / 山铜砧 = 134）
    { result = 4722, ingredients = { { item = 757, stack = 1 }, { item = 3827, stack = 1 }, { item = 3787, stack = 1 }, { item = 1570, stack = 2 }, { item = 2880, stack = 1 } }, tile = 134 },
    -- 骨块（工作台 = 18）
    { result = 766, ingredients = { { item = 154, stack = 1 } }, tile = 18 },
    -- 假宝箱
    { result = 3705, ingredients = { { item = 3886, stack = 1 } } },
    { result = 3706, ingredients = { { item = 3887, stack = 1 } } },

    -- 睡觉图标：无材料，跳过
    -- { result = 5013, ingredients = {}, tile = 79 },
}

local function count_ingredients(r)
    local n = 0
    for _ in ipairs(r.ingredients) do n = n + 1 end
    return n
end

-- 手动注册（发布版 LuaLoader 1.4.1 没有 mod.recipe）
--   触发点用 0 参数的 Player.ResetEffects，避免 Main.Update(GameTime) 的参数编组问题。
local recipe_type
local f_current_recipe
local f_create_item
local f_required_item
local f_required_tile
local f_num_recipes
local f_item_stack
local m_add_recipe
local m_item_net_defaults
local m_create_quick
local m_update_materials

local recipes_added = false

local function recipes_ready()
    if not (f_num_recipes and m_add_recipe) then return false end
    local n = P.get_field_value(f_num_recipes, nil, "int32")
    return type(n) == "number" and n > 0
end

local function add_one(r)
    if not (f_current_recipe and f_create_item and f_required_item and m_add_recipe and m_item_net_defaults) then
        return false
    end

    local cur = P.get_field_value(f_current_recipe, nil, "object")
    if not cur then return false end

    local create = P.get_field_value(f_create_item, cur, "object")
    if not create then return false end
    P.invoke(m_item_net_defaults, create, r.result)
    if f_item_stack then
        P.set_field_value(f_item_stack, create, r.stack or 1, "int32")
    end

    local req = P.get_field_value(f_required_item, cur, "object")
    if not req then return false end
    for i, ing in ipairs(r.ingredients) do
        local slot = P.array_at(req, i - 1) -- requiredItem 是 0 基数组
        if slot then
            P.invoke(m_item_net_defaults, slot, ing.item)
            if f_item_stack then
                P.set_field_value(f_item_stack, slot, ing.stack or 1, "int32")
            end
        end
    end

    if r.tile and r.tile >= 0 and f_required_tile then
        P.set_field_value(f_required_tile, cur, r.tile, "int32")
    end

    P.invoke(m_add_recipe)
    return true
end

local function add_all_recipes()
    local ok_count = 0
    for _, r in ipairs(RECIPES) do
        if count_ingredients(r) == 0 then
            mod.warn("跳过无材料配方 result=" .. tostring(r.result))
        else
            local ok, done = pcall(add_one, r)
            if ok and done then
                ok_count = ok_count + 1
            else
                mod.warn("配方注册失败 result=" .. tostring(r.result) .. " -> " .. tostring(done))
            end
        end
    end

    if m_create_quick then P.invoke(m_create_quick) end
    if m_update_materials then P.invoke(m_update_materials) end

    mod.info("已注册 %d 条配方（手动）", ok_count)
end

-- Player.ResetEffects()：0 参数，每帧执行，作为延迟注册的触发点
function on_player_frame(inst, args)
    if recipes_added then return end
    if not recipes_ready() then return end
    recipes_added = true
    add_all_recipes()
end

local function setup_manual_recipes()
    recipe_type = first_type({ { "Terraria", "Recipe" } })
    if not recipe_type then
        mod.warn("找不到 Terraria.Recipe，跳过配方注册")
        return
    end

    f_current_recipe = P.get_field(recipe_type, "currentRecipe")
    f_create_item = P.get_field(recipe_type, "createItem")
    f_required_item = P.get_field(recipe_type, "requiredItem")
    f_required_tile = P.get_field(recipe_type, "requiredTile")
    f_num_recipes = P.get_field(recipe_type, "numRecipes")
    m_add_recipe = P.get_method(recipe_type, "AddRecipe", 0)
    m_create_quick = P.get_method(recipe_type, "CreateRequiredItemQuickLookups", 0)
    m_update_materials = P.get_method(recipe_type, "UpdateWhichItemsAreMaterials", 0)
    f_item_stack = P.get_field(item_type, "stack")
    m_item_net_defaults = P.get_method(item_type, "netDefaults", 1)

    if f_current_recipe and m_add_recipe and m_item_net_defaults then
        local player = first_type({ { "Terraria", "Player" } })
        local m_reset = player and P.get_method(player, "ResetEffects", 0)
        if m_reset then
            P.install_hook(m_reset, { postfix = on_player_frame })
        else
            mod.warn("找不到 Player.ResetEffects，无法注册配方")
        end
    else
        mod.warn("Recipe 符号不完整，跳过配方注册")
    end
end

-- ============================================================================
-- setup
-- ============================================================================

function setup()
    mod.info("ForgottenItem-Refresh 初始化（%s/%s）", mod.platform, mod.arch)

    -- ---- Item ----
    item_type = first_type({ { "Terraria", "Item" } })
    if not item_type then
        mod.warn("找不到 Terraria.Item，终止初始化")
        return
    end

    for name in pairs(ITEM_FIELD_TYPES) do
        item_fields[name] = P.get_field(item_type, name)
    end
    buy_price = P.get_method(item_type, "buyPrice", 4)
    set_weapon_values = P.get_method(item_type, "SetWeaponValues", 3)
    default_to_food = P.get_method(item_type, "DefaultToFood", 6)

    local m_defaults = P.get_method(item_type, "SetDefaults", 2)
    if m_defaults then
        P.install_hook(m_defaults, { postfix = on_set_defaults })
    else
        mod.warn("找不到 Item.SetDefaults(int, ItemVariant)")
    end

    -- ---- ItemID.Sets / PrefixLegacy.ItemSets（嵌套类型）----
    -- 1.4.2+：用 get_inner_type(parent, "Sets") 取；1.4.1：退回 get_type 全名（Android 上取不到）。
    local function nested(outer_candidates, inner_name, fallback_candidates)
        if type(P.get_inner_type) == "function" then
            local outer = first_type(outer_candidates)
            if outer then
                local t = P.get_inner_type(outer, inner_name)
                if t then return t end
            end
        end
        return first_type(fallback_candidates)
    end

    local sets = nested(
        { { "Terraria.ID", "ItemID" } },
        "Sets",
        { { "Terraria.ID", "ItemID.Sets" }, { "", "ItemID.Sets" } }
    )
    if sets then
        for _, name in ipairs({ "Deprecated", "ItemsThatShouldNotBeInInventory", "ShimmerTransformToItem" }) do
            itemid_fields[name] = P.get_field(sets, name)
        end
        apply_itemid_sets()
        local m = P.get_method(sets, ".cctor", 0)
        if m then P.install_hook(m, { postfix = function() apply_itemid_sets() end }) end
    else
        mod.warn("找不到 ItemID.Sets（需要 LuaLoader 1.4.2+ 的 get_inner_type；跳过禁装/微光）")
    end

    local prefix = nested(
        { { "Terraria.GameContent.Prefixes", "PrefixLegacy" } },
        "ItemSets",
        { { "Terraria.GameContent.Prefixes", "PrefixLegacy.ItemSets" }, { "", "PrefixLegacy.ItemSets" } }
    )
    if prefix then
        for _, name in ipairs({ "SwordsHammersAxesPicks", "Magic", "GunsBows" }) do
            prefix_fields[name] = P.get_field(prefix, name)
        end
        apply_prefix_sets()
        local m = P.get_method(prefix, ".cctor", 0)
        if m then P.install_hook(m, { postfix = function() apply_prefix_sets() end }) end
    else
        mod.warn("找不到 PrefixLegacy.ItemSets（需要 LuaLoader 1.4.2+ 的 get_inner_type；跳过词缀集合）")
    end

    -- ---- ItemDropDatabase ----
    local dropdb = first_type({ { "Terraria.GameContent.ItemDropRules", "ItemDropDatabase" } })
    local rule = first_type({ { "Terraria.GameContent.ItemDropRules", "ItemDropRule" } })
    if dropdb and rule then
        drop_common = P.get_method(rule, "Common", 4)
        drop_register = P.get_method(dropdb, "RegisterToNPC", 2)
        local m = P.get_method(dropdb, "Populate", 0)
        if m and drop_common and drop_register then
            P.install_hook(m, { postfix = on_populate })
        else
            mod.warn("掉落注册符号不完整，跳过掉落表")
        end
    else
        mod.warn("找不到 ItemDropDatabase / ItemDropRule")
    end

    -- ---- Recipe ----
    -- 只针对发布版 LuaLoader 1.4.1（它没有 mod.recipe），因此走手动注册路径。
    setup_manual_recipes()

    mod.info("ForgottenItem-Refresh 初始化完成")
end

todo_list = { "setup" }
