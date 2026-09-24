# Scholium 手动测试 Triptych

三个库：01-analyses、02-topics、03-works。通过当前应用的新建 Triptych 流程选择这三个目录；不要把父目录注册成一个库。建议先复制整个目录后测试。

总计 500 篇库内笔记：Analyses 160、Topics 220、Works 120（本说明不计入）。格式与检索目录轮换覆盖 12 类格式：标题与分隔线、行内格式、列表、引用与 Callout、代码、表格、脚注、数学、Mermaid、链接、图片、HTML 与转义。HTML 是源码保留样本，不要求执行或原样渲染。图片使用本地生成的 PNG，无网络依赖。

从 Topics / QA Topic 开始。数据全部为合成内容，不依赖真实研究笔记。

- 浏览：三库切换、嵌套目录、同名文件、空白笔记、长文目录。
- 编辑：Review / Edit / Source、自动保存、撤销、文件重命名。
- 搜索：晨光样本、aurora-fixture、文件名和正文标题。
- Connect / Attention：正常跨库链接、注释；诊断样本故意保留缺失、歧义及未闭合注释。
- 保真：源码保真.md 带 UTF-8 BOM、CRLF、自定义 YAML、无末尾换行；操作前后可对照 fixture-manifest.json 的 SHA-256。
- YAML：QA Topic 带自定义字段与数字；使用 property:qa_stage=draft 或 property:year=2026 检索并定位原文。属性直接在源文本编辑。
- 附件：QA Topic 正文链接打开本地说明；从 attachment-samples/说明.txt 测试 Copy / Reference 在编辑器插入链接，移除链接不删文件。
- Links：External 显示两条合成 Zotero 链接，保留库、页码和注释。它们不是实际文献，测试展示时不必启动 Zotero。
- Settle：保存 QA Work 后执行 Settle，再编辑，检查当前修订状态。
- 冲突：只在测试副本中制造编辑器未保存修改与外部修改，检查恢复路径。
- Agent Changes：连接当前运行应用的 MCP 后实际创建；初始操作记录为空。

不预制 .scholium、稳定 ID、Agent Change 或恢复记录；由当前应用创建。没有旧 Research Action / Handoff 状态。

生成脚本只接受不存在的目标目录，不覆盖旧测试数据。此夹具不是 UI 验收或发布测试通过证明。
