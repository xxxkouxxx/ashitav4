// localStorage操作モジュール
// キー形式: ff11_weekly_YYYY_WW

const Storage = (() => {
    const KEY_PREFIX = 'ff11_weekly_';

    // ISO 8601週番号を取得
    function getISOWeek(date) {
        const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        const dayNum = d.getUTCDay() || 7;
        d.setUTCDate(d.getUTCDate() + 4 - dayNum);
        const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
        return {
            year: d.getUTCFullYear(),
            week: Math.ceil((((d - yearStart) / 86400000) + 1) / 7)
        };
    }

    // 当週の年・週番号を返す
    function currentWeek() {
        return getISOWeek(new Date());
    }

    // 先週の年・週番号を返す
    function previousWeek() {
        const d = new Date();
        d.setDate(d.getDate() - 7);
        return getISOWeek(d);
    }

    // ストレージキーを生成
    function makeKey(year, week) {
        return `${KEY_PREFIX}${year}_${String(week).padStart(2, '0')}`;
    }

    // 週報データを保存
    function save(year, week, data) {
        const key = makeKey(year, week);
        data._savedAt = new Date().toISOString();
        localStorage.setItem(key, JSON.stringify(data));
    }

    // 週報データを読み込み
    function load(year, week) {
        const key = makeKey(year, week);
        const raw = localStorage.getItem(key);
        return raw ? JSON.parse(raw) : null;
    }

    // 保存済み一覧を新しい順で返す
    function list() {
        const entries = [];
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (!key.startsWith(KEY_PREFIX)) continue;
            const suffix = key.slice(KEY_PREFIX.length); // "YYYY_WW"
            const [year, week] = suffix.split('_').map(Number);
            const data = JSON.parse(localStorage.getItem(key));
            entries.push({ year, week, key, title: data.title || '', savedAt: data._savedAt });
        }
        entries.sort((a, b) => b.key.localeCompare(a.key));
        return entries;
    }

    // 前週データをベースに新規データを生成（土日固定・タイトルはクリア）
    function buildFromPrevious() {
        const prev = previousWeek();
        const prevData = load(prev.year, prev.week);
        if (!prevData) return null;
        const base = JSON.parse(JSON.stringify(prevData));
        // 変動項目をリセット
        base.title = '';
        base.summary = '';
        if (base.kpi) {
            base.kpi.forEach(row => { row.result = ''; row.verdict = ''; row.note = ''; });
        }
        if (base.log) {
            base.log.forEach(row => {
                if (!row.fixed) { row.hours = ''; row.style = ''; row.activity = ''; }
                else { row.hours = ''; } // 固定行は時間だけリセット
            });
        }
        if (base.kpt) {
            base.kpt.forEach(row => { row.content = ''; row.action = ''; });
        }
        if (base.nextGoals) base.nextGoals = ['', '', ''];
        delete base._savedAt;
        return base;
    }

    // 週報を削除
    function remove(year, week) {
        localStorage.removeItem(makeKey(year, week));
    }

    return { currentWeek, previousWeek, save, load, list, buildFromPrevious, remove };
})();
