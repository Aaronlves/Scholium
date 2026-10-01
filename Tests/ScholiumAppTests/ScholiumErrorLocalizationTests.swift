import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Researcher-facing typed error localization")
struct ScholiumErrorLocalizationTests {
    private let chinese = Locale(identifier: "zh-Hans")
    private let english = Locale(identifier: "en")

    @Test("Conflict, failed verification and unknown outcome retain distinct save meanings")
    func consequentialSaveStates() {
        let revision = DocumentFingerprint(content: "exact source")
        let conflict = ScholiumErrorLocalization.message(
            VaultRepositoryError.conflict(expected: revision, current: revision), locale: chinese)
        #expect(conflict == "开始编辑后，磁盘上的笔记发生了更改。请先比较修改或重新载入，再保存。")

        let failedReadback = ScholiumErrorLocalization.message(
            VaultRepositoryError.readbackMismatch(expected: revision, current: revision), locale: chinese)
        #expect(failedReadback.contains("无法验证已保存的字节"))
        #expect(failedReadback.contains("未解决的保存事务仍保留"))

        let unknown = ScholiumErrorLocalization.message(
            VaultRepositoryError.commitUncertain("readback: EIO"), locale: chinese)
        #expect(unknown.contains("无法确认提交后哪些字节属于权威源文本"))
        #expect(unknown.contains("未将笔记报告为已保存"))
        #expect(unknown.hasSuffix("readback: EIO"))
        #expect(!unknown.contains("可以重试"))
    }

    @Test("Paths, authored keys and diagnostic details bypass localization")
    func sourceValuesRemainVerbatim() {
        let path = "Review/Source—原文 🦉.md"
        #expect(
            ScholiumErrorLocalization.message(VaultRepositoryError.fileDoesNotExist(path), locale: chinese)
                == "笔记已不存在：\(path)")
        let parserDetail = "Review\nline 2: unknown value ‘源文本’"
        #expect(
            ScholiumErrorLocalization.message(FrontmatterPatchRefusal.invalidYAML(parserDetail), locale: chinese)
                == "完整 YAML 文首无效：\(parserDetail)")
        let refused = ScholiumErrorLocalization.message(
            FrontmatterPatchRefusal.unsupportedExistingValue("Review"), locale: chinese)
        #expect(refused.contains("“Review”"))
        #expect(!refused.contains("“审阅”"))
    }

    @Test("External and unknown errors remain raw even when they equal catalog keys")
    func externalDiagnosticsRemainVerbatim() {
        let external = "Review"
        #expect(ScholiumErrorLocalization.message(CodexConnectionError.server(external), locale: chinese) == external)
        #expect(ScholiumErrorLocalization.message(ScholiumAppBridgeError.remote(code: "invalid", message: external), locale: chinese) == external)
        let unknown = NSError(domain: "ExternalFixture", code: 5, userInfo: [NSLocalizedDescriptionKey: external])
        #expect(ScholiumErrorLocalization.message(unknown, locale: chinese) == external)
        let syscall = ScholiumAppBridgeError.systemCall("bind", 5)
        #expect(ScholiumErrorLocalization.message(syscall, locale: chinese) == syscall.localizedDescription)
    }

    @Test("Local installation failure is typed independently from external server messages")
    func localInstallationFailure() {
        let raw = "The Codex installation changed. Reconnect after checking the installation."
        #expect(ScholiumErrorLocalization.message(CodexConnectionError.server(raw), locale: chinese) == raw)
        #expect(
            ScholiumErrorLocalization.message(CodexConnectionError.installationChanged, locale: chinese)
                == "Codex 安装发生了更改。请检查安装后重新连接。")
        #expect(ScholiumErrorLocalization.message(CodexConnectionError.installationChanged, locale: english) == raw)
    }

    @Test("Public configuration and resource errors stay delivery-neutral typed contracts")
    func configurationAndResourceFailures() {
        let detail = "rename: EIO"
        #expect(
            ScholiumErrorLocalization.message(ExactFileReplacementError.commitUncertain(detail), locale: chinese)
                == "无法确认配置替换结果：\(detail)")
        #expect(
            ScholiumErrorLocalization.message(ExactFileReplacementError.revisionConflict, locale: chinese)
                == "配置文件或其文件夹发生了更改。请重新载入后重试。")
        let path = "/Library/Review/原始文件.pdf"
        #expect(
            ScholiumErrorLocalization.message(IndexedAttachmentAccessError.bookmarkUnavailable(path), locale: chinese)
                == "Scholium 无法保留对 \(path) 处索引附件的读取权限。")
        #expect(
            ScholiumErrorLocalization.message(BundledResearchSkillResourceError.invalid(path), locale: english)
                == BundledResearchSkillResourceError.invalid(path).localizedDescription)
    }

    @Test("Committed refresh failure never becomes a retryable write failure")
    func committedAndUncertainRemainDistinct() {
        let committed = ScholiumErrorLocalization.message(
            ScholiumApplicationError.operationCommittedButRefreshFailed(operation: "note_move", reason: "EIO"), locale: chinese)
        #expect(committed == "note_move 已成功提交，但无法刷新工作区快照：EIO")
        let uncertain = ScholiumErrorLocalization.message(
            ScholiumApplicationError.operationCommitUncertain(operation: "note_move", reason: "EIO"), locale: chinese)
        #expect(uncertain == "Scholium 无法确认 note_move 是否已提交。请重新载入权威状态，再尝试其他修改：EIO")
    }

    @Test("Registry recovery localizes state and preserves its exact reason")
    func registryHealthProjection() {
        #expect(
            ScholiumErrorLocalization.registrySummary(.malformedCurrentSchema("decoder"), locale: chinese)
                == "脉络注册表已损坏，需要先保留原文件，再重新关联。")
        #expect(
            ScholiumErrorLocalization.registryDetails(.malformedCurrentSchema("Review"), locale: chinese)
                == "无法按受支持的格式解码注册表。Review")
        #expect(
            ScholiumErrorLocalization.message(TriptychControlError.settingsOldSchema(nil), locale: chinese)
                == "便携脉络设置未记录格式版本。其精确字节已保留。")
        #expect(
            ScholiumErrorLocalization.message(TriptychControlError.settingsFutureSchema(999), locale: chinese)
                == "便携脉络设置使用未来版本的格式 999。其精确字节已保留。")
    }

    @Test("Localized recovery explanations never mutate the durable record")
    func recoveryRecordRemainsUnchanged() throws {
        let record = TriptychMutationRecoveryRecord(
            triptychID: UUID(), operation: .noteMove,
            failure: "Review\nExact failure: EIO", files: [])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(record)
        let explanation = ScholiumErrorLocalization.message(
            TriptychTransactionError.recoveryPersistenceFailed(record, "detail: Review"), locale: chinese)
        #expect(explanation.contains(record.id.uuidString))
        #expect(explanation.hasSuffix("detail: Review"))
        #expect(try encoder.encode(record) == original)
        #expect(record.failure == "Review\nExact failure: EIO")
    }

    @Test("User-facing tool validation uses the application resource catalog")
    func applicationValidationErrors() {
        #expect(
            ScholiumErrorLocalization.message(CodexChatToolConfigurationError.duplicateName, locale: chinese)
                == "已有工具连接使用此名称。")
        #expect(
            ScholiumErrorLocalization.message(AgentChatPDFPageSelectionFailure.tooManyPages, locale: chinese)
                == "每次图片输入最多选择 20 页。")
        #expect(
            ScholiumErrorLocalization.message(ZoteroUseCaseError.invalidAnalysisReference, locale: chinese)
                == "仅可为此脉络中的分析确认 Zotero 来源。")
    }

    @Test("English diagnostics retain the domain's meaning and raw values")
    func englishProjection() {
        let errors: [any Error] = [
            VaultRepositoryError.fileDoesNotExist("Exact.md"),
            VaultRepositoryError.commitUncertain("EIO"),
            TriptychControlError.settingsFutureSchema(11),
            DocumentImportError.unsupportedSource("Exact.md"),
            CodexConnectionError.timedOut,
            ExternalMarkdownFileError.changed,
            FrontmatterPatchRefusal.unsupportedExistingValue("aliases"),
        ]
        for error in errors {
            #expect(ScholiumErrorLocalization.message(error, locale: english) == error.localizedDescription)
        }
    }
}
