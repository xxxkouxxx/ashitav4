// FF11週報ツール メインロジック

document.addEventListener('DOMContentLoaded', () => {

    // ── 現在の編集対象週 ──
    let currentYear, currentWeek;

    // ── デフォルトデータ ──
    function defaultData() {
        return {
            title: '',
            summary: '',
            kpi: [
                { label: 'オデシー',         goal: '',    result: '', verdict: '', note: '' },
                { label: '装備強化・合成',    goal: '',    result: '', verdict: '', note: '' },
                { label: 'フレ・LS活動',      goal: '',    result: '', verdict: '', note: '' },
                { label: 'デイリールーティン', goal: '消化', result: '', verdict: '', note: '' },
            ],
            log: [
                { day: '月', hours: '', style: '', activity: '', fixed: false },
                { day: '火', hours: '', style: '', activity: '', fixed: false },
                { day: '水', hours: '', style: '', activity: '', fixed: false },
                { day: '木', hours: '', style: '', activity: '', fixed: false },
                { day: '金', hours: '', style: '', activity: '', fixed: false },
                { day: '土', hours: '', style: '固定', activity: 'LS ダイバージェンス', fixed: true },
                { day: '日', hours: '', style: '固定', activity: 'オデシー ジェール',   fixed: true },
            ],
            kpt: [
                { type: 'Keep',    sub: '良かった点①', content: '', action: '' },
                { type: 'Keep',    sub: '良かった点②', content: '', action: '' },
                { type: 'Problem', sub: '反省点①',     content: '', action: '' },
                { type: 'Problem', sub: '反省点②',     content: '', action: '' },
                { type: 'Try',     sub: '来週試す①',   content: '', action: '' },
                { type: 'Try',     sub: '来週試す②',   content: '', action: '' },
            ],
            nextGoals: ['', '', ''],
        };
    }

    // ── フォームからデータ収集 ──
    function collectFormData() {
        const d = defaultData();
        d.title   = q('#f-title').value;
        d.summary = q('#f-summary').value;

        d.kpi.forEach((row, i) => {
            row.goal    = q(`#f-kpi-goal-${i}`)   .value;
            row.result  = q(`#f-kpi-result-${i}`) .value;
            row.verdict = q(`#f-kpi-verdict-${i}`).value;
            row.note    = q(`#f-kpi-note-${i}`)   .value;
        });

        d.log.forEach((row, i) => {
            row.hours = q(`#f-log-hours-${i}`).value;
            if (!row.fixed) {
                row.style    = q(`#f-log-style-${i}`)   .value;
                row.activity = q(`#f-log-activity-${i}`).value;
            }
        });

        d.kpt.forEach((row, i) => {
            row.content = q(`#f-kpt-content-${i}`).value;
            row.action  = q(`#f-kpt-action-${i}`) .value;
        });

        d.nextGoals = d.nextGoals.map((_, i) => q(`#f-goal-${i}`).value);
        return d;
    }

    // ── フォームにデータを流し込み ──
    function fillForm(data) {
        q('#f-title').value   = data.title   || '';
        q('#f-summary').value = data.summary || '';

        (data.kpi || []).forEach((row, i) => {
            q(`#f-kpi-goal-${i}`)   .value = row.goal    || '';
            q(`#f-kpi-result-${i}`) .value = row.result  || '';
            q(`#f-kpi-verdict-${i}`).value = row.verdict || '';
            q(`#f-kpi-note-${i}`)   .value = row.note    || '';
        });

        (data.log || []).forEach((row, i) => {
            q(`#f-log-hours-${i}`).value = row.hours || '';
            if (!row.fixed) {
                q(`#f-log-style-${i}`)   .value = row.style    || '';
                q(`#f-log-activity-${i}`).value = row.activity || '';
            }
        });

        (data.kpt || []).forEach((row, i) => {
            q(`#f-kpt-content-${i}`).value = row.content || '';
            q(`#f-kpt-action-${i}`) .value = row.action  || '';
        });

        (data.nextGoals || []).forEach((g, i) => {
            q(`#f-goal-${i}`).value = g || '';
        });
    }

    // ── プレビュー更新 ──
    function renderPreview() {
        const d = collectFormData();

        // タイトル（空のときはフォームのplaceholderをそのまま使う）
        q('#pv-title').textContent = d.title || q('#f-title').placeholder;

        // 総評
        const summaryEl = q('#pv-summary');
        if (d.summary) {
            summaryEl.textContent = d.summary;
            summaryEl.classList.remove('dim');
        } else {
            summaryEl.textContent = '※ここに今週のハイライト・総評を1〜2行。';
            summaryEl.classList.add('dim');
        }

        // 総プレイ時間
        const total = d.log.reduce((s, r) => s + (parseFloat(r.hours) || 0), 0);
        const totalRounded = Math.round(total * 10) / 10;
        q('#pv-total-hours').textContent = totalRounded || '?';
        q('#pv-meta-hours').textContent  = `⏱ 総プレイ時間：約${totalRounded}時間`;

        // KPI 行
        d.kpi.forEach((row, i) => {
            q(`#pv-kpi-goal-${i}`)  .textContent = row.goal   || '—';
            q(`#pv-kpi-result-${i}`).textContent = row.result || '—';
            q(`#pv-kpi-note-${i}`)  .textContent = row.note   || '—';
            const bdgEl = q(`#pv-kpi-verdict-${i}`);
            bdgEl.className = 'bdg';
            if (row.verdict === 'ok') {
                bdgEl.classList.add('bdg-g'); bdgEl.textContent = '🟢達成';
            } else if (row.verdict === 'cont') {
                bdgEl.classList.add('bdg-y'); bdgEl.textContent = '🟡継続中';
            } else if (row.verdict === 'ng') {
                bdgEl.classList.add('bdg-r'); bdgEl.textContent = '🔴未達';
            } else {
                bdgEl.classList.add('bdg-na'); bdgEl.textContent = '—';
            }
        });

        // 稼働ログ行
        d.log.forEach((row, i) => {
            q(`#pv-log-hours-${i}`).textContent = row.hours ? `${row.hours}h` : '—';
            if (!row.fixed) {
                q(`#pv-log-style-${i}`)   .textContent = row.style    || '—';
                q(`#pv-log-activity-${i}`).textContent = row.activity || '—';
            }
        });

        // KPT 行
        d.kpt.forEach((row, i) => {
            const bodyEl = q(`#pv-kpt-body-${i}`);
            const actEl  = q(`#pv-kpt-act-${i}`);
            if (row.content) {
                bodyEl.textContent = row.content;
                bodyEl.classList.remove('dim');
            } else {
                bodyEl.textContent = row.type === 'Keep' ? '〇〇（良かったこと）' : row.type === 'Problem' ? '〇〇（反省・課題）' : '〇〇（来週試したいこと）';
                bodyEl.classList.add('dim');
            }
            if (row.action) {
                actEl.innerHTML = `<span class="arr">→</span>${row.action}`;
                actEl.classList.remove('dim');
            } else {
                actEl.innerHTML = `<span class="arr">→</span><span style="opacity:.4;font-style:italic;">${row.type === 'Problem' ? 'Tryへ↓' : '来週も継続する施策'}</span>`;
                actEl.classList.add('dim');
            }
        });

        // 来週の目標
        d.nextGoals.forEach((g, i) => {
            const li = q(`#pv-goal-${i}`);
            if (g) {
                li.textContent = g;
                li.classList.remove('dim');
            } else {
                li.textContent = `目標${['①','②','③'][i] || i+1}`;
                li.classList.add('dim');
            }
        });
    }

    // ── イベントリスナー一括設定（フォーム変更でプレビュー更新） ──
    function bindFormEvents() {
        const form = q('#form-panel');
        form.addEventListener('input',  renderPreview);
        form.addEventListener('change', renderPreview);
    }

    // ── 保存 ──
    function handleSave() {
        const data = collectFormData();
        Storage.save(currentYear, currentWeek, data);
        const btn = q('#btn-save');
        const orig = btn.textContent;
        btn.textContent = '✅ 保存完了';
        btn.classList.add('ok');
        setTimeout(() => { btn.textContent = orig; btn.classList.remove('ok'); }, 2000);
    }

    // ── 新規作成（当週・空データ） ──
    function handleNew() {
        if (!confirm('入力内容をクリアして新規作成しますか？')) return;
        const { year, week } = Storage.currentWeek();
        currentYear = year;
        currentWeek = week;
        updateHeaderWeek();
        fillForm(defaultData());
        renderPreview();
    }

    // ── 過去の週報モーダル ──
    function openModal() {
        const overlay = q('#modal-overlay');
        const list = q('#modal-list');
        list.innerHTML = '';

        const entries = Storage.list();
        if (!entries.length) {
            list.innerHTML = '<div class="modal-empty">保存済みの週報がありません</div>';
        } else {
            entries.forEach(e => {
                const div = document.createElement('div');
                div.className = 'modal-item';
                div.innerHTML = `
                    <div class="modal-item-title">${e.title || '（タイトルなし）'}</div>
                    <div class="modal-item-meta">${e.year}/W${String(e.week).padStart(2,'0')}</div>
                    <button class="modal-item-del" data-year="${e.year}" data-week="${e.week}" title="削除">✕</button>
                `;
                // 行クリックで読み込み
                div.addEventListener('click', ev => {
                    if (ev.target.classList.contains('modal-item-del')) return;
                    const data = Storage.load(e.year, e.week);
                    if (data) {
                        currentYear = e.year;
                        currentWeek = e.week;
                        updateHeaderWeek();
                        fillForm(data);
                        renderPreview();
                    }
                    closeModal();
                });
                list.appendChild(div);
            });
        }
        overlay.classList.add('open');
    }

    function closeModal() {
        q('#modal-overlay').classList.remove('open');
    }

    // 削除ボタン（イベント委譲）
    q('#modal-list').addEventListener('click', e => {
        const btn = e.target.closest('.modal-item-del');
        if (!btn) return;
        const y = Number(btn.dataset.year);
        const w = Number(btn.dataset.week);
        if (!confirm(`${y}/W${String(w).padStart(2,'0')} を削除しますか？`)) return;
        Storage.remove(y, w);
        openModal(); // 再描画
    });

    // ── ヘッダーの週番号表示更新 ──
    function updateHeaderWeek() {
        q('#header-week').textContent = `${currentYear} / W${String(currentWeek).padStart(2,'0')}`;
    }

    // ── クリップボードコピー（file://プロトコル対応fallback付き） ──
    function copyText(text, btn, label) {
        const showOk = () => {
            btn.textContent = '✅ コピーしました！';
            btn.classList.add('ok');
            setTimeout(() => { btn.textContent = label; btn.classList.remove('ok'); }, 2000);
        };
        const fallback = () => {
            const ta = document.createElement('textarea');
            ta.value = text;
            ta.style.cssText = 'position:fixed;opacity:0;top:0;left:0;';
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            document.body.removeChild(ta);
            showOk();
        };
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(text).then(showOk).catch(fallback);
        } else {
            fallback();
        }
    }

    // ── ユーティリティ ──
    function q(sel) { return document.querySelector(sel); }

    // ── 初期化 ──
    function init() {
        const cw = Storage.currentWeek();
        currentYear = cw.year;
        currentWeek = cw.week;
        updateHeaderWeek();

        const saved = Storage.load(currentYear, currentWeek);
        fillForm(saved || defaultData());
        bindFormEvents();
        renderPreview();

        // ボタン
        q('#btn-save') .addEventListener('click', handleSave);
        q('#btn-new')  .addEventListener('click', handleNew);
        q('#btn-history').addEventListener('click', openModal);
        q('#btn-pdf')  .addEventListener('click', () => window.print());

        // セクション個別PDF
        document.querySelectorAll('.sec-print-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const cls = `print-${btn.dataset.section}`;
                document.body.classList.add(cls);
                window.addEventListener('afterprint', () => {
                    document.body.classList.remove(cls);
                }, { once: true });
                window.print();
            });
        });
        q('#modal-close') .addEventListener('click', closeModal);
        q('#modal-overlay').addEventListener('click', e => { if (e.target === e.currentTarget) closeModal(); });

        // コピーボタン
        const cpFull = q('#cp-full');
        const cpDiff = q('#cp-diff');
        const cpTags = q('#cp-tags');
        const cpNote = q('#cp-note');
        cpNote.addEventListener('click', () => copyText(Generator.generateNoteText(collectFormData()), cpNote, '✨ Note向けコピー（絵文字版）'));
        cpFull.addEventListener('click', () => copyText(Generator.generateFullText(collectFormData()), cpFull, '📋 全文コピー（マークダウン表）'));
        cpDiff.addEventListener('click', () => copyText(Generator.generateDiffText(collectFormData()), cpDiff, '⚡ 差分のみ（最速版）コピー'));
        cpTags.addEventListener('click', () => copyText(Generator.generateTagText(), cpTags, '🔖 タグ一覧コピー'));
    }

    init();
});
