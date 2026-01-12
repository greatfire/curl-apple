# curl-apple

Pre-compiled libcurl framework for iOS and macOS applications! Automatically updated within 24-hours of a new release of curl.

Let me know if you need tvOS and/or watchOS too.
This project is prepared to provide these, but there's no point to waste space and time if nobody needs it.

If you want something more convenient to use curl in your projects, you might want to have a look at
https://github.com/greatfire/SwiftyCurl.


## Using the pre-compiled framework

1. Download and extract curl.xcframework.zip from the latest release
1. Compare the SHA-256 checksum of the downloaded framework with the fingerprint in the release
    ```bash
    shasum -a 256 curl.xcframework.zip
    ```
1. Select your target in Xcode and click the "+" under Frameworks, Libraries, and Embedded Content  
    ![Screenshot of the Frameworks, Libraries, and Embedded Content section in Xcode with the plus button circled](resources/frameworks.png)
1. Click "Add Other" then "Add Files..."  
    ![Screenshot of a dropdown menu with the add files option highlighted](resources/addfiles.png)
1. Select the extracted curl.xcframework directory

## Compile it yourself

Use the included build script to compile a specific version or customize the configuration options

```
./build-apple.sh <curl version> [optional configure parameters]
```

The following config parameters are always provided: `--disable-shared`, `--enable-static`, `--with-secure-transport`, 
`--with-openssl`, `--without-libpsl`, `--without-libidn2`, `--without-nghttp2`

## TLS support

The newer versions contain OpenSSL (which makes the xcframework significantly bigger, unfortunately), 
because support for Apple's discontinued "SecureTransport" framework is going away.

See https://daniel.haxx.se/blog/2025/01/14/secure-transport-support-in-curl-is-on-its-way-out/

Upside: TLS 1.3 support
Downside: No integrated support for certificates in the OS/user keychain.

## Authors

This project was originally devised by Ian Spence:
https://github.com/tls-inspector/curl-ios/

MacOS extensions and minor improvements by Benjamin Erhart.
