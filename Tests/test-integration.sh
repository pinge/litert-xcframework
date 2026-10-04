#!/usr/bin/env bash

# supports bash 3.2.57 on macos-26 runner.

set -euo pipefail

PLATFORM="${1:-simulator}"
LITERT_VERSION="${2:-2.1.6}"
PACKAGE_MANAGER="${3:-swiftpm}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"
SIMULATOR_ID="${SIMULATOR_ID:-}"
LITERT_ARTIFACT_DIR="${LITERT_ARTIFACT_DIR:-}"
# AWS Device Farm is available only in us-west-2.
DEVICE_FARM_REGION="us-west-2"
DEVICE_FARM_PROJECT_ARN="${DEVICE_FARM_PROJECT_ARN:-}"
DEVICE_FARM_DEVICE_NAME="${DEVICE_FARM_DEVICE_NAME:-Apple iPhone 17}"
DEVICE_FARM_OS_VERSION="${DEVICE_FARM_OS_VERSION:-26.3.1}"
DEVICE_FARM_TIMEOUT_SECONDS=1800

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -n "$LITERT_ARTIFACT_DIR" ]]; then
  LITERT_ARTIFACT_DIR="$(cd "$LITERT_ARTIFACT_DIR" && pwd)"
  for archive in \
    CLiteRT.xcframework.zip \
    LiteRTMetalAccelerator.xcframework.zip \
    LiteRT.xcframeworks.zip \
    LiteRT.podspec; do
    if [[ ! -f "$LITERT_ARTIFACT_DIR/$archive" ]]; then
      echo "Missing LiteRT artifact: $LITERT_ARTIFACT_DIR/$archive" >&2
      exit 1
    fi
  done
fi

if [[ "$#" -gt 3 ]]; then
  echo "Usage: $0 [simulator|device] [litert_version] [swiftpm|cocoapods]" >&2
  exit 2
fi

case "$PLATFORM" in
  simulator) ;;
  device) ;;
  *)
    echo "Invalid platform: $PLATFORM" >&2
    exit 2
    ;;
esac

case "$LITERT_VERSION" in
  2.1.6|2.2.0) ;;
  *)
    echo "LiteRT $LITERT_VERSION not supported" >&2
    exit 2
    ;;
esac

case "$PACKAGE_MANAGER" in
  swiftpm) EXAMPLE=SwiftPM ;;
  cocoapods) EXAMPLE=CocoaPods ;;
  *)
    echo "Invalid package manager: $PACKAGE_MANAGER" >&2
    exit 2
    ;;
esac

TEST_WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/litert-xcframework-integration.XXXXXX")"
mkdir -p "$TEST_WORKSPACE/Examples" "$TEST_WORKSPACE/Tests"
ditto "$REPOSITORY_ROOT/Examples/Shared" "$TEST_WORKSPACE/Examples/Shared"
ditto "$REPOSITORY_ROOT/Examples/$EXAMPLE" "$TEST_WORKSPACE/Examples/$EXAMPLE"
ditto "$REPOSITORY_ROOT/Tests/Integration" "$TEST_WORKSPACE/Tests/Integration"

EXAMPLE_DIRECTORY="$TEST_WORKSPACE/Examples/$EXAMPLE"
if [[ "$PACKAGE_MANAGER" == swiftpm ]]; then
  PROJECT_FILE="$EXAMPLE_DIRECTORY/LiteRTExample.xcodeproj/project.pbxproj"
  if [[ -n "$LITERT_ARTIFACT_DIR" ]]; then
    LOCAL_PACKAGE_DIRECTORY="$EXAMPLE_DIRECTORY/LiteRT"
    mkdir -p "$LOCAL_PACKAGE_DIRECTORY"
    ditto -x -k \
      "$LITERT_ARTIFACT_DIR/CLiteRT.xcframework.zip" \
      "$LOCAL_PACKAGE_DIRECTORY"
    ditto -x -k \
      "$LITERT_ARTIFACT_DIR/LiteRTMetalAccelerator.xcframework.zip" \
      "$LOCAL_PACKAGE_DIRECTORY"
    ditto \
      "$REPOSITORY_ROOT/Tests/Integration/LocalPackage.swift" \
      "$LOCAL_PACKAGE_DIRECTORY/Package.swift"
    perl -0pi -e \
      's{/\* Begin XCRemoteSwiftPackageReference section \*/.*?/\* End XCRemoteSwiftPackageReference section \*/}{/\* Begin XCLocalSwiftPackageReference section \*/\n\t\tA00000000000000000000001 /\* XCLocalSwiftPackageReference "LiteRT" \*/ = {\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = LiteRT;\n\t\t};\n/\* End XCLocalSwiftPackageReference section \*/}s' \
      "$PROJECT_FILE"
    sed -i '' \
      's/XCRemoteSwiftPackageReference "litert-xcframework"/XCLocalSwiftPackageReference "LiteRT"/g' \
      "$PROJECT_FILE"
    grep -q 'isa = XCLocalSwiftPackageReference;' "$PROJECT_FILE"
    if grep -q 'XCRemoteSwiftPackageReference' "$PROJECT_FILE"; then
      echo "Failed to replace the remote Swift package reference" >&2
      exit 1
    fi
  else
    VERSION_COUNT="$(grep -Ec '^[[:space:]]*version = [0-9]+\.[0-9]+\.[0-9]+;$' "$PROJECT_FILE")"
    if [[ "$VERSION_COUNT" -ne 1 ]]; then
      echo "Expected one exact Swift package version in $PROJECT_FILE" >&2
      exit 1
    fi

    sed -i '' -E \
      "s/^([[:space:]]*version = )[0-9]+\.[0-9]+\.[0-9]+;$/\1${LITERT_VERSION};/" \
      "$PROJECT_FILE"
  fi
  XCODE_CONTAINER_FLAG=-project
  XCODE_CONTAINER="$EXAMPLE_DIRECTORY/LiteRTExample.xcodeproj"
else
  if [[ -n "$LITERT_ARTIFACT_DIR" ]]; then
    LOCAL_POD_DIRECTORY="$EXAMPLE_DIRECTORY/LiteRT"
    mkdir -p "$LOCAL_POD_DIRECTORY"
    ditto -x -k \
      "$LITERT_ARTIFACT_DIR/LiteRT.xcframeworks.zip" \
      "$LOCAL_POD_DIRECTORY"
    ditto "$LITERT_ARTIFACT_DIR/LiteRT.podspec" "$LOCAL_POD_DIRECTORY/LiteRT.podspec"
    ditto "$REPOSITORY_ROOT/LICENSE" "$LOCAL_POD_DIRECTORY/LICENSE"
    (
      cd "$EXAMPLE_DIRECTORY"
      LITERT_PATH="$LOCAL_POD_DIRECTORY" pod install
    )
  else
    (
      cd "$EXAMPLE_DIRECTORY"
      LITERT_VERSION="$LITERT_VERSION" pod install
    )
  fi
  XCODE_CONTAINER_FLAG=-workspace
  XCODE_CONTAINER="$EXAMPLE_DIRECTORY/LiteRTExample.xcworkspace"
fi

echo "Test workspace: $TEST_WORKSPACE"

if [[ "$PLATFORM" == device ]]; then
  for command in aws curl; do
    if ! command -v "$command" >/dev/null; then
      echo "Required command not found: $command" >&2
      exit 1
    fi
  done

  if [[ -z "$DEVICE_FARM_PROJECT_ARN" ]]; then
    echo "DEVICE_FARM_PROJECT_ARN is required for device tests" >&2
    exit 1
  fi

  mask_value() {
    if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
      printf '::add-mask::%s\n' "$1"
    fi
  }

  mask_value "$DEVICE_FARM_PROJECT_ARN"

  DEVICE_FARM_DEVICE_ARN="$(aws devicefarm list-devices \
    --region "$DEVICE_FARM_REGION" \
    --query "devices[?name=='$DEVICE_FARM_DEVICE_NAME' && os=='$DEVICE_FARM_OS_VERSION' && fleetType=='PUBLIC'].arn" \
    --output text)"
  if [[ -z "$DEVICE_FARM_DEVICE_ARN" || "$DEVICE_FARM_DEVICE_ARN" == None ]]; then
    echo "Public Device Farm device not found: $DEVICE_FARM_DEVICE_NAME, iOS $DEVICE_FARM_OS_VERSION" >&2
    exit 1
  fi
  mask_value "$DEVICE_FARM_DEVICE_ARN"

  echo "LiteRT $LITERT_VERSION, $PACKAGE_MANAGER, iOS Device $(xcrun --sdk iphoneos --show-sdk-version)"

  xcodebuild build-for-testing \
    "$XCODE_CONTAINER_FLAG" "$XCODE_CONTAINER" \
    -scheme LiteRTExample \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$TEST_WORKSPACE/DerivedData" \
    CODE_SIGNING_ALLOWED=NO

  DEVICE_PRODUCTS="$TEST_WORKSPACE/DerivedData/Build/Products/Debug-iphoneos"
  APP_BUNDLE="$DEVICE_PRODUCTS/LiteRTExample.app"
  XCTEST_BUNDLE="$APP_BUNDLE/PlugIns/LiteRTExampleTests.xctest"
  PACKAGE_DIRECTORY="$TEST_WORKSPACE/DeviceFarm"
  APP_PACKAGE="$PACKAGE_DIRECTORY/LiteRTExample.ipa"
  XCTEST_PACKAGE="$PACKAGE_DIRECTORY/LiteRTExampleTests.xctest.zip"

  if [[ ! -d "$APP_BUNDLE" || ! -d "$XCTEST_BUNDLE" ]]; then
    echo "Device build output is missing the app or XCTest bundle" >&2
    exit 1
  fi

  # Older Device Farm hosts may not provide the selected Xcode's Testing runtime dependencies.
  # https://docs.aws.amazon.com/devicefarm/latest/developerguide/ios-host-migration.html#ios-host-migration-differences
  # https://github.com/WebKit/WebKit/blob/main/Tools/TestWebKitAPI/TestWebKitAPI.xcodeproj/project.pbxproj
  IPHONEOS_DEVELOPER_DIRECTORY="$(xcode-select -p)/Platforms/iPhoneOS.platform/Developer"

  copy_xcode_test_dependency() {
    local binary_path="$1"
    local install_name="$2"
    local dependency_name="$3"
    local dependency_sources
    local linked_libraries

    if [[ ! -f "$binary_path" ]]; then
      return
    fi
    if ! linked_libraries="$(otool -L "$binary_path")"; then
      echo "Failed to inspect Xcode test runtime: $binary_path" >&2
      exit 1
    fi
    if ! awk -v install_name="$install_name" '
      NR > 1 && $1 == install_name { found = 1 }
      END { exit(found ? 0 : 1) }
    ' <<< "$linked_libraries"; then
      return
    fi

    if ! dependency_sources="$(
      find "$IPHONEOS_DEVELOPER_DIRECTORY" -name "$dependency_name" -print
    )"; then
      echo "Failed to locate Xcode test dependency: $dependency_name" >&2
      exit 1
    fi
    if [[ -z "$dependency_sources" ]]; then
      echo "Required Xcode test dependency not found: $dependency_name" >&2
      exit 1
    fi
    if [[ "$dependency_sources" == *$'\n'* ]]; then
      echo "Multiple Xcode test dependencies found: $dependency_name" >&2
      printf '%s\n' "$dependency_sources" >&2
      exit 1
    fi

    ditto "$dependency_sources" "$APP_BUNDLE/Frameworks/$dependency_name"
  }

  copy_xcode_test_dependency \
    "$APP_BUNDLE/Frameworks/libXCTestSwiftSupport.dylib" \
    '@rpath/_Testing_Foundation.framework/_Testing_Foundation' \
    '_Testing_Foundation.framework'
  copy_xcode_test_dependency \
    "$APP_BUNDLE/Frameworks/Testing.framework/Testing" \
    '@rpath/lib_TestingInterop.dylib' \
    'lib_TestingInterop.dylib'

  mkdir -p "$PACKAGE_DIRECTORY/Payload"
  ditto --norsrc --noextattr \
    "$APP_BUNDLE" "$PACKAGE_DIRECTORY/Payload/LiteRTExample.app"
  ditto -c -k --norsrc --noextattr --keepParent \
    "$PACKAGE_DIRECTORY/Payload" "$APP_PACKAGE"
  ditto -c -k --norsrc --noextattr --keepParent \
    "$XCTEST_BUNDLE" "$XCTEST_PACKAGE"

  upload_package() {
    local package_path="$1"
    local package_type="$2"
    local upload
    local upload_arn
    local upload_url
    local upload_status

    upload="$(aws devicefarm create-upload \
      --region "$DEVICE_FARM_REGION" \
      --project-arn "$DEVICE_FARM_PROJECT_ARN" \
      --name "$(basename "$package_path")" \
      --type "$package_type" \
      --query '[upload.arn, upload.url]' \
      --output text)"
    IFS=$'\t' read -r upload_arn upload_url <<< "$upload"
    mask_value "$upload_arn"
    mask_value "$upload_url"
    curl --fail --silent --show-error -T "$package_path" "$upload_url"

    while true; do
      upload_status="$(aws devicefarm get-upload \
        --region "$DEVICE_FARM_REGION" \
        --arn "$upload_arn" \
        --query upload.status \
        --output text)"
      case "$upload_status" in
        SUCCEEDED)
          DEVICE_FARM_UPLOAD_ARN="$upload_arn"
          return
          ;;
        FAILED|ERRORED)
          aws devicefarm get-upload \
            --region "$DEVICE_FARM_REGION" \
            --arn "$upload_arn" \
            --query 'upload.{Status:status,Message:message}'
          return 1
          ;;
      esac
      sleep 2
    done
  }

  upload_package "$APP_PACKAGE" IOS_APP
  APP_UPLOAD_ARN="$DEVICE_FARM_UPLOAD_ARN"
  upload_package "$XCTEST_PACKAGE" XCTEST_TEST_PACKAGE
  XCTEST_UPLOAD_ARN="$DEVICE_FARM_UPLOAD_ARN"

  DEVICE_SELECTION="{\"filters\":[{\"attribute\":\"ARN\",\"operator\":\"EQUALS\",\"values\":[\"$DEVICE_FARM_DEVICE_ARN\"]}],\"maxDevices\":1}"
  RUN_ARN=""
  RUN_COMPLETED=false
  stop_incomplete_run() {
    local exit_status="$1"
    trap - HUP INT TERM
    if [[ -n "$RUN_ARN" && "$RUN_COMPLETED" == false ]]; then
      aws devicefarm stop-run \
        --region "$DEVICE_FARM_REGION" \
        --arn "$RUN_ARN" >/dev/null 2>&1 || true
    fi
    exit "$exit_status"
  }
  trap 'stop_incomplete_run 129' HUP
  trap 'stop_incomplete_run 130' INT
  trap 'stop_incomplete_run 143' TERM

  RUN_ARN="$(aws devicefarm schedule-run \
    --region "$DEVICE_FARM_REGION" \
    --project-arn "$DEVICE_FARM_PROJECT_ARN" \
    --app-arn "$APP_UPLOAD_ARN" \
    --device-selection-configuration "$DEVICE_SELECTION" \
    --name "LiteRT $LITERT_VERSION - iOS $DEVICE_FARM_OS_VERSION - $PACKAGE_MANAGER" \
    --test "type=XCTEST,testPackageArn=$XCTEST_UPLOAD_ARN" \
    --execution-configuration 'accountsCleanup=false,appPackagesCleanup=false,videoCapture=false' \
    --query run.arn \
    --output text)"
  mask_value "$RUN_ARN"

  RUN_DEADLINE=$((SECONDS + DEVICE_FARM_TIMEOUT_SECONDS))

  while true; do
    RUN_STATUS="$(aws devicefarm get-run \
      --region "$DEVICE_FARM_REGION" \
      --arn "$RUN_ARN" \
      --query run.status \
      --output text)"
    if [[ "$RUN_STATUS" == COMPLETED ]]; then
      RUN_COMPLETED=true
      break
    fi
    if (( SECONDS >= RUN_DEADLINE )); then
      aws devicefarm stop-run \
        --region "$DEVICE_FARM_REGION" \
        --arn "$RUN_ARN" >/dev/null
      RUN_COMPLETED=true
      echo "Device Farm run timed out after $DEVICE_FARM_TIMEOUT_SECONDS seconds" >&2
      exit 1
    fi
    echo "Device Farm status: $RUN_STATUS"
    sleep 60
  done

  aws devicefarm get-run \
    --region "$DEVICE_FARM_REGION" \
    --arn "$RUN_ARN" \
    --query 'run.{Status:status,Result:result,Counters:counters}'
  RUN_RESULT="$(aws devicefarm get-run \
    --region "$DEVICE_FARM_REGION" \
    --arn "$RUN_ARN" \
    --query run.result \
    --output text)"
  [[ "$RUN_RESULT" == PASSED ]]
  exit
fi

echo "LiteRT $LITERT_VERSION, $PACKAGE_MANAGER, iOS Simulator $(xcrun --sdk iphonesimulator --show-sdk-version)"

if [[ -n "$SIMULATOR_ID" ]]; then
  SIMULATOR_DESTINATION="platform=iOS Simulator,id=${SIMULATOR_ID}"
else
  SIMULATOR_DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=latest"
fi

xcodebuild test \
  "$XCODE_CONTAINER_FLAG" "$XCODE_CONTAINER" \
  -scheme LiteRTExample \
  -testPlan Simulator \
  -sdk iphonesimulator \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath "$TEST_WORKSPACE/DerivedData" \
  -resultBundlePath "$TEST_WORKSPACE/TestResults.xcresult"
