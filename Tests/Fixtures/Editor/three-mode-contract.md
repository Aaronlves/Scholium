---
title: "Three-mode editor contract 范围"
scope: "Synthetic QA only"
limitations:
  - "No scholarly claim or source attribution."
---

# Three-mode editor contract 范围

## Ordinary and mixed-script prose

This long ordinary paragraph compares **strong evidence**, *Neocaridina denticulata*, ~~withdrawn wording~~, ==provisional emphasis==, `exact_code()`, [a standard link](https://example.invalid/editor-contract), [[Synthetic Note|a wikilink]], and inline mathematics $x^2 + y^2$. 中文论证与 English terminology remain in one paragraph so line wrapping and accumulated rhythm can be compared without attributing any claim to a source.

中文段落检查混合排版、标点、组合字符 é 与 emoji 🧭。

هذا نص عربي اختباري يحافظ على اتجاهه ويعزل المصطلح Scholium والعدد 2026 دون إسناد ادعاء إلى مصدر.

זהו טקסט בדיקה סינתטי ששומר על כיוונו ומבודד את המונח Scholium ואת המספר 2026 ללא טענה מחקרית.

### Lists and quotation

- First unordered item with **inline strength**.
  - Nested unordered item.
- Second unordered item.
- [ ] Open synthetic task.

1. First ordered item.
   1. Nested ordered item.
2. Second ordered item.

> Ordinary quotation with *emphasis* and a continuation line.
> The second line keeps one semantic quotation block.

### Code, rule, and table

Inline `let exact = true` remains distinct from the fenced block.

```swift
let mixed = "范围 🧭"
print(mixed)
```

```Mermaid
flowchart LR
accTitle: Synthetic argument diagram
accDescr: A synthetic reason points to a synthetic conclusion.
Reason[Reason] --> Conclusion[Conclusion]
```

---

| Construct | State | Count |
|:---|:---:|---:|
| Paragraph | Ready | 2 |
| Table | Ready | 1 |

### Scholium semantics

> [!orient] Reading route
> Orientation has no visible generated role heading in rendered presentation.

> [!state] Synthetic claim
> This is fixture text, not a scholarly assertion.

> [!quote] Synthetic quotation
> This is not attributed to a person or publication.

Display mathematics must own only its local overflow:

$$
\int_0^1 x^2 \, dx + \sum_{n=1}^{20} \frac{1}{n^2}
$$

Footnote reference[^parity].

Inline note ^[Synthetic inline note.].

[^parity]: Synthetic footnote content with exact source and a nested list.

  - Nested footnote item.

### Deliberately irregular Markdown

Escaped markers remain literal: \*not emphasis\* and \[not a link\].

An unmatched marker remains exact source: *unfinished emphasis.

An incomplete link remains exact source: [unfinished destination](

%% Obsidian comment syntax remains excluded from rendered semantics. %%

<section data-fixture="raw-html">Raw HTML remains a bounded literal region.</section>

INACTIVE_EDIT_ANCHOR keeps every catalog construct outside the active editing position.
