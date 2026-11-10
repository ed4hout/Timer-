import SwiftUI

struct PlanView: View {
    @EnvironmentObject var model: AppModel
    @State private var saving = false
    @State private var name = ""
    @State private var looksOpen = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Header(accent: model.color(.done))

                    HStack(alignment: .firstTextBaseline) {
                        Text("SCHEMA").font(.cond(28).italic())
                        Spacer()
                        Text("Totaal ").font(.system(size: 14)).foregroundColor(Theme.muted)
                            + Text(fmt(model.total)).font(.cond(22))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                saving = true
                                nameFocused = true
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Image(systemName: "plus").font(.system(size: 18, weight: .bold))
                                    Text("Training opslaan").font(.system(size: 12)).foregroundColor(Theme.muted)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .frame(minWidth: 96, minHeight: 56, alignment: .leading)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            }
                            .buttonStyle(.plain)

                            ForEach(model.favorites) { fav in
                                FavoriteTile(fav: fav, selected: model.isSelected(fav),
                                             onTap: { model.apply(fav) },
                                             onDelete: { model.delete(fav) })
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if saving {
                        HStack(spacing: 8) {
                            TextField("Naam, bijv. Benen", text: $name)
                                .focused($nameFocused)
                                .submitLabel(.done)
                                .onSubmit(save)
                                .padding(12)
                                .background(Theme.card2)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Button("Bewaar", action: save)
                                .buttonStyle(PillButtonStyle(primary: true))
                                .frame(width: 96)
                            Button { saving = false; name = "" } label: { Image(systemName: "xmark") }
                                .buttonStyle(PillButtonStyle())
                                .frame(width: 48)
                        }
                    }

                    Card(padding: 12) {
                        VStack(spacing: 0) {
                            StepperRow(title: "Voorbereiding", dot: model.color(.prep), key: \.prep, step: 5, range: 0...60, isTime: true)
                            Divider().overlay(Theme.line)
                            StepperRow(title: "Werk", dot: model.color(.work), key: \.work, step: 5, range: 5...600, isTime: true)
                            Divider().overlay(Theme.line)
                            StepperRow(title: "Rust", dot: model.color(.rest), key: \.rest, step: 5, range: 0...600, isTime: true)
                            Divider().overlay(Theme.line)
                            StepperRow(title: "Rondes", dot: .white, key: \.rounds, step: 1, range: 1...30, isTime: false)
                            Divider().overlay(Theme.line)
                            StepperRow(title: "Sets", dot: .white, key: \.sets, step: 1, range: 1...10, isTime: false)
                            Divider().overlay(Theme.line)
                            StepperRow(title: "Pauze tussen sets", dot: model.color(.setrest), key: \.setrest, step: 5, range: 0...600, isTime: true)
                        }
                    }

                    Card(padding: 14) {
                        DisclosureGroup(isExpanded: $looksOpen) {
                            VStack(spacing: 8) {
                                ForEach(LookKey.allCases) { k in LookRow(key: k) }
                                Text("Letters, cijfers en ! ? - . / : + ♥ · max. 8 tekens")
                                    .font(.system(size: 11)).foregroundColor(Theme.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Standaard herstellen") { model.looks = Looks() }
                                    .buttonStyle(PillButtonStyle())
                            }
                            .padding(.top, 10)
                        } label: {
                            HStack {
                                Text("Teksten & kleuren").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                                Spacer()
                                HStack(spacing: 4) {
                                    ForEach([LookKey.prep, .work, .rest, .setrest, .done]) { k in
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(hex: model.looks[k].hex))
                                            .frame(width: 12, height: 12)
                                    }
                                }
                            }
                        }
                        .tint(Theme.muted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func save() {
        model.saveFavorite(name)
        if !name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = ""
            saving = false
            nameFocused = false
        }
    }
}

private struct FavoriteTile: View {
    let fav: Favorite
    let selected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("★ " + fav.name.uppercased())
                    .font(.cond(18).italic())
                    .lineLimit(1)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            }
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.muted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 9)
        .frame(minHeight: 56)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(selected ? Color(hex: fav.looks[.prep].hex) : Theme.line, lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var desc: String {
        let c = fav.config
        var s = "\(c.work)s / \(c.rest)s · \(c.rounds) rondes"
        if c.sets > 1 { s += " · \(c.sets) sets" }
        return s
    }
}

private struct StepperRow: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let dot: Color
    let key: WritableKeyPath<WorkoutConfig, Int>
    let step: Int
    let range: ClosedRange<Int>
    let isTime: Bool

    var body: some View {
        let v = model.config[keyPath: key]
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(dot).frame(width: 10, height: 10)
            Text(title).font(.system(size: 16, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                stepButton("minus", -step)
                Text(isTime ? fmt(Double(v)) : "\(v)")
                    .font(.cond(22, .bold))
                    .monospacedDigit()
                    .frame(minWidth: 56)
                stepButton("plus", step)
            }
        }
        .padding(.vertical, 6)
    }

    private func stepButton(_ icon: String, _ delta: Int) -> some View {
        Button { model.change(key, by: delta, range: range) } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(Theme.card2)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct LookRow: View {
    @EnvironmentObject var model: AppModel
    let key: LookKey

    var body: some View {
        HStack(spacing: 8) {
            Text(key.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.muted)
                .frame(width: 96, alignment: .leading)
            ColorPicker("", selection: Binding(
                get: { Color(hex: model.looks[key].hex) },
                set: { model.looks[key].hex = $0.hexString }
            ), supportsOpacity: false)
            .labelsHidden()
            TextField(Looks.defaults[key]?.text ?? "", text: Binding(
                get: { model.looks[key].text },
                set: { model.looks[key].text = PixelFont.sanitize($0) }
            ))
            .font(.system(size: 16, weight: .semibold))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .padding(10)
            .background(Theme.card2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
