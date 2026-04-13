addon.name    = 'PartyMacros'
addon.author  = '7xxxk'
addon.version = '1.2.0'
addon.desc    = 'パーティコマンドマクロ & キーバインド管理'

require('common')

-- ============================================================================
-- Shift-JIS バイト列定義
-- UTF-8 で書かれた Lua ファイルから QueueCommand に日本語を渡すと
-- FFXI（Shift-JIS）側で文字化けするため、バイト列で直接定義する
-- ============================================================================
local SJ = {
    -- リング装備
    schneck  = string.char(  -- シュネデックリング
        0x83,0x56, 0x83,0x85, 0x83,0x6C, 0x83,0x66, 0x83,0x62,
        0x83,0x4E, 0x83,0x8A, 0x83,0x93, 0x83,0x4F),
    dezon    = string.char(  -- デジョンリング
        0x83,0x66, 0x83,0x57, 0x83,0x87, 0x83,0x93,
        0x83,0x8A, 0x83,0x93, 0x83,0x4F),
    -- マウント
    raptor   = string.char(  -- ラプトル
        0x83,0x89, 0x83,0x76, 0x83,0x67, 0x83,0x8B),
    -- アビリティ・魔法名
    bolters  = string.char(  -- ボルターズロール
        0x83,0x7B, 0x83,0x8B, 0x83,0x5E, 0x83,0x9C,
        0x83,0x59, 0x83,0x8D, 0x83,0x9C, 0x83,0x8B),
    mazurka  = string.char(  -- チョコボのマズルカ
        0x83,0x60, 0x83,0x87, 0x83,0x52, 0x83,0x7B,
        0x82,0xCC, 0x83,0x7D, 0x83,0x59, 0x83,0x8B, 0x83,0x4A),
}

-- ============================================================================
-- ユーザー設定（実際の環境に合わせて変更してください）
-- /serv プラグイン必須: https://github.com/ThornyFFXI/Servbot
-- ============================================================================
local config = {
    ipc_all      = '/serv sendall ',      -- 全員へ送信
    ipc_cor      = '/serv send CorName ', -- ← COR キャラ名に変更
    ipc_brd      = '/serv send BrdName ', -- ← BRD キャラ名に変更
    follow_start = '/fm start',
    follow_stop  = '/fm stop',
    assist_cmd   = '/assist alltarget',
    warp_delay   = 10.0,                  -- デジョンリング使用までの待機秒数
}

-- ============================================================================
-- 遅延コマンド管理（warpの装備→使用ディレイ用）
-- ============================================================================
local delayed_cmds = {}

local function queue_delayed(delay_sec, cmd)
    table.insert(delayed_cmds, {
        execute_at = os.clock() + delay_sec,
        command    = cmd,
    })
    -- print は ASCII のみ使用（日本語 UTF-8 は Ashita で文字化け＋バイナリ混入するため）
    print('[PartyMacros] queued in ' .. delay_sec .. 's')
end

-- ============================================================================
-- キーバインド定義（^ = Ctrl, + = Shift, ! = Alt）
-- ============================================================================
local binds = {
    { key = '^+b', cmd = '/pmacro fast_move', desc = 'Follow開始 & 全員シュネデック' },
    { key = '^+c', cmd = '/pmacro stop',      desc = 'Follow停止'                  },
    { key = '^+d', cmd = '/pmacro schneck',   desc = '全員シュネデックリング装備'   },
    { key = '^+e', cmd = '/pmacro bolters',   desc = 'COR: ボルターズロール'        },
    { key = '^+f', cmd = '/pmacro mazurka',   desc = 'BRD: チョコボのマズルカ'      },
    { key = '^+g', cmd = '/pmacro assist',    desc = 'ターゲットアシスト'           },
    { key = '^+h', cmd = '/pmacro warp',      desc = '全員デジョンリング（安全）'   },
    { key = '^+i', cmd = '/pmacro mount',     desc = '全員マウント（ラプトル）'     },
    { key = '^+j', cmd = '/pmacro dismount',  desc = '全員マウント解除'             },
}

-- ============================================================================
-- ロード / アンロード
-- ============================================================================
ashita.events.register('load', 'partymacros_load', function()
    local chat = AshitaCore:GetChatManager()
    for _, b in ipairs(binds) do
        chat:QueueCommand(1, '/bind ' .. b.key .. ' ' .. b.cmd)
    end
    print('[PartyMacros] v' .. addon.version .. ' loaded.')
end)

ashita.events.register('unload', 'partymacros_unload', function()
    local chat = AshitaCore:GetChatManager()
    for _, b in ipairs(binds) do
        chat:QueueCommand(1, '/unbind ' .. b.key)
    end
end)

-- ============================================================================
-- コマンド処理（/pmacro <action>）
-- ============================================================================
ashita.events.register('command', 'partymacros_command', function(e)
    -- バインド経由では e.command が string 以外で来ることがあるためガード
    if e == nil or type(e.command) ~= 'string' then return end
    local args = e.command:args()
    if #args == 0 or args[1] ~= '/pmacro' then return end
    e.blocked = true

    local action = args[2]
    local chat   = AshitaCore:GetChatManager()

    if action == 'fast_move' then
        -- Follow開始 → 自分＋全員シュネデックリング装備
        chat:QueueCommand(1, config.follow_start)
        chat:QueueCommand(1, '/equip ring2 ' .. SJ.schneck)                      -- 自分
        chat:QueueCommand(1, config.ipc_all .. '/equip ring2 ' .. SJ.schneck)    -- 他全員

    elseif action == 'stop' then
        -- Follow停止
        chat:QueueCommand(1, config.follow_stop)

    elseif action == 'schneck' then
        -- 自分＋全員シュネデックリング装備
        chat:QueueCommand(1, '/equip ring2 ' .. SJ.schneck)                      -- 自分
        chat:QueueCommand(1, config.ipc_all .. '/equip ring2 ' .. SJ.schneck)    -- 他全員

    elseif action == 'bolters' then
        -- COR: ボルターズロール（COR キャラへ送信）
        chat:QueueCommand(1, config.ipc_cor .. '/ja ' .. SJ.bolters .. ' <me>')

    elseif action == 'mazurka' then
        -- BRD: チョコボのマズルカ（BRD キャラへ送信）
        chat:QueueCommand(1, config.ipc_brd .. '/ma ' .. SJ.mazurka .. ' <me>')

    elseif action == 'assist' then
        -- ターゲットアシスト
        chat:QueueCommand(1, config.assist_cmd)

    elseif action == 'warp' then
        -- Follow停止 → 自分＋全員デジョンリング装備 → N秒後に使用
        chat:QueueCommand(1, config.follow_stop)
        chat:QueueCommand(1, '/equip ring2 ' .. SJ.dezon)                        -- 自分
        chat:QueueCommand(1, config.ipc_all .. '/equip ring2 ' .. SJ.dezon)      -- 他全員
        queue_delayed(config.warp_delay, '/item ' .. SJ.dezon .. ' <me>')        -- 自分（遅延）
        queue_delayed(config.warp_delay, config.ipc_all .. '/item ' .. SJ.dezon .. ' <me>') -- 他全員（遅延）

    elseif action == 'mount' then
        -- 自分＋全員ラプトルマウント
        chat:QueueCommand(1, '/mo ' .. SJ.raptor)                                -- 自分
        chat:QueueCommand(1, config.ipc_all .. '/mo ' .. SJ.raptor)              -- 他全員

    elseif action == 'dismount' then
        -- 自分＋全員マウント解除
        chat:QueueCommand(1, '/dismount')                                         -- 自分
        chat:QueueCommand(1, config.ipc_all .. '/dismount')                      -- 他全員
    end
end)

-- ============================================================================
-- 毎フレーム処理（遅延コマンドのタイマー消化）
-- ============================================================================
ashita.events.register('d3d_present', 'partymacros_present', function()
    if #delayed_cmds == 0 then return end
    local now = os.clock()
    for i = #delayed_cmds, 1, -1 do
        if now >= delayed_cmds[i].execute_at then
            AshitaCore:GetChatManager():QueueCommand(1, delayed_cmds[i].command)
            table.remove(delayed_cmds, i)
        end
    end
end)
