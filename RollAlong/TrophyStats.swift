//
//  TrophyStats.swift
//  RollAlong
//
//  S0-T1 STUB — pre-registered in project.pbxproj to defuse later pbxproj
//  conflicts (sprint-plan.md §2 S0-T1, §4a). Implementation lands in
//  S0-T2: the latched `ra_trophy*` counter store bumped from GameState
//  funnels (source-tagged play-earned coins, daily-reward claims, no-fall
//  clear streak, CotD consecutive-date helper). Counters are monotonic
//  ratchets — untouched by resetProgress()/liquidateCoinCosmetics().
//  Never a coins-spent or falls/failure counter. No logic may live here
//  before S0-T2.
//

import Foundation
