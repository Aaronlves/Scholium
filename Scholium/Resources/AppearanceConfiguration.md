# Document appearance configuration / 文稿外观配置

In Settings → Appearance, choose **Show in Finder…** to locate `appearances.json`.
The same pane contains the structured reading, hyphenation, heading, Bold Font,
and Italic Font controls for the selected appearance profile.
The generated file is a complete, editable example. Copy it before experimenting,
edit it with a text editor, then choose **Reload** in Scholium. You can replace it
with another complete configuration of the same format.

在“设置 → 外观”中选择“在 Finder 中显示…”，找到 `appearances.json`。
同一页面提供正文、标题、粗体和斜体字体控件，编辑当前外观配置。
当前文件本身就是完整示例。可以先复制一份，再用文本编辑器修改或替换，
然后回到 Scholium 选择“重新载入”。

## File structure

- `selectedProfileID` identifies the selected configuration in `profiles`.
- Each profile has a unique `id`, a `name`, and `settings`.
- Keep IDs and required fields intact. JSON does not permit comments or trailing commas.
- Settings affects Markdown content display on this Mac, never Markdown/YAML bytes or native app chrome.
- The interface edits the same configuration and preserves its advanced settings.
- When an external change is detected, reload before saving from the interface.
- A failed reload retains the currently loaded appearance and reports the field.
- Reload after a successful repair. An invalid file is never automatically rewritten.

`selectedProfileID` 必须对应 `profiles` 中某一项的 `id`。保留完整结构、唯一 ID
和所有必需字段；JSON 不支持注释和尾随逗号。配置仅影响本机呈现，不改写研究
文档内容或系统界面。界面修改与文件修改使用同一套配置；文件被外部修改后，须先
重新载入再从界面保存。重新载入失败会保留当前外观，并指出错误位置。

## Common fields

| Field | Meaning / 含义 | Supported values |
| --- | --- | --- |
| `lineWidthCharacterUnits` | Read/Edit reading measure / 阅读与编辑行宽 | 48–96; relative character-width units, not a count of Chinese characters. |
| `body.fontFamily` | Body font / 正文字体 | `alegreya`, `iowan`, `palatino`, `georgia`, `times`, `systemSerif`, or an installed font family name / 或已安装字体家族名 |
| `body.cjkStrongFontFamily` | Chinese strong face / 中文加粗字体 | omitted or `null` follows body font; `""` restores body font; otherwise an installed family name |
| `body.cjkEmphasisFontFamily` | Chinese emphasis face / 中文强调字体 | omitted or `null` uses Kaiti SC; `""` follows the body font's native italic; otherwise an installed family name |
| `body.fontSizePoints` | Body size / 正文字号 | 9–24 pt |
| `body.lineHeight` | Line spacing / 行距 | 1.2–2.4 × |
| `source.fontFamily` | Code font / 代码字体 | Installed font family name / 已安装字体家族名 |
| `source.fontSizePoints` | Code size / 代码字号 | 6–72 pt |

## Body typography

`paragraphSpacingEm`: 0–2; `firstLineIndentEm`: 0–4. An `em` is relative to
the applicable font size. `hyphenation` is `none` or `automatic`; it defaults to
`none`. Automatic uses the language-aware native hyphenation engine for
supported prose, while Chinese text and technical regions remain
unsplit by automatic hyphenation.

`alignment`: `start`, `center`, `justify`.

These fields control native paragraph spacing, indentation and alignment.
这些字段控制原生文稿的段间距、首行缩进和对齐；断词由 `hyphenation` 字段控制。

## Headings

- `fontFamily`: `body`, `alegreya`, `systemSerif`, `systemSans`, or an installed font family name / 或已安装字体家族名.
- `cjkStrongFontFamily`: omitted or `null` follows the heading font; `""` also follows it; otherwise an installed family name is used only for Chinese glyphs in strong text.
- `cjkEmphasisFontFamily`: omitted or `null` uses Kaiti SC for Chinese emphasis; `""` follows the heading font's native italic; otherwise an installed family name is used only for Chinese glyphs in emphasis and italic headings.
- `style`: `upright`, `italic`, `smallCaps`.
- `weight`: 400–700; `lineHeight`: 1–2.4.
- `level1` through `level6` control H1 through H6 independently.
- Each level has `scale` (0.8–3), `alignment` (`start`, `center`, `justify`),
  `spaceBeforeEm` (0–4), and `spaceAfterEm` (0–4).

`level1` 至 `level6` 分别对应 H1 至 H6，可以独立调整；它们不改变原文标题层级。

## Callouts

Keep one entry for each role, in the generated order:
`orientation`, `connections`, `statement`, `illustration`, `caution`,
`folded`, `quotation`, `source`.

Common fields: `inlineInsetEm` (0–4), `blockGapEm` (0–4),
`fontScale` (0.8–1.4), `paragraphSpacingEm` (0–2), `titleWeight` (400–700).

| Role | Additional fields |
| --- | --- |
| `orientation` | `startInsetEm`, `endInsetEm` (0–6); `lineHeight` (1.1–2.4) |
| `connections`, `folded` | `contentIndentEm` (0–4) |
| `statement` | `titleGapEm` (0–2) |
| `caution`, `source` | `paddingBlockEm` (0–3); `paddingInlineEm` (0–4) |
| `quotation` | `quotationScale` (0.8–1.5); `attributionScale` (0.6–1.2) |

These values change appearance within Scholium's protected document structure.
They cannot hide provenance, diagnostics, conflicts or recovery information.
这些参数只调整受保护结构内的排版，不能隐藏来源、诊断、冲突或恢复信息。

Bold and italic font choices are presentation-only. Latin characters continue
using the selected body or heading family, including its real bold and italic
faces; the built-in mixed-script defaults use FangSong for body text and KaiTi
for italic text. An explicit font choice remains authoritative until it is
changed or reset. Font family names refer to fonts installed on this Mac and
are safely quoted in generated CSS. They never become Markdown/YAML content.

语义字体选择只影响呈现层。拉丁字符继续使用正文或标题所选字体及其真实的
粗体、斜体字形；中文替代字体只作用于呈现语言片段。字体名必须是本机已安装
的字体，并会在生成 CSS 时安全转义，不会写入 Markdown/YAML。
