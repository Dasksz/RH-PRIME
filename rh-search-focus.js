(function () {
  'use strict';
  let active = null, spacer = null, baseline = 0, frame = 0;
  function isSearch(el) {
    return el instanceof HTMLInputElement && !el.disabled &&
      (el.type === 'search' || el.hasAttribute('data-rh-search') ||
       /buscar|pesquis|filtrar/i.test([el.placeholder, el.getAttribute('aria-label')].join(' ')));
  }
  function release() {
    active = null;
    if (spacer) spacer.remove();
    spacer = null;
  }
  function maintain() {
    frame = 0;
    if (!active || !active.isConnected || document.activeElement !== active) return;
    const previous = spacer.offsetHeight;
    const contentHeight = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight) - previous;
    const needed = Math.max(0, baseline - contentHeight);
    if (Math.abs(previous - needed) > 1) spacer.style.height = needed + 'px';
    const viewport = window.visualViewport;
    const top = viewport ? viewport.offsetTop : 0;
    const bottom = top + (viewport ? viewport.height : window.innerHeight);
    const rect = active.getBoundingClientRect();
    if (rect.bottom > bottom - 24) window.scrollBy(0, rect.bottom - bottom + 24);
    else if (rect.top < top + 16) window.scrollBy(0, rect.top - top - 16);
  }
  function schedule() { if (!frame && active) frame = requestAnimationFrame(maintain); }
  document.addEventListener('focusin', function (event) {
    if (!matchMedia('(max-width: 767px)').matches || !isSearch(event.target)) return;
    release();
    active = event.target;
    baseline = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
    spacer = document.createElement('div');
    spacer.setAttribute('aria-hidden', 'true');
    spacer.style.cssText = 'height:0;pointer-events:none;flex:none;overflow-anchor:none';
    document.body.appendChild(spacer);
    schedule();
  });
  document.addEventListener('focusout', function () {
    setTimeout(function () { if (active && document.activeElement !== active) release(); }, 150);
  });
  document.addEventListener('input', schedule);
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', schedule);
    window.visualViewport.addEventListener('scroll', schedule);
  }
  window.addEventListener('resize', schedule);
})();
