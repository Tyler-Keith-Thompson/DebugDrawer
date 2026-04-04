#if DEBUG
    import SwiftUI

    #if os(macOS)
    import AppKit

    // MARK: - Audit issue model

    public struct A11yIssue: Identifiable {
        public let id = UUID()
        public let severity: Severity
        public let category: Category
        public let message: String
        public let viewClass: String
        public let frame: CGRect
        public let wcagRef: String?
        public weak var view: NSView?

        public enum Severity: Int, Comparable, CaseIterable {
            case critical = 0
            case warning = 1
            case suggestion = 2

            public static func < (lhs: Severity, rhs: Severity) -> Bool {
                lhs.rawValue < rhs.rawValue
            }

            var label: String {
                switch self {
                case .critical: "Critical"
                case .warning: "Warning"
                case .suggestion: "Suggestion"
                }
            }

            var color: Color {
                switch self {
                case .critical: .red
                case .warning: .orange
                case .suggestion: .blue
                }
            }

            var icon: String {
                switch self {
                case .critical: "xmark.octagon.fill"
                case .warning: "exclamationmark.triangle.fill"
                case .suggestion: "info.circle.fill"
                }
            }
        }

        public enum Category: String, CaseIterable {
            case label = "Labels"
            case hitTarget = "Hit Targets"
            case contrast = "Contrast"
            case traits = "Traits"
            case hierarchy = "Hierarchy"
        }
    }

    // MARK: - Auditor

    @MainActor
    final class A11yAuditor {
        /// Minimum hit target size (Apple HIG: 44pt)
        private let minHitTargetSize: CGFloat = 44

        func audit(view: NSView) -> [A11yIssue] {
            var issues: [A11yIssue] = []
            auditRecursive(view: view, issues: &issues, depth: 0)
            return issues.sorted { $0.severity < $1.severity }
        }

        private func auditRecursive(view: NSView, issues: inout [A11yIssue], depth: Int) {
            guard !view.isHidden, view.alphaValue > 0.01 else { return }
            guard depth < 30 else { return }

            let className = String(describing: type(of: view))

            // --- Label checks ---
            checkMissingLabel(view: view, className: className, issues: &issues)

            // --- Hit target size ---
            checkHitTargetSize(view: view, className: className, issues: &issues)

            // --- Contrast ---
            checkContrast(view: view, className: className, issues: &issues)

            // --- Traits ---
            checkTraits(view: view, className: className, issues: &issues)

            // --- Heading hierarchy ---
            checkHeadingHierarchy(view: view, className: className, issues: &issues)

            // Recurse
            for subview in view.subviews {
                auditRecursive(view: subview, issues: &issues, depth: depth + 1)
            }
        }

        // MARK: - Label checks

        private func checkMissingLabel(view: NSView, className: String, issues: inout [A11yIssue]) {
            // Interactive controls must have an accessibility label
            let isInteractive = view is NSButton || view is NSSegmentedControl ||
                view is NSTextField || view is NSSlider || view is NSPopUpButton ||
                view is NSStepper || view is NSSwitch ||
                className.contains("Button") || className.contains("Toggle") ||
                className.contains("Slider") || className.contains("Picker")

            guard isInteractive else { return }

            let label = view.accessibilityLabel()
            let title = (view as? NSButton)?.title

            if label == nil || label?.isEmpty == true, title == nil || title?.isEmpty == true {
                issues.append(A11yIssue(
                    severity: .critical,
                    category: .label,
                    message: "Interactive control has no accessibility label",
                    viewClass: className,
                    frame: view.frame,
                    wcagRef: "WCAG 1.1.1",
                    view: view
                ))
            }
        }

        // MARK: - Hit target size

        private func checkHitTargetSize(view: NSView, className: String, issues: inout [A11yIssue]) {
            let isClickable = view is NSButton || view is NSSegmentedControl ||
                view is NSPopUpButton || view is NSSwitch ||
                className.contains("Button") || className.contains("Toggle")

            guard isClickable else { return }

            let frame = view.frame
            if frame.width < minHitTargetSize || frame.height < minHitTargetSize {
                let actual = "\(Int(frame.width))×\(Int(frame.height))"
                issues.append(A11yIssue(
                    severity: .warning,
                    category: .hitTarget,
                    message: "Hit target too small: \(actual)pt (minimum 44×44pt)",
                    viewClass: className,
                    frame: frame,
                    wcagRef: "WCAG 2.5.5",
                    view: view
                ))
            }
        }

        // MARK: - Contrast

        private func checkContrast(view: NSView, className: String, issues: inout [A11yIssue]) {
            // Check text views for contrast
            guard let textField = view as? NSTextField, !textField.isHidden else { return }

            let textColor = textField.textColor ?? .labelColor
            let bgColor = effectiveBackgroundColor(of: view) ?? .windowBackgroundColor

            let ratio = contrastRatio(textColor, bgColor)

            // WCAG AA: 4.5:1 for normal text, 3:1 for large text (18pt+ or 14pt+ bold)
            let fontSize = textField.font?.pointSize ?? 12
            let isBold = textField.font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isLargeText = fontSize >= 18 || (fontSize >= 14 && isBold)
            let requiredRatio: CGFloat = isLargeText ? 3.0 : 4.5

            if ratio < requiredRatio {
                issues.append(A11yIssue(
                    severity: ratio < 2.0 ? .critical : .warning,
                    category: .contrast,
                    message: String(format: "Low contrast ratio: %.1f:1 (need %.1f:1)", ratio, requiredRatio),
                    viewClass: className,
                    frame: view.frame,
                    wcagRef: "WCAG 1.4.3",
                    view: view
                ))
            }
        }

        private func effectiveBackgroundColor(of view: NSView) -> NSColor? {
            var current: NSView? = view
            while let v = current {
                if let bg = v.layer?.backgroundColor, bg.alpha > 0.01 {
                    return NSColor(cgColor: bg)
                }
                current = v.superview
            }
            return nil
        }

        private func contrastRatio(_ c1: NSColor, _ c2: NSColor) -> CGFloat {
            let l1 = relativeLuminance(c1)
            let l2 = relativeLuminance(c2)
            let lighter = max(l1, l2)
            let darker = min(l1, l2)
            return (lighter + 0.05) / (darker + 0.05)
        }

        private func relativeLuminance(_ color: NSColor) -> CGFloat {
            guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
            func linearize(_ c: CGFloat) -> CGFloat {
                c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            let r = linearize(rgb.redComponent)
            let g = linearize(rgb.greenComponent)
            let b = linearize(rgb.blueComponent)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        // MARK: - Traits

        private func checkTraits(view: NSView, className: String, issues: inout [A11yIssue]) {
            // Images should have a description or be marked decorative
            if className.contains("ImageView") || className.contains("NSImageView") {
                let label = view.accessibilityLabel()
                let role = view.accessibilityRole()
                if label == nil || label?.isEmpty == true, role != .image {
                    issues.append(A11yIssue(
                        severity: .warning,
                        category: .traits,
                        message: "Image has no accessibility description",
                        viewClass: className,
                        frame: view.frame,
                        wcagRef: "WCAG 1.1.1",
                        view: view
                    ))
                }
            }
        }

        // MARK: - Heading hierarchy

        private func checkHeadingHierarchy(view: NSView, className: String, issues: inout [A11yIssue]) {
            // Check for text that looks like a heading but isn't marked as one
            guard let textField = view as? NSTextField else { return }
            let fontSize = textField.font?.pointSize ?? 12
            let isBold = textField.font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false

            if fontSize >= 16, isBold {
                let role = view.accessibilityRole()
                if role != .staticText {
                    // This might not be an issue — just a suggestion
                    // Only flag if it looks like a heading but has no heading role set
                }
                // Check if subrole is set to heading
                let subrole = view.accessibilitySubrole()
                if subrole == nil {
                    issues.append(A11yIssue(
                        severity: .suggestion,
                        category: .hierarchy,
                        message: "Large bold text may need heading accessibility trait",
                        viewClass: className,
                        frame: view.frame,
                        wcagRef: "WCAG 1.3.1",
                        view: view
                    ))
                }
            }
        }
    }

    // MARK: - Audit result

    struct AuditResult {
        let issues: [A11yIssue]
        let viewCount: Int
        let timestamp: Date

        var score: Int {
            guard viewCount > 0 else { return 100 }
            let criticalPenalty = issues.filter { $0.severity == .critical }.count * 15
            let warningPenalty = issues.filter { $0.severity == .warning }.count * 5
            let suggestionPenalty = issues.filter { $0.severity == .suggestion }.count * 1
            return max(0, 100 - criticalPenalty - warningPenalty - suggestionPenalty)
        }

        var scoreColor: Color {
            if score >= 90 { return .green }
            if score >= 70 { return .yellow }
            if score >= 50 { return .orange }
            return .red
        }
    }

    // MARK: - Auditor UI

    struct A11yAuditorView: View {
        @State private var result: AuditResult?
        @State private var isAuditing = false
        @State private var filterSeverity: A11yIssue.Severity?
        @State private var filterCategory: A11yIssue.Category?

        var filteredIssues: [A11yIssue] {
            guard let result else { return [] }
            var issues = result.issues
            if let sev = filterSeverity {
                issues = issues.filter { $0.severity == sev }
            }
            if let cat = filterCategory {
                issues = issues.filter { $0.category == cat }
            }
            return issues
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Run button
                HStack {
                    Button(result == nil ? "Run Audit" : "Re-Audit") { runAudit() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isAuditing)

                    if isAuditing {
                        ProgressView().controlSize(.small)
                    }

                    Spacer()

                    if let result {
                        // Score badge
                        HStack(spacing: 4) {
                            Text("\(result.score)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(result.scoreColor)
                            Text("/ 100")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let result {
                    // Summary
                    HStack(spacing: 12) {
                        severityBadge(.critical, count: result.issues.filter { $0.severity == .critical }.count)
                        severityBadge(.warning, count: result.issues.filter { $0.severity == .warning }.count)
                        severityBadge(.suggestion, count: result.issues.filter { $0.severity == .suggestion }.count)
                    }

                    // Filters
                    HStack(spacing: 4) {
                        filterButton("All", isActive: filterSeverity == nil && filterCategory == nil) {
                            filterSeverity = nil
                            filterCategory = nil
                        }
                        ForEach(A11yIssue.Severity.allCases, id: \.rawValue) { sev in
                            filterButton(sev.label, color: sev.color, isActive: filterSeverity == sev) {
                                filterSeverity = filterSeverity == sev ? nil : sev
                                filterCategory = nil
                            }
                        }
                    }

                    // Issues list
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredIssues) { issue in
                                issueRow(issue)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .background(Color.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    // Export
                    HStack {
                        Text("\(result.viewCount) views audited")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy Report") { copyReport() }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }

        private func runAudit() {
            isAuditing = true
            DispatchQueue.main.async {
                guard let contentView = NSApp?.keyWindow?.contentView else {
                    isAuditing = false
                    return
                }

                let auditor = A11yAuditor()
                let issues = auditor.audit(view: contentView)
                let viewCount = countViews(contentView)

                result = AuditResult(issues: issues, viewCount: viewCount, timestamp: Date())
                isAuditing = false
            }
        }

        private func countViews(_ view: NSView) -> Int {
            1 + view.subviews.reduce(0) { $0 + countViews($1) }
        }

        private func severityBadge(_ severity: A11yIssue.Severity, count: Int) -> some View {
            HStack(spacing: 3) {
                Image(systemName: severity.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(severity.color)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
        }

        private func filterButton(_ label: String, color: Color = .secondary, isActive: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(label)
                    .font(.system(size: 9, weight: isActive ? .bold : .regular))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isActive ? color.opacity(0.2) : Color.clear)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }

        private func issueRow(_ issue: A11yIssue) -> some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: issue.severity.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(issue.severity.color)

                        Text(issue.message)
                            .font(.system(size: 10))
                            .lineLimit(2)

                        Spacer()

                        if let ref = issue.wcagRef {
                            Text(ref)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(issue.viewClass)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text("\(Int(issue.frame.width))×\(Int(issue.frame.height))")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)

                        Text(issue.category.rawValue)
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(2)

                        Spacer()

                        if issue.view != nil {
                            Button("Highlight") { highlightView(issue) }
                                .font(.system(size: 9))
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(issue.severity.color)
                        .frame(width: 2)
                }

                Divider().padding(.leading, 6)
            }
        }

        private func highlightView(_ issue: A11yIssue) {
            guard let view = issue.view else { return }
            view.wantsLayer = true

            let highlight = NSView(frame: view.bounds)
            highlight.wantsLayer = true
            highlight.layer?.borderWidth = 3
            highlight.layer?.borderColor = NSColor(issue.severity.color).withAlphaComponent(0.8).cgColor
            highlight.layer?.backgroundColor = NSColor(issue.severity.color).withAlphaComponent(0.1).cgColor
            highlight.layer?.cornerRadius = 3
            view.addSubview(highlight)

            // Flash repeatedly for ~10 seconds so the user can collapse the drawer and still see it
            var flashCount = 0
            let maxFlashes = 10

            func flash() {
                guard flashCount < maxFlashes, highlight.superview != nil else {
                    highlight.removeFromSuperview()
                    return
                }
                flashCount += 1
                highlight.alphaValue = 1.0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.5
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    highlight.animator().alphaValue = 0.1
                } completionHandler: {
                    flash()
                }
            }
            flash()
        }

        private func copyReport() {
            guard let result else { return }
            var lines: [String] = [
                "Accessibility Audit Report",
                "Score: \(result.score)/100",
                "Views: \(result.viewCount)",
                "Issues: \(result.issues.count)",
                "Date: \(result.timestamp.formatted())",
                "",
            ]

            for issue in result.issues {
                let sev = issue.severity.label.uppercased()
                let ref = issue.wcagRef ?? ""
                lines.append("[\(sev)] \(issue.message) — \(issue.viewClass) \(ref)")
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        }
    }

    #endif // os(macOS)

#endif
