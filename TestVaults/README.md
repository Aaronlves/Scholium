# Scholium 手动测试 Triptych

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
