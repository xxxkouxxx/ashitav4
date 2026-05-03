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
--   compId=162: Soul Jump    (使用中 29.6s → 30s リキャスト確認)
--   compId=163: サポートジョブアビリティ（SAMメディテート等）
local JUMP_ID         = 158;
local HIGH_JUMP_ID    = 160;
local SUPER_JUMP_ID   = 159;
local SPIRIT_JUMP_ID  = 161;
local SOUL_JUMP_ID    = 162;

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

gFunctions.GetSoulJumpRecast = function()
    local data = gFunctions.GetAbilityTimerData(SOUL_JUMP_ID);
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

return gFunctions;
