(() => {
  'use strict';
  if (customElements.get('rh-multi-select')) return;
  class RHMultiSelect extends HTMLElement {
    constructor() {
      super();
      this.attachShadow({mode:'open'});
      this._options=[];
      this._selected=new Set();
      this._query='';
      this._open=false;
      this.shadowRoot.innerHTML=`
        <style>
          :host{display:block;position:relative;min-width:0;font:inherit;color:var(--rh-ink,#183440)}
          *{box-sizing:border-box}
          .trigger{width:100%;min-height:42px;padding:9px 12px;border:1px solid var(--rh-border,#344b58);border-radius:10px;background:var(--rh-panel,#142630);color:var(--rh-ink,#e7f0f4);font:inherit;text-align:left;display:flex;align-items:center;justify-content:space-between;gap:8px;cursor:pointer}
          .label{font-weight:700;color:var(--rh-muted,#adc2cd);white-space:nowrap}.summary{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0;flex:1}
          .panel{position:absolute;z-index:1000;top:calc(100% + 5px);left:0;width:min(340px,calc(100vw - 24px));padding:8px;border:1px solid var(--rh-border,#344b58);border-radius:12px;background:var(--rh-panel,#142630);box-shadow:0 14px 32px #0005}
          .actions{display:flex;justify-content:space-between;align-items:center;padding:0 2px 7px;font-size:12px;color:var(--rh-muted,#adc2cd)}
          .clear{border:0;background:transparent;color:var(--rh-accent,#137e71);font:inherit;font-weight:700;cursor:pointer;padding:4px}
          .search{display:block;width:100%;height:38px;padding:8px 10px;border:1px solid var(--rh-border,#344b58);border-radius:8px;background:var(--rh-soft,#203540);color:var(--rh-ink,#e7f0f4);font:inherit;outline:none;margin-bottom:7px}
          .list{max-height:220px;overflow-y:auto;overscroll-behavior:contain;scrollbar-width:thin;scrollbar-color:var(--rh-muted,#adc2cd) var(--rh-soft,#203540)}
          .option{width:100%;min-height:38px;padding:8px 9px;border:0;border-radius:6px;background:transparent;color:var(--rh-ink,#e7f0f4);font:inherit;text-align:left;cursor:pointer;display:flex;align-items:flex-start;gap:9px}
          .option:hover{background:var(--rh-soft,#203540)}.check{width:17px;height:17px;border:1px solid var(--rh-muted,#adc2cd);border-radius:4px;flex:none;margin-top:1px;display:grid;place-items:center;color:white;font-size:12px}
          .option[aria-checked=true] .check{background:var(--rh-accent,#137e71);border-color:var(--rh-accent,#137e71)}
          .option-text{overflow-wrap:anywhere}.empty{padding:10px;color:var(--rh-muted,#adc2cd);font-size:.9em}
          [hidden]{display:none!important}
        </style>
        <button class="trigger" type="button" aria-haspopup="listbox" aria-expanded="false"><span class="label"></span><span class="summary"></span><span aria-hidden="true">⌄</span></button>
        <div class="panel" hidden><div class="actions"><span class="count"></span><button class="clear" type="button">Limpar</button></div><input class="search" type="search" autocomplete="off" placeholder="Digite para filtrar..." aria-label="Filtrar opções"><div class="list" role="listbox" aria-multiselectable="true"></div></div>`;
      this._trigger=this.shadowRoot.querySelector('.trigger');
      this._label=this.shadowRoot.querySelector('.label');
      this._summary=this.shadowRoot.querySelector('.summary');
      this._panel=this.shadowRoot.querySelector('.panel');
      this._search=this.shadowRoot.querySelector('.search');
      this._list=this.shadowRoot.querySelector('.list');
      this._trigger.addEventListener('click',()=>this._setOpen(!this._open));
      this._search.addEventListener('input',()=>{this._query=this._search.value;this._drawOptions();});
      this._list.addEventListener('click',event=>{const option=event.target.closest('[data-value]');if(option)this._toggle(option.dataset.value);});
      this.shadowRoot.querySelector('.clear').addEventListener('click',()=>{this._selected.clear();this._draw();this._emit();});
      this.addEventListener('keydown',event=>{if(event.key==='Escape'&&this._open){this._setOpen(false);this._trigger.focus();}});
    }
    connectedCallback(){this._readOptions();this._observer=new MutationObserver(()=>this._readOptions());this._observer.observe(this,{childList:true,subtree:true,characterData:true,attributes:true});this._outside=event=>{if(!event.composedPath().includes(this))this._setOpen(false);};document.addEventListener('pointerdown',this._outside);this._draw();}
    disconnectedCallback(){this._observer?.disconnect();document.removeEventListener('pointerdown',this._outside);}
    get values(){return [...this._selected];}
    set values(values){const valid=new Set(this._options.map(option=>option.value));this._selected=new Set((Array.isArray(values)?values:[]).map(String).filter(value=>valid.has(value)));this._draw();}
    _readOptions(){const previous=this._selected;this._options=[...this.querySelectorAll('option')].map(option=>({value:option.value,label:option.textContent.trim()}));this._selected=new Set([...previous].filter(value=>this._options.some(option=>option.value===value)));this._draw();}
    _draw(){if(!this._trigger)return;const label=this.getAttribute('filter-label')||this.getAttribute('aria-label')||'Filtro';this._label.textContent=label+':';const selected=this._options.filter(option=>this._selected.has(option.value));this._summary.textContent=selected.length?selected.length===1?selected[0].label:selected.length+' selecionados':'Todos';this._trigger.setAttribute('aria-label',label+': '+(selected.map(option=>option.label).join(', ')||'Todos'));this._drawOptions();}
    _drawOptions(){if(!this._list)return;const norm=value=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('pt-BR');const query=norm(this._query.trim());const options=this._options.filter(option=>norm(option.label).includes(query));if(!options.length){this._list.innerHTML='<div class="empty">Nenhuma opção encontrada.</div>';return;}this._list.innerHTML=options.map(option=>'<button type="button" class="option" role="option" aria-checked="'+this._selected.has(option.value)+'" data-value="'+this._escape(option.value)+'"><span class="check">'+(this._selected.has(option.value)?'✓':'')+'</span><span class="option-text">'+this._escape(option.label)+'</span></button>').join('');this.shadowRoot.querySelector('.count').textContent=this._selected.size+' selecionado(s)';}
    _escape(value){return String(value).replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));}
    _setOpen(open){this._open=open;this._panel.hidden=!open;this._trigger.setAttribute('aria-expanded',String(open));if(open){const rect=this.getBoundingClientRect(),width=Math.min(340,Math.max(250,window.innerWidth-24)),left=Math.min(Math.max(12,rect.left),window.innerWidth-width-12);this._panel.style.width=width+'px';this._panel.style.left=(left-rect.left)+'px';this._query='';this._search.value='';this._drawOptions();requestAnimationFrame(()=>this._search.focus());}}
    _toggle(value){if(this._selected.has(value))this._selected.delete(value);else this._selected.add(value);this._draw();this._emit();}
    _emit(){this.dispatchEvent(new Event('input',{bubbles:true,composed:true}));this.dispatchEvent(new Event('change',{bubbles:true,composed:true}));}
  }
  customElements.define('rh-multi-select',RHMultiSelect);
})();
