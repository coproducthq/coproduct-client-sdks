import UIKit

/// Maps the platform's own interface idiom to the phone or tablet vocabulary.
/// This is a declaration the OS makes, not an inference from screen size, which
/// is why iOS needs no classification policy the way Android does
enum DeviceClassifier {
    static func deviceType(for idiom: UIUserInterfaceIdiom) -> String? {
        switch idiom {
        case .phone:
            return "phone"
        case .pad:
            return "tablet"
        default:
            // Television, CarPlay, Mac, Vision, unspecified, and any idiom added
            // later. Omitting rather than guessing keeps is_set and is_not_set
            // meaningful
            return nil
        }
    }
}
