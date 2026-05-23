-- PetHUD 共通ヘルパー（petme helper.lua をベースに PUP 用機能を追加）
local gFunctions = T{};

--------------------------------------------------------------------------------
-- アビリティリキャストポインタ（tCrossBar / petme 由来）
--------------------------------------------------------------------------------
local AbilityRecastPointer = nil;
pcall(function()
    local ptr = ashita.memory.find('FFXiMain.dll', 0, '894124E9????????8B46??6A006A00508BCEE8', 0x19, 0);
    AbilityRecastPointer = ashita.memory.read_uint32(ptr);
end);

-- アビリティのリキャストデータを取得
gFunctions.GetAbilityTimerData = function(id)
    if AbilityRecastPointer == nil then
        return { Modifier = 0, Recast = 0 };
    end
    for i = 1, 31 do
        local compId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);
        if compId == id then
            return {
                Modifier = ashita.memory.read_int16(AbilityRecastPointer + (i * 8) + 4),
                Recast   = ashita.memory.read_uint32(AbilityRecastPointer + (i * 4) + 0xF8),
            };
        end
    end
    return { Modifier = 0, Recast = 0 };
end

-- Reward リキャストを秒単位で返す
gFunctions.GetRewardRecast = function()
    -- Reward == ability recast ID 103
    local recast   = 0;
    local modifier = 0;
    for i = 1, 31 do
        local compId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);
        if compId == 103 then
            modifier = ashita.memory.read_int16(AbilityRecastPointer + (i * 8) + 4);
            recast   = ashita.memory.read_uint32(AbilityRecastPointer + (i * 4) + 0xF8);
            break;
        end
    end
    return math.floor(recast / 60), modifier;
end

-- Ready リキャストを { 残チャージ数, 次チャージまでの秒数 } で返す
gFunctions.GetReadyRecast = function()
    -- Ready == ability recast ID 102
    local data = gFunctions.GetAbilityTimerData(102);
    local baseRecast       = 60 * (90 + data.Modifier);
    local chargeValue      = baseRecast / 3;
    local remainingCharges = math.floor((baseRecast - data.Recast) / chargeValue);
    local timeUntilNext    = math.fmod(data.Recast, chargeValue);
    return { remainingCharges, math.ceil(timeUntilNext / 60) };
end

-- Sic リキャストを秒単位で返す
gFunctions.GetSicRecast = function()
    local data = gFunctions.GetAbilityTimerData(102);
    return math.ceil(data.Recast / 60);
end

-- BP Rage リキャスト（SMN）
gFunctions.GetBPRageRecast = function()
    local data = gFunctions.GetAbilityTimerData(173);
    return math.ceil(data.Recast / 60);
end

-- BP Ward リキャスト（SMN）
gFunctions.GetBPWardRecast = function()
    local data = gFunctions.GetAbilityTimerData(174);
    return math.ceil(data.Recast / 60);
end

-- DRG Jump 系リキャスト（秒単位）
-- /pethud abiscan の結果より確認済み:
--   compId=157: Ancient Circle
--   compId=158: Jump         (使用中 32.6s → 30s リキャスト確認)
--   compId=159: Super Jump
--   compId=160: High Jump
--   compId=161: Spirit Jump
--   compId=162: Spirit Link  (実機確認: スピリットリンク使用で反応 ※旧記録はSoul Jumpと誤認)
--   compId=163: サポートジョブアビリティ（SAMメディテート等）
-- ⚠ Soul Jump の compId は未確定。/pethud abiscan で要確認
local JUMP_ID         = 158;
local HIGH_JUMP_ID    = 160;
local SUPER_JUMP_ID   = 159;
local SPIRIT_JUMP_ID  = 161;
local SPIRIT_LINK_ID  = 162;
-- local SOUL_JUMP_ID = ???; -- 要 abiscan 確認

gFunctions.GetJumpRecast = function()
    local data = gFunctions.GetAbilityTimerData(JUMP_ID);
    return math.ceil(data.Recast / 60);
end

gFunctions.GetHighJumpRecast = function()
    local data = gFunctions.GetAbilityTimerData(HIGH_JUMP_ID);
    return math.ceil(data.Recast / 60);
end

gFunctions.GetSuperJumpRecast = function()
    local data = gFunctions.GetAbilityTimerData(SUPER_JUMP_ID);
    return math.ceil(data.Recast / 60);
end

gFunctions.GetSpiritJumpRecast = function()
    local data = gFunctions.GetAbilityTimerData(SPIRIT_JUMP_ID);
    return math.ceil(data.Recast / 60);
end

gFunctions.GetSpiritLinkRecast = function()
    local data = gFunctions.GetAbilityTimerData(SPIRIT_LINK_ID);
    return math.ceil(data.Recast / 60);
end

-- Soul Jump リキャスト（compId 未確定のため一時無効）
-- gFunctions.GetSoulJumpRecast = function()
--     local data = gFunctions.GetAbilityTimerData(SOUL_JUMP_ID);
--     return math.ceil(data.Recast / 60);
-- end

-- GEO Jump 系リキャスト（秒単位）
-- ⚠ compId は実機で /pethud abiscan を実行して確認・更新してください（暫定値）
local FULL_CIRCLE_ID   = 175;
local RADIAL_ARCANA_ID = 176;
local LIFE_CYCLE_ID    = 177;
local BOLSTER_ID       = 178;

gFunctions.GetFullCircleRecast = function()
    local data = gFunctions.GetAbilityTimerData(FULL_CIRCLE_ID);
    return math.ceil(data.Recast / 60);
end

gFunctions.GetRadialArcanaRecast = function()
    local data = gFunctions.GetAbilityTimerData(RADIAL_ARCANA_ID);
    return math.ceil(data.Recast / 60);
end

gFunctions.GetLifeCycleRecast = function()
    local data = gFunctions.GetAbilityTimerData(LIFE_CYCLE_ID);
    return math.ceil(data.Recast / 60);
end

gFunctions.GetBolsterRecast = function()
    local data = gFunctions.GetAbilityTimerData(BOLSTER_ID);
    return math.ceil(data.Recast / 60);
end

-- サーバーIDからエンティティを検索（petinfo 由来）
gFunctions.GetEntityByServerId = function(sid)
    for x = 0, 2303 do
        local ent = GetEntity(x);
        if ent ~= nil and ent.ServerId == sid then
            return ent;
        end
    end
    return nil;
end

-- プレイヤーのバフリストに指定 ID が含まれるか確認
gFunctions.HasStatusEffect = function(effectId)
    local ok, result = pcall(function()
        for i = 0, 31 do
            local e = AshitaCore:GetMemoryManager():GetPlayer():GetStatusEffect(i);
            if e == effectId then return true; end
        end
        return false;
    end);
    if ok then return result else return false; end
end

--------------------------------------------------------------------------------
-- API プローブ: 正しいメソッド名を特定する
-- /pethud buffcheck で呼び出す
--------------------------------------------------------------------------------
gFunctions.PrintBuffCheck = function()
    print('[PetHud] ===== API Probe =====');
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    local party  = AshitaCore:GetMemoryManager():GetParty();

    -- player オブジェクトのバフ系メソッド候補を全列挙
    local playerMethods = {
        'GetStatusEffect',
        'GetStatusEffectParam',
        'GetStatusEffectTimer',
        'GetBuff',
        'GetBuffId',
        'GetBuffParam',
        'GetBuffTimer',
        'GetBuffs',
        'GetStatusEffects',
    };
    print('[PetHud] -- player methods --');
    for _, m in ipairs(playerMethods) do
        local ok, v = pcall(function() return player[m](player, 0); end);
        if ok then
            print(string.format('[PetHud]  player:%s(0) = %s  [OK]', m, tostring(v)));
        else
            -- nilかエラーか区別
            if player[m] == nil then
                print(string.format('[PetHud]  player:%s  = nil (no such method)', m));
            else
                print(string.format('[PetHud]  player:%s  = exists but call failed', m));
            end
        end
    end

    -- party オブジェクトのバフ系メソッド候補
    local partyMethods = {
        'GetMemberBuff',
        'GetMemberBuffId',
        'GetMemberBuffTimer',
        'GetMemberStatusEffect',
        'GetMemberStatusEffectParam',
        'GetMemberStatusEffectTimer',
        'GetMemberStatus',
    };
    print('[PetHud] -- party methods --');
    for _, m in ipairs(partyMethods) do
        local ok, v = pcall(function() return party[m](party, 0, 0); end);
        if ok then
            print(string.format('[PetHud]  party:%s(0,0) = %s  [OK]', m, tostring(v)));
        else
            if party[m] == nil then
                print(string.format('[PetHud]  party:%s  = nil (no such method)', m));
            else
                print(string.format('[PetHud]  party:%s  = exists but call failed', m));
            end
        end
    end

    -- 見つかったメソッドでバフスキャン（[OK] が出たメソッドを使う）
    -- GetMemberBuff が [OK] なら party 経由でスキャン
    if party.GetMemberBuff ~= nil then
        print('[PetHud] -- party:GetMemberBuff scan --');
        for i = 0, 31 do
            local ok, v = pcall(function() return party:GetMemberBuff(0, i); end);
            if ok and v ~= nil and v ~= 0 then
                -- タイマーも試みる
                local timerOk, t = pcall(function() return party:GetMemberBuffTimer(0, i); end);
                local tStr = timerOk and tostring(t) or '?';
                print(string.format('[PetHud]  buff[%2d] id=%d  timer=%s', i, v, tStr));
            end
        end
    end

    print('[PetHud] =====================');
end

return gFunctions;
