// 範囲を切り出して撮る。`playwright-cli run-code "$(cat clip.js)"` で渡す。
// 先に `eval` で window.__clipSpec = [{ name, path, from, to, box?, pad? }] を置く（from/to/box は CSS セレクタ。from の上端〜to の下端、横幅は box か from/to の幅）。
// 固定表示（fixed・sticky）の要素は撮影中だけ隠す。チャット欄のように内側でスクロールする画面は、先に縦長へ resize して全体を表示させておく。
async page => {
  const specs = await page.evaluate(() => window.__clipSpec);
  await page.addStyleTag({ content: '.__hide-fixed{visibility:hidden !important}' });
  await page.evaluate(() => {
    for (const el of document.querySelectorAll('body *')) {
      const p = getComputedStyle(el).position;
      if (p === 'fixed' || p === 'sticky') el.classList.add('__hide-fixed');
    }
  });
  const out = [];
  for (const s of specs) {
    const r = await page.evaluate((s) => {
      const top = (sel) => { const e = document.querySelector(sel); const b = e.getBoundingClientRect(); return { t: b.top + window.scrollY, b: b.bottom + window.scrollY, l: b.left, r: b.right }; };
      const a = top(s.from), z = top(s.to);
      const box = s.box ? top(s.box) : { l: Math.min(a.l, z.l), r: Math.max(a.r, z.r) };
      return { x: Math.max(0, box.l - (s.pad ?? 16)), y: Math.max(0, a.t - (s.pad ?? 16)), width: box.r - box.l + 2 * (s.pad ?? 16), height: z.b - a.t + 2 * (s.pad ?? 16) };
    }, s);
    await page.screenshot({ path: s.path, fullPage: true, clip: r });
    out.push(s.name + ' ' + JSON.stringify(r));
  }
  await page.evaluate(() => document.querySelectorAll('.__hide-fixed').forEach(e => e.classList.remove('__hide-fixed')));
  return out.join('\n');
}
