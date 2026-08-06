import SwiftUI

struct RandomizerView: View {
  var body: some View {
    EmptyFeatureView(
      title: "Nothing eligible yet",
      systemImage: "shuffle",
      message: "In-progress projects and pages will appear after the Randomizer contract is connected."
    )
    .navigationTitle("Randomizer")
  }
}
