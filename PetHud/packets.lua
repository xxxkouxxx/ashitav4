-- PetHUD パケット処理（petme packets.lua をベースに PUP 対応を追加）
local gConfig  = require('config');
local settings = require('settings');

local outPacketId = T{
    ACTION = 0x001A,
    CHECK  = 0x00DD,
}

local inPacketId = T{
    ACTION   = 0x0028,
    CHECK    = 0x0029,
    PET_SYNC = 0x0068,
    ZONE_IN  = 0x000A,
}

-- アウトゴーイングアクションパケットのカテゴリ
local CATEGORY_JOB_ABILITY = 0x09;

-- ジョブアビリティ ID（パケット中の actionId）
local abilId = T{
    -- BST
    CHARM       = 0x34,
    TAME        = 0x36,
    FIGHT       = 0x45,
    HEEL        = 0x46,
    LEAVE       = 0x47,
    SIC         = 0x48,
    STAY        = 0x49,
    REWARD      = 0x4E,
    CALL_BEAST  = 0x55,
    READY       = 0x163,
    -- PUP マニューバー（HorizonXI 実測値 Light=0x93 より逆算）
    FIRE_MNV    = 0x8D,
    ICE_MNV     = 0x8E,
    WIND_MNV    = 0x8F,
    EARTH_MNV   = 0x90,
    THUNDER_MNV = 0x91,
    WATER_MNV   = 0x92,
    LIGHT_MNV   = 0x93,
    DARK_MNV    = 0x94,
    -- PUP 特殊アビリティ（HorizonXI 実測値）
    OVERDRIVE   = 0x87,  -- オーバードライブ（実測確認済み）
    ACTIVATE    = 0x89,  -- Activate（要実機確認）
    -- 0x8A: オーバードライブ直前に発火を確認。Repair の可能性が高い。
    --       Deactivate（ペット解除）は パケット検出を廃止し、
    --       ペットエンティティ消滅タイマー（pethud.lua）で判定する。
    REPAIR_OR_DEACTIVATE = 0x8A,  -- 要実機確認（Repair or Deactivate）
}

-- マニューバー ID → gConfig.maneuverType のマッピング（HorizonXI 実測値）
local maneuverAbilToType = {
    [0x8D] = 1, -- FIRE
    [0x8E] = 2, -- ICE
    [0x8F] = 3, -- WIND
    [0x90] = 4, -- EARTH
    [0x91] = 5, -- LIGHTNING
    [0x92] = 6, -- WATER
    [0x93] = 7, -- LIGHT
    [0x94] = 8, -- DARK
}

-- Charm チェック処理用の状態管理
local charmStates = T{
    NONE        = 0,
    SENDING_PCK = 1,
    CHECK_PCK   = 2,
}
local charmState     = charmStates.NONE;
local charmTarget    = nil;
local charmTargetIdx = nil;

local gPackets = T{};

-- マニューバーリストに追加 / 更新
local lastManeuverTime  = {}  -- ギアスワップアドオンによるパケット再送対策
-- ギアスワップは precast / midcast / aftercast の 3フェーズで
-- 同じパケットを 2〜4 秒おきに複数回送ってくる場合がある。
-- 5 秒デバウンスでそれらをまとめて弾く。
local MANEUVER_DEBOUNCE = 5

local function addManeuver(mType)
    local now      = os.time();
    -- 設定値から継続時間を取得（デフォルト 60 秒）
    local duration = gConfig.params.settings.maneuverDuration[1] or 60;

    -- 同一タイプをデバウンス内に重複検出した場合はスキップ
    if lastManeuverTime[mType] ~= nil and (now - lastManeuverTime[mType]) < MANEUVER_DEBOUNCE then
        return;
    end
    lastManeuverTime[mType] = now;

    local list = gConfig.params.mobInfo.pupPet.maneuvers;

    -- 同一タイプが既にリストにある場合は expiry をリセット（重複追加しない）
    for _, entry in ipairs(list) do
        if entry.mType == mType then
            entry.expiry = now + duration;
            return;
        end
    end

    -- 新規追加（3スタック以上は一番古いものを削除）
    if #list >= 3 then
        table.remove(list, 1);
    end
    table.insert(list, { mType = mType, expiry = now + duration });
end

-- 期限切れマニューバーを掃除
local function cleanExpiredManeuvers()
    local now  = os.time();
    local list = gConfig.params.mobInfo.pupPet.maneuvers;
    for i = #list, 1, -1 do
        if list[i].expiry <= now then
            table.remove(list, i);
        end
    end
end

--------------------------------------------------------------------
gPackets.packet_out_cb = function(e)
    -- Check パケット送出（Charm 準備）
    if e.id == outPacketId.CHECK then
        if charmState == charmStates.SENDING_PCK then
            local pktdata = e.data:totable();
            local pckt = struct.pack('BBBBHBBHBBBBBB',
                pktdata[1], pktdata[2], pktdata[3], pktdata[4],
                charmTarget, pktdata[7], pktdata[8], charmTargetIdx,
                pktdata[11], pktdata[12], pktdata[13], pktdata[14],
                pktdata[15], pktdata[16]);
            e.data_modified = pckt;
            charmState = charmStates.CHECK_PCK;
        end
        return;
    end

    -- Action パケット送出
    if e.id == outPacketId.ACTION then
        local target     = struct.unpack('H', e.data, 0x04 + 0x01);
        local targetIdx  = struct.unpack('H', e.data, 0x08 + 0x01);
        local category   = struct.unpack('H', e.data, 0x0A + 0x01);
        local actionId   = struct.unpack('H', e.data, 0x0C + 0x01);

        if category == CATEGORY_JOB_ABILITY then
            -- BST: ペットなし時の Charm 開始
            if gConfig.params.mobInfo.petType == gConfig.petType.NONE then
                if actionId == abilId.CHARM then
                    charmState     = charmStates.SENDING_PCK;
                    charmTarget    = target;
                    charmTargetIdx = targetIdx;
                    AshitaCore:GetChatManager():QueueCommand(1, '/check');
                end
            end

            -- PUP: マニューバー使用
            local mType = maneuverAbilToType[actionId];
            if mType ~= nil then
                addManeuver(mType);
                return;
            end

            -- PUP: Activate でペットタイプを設定
            if actionId == abilId.ACTIVATE then
                local job = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob();
                if job == 18 then  -- PUP
                    gConfig.params.mobInfo.petType = gConfig.petType.PUPPET;
                end
            end

            -- 注意: Deactivate のアウトゴーイング検出は廃止。
            -- 0x8A は SP アビリティが使用する ID と判明したため。
            -- 実際の Deactivate は pethud.lua のペット消滅タイマーで処理する。
        end
    end
end

--------------------------------------------------------------------
gPackets.packet_in_cb = function(e)
    -- ゾーン移動: マニューバーをリセット
    if e.id == inPacketId.ZONE_IN then
        gConfig.params.mobInfo.pupPet.maneuvers = {};
        return;
    end

    -- Check 受信（BST Charm 用）
    if e.id == inPacketId.CHECK then
        local param1 = struct.unpack('l', e.data, 0x0C + 0x01);
        local param2 = struct.unpack('L', e.data, 0x10 + 0x01);
        local msg    = struct.unpack('H', e.data, 0x18 + 0x01);
        if charmState == charmStates.CHECK_PCK then
            if ((msg >= 0xAA and msg <= 0xB2) or (param2 >= 0x40 and param2 <= 0x47)) then
                e.blocked = true;
                gConfig.params.mobInfo.mobLevel = param1;
                -- charmUntil は petBSTCharm が計算するのでここでは設定しない
            end
            charmState = charmStates.NONE;
        end
        return;
    end

    -- Action 受信
    if e.id == inPacketId.ACTION then
        local actor    = struct.unpack('I', e.data, 0x05 + 0x01);
        local abilityID = bit.band(bit.rshift(struct.unpack('H', e.data, 0x0A + 0x01), 6), 0xffff);
        local playerSid = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0);

        if actor == playerSid then
            if abilityID == abilId.CHARM then
                gConfig.params.mobInfo.petType = gConfig.petType.CHARMED;

            elseif abilityID == abilId.CALL_BEAST then
                gConfig.params.mobInfo.petType = gConfig.petType.JUG;
                -- jugPet.newJug() は petBSTJug 側で処理

            elseif abilityID == abilId.STAY then
                if gConfig.params.mobInfo.bstPet.stayTicks == 0 then
                    gConfig.params.mobInfo.bstPet.stayTicks = os.time() + 20;
                end

            elseif abilityID == abilId.HEEL then
                gConfig.params.mobInfo.bstPet.stayTicks = 0;

            elseif abilityID == abilId.LEAVE then
                gConfig.params.mobInfo.petType = gConfig.petType.NONE;
                gConfig.params.mobInfo.bstPet.stayTicks = 0;
            end
        end

        -- ペットターゲット追跡（Action パケットのアクター＝ペット）
        local player = GetPlayerEntity();
        if player ~= nil and player.PetTargetIndex ~= 0 then
            local pet = GetEntity(player.PetTargetIndex);
            if pet ~= nil and actor == pet.ServerId then
                gConfig.params.mobInfo.petTarget =
                    ashita.bits.unpack_be(e.data_modified:totable(), 0x96, 0x20);
            end
        end
        return;
    end

    -- Pet Sync 受信（ペットターゲット更新）
    if e.id == inPacketId.PET_SYNC then
        local player = GetPlayerEntity();
        if player == nil then
            gConfig.params.mobInfo.petTarget = nil;
            return;
        end
        local ownerSid = struct.unpack('I', e.data_modified, 0x08 + 0x01);
        if ownerSid == player.ServerId then
            gConfig.params.mobInfo.petTarget = struct.unpack('I', e.data_modified, 0x14 + 0x01);
        end
        return;
    end
end

-- 毎フレーム呼び出し: 期限切れマニューバーを掃除
gPackets.tick = function()
    cleanExpiredManeuvers();
end

return gPackets;
