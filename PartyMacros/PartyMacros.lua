addon.name    = 'PartyMacros'
addon.author  = '7xxxk'
addon.version = '1.1.0'
addon.desc    = 'パーティコマンドマクロ & キーバインド管理'
addon.link    = 'https://github.com/AshitaXI/Ashita'

local imgui   = require('imgui')
local settings = require('settings')

-- ============================================================================
-- デフォルト設定（settings ライブラリで永続化）
-- ============================================================================
local default_settings = T{
    x          = 10,
    y          = 10,
    show_ui    = true,
    warp_delay = 10.0,
    -- 複数キャラへの送信コマンドプレフィックス
    -- ※ 'CorName' / 'BrdName' を実際のキャラクター名に変更してください
    ipc_all    = '/serv sendall ',
    ipc_cor    = '/serv send CorName ',
    ipc_brd    = '/serv send BrdName ',
    -- その他のコマンド
    follow_start = '/fm start',
    follow_stop  = '/fm stop',
    assist_cmd   = '/assist alltarget',
}

local cfg = T{}

-- ============================================================================
-- 状態管理・タイマー処理
-- ============================================================================
local delayed_commands = {}

-- 指定秒数後にコマンドを実行するためのキュー関数
local function queue_command(delay_seconds, command_str)
    table.insert(delayed_commands, {
        execute_time = os.clock() + delay_seconds,
        command      = command_str,
    })
    print(string.format('\31\200[\31\05PartyMacros\31\200]\30\01 %s 秒後に実行予約: %s', delay_seconds, command_str))
end

-- ============================================================================
-- キーバインド定義
-- ============================================================================
-- key: Ashita v4 のバインド構文 (^ = Ctrl, + = Shift, ! = Alt, # = Win)
local binds = {
    { key = '^+b', cmd = '/pmacro fast_move', desc = 'Follow開始 & 全員シュネデック' },
    { key = '^+c', cmd = '/pmacro stop',      desc = 'Follow停止' },
    { key = '^+d', cmd = '/pmacro schneck',   desc = '全員シュネデックリング' },
    { key = '^+e', cmd = '/pmacro bolters',   desc = 'COR: ボルターズロール' },
    { key = '^+f', cmd = '/pmacro mazurka',   desc = 'BRD: チョコボのマズルカ' },
    { key = '^+g', cmd = '/pmacro assist',    desc = 'ターゲットアシスト' },
    { key = '^+h', cmd = '/pmacro warp',      desc = 'Follow停止 & 全員デジョンリング（安全設計）' },
    { key = '^+i', cmd = '/pmacro mount',     desc = '全員マウント（ラプトル）' },
    { key = '^+j', cmd = '/pmacro dismount',  desc = '全員マウント解除' },
}

-- バインド構文 (^+b 等) を表示用文字列に変換する
-- ^ = Ctrl, + = Shift, ! = Alt, # = Win の順で先頭から解釈する
local function format_key(key)
    local modifiers = ''
    local MOD = { ['^'] = 'Ctrl+', ['+'] = 'Shift+', ['!'] = 'Alt+', ['#'] = 'Win+' }
    local i = 1
    while i <= #key do
        local c = key:sub(i, i)
        if MOD[c] then
            modifiers = modifiers .. MOD[c]
        else
            -- 残りは実際のキー文字
            return modifiers .. key:sub(i):upper()
        end
        i = i + 1
    end
    return modifiers
end

-- ============================================================================
-- イベントフック: ロード / アンロード
-- ============================================================================
ashita.events.register('load', 'partymacros_load', function()
    cfg = settings.load(default_settings)

    local chat = AshitaCore:GetChatManager()
    for _, b in ipairs(binds) do
        chat:QueueCommand(1, string.format('/bind %s %s', b.key, b.cmd))
    end
    print('\31\200[\31\05PartyMacros\31\200]\30\01 v' .. addon.version .. ' ロード完了。')
end)

ashita.events.register('unload', 'partymacros_unload', function()
    settings.save()

    -- 環境を汚さないようアンロード時にバインドを解除
    local chat = AshitaCore:GetChatManager()
    for _, b in ipairs(binds) do
        chat:QueueCommand(1, string.format('/unbind %s', b.key))
    end
end)

-- 設定変更コールバック
settings.register('settings', 'partymacros_settings', function(new_cfg)
    cfg = new_cfg
end)

-- ============================================================================
-- イベントフック: コマンド処理
-- ============================================================================
ashita.events.register('command', 'partymacros_command', function(e)
    local args = e.command:args()
    if args[1] ~= '/pmacro' then return end
    e.blocked = true

    local action = args[2]
    local chat   = AshitaCore:GetChatManager()

    if action == 'ui' then
        cfg.show_ui = not cfg.show_ui
        settings.save()

    elseif action == 'fast_move' then
        chat:QueueCommand(1, cfg.follow_start)
        chat:QueueCommand(1, cfg.ipc_all .. '/equip ring2 シュネデックリング')

    elseif action == 'stop' then
        chat:QueueCommand(1, cfg.follow_stop)

    elseif action == 'schneck' then
        chat:QueueCommand(1, cfg.ipc_all .. '/equip ring2 シュネデックリング')

    elseif action == 'bolters' then
        chat:QueueCommand(1, cfg.ipc_cor .. '/ja ボルターズロール <me>')

    elseif action == 'mazurka' then
        chat:QueueCommand(1, cfg.ipc_brd .. '/ma チョコボのマズルカ <me>')

    elseif action == 'assist' then
        chat:QueueCommand(1, cfg.assist_cmd)

    elseif action == 'warp' then
        -- 確実なデジョンリング実行フロー
        chat:QueueCommand(1, cfg.follow_stop)
        chat:QueueCommand(1, cfg.ipc_all .. '/equip ring2 デジョンリング')
        -- 設定した秒数（デフォルト10秒）経過後にアイテムを使用させる
        queue_command(cfg.warp_delay, cfg.ipc_all .. '/item デジョンリング <me>')

    elseif action == 'mount' then
        chat:QueueCommand(1, cfg.ipc_all .. '/mo ラプトル')

    elseif action == 'dismount' then
        chat:QueueCommand(1, cfg.ipc_all .. '/dismount')
    end
end)

-- ============================================================================
-- イベントフック: 毎フレーム処理（UI描画 & タイマー消化）
-- ============================================================================
ashita.events.register('d3d_present', 'partymacros_present', function()
    -- 1. 遅延コマンドのタイマー消化
    local now = os.clock()
    for i = #delayed_commands, 1, -1 do
        if now >= delayed_commands[i].execute_time then
            AshitaCore:GetChatManager():QueueCommand(1, delayed_commands[i].command)
            table.remove(delayed_commands, i)
        end
    end

    -- 2. ImGui ウィンドウ描画
    if not cfg.show_ui then return end

    local show_ref = { cfg.show_ui }
    imgui.SetNextWindowSize({ 400, 330 }, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowPos({ cfg.x, cfg.y }, ImGuiCond_FirstUseEver)

    if imgui.Begin('PartyMacros##partymacros', show_ref, ImGuiWindowFlags_None) then
        -- ウィンドウ位置を保存
        cfg.x, cfg.y = imgui.GetWindowPos()

        imgui.Text('現在有効なキーバインド一覧:')
        imgui.Separator()

        for _, b in ipairs(binds) do
            imgui.BulletText(string.format('%-20s : %s', format_key(b.key), b.desc))
        end

        imgui.Spacing()
        imgui.Separator()

        -- 実行待ちの遅延コマンドがある場合、カウントダウンを表示
        if #delayed_commands > 0 then
            imgui.TextColored({ 1.0, 0.5, 0.0, 1.0 }, '実行待ちのコマンドがあります:')
            for _, delayed in ipairs(delayed_commands) do
                local remain = math.max(0, delayed.execute_time - now)
                imgui.Text(string.format(' [%.1f秒後] %s', remain, delayed.command))
            end
        else
            imgui.TextColored({ 0.5, 1.0, 0.5, 1.0 }, '待機中のコマンドはありません。')
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Text('設定  (/pmacro ui でトグル)')

        -- warp_delay スライダー
        local delay_ref = { cfg.warp_delay }
        if imgui.SliderFloat('デジョン待機秒数##pm', delay_ref, 3.0, 30.0) then
            cfg.warp_delay = delay_ref[1]
            settings.save()
        end

        imgui.End()
    else
        imgui.End()
    end

    -- クローズボタンで閉じた場合に状態を保存
    if cfg.show_ui ~= show_ref[1] then
        cfg.show_ui = show_ref[1]
        settings.save()
    end
end)
