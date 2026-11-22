import SwiftUI
import GRECore

struct VocabularyView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .study

    enum Mode: String, CaseIterable, Identifiable {
        case study = "Study"
        case browse = "Word List"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                Spacer()
                let counts = model.analytics.vocabularyCounts(totalWords: model.content?.vocabulary.count ?? 0)
                Pill(text: "\(counts.new) new", color: .blue)
                Pill(text: "\(counts.learning) learning", color: .orange)
                Pill(text: "\(counts.mastered) mastered", color: Theme.correct)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            switch mode {
            case .study: FlashcardStudyView()
            case .browse: WordListView()
            }
        }
        .navigationTitle("Vocabulary")
    }
}

struct FlashcardStudyView: View {
    @Environment(AppModel.self) private var model
    @State private var queue: [VocabWord] = []
    @State private var showAnswer = false
    @State private var reviewedThisSession = 0
    @State private var loaded = false

    var body: some View {
        Group {
            if let word = queue.first {
                card(word)
            } else if loaded {
                done
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: reload)
    }

    private func reload() {
        queue = model.studyQueue()
        showAnswer = false
        loaded = true
    }

    private func card(_ word: VocabWord) -> some View {
        let state = model.cardState(word)
        return VStack(spacing: 22) {
            HStack {
                Text("\(queue.count) to review").foregroundStyle(.secondary)
                Spacer()
                Text(state == nil ? "New word" : "Review").font(.caption.weight(.semibold))
                    .foregroundStyle(state == nil ? Color.blue : Color.orange)
            }
            .frame(maxWidth: 620)

            VStack(spacing: 14) {
                Text(word.word)
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                Text(word.partOfSpeech).italic().foregroundStyle(.secondary)
                if showAnswer {
                    Divider().padding(.vertical, 6)
                    Text(word.definition)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("“\(word.example)”")
                        .italic()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !word.synonyms.isEmpty {
                        Text("Synonyms: \(word.synonyms.joined(separator: ", "))")
                            .font(.callout)
                    }
                }
            }
            .padding(36)
            .frame(maxWidth: 620, minHeight: 300)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

            if showAnswer {
                HStack(spacing: 12) {
                    ForEach(ReviewRating.allCases, id: \.self) { rating in
                        let preview = SpacedRepetition.review(state, wordId: word.id, rating: rating)
                        Button {
                            rate(word, rating)
                        } label: {
                            VStack(spacing: 2) {
                                Text(rating.title).font(.headline)
                                Text(SpacedRepetition.intervalText(preview)).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(width: 100, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(color(for: rating))
                        .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue + 1)")), modifiers: [])
                    }
                }
                Text("Press 1–4 to rate how well you knew it.").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Show Answer") { showAnswer = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
                Text("Try to recall the meaning first, then press Space.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(28)
    }

    private func color(for rating: ReviewRating) -> Color {
        switch rating {
        case .again: return Theme.incorrect
        case .hard: return .orange
        case .good: return Theme.correct
        case .easy: return .blue
        }
    }

    private func rate(_ word: VocabWord, _ rating: ReviewRating) {
        model.review(word, rating: rating)
        reviewedThisSession += 1
        showAnswer = false
        queue.removeFirst()
        if rating == .again {
            // Missed cards come back later in this session.
            queue.insert(word, at: min(queue.count, 5))
        }
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.correct)
            Text(reviewedThisSession > 0 ? "All caught up — \(reviewedThisSession) cards reviewed." : "Nothing due right now.")
                .font(.title2.weight(.semibold))
            Text("New words unlock each day (\(model.progress.newCardsPerDay) per day; change this in Settings). Reviews come back when they're due.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Check Again") { reload() }
        }
    }
}

struct WordListView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var tier = 0
    @State private var selection: VocabWord.ID?

    private var words: [VocabWord] {
        (model.content?.vocabulary ?? []).filter { word in
            (tier == 0 || word.tier == tier) &&
                (search.isEmpty || word.word.localizedCaseInsensitiveContains(search) ||
                    word.definition.localizedCaseInsensitiveContains(search) ||
                    word.synonyms.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search words, definitions, synonyms", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Picker("Tier", selection: $tier) {
                    Text("All tiers").tag(0)
                    Text("Tier 1 · most frequent").tag(1)
                    Text("Tier 2 · common").tag(2)
                    Text("Tier 3 · advanced").tag(3)
                }
                .frame(width: 220)
                Spacer()
                Text("\(words.count) words").foregroundStyle(.secondary)
            }
            .padding(12)
            Table(words, selection: $selection) {
                TableColumn("Word") { word in
                    Text(word.word).fontWeight(.semibold)
                }
                .width(min: 110, ideal: 140)
                TableColumn("Part of speech") { word in
                    Text(word.partOfSpeech).foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100)
                TableColumn("Definition") { word in
                    Text(word.definition)
                }
                TableColumn("Synonyms") { word in
                    Text(word.synonyms.joined(separator: ", ")).foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 200)
                TableColumn("Status") { word in
                    statusText(word)
                }
                .width(min: 70, ideal: 90)
            }
            if let selection, let word = words.first(where: { $0.id == selection }) {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.word).font(.headline)
                    Text("“\(word.example)”").italic().foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func statusText(_ word: VocabWord) -> some View {
        if let state = model.cardState(word) {
            if state.isMastered {
                Text("Mastered").foregroundStyle(Theme.correct)
            } else {
                Text("Learning").foregroundStyle(.orange)
            }
        } else {
            Text("New").foregroundStyle(.secondary)
        }
    }
}
