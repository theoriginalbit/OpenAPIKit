//
//  SchemaObjectContext.swift
//  
//
//  Created by Mathew Polzin on 6/22/19.
//

import Foundation
import AnyCodable
import Poly

// MARK: - Generic Context

public protocol JSONSchemaObjectContext {
    var required: Bool { get }
    var nullable: Bool { get }
}

extension JSONSchemaObject {
    public struct Context<Format: OpenAPIFormat>: JSONSchemaObjectContext, Equatable {
        public let format: Format
        public let required: Bool
        public let nullable: Bool

        // NOTE: "const" is supported by the newest JSON Schema spec but not
        // yet by OpenAPI. Instead, will use "enum" with one possible value for now.
//        public let constantValue: Format.SwiftType?

        /// The OpenAPI spec calls this "enum"
        ///
        /// If not specified, it is assumed that any
        /// value of the given format is allowed.
        /// NOTE: I would like the array of allowed
        /// values to have the type `Format.SwiftType`
        /// but this is not tractable because I also
        /// want to be able to automatically turn any
        /// Swift type that will get _encoded as
        /// something compatible with_ `Format.SwiftType`
        /// into an allowed value.
        public let allowedValues: [AnyCodable]?

        // I wanted example to be AnyCodable, but alas that causes
        // runtime problems when encoding in a very strange way.
        // For now, a String (which is OK by the OpenAPI spec) will
        // have to do.
        public let example: String?

        public init(format: Format,
                    required: Bool,
                    nullable: Bool = false,
//                    constantValue: Format.SwiftType? = nil,
            allowedValues: [AnyCodable]? = nil,
            example: (codable: AnyCodable, encoder: JSONEncoder)? = nil) {
            self.format = format
            self.required = required
            self.nullable = nullable
//            self.constantValue = constantValue
            self.allowedValues = allowedValues
            self.example = example
                .flatMap { try? $0.encoder.encode($0.codable)}
                .flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}

// MARK: - Transformations

extension JSONSchemaObject.Context {
    /// Return the optional version of this Context
    public func optionalContext() -> Self {
        return .init(format: format,
                     required: false,
                     nullable: nullable,
//                         constantValue: constantValue,
            allowedValues: allowedValues)
    }

    /// Return the required version of this context
    public func requiredContext() -> Self {
        return .init(format: format,
                     required: true,
                     nullable: nullable,
//                         constantValue: constantValue,
            allowedValues: allowedValues)
    }

    /// Return the nullable version of this context
    public func nullableContext() -> Self {
        return .init(format: format,
                     required: required,
                     nullable: true,
//                         constantValue: constantValue,
            allowedValues: allowedValues)
    }

    /// Return this context with the given list of possible values
    public func with(allowedValues: [AnyCodable]) -> Self {
        return .init(format: format,
                     required: required,
                     nullable: nullable,
//                         constantValue: constantValue,
            allowedValues: allowedValues)
    }

    /// Return this context with the given example
    public func with(example: AnyCodable, using encoder: JSONEncoder) -> Self {
        return .init(format: format,
                     required: required,
                     nullable: nullable,
//                         constantValue: constantValue,
            allowedValues: allowedValues,
            example: (codable: example, encoder: encoder))
    }
}

// MARK: - Specific Contexts

extension JSONSchemaObject {
    public struct NumericContext: Equatable {
        /// A numeric instance is valid only if division by this keyword's value results in an integer. Defaults to nil.
        public let multipleOf: Double?
        public let maximum: Double?
        public let exclusiveMaximum: Double?
        public let minimum: Double?
        public let exclusiveMinimum: Double?

        public init(multipleOf: Double? = nil,
                    maximum: Double? = nil,
                    exclusiveMaximum: Double? = nil,
                    minimum: Double? = nil,
                    exclusiveMinimum: Double? = nil) {
            self.multipleOf = multipleOf
            self.maximum = maximum
            self.exclusiveMaximum = exclusiveMaximum
            self.minimum = minimum
            self.exclusiveMinimum = exclusiveMinimum
        }
    }

    public struct StringContext: Equatable {
        public let maxLength: Int?
        public let minLength: Int

        /// Regular expression
        public let pattern: String?

        public init(maxLength: Int? = nil,
                    minLength: Int = 0,
                    pattern: String? = nil) {
            self.maxLength = maxLength
            self.minLength = minLength
            self.pattern = pattern
        }
    }

    public struct ArrayContext: Equatable {
        /// A JSON Type Node that describes
        /// the type of each element in the array.
        public let items: JSONSchemaObject?

        /// Maximum number of items in array.
        public let maxItems: Int?

        /// Minimum number of items in array.
        /// Defaults to 0.
        public let minItems: Int

        /// Setting to true indicates all
        /// elements of the array are expected
        /// to be unique. Defaults to false.
        public let uniqueItems: Bool

        public init(items: JSONSchemaObject? = nil,
                    maxItems: Int? = nil,
                    minItems: Int = 0,
                    uniqueItems: Bool = false) {
            self.items = items
            self.maxItems = maxItems
            self.minItems = minItems
            self.uniqueItems = uniqueItems
        }
    }

    public struct ObjectContext: Equatable {
        public let maxProperties: Int?
        let _minProperties: Int
        public let properties: [String: JSONSchemaObject]
        public let additionalProperties: Either<Bool, JSONSchemaObject>?

        // NOTE that an object's required properties
        // array is determined by looking at its properties'
        // required Bool.
        public var requiredProperties: [String] {
            return Array(properties.filter { (_, schemaObject) in
                schemaObject.required
            }.keys)
        }

        public var minProperties: Int {
            return max(_minProperties, requiredProperties.count)
        }

        public init(properties: [String: JSONSchemaObject],
                    additionalProperties: Either<Bool, JSONSchemaObject>? = nil,
                    maxProperties: Int? = nil,
                    minProperties: Int = 0) {
            self.properties = properties
            self.additionalProperties = additionalProperties
            self.maxProperties = maxProperties
            self._minProperties = minProperties
        }
    }
}

// MARK: - Codable

extension JSONSchemaObject.Context {
    private enum CodingKeys: String, CodingKey {
        case type
        case format
        case allowedValues = "enum"
        case nullable
        case example
//        case constantValue = "const"
    }
}

extension JSONSchemaObject.Context: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(format.jsonType, forKey: .type)

        if format != Format.unspecified {
            try container.encode(format, forKey: .format)
        }

        if allowedValues != nil {
            try container.encode(allowedValues, forKey: .allowedValues)
        }

//        if constantValue != nil {
//            try container.encode(constantValue, forKey: .constantValue)
//        }

        // nullable is false if omitted
        if nullable {
            try container.encode(nullable, forKey: .nullable)
        }

        if example != nil {
            try container.encode(example, forKey: .example)
        }
    }
}

extension JSONSchemaObject.Context: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        format = try container.decode(Format.self, forKey: .format)

        // default to false at decoding site. It is the responsibility of
        // decoders farther upstream to mark this as required if needed
        // using `.requiredContext()`.
        required = false

        allowedValues = try container.decodeIfPresent([AnyCodable].self, forKey: .allowedValues)

//        constantValue = container.decodeIfPresent(Format.SwiftType, forKey: .constantValue)

        nullable = try container.decodeIfPresent(Bool.self, forKey: .nullable) ?? false

        example = try container.decodeIfPresent(String.self, forKey: .example)
    }
}

extension JSONSchemaObject.NumericContext {
    private enum CodingKeys: String, CodingKey {
        case multipleOf
        case maximum
        case exclusiveMaximum
        case minimum
        case exclusiveMinimum
    }
}

extension JSONSchemaObject.NumericContext: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if multipleOf != nil {
            try container.encode(multipleOf, forKey: .multipleOf)
        }

        if maximum != nil {
            try container.encode(maximum, forKey: .maximum)
        }

        if exclusiveMaximum != nil {
            try container.encode(exclusiveMaximum, forKey: .exclusiveMaximum)
        }

        if minimum != nil {
            try container.encode(minimum, forKey: .minimum)
        }

        if exclusiveMinimum != nil {
            try container.encode(exclusiveMinimum, forKey: .exclusiveMinimum)
        }
    }
}

extension JSONSchemaObject.NumericContext: Decodable {
    // default implementation works
}

extension JSONSchemaObject.StringContext {
    private enum CodingKeys: String, CodingKey {
        case maxLength
        case minLength
        case pattern
    }
}

extension JSONSchemaObject.StringContext: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if maxLength != nil {
            try container.encode(maxLength, forKey: .maxLength)
        }

        if minLength > 0 {
            try container.encode(minLength, forKey: .minLength)
        }

        if pattern != nil {
            try container.encode(pattern, forKey: .pattern)
        }
    }
}

extension JSONSchemaObject.StringContext: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
        minLength = try container.decodeIfPresent(Int.self, forKey: .minLength) ?? 0
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
    }
}

extension JSONSchemaObject.ArrayContext {
    private enum CodingKeys: String, CodingKey {
        case items
        case maxItems
        case minItems
        case uniqueItems
    }
}

extension JSONSchemaObject.ArrayContext: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if items != nil {
            try container.encode(items, forKey: .items)
        }

        if maxItems != nil {
            try container.encode(maxItems, forKey: .maxItems)
        }

        if minItems > 0 {
            // omission is the same as 0
            try container.encode(minItems, forKey: .minItems)
        }

        if uniqueItems {
            // omission is the same as false
            try container.encode(uniqueItems, forKey: .uniqueItems)
        }
    }
}

extension JSONSchemaObject.ArrayContext: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        items = try container.decodeIfPresent(JSONSchemaObject.self, forKey: .items)
        maxItems = try container.decodeIfPresent(Int.self, forKey: .maxItems)
        minItems = try container.decodeIfPresent(Int.self, forKey: .minItems) ?? 0
        uniqueItems = try container.decodeIfPresent(Bool.self, forKey: .uniqueItems) ?? false
    }
}

extension JSONSchemaObject.ObjectContext {
    private enum CodingKeys: String, CodingKey {
        case maxProperties
        case minProperties
        case properties
        case additionalProperties
        case required
    }
}

extension JSONSchemaObject.ObjectContext: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if maxProperties != nil {
            try container.encode(maxProperties, forKey: .maxProperties)
        }

        try container.encode(properties, forKey: .properties)

        if additionalProperties != nil {
            try container.encode(additionalProperties, forKey: .additionalProperties)
        }

        if !requiredProperties.isEmpty {
            try container.encode(requiredProperties, forKey: .required)
        }

        if minProperties > 0 {
            try container.encode(minProperties, forKey: .minProperties)
        }
    }
}

extension JSONSchemaObject.ObjectContext: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        maxProperties = try container.decodeIfPresent(Int.self, forKey: .maxProperties)
        _minProperties = try container.decodeIfPresent(Int.self, forKey: .minProperties) ?? 0
        additionalProperties = try container.decodeIfPresent(Either<Bool, JSONSchemaObject>.self, forKey: .additionalProperties)

        let requiredArray = try container.decodeIfPresent([String].self, forKey: .required) ?? []

        var decodedProperties = try container.decode([String: JSONSchemaObject].self, forKey: .properties)

        decodedProperties.forEach { (propertyName, property) in
            if requiredArray.contains(propertyName) {
                decodedProperties[propertyName] = property.requiredSchemaObject()
            }
        }

        properties = decodedProperties
    }
}
