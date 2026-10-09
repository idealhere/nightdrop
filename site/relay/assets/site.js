(function () {
  // Two languages in one page: English is the markup, Russian sits in data-ru (it may hold
  // inline tags). The choice is shared with the rest of the site.
  var root = document.documentElement;
  var nodes = document.querySelectorAll('[data-ru]');
  nodes.forEach(function (n) { n.setAttribute('data-en', n.innerHTML); });
  var titles = { en: document.title, ru: root.getAttribute('data-title-ru') || document.title };
  function apply(lang) {
    nodes.forEach(function (n) { n.innerHTML = n.getAttribute('data-' + lang); });
    root.lang = lang;
    document.title = titles[lang];
    document.querySelectorAll('.lang button').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.getAttribute('data-lang') === lang));
    });
    try { localStorage.setItem('cyberdog-lang', lang); } catch (e) {}
  }
  var saved = null;
  try { saved = localStorage.getItem('cyberdog-lang'); } catch (e) {}
  if (saved === 'ru' || /[?&]ru\b/.test(location.search)) apply('ru');
  document.querySelectorAll('.lang button').forEach(function (b) {
    b.addEventListener('click', function () { apply(b.getAttribute('data-lang')); });
  });

  // Sections fade in as they are reached. Without the observer everything is simply visible.
  var items = document.querySelectorAll('.reveal');
  // `?static` shows everything at once: for a screenshot, or a reader who wants no fading.
  if (!('IntersectionObserver' in window) || /[?&]static/.test(location.search)) {
    items.forEach(function (i) { i.classList.add('in'); }); return;
  }
  var seen = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); seen.unobserve(e.target); } });
  }, { rootMargin: '0px 0px -4% 0px' });
  items.forEach(function (i) { seen.observe(i); });
})();
