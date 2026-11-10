import SwiftUI

struct BoardView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var board: Board

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Header(accent: model.color(.done))

                    // Connection
                    Card {
                        HStack {
                            SectionLabel(text: "Bord")
                            Spacer()
                            Text(board.status).font(.system(size: 13, weight: .medium))
                                .foregroundColor(board.isConnected ? Theme.ok : Theme.muted)
                        }
                        HStack(spacing: 8) {
                            Button("Verbinden") { board.connect() }.buttonStyle(PillButtonStyle(primary: true))
                            Button("Verbreken") { board.disconnect() }.buttonStyle(PillButtonStyle())
                        }
                        HStack(spacing: 8) {
                            Button("Bord aan") { board.setPower(true) }.buttonStyle(PillButtonStyle())
                            Button("Bord uit") { board.setPower(false) }.buttonStyle(PillButtonStyle())
                        }
                        HStack {
                            SectionLabel(text: "Helderheid")
                            Text("\(Int(model.brightness))%").font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.top, 4)
                        Slider(value: $model.brightness, in: 5...100, step: 1, onEditingChanged: { editing in
                            if !editing { board.setBrightness(Int(model.brightness)) }
                        })
                        .tint(.white)
                        HStack {
                            SectionLabel(text: "Fijnafstelling bord")
                            Text(String(format: "%+.2f s", model.boardCorrection)).font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.top, 4)
                        Slider(value: $model.boardCorrection, in: -2...2, step: 0.25).tint(.white)
                        Text("De app volgt het bord automatisch. Alleen als het nog iets afwijkt: bord achter → rechts, bord voor → links.")
                            .font(.system(size: 11)).foregroundColor(Theme.muted)
                    }

                    // Sport pictures
                    Card {
                        SectionLabel(text: "Sportplaatjes · tik om te tonen")
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(SportIcon.all) { ic in
                                Button { model.showOnBoard(BoardArt.icon(ic)) } label: {
                                    LEDView(frame: BoardArt.icon(ic))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Message + rotation
                    Card {
                        SectionLabel(text: "Bericht op het bord")
                        HStack(spacing: 8) {
                            TextField("LETS GO!", text: $model.message)
                                .font(.system(size: 18, weight: .semibold))
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(Theme.card2)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Button("Tonen") { model.showOnBoard(BoardArt.message(model.message)) }
                                .buttonStyle(PillButtonStyle(primary: true))
                                .frame(width: 96)
                        }
                        SectionLabel(text: "Draaien").padding(.top, 4)
                        Picker("Draaien", selection: $model.rotation) {
                            Text("0°").tag(0)
                            Text("90°").tag(1)
                            Text("180°").tag(2)
                            Text("270°").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: model.rotation) { _, v in board.setRotation(v) }
                    }

                    // Sound
                    Card {
                        HStack {
                            SectionLabel(text: "Geluid")
                            Text("\(Int(model.soundSettings.volume * 100))%").font(.system(size: 12, weight: .semibold))
                        }
                        Slider(value: $model.soundSettings.volume, in: 0...1).tint(.white)
                        SoundRow(title: "Aftellen 3-2-1", key: \.count, kind: .count, word: "3")
                        SoundRow(title: "Start werk", key: \.work, kind: .phase, word: model.looks.label(.work))
                        SoundRow(title: "Start rust", key: \.rest, kind: .phase, word: model.looks.label(.rest))
                        SoundRow(title: "Einde", key: \.done, kind: .done, word: model.looks.label(.done))
                        Toggle(isOn: $model.soundSettings.duck) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Muziek zachter tijdens training").font(.system(size: 15, weight: .medium))
                                Text("Spotify speelt altijd door; dit zet hem wat zachter")
                                    .font(.system(size: 12)).foregroundColor(Theme.muted)
                            }
                        }
                        .tint(Theme.ok)
                        .padding(.top, 4)
                    }

                    // Other
                    Card {
                        Toggle(isOn: $model.keepAwake) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scherm aan houden").font(.system(size: 15, weight: .medium))
                                Text("Tijdens de training").font(.system(size: 12)).foregroundColor(Theme.muted)
                            }
                        }
                        .tint(Theme.ok)
                        Button("Ander bord zoeken") { board.forgetAndSearch() }
                            .buttonStyle(PillButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct SoundRow: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let key: WritableKeyPath<SoundSettings, SoundChoice>
    let kind: SoundKind
    let word: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.muted)
                .frame(width: 108, alignment: .leading)
            Picker(title, selection: Binding(
                get: { model.soundSettings[keyPath: key] },
                set: { newValue in
                    model.soundSettings[keyPath: key] = newValue
                    model.testSound(key, kind, word: word)
                }
            )) {
                ForEach(SoundChoice.allCases) { c in Text(c.title).tag(c) }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.testSound(key, kind, word: word) } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.card2)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}
