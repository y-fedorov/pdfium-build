#!/usr/bin/env bash

set -e

MAJOR_VERSION=0.1
LIBNAME="libpdfium-dev"

git=$(which git)

#
# Sandbox
#
DEB_BUILD_DIR="$(pwd)/deb-build-env"

mkdir -p ${DEB_BUILD_DIR}
cd ${DEB_BUILD_DIR}

#
# Download, configure, and build PDFium
#
DEPOT_TOOLS="${DEB_BUILD_DIR}/depot_tools"
if [ ! -d "${DEPOT_TOOLS}" ]; then
    ${git} clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH="${DEPOT_TOOLS}":"$PATH"

#clean all git change for pdfium
cd pdfium/build
git reset --hard
cd ../../

gclient config --unmanaged https://pdfium.googlesource.com/pdfium.git
gclient sync
cd pdfium



BUILD_RES="out/Release_x64"
mkdir -p ${BUILD_RES}
cat << EOF > ${BUILD_RES}/args.gn
pdf_use_skia = false # Set true to enable experimental skia backend.
pdf_enable_xfa = false # Set false to remove XFA support (implies JS support).
pdf_enable_v8 = false # Set false to remove Javascript support.
is_component_build = true
use_sysroot=false
EOF

# comment visibility flag before build. fix pdftool build issue
sed -i -- 's/"\/\/build\/config\/gcc:symbol_visibility_hidden",/# "\/\/build\/config\/gcc:symbol_visibility_hidden",/g'  build/config/BUILDCONFIG.gn

gn gen ${BUILD_RES}

ninja -C ${BUILD_RES}

#
# Prepare build environment for deb package
#
MINOR_VERSION=$(${git} log -1 --pretty=format:%h)
VERSION=${MAJOR_VERSION}~${MINOR_VERSION}
DEB_BUILD_PDFIUM="${DEB_BUILD_DIR}/pdfium-${VERSION}"

if [ -d ${DEB_BUILD_PDFIUM} ]; then
    rm -rf ${DEB_BUILD_PDFIUM}
fi
mkdir -p ${DEB_BUILD_PDFIUM}

cp -r ../../debian ${DEB_BUILD_PDFIUM}/

#
# Copy build artifacts to deb sandbox environment
#
mkdir -p "${DEB_BUILD_PDFIUM}/usr/lib/pdfium"
mkdir -p "${DEB_BUILD_PDFIUM}/usr/include/pdfium"
find ${BUILD_RES} -name '*.a' -not -path "**/testing/*" -not -path "**/build/*" -not -name 'libtest_support.a' -exec cp {} ${DEB_BUILD_PDFIUM}/usr/lib/pdfium/ \;
cp public/*.h ${DEB_BUILD_PDFIUM}/usr/include/pdfium/

#
# Prepare changelog
#
DEB_CHANGE_LOG=${DEB_BUILD_PDFIUM}/debian/changelog 
${git} log --pretty=tformat:"%h|%H|%s|%an <%aE>|%aD" | \
awk '{split($0,a,"|"); print "'${LIBNAME}' ('${MAJOR_VERSION}'~"a[1]") unstable; urgency=low\n\n\t* --> sha1:"a[2]"\n\t* "a[3]"\n\n\t-- "a[4]"\t  "a[5]"\n"}' | \
sed 's/\t/  /' > ${DEB_CHANGE_LOG}

#remove last empty line
#sed -i '$ d' ${DEB_CHANGE_LOG}

#
# Build deb package
#
cd ${DEB_BUILD_PDFIUM}
dpkg-buildpackage -b

# alternative build option
#debuild -us -uc

echo "Success!"
