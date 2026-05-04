-- ============================================================
-- PTChatLog.lua  v2.0.0
-- Ashita v4 アドオン - PT/ALチャット + 重要戦闘ログ 自動ファイル記録
--
-- 目的: ログを logs\ フォルダに自動保存し、Claude に貼り付けて作戦分析に使う
-- ImGui ウィンドウなし。パケット受信のたびに即時 flush。
--
-- コマンド:
--   /ptchatlog debug   デバッグモード切替（全モードIDをログ出力）
-- ============================================================

addon.name    = 'PTChatLog'
addon.author  = '7xxxk'
addon.version = '2.0.0'
addon.desc    = 'PT/ALチャット + 重要戦闘ログを logs\\ フォルダへ自動保存'

require('common')

-- ============================================================
-- Shift-JIS → UTF-8 変換（kernel32.dll 経由）
-- ffi.C は msvcrt のみ。MultiByteToWideChar は kernel32 なので
-- ffi.load('kernel32') を使う必要がある。
-- ============================================================
local ffi = nil
local k32 = nil
pcall(function() ffi = require('ffi') end)

if ffi then
    pcall(function()
        ffi.cdef([[
            int MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags,
                const char* lpMultiByteStr, int cbMultiByte,
                unsigned short* lpWideCharStr, int cchWideChar);
            int WideCharToMultiByte(unsigned int CodePage, unsigned long dwFlags,
                const unsigned short* lpWideCharStr, int cchWideChar,
                char* lpMultiByteStr, int cbMultiByte,
                const char* lpDefaultChar, int* lpUsedDefaultChar);
        ]])
    end)
    pcall(function() k32 = ffi.load('kernel32') end)
end

local CP_SJIS = 932
local CP_UTF8 = 65001

local function sjis_to_utf8(str)
    if not str or str == '' then return str end
    if not ffi or not k32 then return str end
    local ok, result = pcall(function()
        local wlen = k32.MultiByteToWideChar(CP_SJIS, 0, str, #str, nil, 0)
        if wlen <= 0 then return str end
        local wbuf = ffi.new('unsigned short[?]', wlen + 1)
        k32.MultiByteToWideChar(CP_SJIS, 0, str, #str, wbuf, wlen)
        local ulen = k32.WideCharToMultiByte(CP_UTF8, 0, wbuf, wlen, nil, 0, nil, nil)
        if ulen <= 0 then return str end
        local ubuf = ffi.new('char[?]', ulen + 1)
        k32.WideCharToMultiByte(CP_UTF8, 0, wbuf, wlen, ubuf, ulen, nil, nil)
        return ffi.string(ubuf, ulen)
    end)
    return ok and result or str
end

-- ============================================================
-- 定数・設定
-- ============================================================
local PACKET_CHAT   = 0x017
local MODE_PARTY    = 0x05
local MODE_ALLIANCE = 0x0D

-- 戦闘系記録対象モード ID（実機確認後に追加）
-- /ptchatlog debug を有効にして戦闘し、ログに出た mode=0xXX を確認して追加する
local BATTLE_MODES = {
    -- 0x1D,  -- 例: 死亡・倒れたメッセージ（要実測）
    -- 0x8E,  -- 例: システム通知（要実測）
}

-- ジョブ名テーブル
local JOB_NAMES = {
    [0]='None',[1]='WAR',[2]='MNK',[3]='WHM',[4]='BLM',
    [5]='RDM', [6]='THF',[7]='PLD',[8]='DRK',[9]='BST',
    [10]='BRD',[11]='RNG',[12]='SAM',[13]='NIN',[14]='DRG',
    [15]='SMN',[16]='BLU',[17]='COR',[18]='PUP',[19]='DNC',
    [20]='SCH',[21]='GEO',[22]='RUN',
}

-- ============================================================
-- 状態変数
-- ============================================================
local log_file   = nil
local debug_mode = false  -- /ptchatlog debug で切り替え

-- ============================================================
-- ヘルパー関数
-- ============================================================

-- NUL終端文字列をパケットデータから読み取る（byte_offset: 0-indexed）
local function read_string(data, byte_offset)
    local result = {}
    local i = byte_offset
    local limit = byte_offset + 256
    while i < limit do
        local b = ashita.bits.unpack_be(data, i * 8, 8)
        if not b or b == 0 then break end
        result[#result + 1] = string.char(b)
        i = i + 1
    end
    return table.concat(result)
end

-- パーティ情報文字列を生成
local function get_party_string()
    local members = {}
    local ok, party = pcall(function()
        return AshitaCore:GetMemoryManager():GetParty()
    end)
    if not ok or not party then return '(パーティ情報取得失敗)' end
    for i = 0, 17 do
        local name = party:GetMemberName(i)
        if name and name ~= '' then
            local main_id = party:GetMemberMainJob(i)
            local sub_id  = party:GetMemberSubJob(i)
            local main_str = JOB_NAMES[main_id] or '?'
            local sub_str  = JOB_NAMES[sub_id]  or '?'
            members[#members + 1] = string.format('%s(%s/%s)', name, main_str, sub_str)
        end
    end
    if #members == 0 then return '(ソロ)' end
    return table.concat(members, ', ')
end

-- ============================================================
-- ログファイル操作
-- ============================================================

local function open_log()
    local log_dir = AshitaCore:GetInstallPath() .. 'logs\\'
    local fname   = os.date('PTChatLog_%Y%m%d_%H%M%S.log')
    log_file = io.open(log_dir .. fname, 'w')
    if log_file then
        log_file:write('=== PTChatLog Session ===\n')
        log_file:write('Date:  ' .. os.date('%Y-%m-%d %H:%M:%S') .. '\n')
        log_file:write('Party: ' .. get_party_string() .. '\n')
        log_file:write('=========================\n\n')
        log_file:flush()
        print('[PTChatLog] ログ開始: logs\\' .. fname)
    else
        print('[PTChatLog] ERROR: ログファイルを開けませんでした: ' .. log_dir .. fname)
    end
end

local function close_log()
    if log_file then
        log_file:write('\n=== Session End: ' .. os.date('%H:%M:%S') .. ' ===\n')
        log_file:close()
        log_file = nil
    end
end

-- ============================================================
-- イベントハンドラ
-- ============================================================

ashita.events.register('load', 'ptchatlog_load', function()
    open_log()
end)

ashita.events.register('unload', 'ptchatlog_unload', function()
    close_log()
end)

ashita.events.register('command', 'ptchatlog_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    if not args[1]:any('/ptchatlog', '/ptcl') then return end
    e.blocked = true

    if args[2] == 'debug' then
        debug_mode = not debug_mode
        local state = debug_mode and 'ON（全モードIDをログ出力）' or 'OFF'
        print('[PTChatLog] デバッグモード: ' .. state)
    elseif args[2] == 'new' or args[2] == 'reopen' then
        -- 新しいログファイルを作成（ボス・コンテンツ区切りに使用）
        close_log()
        open_log()
    else
        print('[PTChatLog] コマンド:')
        print('  /ptchatlog new     新しいログファイルを作成（ボス区切り等）')
        print('  /ptchatlog debug   デバッグモード切替（モードID確認用）')
    end
end)

ashita.events.register('packet_in', 'ptchatlog_packet_in', function(e)
    if e.id ~= PACKET_CHAT then return end
    if not log_file then return end

    local mode    = ashita.bits.unpack_be(e.data_raw, 0x04 * 8, 8)
    local sender  = sjis_to_utf8(read_string(e.data_raw, 0x08))
    local message = sjis_to_utf8(read_string(e.data_raw, 0x18))

    if not message or message == '' then return end

    local type_str

    if mode == MODE_PARTY then
        type_str = 'PT'
    elseif mode == MODE_ALLIANCE then
        type_str = 'AL'
    else
        -- BATTLE_MODES チェック
        local is_battle = false
        for _, m in ipairs(BATTLE_MODES) do
            if m == mode then
                is_battle = true
                break
            end
        end

        if is_battle then
            type_str = 'SYS'
        elseif debug_mode then
            -- デバッグ: 全モードをログに出力してモードIDを確認できるようにする
            type_str = string.format('DEBUG[0x%02X]', mode)
        else
            return  -- 記録しない
        end
    end

    local line = string.format('[%s] %s %s: %s\n',
        os.date('%H:%M:%S'), type_str, sender, message)
    log_file:write(line)
    log_file:flush()
end)
