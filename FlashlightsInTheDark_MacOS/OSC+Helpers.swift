import OSCKit

extension Array where Element == any OSCValue {
    func int32(at index: Int)   -> Int32?     { self[index] as? Int32      }
    func float32(at index: Int) -> Float32?   { self[index] as? Float32    }
    func float64(at index: Int) -> Float64?   { self[index] as? Float64    }
    func string(at index: Int)  -> String?    { self[index] as? String     }
    func timetag(at index: Int) -> OSCTimeTag?{ self[index] as? OSCTimeTag }
}
