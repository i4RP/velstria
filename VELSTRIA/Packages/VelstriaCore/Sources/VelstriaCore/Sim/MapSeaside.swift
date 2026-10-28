import Foundation

extension MapDefinition {
    /// Seaside shares the established three-lane gameplay layout. The beach scenery
    /// replaces terrain visuals without changing hero, minion, objective or path rules.
    public static let seaside: MapDefinition = {
        var map = canyon
        map.stageID = "seaside"
        return map
    }()
}
