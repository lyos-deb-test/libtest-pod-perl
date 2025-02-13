#!/bin/bash

# 判断当前用户是否为 root
IS_ROOT=false
if [ "$EUID" -eq 0 ]; then
    IS_ROOT=true
fi

# 确保 dpkg-dev 和 devscripts 已安装
REQUIRED_PKGS="dpkg-dev devscripts"

if [ "$IS_ROOT" = false ]; then
    sudo apt-get update
    sudo apt-get install -y $REQUIRED_PKGS
else
    apt-get update
    apt-get install -y $REQUIRED_PKGS
fi

# 获取当前目录下的所有子文件夹
SUBDIRS=($(find . -maxdepth 1 -mindepth 1 -type d -exec basename {} \;))

# 检查是否只有一个子文件夹
if [ "${#SUBDIRS[@]}" -ne 1 ]; then
    echo "错误：当前目录下必须有且仅有一个子文件夹。"
    if [ "${#SUBDIRS[@]}" -eq 0 ]; then
        echo "未找到任何子文件夹。"
    else
        echo "找到以下多个子文件夹："
        printf '%s\n' "${SUBDIRS[@]}"
    fi
    exit 1
fi

PROJECT_NAME="${SUBDIRS[0]}"
SOURCE_DIR="${PWD}/${PROJECT_NAME}"  # 源码目录

# 检查源码目录是否存在
if [ ! -d "$SOURCE_DIR" ]; then
    echo "源码目录 ${SOURCE_DIR} 不存在"
    exit 1
fi

# 进入源码目录并从 debian/changelog 中提取版本号
cd "${SOURCE_DIR}"

FORMAT_FILE="${SOURCE_DIR}/debian/source/format"
if [ ! -f "${FORMAT_FILE}" ] || ! grep -q "3.0 (native)" "${FORMAT_FILE}"; then
	VERSION=$(dpkg-parsechangelog --show-field Version)
	# 提取上游版本号，忽略 Debian 修订版本号和 epoch
	VERSION=${VERSION%%-*}  # 去掉 Debian 修订版本号
	if [[ "$VERSION" == *:* ]]; then
	    VERSION=${VERSION#*:}  # 如果有 epoch，去掉 epoch
	fi
	
	ORIG_TARBALL="${PROJECT_NAME}_${VERSION}.orig.tar.gz"
	
	# 创建临时目录并复制源码（不包括 debian 文件夹）
	TEMP_DIR=$(mktemp -d)
	cp -r "${SOURCE_DIR}/." "${TEMP_DIR}/"
	rm -rf "${TEMP_DIR}/debian"
	
	# 返回上一级目录并在临时目录中创建 .orig.tar.gz 文件
	cd ..
	tar -czf "${ORIG_TARBALL}" -C "${TEMP_DIR}" .
	
	# 清理临时目录
	rm -rf "${TEMP_DIR}"
else
    echo "Detected '3.0 (native)' source format, skipping orig.tar.gz creation."
fi

# 自动安装构建依赖
echo "Installing build dependencies..."
if [ "$IS_ROOT" = false ]; then
    sudo mk-build-deps -i -t "apt-get -y" "${SOURCE_DIR}/debian/control"
else
    mk-build-deps -i -t "apt-get -y" "${SOURCE_DIR}/debian/control"
fi

# 使用 debuild 构建 Debian 包
echo "Building Debian package..."
cd "${SOURCE_DIR}"
debuild -us -uc

echo "Debian package build completed."