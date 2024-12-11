#!/bin/bash

# some variables to influence the behaviour of this script
MAKE_JOBS="-j12" # probably enough, I havent seen make use this many even if allowed to
CMAKE="/usr/bin/cmake"
MAKE="make"

# default options
CLEAN_SIM_DIRECTORY=0;
MAKE_SIM=0;
MAKE_BIT=0;
SKIP_PROJ=1;
NOGUI=0;

# options
OPTIONS=(
		"h,help,,Print help message and exit"
		"c,clean,,Clean the sim directory"
		"s,sim,,create the simulation project"
		"b,bitgen,,generate bitstream"
		"p,proj,,do not skip project generation"
		",nogui,,do not attempt to open vivado"
	)
LENGTHS=( 0 0 0 )
SHORT_OPTIONS=""
LONG_OPTIONS=""
for LINE in "${OPTIONS[@]}"; do
	ARR=( $(echo "$LINE" | awk -F ',' '{print "<"$1"> <"$2"> <"$3">" }') );
		CLENS=( "${#ARR[0]}" "${#ARR[1]}" "${#ARR[2]}" );
	if [[ "${LENGTHS[0]}" -lt "${CLENS[0]}" ]]; then
		LENGTHS[0]="${CLENS[0]}"
	fi
	if [[ "${LENGTHS[1]}" -lt "${CLENS[1]}" ]]; then
		LENGTHS[1]="${CLENS[1]}"
	fi
	if [[ "${LENGTHS[2]}" -lt "${CLENS[2]}" ]]; then
		LENGTHS[2]="${CLENS[2]}"
	fi
	OPT_SHORT=$(echo "$LINE" | cut -f 1 -d ',')
	OPT_LONG=$(echo "$LINE" | cut -f 2 -d ',')
	OPT_ARG=$(if ! [[ "${ARR[2]}" = "<>" ]]; then echo ":"; fi)
	
	SHORT_OPTIONS=$SHORT_OPTIONS$OPT_SHORT$OPT_ARG
	LONG_OPTIONS=${LONG_OPTIONS:+$LONG_OPTIONS,}$OPT_LONG$OPT_ARG
	
done

function usage() {
	echo "Usage:"
	echo "  ./build.sh [options...]"
	echo ""
	echo "Options:"
	for OPT_STRING_ENTRY in "${OPTIONS[@]}"; do
		SHORT_OPT=$(echo "$OPT_STRING_ENTRY" | awk -F ',' '{print $1}');
		LONG_OPT=$(echo "$OPT_STRING_ENTRY" | awk -F ',' '{print $2}');
		ARG=$(echo "$OPT_STRING_ENTRY" | awk -F ',' '{ print "<"$3">" }');
		DESC=$(echo "$OPT_STRING_ENTRY" | cut -f 4- -d ',');
		ARG=$(if [[ "$ARG" = "<>" ]]; then echo ""; else echo "$ARG"; fi);
		FORMAT_STRING="  -%s %s, --%s %s %$((("${LENGTHS[1]}"+"${LENGTHS[2]}"+"${LENGTHS[2]}"-"${#ARG}"-"${#ARG}"-"${#LONG_OPT}")))s %s\n"
		printf "$FORMAT_STRING" "$SHORT_OPT" "$ARG" "$LONG_OPT" "$ARG" "" "$DESC"
	done
}

function parse_args() {
	# parse commandline options
	OLD_OPTS=("$@")
	SCREEN_OPTS=( )
	eval set -- "$(getopt -l $LONG_OPTIONS -o $SHORT_OPTIONS -a -- "$@")"
	while true; do
		case "$1" in
			-h|--help) shift; usage; exit 0;;
			-c|--clean) CLEAN_SIM_DIRECTORY=1; shift;;
			-s|--sim) MAKE_SIM=1; shift;;
			-p|--proj) SKIP_PROJ=0; shift;;
			-b|--bitgen) MAKE_BIT=1; shift;;
			--nogui) NOGUI=1; shift;;
			--) shift; break;;
			
			*) echo "Unimplemented Option: '$1'"; exit 1;;
		esac
	done
	
	# remove --background or -B options along with their arguments
	function aux() {
		while [[ $# -gt 0 ]]; do
			if [[ "$1" = "-b" ]] || [[ "$1" = "--background" ]]; then
				shift;
				if ! [[ "$1" = "-"* ]]; then
					shift;
				fi
			else
				SCREEN_OPTS=(${SCREEN_OPTS[0]+"${SCREEN_OPTS[@]}"} "$1");
				shift;
			fi
		done
	}
	
	aux "${OLD_OPTS[@]}";
}

function create_log_file() {
	LOG_FILE="$ABS_PATH/build-log-$1-$(date +%Y-%m-%d_%H:%M:%S).log"
	touch "$LOG_FILE"
}

function clean_build() {
	# Clean the build directory
	rm -rf "$ABS_PATH"/build_bit;
}

function clean_sim() {
	# Clean the sim directory
	rm -rf "$ABS_PATH"/build_sim;
}

function patch_submodules() {
	# patch files in the submodule repository that cannot be commited there
	# NOTE: this should run top level in the project repository
	for FILE in $(find "$ABS_PATH/patches" -type f -printf "%P "); do
		echo "Patching: $FILE..."
		cp "$ABS_PATH/patches/$FILE" "$ABS_PATH/$FILE"
	done
}

function make_sim() {
	# first create and change to sim directory
	echo "Creating sim directory..."
    if [[ ! -d "$ABS_PATH/build_sim" ]] || [[ -z $(ls "$ABS_PATH/build_sim") ]]; then
        BUILD_DIR_EMPTY=1
    fi
	mkdir -p "$ABS_PATH/build_sim";
	cd "$ABS_PATH/build_sim";
    
    # patch submodule
    patch_submodules;
    
    # running cmake
    if [[ "$CLEAN_SIM_DIRECTORY" -eq 1 ]] || [[ "$BUILD_DIR_EMPTY" ]]; then
        "$CMAKE" "$ABS_PATH/examples_hw" "-DEXAMPLE=arrow" >> "$LOG_FILE" 2>&1
        "$MAKE" "$MAKE_JOBS" project >> "$LOG_FILE" 2>&1
    fi
	
	# creating simulation
	echo "Running make sim..."
	"$MAKE" "$MAKE_JOBS" sim >> "$LOG_FILE" 2>&1
	
	# patch simulation project
	echo "Patching simulation project"
	vivado -mode tcl sim/test.xpr < "$ABS_PATH/scripts/sim-patch.tcl" >> "$LOG_FILE" 2>&1
	
	if [[ "$NOGUI" -eq 0 ]]; then
		# open vivado
		echo "Opening Vivado..."
		vivado "$ABS_PATH/build_sim/sim/test.xpr" >> "$LOG_FILE" 2>&1
    else
        echo "Skipping Vivado..."
	fi
}

function make_bitstream() {
	# create and change to the build directory
	echo "Creating build_bit directory..."
	mkdir -p "$ABS_PATH/build_bit"
	cd "$ABS_PATH/build_bit"
	
	if [[ "$SKIP_PROJ" -eq 0 ]]; then
		# generate project
		echo "Patching submodule..."
		patch_submodules;
		echo "Running cmake..."
		"$CMAKE" "$ABS_PATH/Coyote/examples_hw" "-DEXAMPLE=arrow" >> "$LOG_FILE" 2>&1
		echo "Running make project..."
		"$MAKE" "$MAKE_JOBS" project >> "$LOG_FILE" 2>&1
	fi
	
	# patching ip instances
	echo "Instantiating IP uses..."
	vivado -mode tcl "test_shell/test.xpr" < "$ABS_PATH/scripts/init_ip_shell.tcl" >> "$LOG_FILE" 2>&1
	
	# run bitgen
	"$MAKE" "$MAKE_JOBS" bitgen >> "$LOG_FILE" 2>&1
}

function main() {
	# parse arguments (note that this will already invoke the screen if necessary)
	# all following code will run in the screen if that is wanted by the user
	echo "Starting build script...";
	parse_args "$@";
	echo "Arguments parsed.";
	
	# Recover the absolute path of the repository, resolving symlinks
	ABS_PATH="$(realpath $(dirname "$0"))";

	# goto repository directory along the canonical path
	cd "$ABS_PATH";
	
	# Clean the sim directory if requested
	if [[ "$CLEAN_SIM_DIRECTORY" -eq 1 ]]; then
		echo "Cleaning sim directory..."
		clean_sim;
	fi
	
	# run project setup and make sim if requested
	if [[ "$MAKE_SIM" -eq 1 ]]; then
		# create and name log file for sim build
		create_log_file "sim";
		
		make_sim;
	fi
	
	# run project setup and make bitgen if requested
	if [[ "$MAKE_BIT" -eq 1 ]]; then
		# create and name log file for bitstream build
		create_log_file "bit";
		
		make_bitstream;
	fi
}


main "$@";
