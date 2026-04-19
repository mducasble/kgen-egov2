import Foundation
import AVFoundation
import CoreGraphics
import simd

/// Fits Apple's `AVCameraCalibrationData` radial lookup table to OpenCV /
/// ROS plumb_bob radial distortion coefficients (`k1, k2, k3`), with
/// tangential components assumed zero (`p1 = p2 = 0`).
///
/// ## Math
///
/// Apple's `lensDistortionLookupTable` stores N `Float32` magnifications
/// sampled uniformly along radial distance from `lensDistortionCenter`, from
/// `0` to `r_max` (distance to the farthest corner of the reference image).
/// For a *distorted* pixel at radial distance `r_d`, the magnification `m(r_d)`
/// rectifies to undistorted radial distance:
///
///     r_u = r_d * (1 + m(r_d))
///
/// The *inverse* lookup table, by contrast, stores `m'(r_u)` such that
///
///     r_d = r_u * (1 + m'(r_u))
///
/// which matches the plumb_bob forward model (undistorted → distorted) used by
/// OpenCV. Fitting `k1, k2, k3` therefore boils down to:
///
///     y  = k1 * x² + k2 * x⁴ + k3 * x⁶
///
/// where `x = r_u_norm` (undistorted radius in normalized camera coordinates,
/// i.e. pixels divided by focal length) and `y = (r_d_norm / r_u_norm) − 1`.
/// The system is linear in `[k1, k2, k3]` and is solved by normal equations.
enum PlumbBobFitter {

    struct FitInput {
        let inverseLookupTable: Data
        let intrinsicMatrix: matrix_float3x3
        let intrinsicReferenceDimensions: CGSize
        let lensDistortionCenter: CGPoint
    }

    struct FitResult {
        /// [k1, k2, p1=0, p2=0, k3]
        let coefficients: [Double]
        let k1: Double
        let k2: Double
        let k3: Double
        let residualRmsNormalized: Double
        /// RMS expressed in *probe-reference* pixels (same reference as the
        /// intrinsic matrix). Caller can scale to recording resolution.
        let residualRmsPx: Double
        let samples: Int
    }

    enum FitError: Error {
        case emptyLookupTable
        case singularSystem
        case unsupportedSize
    }

    /// Fits `k1, k2, k3`. Returns a `FitResult` whose `coefficients` can be
    /// written directly as `D` in a plumb_bob-style camera calibration.
    static func fit(_ input: FitInput) throws -> FitResult {
        let width = Double(input.intrinsicReferenceDimensions.width)
        let height = Double(input.intrinsicReferenceDimensions.height)
        guard width > 0, height > 0 else { throw FitError.unsupportedSize }

        let fx = Double(input.intrinsicMatrix.columns.0.x)
        let fy = Double(input.intrinsicMatrix.columns.1.y)
        guard fx > 0, fy > 0 else { throw FitError.unsupportedSize }

        // Apple's worked example uses the mean of (fx, fy) when projecting radial
        // samples; since distortion is radial, using a scalar focal length here
        // keeps the 1D fit consistent with how the table was built.
        let fScalar = 0.5 * (fx + fy)

        // r_max matches Apple's reference implementation: farthest corner from
        // the distortion center in pixel space at the reference dimensions.
        let cx = Double(input.lensDistortionCenter.x)
        let cy = Double(input.lensDistortionCenter.y)
        let dxMax = max(cx, width - cx)
        let dyMax = max(cy, height - cy)
        let rMax = sqrt(dxMax * dxMax + dyMax * dyMax)
        guard rMax > 0 else { throw FitError.unsupportedSize }

        // Decode the inverse lookup table (undistorted → magnification to distorted).
        let floats = input.inverseLookupTable.withUnsafeBytes { rawBuffer -> [Float] in
            guard let base = rawBuffer.baseAddress else { return [] }
            let count = rawBuffer.count / MemoryLayout<Float>.size
            let typed = base.assumingMemoryBound(to: Float.self)
            return Array(UnsafeBufferPointer(start: typed, count: count))
        }
        guard floats.count >= 2 else { throw FitError.emptyLookupTable }

        // Build N samples along an idealised +x radial line from the center.
        // Skip index 0 (r=0 → trivial, no contribution) and the last index (avoid
        // clipping at r_max which Apple clamps).
        let sampleCount = min(floats.count, 256)
        var xs: [Double] = []      // r_u_norm (undistorted, normalized)
        var ys: [Double] = []      // target: (r_d_norm / r_u_norm) − 1
        xs.reserveCapacity(sampleCount)
        ys.reserveCapacity(sampleCount)

        for i in 1..<sampleCount {
            // Uniformly sample normalized *undistorted* radius in [0, 1] along r_u.
            // The inverse lookup is indexed by undistorted radius, so this is the
            // natural parameterisation. We map i → r_u_px ∈ (0, rMax].
            let rUPx = rMax * Double(i) / Double(sampleCount)
            let magIndex = (rUPx / rMax) * Double(floats.count - 1)
            let lo = Int(magIndex)
            let frac = magIndex - Double(lo)
            let m0 = Double(floats[lo])
            let m1 = Double(floats[min(lo + 1, floats.count - 1)])
            let mag = (1.0 - frac) * m0 + frac * m1

            let rDPx = rUPx * (1.0 + mag)
            let rUNorm = rUPx / fScalar
            let rDNorm = rDPx / fScalar

            guard rUNorm > 1e-9 else { continue }
            let y = (rDNorm / rUNorm) - 1.0
            xs.append(rUNorm)
            ys.append(y)
        }
        guard !xs.isEmpty else { throw FitError.emptyLookupTable }

        // Normal-equation solve of a 3×3 symmetric positive-definite system:
        //   [ Σx²·x²  Σx²·x⁴  Σx²·x⁶ ] [k1]   [ Σx²·y ]
        //   [ Σx⁴·x²  Σx⁴·x⁴  Σx⁴·x⁶ ] [k2] = [ Σx⁴·y ]
        //   [ Σx⁶·x²  Σx⁶·x⁴  Σx⁶·x⁶ ] [k3]   [ Σx⁶·y ]
        var sX2X2 = 0.0, sX2X4 = 0.0, sX2X6 = 0.0
        var sX4X4 = 0.0, sX4X6 = 0.0
        var sX6X6 = 0.0
        var sX2Y = 0.0, sX4Y = 0.0, sX6Y = 0.0

        for (x, y) in zip(xs, ys) {
            let x2 = x * x
            let x4 = x2 * x2
            let x6 = x4 * x2
            let x8 = x4 * x4
            let x10 = x6 * x4
            let x12 = x6 * x6
            sX2X2 += x4
            sX2X4 += x6
            sX2X6 += x8
            sX4X4 += x8
            sX4X6 += x10
            sX6X6 += x12
            sX2Y += x2 * y
            sX4Y += x4 * y
            sX6Y += x6 * y
        }

        // Build 3×3 and RHS as doubles. Solve by explicit inverse (tiny, stable
        // enough for this well-conditioned Vandermonde-like setup).
        let a = simd_double3x3(rows: [
            simd_double3(sX2X2, sX2X4, sX2X6),
            simd_double3(sX2X4, sX4X4, sX4X6),
            simd_double3(sX2X6, sX4X6, sX6X6)
        ])
        let det = a.determinant
        guard abs(det) > 1e-30 else { throw FitError.singularSystem }
        let b = simd_double3(sX2Y, sX4Y, sX6Y)
        let k = a.inverse * b
        let k1 = k.x
        let k2 = k.y
        let k3 = k.z

        // Residual: re-evaluate the model and compare against the table.
        var sumSq = 0.0
        for (x, y) in zip(xs, ys) {
            let x2 = x * x
            let modelY = k1 * x2 + k2 * x2 * x2 + k3 * x2 * x2 * x2
            let diff = modelY - y
            sumSq += diff * diff
        }
        let rmsNormalized = sqrt(sumSq / Double(xs.count))
        // Convert the normalized residual back to probe-reference pixels along r.
        // For a sample with r_u_norm = x, the forward-model distorted radius is
        // r_d_norm = x * (1 + modelY). The residual Δ(r_d_norm) ≈ x * Δy. We
        // report the mean x weighted RMS as a pixel-space proxy.
        let meanX = xs.reduce(0.0, +) / Double(xs.count)
        let rmsPx = rmsNormalized * meanX * fScalar

        return FitResult(
            coefficients: [k1, k2, 0.0, 0.0, k3],
            k1: k1,
            k2: k2,
            k3: k3,
            residualRmsNormalized: rmsNormalized,
            residualRmsPx: rmsPx,
            samples: xs.count
        )
    }
}
