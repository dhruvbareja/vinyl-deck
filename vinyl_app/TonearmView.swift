import SwiftUI

struct TonearmView: View {
    // states you should wire into your deck's playback control
    @Binding var isOnRecord: Bool
    @State private var dragTranslation: CGSize = .zero
    @GestureState private var dragState: CGSize = .zero

    // geometry parameters (tweak)
    let parkedAngle: Angle = .degrees(-45)
    let onRecordAngle: Angle = .degrees(-12)

    var body: some View {
        // The visual arm (replace with your existing code)
        ZStack {
            // arm shaft
            RoundedRectangle(cornerRadius: 4)
                .frame(width: 220, height: 8)
                .offset(x: 0, y: -4)
            // head shell
            Circle().frame(width: 34, height: 34)
                .offset(x: 110, y: -6)
        }
        .rotationEffect(isOnRecord ? onRecordAngle : parkedAngle, anchor: .leading)
        // apply drag offset - rotate while dragging
        .rotationEffect(.radians(Double(dragState.width / 900)), anchor: .leading)
        .gesture(
            DragGesture(minimumDistance: 1)
                .updating($dragState) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    // if user dragged sufficiently towards center -> place on record
                    if value.translation.width < -40 { // leftwards drag
                        withAnimation(.interactiveSpring()) { isOnRecord = true }
                    } else if value.translation.width > 40 { // rightwards drag
                        withAnimation(.interactiveSpring()) { isOnRecord = false }
                    } else {
                        // small move: toggle
                        withAnimation(.spring()) { isOnRecord.toggle() }
                    }
                }
        )
        .onTapGesture {
            // keep existing tap toggle
            withAnimation(.spring()) { isOnRecord.toggle() }
        }
    }
}
