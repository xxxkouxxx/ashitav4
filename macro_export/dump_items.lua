-- dump_items.lua - FF11 全アイテム名をCSVに出力する1回限りのスクリプト
-- 使い方: ゲーム内で /exec dump_items

local ffi = require('ffi')
pcall(ffi.cdef, [[
    int MultiByteToWideChar(uint32_t CodePage, uint32_t dwFlags, char* lpMultiByteStr, int cbMultiByte, wchar_t* lpWideCharStr, int32_t cchWideChar);
    int WideCharToMultiByte(uint32_t CodePage, uint32_t dwFlags, wchar_t* lpWideCharStr, int32_t cchWideChar, char* lpMultiByteStr, int32_t cbMultiByte, char lpDefaultChar);
]])

local function sjis_to_utf8(s)
    local buf  = ffi.new('char[4096]')
    local wbuf = ffi.new('wchar_t[4096]')
    ffi.copy(buf, s)
    ffi.C.MultiByteToWideChar(932, 0, buf, -1, wbuf, 4096)
    ffi.C.WideCharToMultiByte(65001, 0, wbuf, -1, buf, 4096, 0)
    return ffi.string(buf)
end

local out_path = AshitaCore:GetInstallPath() .. 'export\\all_items.csv'
local f = io.open(out_path, 'w')
if not f then
    print('[dump_items] ファイルを開けません: ' .. out_path)
    return
end

f:write('\xEF\xBB\xBF')  -- UTF-8 BOM
f:write('ID,Name\n')

local rman  = AshitaCore:GetResourceManager()
local count = 0
for id = 1, 65534 do
    local r = rman:GetItemById(id)
    if r and r.Name and r.Name[1] then
        local raw = r.Name[1]
        local nul = raw:find('\0')
        if nul then raw = raw:sub(1, nul - 1) end
        if raw ~= '' then
            local name = sjis_to_utf8(raw)
            -- カンマを含む名前はクォートで囲む
            if name:find(',') then name = '"' .. name .. '"' end
            f:write(id .. ',' .. name .. '\n')
            count = count + 1
        end
    end
end

f:close()
print('[dump_items] 完了: ' .. count .. '件 -> ' .. out_path)
