#!/usr/bin/env bash

[[ $# = 0 ]] && echo "No Input" && exit 1

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Create input & working directory if it does not exist
mkdir -p "$PROJECT_DIR"/input "$PROJECT_DIR"/working

# download or copy from local?
if echo "$1" | grep -e '^\(https\?\|ftp\)://.*$' > /dev/null; then
    # 1DRV URL DIRECT LINK IMPLEMENTATION
    if echo "$1" | grep -e '1drv.ms' > /dev/null; then
        URL=`curl -I "$1" -s | grep location | sed -e "s/redir/download/g" | sed -e "s/location: //g"`
    else
        URL=$1
    fi
    cd "$PROJECT_DIR"/input || exit
    { type -p aria2c > /dev/null 2>&1 && printf "Downloading File...\n" && aria2c -x16 -j"$(nproc)" "${URL}"; } || { printf "Downloading File...\n" && sudo apt install axel >> /dev/null 2>&1 && axel -q -a -n 78 "${URL}" || exit 1; }
    detox "${URL##*/}"
else
    URL=$(printf "%s\n" "$1")
    [[ -e "$URL" ]] || { echo "Invalid Input" && exit 1; }
fi

FILE=$(echo ${URL##*/} | inline-detox)
EXTENSION=$(echo ${URL##*.} | inline-detox)
UNZIP_DIR=${FILE/.$EXTENSION/}
PARTITIONS="system vendor cust odm oem factory product modem systemex xrom system_ext system_other"

if [[ -d "$1" ]]; then
    echo 'Directory detected. Copying...'
    cp -a "$1" "$PROJECT_DIR"/working/"${UNZIP_DIR}"
elif [[ -f "$1" ]]; then
    echo 'File detected. Copying...'
    cp -a "$1" "$PROJECT_DIR"/input/"${FILE}" > /dev/null 2>&1
fi

# clone other repo's
if [[ -d "$PROJECT_DIR/Firmware_extractor" ]]; then
    git -C "$PROJECT_DIR"/Firmware_extractor pull --recurse-submodules
else
    git clone -q --recurse-submodules https://github.com/AndroidDumps/Firmware_extractor "$PROJECT_DIR"/Firmware_extractor
fi
if [[ -d "$PROJECT_DIR/mkbootimg_tools" ]]; then
    git -C "$PROJECT_DIR"/mkbootimg_tools pull --recurse-submodules
else
    git clone -q https://github.com/carlitros900/mkbootimg_tools "$PROJECT_DIR/mkbootimg_tools"
fi
if [[ -d "$PROJECT_DIR/vmlinux-to-elf" ]]; then
    git -C "$PROJECT_DIR"/vmlinux-to-elf pull --recurse-submodules
else
    git clone -q https://github.com/marin-m/vmlinux-to-elf "$PROJECT_DIR/vmlinux-to-elf"
fi

# extract rom via Firmware_extractor
[[ ! -d "$1" ]] && bash "$PROJECT_DIR"/Firmware_extractor/extractor.sh "$PROJECT_DIR"/input/"${FILE}" "$PROJECT_DIR"/working/"${UNZIP_DIR}"

# extract PARTITIONS
cd "$PROJECT_DIR"/working/"${UNZIP_DIR}" || exit
for p in $PARTITIONS; do
    if [[ -e "$p.img" ]]; then
        mkdir "$p" 2> /dev/null || rm -rf "${p:?}"/*
        echo "Extracting $p partition"
        7z x "$p".img -y -o"$p"/ > /dev/null 2>&1
        rm "$p".img > /dev/null 2>&1
    fi
done

# board-info.txt
find "$PROJECT_DIR"/working/"${UNZIP_DIR}"/modem -type f -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING=MPSS." | sed "s|QC_IMAGE_VERSION_STRING=MPSS.||g" | cut -c 4- | sed -e 's/^/require version-baseband=/' >> "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt
find "$PROJECT_DIR"/working/"${UNZIP_DIR}"/tz* -type f -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING" | sed "s|QC_IMAGE_VERSION_STRING|require version-trustzone|g" >> "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt
if [ -e "$PROJECT_DIR"/working/"${UNZIP_DIR}"/vendor/build.prop ]; then
    strings "$PROJECT_DIR"/working/"${UNZIP_DIR}"/vendor/build.prop | grep "ro.vendor.build.date.utc" | sed "s|ro.vendor.build.date.utc|require version-vendor|g" >> "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt
fi
sort -u -o "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt

# set variables
ls system/build*.prop 2> /dev/null || ls system/system/build*.prop 2> /dev/null || { echo "No system build*.prop found, pushing cancelled!" && exit; }
flavor=$(grep -oP "(?<=^ro.build.flavor=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.vendor.build.flavor=).*" -hs vendor/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.system.build.flavor=).*" -hs {system,system/system}/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.build.type=).*" -hs {system,system/system}/build*.prop)
release=$(grep -oP "(?<=^ro.build.version.release=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${release}" ]] && release=$(grep -oP "(?<=^ro.vendor.build.version.release=).*" -hs vendor/build*.prop)
[[ -z "${release}" ]] && release=$(grep -oP "(?<=^ro.system.build.version.release=).*" -hs {system,system/system}/build*.prop)
id=$(grep -oP "(?<=^ro.build.id=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${id}" ]] && id=$(grep -oP "(?<=^ro.vendor.build.id=).*" -hs vendor/build*.prop)
[[ -z "${id}" ]] && id=$(grep -oP "(?<=^ro.system.build.id=).*" -hs {system,system/system}/build*.prop)
incremental=$(grep -oP "(?<=^ro.build.version.incremental=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${incremental}" ]] && incremental=$(grep -oP "(?<=^ro.vendor.build.version.incremental=).*" -hs vendor/build*.prop)
[[ -z "${incremental}" ]] && incremental=$(grep -oP "(?<=^ro.system.build.version.incremental=).*" -hs {system,system/system}/build*.prop)
tags=$(grep -oP "(?<=^ro.build.tags=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${tags}" ]] && tags=$(grep -oP "(?<=^ro.vendor.build.tags=).*" -hs vendor/build*.prop)
[[ -z "${tags}" ]] && tags=$(grep -oP "(?<=^ro.system.build.tags=).*" -hs {system,system/system}/build*.prop)
platform=$(grep -oP "(?<=^ro.board.platform=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${platform}" ]] && platform=$(grep -oP "(?<=^ro.vendor.board.platform=).*" -hs vendor/build*.prop)
[[ -z "${platform}" ]] && platform=$(grep -oP "(?<=^ro.system.board.platform=).*" -hs {system,system/system}/build*.prop)
manufacturer=$(grep -oP "(?<=^ro.product.manufacturer=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${manufacturer}" ]] && manufacturer=$(grep -oP "(?<=^ro.vendor.product.manufacturer=).*" -hs vendor/build*.prop)
[[ -z "${manufacturer}" ]] && manufacturer=$(grep -oP "(?<=^ro.system.product.manufacturer=).*" -hs {system,system/system}/build*.prop)
fingerprint=$(grep -oP "(?<=^ro.build.fingerprint=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${fingerprint}" ]] && fingerprint=$(grep -oP "(?<=^ro.vendor.build.fingerprint=).*" -hs vendor/build*.prop)
[[ -z "${fingerprint}" ]] && fingerprint=$(grep -oP "(?<=^ro.system.build.fingerprint=).*" -hs {system,system/system}/build*.prop)
brand=$(grep -oP "(?<=^ro.product.brand=).*" -hs {system,system/system,vendor}/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.vendor.brand=).*" -hs vendor/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.vendor.product.brand=).*" -hs vendor/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.system.brand=).*" -hs {system,system/system}/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(echo "$fingerprint" | cut -d / -f1)
codename=$(grep -oP "(?<=^ro.product.device=).*" -hs {system,system/system,vendor}/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.vendor.device=).*" -hs vendor/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.vendor.product.device=).*" -hs vendor/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.system.device=).*" -hs {system,system/system}/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(echo "$fingerprint" | cut -d / -f3 | cut -d : -f1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.build.fota.version=).*" -hs {system,system/system}/build*.prop | cut -d - -f1 | head -1)
description=$(grep -oP "(?<=^ro.build.description=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.vendor.build.description=).*" -hs vendor/build*.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.system.build.description=).*" -hs {system,system/system}/build*.prop)
[[ -z "${description}" ]] && description="$flavor $release $id $incremental $tags"
is_ab=$(grep -oP "(?<=^ro.build.ab_update=).*" -hs {system,system/system,vendor}/build*.prop | head -1)
[[ -z "${is_ab}" ]] && is_ab="false"
branch=$(echo "$description" | tr ' ' '-')
repo=$(echo "$brand"_"$codename"_dump | tr '[:upper:]' '[:lower:]')
platform=$(echo "$platform" | tr '[:upper:]' '[:lower:]' | tr -dc '[:print:]' | tr '_' '-' | cut -c 1-35)
top_codename=$(echo "$codename" | tr '[:upper:]' '[:lower:]' | tr -dc '[:print:]' | tr '_' '-' | cut -c 1-35)
manufacturer=$(echo "$manufacturer" | tr '[:upper:]' '[:lower:]' | tr -dc '[:print:]' | tr '_' '-' | cut -c 1-35)
printf "# %s\n- manufacturer: %s\n- platform: %s\n- codename: %s\n- flavor: %s\n- release: %s\n- id: %s\n- incremental: %s\n- tags: %s\n- fingerprint: %s\n- is_ab: %s\n- brand: %s\n- branch: %s\n- repo: %s\n" "$description" "$manufacturer" "$platform" "$codename" "$flavor" "$release" "$id" "$incremental" "$tags" "$fingerprint" "$is_ab" "$brand" "$branch" "$repo" > "$PROJECT_DIR"/working/"${UNZIP_DIR}"/README.md
cat "$PROJECT_DIR"/working/"${UNZIP_DIR}"/README.md

# copy file names
chown "$(whoami)" ./* -R
chmod -R u+rwX ./* #ensure final permissions
find "$PROJECT_DIR"/working/"${UNZIP_DIR}" -type f -printf '%P\n' | sort | grep -v ".git/" > "$PROJECT_DIR"/working/"${UNZIP_DIR}"/all_files.txt

echo "Dump done locally."
exit 1


