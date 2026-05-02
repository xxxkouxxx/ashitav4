// Noteマークダウンテキスト生成モジュール（v2テンプレート準拠）

const Generator = (() => {
    const TAGS_FULL  = '#FF11 #FFXI #ファイナルファンタジーXI #週報 #オデシー #ソーティ #ヴァナディール #装備合成';
    const TAGS_DIFF  = '#FF11 #FFXI #週報 #オデシー #ヴァナディール';
    const SEP_FULL   = '━━━━━━━━━━━━━━━━━━━━';
    const SEP_SHORT  = '━━━';

    // 判定テキスト変換
    function verdictEmoji(v) {
        if (v === 'ok')   return '🟢達成';
        if (v === 'cont') return '🟡継続中';
        if (v === 'ng')   return '🔴未達';
        return '—';
    }

    // 稼働時間合計
    function calcTotal(log) {
        const total = (log || []).reduce((s, r) => s + (parseFloat(r.hours) || 0), 0);
        return Math.round(total * 10) / 10;
    }

    // 全文版（v2 tpl-full 準拠）
    function generateFullText(data) {
        const L = [];
        const totalH = calcTotal(data.log);

        L.push(data.title || '【FF11週報】〇月 第〇週');
        L.push('');
        L.push(data.summary || '※今週のハイライト・総評を1〜2行で記入');
        L.push('');
        L.push(`⏱ 総プレイ時間：約${totalH}時間`);
        L.push('');
        L.push(SEP_FULL);
        L.push('① 今週の目標達成度・KPI');
        L.push(SEP_FULL);
        L.push('');
        L.push('| 項目 | 目標 | 結果・実績 | 判定 | 備考 |');
        L.push('|------|------|----------|------|------|');
        (data.kpi || []).forEach(r => {
            L.push(`| ${r.label} | ${r.goal || '—'} | ${r.result || '—'} | ${verdictEmoji(r.verdict)} | ${r.note || '—'} |`);
        });
        L.push('');
        L.push(SEP_FULL);
        L.push('② 稼働ログ（曜日別ダイジェスト）');
        L.push(SEP_FULL);
        L.push('');
        L.push(`今週の総プレイ時間：約${totalH}時間`);
        L.push('');
        L.push('| 曜日 | 時間 | スタイル | 主な活動内容 |');
        L.push('|------|------|---------|------------|');
        (data.log || []).forEach(r => {
            L.push(`| ${r.day} | ${r.hours || '—'}h | ${r.style || '—'} | ${r.activity || '—'} |`);
        });
        L.push('');
        L.push(SEP_FULL);
        L.push('③ 今週の振り返り（KPT）');
        L.push(SEP_FULL);
        L.push('');

        const keeps    = (data.kpt || []).filter(r => r.type === 'Keep');
        const problems = (data.kpt || []).filter(r => r.type === 'Problem');
        const tries    = (data.kpt || []).filter(r => r.type === 'Try');

        L.push('■ Keep（良かった点）');
        keeps.forEach(r => L.push(`✅ ${r.content || '〇〇'}　→ ${r.action || '来週も継続'}`));
        L.push('');
        L.push('■ Problem（反省点）');
        problems.forEach(r => L.push(`❌ ${r.content || '〇〇'}　→ ${r.action || 'Tryへ↓'}`));
        L.push('');
        L.push('■ Try（来週試すこと）');
        tries.forEach(r => L.push(`💡 ${r.content || '〇〇'}`));
        L.push('');
        L.push(SEP_FULL);
        L.push('【来週のメイン目標】');
        L.push(SEP_FULL);
        (data.nextGoals || []).forEach(g => L.push(`▶ ${g || '目標を入力'}`));
        L.push('');
        L.push(SEP_FULL);
        L.push('');
        L.push('今週も遊んでくれた皆様、ありがとうございました。来週もよろしくお願いします！⚔️');
        L.push('');
        L.push(TAGS_FULL);

        return L.join('\n');
    }

    // 差分最速版（v2 tpl-diff 準拠）
    function generateDiffText(data) {
        const L = [];
        const totalH = calcTotal(data.log);

        L.push(data.title || '【FF11週報】〇月 第〇週');
        L.push('');
        if (data.summary) L.push(data.summary);
        L.push('');
        L.push(`⏱ 約${totalH}時間`);
        L.push('');
        L.push(`${SEP_SHORT} ① KPI ${SEP_SHORT}`);
        L.push('| 項目 | 目標→結果 | 判定 |');
        L.push('|------|----------|------|');
        (data.kpi || []).forEach(r => {
            const goal   = r.goal   || '?';
            const result = r.result || '?';
            const v = r.verdict === 'ok' ? '🟢' : r.verdict === 'cont' ? '🟡' : r.verdict === 'ng' ? '🔴' : '—';
            L.push(`| ${r.label} | ${goal}→${result} | ${v} |`);
        });
        L.push('');
        L.push(`${SEP_SHORT} ② 稼働ログ ${SEP_SHORT}`);

        // 月〜金を2行に圧縮
        const weekdays = (data.log || []).filter(r => !r.fixed);
        const mid = Math.ceil(weekdays.length / 2);
        const row1 = weekdays.slice(0, mid).map(r => `${r.day}${r.hours || '?'}h:${r.activity || '—'}`).join(' / ');
        const row2 = weekdays.slice(mid).map(r => `${r.day}${r.hours || '?'}h:${r.activity || '—'}`).join(' / ');
        if (row1) L.push(row1);
        if (row2) L.push(row2);

        const sat = (data.log || []).find(r => r.day === '土');
        const sun = (data.log || []).find(r => r.day === '日');
        const satH = sat ? sat.hours || '?' : '?';
        const sunH = sun ? sun.hours || '?' : '?';
        L.push(`土${satH}h:ダイバージェンス / 日${sunH}h:ジェール`);

        L.push('');
        L.push(`${SEP_SHORT} ③ KPT ${SEP_SHORT}`);

        const keeps    = (data.kpt || []).filter(r => r.type === 'Keep'    && r.content).map(r => r.content);
        const problems = (data.kpt || []).filter(r => r.type === 'Problem' && r.content).map(r => r.content);
        const tries    = (data.kpt || []).filter(r => r.type === 'Try'     && r.content).map(r => r.content);
        if (keeps.length)    L.push(`✅Keep: ${keeps.join(' / ')}`);
        if (problems.length) L.push(`❌Problem: ${problems.join(' / ')}`);
        if (tries.length)    L.push(`💡Try: ${tries.join(' / ')}`);
        L.push('');

        const goals = (data.nextGoals || []).filter(g => g);
        if (goals.length) L.push(`▶来週目標: ${goals.join(' / ')}`);
        L.push('');
        L.push('ありがとうございました！⚔️');
        L.push(TAGS_DIFF);

        return L.join('\n');
    }

    // タグのみ
    function generateTagText() {
        return TAGS_FULL;
    }

    // ── Note向け絵文字リスト形式 ──

    // KPI項目ごとの絵文字
    const KPI_EMOJI = {
        'オデシー':         '⚔️',
        '装備強化・合成':   '🔨',
        'フレ・LS活動':     '👥',
        'デイリールーティン': '📋',
    };
    // 曜日絵文字
    const DAY_EMOJI = { '月':'🌙', '火':'🔥', '水':'💧', '木':'🌲', '金':'✨', '土':'🛡️', '日':'🌿' };

    // コードブロックで囲む（Note の <> ブロック用）
    function codeBlock(lines) {
        return ['```', ...lines, '```'].join('\n');
    }

    // 月ごとの画像ヒント（植物 × コーヒー）
    const IMAGE_HINTS = [
        /* 1月 */ '冬の窓辺に置かれた深煎りホットコーヒー、そばに凛と咲く白い蝋梅（ロウバイ）。湯気と雪のコントラスト。',
        /* 2月 */ '淡いピンクの梅の枝を背景に、白いカップのフラットホワイト。春の予感をにじませた光。',
        /* 3月 */ '散りかけの桜吹雪の下、石畳の上に置かれたさくらラテ（ピンク色）。柔らかな春の午後。',
        /* 4月 */ 'カラフルなチューリップ畑のそばに、アイスラテのグラス。澄んだ青空と春の陽射し。',
        /* 5月 */ '薄紫の藤棚の下、木製テーブルに置かれたコールドブリュー。新緑の風と甘い香り。',
        /* 6月 */ '雨粒が光る紫陽花（ブルー系）と、濡れた石畳の上のアイスコーヒー。梅雨のしっとりした朝。',
        /* 7月 */ '元気なひまわりと、汗をかいたアイスラテのグラス。強い夏の光とグリーンの葉。',
        /* 8月 */ '夕暮れの空を背景にした朝顔（紫）と、コールドブリューのボトル。夏の終わりの涼やかさ。',
        /* 9月 */ '赤い彼岸花が揺れる土手のそば、ホットコーヒーのカップ。秋の澄んだ空気と夕焼け色。',
        /* 10月 */ '金木犀の小さなオレンジの花が散る中、キャラメルラテのカップ。甘い香りが漂う秋の午後。',
        /* 11月 */ '赤や黄色に染まった紅葉を背景に、ホットカプチーノとシナモンスティック。晩秋の温もり。',
        /* 12月 */ '雪の積もった柊（ひいらぎ）の葉を添えて、シナモンホットモカ。クリスマス前夜の暖かな灯り。',
    ];

    function getImageHint() {
        const month = new Date().getMonth(); // 0〜11
        return `📸 表紙画像ヒント：${IMAGE_HINTS[month]}`;
    }

    function generateNoteText(data) {
        const L = [];
        const totalH = calcTotal(data.log);

        // 表紙画像ヒント（冒頭に挿入）
        L.push(getImageHint());
        L.push('');

        // タイトル・総評
        L.push(data.title || '【FF11週報】〇月 第〇週');
        L.push('');
        if (data.summary) { L.push(data.summary); L.push(''); }
        L.push(`⏱ 総プレイ時間：約${totalH}時間`);
        L.push('');

        // ① KPI — セクション全体を1つのコードブロック
        L.push(`${SEP_SHORT} ① 今週のKPI ${SEP_SHORT}`);
        L.push('');
        const kpiBlock = [];
        (data.kpi || []).forEach((r, i) => {
            const icon = KPI_EMOJI[r.label] || '📌';
            const v    = verdictEmoji(r.verdict);
            if (i > 0) kpiBlock.push('');
            kpiBlock.push(`${icon} ${r.label}`);
            if (r.goal && r.result) {
                kpiBlock.push(`　目標：${r.goal}　→　${r.result}　${v}`);
            } else if (r.result) {
                kpiBlock.push(`　結果：${r.result}　${v}`);
            } else {
                kpiBlock.push(`　—`);
            }
            if (r.note && r.note !== '—') kpiBlock.push(`　備考：${r.note}`);
        });
        L.push(codeBlock(kpiBlock));
        L.push('');

        // ② 稼働ログ — セクション全体を1つのコードブロック
        L.push(`${SEP_SHORT} ② 稼働ログ（今週 ${totalH}h）${SEP_SHORT}`);
        L.push('');
        const logBlock = (data.log || []).map(r => {
            const icon = DAY_EMOJI[r.day] || '📅';
            const h    = r.hours ? `${r.hours}h` : '—';
            const act  = r.activity || '—';
            return r.fixed
                ? `${icon} ${r.day}　${h}　→ ${act}（固定）`
                : `${icon} ${r.day}　${h}　→ ${act}`;
        });
        L.push(codeBlock(logBlock));
        L.push('');

        // ③ KPT — セクション全体を1つのコードブロック
        L.push(`${SEP_SHORT} ③ KPT振り返り ${SEP_SHORT}`);
        L.push('');

        const keeps    = (data.kpt || []).filter(r => r.type === 'Keep'    && r.content);
        const problems = (data.kpt || []).filter(r => r.type === 'Problem' && r.content);
        const tries    = (data.kpt || []).filter(r => r.type === 'Try'     && r.content);

        const kptBlock = [];
        if (keeps.length) {
            kptBlock.push('✅ Keep');
            keeps.forEach(r => {
                kptBlock.push(`・${r.content}`);
                if (r.action) kptBlock.push(`　→ ${r.action}`);
            });
        }
        if (problems.length) {
            if (kptBlock.length) kptBlock.push('');
            kptBlock.push('❌ Problem');
            problems.forEach(r => {
                kptBlock.push(`・${r.content}`);
                if (r.action) kptBlock.push(`　→ ${r.action}`);
            });
        }
        if (tries.length) {
            if (kptBlock.length) kptBlock.push('');
            kptBlock.push('💡 Try');
            tries.forEach(r => {
                kptBlock.push(`・${r.content}`);
                if (r.action) kptBlock.push(`　→ ${r.action}`);
            });
        }
        if (kptBlock.length) { L.push(codeBlock(kptBlock)); L.push(''); }

        // 来週の目標 — 1つのコードブロック
        const goals = (data.nextGoals || []).filter(g => g);
        if (goals.length) {
            L.push(`${SEP_SHORT} 来週の目標 ${SEP_SHORT}`);
            L.push('');
            L.push(codeBlock(goals.map(g => `▶ ${g}`)));
            L.push('');
        }

        L.push('━━━━━━━━━━━━━━━━━━━━');
        L.push('');
        L.push('今週も遊んでくれた皆様、ありがとうございました。来週もよろしくお願いします！⚔️');
        L.push('');
        L.push(TAGS_FULL);

        return L.join('\n');
    }

    return { generateFullText, generateDiffText, generateTagText, generateNoteText };
})();
