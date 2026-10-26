// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum ForkWindowSwitcherTests {
    static func run(_ suite: TestSuite) {
        let screen = WindowEdgeSnapScreen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 835)
        )
        func top(_ y: CGFloat, layout: WindowEdgeSnapLayout = .standard) -> WindowEdgeSnapTarget? {
            WindowEdgeSnapSupport.target(at: CGPoint(x: 720, y: y), screens: [screen], layout: layout)
        }
        suite.expect(top(875)?.action == .topHalf && top(887)?.action == .topHalf
                && top(887.5)?.action == .maximize && top(900)?.action == .maximize,
                     "default top contact offers the upper half before pushing farther maximizes")
        let upperHalf = WindowLayoutGeometry.rect(for: .topHalf,
                                                  current: screen.visibleFrame,
                                                  visibleFrame: screen.visibleFrame,
                                                  windowGap: WindowLayoutGaps.windowGap,
                                                  screenGap: WindowLayoutGaps.screenGap,
                                                  marginPercent: WindowLayoutMargin.percent)
        suite.expect(top(875)?.frame == upperHalf.integral,
                     "the upper-half preview uses current gap and margin settings")
        suite.expect(WindowEdgeSnapSupport.topCenterAction(pointY: 899, visibleTop: 900, physicalTop: 900) == .topHalf
                && WindowEdgeSnapSupport.topCenterAction(pointY: 900, visibleTop: 900, physicalTop: 900) == .maximize,
                     "an auto-hidden menu bar promotes only at the physical top edge")
        suite.expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 0, y: 900), screens: [screen])?.action == .topLeft
                && WindowEdgeSnapSupport.target(at: CGPoint(x: 1440, y: 900), screens: [screen])?.action == .topRight,
                     "pushing through the menu bar leaves corner placements intact")
        suite.expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 720, y: 875), screens: [screen],
                                                  enabledZones: WindowEdgeSnapZone.allEnabled.subtracting([.top])) == nil,
                     "disabling the top zone disables both upper-half and maximize targets")
        let customized = WindowEdgeSnapLayout(storageValue: "top=topHalf")
        suite.expect(top(875, layout: customized)?.action == .topHalf
                && top(900, layout: customized)?.action == .topHalf,
                     "a customized top-half placement keeps the user's chosen action at every height")
        let split = WindowEdgeSnapLayout(storageValue: "top=leftThird+maximize+rightThird")
        suite.expect(top(875, layout: split)?.action == .maximize,
                     "a customized split top edge keeps its maximize area instead of the default split")

        func direction(_ hovered: Int, first: Int, visible: Int = 4, count: Int = 8) -> Int? {
            SwitcherSupport.iconRowEdgeHoverDirection(hoveredIndex: hovered,
                                                       firstVisibleIndex: first,
                                                       visibleCount: visible,
                                                       itemCount: count)
        }
        func delta(_ hovered: Int, first: Int) -> Int? {
            SwitcherSupport.iconRowEdgeHoverDelta(hoveredIndex: hovered,
                                                  firstVisibleIndex: first,
                                                  visibleCount: 4,
                                                  itemCount: 8)
        }
        suite.expect(direction(0, first: 0) == -1 && delta(0, first: 0) == nil
                && direction(7, first: 4) == 1 && delta(7, first: 4) == nil,
                     "terminal overflow edges retain a bounce direction without stepping past the row")
        suite.expect(direction(3, first: 0) == 1 && delta(3, first: 0) == 1
                && direction(4, first: 4) == -1 && delta(4, first: 4) == -1,
                     "overflow edges with hidden icons keep scrolling in either direction")
        suite.expect(direction(2, first: 0) == nil
                && direction(0, first: 0, visible: 8) == nil
                && direction(0, first: 0, count: 0) == nil,
                     "middle icons, rows that fit and empty rows do not bounce")
    }
}
