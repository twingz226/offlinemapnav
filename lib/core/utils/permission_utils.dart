import 'package:permission_handler/permission_handler.dart';

class PermissionUtils {
  static Future<bool> requestLocationPermission() async {
    var status = await Permission.location.request();
    return status.isGranted;
  }
}
