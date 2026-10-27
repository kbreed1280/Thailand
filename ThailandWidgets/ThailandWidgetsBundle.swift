import WidgetKit
import SwiftUI

/// Widget extension: the flight and day-plan Live Activities, plus the Lock Screen Nashville/local clock.
@main
struct ThailandWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FlightLiveActivity()
        DayPlanLiveActivity()
        DualClockWidget()
    }
}
