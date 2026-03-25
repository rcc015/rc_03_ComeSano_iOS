//
//  ComeSanoWidgetsIOSBundle.swift
//  ComeSanoWidgetsIOS
//
//  Created by Rodrigo Castro Camacho on 02/03/26.
//

import WidgetKit
import SwiftUI

@main
struct ComeSanoWidgetsIOSBundle: WidgetBundle {
    var body: some Widget {
        ClassicBalanceWidget()
        DailyBalanceWidget()
        MacrosWidget()
        QuickLogWidget()
        SmartDashboardWidget()
    }
}
