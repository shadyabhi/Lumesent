import AppKit
import SwiftUI

struct AlertGridView: View {
    @ObservedObject var model: AlertGridModel
    let layout: AlertLayout
    let onDismissCard: (UUID) -> Void
    let onDismissAll: () -> Void

    private var cardMinHeight: CGFloat { layout == .banner ? 200 : 280 }

    /// Widen the card when any notification has a lot of text so long bodies
    /// wrap onto fewer lines instead of growing tall enough to overflow the
    /// screen vertically. All cards in the grid share the same width for
    /// visual consistency.
    private var cardWidth: CGFloat {
        if layout == .banner { return 340 }
        let longest = model.cards.map(Self.textLength(for:)).max() ?? 0
        switch longest {
        case ..<300:  return 400
        case ..<800:  return 560
        case ..<1500: return 720
        default:      return 900
        }
    }

    /// Reduce column count as cards get wider so the grid still fits the screen.
    private var maxColumns: Int {
        if layout == .banner { return 2 }
        switch cardWidth {
        case ..<500: return 3
        case ..<650: return 2
        default:     return 1
        }
    }

    private static func textLength(for card: AlertGridModel.CardItem) -> Int {
        card.notification.title.count
            + card.notification.subtitle.count
            + card.notification.body.count
    }

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .fullScreenUI, blendingMode: .behindWindow)
                .opacity(model.cards.isEmpty ? 0 : 1)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(backgroundOpacity))
                .onTapGesture {
                    let hasSticky = model.cards.contains { $0.displayMode.isSticky }
                    if !hasSticky { onDismissAll() }
                }

            let width = cardWidth
            let columns = max(1, min(model.cards.count, maxColumns))
            let gridContent = LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(width), spacing: 16), count: columns),
                spacing: 16
            ) {
                ForEach(model.cards) { card in
                    let dismissed = model.pendingDismissals.contains(card.id)
                    AlertCardView(
                        card: card,
                        layout: layout,
                        cardWidth: width,
                        onDismiss: { onDismissCard(card.id) }
                    )
                    .frame(idealWidth: width, minHeight: cardMinHeight)
                    .frame(width: width)
                    .opacity(dismissed ? 0 : 1)
                    .allowsHitTesting(!dismissed)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                }
            }
            .fixedSize(horizontal: true, vertical: true)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.cards.map(\.id))

            if layout == .banner {
                VStack {
                    gridContent
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    Spacer()
                }
            } else {
                gridContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var backgroundOpacity: Double {
        if model.cards.isEmpty { return 0 }
        if layout == .banner { return 0.3 }
        let visibleCount = model.visibleCards.count
        return min(0.85, 0.4 + Double(visibleCount) * 0.15)
    }
}

struct AlertCardView: View {
    let card: AlertGridModel.CardItem
    let layout: AlertLayout
    let cardWidth: CGFloat
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?
    @State private var resolvedAppIcon: NSImage?

    private var titleSize: CGFloat { layout == .banner ? 18 : 24 }
    private var bodySize: CGFloat { layout == .banner ? 13 : 16 }
    private var iconSize: CGFloat { layout == .banner ? 32 : 44 }

    var body: some View {
        VStack(spacing: layout == .banner ? 8 : 14) {
            appIconView
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)

            Text(card.notification.appName)
                .font(layout == .banner ? .caption : .subheadline)
                .foregroundStyle(.secondary)

            Text(card.notification.title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            if !card.notification.subtitle.isEmpty {
                Text(card.notification.subtitle)
                    .font(.system(size: titleSize * 0.75, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }

            if !card.notification.body.isEmpty {
                markdownText(card.notification.body, fontSize: bodySize)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Dismiss") { onDismiss() }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.small)
                .padding(.top, 2)
                .accessibilityLabel("Dismiss alert")
                .accessibilityHint("Dismiss this notification alert")

            Text(elapsedTimeString)
                .font(.system(size: layout == .banner ? 11 : 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 2)
        }
        .padding(layout == .banner ? 16 : 24)
        .onAppear {
            startTimer()
            resolvedAppIcon = Self.resolveAppIcon(for: card.notification.appIdentifier)
            withAnimation(.easeOut(duration: 0.25)) {
                appeared = true
            }
        }
        .onDisappear { timer?.invalidate() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .scaleEffect(appeared ? 1.0 : 0.85)
        .opacity(appeared ? 1.0 : 0.0)
    }

    @ViewBuilder
    private var appIconView: some View {
        if let icon = resolvedAppIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var elapsedTimeString: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    private func markdownText(_ string: String, fontSize: CGFloat) -> some View {
        MarkdownTextView(
            string: string,
            fontSize: fontSize,
            textColor: NSColor.white.withAlphaComponent(0.85),
            maxWidth: cardWidth - (layout == .banner ? 32 : 48)
        )
    }

    private static func resolveAppIcon(for bundleId: String) -> NSImage? {
        guard bundleId != "external" else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Markdown rendering

/// Self-sizing NSTextView wrapper that renders CommonMark markdown with proper
/// block-level support (code blocks, headers, lists, blockquotes) plus inline
/// styling (bold, italic, inline code with background).
struct MarkdownTextView: NSViewRepresentable {
    let string: String
    let fontSize: CGFloat
    let textColor: NSColor
    let maxWidth: CGFloat

    func makeNSView(context: Context) -> SelfSizingTextView {
        let tv = SelfSizingTextView(maxLayoutWidth: maxWidth)
        tv.isEditable = false
        tv.isSelectable = false
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateNSView(_ tv: SelfSizingTextView, context: Context) {
        tv.maxLayoutWidth = maxWidth
        tv.textContainer?.size = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
        tv.textStorage?.setAttributedString(MarkdownRenderer.render(
            string, fontSize: fontSize, textColor: textColor, maxWidth: maxWidth
        ))
        tv.invalidateIntrinsicContentSize()
    }
}

/// NSTextView subclass that reports its intrinsic height based on laid-out text.
final class SelfSizingTextView: NSTextView {
    var maxLayoutWidth: CGFloat

    init(maxLayoutWidth: CGFloat) {
        self.maxLayoutWidth = maxLayoutWidth
        let container = NSTextContainer(size: NSSize(width: maxLayoutWidth, height: .greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()
        let storage = NSTextStorage()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        container.widthTracksTextView = true
        super.init(frame: .zero, textContainer: container)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else { return .zero }
        lm.ensureLayout(for: tc)
        let rect = lm.usedRect(for: tc)
        return NSSize(width: maxLayoutWidth, height: ceil(rect.height))
    }
}

/// Converts a markdown string into an NSAttributedString with styled block and
/// inline elements suitable for display in a dark alert card.
enum MarkdownRenderer {
    static func render(_ markdown: String, fontSize: CGFloat, textColor: NSColor, maxWidth: CGFloat) -> NSAttributedString {
        // Convert bare newlines to paragraph breaks so the CommonMark parser
        // creates distinct paragraph blocks for each line.  Hard line breaks
        // (two trailing spaces) aren't reliably preserved by Apple's
        // AttributedString markdown parser, but paragraph breaks are.
        let prepared = markdown.replacingOccurrences(
            of: "(?<!\n)\n(?!\n)",
            with: "\n\n",
            options: .regularExpression
        )
        guard let parsed = try? AttributedString(
            markdown: prepared,
            options: .init(interpretedSyntax: .full)
        ) else {
            return plain(markdown, fontSize: fontSize, textColor: textColor)
        }

        let baseFont = NSFont.systemFont(ofSize: fontSize)
        let codeFont = NSFont.monospacedSystemFont(ofSize: fontSize * 0.9, weight: .regular)
        let codeBg = NSColor.white.withAlphaComponent(0.12)
        let result = NSMutableAttributedString()
        var lastParagraphIdentity: Int?

        for run in parsed.runs {
            let text = String(parsed[run.range].characters)

            // Insert a newline between distinct paragraph-level blocks so
            // that each original line appears on its own line in the alert.
            if let intent = run.presentationIntent,
               let paraComponent = intent.components.first(where: {
                   if case .paragraph = $0.kind { return true }; return false
               }) {
                let pid = paraComponent.identity
                if let prev = lastParagraphIdentity, pid != prev, result.length > 0 {
                    result.append(NSAttributedString(string: "\n"))
                }
                lastParagraphIdentity = pid
            }
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.alignment = .center

            var font: NSFont = baseFont
            var fgColor: NSColor = textColor
            var bgColor: NSColor? = nil

            // --- Block-level intent ---
            if let intent = run.presentationIntent {
                for component in intent.components {
                    switch component.kind {
                    case .header(let level):
                        let sizes: [CGFloat] = [1.6, 1.35, 1.15, 1.0, 0.9, 0.85]
                        let scale = sizes[min(level - 1, sizes.count - 1)]
                        font = NSFont.systemFont(ofSize: fontSize * scale, weight: level <= 2 ? .bold : .semibold)
                    case .codeBlock:
                        font = NSFont.monospacedSystemFont(ofSize: fontSize * 0.9, weight: .regular)
                        bgColor = codeBg
                        paraStyle.alignment = .left
                        paraStyle.headIndent = 8
                        paraStyle.firstLineHeadIndent = 8
                        paraStyle.tailIndent = -8
                    case .blockQuote:
                        fgColor = textColor.withAlphaComponent(0.65)
                        paraStyle.headIndent = 16
                        paraStyle.firstLineHeadIndent = 16
                    case .orderedList, .unorderedList:
                        paraStyle.headIndent = 20
                        paraStyle.firstLineHeadIndent = 8
                        paraStyle.alignment = .left
                    case .listItem(let ordinal):
                        let bullet = ordinal > 0 ? "\(ordinal). " : "• "
                        let bulletAttr = NSAttributedString(string: bullet, attributes: [
                            .font: baseFont,
                            .foregroundColor: textColor.withAlphaComponent(0.6),
                            .paragraphStyle: paraStyle,
                        ])
                        result.append(bulletAttr)
                    case .thematicBreak:
                        let hr = NSMutableAttributedString(string: "\n―――\n", attributes: [
                            .font: NSFont.systemFont(ofSize: fontSize * 0.8),
                            .foregroundColor: textColor.withAlphaComponent(0.3),
                            .paragraphStyle: paraStyle,
                        ])
                        result.append(hr)
                        continue
                    default:
                        break
                    }
                }
            }

            // --- Inline intent ---
            if let inline = run.inlinePresentationIntent {
                if inline.contains(.code) {
                    font = codeFont
                    bgColor = codeBg
                }
                if inline.contains(.stronglyEmphasized) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                if inline.contains(.emphasized) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                if inline.contains(.strikethrough) {
                    // handled below via attribute
                }
            }

            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: fgColor,
                .paragraphStyle: paraStyle,
            ]
            if let bg = bgColor {
                attrs[.backgroundColor] = bg
            }
            if run.inlinePresentationIntent?.contains(.strikethrough) == true {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.strikethroughColor] = fgColor
            }

            result.append(NSAttributedString(string: text, attributes: attrs))
        }

        return result
    }

    private static func plain(_ string: String, fontSize: CGFloat, textColor: NSColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor,
            .paragraphStyle: style,
        ])
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
