/// The Meta (Facebook) app ResPAWnd uses to connect an organization's
/// Facebook Page. The same App ID is set for Android in
/// android/app/src/main/res/values/strings.xml, for iOS in
/// ios/Runner/Info.plist, and for the backend in the FB_APP_ID secret
/// (functions/facebook.js). The App ID is public; the app secret is only in
/// Secret Manager.
class FacebookConfig {
  const FacebookConfig._();

  static const String appId = '1764224901694464';

  /// Facebook JavaScript SDK version for the web build.
  static const String webSdkVersion = 'v21.0';

  /// What connecting a Page asks for: list the Pages the account manages and
  /// post to the chosen one.
  static const List<String> pagePermissions = ['pages_show_list', 'pages_read_engagement', 'pages_manage_posts'];
}
