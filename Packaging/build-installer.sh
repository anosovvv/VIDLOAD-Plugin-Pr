#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
engine_root="${project_root}/Engine"
tools_source="/Applications/VIDLOAD.app/Contents/Resources/VIDLOADTools.bundle"
ccx_path="${1:-}"
version="0.1.3"
output_dir="${project_root}/dist"
installer_path="${output_dir}/VIDLOAD-Plugin-Pr-${version}.pkg"

if [[ -z "${ccx_path}" || ! -f "${ccx_path}" ]]; then
    echo "Pass the path to the packaged VIDLOAD Plugin Pr .ccx file." >&2
    exit 64
fi

ccx_path="${ccx_path:A}"

if [[ ! -d "${tools_source}" ]]; then
    echo "Bundled VIDLOAD tools were not found at: ${tools_source}" >&2
    exit 66
fi

if [[ -e "${installer_path}" ]]; then
    echo "Installer already exists: ${installer_path}" >&2
    exit 73
fi

work_dir="$(/usr/bin/mktemp -d /private/tmp/vidload-plugin-pr-installer.XXXXXX)"
trap '/bin/rm -rf "${work_dir}"' EXIT

payload_root="${work_dir}/payload"
engine_app="${payload_root}/Applications/VIDLOAD Plugin Pr Engine.app"
resources_dir="${engine_app}/Contents/Resources"
engine_binary_dir="${engine_app}/Contents/MacOS"

cd "${engine_root}"
swift build -c release --arch arm64
swift build -c release --arch x86_64

/bin/mkdir -p "${engine_binary_dir}" "${resources_dir}" \
    "${payload_root}/Library/Application Support/VIDLOAD Plugin Pr" \
    "${payload_root}/Library/LaunchAgents" \
    "${work_dir}/scripts" "${output_dir}"

/usr/bin/lipo -create \
    "${engine_root}/.build/arm64-apple-macosx/release/VIDLOADPluginEngine" \
    "${engine_root}/.build/x86_64-apple-macosx/release/VIDLOADPluginEngine" \
    -output "${engine_binary_dir}/VIDLOADPluginEngine"

/bin/cp "${script_dir}/engine-app/Info.plist" "${engine_app}/Contents/Info.plist"
/bin/cp "${script_dir}/engine-app/VIDLOADPluginEngine.icns" "${resources_dir}/VIDLOADPluginEngine.icns"
/usr/bin/ditto --norsrc "${tools_source}" "${resources_dir}/VIDLOADTools.bundle"
/usr/bin/xattr -rc "${engine_app}"
/bin/cp "${ccx_path}" "${payload_root}/Library/Application Support/VIDLOAD Plugin Pr/VIDLOAD Plugin Pr.ccx"
/bin/cp "${script_dir}/launchd/com.anosovvv.vidload-plugin-pr.engine.plist" \
    "${payload_root}/Library/LaunchAgents/com.anosovvv.vidload-plugin-pr.engine.plist"
/bin/cp "${script_dir}/scripts/postinstall" "${work_dir}/scripts/postinstall"
/bin/chmod 755 "${engine_binary_dir}/VIDLOADPluginEngine" "${work_dir}/scripts/postinstall"
# Finder metadata can create AppleDouble files when the staged bundle is copied.
# They are not part of the plugin and needlessly bloat the installer.
/usr/bin/xattr -rc "${payload_root}"
/usr/bin/find "${payload_root}" -type f -name '._*' -delete

/usr/bin/pkgbuild \
    --root "${payload_root}" \
    --scripts "${work_dir}/scripts" \
    --identifier "com.anosovvv.vidload-plugin-pr.installer" \
    --version "${version}" \
    --install-location / \
    "${installer_path}"

/usr/bin/shasum -a 256 "${installer_path}" > "${installer_path}.sha256"
/usr/sbin/pkgutil --payload-files "${installer_path}" > "${installer_path}.contents.txt"

echo "Created ${installer_path}"
