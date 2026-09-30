/// Debug builds contain the synthetic test camera (ADR-0013); Profile and Release builds never do.
///
/// The marker string exists only inside the `#if` block, so CI can prove release artifacts do NOT
/// contain it: the debug build must contain the marker and the release build must not.
public enum SyntheticCameraBuild {
    #if DOROCAM_SYNTHETIC_CAMERA
    public static let isCompiledIn = true

    /// Unique, greppable text. Never reuse it anywhere outside this block.
    public static let marker = "dorocam.synthetic-camera.v1"
    #else
    public static let isCompiledIn = false
    #endif
}
