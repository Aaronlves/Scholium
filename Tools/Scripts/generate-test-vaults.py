#!/usr/bin/env python3
"""Create fresh, nonprivate manual QA vaults; never overwrite an existing set."""
import argparse
import hashlib
import json
import struct
import zlib
from pathlib import Path


def generate(root):
    root.mkdir(parents=True, exist_ok=False)
    for role in ('01-analyses', '02-topics', '03-works'):
        (root / role).mkdir()
    files = {}

    def put(path, body):
        data = body.encode('utf-8') if isinstance(body, str) else body
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        files[path] = hashlib.sha256(data).hexdigest()

    def note(path, body, keywords='[测试, QA]'):
        put(path, '---\nsummary: 合成的非私人界面测试数据，不是学术来源。\nkeywords: '
            + keywords + '\n---\n\n' + body)

    for name in ('QA Autosave A', 'QA Autosave B'):
        note(f'01-analyses/{name}.md', f'# {name}\n\nSynthetic nonprivate QA fixture.\n\n编辑此段，切换笔记，再返回检查自动保存。\n')
    note('01-analyses/示例材料.md', '# 材料正文中的一级标题\n\n文件名、正文标题和受管理的来源标题应保持独立。\n\n'
         '这是一段虚构测试材料，没有作者归属、真实引文或 DOI。\n\n## 摘录区域\n\n'
         '> 这段引文仅用于检查引用块的显示。\n\n## 测试范围\n\n'
         '[[QA Topic]]{{从材料返回测试问题；此注释不构成证据。}}\n')
    note('02-topics/QA Topic.md', '# QA Topic\n\n从这里开始浏览。全部内容都是可丢弃的测试数据。\n\n'
         '## Connections\n\n[[示例材料]]{{检查出链、入链以及注释定位。}}\n\n'
         '[[QA Work|打开写作样本]]\n\n[[排版样本]]\n\n[[长文与目录]]\n\n'
         '## Search\n\n中文检索标记：晨光样本。English marker: aurora-fixture.\n\n'
         '组合检索：中文 English café naïve αβγ。\n', '[测试, 晨光样本, aurora-fixture]')
    note('02-topics/排版样本.md', '# 排版样本\n\n普通正文，**粗体**、*斜体*、`inline code` 与 [外部链接](https://example.org)。\n\n'
         '## 列表\n\n- 第一项\n- 第二项\n  - 子项\n\n1. 首项\n2. 次项\n\n'
         '- [ ] 未完成\n- [x] 已完成\n\n## 引用与脚注\n\n> 合成引文。\n>\n> 第二段。\n\n'
         '脚注定位测试。[^qa]\n\n[^qa]: 合成脚注，无外部文献归属。\n\n'
         '## 表格\n\n| 标记 | 内容 |\n| --- | --- |\n| 中文 | 自动保存 |\n| English | Search |\n\n'
         '## 代码\n\n```text\n[[这不是需要解析的正文链接]]\nsource bytes remain authoritative\n```\n')
    note('02-topics/长文与目录.md', '# 长文与目录\n\n用于滚动、目录定位和返回位置测试。\n\n' + ''.join(
         f'## 第 {i:02d} 节\n\n' + ('这是一段合成的排版测试正文。用于检查中文换行、滚动与光标定位。English text checks mixed typography.\n\n' * 4)
         + f'### 第 {i:02d} 节的子标题\n\n本段用于检查目录层级。\n\n' for i in range(1, 25)))
    for folder in ('文件夹甲', '文件夹乙'):
        note(f'02-topics/{folder}/同名笔记.md', f'# 同名笔记\n\n当前位置：{folder}。用于侧栏路径辨识。\n')
    note('02-topics/诊断样本.md', '# 诊断样本\n\n本页故意包含未解析与歧义链接；不应把这些测试错误修正掉。\n\n'
         '[[不存在的测试目标]]\n\n[[同名笔记]]\n\n[[QA Topic]]{{未闭合的注释\n')
    put('02-topics/空白笔记.md', b'')
    put('02-topics/源码保真.md', b'\xef\xbb\xbf---\r\n# Keep this comment\r\nsummary: "Source fidelity fixture"\r\nkeywords: []\r\ncustom_fixture:\r\n  quoted: \'001\'\r\n  unknown: true\r\n---\r\n\r\n# Source fidelity\r\n\r\nBOM + CRLF; no final newline.')
    note('03-works/QA Work.md', '# 写作样本正文标题\n\n本文件仅用于编辑和界面测试，不提出真实的哲学论证。\n\n'
         '## 起点\n\n参考 [[QA Topic]] 与 [[示例材料]]{{检验跨库导航，不代表来源支持。}}。\n\n'
         '## 可编辑段落\n\n在这里修改一句话，观察自动保存，再测试撤销。\n\n'
         '## 后续段落\n\n为 Settle、外部修改和 Agent Change 测试保留独立编辑区域。\n')
    formats = [
        ('标题与分隔线', '# 一级\n\n## 二级\n\n### 三级\n\n#### 四级\n\n##### 五级\n\n###### 六级\n\nSetext heading\n==============\n\n---\n'),
        ('行内格式', '**粗体**、*斜体*、***粗斜体***、~~删除线~~、`inline code`。\n\n转义：\\*literal\\* &amp; Unicode：café é 中文 🧭。\n\n硬换行。  \n下一行。\n'),
        ('列表', '- 无序一\n  - 嵌套子项\n    - 第三级\n- 无序二\n\n1. 顺序一\n2. 顺序二\n\n- [ ] 待处理\n- [x] 已完成\n'),
        ('引用与Callout', '> 一级引用\n>\n> > 二级引用\n\n> [!NOTE] 测试提示\n> 合成提示内容。\n\n> [!WARNING]\n> 测试警示内容。\n'),
        ('代码', '```swift\nlet label = "测试"\nprint(label)\n```\n\n```python\nprint("fixture")\n```\n\n    indented_code = True\n'),
        ('表格', '| 左对齐 | 居中 | 右对齐 |\n| :--- | :---: | ---: |\n| **中文** | `code` | 123 |\n| escaped \\| pipe | English | 456 |\n'),
        ('脚注', '第一处脚注[^one]，再次引用[^one]。另一处[^two]。\n\n[^one]: 合成脚注一。\n\n[^two]: 第一段。\n\n    脚注续段。\n'),
        ('数学', '行内公式 $a^2+b^2=c^2$。\n\n$$\n\\int_0^1 x^2\\,dx = \\frac{1}{3}\n$$\n'),
        ('Mermaid', '```mermaid\nflowchart LR\n  A[Read] --> B[Edit]\n  B --> C[Save]\n```\n'),
        ('链接', '[[QA Topic|测试入口]]{{此注释仅测试显示与定位。}}\n\n[外部链接](https://example.org) 与 <https://example.org>。\n\n[引用式链接][site]\n\n[site]: https://example.org "Example"\n'),
        ('图片', '![本地测试色块](../Attachments/fixture.png "合成图片")\n'),
        ('HTML与转义', '<!-- 保留源注释 -->\n\n<section>Raw HTML source fixture</section>\n\n\\[转义方括号\\] 与 &lt;tag&gt;。\n'),
    ]
    # Exactly 500 vault notes: existing 3 / 8 / 1 plus 157 / 212 / 119.
    for role, count in [('01-analyses', 157), ('02-topics', 212), ('03-works', 119)]:
        for i in range(1, count + 1):
            label, body = formats[(i - 1) % len(formats)]
            note(f'{role}/格式与检索/{role[:2]}-{i:03d}-{label}.md',
                 f'# {label}样本 {i:03d}\n\n合成测试编号 {role[:2]}-{i:03d}；检索标记 corpus-{i:03d}。\n\n'
                 + body + '\n\n返回 [[QA Topic]]。\n')
        def chunk(kind, data):
            return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
        pixels = b''.join(b'\0' + bytes((45, 90, 130)) * 96 for _ in range(64))
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 96, 64, 8, 2, 0, 0, 0))
        png += chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
        put(f'{role}/Attachments/fixture.png', png)
    put('attachment-samples/说明.txt', '合成的非私人附件。通过应用的附件入口复制或引用此文件。\n')
    put('README.md', '''# Scholium 手动测试 Triptych

三个库：01-analyses、02-topics、03-works。通过当前应用的新建 Triptych 流程选择这三个目录；不要把父目录注册成一个库。建议先复制整个目录后测试。

总计 500 篇库内笔记：Analyses 160、Topics 220、Works 120（本说明不计入）。格式与检索目录轮换覆盖 12 类格式：标题与分隔线、行内格式、列表、引用与 Callout、代码、表格、脚注、数学、Mermaid、链接、图片、HTML 与转义。HTML 是源码保留样本，不要求执行或原样渲染。图片使用本地生成的 PNG，无网络依赖。

从 Topics / QA Topic 开始。数据全部为合成内容，不依赖真实研究笔记。

- 浏览：三库切换、嵌套目录、同名文件、空白笔记、长文目录。
- 编辑：Review / Edit / Source、自动保存、撤销、文件重命名。
- 搜索：晨光样本、aurora-fixture、文件名和正文标题。
- Connect / Attention：正常跨库链接、注释；诊断样本故意保留缺失、歧义及未闭合注释。
- 保真：源码保真.md 带 UTF-8 BOM、CRLF、自定义 YAML、无末尾换行；操作前后可对照 fixture-manifest.json 的 SHA-256。
- About：初始仅 summary / keywords；通过当前 Metadata 界面添加来源标题、作者、Topic aliases 或 Work type，确认它们与文件名独立。没有把 managed Metadata 塞进 YAML。
- 附件：从 attachment-samples/说明.txt 测试 Copy / Reference 及打开；初始不存在附件关系。
- Settle：保存 QA Work 后执行 Settle，再编辑，检查当前修订状态。
- 冲突：只在测试副本中制造编辑器未保存修改与外部修改，检查恢复路径。
- Agent Changes / Research Records：连接当前运行应用的 MCP 后实际创建；初始 Records 和 Agent Changes 为空。记录搜索需先有真实生成的测试记录。

不预制 .scholium、稳定 ID、Metadata、Record、Agent Change 或恢复记录；由当前应用创建。没有旧 Research Action / Handoff 状态。

生成脚本只接受不存在的目标目录，不覆盖旧测试数据。此夹具不是 UI 验收或发布测试通过证明。
''')
    (root / 'fixture-manifest.json').write_text(json.dumps({'files_sha256': files}, ensure_ascii=False, indent=2) + '\n')
    print(f'Created {root}: {sum(p.endswith(".md") and not p == "README.md" for p in files)} notes, {len(files)} files; no preconfigured portable state.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    generate(parser.parse_args().destination.resolve())
