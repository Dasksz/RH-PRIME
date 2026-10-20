/* Seletor pesquisável compartilhado pelos filtros do RH. */
(() => {
  'use strict';
  if (customElements.get('rh-search-select')) return;

  class RHSearchSelect extends HTMLElement {
    constructor() {
      super();
      this.attachShadow({ mode: 'open' });
      this._value = '';
      this._options = [];
      this._query = '';
      this._active = -1;
      this._open = false;
      this._renderShell();
    }

    connectedCallback() {
      this._readOptions();
      this._observer = new MutationObserver(() => this._readOptions());
      this._observer.observe(this, { childList: true, subtree: true, characterData: true, attributes: true });
      this._outsideClick = event => {
        if (!event.composedPath().includes(this)) this._setOpen(false);
      };
      document.addEventListener('pointerdown', this._outsideClick);
      this._draw();
    }

    disconnectedCallback() {
      this._observer?.disconnect();
      document.removeEventListener('pointerdown', this._outsideClick);
    }

    get value() { return this._value; }
    set value(value) {
      this._value = String(value ?? '');
      this._draw();
    }

    _renderShell() {
      this.shadowRoot.innerHTML = `
        <style>
          :host{display:block;width:100%;min-width:0;font:inherit;color:var(--rh-ink,#183440);position:relative;--rs-border:var(--rh-border,#344b58);--rs-panel:var(--rh-panel,#142630);--rs-soft:var(--rh-soft,#203540);--rs-ink:var(--rh-ink,#e7f0f4);--rs-muted:var(--rh-muted,#adc2cd);--rs-accent:var(--rh-accent,#137e71)}
          *{box-sizing:border-box}
          .trigger{width:100%;min-height:42px;padding:9px 12px;border:1px solid var(--rs-border);border-radius:12px;background:var(--rs-panel);color:var(--rs-ink);font:inherit;text-align:left;display:flex;align-items:center;justify-content:space-between;gap:10px;cursor:pointer}
          .trigger:hover,.trigger:focus-visible{border-color:var(--rs-accent);outline:none;box-shadow:0 0 0 2px color-mix(in srgb,var(--rs-accent) 25%,transparent)}
          :host(.compact) .trigger{min-height:34px;padding:6px 8px;border-radius:9px;font-size:12px}
          .selected{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0}.chevron{width:9px;height:9px;flex:none;border-right:2px solid currentColor;border-bottom:2px solid currentColor;transform:rotate(45deg);margin:-5px 3px 0;opacity:.75}
          .panel{position:absolute;z-index:1000;top:calc(100% + 5px);left:0;right:0;padding:8px;border:1px solid var(--rs-border);border-radius:12px;background:var(--rs-panel);box-shadow:0 14px 32px #0005}
          .search{display:block;width:100%;height:40px;padding:8px 10px;border:1px solid var(--rs-border);border-radius:8px;background:var(--rs-soft);color:var(--rs-ink);font:inherit;outline:none;margin-bottom:7px}
          .search:focus{border-color:var(--rs-accent);box-shadow:0 0 0 2px color-mix(in srgb,var(--rs-accent) 25%,transparent)}
          .list{max-height:220px;overflow-y:auto;overscroll-behavior:contain;scrollbar-width:thin;scrollbar-color:var(--rs-muted) var(--rs-soft)}
          .list::-webkit-scrollbar{width:9px}.list::-webkit-scrollbar-track{background:var(--rs-soft);border-radius:8px}.list::-webkit-scrollbar-thumb{background:var(--rs-muted);border:2px solid var(--rs-soft);border-radius:8px}
          .option{width:100%;min-height:38px;padding:8px 10px;border:0;border-radius:6px;background:transparent;color:var(--rs-ink);font:inherit;text-align:left;cursor:pointer;overflow-wrap:anywhere}
          .option:hover,.option.active{background:var(--rs-soft)}.option[aria-selected=true]{color:var(--rs-accent);font-weight:700}
          .empty{padding:10px;color:var(--rs-muted);font-size:.9em}
          [hidden]{display:none!important}
        </style>
        <button class="trigger" type="button" aria-haspopup="listbox" aria-expanded="false"><span class="selected"></span><span class="chevron" aria-hidden="true"></span></button>
        <div class="panel" hidden><input class="search" type="search" autocomplete="off" placeholder="Digite para filtrar..." aria-label="Filtrar opções"><div class="list" role="listbox"></div></div>`;
      this._trigger = this.shadowRoot.querySelector('.trigger');
      this._label = this.shadowRoot.querySelector('.selected');
      this._panel = this.shadowRoot.querySelector('.panel');
      this._search = this.shadowRoot.querySelector('.search');
      this._list = this.shadowRoot.querySelector('.list');
      this._trigger.addEventListener('click', () => this._setOpen(!this._open));
      this._trigger.addEventListener('keydown', event => {
        if (event.key === 'ArrowDown') { event.preventDefault(); this._setOpen(true); }
      });
      this._search.addEventListener('input', () => { this._query = this._search.value; this._active = 0; this._drawOptions(); });
      this._search.addEventListener('keydown', event => this._onKeydown(event));
      this._list.addEventListener('click', event => {
        const option = event.target.closest('[data-value]');
        if (option) this._choose(option.dataset.value);
      });
      this._list.addEventListener('mousemove', event => {
        const option = event.target.closest('[data-index]');
        if (option) {
          this._active = Number(option.dataset.index);
          this._list.querySelectorAll('.option').forEach(item => item.classList.toggle('active', item === option));
        }
      });
    }

    _readOptions() {
      const options = [...this.querySelectorAll('option')].map(option => ({ value: option.value, label: option.textContent.trim() }));
      if (options.length) {
        this._options = options;
        if (!options.some(option => option.value === this._value)) this._value = options[0].value;
        this._draw();
      }
    }

    _draw() {
      if (!this._trigger) return;
      const selected = this._options.find(option => option.value === this._value);
      const fallback = this.getAttribute('aria-label') || 'Selecione uma opção';
      this._label.textContent = selected?.label || fallback;
      this._trigger.setAttribute('aria-label', `${fallback}: ${selected?.label || fallback}`);
      this._drawOptions();
    }

    _drawOptions() {
      if (!this._list) return;
      const normalize = value => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('pt-BR');
      const query = normalize(this._query.trim());
      const visible = this._options.filter(option => normalize(option.label).includes(query));
      if (!visible.length) { this._list.innerHTML = '<div class="empty">Nenhuma opção encontrada.</div>'; return; }
      this._active = Math.max(0, Math.min(this._active, visible.length - 1));
      this._list.innerHTML = visible.map((option, index) => `<button type="button" class="option${index === this._active && this._open ? ' active' : ''}" role="option" aria-selected="${option.value === this._value}" data-value="${this._escape(option.value)}" data-index="${index}">${this._escape(option.label)}</button>`).join('');
    }

    _escape(value) { return String(value).replace(/[&<>"']/g, char => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' })[char]); }

    _setOpen(open) {
      this._open = open;
      this._panel.hidden = !open;
      this._trigger.setAttribute('aria-expanded', String(open));
      if (open) {
        this._query = '';
        this._active = Math.max(0, this._options.findIndex(option => option.value === this._value));
        this._search.value = '';
        this._drawOptions();
        requestAnimationFrame(() => { this._search.focus(); this._list.querySelector('[aria-selected="true"]')?.scrollIntoView({ block: 'nearest' }); });
      }
    }

    _choose(value) {
      if (value === this._value) { this._setOpen(false); return; }
      this._value = value;
      this._setOpen(false);
      this._draw();
      this.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
      this.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
    }

    _onKeydown(event) {
      const visible = this._options.filter(option => {
        const normalize = value => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('pt-BR');
        return normalize(option.label).includes(normalize(this._query.trim()));
      });
      if (event.key === 'Escape') { event.preventDefault(); this._setOpen(false); this._trigger.focus(); }
      else if (event.key === 'ArrowDown') { event.preventDefault(); this._active = Math.min(this._active + 1, visible.length - 1); this._drawOptions(); this._list.querySelector('.active')?.scrollIntoView({ block: 'nearest' }); }
      else if (event.key === 'ArrowUp') { event.preventDefault(); this._active = Math.max(0, this._active - 1); this._drawOptions(); this._list.querySelector('.active')?.scrollIntoView({ block: 'nearest' }); }
      else if (event.key === 'Enter' && visible[this._active]) { event.preventDefault(); this._choose(visible[this._active].value); this._trigger.focus(); }
    }
  }

  customElements.define('rh-search-select', RHSearchSelect);
})();
