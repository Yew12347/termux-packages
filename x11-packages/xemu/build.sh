TERMUX_PKG_HOMEPAGE=https://xemu.app/
TERMUX_PKG_DESCRIPTION="A free and open-source emulator for the original Xbox console."
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@George-Seven"
_COMMIT=956ef0b2ebe50896b7801d4f5ea621e431d9e3ae
TERMUX_PKG_VERSION=0.8.5
TERMUX_PKG_REVISION=1
TERMUX_PKG_DEPENDS="at-spi2-core, brotli, fontconfig, freetype, fribidi, gdk-pixbuf, glib, harfbuzz, libandroid-shmem, libandroid-support, libbz2, libc++, libcairo, libdecor, libepoxy, libexpat, libffi, libgraphite, libiconv, libjpeg-turbo, libpcap, libpixman, libpng, libsamplerate, libslirp, libwayland, libx11, libxau, libxcb, libxcomposite, libxcursor, libxdamage, libxdmcp, libdecor, libxext, libxfixes, libxi, libxinerama, libxkbcommon, libxrandr, libxrender, libxss, mesa, openssl, pango, pcre2, sdl2, zlib"
TERMUX_PKG_BUILD_DEPENDS="gtk3, libepoxy, libglvnd-dev, libpcap, libpixman, libsamplerate, libslirp, libtasn1, sdl2, vulkan-headers, xorgproto"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_SHA256=08be4300e513bc36f91b3c8276ff2c9572c73dd8cf98fac04fc3a8233feef1cf
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_BLACKLISTED_ARCHES="arm, i686, x86_64"
TERMUX_PKG_RM_AFTER_INSTALL="
lib/python*
"

# ---------------- SOURCE ----------------

termux_step_get_source() {
	mkdir -p "$TERMUX_PKG_SRCDIR"
	cd "$TERMUX_PKG_SRCDIR"
	git clone https://github.com/xemu-project/xemu
	cd xemu
	git checkout ${_COMMIT}
	git submodule update --init --recursive
	mv * .* ../
}

termux_step_post_get_source() {
	local s=$(find . -type f ! -path '*/.git/*' -print0 \
		| xargs -0 sha256sum | LC_ALL=C sort | sha256sum)
	[[ "$s" == "$TERMUX_PKG_SHA256  "* ]] \
		|| termux_error_exit "Checksum mismatch"
}

# ---------------- PRE-CONFIGURE ----------------

termux_step_pre_configure() {
	# Skip setjmp/_lib hacks
	termux_setup_cmake
	termux_setup_ninja
	if [ "$TERMUX_ON_DEVICE_BUILD" = "true" ]; then
		termux_setup_python_pip
		pip install pyyaml
	else
		pip install --break-system-packages pyyaml
	fi
}

# ---------------- CONFIGURE ----------------

termux_step_configure() {
	CFLAGS+=" -DANDROID"
	CXXFLAGS+=" $CFLAGS"
	LDFLAGS+=" -llog -landroid-shmem"

	CONFIGURE_FLAGS="
	--prefix=$TERMUX_PREFIX
	--enable-egl
	--enable-opengl
	--enable-vulkan
	--disable-glx
	--disable-stack-protector
	--disable-vte
	--disable-vnc-sasl
	--disable-xen
	--disable-xen-pci-passthrough
	--disable-hvf
	--disable-whpx
	--disable-snappy
	--disable-lzfse
	--disable-seccomp
	--disable-vhost-user
	--disable-vhost-user-blk-server
	--disable-guest-agent
	--disable-werror
	--enable-trace-backends=nop
	--target-list=i386-softmmu
	--extra-cflags=-DXBOX=1
	--enable-gtk
	--enable-x11
	"

	if [ "$TERMUX_ON_DEVICE_BUILD" = "true" ]; then
		./configure $CONFIGURE_FLAGS
	else
		./configure \
			--cross-prefix=${TERMUX_HOST_PLATFORM}- \
			--host-cc=gcc \
			--cc=$CC \
			--cxx=$CXX \
			--objcc=$CC \
			$CONFIGURE_FLAGS
	fi

	grep -q CONFIG_EGL=y config-host.mak \
		|| termux_error_exit "EGL not enabled"

	grep -q CONFIG_VULKAN=y config-host.mak \
		|| termux_error_exit "Vulkan not enabled"

	! grep -q CONFIG_GLX=y config-host.mak \
		|| termux_error_exit "GLX enabled (software path)"
}

# ---------------- BUILD ----------------

termux_step_make() {
	make qemu-system-i386

	mkdir -p dist
	mv build/qemu-system-i386 dist/xemu

	python3 ./scripts/gen-license.py > dist/LICENSE.txt

	sed "s|@TERMUX_PREFIX@|$TERMUX_PREFIX|g" \
		"$TERMUX_PKG_BUILDER_DIR/iso2xiso.in" > dist/iso2xiso
	chmod +x dist/iso2xiso

	termux_download \
	"https://archive.org/download/xemustarter/XEMU%20FILES.zip/XEMU%20FILES%2FBoot%20ROM%20Image%2Fmcpx_1.0.bin" \
	dist/mcpx_1.0.bin \
	e99e3a772bf5f5d262786aee895664eb96136196e37732fe66e14ae062f20335

	termux_download \
	"https://archive.org/download/xemustarter/XEMU%20FILES.zip/XEMU%20FILES%2FBIOS%2FComplex_4627v1.03.bin" \
	dist/4627v1.03.bin \
	1de4c87effe40d44f95581d204f9fa0600fbd5fe2171692316dcf97af0f4113f

	termux_download \
	"https://github.com/xemu-project/xemu-hdd-image/releases/latest/download/xbox_hdd.qcow2.zip" \
	dist/xbox_hdd.qcow2.zip \
	d9f5a4c1224ff24cf9066067bda70cc8b9c874ea22b9c542eb2edbfc4621bb39

	unzip -o dist/xbox_hdd.qcow2.zip -d dist
}

# ---------------- INSTALL ----------------

termux_step_make_install() {
	install -Dm755 dist/xemu "$TERMUX_PREFIX/libexec/xemu-bin"

	cat > "$TERMUX_PREFIX/bin/xemu" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

# GTK + X11 windowed mode for Openbox or X11
export DISPLAY=:0
export SDL_RENDER_DRIVER=opengl
export QEMU_GL=on
export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/turnip_icd.json
export MESA_LOADER_DRIVER_OVERRIDE=zink
export GALLIUM_DRIVER=zink

exec "$PREFIX/libexec/xemu-bin" "$@"
EOF
	chmod +x "$TERMUX_PREFIX/bin/xemu"

	install -Dm755 dist/iso2xiso "$TERMUX_PREFIX/bin/iso2xiso"
	install -Dm644 dist/*.bin "$TERMUX_PREFIX/share/xemu"
	install -Dm644 dist/xbox_hdd.qcow2 "$TERMUX_PREFIX/share/xemu"
}

termux_step_install_license() {
	install -Dm644 dist/LICENSE.txt \
	"$TERMUX_PREFIX/share/doc/xemu/LICENSE"
}
