---
layout: guide
title: Development
description: Run the checks and maintain the README, website, and User Guide.
---

The library and documentation sources live in the
[Lesath repository](https://github.com/noxdea/lesath).

**On this page**

* Contents
{:toc}

## Work on the library

Use CRuby 3.2 or newer:

```sh
git clone https://github.com/noxdea/lesath.git
cd lesath
bundle install
bundle exec rake spec
gem build --strict lesath.gemspec
```

The default `bundle exec rake` task also runs the specs. CI checks CRuby 3.2,
3.3, 3.4, and 4.0 on Linux, macOS, and Windows.

Before extending the supported subset, add a fixture that proves a feature
survives a read/write round trip or produces a clear error. Follow
[ADR 001](https://github.com/noxdea/lesath/blob/main/docs/adr/001-lossless-subset.md)
when deciding how to preserve new content.

## Documentation sources

| File | Purpose |
| --- | --- |
| `README.md` | GitHub introduction, installation, quick start, and documentation links |
| `index.html` | Public landing page |
| `styles.css` | Shared landing page and guide styles |
| `docs/*.md` | User Guide chapters with Jekyll front matter |
| `_layouts/guide.html` | Shared guide navigation and page layout |
| `_config.yml` | Site URL, guide navigation, Markdown settings, and build exclusions |

Keep commands and API examples consistent with the library. Use relative
`.html` links between guide chapters and the canonical Pages URL in the
README. When adding a chapter, add it to `guide_navigation` in `_config.yml`.

The guide uses GitHub Pages' built-in Jekyll and Kramdown support. It does
not require a custom site generator or JavaScript to navigate the chapters.

## Preview the site

Install Jekyll separately from the library's bundle:

```sh
gem install jekyll -v 3.10.0
gem install kramdown-parser-gfm
JEKYLL_NO_BUNDLER_REQUIRE=true jekyll serve
```

Open `http://127.0.0.1:4000/lesath/` and
`http://127.0.0.1:4000/lesath/docs/`. The environment variable lets Jekyll run
without adding site dependencies to the gem's Gemfile.

Check desktop and mobile widths, keyboard navigation, table scrolling, code
blocks, and links between chapters. Build without serving with:

```sh
JEKYLL_NO_BUNDLER_REQUIRE=true jekyll build
```

## Publish

GitHub Pages publishes the repository's `main` branch from its root directory.
Merging documentation changes into `main` rebuilds the website at
`https://noxdea.github.io/lesath/` and the guide at
`https://noxdea.github.io/lesath/docs/`.

The repository's Pages settings should remain **Deploy from a branch**,
branch **main**, folder **/(root)**. Check the Pages build and deployment
in GitHub Actions after merging changes. Repository source and specs are
excluded from the published site in `_config.yml`.

## License

Lesath is released under the
[MIT License](https://github.com/noxdea/lesath/blob/main/LICENSE.txt).
