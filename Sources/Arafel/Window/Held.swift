import SwiftUI

/// A view's own value, kept with `@StateObject`. Not `@State`: from the macOS 27 SDK on, `@State` is a macro whose
/// plugin ships with Xcode only, and this package builds with the Command Line Tools.
final class Held<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
