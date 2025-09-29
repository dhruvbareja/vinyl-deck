import SwiftUI

struct TonearmView: View {
    @Binding var playing: Bool   // if true → needle on vinyl, else away

    var body: some View {
        Rectangle()
            .fill(Color.gray)
            .frame(width: 8, height: 160)
            .cornerRadius(4)
            .rotationEffect(.degrees(playing ? -25 : -60), anchor: .topLeading)
            .offset(x: 100, y: -40)
            .shadow(radius: 4)
            .animation(.easeInOut(duration: 0.8), value: playing)
    }
}
