import WidgetKit
import SwiftUI

/// Widget extension: currently the flight Live Activity (Lock Screen + Dynamic Island).
@main
struct ThailandWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FlightLiveActivity()
    }
}
