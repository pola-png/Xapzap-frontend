class Environment {
  // These can be overridden at build time using
  // --dart-define=APPWRITE_PROJECT_ID=... and --dart-define=APPWRITE_ENDPOINT=...
  static const String appwriteProjectId =
      String.fromEnvironment('APPWRITE_PROJECT_ID', defaultValue: '690641ad0029b51eefe0');

  static const String appwriteProjectName = 'XapZap';

  static const String appwritePublicEndpoint =
      String.fromEnvironment('APPWRITE_ENDPOINT', defaultValue: 'https://nyc.cloud.appwrite.io/v1');
}

