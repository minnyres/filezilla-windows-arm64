#!/bin/bash -e

help_msg="Usage: ./build.sh [arm32|arm64]"

[ -z "$vcpkg_dir" ] && vcpkg_dir=$PWD/vcpkg
[ -z "$llvm_dir" ] && llvm_dir=$PWD/llvm-mingw
work_dir=$PWD

if [ $# == 1 ]; then
    if [ $1 == "arm32" ]; then
        arch=arm32
        vcpkg_libs_dir=$vcpkg_dir/installed/arm-mingw-static-release
        TARGET=armv7-w64-mingw32
        shellext_patch="0003-Enable-shellext-on-Windows-ARM32.patch"
        export libclang_rt="${llvm_dir}/lib/clang/17/lib/windows/libclang_rt.builtins-arm.a"
    elif [ $1 == "arm64" ]; then
        arch=arm64
        vcpkg_libs_dir=$vcpkg_dir/installed/arm64-mingw-static-release
        TARGET=aarch64-w64-mingw32
        shellext_patch="0003-Enable-shellext-on-Windows-ARM64.patch"
        export libclang_rt="${llvm_dir}/lib/clang/17/lib/windows/libclang_rt.builtins-aarch64.a"
    else
        echo $help_msg
        exit -1
    fi
else
    echo $help_msg
    exit -1
fi

libfilezilla_version=0.48.1
libfilezilla_path=$PWD/libfilezilla-windows-$arch
filezilla_version=3.67.1
filezilla_path=$PWD/filezilla-windows-$arch
wxwidgets_version=3.2.5
wxwidgets_path=$PWD/wxmsw-windows-$arch

export PATH=$llvm_dir/bin:$wxwidgets_path/bin:$PATH
export PKG_CONFIG_LIBDIR=$vcpkg_libs_dir/lib/pkgconfig:$libfilezilla_path/lib/pkgconfig
export PKG_CONFIG_PATH=$PKG_CONFIG_LIBDIR
export CPPFLAGS="-I$vcpkg_libs_dir/include -I$libfilezilla_path/include"
export LDFLAGS="-L$vcpkg_libs_dir/lib -L$libfilezilla_path/lib --static -s  -Wl,--allow-multiple-definition"

wget="wget -nc --progress=bar:force"
gitclone="git clone --depth=1 --recursive"

function gnumakeplusinstall {
    make -j $(nproc)
    make install
}

# Build wxwidgets
[ -d wxWidgets ] || $gitclone --branch v$wxwidgets_version --recurse-submodules --depth 1 https://github.com/wxWidgets/wxWidgets.git
pushd wxWidgets
if [ $arch == "arm32" ]; then   
    git apply ../patches/wx-fix-arm32-support.patch
fi
mkdir build-$TARGET
cd build-$TARGET
../configure --host=$TARGET --prefix=${wxwidgets_path} --with-zlib=sys --with-msw --with-libiconv-prefix=$vcpkg_dir --disable-shared --disable-debug_flag --enable-optimise --enable-unicode
gnumakeplusinstall
popd

# Build libfilezilla
# $wget https://download.filezilla-project.org/libfilezilla/libfilezilla-${libfilezilla_version}.tar.xz
svn co https://svn.filezilla-project.org/svn/libfilezilla/trunk@11169 libfilezilla-${libfilezilla_version}
pushd libfilezilla-${libfilezilla_version}
autoreconf -fi
./configure --host=$TARGET --prefix=${libfilezilla_path} --disable-shared --enable-static 
gnumakeplusinstall
popd
rm -rf libfilezilla-${libfilezilla_version}

# Build filezilla
# $wget https://download.filezilla-project.org/client/FileZilla_${filezilla_version}_src.tar.xz
svn co https://svn.filezilla-project.org/svn/FileZilla3/trunk@11172 filezilla-${filezilla_version}
pushd filezilla-${filezilla_version}
patch -p1 < ../patches/0002-Enable-shellext-build-on-clang-MinGW.patch
patch -p1 < ../patches/$shellext_patch
autoreconf -fi
pushd src/fzshellext
autoreconf -fi
popd
./configure --build=x86_64-linux-gnu --host=$TARGET --prefix=${filezilla_path} --disable-shared --enable-static  --with-pugixml=builtin --disable-storj --with-wx-config=${wxwidgets_path}/bin/wx-config
gnumakeplusinstall
find . -name "*.exe" -exec $TARGET-strip {} \;
find . -name "*.dll" -exec $TARGET-strip {} \;
find ${filezilla_path} -name "*.exe" -exec $TARGET-strip {} \;
find ${filezilla_path} -name "*.dll" -exec $TARGET-strip {} \;
cd data
if [ $arch == "arm64" ]; then
    sed -i '/fzshellext\/32/d' makezip.sh
elif [ $arch == "arm32" ]; then
    sed -i '/fzshellext\/64/d' makezip.sh
fi
sed -i '/fzstorj/d' makezip.sh
bash makezip.sh ${filezilla_path}
mv FileZilla.zip $work_dir/filezilla_${filezilla_version}_$arch.zip
popd
rm -rf filezilla-${filezilla_version}
