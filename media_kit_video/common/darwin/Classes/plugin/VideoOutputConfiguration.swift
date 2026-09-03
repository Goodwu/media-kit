public class VideoOutputConfiguration {
  public let width: Int64?
  public let height: Int64?
  public let enableHardwareAcceleration: Bool
  public let useNativeSurface: Bool

  init(
    width: Int64?,
    height: Int64?,
    enableHardwareAcceleration: Bool,
    useNativeSurface: Bool = false
  ) {
    self.width = width
    self.height = height
    self.enableHardwareAcceleration = enableHardwareAcceleration
    self.useNativeSurface = useNativeSurface
  }

  public static func fromDict(_ dict: [String: Any])
    -> VideoOutputConfiguration
  {
    let widthStr = dict["width"] as! String
    let heightStr = dict["height"] as! String
    let enableHardwareAcceleration =
      dict["enableHardwareAcceleration"] as! Bool

    let width: Int64? = Int64(widthStr)
    let height: Int64? = Int64(heightStr)

    return VideoOutputConfiguration(
      width: width,
      height: height,
      enableHardwareAcceleration: enableHardwareAcceleration,
      useNativeSurface: dict["useNativeSurface"] as? Bool ?? false
    )
  }
}
