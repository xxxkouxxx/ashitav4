--[[
* macro_export - FF11 マクロ・装備セット・所持アイテム エクスポートアドオン
* Ashita v4 対応
*
* インストール先: C:\Ashita-v4beta\addons\macro_export\
* 使い方:
*   /addon load macro_export    -- アドオン読み込み
*   /me export                  -- 全データをCSV出力
*   /me macros                  -- マクロのみ出力
*   /me equipsets               -- 装備セットのみ出力
*   /me inventory               -- 所持アイテムのみ出力
--]]

addon.name    = 'macro_export'
addon.author  = 'macro_export'
addon.desc    = 'マクロ・装備セット・所持アイテムをCSVにエクスポートします'
addon.version = '1.1.0'

require('common')
local chat = require('chat')
local encoding = require('encoding')

-- 出力先ディレクトリ (Ashitaルート直下のexportフォルダ)
local EXPORT_DIR = AshitaCore:GetInstallPath() .. 'export\\'

-------------------------------------------------------------------------------
-- ユーティリティ
-------------------------------------------------------------------------------

-- ディレクトリが存在しなければ作成
local function ensure_dir(path)
    os.execute('mkdir "' .. path .. '" 2>nul')
end

-- CSV用エスケープ（カンマ・改行・ダブルクォートを含む場合はクォートで囲む）
local function csv_escape(val)
    if val == nil then return '' end
    val = tostring(val)
    if val:find('[,"\n\r]') then
        val = '"' .. val:gsub('"', '""') .. '"'
    end
    return val
end

-- ファイルに行を書き込む
local function write_csv(filepath, lines)
    local f = io.open(filepath, 'w')
    if not f then
        print(chat.header(addon.name) .. chat.error('Failed to open file: ' .. filepath))
        return false
    end
    -- BOM (UTF-8) を付けてExcelで文字化けしないようにする
    f:write('\xEF\xBB\xBF')
    for _, line in ipairs(lines) do
        f:write(line .. '\n')
    end
    f:close()
    return true
end

-- PlayOnline USER ディレクトリを取得 (FFI不使用・os.execute + io.open のみ)
local POL_USER_BASE = 'C:\\Program Files (x86)\\PlayOnline\\SquareEnix\\FINAL FANTASY XI\\USER\\'

local function find_pol_user_dir()
    local tmpfile = AshitaCore:GetInstallPath() .. 'poldir.tmp'
    os.execute('dir /b /ad /od "' .. POL_USER_BASE .. '" > "' .. tmpfile .. '" 2>nul')
    local found_dir = nil
    local f = io.open(tmpfile, 'r')
    if f then
        for line in f:lines() do
            local name = line:match('^([%x]+)$')
            if name then
                local candidate = POL_USER_BASE .. name .. '\\'
                local test = io.open(candidate .. 'mcr.dat', 'rb')
                if test then
                    test:close()
                    found_dir = candidate
                end
            end
        end
        f:close()
        os.remove(tmpfile)
    end
    return found_dir
end

-- バイナリ文字列からNull終端を除いてUTF-8に変換（タイトル・装備名など純粋ShiftJIS用）
local function bin_to_utf8(buf, offset, size)
    local s = buf:sub(offset + 1, offset + size)
    local nul = s:find('\0')
    if nul then s = s:sub(1, nul - 1) end
    if s == '' then return '' end
    s = s:gsub('[\x01-\x1F\x7F]', '')
    if s == '' then return '' end
    return encoding:ShiftJIS_To_UTF8(s)
end

-- FF11マクロ行デコード: FD 02 01 XX YY FD トークンを復号してUTF-8文字列を返す
local SLASH_CMDS = {
    [0x07] = '/attack', [0x09] = '/target',
    [0x0A] = '/assist', [0x15] = '/ja',
    [0x18] = '/ws',     [0x16] = '/ma',
    [0x1C] = '/item',
}
local function decode_macro_line(buf, offset, size)
    local s = buf:sub(offset + 1, offset + size)
    local nul = s:find('\0')
    if nul then s = s:sub(1, nul - 1) end
    if s == '' then return '' end

    local parts = {}
    local sjis  = {}
    local function flush()
        if #sjis > 0 then
            parts[#parts + 1] = encoding:ShiftJIS_To_UTF8(table.concat(sjis))
            sjis = {}
        end
    end

    local i = 1
    local len = #s
    while i <= len do
        local b = s:byte(i)
        -- '/' の直後が FD 02 01 0D コマンドトークンなら '/' をスキップ（トークン側で付与）
        if b == 0x2F and i + 5 <= len
            and s:byte(i+1) == 0xFD and s:byte(i+2) == 0x02
            and s:byte(i+3) == 0x01 and s:byte(i+4) == 0x0D then
            i = i + 1
        -- 6バイトトークン: FD 02 01 XX YY FD
        elseif b == 0xFD and i + 5 <= len
            and s:byte(i+1) == 0x02 and s:byte(i+2) == 0x01
            and s:byte(i+5) == 0xFD then
            flush()
            local cat = s:byte(i+3)
            local sub = s:byte(i+4)
            i = i + 6
            if cat == 0x0D then
                parts[#parts + 1] = SLASH_CMDS[sub] or string.format('/?:%02X', sub)
            elseif cat == 0x1F or cat == 0x21 or cat == 0x2A then
                local rman = AshitaCore:GetResourceManager()
                local id = sub
                if cat == 0x21 then id = sub + 512 end
                if cat == 0x2A then id = sub + 256 end
                local res  = rman:GetAbilityById(id)
                local name = res and res.Name and res.Name[1]
                if name and #name > 0 then
                    parts[#parts + 1] = encoding:ShiftJIS_To_UTF8(name)
                else
                    parts[#parts + 1] = string.format('[%s:%02X]',
                        cat == 0x1F and 'ja' or cat == 0x21 and 'ws' or 'mb', sub)
                end
            elseif cat == 0x01 then
                local vars = {[0x0C]='<tp>',[0x01]='<hp>',[0x02]='<mp>'}
                parts[#parts + 1] = vars[sub] or string.format('<var:%02X>', sub)
            end
            -- 不明カテゴリはスキップ
        elseif b == 0xFD then
            i = i + 1  -- 孤立FDをスキップ
        elseif (b >= 0x01 and b <= 0x1F) or b == 0x7F then
            i = i + 1  -- 制御文字をスキップ
        else
            sjis[#sjis + 1] = string.char(b)
            i = i + 1
        end
    end
    flush()
    return table.concat(parts)
end

-------------------------------------------------------------------------------
-- マクロ エクスポート
-------------------------------------------------------------------------------
-- PlayOnline USER ディレクトリの mcr.dat を読む
-- フォーマット: ヘッダー24バイト + 20エントリ × 380バイト
--   各エントリ: タイトル(14) + 6行 × 61バイト
-- 注意: mcr.dat はアクティブな20マクロのみ保持 (F1-F10 + Ctrl+F1-F10)

-- USER ディレクトリ内の mcr[数字].dat を数値順で列挙して返す
-- mcr.dat（アクティブ一時ファイル）は重複回避のため除外
local function find_macro_files(user_dir)
    local files = {}
    local tmpfile = AshitaCore:GetInstallPath() .. 'mcrlist.tmp'
    os.execute('dir /b "' .. user_dir .. 'mcr*.dat" > "' .. tmpfile .. '" 2>nul')
    local ft = io.open(tmpfile, 'r')
    if ft then
        for fname in ft:lines() do
            fname = fname:match('^(.-)%s*$')
            -- mcr[数字].dat のみ（mcr.dat / mcr.sys / smcr.dat 等は除外）
            local num_str = fname:match('^mcr(%d+)%.dat$')
            if num_str then
                local fpath = user_dir .. fname
                local tf = io.open(fpath, 'rb')
                if tf then
                    tf:close()
                    table.insert(files, { path = fpath, label = 'p' .. num_str, num = tonumber(num_str) })
                end
            end
        end
        ft:close()
        os.remove(tmpfile)
    end
    -- 数値順ソート（dir /b はアルファベット順なので mcr10 > mcr2 になる）
    table.sort(files, function(a, b) return a.num < b.num end)
    return files
end

local function export_macros(char_name, out_path)
    local user_dir = find_pol_user_dir()
    if not user_dir then
        print(chat.header(addon.name) .. chat.error('PlayOnline USER directory not found.'))
        return
    end

    local macro_files = find_macro_files(user_dir)
    if #macro_files == 0 then
        print(chat.header(addon.name) .. chat.error('No mcr*.dat files found: ' .. user_dir))
        return
    end

    local HEADER_SIZE = 24
    local ENTRY_SIZE  = 380
    local ENTRY_HDR   = 4     -- エントリ先頭の非テキストヘッダー
    local LINE_SIZE   = 61    -- 1行のバイト数
    local LINES_PER   = 6
    local TITLE_OFF   = 370   -- タイトルはエントリ末尾 (4 + 6*61 = 370)
    local TITLE_SIZE  = 10    -- タイトルフィールドのバイト数

    -- ファイル列を追加（ページNo → ファイル識別子に変更）
    local lines_out = {}
    table.insert(lines_out, table.concat(
        {'ファイル', 'ブックNo', 'マクロNo', 'タイトル',
         '行1', '行2', '行3', '行4', '行5', '行6'}, ','))

    local found = 0
    for _, file_info in ipairs(macro_files) do
        local f = io.open(file_info.path, 'rb')
        if not f then goto continue end
        local data = f:read('*all')
        f:close()

        local num_entries = math.floor((#data - HEADER_SIZE) / ENTRY_SIZE)
        for i = 0, num_entries - 1 do
            local base_off = HEADER_SIZE + i * ENTRY_SIZE
            local title = bin_to_utf8(data, base_off + TITLE_OFF, TITLE_SIZE)
            local body  = {}
            for j = 0, LINES_PER - 1 do
                local loff = base_off + ENTRY_HDR + j * LINE_SIZE
                table.insert(body, decode_macro_line(data, loff, LINE_SIZE))
            end
            -- 空エントリはスキップ
            local is_empty = (title == '')
            if is_empty then
                for _, b in ipairs(body) do if b ~= '' then is_empty = false; break end end
            end
            if not is_empty then
                -- 前10エントリ=通常マクロ(ブック1)、後10エントリ=Ctrlマクロ(ブック2)
                local book_no  = math.floor(i / 10) + 1
                local macro_no = (i % 10) + 1
                local row = {
                    csv_escape(file_info.label),
                    csv_escape(book_no),
                    csv_escape(macro_no),
                    csv_escape(title),
                }
                for _, b in ipairs(body) do table.insert(row, csv_escape(b)) end
                table.insert(lines_out, table.concat(row, ','))
                found = found + 1
            end
        end
        ::continue::
    end

    if write_csv(out_path, lines_out) then
        print(chat.header(addon.name) .. string.format(
            'Macros exported: %d entries (%d files) -> %s',
            found, #macro_files, out_path))
    end
end

-------------------------------------------------------------------------------
-- 装備セット エクスポート
-------------------------------------------------------------------------------
-- es0.dat ～ es9.dat を順番に読む（各ファイル20セット、計200セット）
-- フォーマット: ヘッダー24バイト + 20エントリ × 80バイト
--   各エントリ: 名前(16) + パディング(16) + 16スロット × 2バイトID + パディング(16)

local SLOT_NAMES = {
    [0]  = 'Main',     [1]  = 'Sub',      [2]  = 'Range',
    [3]  = 'Ammo',     [4]  = 'Head',     [5]  = 'Body',
    [6]  = 'Hands',    [7]  = 'Legs',     [8]  = 'Feet',
    [9]  = 'Neck',     [10] = 'Waist',    [11] = 'Earring1',
    [12] = 'Earring2', [13] = 'Ring1',    [14] = 'Ring2',
    [15] = 'Back',
}

local function export_equipsets(char_name, out_path)
    local user_dir = find_pol_user_dir()
    if not user_dir then
        print(chat.header(addon.name) .. chat.error('PlayOnline USER directory not found.'))
        return
    end

    local HEADER_SIZE = 24
    local ENTRY_SIZE  = 80
    local NAME_SIZE   = 16   -- セット名フィールド
    local NUM_SLOTS   = 16   -- スロット数 (各4バイト: item_id 2B + extra 2B)
    local rman = AshitaCore:GetResourceManager()

    local header = {'セットNo', 'セット名'}
    for i = 0, NUM_SLOTS - 1 do
        table.insert(header, SLOT_NAMES[i] or ('Slot' .. i))
    end
    local lines_out = { table.concat(header, ',') }

    local found      = 0
    local set_index  = 0   -- ゲーム内セット番号（es0=1-20, es1=21-40, ...）

    for file_num = 0, 9 do
        local es_path = user_dir .. 'es' .. file_num .. '.dat'
        local f = io.open(es_path, 'rb')
        if not f then break end   -- ファイルがなければ終了
        local data = f:read('*all')
        f:close()

        local num_entries = math.floor((#data - HEADER_SIZE) / ENTRY_SIZE)
        for i = 0, num_entries - 1 do
            set_index = set_index + 1
            local base_off = HEADER_SIZE + i * ENTRY_SIZE
            local set_name = bin_to_utf8(data, base_off, NAME_SIZE)
            -- アイテムID: 16スロット × 2バイト
            local items = {}
            for s = 0, NUM_SLOTS - 1 do
                local id_off  = base_off + NAME_SIZE + s * 4
                local lo      = data:byte(id_off + 1) or 0
                local hi      = data:byte(id_off + 2) or 0
                local item_id = lo + hi * 256
                if item_id > 0 and item_id < 65535 then
                    local res  = rman:GetItemById(item_id)
                    local raw  = (res and res.Name and res.Name[1]) or ('ID:' .. item_id)
                    items[s]   = encoding:ShiftJIS_To_UTF8(raw)
                else
                    items[s] = ''
                end
            end
            if set_name ~= '' then
                local row = {csv_escape(set_index), csv_escape(set_name)}
                for s = 0, NUM_SLOTS - 1 do table.insert(row, csv_escape(items[s] or '')) end
                table.insert(lines_out, table.concat(row, ','))
                found = found + 1
            end
        end
    end

    if found == 0 then
        print(chat.header(addon.name) .. chat.error('No equipment sets found: ' .. user_dir))
        return
    end

    if write_csv(out_path, lines_out) then
        print(chat.header(addon.name) .. string.format(
            'Equipsets exported: %d entries (es0-es9.dat) -> %s', found, out_path))
    end
end

-------------------------------------------------------------------------------
-- 所持アイテム エクスポート
-------------------------------------------------------------------------------
-- Ashita v4 API でインベントリ取得
-- バッグ種別: 0=Inventory, 1=Safe, 2=Storage, 3=Temporary,
--             4=Locker, 5=Satchel, 6=Sack, 7=Case, 8=Wardrobe,
--             9=Safe2, 10=Wardrobe2, ..., 13=Wardrobe5

local BAG_NAMES = {
    [0]  = 'Inventory',  [1]  = 'Safe',       [2]  = 'Storage',
    [3]  = 'Temporary',  [4]  = 'Locker',      [5]  = 'Satchel',
    [6]  = 'Sack',       [7]  = 'Case',        [8]  = 'Wardrobe1',
    [9]  = 'Safe2',      [10] = 'Wardrobe2',   [11] = 'Wardrobe3',
    [12] = 'Wardrobe4',  [13] = 'Wardrobe5',
}

local function export_inventory(out_path)
    local inv  = AshitaCore:GetMemoryManager():GetInventory()
    local rman = AshitaCore:GetResourceManager()

    local lines = { table.concat({'バッグ', 'スロット', 'アイテムID', 'アイテム名', '個数', 'オーグメント'}, ',') }
    local found = 0

    for bag_id, bag_name in pairs(BAG_NAMES) do
        local count = inv:GetContainerCountMax(bag_id)
        for slot = 0, count - 1 do
            local item = inv:GetContainerItem(bag_id, slot)
            if item and item.Id and item.Id ~= 0 and item.Id ~= 65535 then
                local res  = rman:GetItemById(item.Id)
                -- res.Name[1] は Shift-JIS バイト列なので UTF-8 に変換
                local raw  = (res and res.Name and res.Name[1]) or ('ID:' .. item.Id)
                local name = encoding:ShiftJIS_To_UTF8(raw)
                -- オーグメント情報 (存在する場合)
                local augstr = ''
                if item.Augments then
                    local augs = {}
                    for _, aug in ipairs(item.Augments) do
                        if aug ~= 0 then
                            table.insert(augs, tostring(aug))
                        end
                    end
                    augstr = table.concat(augs, '/')
                end
                local row = {
                    csv_escape(bag_name),
                    csv_escape(slot),
                    csv_escape(item.Id),
                    csv_escape(name),
                    csv_escape(item.Count or 1),
                    csv_escape(augstr),
                }
                table.insert(lines, table.concat(row, ','))
                found = found + 1
            end
        end
    end

    if write_csv(out_path, lines) then
        print(chat.header(addon.name) .. string.format(
            'Inventory exported: %d entries -> %s', found, out_path))
    end
end

-------------------------------------------------------------------------------
-- メインコマンドハンドラ
-------------------------------------------------------------------------------
ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/me' then
        return
    end

    local sub = (args[2] or 'export'):lower()
    if sub ~= 'export' and sub ~= 'macros' and sub ~= 'equipsets' and sub ~= 'inventory' then
        return
    end

    e.blocked = true

    -- キャラ名取得
    local char_name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) or 'Unknown'

    ensure_dir(EXPORT_DIR)

    local ts = os.date('%Y%m%d_%H%M%S')
    print(chat.header(addon.name) .. 'Export started: ' .. char_name)

    if sub == 'export' or sub == 'macros' then
        local path = EXPORT_DIR .. char_name .. '_macros_' .. ts .. '.csv'
        export_macros(char_name, path)
    end

    if sub == 'export' or sub == 'equipsets' then
        local path = EXPORT_DIR .. char_name .. '_equipsets_' .. ts .. '.csv'
        export_equipsets(char_name, path)
    end

    if sub == 'export' or sub == 'inventory' then
        local path = EXPORT_DIR .. char_name .. '_inventory_' .. ts .. '.csv'
        export_inventory(path)
    end

    print(chat.header(addon.name) .. 'Output: ' .. EXPORT_DIR)
end)

-- ロード完了メッセージ
ashita.events.register('load', 'load_cb', function()
    print(chat.header(addon.name) .. 'Loaded. Use /me export to start export.')
end)
