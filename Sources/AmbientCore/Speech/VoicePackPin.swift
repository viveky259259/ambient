/// The published offline voice helper. `scripts/pin-voice-helper.sh` rewrites this file after uploading a helper to
/// the `voice-<version>` release; until then the offline voice reports that it isn't available in this build.
public enum VoicePackPin {
    public static let version = "1"
    public static let helperSHA256 = ""
    public static let helperBytes: Int64 = 0
}
