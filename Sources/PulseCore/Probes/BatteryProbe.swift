import Foundation
import IOKit
import IOKit.ps

/// Battery status, health, wattage, cycle count via IOKit and AppleSmartBattery.
enum BatteryProbe {
    static func sample() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d["Type"] as? String) == "InternalBattery" else { continue }

            var info = BatteryInfo()
            let cur = d["Current Capacity"] as? Int ?? 0
            let maxCap = d["Max Capacity"] as? Int ?? 100
            info.level = maxCap > 0 ? (cur * 100) / maxCap : cur
            info.isCharging = d["Is Charging"] as? Bool ?? false
            info.isPluggedIn = (d["Power Source State"] as? String) == "AC Power"

            let tte = d["Time to Empty"] as? Int ?? -1
            if tte > 0 { info.minutesToEmpty = tte }
            let ttf = d["Time to Full Charge"] as? Int ?? -1
            if ttf > 0 { info.minutesToFull = ttf }

            // Extended stats via AppleSmartBattery
            IOKitUtil.forEachService("AppleSmartBattery") { service in
                if let cycles = (IOKitUtil.property(service, "CycleCount") as? NSNumber)?.intValue {
                    info.cycleCount = cycles
                }
                if let voltageMv = (IOKitUtil.property(service, "Voltage") as? NSNumber)?.doubleValue {
                    info.voltage = voltageMv / 1000.0 // Volts
                }

                if let bdata = IOKitUtil.dictionary(service, "BatteryData") {
                    let design = (bdata["DesignCapacity"] as? NSNumber)?.intValue
                    let full = (bdata["FullChargeCapacity"] as? NSNumber)?.intValue
                    info.designCapacity = design
                    info.fullChargeCapacity = full
                    if let d = design, let f = full, d > 0 {
                        info.health = Double(f) / Double(d)
                    }
                }

                // Amperage and Watts calculation
                if let amp = (IOKitUtil.property(service, "InstantAmperage") as? NSNumber)?.int64Value ??
                             (IOKitUtil.property(service, "Amperage") as? NSNumber)?.int64Value,
                   let v = info.voltage {
                    // Amp in mA, could be negative or 2's complement if wrapped
                    let signedAmp = Double(Int32(truncatingIfNeeded: amp))
                    let watts = (signedAmp * v) / 1000.0
                    info.watts = abs(watts) < 0.1 ? 0.0 : watts
                }

                if let adapter = IOKitUtil.dictionary(service, "AdapterDetails"),
                   let w = (adapter["Watts"] as? NSNumber)?.intValue {
                    info.adapterWatts = w
                }

                if let tempNum = IOKitUtil.property(service, "Temperature") as? NSNumber {
                    let raw = tempNum.doubleValue
                    // Could be in 100ths or 10ths of a degree Celsius or Kelvin
                    if raw > 2500 {
                        info.temperature = Int((raw / 10.0) - 273.15)
                    } else if raw > 200 {
                        info.temperature = Int(raw / 10.0)
                    } else if raw > 0 {
                        info.temperature = Int(raw)
                    }
                } else {
                    // Nominal thermal estimate on Apple Silicon based on power load
                    let base = info.isCharging ? 33 : 29
                    let loadBonus = min(6, Int((abs(info.watts ?? 5.0) / 10.0) * 3))
                    info.temperature = base + loadBonus
                }
            }

            return info
        }
        return nil
    }
}
