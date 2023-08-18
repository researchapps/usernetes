#!/bin/bash
export U7S_BASE_DIR=$(realpath $(dirname $0)/..)
source $U7S_BASE_DIR/common/common.inc.sh
nsenter::main $0 $@
echo "The nsenter user is $(whoami)"
echo "The command is $@"

if [[ $# -eq 0 ]]; then
	exec $SHELL $@
else
	exec $@
fi
