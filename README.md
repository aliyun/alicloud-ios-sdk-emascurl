# EMASNet Project

## Clone from Git

1. Clone the repository:
    ```bash
    git clone http://gitlab.alibaba-inc.com/alicloud-ams/alicloud-ios-sdk-emasnet.git
    ```
   
2. Change to the project directory:
    ```bash
    cd alicloud-ios-sdk-emasnet
    ```

3. Install dependencies:
    ```bash
    pod install
    ```

## Build and Run EMASNetDemo

1. Open EMASNet.xcworkspace

2. Choose the scheme `EMASNet`

3. Click the run button

## Script to Build EMASNet.xcframework

If you want to build an EMASNet.xcframework, run the script below:

   ```bash
   ./create_xcframework.sh
   ```

   an EMASNet.xcframework will be created in the `build` folder.

## (Optional) Link with your desired libcurl xcframework

Depending on your requirements, choose an appropriate `libcurl xcframework` to link. Default we link a libcurl-HTTP2.xcframework in this reposity. These frameworks can be built from the [alicloud-ios-sdk-curl](http://gitlab.alibaba-inc.com/alicloud-ams/alicloud-ios-sdk-curl.git) repository.

**Important:** Ensure that you link the `libcurl xcframework` with the `EMASNetDemo` target, not the `EMASNet` target.

### Steps to Link the libcurl xcframework

1. **Open the project:**
   - Select `PROJECT` > `EMASNet`.

2. **Choose the appropriate target:**
   - Select `TARGETS` > `EMASNetDemo`.

3. **Go to the build settings:**
   - Select the `Build Phases` tab.

4. **Add the library:**
   - Under `Link Binary With Libraries`, click the `+` button.
   - Add the desired `libcurl xcframework`, for example, `libcurl-HTTP2.xcframework`.

Once linked, you are ready to run the project with certain libcurl version.