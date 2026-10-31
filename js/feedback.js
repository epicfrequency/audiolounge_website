(() => {
  const node = (tag, text, className) => {
    const el = document.createElement(tag);
    if (text !== undefined) el.textContent = text;
    if (className) el.className = className;
    return el;
  };
  async function api(path, options) {
    const response = await fetch(path, options);
    let data;
    try { data = await response.json(); } catch { throw new Error('The board is unavailable. Please try again later or email support@audiolounge.app.'); }
    if (!response.ok) throw new Error(data.error || 'Please try again later.');
    return data;
  }
  document.querySelectorAll('[data-board]').forEach((board) => {
    const kind = board.dataset.board;
    const content = board.querySelector('.board-content');
    const status = board.querySelector('.board-status');
    const more = board.querySelector('.board-more');
    let next = null;
    let posts = [];
    function render() {
      content.replaceChildren();
      if (!posts.length) { content.append(node('p', kind === 'feature' ? 'No suggestions yet. Share the first idea.' : 'No problems posted yet.')); return; }
      if (kind === 'feature') {
        const wrap = node('div', undefined, 'board-table-wrap');
        const table = node('table', undefined, 'board-table');
        const caption = node('caption', 'Feature suggestions, newest first');
        table.append(caption);
        const head = node('thead'), tr = node('tr');
        ['Suggestion', 'Submitted', 'Votes'].forEach(text => { const th = node('th', text); th.scope = 'col'; tr.append(th); });
        head.append(tr); table.append(head);
        const body = node('tbody');
        posts.forEach(post => {
          const row = node('tr'), description = node('td');
          description.append(node('strong', post.title), node('p', post.message, 'board-message'), node('small', post.name));
          const date = node('td', new Date(post.created).toLocaleDateString());
          const votes = node('td'), button = node('button', post.voted ? `✓ ${post.votes}` : `+1 · ${post.votes}`, 'board-vote');
          button.type = 'button'; button.disabled = !!post.voted;
          button.setAttribute('aria-label', `${post.voted ? 'Already voted for' : 'Vote for'} ${post.title}: ${post.votes} votes`);
          button.addEventListener('click', async () => {
            button.disabled = true;
            try {
              const result = await api(`/api/feedback/${post.id}/vote`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
              post.votes = result.votes; post.voted = true; render(); status.textContent = 'Your vote has been counted.';
            } catch (error) { status.textContent = error.message; button.disabled = false; }
          });
          votes.append(button); row.append(description, date, votes); body.append(row);
        });
        table.append(body); wrap.append(table); content.append(wrap);
      } else posts.forEach(post => {
        const article = node('article', undefined, 'board-post');
        article.append(node('h3', post.title), node('small', `${post.name} · ${new Date(post.created).toLocaleDateString()}`), node('p', post.message, 'board-message'));
        content.append(article);
      });
    }
    async function load(append = false) {
      more.disabled = true;
      status.textContent = 'Loading…';
      try {
        const data = await api(`/api/feedback?kind=${kind}${append && next ? `&before=${next}` : ''}`);
        posts = append ? posts.concat(data.posts) : data.posts;
        next = data.next; more.hidden = !next;
        render(); status.textContent = '';
      } catch (error) {
        status.replaceChildren(node('span', error.message + ' '));
        const retry = node('button', 'Try again', 'board-retry'); retry.type = 'button';
        retry.addEventListener('click', () => load(append)); status.append(retry);
      } finally { more.disabled = false; }
    }
    more.addEventListener('click', () => load(true));
    const form = board.querySelector('form');
    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const submit = form.querySelector('[type="submit"]'), message = form.querySelector('.board-form-status');
      const data = Object.fromEntries(new FormData(form)); data.kind = kind;
      submit.disabled = true; message.textContent = 'Posting…';
      try {
        await api('/api/feedback', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
        form.reset(); message.textContent = 'Posted. Thank you for sharing.'; await load();
      } catch (error) { message.textContent = error.message; }
      finally { submit.disabled = false; }
    });
    // Establish the visitor cookie before enabling mutations.
    form.querySelector('[type="submit"]').disabled = true;
    load().finally(() => { form.querySelector('[type="submit"]').disabled = false; });
  });
})();
