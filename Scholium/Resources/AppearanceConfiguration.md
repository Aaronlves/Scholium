# Document appearance configuration / 文稿外观配置

In Settings → Appearance, choose **Show in Finder…** to locate `appearances.json`.
The same pane contains the structured reading, heading, Bold Font, and Italic
Font controls for the selected appearance profile.
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
| `lineWidthCharacterUnits` | Reading measure / 行宽 | 48–96; relative character-width units, not a count of Chinese characters |
| `body.fontFamily` | Body font / 正文字体 | `alegreya`, `iowan`, `palatino`, `georgia`, `times`, `systemSerif` |
| `body.cjkStrongFontFamily` | Chinese strong face / 中文加粗字体 | omitted or `null` follows body font; `""` restores body font; otherwise an installed family name |
| `body.cjkEmphasisFontFamily` | Chinese emphasis face / 中文强调字体 | omitted or `null` uses Kaiti SC; `""` follows the body font's native italic; otherwise an installed family name |
| `body.fontSizePoints` | Body size / 正文字号 | 9–24 pt |
| `body.lineHeight` | Line spacing / 行距 | 1.2–2.4 × |
| `source.fontFamily` | Source font / 源文本字体 | Installed font family name / 已安装字体家族名 |
| `source.fontSizePoints` | Source size / 源文本字号 | 6–72 pt |

## Body typography

`paragraphSpacingEm`: 0–2; `firstLineIndentEm`: 0–4. An `em` is relative to
the applicable font size.

`alignment`: `start`, `center`, `justify`.

These fields control paragraph spacing, indentation and alignment. Fine
typesetting is intentionally not a profile field; use the Advanced CSS surface
described below for letter spacing, word spacing, hyphenation, kerning and
ligatures.
这些字段只控制段间距、首行缩进和对齐。字距、词距、断词、字偶距与连字等细致
排版不再属于外观配置字段，请使用下面的 Advanced CSS。

## Headings

- `fontFamily`: `body`, `alegreya`, `systemSerif`, `systemSans`.
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

Optional CSS snippets remain a separate, constrained override for ordinary
document content. Use **CSS Snippets…** in the Appearance pane to open the
manager. **Open CSS Folder** reveals the app-owned `Styles/Snippets` folder;
direct `.css` files are discovered automatically, watched for edits, and
reloaded after validation. The manifest stores only order, enablement, names,
and stable identities; CSS file bytes remain the file's responsibility. A
missing or invalid file stays listed with an error so it can be repaired.

Snippets are the only configuration surface for fine typography and are
applied after the generated appearance CSS, so they can refine the selected
profile without creating a second appearance owner. They do not replace
structured appearance defaults or style native controls. The public Callout
surface uses `.callout`, `.callout-title`, `.callout-body`, `.callout-content`,
and `.callout-<role>` (for example `.callout-state .callout-title`); Scholium
maps these names separately for Review and Edit and does not expose its
internal projection classes.

For example, an imported snippet can contain:

```css
body {
  letter-spacing: 0;
  word-spacing: 0.04em;
  hyphens: auto;
  font-kerning: normal;
  font-variant-ligatures: common-ligatures;
}

h1, h2, h3, h4, h5, h6 {
  letter-spacing: -0.01em;
}
```

The supported selectors are ordinary document elements such as `body`, `p`,
`h1`–`h6`, `li`, `blockquote`, `table`, `code`, `strong`, `em`, and `mark`,
along with the public Callout selectors described above. Snippets are
sanitized, scoped to document content, and projected into both Review and Edit.

例如，导入的 CSS 片段可以包含上述规则。支持的选择器是 `body`、`p`、`h1`–`h6`、
`li`、`blockquote`、`table`、`code`、`strong`、`em`、`mark` 以及公开的 Callout
选择器；片段会经过安全检查，只作用于文稿内容，并同时投影到 Review 和 Edit。

Default sizing follows a 16 CSS px body (12 pt), with Courier at 12.8 CSS px (9.6 pt) for Source and Frontmatter. Heading scales remain relative to body text; the body font family is unchanged.
