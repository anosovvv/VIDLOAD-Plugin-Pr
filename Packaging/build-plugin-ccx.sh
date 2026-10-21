#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
output_dir="${project_root}/dist"
output_path="${1:-${output_dir}/com.anosovvv.vidload-plugin-pr.ccx}"

if [[ -e "${output_path}" ]]; then
    echo "Plugin package already exists: ${output_path}" >&2
    exit 73
fi

/bin/mkdir -p "${output_dir}"

(
    cd "${project_root}"
    /usr/bin/zip -q -r "${output_path}" manifest.json index.html src
)

/usr/bin/unzip -t "${output_path}" >/dev/null
echo "Created ${output_path}"
