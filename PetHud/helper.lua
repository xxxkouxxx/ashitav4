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
-- バフ一覧を詳細出力（マニューバー効果時間調査用）
-- /pethud buffcheck で呼び出す
--------------------------------------------------------------------------------
gFunctions.PrintBuffCheck = function()
    print('[PetHud] ===== Buff Check v2 =====');
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if player == nil then
        print('[PetHud] ERROR: GetPlayer() returned nil');
        print('[PetHud] ===========================');
        return;
    end

    -- ① まず slot 0 だけ pcall なしでテスト → API エラーを可視化
    local apiOk, apiErr = pcall(function()
        local v = player:GetStatusEffect(0);
        print(string.format('[PetHud] GetStatusEffect(0) raw = %s', tostring(v)));
    end);
    if not apiOk then
        print('[PetHud] GetStatusEffect() API ERROR: ' .. tostring(apiErr));
        -- 代替: Partyメモリ経由を試みる
        local ok2, err2 = pcall(function()
            local party = AshitaCore:GetMemoryManager():GetParty();
            print('[PetHud] --- Party buff fallback ---');
            for i = 0, 31 do
                local bid = party:GetMemberStatusEffect(0, i);
                if bid ~= nil and bid ~= 0 then
                    print(string.format('[PetHud]  party[0][%2d] id=%d', i, bid));
                end
            end
        end);
        if not ok2 then
            print('[PetHud] Party fallback ERROR: ' .. tostring(err2));
        end
        print('[PetHud] ===========================');
        return;
    end

    -- ② 全スロットスキャン（id≠0 のみ表示。0 が続く場合のみ先頭4スロット強制表示）
    local found = false;
    for i = 0, 31 do
        local effId = 0;
        local param  = 0;
        local timer  = 0;

        local ok, err = pcall(function()
            effId = player:GetStatusEffect(i);
            param = player:GetStatusEffectParam(i);
            timer = player:GetStatusEffectTimer(i);
        end);

        if not ok then
            print(string.format('[PetHud] pcall error at i=%d : %s', i, tostring(err)));
            break;
        end

        local showLine = (effId ~= nil and effId ~= 0);
        if not found and i < 4 then showLine = true; end  -- 先頭4スロットは0でも強制出力

        if showLine then
            if effId ~= 0 then found = true; end
            -- timer は 秒そのまま / 秒×60 の両方を表示
            print(string.format('[PetHud]  [%2d] id=%-5d param=%-6d timer=%d  (as-sec=%.1f  div60=%.1f)',
                i, effId or 0, param or 0, timer or 0,
                (timer or 0),
                (timer or 0) / 60.0));
        end
    end

    if not found then
        print('[PetHud] (アクティブなバフなし / 全スロット 0)');
    end
    print('[PetHud] ===========================');
end

return gFunctions;
