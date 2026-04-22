BUILD_CONFIG="release"

fail()
{
	echo "$1" 1>&2
	exit 1
}

BUILD_ROOT=$PWD/build
SOURCE_ROOT=$PWD
BUILD_FOLDER=$BUILD_ROOT/build-$BUILD_CONFIG
DEPLOY_FOLDER=$BUILD_ROOT/deploy-$BUILD_CONFIG
INSTALLER_FOLDER=$BUILD_ROOT/installer-$BUILD_CONFIG

if [ -n "$CI_VERSION" ]; then
  VERSION=$CI_VERSION
else
  VERSION=`cat $SOURCE_ROOT/app/version.txt`
fi

command -v qmake6 >/dev/null 2>&1 || fail "Unable to find 'qmake6' in your PATH!"
command -v linuxdeployqt >/dev/null 2>&1 || fail "Unable to find 'linuxdeployqt' in your PATH!"

echo Cleaning output directories
rm -rf $BUILD_FOLDER
rm -rf $DEPLOY_FOLDER
rm -rf $INSTALLER_FOLDER
mkdir $BUILD_ROOT
mkdir $BUILD_FOLDER
mkdir $DEPLOY_FOLDER
mkdir $INSTALLER_FOLDER

echo Configuring the project
pushd $BUILD_FOLDER
# We build with Wayland support, but exclude libwayland-client.so and related Wayland libraries from
# the AppImage using linuxdeployqt's -exclude-libs option. This prevents libEGL_mesa.so from failing
# to load due to missing symbols from the host's version of libwayland-client.so.
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
qmake6 $SOURCE_ROOT/moonlight-qt.pro PREFIX=$DEPLOY_FOLDER/usr DEFINES+=APP_IMAGE || fail "Qmake failed!"
popd

echo Compiling Moonlight in $BUILD_CONFIG configuration
pushd $BUILD_FOLDER
make -j$(nproc) $(echo "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]') || fail "Make failed!"
popd

echo Deploying to staging directory
pushd $BUILD_FOLDER
make install || fail "Make install failed!"
popd

# We need to manually place SDL3 in our AppImage, since linuxdeployqt
# cannot see the dependency via ldd when it looks at SDL2-compat.
echo Staging SDL3 library
mkdir -p $DEPLOY_FOLDER/usr/lib
cp /usr/local/lib/libSDL3.so.0 $DEPLOY_FOLDER/usr/lib/

echo Creating AppImage
pushd $INSTALLER_FOLDER
export QT_PLUGIN_PATH=$(qmake6 -query QT_INSTALL_PLUGINS)
VERSION=$VERSION linuxdeployqt $DEPLOY_FOLDER/usr/share/applications/com.moonlight_stream.Moonlight.desktop \
  -qmake=qmake6 -qmldir=$SOURCE_ROOT/app/gui -appimage -extra-plugins=tls,platforms/libqwayland-generic.so,platforms/libqwayland-egl.so,wayland-graphics-integration-client,wayland-shell-integration,wayland-decoration-client \
  -exclude-libs=libwayland-client.so.0,libwayland-cursor.so.0,libwayland-egl.so.1,libdrm.so.2,libgbm.so.1,libvulkan.so.1 \
  -executable=$DEPLOY_FOLDER/usr/lib/libSDL3.so.0 || fail "linuxdeployqt failed!"
popd

echo Build successful