#!/usr/bin/env bash
#
# This is the bootstrap Linux shell script for installing WasmEdge.
# It will detect the platform and architecture, download the corresponding
# WasmEdge release package, and install it to the specified path.
#
# MODIFICATIONS:
#   1. Installation directory is set to ~/.wasmedge.
#   2. Download directory is changed to ~/Downloads/wasm.
#   3. The cleanup code (which deletes the download) has been removed.
#   4. No changes are made to .zshrc; instead, the environment setup is written
#      into ~/.oh-my-zsh/custom/wasmedge.zsh.
#   5. All operations are now entirely local (removing any sudo-dependent logic).
#   6. The script now always runs in verbose mode (set -xv) and outputs every
#      command to both stdout and a log file at ~/.wasmedge/install.log.

set -e

RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
YELLOW=$'\e[0;33m'
NC=$'\e[0m' # No Color

# Set download directory to ~/Downloads/wasm (instead of /tmp)
TMP_DIR="$HOME/Downloads/wasm"

# Use the user’s home directory if not already set
if [ "$__HOME__" = "" ]; then
	__HOME__="$HOME"
fi

info() {
	command printf '\e[0;32mInfo\e[0m: %s\n\n' "$1"
}

warn() {
	command printf '\e[0;33mWarn\e[0m: %s\n\n' "$1"
}

error() {
	command printf '\e[0;31mError\e[0m: %s\n\n' "$1" 1>&2
}

eprintf() {
	command printf '%s\n' "$1" 1>&2
}

get_cuda_version() {
	local cuda=""
	cuda=$($1 --version 2>/dev/null | grep "Cuda compilation tools" | cut -f5 -d ' ' | cut -f1 -d ',')
	echo ${cuda}
}

detect_cuda_nvcc() {
	local cuda=""
	if [[ "${BY_PASS_CUDA_VERSION}" != "0" ]]; then
		cuda="${BY_PASS_CUDA_VERSION}"
	else
		nvcc_paths=("nvcc" "/usr/local/cuda/bin/nvcc" "/opt/cuda/bin/nvcc")
		for nvcc_path in "${nvcc_paths[@]}"
		do
			cuda=$(get_cuda_version ${nvcc_path})
			if [[ "${cuda}" =~ "12" ]]; then
				cuda="12"
				break
			elif [[ "${cuda}" =~ "11" ]]; then
				cuda="11"
				break
			fi
		done
	fi

	echo ${cuda}
}

detect_libcudart() {
	local cudart="0"
	LIBCUDART_PATH="/usr/local/cuda/lib64/libcudart.so"
	if [[ "${BY_PASS_CUDA_VERSION}" != "0" ]]; then
		cudart="1"
	elif [ -f ${LIBCUDART_PATH} ]; then
		cudart="1"
	fi

	echo ${cudart}
}

_realpath() {
	[[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

_downloader() {
	local url=$1
	if ! command -v curl &>/dev/null; then
		if ! command -v wget &>/dev/null; then
			error "Cannot find wget or curl"
			eprintf "Please install wget or curl"
			exit 1
		else
			wget -c --directory-prefix="$TMP_DIR" "$url"
		fi
	else
		pushd "$TMP_DIR"
		curl --progress-bar -L -OC0 "$url"
		popd
	fi
}

_extractor() {
	local prefix="$IPKG"
	if ! command -v tar &>/dev/null; then
		error "Cannot find tar"
		eprintf "Please install tar"
		exit 1
	else
		local opt
		opt=$(tar "$@" 2>&1)
		for var in $opt; do
			local filtered=${var//$prefix/}
			filtered=${filtered//"lib64"/"lib"}
			if [[ "$filtered" =~ "x" ]]; then
				continue
			fi
			if [ ! -d "$IPATH/$filtered" ] ; then
				if [[ "$2" =~ "lib" ]] && [[ ! "$IPATH/$filtered" =~ "/lib/" ]]; then
					echo "#$IPATH/lib/$filtered" >>"$IPATH/env"
					local _re_
					[[ "$OS" == "Linux" ]] && _re_='.[0-9]{1,2}.[0-9]{1,2}.[0-9]{1,2}$'
					[[ "$OS" == "Darwin" ]] && _re_='[0-9]{1,2}.[0-9]{1,2}.[0-9]{1,2}.'
					if [[ "$filtered" =~ $_re_ ]]; then
						local _f_ _f2_ _f3_ _f4_
						_f_=${filtered//$_re_/}
						_f2_=${filtered#$_f_}
						_f2_=${BASH_REMATCH[*]}

						IFS=. read -r var1 var2 <<<"$(if [[ "$filtered" =~ $_re_ ]]; then
						echo "${BASH_REMATCH[*]#.}"
						fi)"

						_f3_=${filtered//${_f2_}/}    # e.g., libsome.so.xx.yy.zz --> libsome.so
						[[ "$OS" == "Linux" ]] && _f4_="$_f3_.$var1"   # e.g., libsome.so.xx.yy.zz --> libsome.so.xx
						[[ "$OS" == "Darwin" ]] && _f4_="${filtered//.${_f2_}dylib/}"".$var1.dylib" # e.g., libsome.xx.yy.zz.dylib --> libsome.xx.dylib

						ln -sf "$IPATH/lib/$filtered" "$IPATH/lib/$_f3_"
						echo "#$IPATH/lib/$_f3_" >>"$IPATH/env"

						ln -sf "$IPATH/lib/$filtered" "$IPATH/lib/$_f4_"
						echo "#$IPATH/lib/$_f4_" >>"$IPATH/env"
					fi
				elif [[ "$2" =~ "bin" ]] && [[ ! "$IPATH/$filtered" =~ "/bin/" ]]; then
					echo "#$IPATH/bin/$filtered" >>"$IPATH/env"
				else
					echo "#$IPATH/$filtered" >>"$IPATH/env"
				fi
			fi
		done
	fi
}

get_latest_release() {
	echo "0.14.1"
}

VERSION=$(get_latest_release)

check_os_arch() {
	[ -z "${ARCH}" ] && ARCH=$(uname -m)
	[ -z "${OS}" ] && OS=$(uname)
	RELEASE_PKG="ubuntu20.04_x86_64.tar.gz"
	IPKG="WasmEdge-${VERSION}-${OS}"
	_LD_LIBRARY_PATH_="LD_LIBRARY_PATH"

	case ${OS} in
		'Linux')
			case ${ARCH} in
				'x86_64') ARCH="x86_64";;
				'arm64' | 'armv8*' | 'aarch64') ARCH="aarch64" ;;
				'amd64') ARCH="x86_64" ;;
				*)
					error "Detected ${OS}-${ARCH} - currently unsupported"
					eprintf "Use --os and --arch to specify the OS and ARCH"
					exit 1
					;;
			esac
			if [ "${LEGACY}" == 1 ]; then
				RELEASE_PKG="manylinux2014_${ARCH}.tar.gz"
			else
				RELEASE_PKG="ubuntu20.04_${ARCH}.tar.gz"
			fi
			_LD_LIBRARY_PATH_="LD_LIBRARY_PATH"
			;;
		'Darwin')
			case ${ARCH} in
				'x86_64') ARCH="x86_64" ;;
				'arm64' | 'arm' | 'aarch64') ARCH="arm64" ;;
				*)
					error "Detected ${OS}-${ARCH} - currently unsupported"
					eprintf "Use --os and --arch to specify the OS and ARCH"
					exit 1
					;;
			esac
			RELEASE_PKG="darwin_${ARCH}.tar.gz"
			_LD_LIBRARY_PATH_="DYLD_LIBRARY_PATH"
			;;
		'Windows_NT' | MINGW*)
			error "Detected ${OS} - currently unsupported"
			eprintf "Please download WasmEdge manually from the release page:"
			eprintf "https://github.com/WasmEdge/WasmEdge/releases/latest"
			exit 1
			;;
		*)
			error "Detected ${OS}-${ARCH} - currently unsupported"
			eprintf "Use --os and --arch to specify the OS and ARCH"
			exit 1
			;;
	esac

	info "Detected ${OS}-${ARCH}"
}

# Set installation directory to ~/.wasmedge
IPATH="$__HOME__/.wasmedge"
VERBOSE=1
LEGACY=0
ENABLE_NOAVX=0
GGML_BUILD_NUMBER=""
DISABLE_WASI_LOGGING="0"
BY_PASS_CUDA_VERSION="0"
BY_PASS_CUDART="0"

set_ENV() {
	ENV="#!/bin/sh
# WasmEdge shell setup
# Affix colons on either side of \$PATH to simplify matching
case \":\${PATH}:\" in
	*:\"$1/bin\":*)
		;;
	*)
		if [ -n \"\${PATH}\" ]; then
			export PATH=\"$1/bin\":\${PATH}
		else
			export PATH=\"$1/bin\"
		fi
		;;
esac
case \":\${${_LD_LIBRARY_PATH_}}:\" in
	*:\"$1/lib\":*)
		;;
	*)
		if [ -n \"\${${_LD_LIBRARY_PATH_}}\" ]; then
			export ${_LD_LIBRARY_PATH_}=\"$1/lib\":\${${_LD_LIBRARY_PATH_}}
		else
			export ${_LD_LIBRARY_PATH_}=\"$1/lib\"
		fi
		;;
esac
case \":\${LIBRARY_PATH}:\" in
	*:\"$1/lib\":*)
		;;
	*)
		if [ -n \"\${LIBRARY_PATH}\" ]; then
			export LIBRARY_PATH=\"$1/lib\":\${LIBRARY_PATH}
		else
			export LIBRARY_PATH=\"$1/lib\"
		fi
		;;
esac
case \":\${C_INCLUDE_PATH}:\" in
	*:\"$1/include\":*)
		;;
	*)
		if [ -n \"\${C_INCLUDE_PATH}\" ]; then
			export C_INCLUDE_PATH=\"$1/include\":\${C_INCLUDE_PATH}
		else
			export C_INCLUDE_PATH=\"$1/include\"
		fi
		;;
esac
case \":\${CPLUS_INCLUDE_PATH}:\" in
	*:\"$1/include\":*)
		;;
	*)
		if [ -n \"\${CPLUS_INCLUDE_PATH}\" ]; then
			export CPLUS_INCLUDE_PATH=\"$1/include\":\${CPLUS_INCLUDE_PATH}
		else
			export CPLUS_INCLUDE_PATH=\"$1/include\"
		fi
		;;
esac"
}

usage() {
	cat <<EOF
Usage: $0 -p </path/to/install> [-V]
WasmEdge installation.
Mandatory arguments to long options are mandatory for short options too.
Long options should be assigned with '='

-h,             --help                          Display help

-l,             --legacy                        Enable legacy OS support.
                                        E.g., CentOS 7.

-v,             --version=[0.14.1]              Install the specific version.

-V,             --verbose                       Run script in verbose mode.
                                        Will print out each step
                                        of execution.

-p,             --path=[/usr/local]             Prefix / Path to install

--noavx                                      Install the GGML noavx plugin.
                                        Default is disabled.

-b,             --ggmlbn=[b2963]                Install the specific GGML plugin.
                                        Default is the latest.

-c,             --ggmlcuda=[11/12]              Install the specific CUDA enabled GGML plugin.
                                        Default is none.

-o,             --os=[Linux/Darwin]             Set the OS.
                                        Default is detected OS.

-a,             --arch=[x86_64/aarch64/arm64]   Set the ARCH.
                                        Default is detected ARCH.

-t,             --tmpdir=[/tmp]                 Set the temporary directory.
                                        Default is /tmp.

Example:
./$0 -p \$IPATH --verbose

Or
./$0 --path=/usr/local --verbose

About:

- WasmEdge is the runtime that executes the wasm program or the AOT compiled
  shared library format or universal wasm format programs.

EOF
}

on_exit() {
	cat <<EOF
${RED}
	Troubleshooting:
	1. Please check --help for the correct usage.
	2. Make a trace by re-running the installer with the -V flag if the issue persists.
	3. Submit the reproduction steps and full trace log to the issue tracker:
	   https://github.com/WasmEdge/WasmEdge/issues/new?template=bug_report.yml
${NC}
EOF
}

exit_clean() {
	trap - EXIT
	exit "$1"
}

make_dirs() {
	for var in "$@"; do
		if [ ! -d "$IPATH/$var" ]; then
			mkdir -p "$IPATH/$var"
		fi
	done
}

install() {
	local dir=$1
	shift
	for var in "$@"; do
		if [ "$var" = "lib" ]; then
			if [ -d "$TMP_DIR/$dir/lib64" ]; then
				cp -rf "$TMP_DIR/$dir/lib64/"* "$IPATH/$var"
			else
				cp -rf "$TMP_DIR/$dir/lib/"* "$IPATH/$var"
			fi
		elif [ "$var" = "plugin" ]; then
			if [ -d "$TMP_DIR/$dir/plugin" ]; then
				# Always copy plugins into the local plugin directory
				cp -rf "$TMP_DIR/$dir/plugin/"* "$IPATH/plugin"
			fi
		else
			cp -rf "$TMP_DIR/$dir/$var/"* "$IPATH/$var"
		fi
	done
}

get_wasmedge_release() {
	info "Fetching WasmEdge-$VERSION"
	_downloader "https://github.com/WasmEdge/WasmEdge/releases/download/$VERSION/WasmEdge-$VERSION-$RELEASE_PKG"
	_extractor -C "${TMP_DIR}" -vxzf "$TMP_DIR/WasmEdge-$VERSION-$RELEASE_PKG"
}

get_wasmedge_ggml_plugin() {
	info "Fetching WasmEdge-GGML-Plugin"
	local CUDA_EXT=""
	local NOAVX_EXT=""
	if [ "${ENABLE_NOAVX}" == "1" ]; then
		info "NOAVX option is given: Use the noavx CPU version."
		NOAVX_EXT="-noavx"
	else
		cuda=$(detect_cuda_nvcc)
		cudart=$(detect_libcudart)
		info "Detected CUDA version from nvcc: ${cuda}"
		if [ "${cuda}" == "" ]; then
			info "CUDA version is not detected from nvcc: Use the CPU version."
			info "If you want to install cuda-11 or cuda-12 version manually, you can specify the following options:"
			info "Use options '-c 11' (a.k.a. '--ggmlcuda=11') or '-c 12' (a.k.a. '--ggmlcuda=12')"
			info "Please refer to https://wasmedge.org/docs/contribute/installer_v2/"
		elif [ "${cudart}" == "0" ]; then
			info "libcudart.so is not found in the default installation path of CUDA: Use the CPU version."
			info "If you want to install cuda-11 or cuda-12 version manually, you can specify the following options:"
			info "Use options '-c 11' or '-c 12'"
			info "Please refer to https://wasmedge.org/docs/contribute/installer_v2/"
			cuda=""
		fi

		if [ "${cuda}" == "12" ]; then
			info "CUDA version 12 is detected from nvcc: Use the GPU version."
			CUDA_EXT="-cuda"
		elif [ "${cuda}" == "11" ]; then
			info "CUDA version 11 is detected from nvcc: Use the GPU version."
			CUDA_EXT="-cuda-11"
		else
			CUDA_EXT=""
		fi
	fi

	if [ "$GGML_BUILD_NUMBER" == "" ]; then
		info "Use default GGML plugin"
		_downloader "https://github.com/WasmEdge/WasmEdge/releases/download/$VERSION/WasmEdge-plugin-wasi_nn-ggml${CUDA_EXT}${NOAVX_EXT}-$VERSION-$RELEASE_PKG"
	else
		info "Use ${GGML_BUILD_NUMBER} GGML plugin"
		if [[ "${VERSION}" =~ ^"0.14.1" ]]; then
			_downloader "https://github.com/second-state/WASI-NN-GGML-PLUGIN-REGISTRY/releases/download/${GGML_BUILD_NUMBER}/WasmEdge-plugin-wasi_nn-ggml${CUDA_EXT}${NOAVX_EXT}-$VERSION-$RELEASE_PKG"
		else
			_downloader "https://github.com/second-state/WASI-NN-GGML-PLUGIN-REGISTRY/raw/main/${VERSION}/${GGML_BUILD_NUMBER}/WasmEdge-plugin-wasi_nn-ggml${CUDA_EXT}${NOAVX_EXT}-$VERSION-$RELEASE_PKG"
		fi
	fi

	local TMP_PLUGIN_DIR="${TMP_DIR}/${IPKG}/plugin"
	mkdir -p "${TMP_PLUGIN_DIR}"
	_extractor -C "${TMP_PLUGIN_DIR}" -vxzf "${TMP_DIR}/WasmEdge-plugin-wasi_nn-ggml${CUDA_EXT}${NOAVX_EXT}-$VERSION-$RELEASE_PKG"
}

get_wasmedge_wasi_logging_plugin() {
	info "Fetching WASI-Logging-Plugin"
	_downloader "https://github.com/WasmEdge/WasmEdge/releases/download/$VERSION/WasmEdge-plugin-wasi_logging-$VERSION-$RELEASE_PKG"
	local TMP_PLUGIN_DIR="${TMP_DIR}/${IPKG}/plugin"
	mkdir -p "${TMP_PLUGIN_DIR}"
	_extractor -C "${TMP_PLUGIN_DIR}" -vxzf "${TMP_DIR}/WasmEdge-plugin-wasi_logging-${VERSION}-${RELEASE_PKG}"
}

wasmedge_checks() {
	if [ "${ARCH}" == "$(uname -m)" ] && [ "${OS}" == "$(uname)" ] ; then
		local version=$1
		if [ -f "$IPATH/bin/wasmedge" ]; then
			info "Installation of wasmedge-${version} successful"
		else
			error "WasmEdge-${version} isn't found in the installation folder ${IPATH}"
			exit 1
		fi
	fi
}

main() {
	trap on_exit EXIT

	# Parse command-line options
	local OPTIND
	OPTLIST="e:h:l:v:p:b:c:o:a:t:V-:"
	while getopts $OPTLIST OPT; do
		if [ "$OPT" = "-" ]; then
			OPT="${OPTARG%%=*}"
			OPTARG="${OPTARG#$OPT}"
			OPTARG="${OPTARG#=}"
		fi
		case "$OPT" in
			h | help)
				usage
				trap - EXIT
				exit 0
				;;
			l | legacy)
				LEGACY=1
				;;
			v | version)
				VERSION="${OPTARG}"
				;;
			V | verbose)
				VERBOSE=1
				;;
			p | path)
				IPATH="$(_realpath "${OPTARG}")"
				;;
			b | ggmlbn)
				GGML_BUILD_NUMBER="${OPTARG}"
				;;
			nowasilogging)
				DISABLE_WASI_LOGGING="1"
				;;
			c | ggmlcuda)
				BY_PASS_CUDA_VERSION="${OPTARG}"
				BY_PASS_CUDART="1"
				;;
			noavx)
				ENABLE_NOAVX=1
				;;
			o | os)
				OS="${OPTARG^}"
				;;
			a | arch)
				ARCH="${OPTARG}"
				;;
			t | tmpdir)
				TMP_DIR="${OPTARG}"
				;;
			?)
				exit 2
				;;
			??*)
				error "Illegal option -- ${OPTARG}"
				exit 1
				;;
			*)
				error "Unknown error"
				eprintf "please raise an issue on GitHub with the command you ran."
				exit 1
				;;
		esac
	done

	shift $((OPTIND - 1))

	# Ensure installation and download directories exist;
	# set up logging to both stdout and the log file, and run in verbose mode.
	mkdir -p "$IPATH"
	mkdir -p "$TMP_DIR"
	exec > >(tee -a "$IPATH/install.log") 2>&1
	set -xv

	check_os_arch

	# Run the uninstaller if a previous installation exists.
	if [ -f "$IPATH/bin/wasmedge" ]; then
		bash <(curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/uninstall.sh) -p "$IPATH" -q
	fi

	# Set environment configuration in the oh-my-zsh custom file
	set_ENV "$IPATH"
	OH_MY_ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
	mkdir -p "$OH_MY_ZSH_CUSTOM"
	echo "$ENV" > "$OH_MY_ZSH_CUSTOM/wasmedge.zsh"

	# Ensure the plugin directory exists
	mkdir -p "$IPATH/plugin"

	if [ -d "$IPATH" ]; then
		info "WasmEdge Installation at $IPATH"
		make_dirs "include" "lib" "bin"

		get_wasmedge_release
		get_wasmedge_ggml_plugin
		if [[ "${VERSION}" =~ ^"0.14.1" ]]; then
			# WASI-Logging is bundled from 0.14.1-rc.1 onward.
			DISABLE_WASI_LOGGING="1"
		fi
		if [[ "${DISABLE_WASI_LOGGING}" == "0" ]]; then
			get_wasmedge_wasi_logging_plugin
		fi

		install "$IPKG" "include" "lib" "bin" "plugin"
		wasmedge_checks "$VERSION"
	else
		error "Installation path invalid"
		eprintf "Please provide a valid path"
		exit 1
	fi

	trap - EXIT
	# Note: The cleanup call has been removed so that downloads remain intact.
	end_message
}

end_message() {
	case ":${PATH}:" in
		*:"${IPATH%"/"}/bin":*)
			echo "${GREEN}WasmEdge binaries accessible${NC}"
			;;
		*)
			echo "${GREEN}Run 'source ~/.oh-my-zsh/custom/wasmedge.zsh' to use WasmEdge binaries${NC}"
			;;
	esac
}

main "$@"