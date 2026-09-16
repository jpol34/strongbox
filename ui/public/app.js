let secrets = [];
const REVEAL_TIMEOUT_MS = 15000;
const CLIPBOARD_CLEAR_MS = 30000;
const TOKEN_STORAGE_KEY = 'strongbox.token';

function token() {
  return document.getElementById('token').value;
}

async function load() {
  const btn = document.getElementById('load');
  const status = document.getElementById('load-status');
  btn.disabled = true;
  status.classList.remove('error');
  status.textContent = 'Loading…';

  try {
    const res = await fetch('/api/secrets', {
      headers: { Authorization: `Bearer ${token()}` },
      cache: 'no-store'
    });
    if (!res.ok) {
      if (res.status === 401) {
        // Saved token is stale (server restarted with a rotated token) - stop trusting it.
        localStorage.removeItem(TOKEN_STORAGE_KEY);
      }
      status.classList.add('error');
      status.textContent = `Error: load failed (${res.status})`;
      return;
    }
    localStorage.setItem(TOKEN_STORAGE_KEY, token());
    secrets = await res.json();
    render();
    status.textContent = `loaded ${secrets.length} secrets`;
  } catch (err) {
    status.classList.add('error');
    status.textContent = `Error: ${err.message}`;
  } finally {
    btn.disabled = false;
  }
}

function render() {
  const q = document.getElementById('search').value.toLowerCase();
  const rows = document.getElementById('rows');
  const empty = document.getElementById('empty');
  rows.innerHTML = '';

  const filtered = secrets.filter(s => s.name.toLowerCase().includes(q));
  empty.hidden = filtered.length > 0;
  if (filtered.length === 0) {
    empty.textContent = secrets.length === 0
      ? 'No secrets loaded. Open ⚙ Settings, paste your token, and click Reload.'
      : `No secrets match "${q}".`;
  }

  filtered.forEach(s => {
    const tr = document.createElement('tr');
    if (s.stale) tr.classList.add('stale');
    const rotated = s.lastRotated ? new Date(s.lastRotated).toLocaleDateString() : '-';
    const badge = s.stale ? `<span class="badge badge-warn">⚠ stale</span>` : '';
    const usedByText = asList(s.usedBy).join('; ');
    const purposeText = s.purpose || '';
    tr.innerHTML = `
      <td class="name-cell" title="${escapeAttr(s.name)}">${s.name}</td>
      <td title="${escapeAttr(usedByText)}">${usedByText}</td>
      <td title="${escapeAttr(purposeText)}">${purposeText}</td>
      <td>${rotated} ${badge}</td>
      <td class="action-cell">
        <button data-name="${s.name}" class="btn btn-ghost btn-sm icon-btn reveal" title="Reveal" aria-label="Reveal ${escapeAttr(s.name)}">
          <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>
        </button>
        <button data-name="${s.name}" class="btn btn-ghost btn-sm icon-btn edit" title="Edit" aria-label="Edit ${escapeAttr(s.name)}">
          <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z"></path></svg>
        </button>
      </td>
    `;
    rows.appendChild(tr);
  });

  document.querySelectorAll('.reveal').forEach(btn => {
    btn.addEventListener('click', () => openRevealModal(btn.dataset.name));
  });
  document.querySelectorAll('.edit').forEach(btn => {
    const s = secrets.find(x => x.name === btn.dataset.name);
    btn.addEventListener('click', () => openModal('edit', s));
  });
}

function asList(value) {
  if (Array.isArray(value)) return value;
  if (value) return [value];
  return [];
}

function escapeAttr(str) {
  return String(str).replace(/&/g, '&amp;').replace(/"/g, '&quot;');
}

let revealTimer = null;
let clipboardClearTimer = null;

function closeRevealModal() {
  if (revealTimer) { clearTimeout(revealTimer); revealTimer = null; }
  document.getElementById('reveal-value').textContent = '';
  document.getElementById('reveal-modal').close();
}

function disableRevealCopy() {
  const copyBtn = document.getElementById('reveal-copy');
  copyBtn.onclick = null;
  copyBtn.disabled = true;
}

async function openRevealModal(name) {
  const modal = document.getElementById('reveal-modal');
  const valueEl = document.getElementById('reveal-value');
  document.getElementById('reveal-title').textContent = name;
  valueEl.textContent = 'Loading…';
  // Clear/disable the copy button up front - it must never keep pointing at a previously
  // revealed value if this reveal fails partway through.
  disableRevealCopy();
  modal.showModal();

  let res;
  try {
    res = await fetch(`/api/secrets/${encodeURIComponent(name)}/reveal`, {
      headers: { Authorization: `Bearer ${token()}` },
      cache: 'no-store'
    });
  } catch (err) {
    valueEl.textContent = `(error: ${err.message})`;
    return;
  }
  if (!res.ok) {
    valueEl.textContent = '(error)';
    return;
  }
  const data = await res.json();
  valueEl.textContent = data.value;

  const copyBtn = document.getElementById('reveal-copy');
  copyBtn.disabled = false;
  copyBtn.onclick = () => {
    navigator.clipboard.writeText(data.value);
    if (clipboardClearTimer) clearTimeout(clipboardClearTimer);
    clipboardClearTimer = setTimeout(() => {
      // Only clear if the clipboard still holds what we put there - don't stomp on
      // something else the user copied in the meantime.
      navigator.clipboard.readText().then(current => {
        if (current === data.value) navigator.clipboard.writeText('');
      }).catch(() => {});
    }, CLIPBOARD_CLEAR_MS);
  };

  if (revealTimer) clearTimeout(revealTimer);
  revealTimer = setTimeout(closeRevealModal, REVEAL_TIMEOUT_MS);
}

let modalMode = 'create';

function resetDeleteButton() {
  const del = document.getElementById('modal-delete');
  del.textContent = 'Delete';
  del.dataset.confirming = 'false';
}

function openModal(mode, secret) {
  modalMode = mode;
  const modal = document.getElementById('secret-modal');
  const nameField = document.getElementById('modal-name');
  const deleteBtn = document.getElementById('modal-delete');
  document.getElementById('modal-title').textContent = mode === 'edit' ? 'Update secret' : 'Add secret';
  document.getElementById('modal-status').textContent = '';
  document.getElementById('modal-status').classList.remove('error');
  document.getElementById('modal-value').value = '';
  document.getElementById('modal-value').placeholder = mode === 'edit' ? 'leave blank to keep existing value' : 'value';
  resetDeleteButton();
  deleteBtn.hidden = mode !== 'edit';

  if (mode === 'edit') {
    nameField.value = secret.name;
    nameField.readOnly = true;
    document.getElementById('modal-purpose').value = secret.purpose || '';
    document.getElementById('modal-usedby').value = asList(secret.usedBy).join('; ');
    document.getElementById('modal-rotation').value = secret.rotationDays || '';
  } else {
    nameField.value = document.getElementById('search').value.trim();
    nameField.readOnly = false;
    document.getElementById('modal-purpose').value = '';
    document.getElementById('modal-usedby').value = '';
    document.getElementById('modal-rotation').value = '';
  }

  modal.showModal();
}

function closeModal() {
  document.getElementById('secret-modal').close();
}

async function deleteModal() {
  const deleteBtn = document.getElementById('modal-delete');
  if (deleteBtn.dataset.confirming !== 'true') {
    deleteBtn.dataset.confirming = 'true';
    deleteBtn.textContent = 'Confirm delete?';
    return;
  }

  const name = document.getElementById('modal-name').value.trim();
  const status = document.getElementById('modal-status');
  try {
    const res = await fetch(`/api/secrets/${encodeURIComponent(name)}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token()}` }
    });
    if (!res.ok) {
      const data = await res.json();
      status.classList.add('error');
      status.textContent = `Error: ${data.error}`;
      resetDeleteButton();
      return;
    }
  } catch (err) {
    status.classList.add('error');
    status.textContent = `Error: ${err.message}`;
    resetDeleteButton();
    return;
  }
  await load();
  closeModal();
}

async function saveModal() {
  const name = document.getElementById('modal-name').value.trim();
  const value = document.getElementById('modal-value').value;
  const purpose = document.getElementById('modal-purpose').value;
  const usedBy = document.getElementById('modal-usedby').value;
  const rotationDays = document.getElementById('modal-rotation').value;
  const status = document.getElementById('modal-status');

  try {
    const res = await fetch('/api/secrets', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token()}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ name, value: value || null, purpose, usedBy: usedBy ? [usedBy] : [], rotationDays: rotationDays || null })
    });
    const data = await res.json();
    status.classList.toggle('error', !res.ok);
    if (!res.ok) {
      status.textContent = `Error: ${data.error}`;
      return;
    }
    status.textContent = `Saved ${data.name}`;
  } catch (err) {
    status.classList.add('error');
    status.textContent = `Error: ${err.message}`;
    return;
  }
  await load();
  closeModal();
}

document.getElementById('load').addEventListener('click', load);
document.getElementById('search').addEventListener('input', render);
document.getElementById('add-open').addEventListener('click', () => openModal('create', null));
document.getElementById('modal-submit').addEventListener('click', saveModal);
document.getElementById('modal-cancel').addEventListener('click', closeModal);
document.getElementById('modal-delete').addEventListener('click', deleteModal);

document.getElementById('secret-modal').addEventListener('click', (e) => {
  if (e.target === e.currentTarget) closeModal();
});

document.getElementById('reveal-close').addEventListener('click', closeRevealModal);
document.getElementById('reveal-modal').addEventListener('click', (e) => {
  if (e.target === e.currentTarget) closeRevealModal();
});

document.querySelectorAll('.popover-menu').forEach(menu => {
  document.addEventListener('click', (e) => {
    if (menu.open && !menu.contains(e.target)) {
      menu.open = false;
    }
  });
  menu.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && menu.open) {
      menu.open = false;
      menu.querySelector('summary').focus();
    }
  });
});

render();

const savedToken = localStorage.getItem(TOKEN_STORAGE_KEY);
if (savedToken) {
  document.getElementById('token').value = savedToken;
  load();
}
