import SwiftUI

/// Shared presentation for the onboarding interview flow:
/// full-screen cover on iOS, large sheet on macOS.
private struct OnboardingPresenterModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content.sheet(isPresented: $isPresented) {
            OnboardingFlowView()
                .frame(minWidth: 640, minHeight: 700)
        }
        #else
        content.fullScreenCover(isPresented: $isPresented) {
            OnboardingFlowView()
        }
        #endif
    }
}

extension View {
    /// Presents `OnboardingFlowView` platform-appropriately.
    func onboardingInterviewCover(isPresented: Binding<Bool>) -> some View {
        modifier(OnboardingPresenterModifier(isPresented: isPresented))
    }
}
