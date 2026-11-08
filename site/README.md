# LensControl landing page

A one-page Hugo site: what LensControl does, how it hooks up, and where to get
it per platform. No theme, no npm, no content files; plain CSS minified by Hugo
Pipes.

## Run it locally

Needs Hugo extended (`brew install hugo`).

```sh
cd site
hugo server          # http://localhost:1313, reloads on save
hugo --minify        # production build into site/public/
```

## Where things live

| What | File |
|------|------|
| Links, tagline, platform cards, icon and screenshot paths | `hugo.toml` → `[params]` |
| Page markup | `layouts/index.html` |
| `<head>` | `layouts/_partials/head.html` |
| Screenshot placeholders (inline SVG) | `layouts/_partials/placeholder-*.html` |
| Styles, light and dark | `assets/css/main.css` |
| Images, favicon | `static/` |

## Changing the links

Everything a visitor can click to leave the page is in `hugo.toml`:

- `params.github`: the repository link in the top bar, hero and footer.
- `[[params.platforms]]`: one block per card, in display order. For macOS,
  set `url` to the Mac App Store page or a GitHub Releases asset and `label`
  to the button text (e.g. "Download for macOS"). It points at the build
  instructions until there is a release.
- `comingSoon = true` hides a card's button and shows a "Coming soon" badge.
  Flip it to `false` and fill `url` / `label` when Windows or Linux ships.

## Icon and screenshots

The hero has an empty, dashed app-icon slot and the screenshots are grey
wireframes. To replace them, drop files into `static/images/` and set the
paths in `hugo.toml`:

```toml
[params]
icon = "images/icon.png"          # shown at 112 × 112, so export 224 px or more

[params.screenshots]
popover = "images/popover.png"    # 330 pt wide → 660 px @2x, about 1:2
window  = "images/window.png"     # 680 pt wide → 1360 px @2x, about 17:12
```

The template switches from placeholder to `<img>` as soon as a path is set.
If a real screenshot has a different height, update the `width`/`height`
attributes in `layouts/index.html` and the `flex` ratios under "Screenshots" in
`main.css` so the two still line up.

## Deployment

`.github/workflows/site.yml` builds with Hugo extended and deploys to GitHub
Pages on every push to `main` that touches `site/**` (or by hand from the
Actions tab).

One-time setup, not done yet: in the repository's **Settings → Pages**, set
**Source** to **GitHub Actions**. Until then the deploy job fails.

The site will serve at `https://drahosistvan.github.io/lenscontrol/`. The
intended domain is **lenscontrol.app**, which is not registered yet. Once it
is: add it under Settings → Pages → Custom domain, point DNS at GitHub Pages,
and change `baseURL` in `hugo.toml`. The workflow passes the Pages URL as
`--baseURL`, so it picks up the custom domain on its own.
