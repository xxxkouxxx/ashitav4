#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ff11_offline_export.py - ゲームを起動せずにFF11マクロ・装備セットをCSVにエクスポート

使い方:
    python ff11_offline_export.py              # 全キャラ処理
    python ff11_offline_export.py --list       # キャラ一覧のみ表示
    python ff11_offline_export.py --char 1587bd5
    python ff11_offline_export.py --inventory path\\to\\inventory.csv
    python ff11_offline_export.py --output C:\\other\\dir

アイテム名:
    export\\all_items.csv があれば自動使用（/exec dump_items で生成）
    なければ最新の *_inventory_*.csv を使用
"""

import os
import sys
import struct
import csv
import glob
import argparse
import winreg
import re
from datetime import datetime
from collections import Counter

OUTPUT_DIR = r'C:\Ashita-v4beta\export'

SLOT_NAMES = [
    'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Neck',
    'Earring1', 'Earring2', 'Body', 'Hands',
    'Ring1', 'Ring2', 'Back', 'Waist', 'Legs', 'Feet',
]


def get_pol_user_base():
    try:
        key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
            r'SOFTWARE\WOW6432Node\PlayOnline\InstallFolder')
        pol_path, _ = winreg.QueryValueEx(key, '0001')
        winreg.CloseKey(key)
        return os.path.join(pol_path, 'USER')
    except Exception as e:
        print(f'[ERROR] PlayOnlineパス取得失敗: {e}')
        sys.exit(1)


def try_extract_char_name(char_dir):
    msg_path = os.path.join(char_dir, 'ffxiusr.msg')
    if not os.path.exists(msg_path):
        return None
    try:
        with open(msg_path, 'rb') as f:
            data = f.read()
        matches = re.findall(b'[A-Z][a-z]{2,14}', data)
        if matches:
            name, _ = Counter(matches).most_common(1)[0]
            return name.decode('ascii')
    except Exception:
        pass
    return None


def list_characters(user_base):
    chars = []
    try:
        entries = os.listdir(user_base)
    except Exception as e:
        print(f'[ERROR] USERディレクトリ読み取り失敗: {e}')
        return chars

    for name in entries:
        if not re.fullmatch(r'[0-9a-fA-F]+', name):
            continue
        char_dir = os.path.join(user_base, name)
        if not os.path.isdir(char_dir):
            continue
        mcr_path = os.path.join(char_dir, 'mcr.dat')
        if not os.path.exists(mcr_path):
            continue
        mtime = datetime.fromtimestamp(os.path.getmtime(mcr_path))
        chars.append({
            'id':    name,
            'dir':   char_dir,
            'mtime': mtime,
            'name':  try_extract_char_name(char_dir),
        })

    chars.sort(key=lambda x: x['mtime'], reverse=True)
    return chars


def decode_sjis(data, offset, size):
    chunk = data[offset:offset + size]
    nul = chunk.find(b'\x00')
    if nul >= 0:
        chunk = chunk[:nul]
    if not chunk:
        return ''
    s = chunk.decode('shift_jis', errors='replace')
    # openpyxl が拒否するコントロール文字を除去（\t \n \r は残す）
    return re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', s)


def write_csv_utf8bom(filepath, rows):
    os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
    with open(filepath, 'w', encoding='utf-8-sig', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(rows)


def load_book_titles(char_dir):
    """mcr.ttl / mcr_2.ttl からブックタイトル辞書 {1:'WAR', 2:'MNK', ...} を返す"""
    titles = {}
    for ttl_file, start in [('mcr.ttl', 1), ('mcr_2.ttl', 21)]:
        path = os.path.join(char_dir, ttl_file)
        if not os.path.exists(path):
            continue
        with open(path, 'rb') as f:
            data = f.read()
        for i in range(20):
            chunk = data[24 + i * 16:24 + (i + 1) * 16]
            name  = chunk.split(b'\x00')[0].decode('shift_jis', errors='replace').strip()
            if name:
                titles[start + i] = name
    return titles


def export_macros(char_dir, output_path):
    """mcrN.dat (N=1〜) を全て読み、全マクロブックをCSVに出力する"""
    HEADER = 24
    ENTRY  = 380
    TITLE  = 14
    LINE   = 61

    book_titles = load_book_titles(char_dir)

    rows = [['ブックNo', 'ページNo', 'マクロNo', 'タイトル',
             '行1', '行2', '行3', '行4', '行5', '行6']]
    found = 0

    book_num = 1
    while True:
        mcr_path = os.path.join(char_dir, f'mcr{book_num}.dat')
        if not os.path.exists(mcr_path):
            break
        with open(mcr_path, 'rb') as f:
            data = f.read()

        book_label = book_titles.get(book_num, str(book_num))
        num = (len(data) - HEADER) // ENTRY
        for i in range(num):
            base  = HEADER + i * ENTRY
            title = decode_sjis(data, base, TITLE)
            lines = [decode_sjis(data, base + TITLE + j * LINE, LINE) for j in range(6)]
            if not title and not any(lines):
                continue
            page_no  = i // 10 + 1
            macro_no = i % 10 + 1
            rows.append([f'{book_num}:{book_label}', page_no, macro_no, title] + lines)
            found += 1

        book_num += 1

    if found == 0:
        print(f'  [WARN] マクロが1件も見つかりません（mcrN.dat が存在しないか全空）')

    write_csv_utf8bom(output_path, rows)
    return found


def _read_csv_dict(path, id_col, name_col):
    result = {}
    for enc in ('utf-8-sig', 'utf-8', 'cp932'):
        try:
            with open(path, encoding=enc, newline='') as f:
                for row in csv.DictReader(f):
                    try:
                        item_id = int(row.get(id_col, 0) or 0)
                        name    = row.get(name_col, '').strip()
                        if item_id and name:
                            result[item_id] = name
                    except (ValueError, KeyError):
                        pass
            break
        except (UnicodeDecodeError, Exception):
            continue
    return result


def load_item_names(output_dir, inventory_csv=None):
    """アイテムID→名前の辞書を構築。all_items.csv 優先、なければ inventory CSV"""
    all_items_path = os.path.join(output_dir, 'all_items.csv')
    if os.path.exists(all_items_path):
        names = _read_csv_dict(all_items_path, 'ID', 'Name')
        if names:
            print(f'アイテム名辞書: {len(names)}件 (all_items.csv)')
            return names

    if inventory_csv and os.path.exists(inventory_csv):
        names = _read_csv_dict(inventory_csv, 'アイテムID', 'アイテム名')
        print(f'アイテム名辞書: {len(names)}件 (inventory CSV)')
        return names

    print('[WARN] all_items.csv も inventory CSV もありません。ID表示になります。')
    print('       ゲーム内で /exec dump_items を実行して all_items.csv を生成してください。')
    return {}


def export_equipsets(char_dir, output_path, item_names):
    """es0.dat〜es9.dat の全ファイルを読み、全装備セット(最大200件)をCSVに出力する"""
    HEADER   = 24
    ENTRY    = 80
    NAME     = 16
    PADDING1 = 16
    SLOTS    = 16

    rows = [['セットNo', 'セット名'] + SLOT_NAMES]
    found = 0

    for file_idx in range(10):
        es_path = os.path.join(char_dir, f'es{file_idx}.dat')
        if not os.path.exists(es_path):
            continue
        with open(es_path, 'rb') as f:
            data = f.read()

        num = (len(data) - HEADER) // ENTRY
        for i in range(num):
            base     = HEADER + i * ENTRY
            set_name = decode_sjis(data, base, NAME)
            if not set_name:
                continue
            slot_vals = []
            for s in range(SLOTS):
                item_id = struct.unpack_from('<H', data, base + NAME + PADDING1 + s * 2)[0]
                slot_vals.append(item_names.get(item_id, f'ID:{item_id}') if item_id else '')
            global_set_no = file_idx * 20 + i + 1
            rows.append([global_set_no, set_name] + slot_vals)
            found += 1

    write_csv_utf8bom(output_path, rows)
    return found


def find_latest_inventory(output_dir):
    files = glob.glob(os.path.join(output_dir, '*_inventory_*.csv'))
    return max(files, key=os.path.getmtime) if files else None


def main():
    parser = argparse.ArgumentParser(
        description='FF11 マクロ・装備セットをゲーム外でCSVエクスポート')
    parser.add_argument('--list',      action='store_true', help='キャラ一覧のみ表示')
    parser.add_argument('--char',      help='処理するキャラのフォルダID (例: 1587bd5)')
    parser.add_argument('--inventory', help='アイテム名解決用 inventory CSV パス（省略時は自動検出）')
    parser.add_argument('--output',    default=OUTPUT_DIR, help='出力先ディレクトリ')
    args = parser.parse_args()

    user_base = get_pol_user_base()
    chars = list_characters(user_base)

    if not chars:
        print('[ERROR] mcr.dat を持つキャラフォルダが見つかりません')
        sys.exit(1)

    print(f'キャラ一覧 ({len(chars)}件):')
    for c in chars:
        label = c['name'] or '(不明)'
        print(f"  {c['id']}  {c['mtime'].strftime('%Y-%m-%d %H:%M')}  {label}")

    if args.list:
        return

    inv_csv    = args.inventory or find_latest_inventory(args.output)
    item_names = load_item_names(args.output, inv_csv)
    print()

    targets = chars
    if args.char:
        targets = [c for c in chars if c['id'].lower() == args.char.lower()]
        if not targets:
            print(f'[ERROR] --char {args.char} が見つかりません')
            sys.exit(1)

    os.makedirs(args.output, exist_ok=True)
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')

    for c in targets:
        label = c['name'] or c['id']
        print(f'--- {label} ({c["id"]}) ---')

        macros_path = os.path.join(args.output, f'{label}_macros_{ts}.csv')
        es_path_out = os.path.join(args.output, f'{label}_equipsets_{ts}.csv')

        n = export_macros(c['dir'], macros_path)
        print(f'  マクロ:     {n}件 -> {macros_path}')

        n = export_equipsets(c['dir'], es_path_out, item_names)
        print(f'  装備セット: {n}件 -> {es_path_out}')

    print('\n完了。ff11_excel.py で Excel 化できます。')
    print(f'例: python ff11_excel.py --char {args.char or "<char>"}')


if __name__ == '__main__':
    main()
