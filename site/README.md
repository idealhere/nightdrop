# CyberDog site

- `relay/` — the site served at https://relay.dforadar.ru/ : three self-contained pages
  (English in the markup, Russian in `data-ru`), their shared `assets/site.css` and `site.js`,
  and `make_assets.py`, which prepares the images. The download page names the current builds;
  the build numbers, file names and checksums in it are rewritten on every release.
- `classic/` — the first, dark version of the site, retired on 2026-10-09 and kept here for
  reference. `published/` is the site exactly as it was served; `src/` holds the Russian source
  pages and `build_i18n.py` turns them into the bilingual ones.
