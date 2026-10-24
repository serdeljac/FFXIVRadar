// Fingerprint of a consolegameswiki recipe page's "crafting" table, as shown in the browser.
// Run it in the browser console (or a browser tool) on a page such as
// https://ffxiv.consolegameswiki.com/wiki/Armorer_Recipes/Level_1_-_9
// It returns { page, count, hash }. Get-WikiRecipes.ps1 prints the same hash for that page
// when its downloaded data matches the table on screen exactly.
(async () => {
  const txt = el => el.innerText.replace(/\s+/g, ' ').trim();
  const num = s => (/^\d+$/.test(s) ? Number(s) : s);
  const data = [];
  for (const t of document.querySelectorAll('#mw-content-text table.crafting')) {
    for (const r of [...t.rows].slice(1)) {
      const c = r.cells;
      const itemCell = txt(c[0]);
      const link = [...c[0].querySelectorAll('a')].find(a => a.innerText.trim());
      const name = link ? txt(link) : itemCell;
      const learned = itemCell.startsWith(name) ? itemCell.slice(name.length).trim() : '';
      const mqm = txt(c[7]).match(/^(\d+)\s*(.*)$/);
      const seq = [];
      for (const dt of c[8].querySelectorAll('.ingredients dt')) { seq.push(num(txt(dt))); seq.push(txt(dt.nextElementSibling)); }
      data.push([name, txt(c[1]), txt(c[2]), txt(c[3]), num(txt(c[4])), num(txt(c[5])), num(txt(c[6])),
                 mqm ? Number(mqm[1]) : txt(c[7]), learned || null, (mqm && mqm[2]) || null, seq]);
    }
  }
  const canon = data.map(d => [...d.slice(0, 10).map(x => x ?? ''), ...d[10]].join('\u001f')).join('\n');
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canon));
  const hash = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
  return { page: document.title.split(' - Final')[0], count: data.length, hash };
})();
