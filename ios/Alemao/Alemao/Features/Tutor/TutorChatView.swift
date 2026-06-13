import SwiftData
import SwiftUI

/// Chat de texto aberto em alemão com a tutora "Lara".
/// A conversa em alemão é a estrela; correções (chips sob a bolha do aluno) e
/// micro-aulas (cards sob a bolha da Lara) são feedback discreto e glanceável.
struct TutorChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var chat: TutorChat

    @State private var messages: [ChatMessage] = []
    @State private var memory = TutorMemory()
    @State private var level: String = "B1"
    @State private var input: String = ""
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var lastFailedInput: String?
    @State private var showReview = false
    @State private var didLoad = false
    @State private var turnTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    private let service = TutorChatService()

    private var correctionsCount: Int {
        messages.reduce(0) { $0 + ($1.corrections?.count ?? 0) }
    }

    /// Sugestões da última mensagem da tutora (muletas anti-bloqueio).
    private var latestSuggestions: [String] {
        messages.last(where: { $0.role == .tutor })?.suggestedReplies_de ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            if !latestSuggestions.isEmpty && !isLoading && input.isEmpty {
                suggestionBar
            }
            Divider()
            inputBar
        }
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showReview = true
                } label: {
                    Image(systemName: "list.bullet.clipboard")
                }
                .disabled(correctionsCount == 0)
            }
        }
        .sheet(isPresented: $showReview) {
            TutorErrorsReviewSheet(messages: messages)
        }
        .onAppear(perform: load)
        .onDisappear { turnTask?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text("Lara").font(.subheadline.bold())
                Text("Tutora de alemão").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if correctionsCount > 0 {
                Text("\(correctionsCount) correções")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            LevelBadge(level, size: .small)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppSpacing.md) {
                    if messages.isEmpty {
                        emptyHint
                    }
                    ForEach(messages) { message in
                        messageRow(message).id(message.id)
                    }
                    if isLoading {
                        HStack {
                            LoadingHStack(message: "Lara schreibt…", controlSize: .small)
                            Spacer()
                        }
                        .id("loading")
                    }
                    if let errorText {
                        retryPill(errorText)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: isLoading) { _, _ in scrollToBottom(proxy) }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Schreib auf Deutsch — über alles!")
                .font(.callout).foregroundStyle(.secondary)
            Text("A Lara corrige com carinho e ensina quando perceber uma dificuldade.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xl)
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        if message.role == .user {
            userRow(message)
        } else {
            tutorRow(message)
        }
    }

    // ---- User bubble + correction chips (anchored under the user's own line) ----

    private func userRow(_ message: ChatMessage) -> some View {
        VStack(alignment: .trailing, spacing: AppSpacing.xs) {
            HStack {
                Spacer(minLength: 40)
                Text(message.text_de)
                    .font(.callout)
                    .padding(AppSpacing.sm)
                    .background(Color.accentColor.opacity(AppOpacity.strong))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
            }

            if let corrections = message.corrections, !corrections.isEmpty {
                ForEach(Array(corrections.enumerated()), id: \.offset) { _, correction in
                    HStack {
                        Spacer(minLength: 24)
                        CorrectionChip(correction: correction)
                    }
                }
            } else if message.corrections != nil {
                // corrections == [] (turno avaliado e limpo) → sinal positivo
                HStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.success)
                    Text("Perfeito!").font(.caption2).foregroundStyle(Color.success)
                }
            }
        }
    }

    // ---- Tutor bubble (German, pristine) + praise + mini-lesson ----

    private func tutorRow(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(message.text_de)
                    .font(.callout)
                    .padding(AppSpacing.sm)
                    .background(Color.secondary.opacity(AppOpacity.medium))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                Spacer(minLength: 40)
            }

            if let praise = message.praise_pt, !praise.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.success)
                    Text(praise).font(.caption).foregroundStyle(Color.success)
                }
            }

            if let lesson = message.miniLesson {
                MiniLessonCard(lesson: lesson)
            }
        }
    }

    // MARK: - Suggestions

    private var suggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(Array(latestSuggestions.enumerated()), id: \.offset) { _, suggestion in
                    Button {
                        input = suggestion
                        inputFocused = true
                    } label: {
                        Text(suggestion)
                            .font(.caption)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(Color.accentColor.opacity(AppOpacity.subtle))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.sm) {
            TextField("Schreib auf Deutsch…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
            Button(action: send) {
                Image(systemName: "paperplane.fill").font(.title3)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding(AppSpacing.md)
    }

    private func retryPill(_ message: String) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(message).font(.caption).foregroundStyle(Color.danger)
            Button {
                if let failed = lastFailedInput { retry(failed) }
            } label: {
                Label("Tentar novamente", systemImage: "arrow.clockwise")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Logic

    private func load() {
        guard !didLoad else { return }   // só na primeira aparição desta instância
        didLoad = true
        messages = chat.messages
        memory = chat.memory
        level = chat.levelCEFR ?? memory.levelEstimate ?? "B1"

        // Reconcilia uma mensagem do usuário sem resposta: acontece quando o usuário
        // saiu da conversa enquanto a tutora respondia (o turno foi cancelado em
        // onDisappear, deixando só a bolha do aluno persistida). Re-dispara o turno
        // para que a view recriada mostre o spinner e a resposta — mantendo o @State
        // consistente com o blob persistido.
        if !isLoading, let last = messages.last,
           last.role == .user, last.corrections == nil {
            runTurn(last.text_de, priorHistory: Array(messages.dropLast()))
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        input = ""
        errorText = nil
        let priorHistory = messages
        messages.append(ChatMessage(role: .user, text_de: text))
        persist()
        runTurn(text, priorHistory: priorHistory)
    }

    private func retry(_ text: String) {
        guard !isLoading else { return }
        errorText = nil
        lastFailedInput = nil
        // O histórico já contém a mensagem do usuário (não foi removida na falha).
        let priorHistory = Array(messages.dropLast())
        runTurn(text, priorHistory: priorHistory)
    }

    private func runTurn(_ text: String, priorHistory: [ChatMessage]) {
        isLoading = true
        turnTask?.cancel()
        turnTask = Task {
            do {
                let turn = try await service.respond(
                    to: text, history: priorHistory, memory: memory, levelCEFR: level
                )
                if Task.isCancelled { return }   // usuário saiu: não escreve em view morta
                await MainActor.run { applyTurn(turn) }
            } catch let err as LLMError {
                if Task.isCancelled { return }
                await MainActor.run { fail(err.localizedDescription, input: text) }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run { fail(error.localizedDescription, input: text) }
            }
        }
    }

    @MainActor
    private func applyTurn(_ turn: TutorTurn) {
        // Anexa correções à última mensagem do usuário PRESERVANDO nil vs [].
        //  - nil  → turno não avaliado (fallback de texto puro): nem chip nem "Perfeito!".
        //  - []   → avaliado e limpo (modelo devolveu "corrections": []): mostra "Perfeito!".
        //  - [..] → mostra chips.
        if let idx = messages.lastIndex(where: { $0.role == .user }) {
            messages[idx].corrections = turn.corrections
        }

        // Gate de cadência do cliente (fonte da verdade): bloqueia aulas próximas demais.
        let hasBlocking = (turn.corrections ?? []).contains { $0.severityEnum == .blocking }
        let lessonSurfaced = turn.mini_lesson != nil
            && (memory.turnsSinceLastLesson >= 3 || hasBlocking)
            && (turn.mini_lesson?.skill_tag != memory.lastTaughtSkill)

        messages.append(ChatMessage(
            role: .tutor,
            text_de: turn.reply_de,
            praise_pt: turn.praise_pt,
            miniLesson: lessonSurfaced ? turn.mini_lesson : nil,
            suggestedReplies_de: turn.suggested_replies_de
        ))
        // Funde a memória registrando EXATAMENTE o skill_tag que apareceu (não o
        // last_taught_skill solto do modelo) — assim o anti-repetição do próximo
        // turno compara contra a aula que o aluno realmente viu.
        let surfacedTag = lessonSurfaced ? turn.mini_lesson?.skill_tag : nil
        memory.fold(turn.memory_update, lessonSurfaced: lessonSurfaced, surfacedSkillTag: surfacedTag)
        if let lvl = memory.levelEstimate, !lvl.isEmpty { level = lvl }
        isLoading = false
        errorText = nil
        lastFailedInput = nil
        persist()
    }

    @MainActor
    private func fail(_ message: String, input failedInput: String) {
        isLoading = false
        errorText = message
        lastFailedInput = failedInput
    }

    private func persist() {
        chat.messages = messages
        chat.memory = memory
        chat.levelCEFR = level
        chat.lastMessageAt = .now
        if chat.title == "Neues Gespräch",
           let first = messages.first(where: { $0.role == .user }) {
            chat.title = String(first.text_de.prefix(40))
        }
        try? modelContext.save()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if isLoading {
                proxy.scrollTo("loading", anchor: .bottom)
            } else if let last = messages.last?.id {
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }
}

/// Card de micro-aula proativa (raro). Começa expandido — é intencional e merecido.
private struct MiniLessonCard: View {
    let lesson: MiniLesson
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "lightbulb.fill").foregroundStyle(Color.warning)
                Text(lesson.title_pt ?? "Dica da Lara").font(.subheadline.bold())
                Spacer()
                Button {
                    withAnimation(.snappy) { collapsed.toggle() }
                } label: {
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let trigger = lesson.trigger_pt, !trigger.isEmpty {
                Text("Por que agora: \(trigger)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !collapsed {
                if let body = lesson.body_pt, !body.isEmpty {
                    Text(body).font(.callout)
                }
                if !lesson.examples.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(Array(lesson.examples.enumerated()), id: \.offset) { _, ex in
                            Text(ex)
                                .font(.callout.monospaced())
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, AppSpacing.xs)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.info.opacity(AppOpacity.subtle))
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                        }
                    }
                }
            }
        }
        .appCard(tone: .medium, radius: .card)
    }
}
