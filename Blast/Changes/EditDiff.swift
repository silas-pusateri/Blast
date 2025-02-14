import Foundation

struct EditDiff: Codable {
    var filters: [String: Any]
    var adjustments: [String: Any]
    var transform: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case filters
        case adjustments
        case transform
    }
    
    init(filters: [String: Any], adjustments: [String: Any], transform: [String: Any]) {
        self.filters = filters
        self.adjustments = adjustments
        self.transform = transform
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let filtersData = try container.decode(Data.self, forKey: .filters)
        let adjustmentsData = try container.decode(Data.self, forKey: .adjustments)
        let transformData = try container.decode(Data.self, forKey: .transform)
        
        filters = try JSONSerialization.jsonObject(with: filtersData) as? [String: Any] ?? [:]
        adjustments = try JSONSerialization.jsonObject(with: adjustmentsData) as? [String: Any] ?? [:]
        transform = try JSONSerialization.jsonObject(with: transformData) as? [String: Any] ?? [:]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        let filtersData = try JSONSerialization.data(withJSONObject: filters)
        let adjustmentsData = try JSONSerialization.data(withJSONObject: adjustments)
        let transformData = try JSONSerialization.data(withJSONObject: transform)
        
        try container.encode(filtersData, forKey: .filters)
        try container.encode(adjustmentsData, forKey: .adjustments)
        try container.encode(transformData, forKey: .transform)
    }
    
    static func from(metadata: [String: Any]) throws -> EditDiff {
        let filters = metadata["filters"] as? [String: Any] ?? [:]
        let adjustments = metadata["adjustments"] as? [String: Any] ?? [:]
        let transform = metadata["transform"] as? [String: Any] ?? [:]
        
        return EditDiff(filters: filters, adjustments: adjustments, transform: transform)
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "filters": filters,
            "adjustments": adjustments,
            "transform": transform
        ]
    }
} 