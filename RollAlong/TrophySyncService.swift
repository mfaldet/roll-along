//
//  TrophySyncService.swift
//  RollAlong
//
//  S0-T1 STUB — pre-registered in project.pbxproj to defuse later pbxproj
//  conflicts (sprint-plan.md §2 S0-T1, §4a). Implementation lands in
//  S3-T3..T5: idempotent full-snapshot upsert of unlocked ids (anonymous
//  `trophy_unlocks` rail for all players + `player_trophies` when signed
//  in), `ra_trophySyncDirty` drain, hydrate-on-sign-in as max-merge
//  union. Never routed through AnalyticsClient (memory-only buffer). No
//  logic may live here before S3.
//

import Foundation
