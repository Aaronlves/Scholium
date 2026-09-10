# Document appearance configuration / 文稿外观配置

In Settings → Document, choose **Show in Finder…** to locate `appearances.json`.
The generated file is a complete, editable example. Copy it before experimenting,
edit it with a text editor, then choose **Reload** in Scholium. You can replace it
with another complete configuration of the same format.

在“设置 → 文稿”中选择“在 Finder 中显示…”，找到 `appearances.json`。
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
| `lineWidthCharacterUnits` | Reading measure / 行宽 | 48–96; relative character-width units, not a count of Chinese characters |
| `body.fontFamily` | Body font / 正文字体 | `alegreya`, `iowan`, `palatino`, `georgia`, `times`, `systemSerif` |
| `body.fontSizePoints` | Body size / 正文字号 | 9–24 pt |
| `body.lineHeight` | Line spacing / 行距 | 1.2–2.4 × |
| `source.fontFamily` | Source font / 源文本字体 | Installed font family name / 已安装字体家族名 |
| `source.fontSizePoints` | Source size / 源文本字号 | 6–72 pt |

## Body typography

`paragraphSpacingEm`: 0–2; `firstLineIndentEm`: 0–4;
`letterSpacingEm`: −0.05–0.1; `wordSpacingEm`: −0.1–0.5.
An `em` is relative to the applicable font size.

`alignment`: `start`, `center`, `justify`.
`hyphenation`: `none`, `automatic`.
`kerning` and `ligatures`: `true` / `false`.

These fields control paragraph spacing, indentation, letter/word spacing,
alignment, hyphenation, kerning and common ligatures.
对应段间距、首行缩进、字距、词距、对齐、断词、字偶距与常用连字。

## Headings

- `fontFamily`: `body`, `alegreya`, `systemSerif`, `systemSans`.
- `style`: `upright`, `italic`, `smallCaps`.
- `weight`: 400–700; `lineHeight`: 1–2.4; `letterSpacingEm`: −0.05–0.1.
- `level1` controls H1; `level2` controls the quieter H2–H6 tier.
- Each tier has `scale` (0.8–3), `alignment` (`start`, `center`, `justify`),
  `spaceBeforeEm` (0–4), and `spaceAfterEm` (0–4).

`level1` 对应正文 H1，`level2` 对应 H2–H6；它们不改变原文标题层级。

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
| `illustration` | `titleColumnEm` (3–16); `columnGapEm` (0–4) |
| `caution`, `source` | `paddingBlockEm` (0–3); `paddingInlineEm` (0–4) |
| `quotation` | `quotationScale` (0.8–1.5); `attributionScale` (0.6–1.2) |

These values change appearance within Scholium's protected document structure.
They cannot hide provenance, diagnostics, conflicts or recovery information.
这些参数只调整受保护结构内的排版，不能隐藏来源、诊断、冲突或恢复信息。

Optional CSS snippets remain a separate, constrained override for ordinary
document content. Use **Advanced CSS…** to manage them. They do not replace
the structured Callout settings or style native controls.

Default sizing follows a 16 CSS px body (12 pt), with Courier at 12.8 CSS px (9.6 pt) for Source and Frontmatter. Heading scales remain relative to body text; the body font family is unchanged.
