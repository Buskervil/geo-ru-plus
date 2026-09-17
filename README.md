# geo-ru-plus

Компактные `geosite.dat` / `geoip.dat` для Happ: российские сайты плюс GitHub (и любые свои домены).

Схема та же, что у [kepler103b/geo-for-ru-only](https://github.com/kepler103b/geo-for-ru-only): из [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) копируются нужные категории, остальное в файл не попадает.

## Ссылки для Happ

После первой сборки Actions (вкладка Releases):

- geosite: `https://github.com/Buskervil/geo-ru-plus/releases/download/latest/geosite.dat`
- geoip: `https://github.com/Buskervil/geo-ru-plus/releases/download/latest/geoip.dat`

В Happ: **Settings → Routing rules → RU Routing** — подставьте URL, дождитесь скачивания, переподключите туннель.

GitHub уже вшит в `geosite:category-ru`, отдельный тег добавлять не нужно. Если хотите видеть `geosite:github` в списке тегов — он тоже есть в файле.

## Что править

| Файл | Зачем |
|---|---|
| `categories.txt` | Теги из domain-list-community (`github`, `telegram`, `discord`…) |
| `extra/custom` | Свои домены, по одному на строку |
| `fold-into-category-ru.txt` | Что дополнительно включить в `category-ru` (уже стоит в Direct) |

Новые категории — как имена файлов в [data/](https://github.com/v2fly/domain-list-community/tree/master/data).

Свои списки можно класть в `extra/`: имя файла станет тегом `geosite:<имя>`.

## Сборка локально

Нужны Git и Go 1.25+.

Windows:

```powershell
winget install GoLang.Go
# новый терминал
.\build.ps1
```

Linux / Git Bash:

```bash
./build.sh
```

Файлы появятся в `dist/`.

Либо **Actions → Build geo files → Run workflow** — релиз `latest` обновится сам.
