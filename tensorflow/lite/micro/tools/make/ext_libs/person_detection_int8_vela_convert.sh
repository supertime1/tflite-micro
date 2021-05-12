#!/bin/bash
# Copyright 2021 The TensorFlow Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ==============================================================================
#
# Called with following arguments:
# 1 - Path to the downloads folder which is typically
#     tensorflow/lite/micro/tools/make/downloads
#
# This script is called from the Makefile and uses the following convention to
# enable determination of sucess/failure:
#
#   - If the script is successful, the only output on stdout should be SUCCESS.
#     The makefile checks for this particular string.
#
#   - Any string on stdout that is not SUCCESS will be shown in the makefile as
#     the cause for the script to have failed.
#
#   - Any other informational prints should be on stderr.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR=${SCRIPT_DIR}/../../../../../..
cd "${ROOT_DIR}"

source tensorflow/lite/micro/tools/make/bash_helpers.sh

DOWNLOADS_DIR=${1}
if [ ! -d ${DOWNLOADS_DIR} ]; then
  echo "The top-level downloads directory: ${DOWNLOADS_DIR} does not exist."
  exit 1
fi

DOWNLOADED_PERSON_MODEL_INT8_PATH=${DOWNLOADS_DIR}/person_model_int8
if [ ! -d ${DOWNLOADED_PERSON_MODEL_INT8_PATH} ]; then
  echo "${DOWNLOADED_PERSON_MODEL_INT8_PATH} is not downloaded."
  exit 1
fi

# Optimize downloaded model with Vela for Ethos-U.
# See tensorflow/lite/micro/kernels/ethos_u/README.md for more info.
CONVERTED_PERSON_MODEL_INT8=${DOWNLOADED_PERSON_MODEL_INT8_PATH}/person_detect_model_data_vela.cc
if [ ! -f ${CONVERTED_PERSON_MODEL_INT8} ]; then
  command xxd -v >&2 || (echo "xxd command is needed, please install.." && exit 1)
  echo >&2 "Converting person detection int8 model to Ethos-U optimized model.."

  # Convert original model to .tflite format.
  grep -E "(0x[0-9a-f]{2}(,|))" ${DOWNLOADED_PERSON_MODEL_INT8_PATH}/person_detect_model_data.cc | xxd -r -p > \
      ${DOWNLOADED_PERSON_MODEL_INT8_PATH}/person_detect.tflite

  # Compile an optimized .tflite version for Ethos-U.
  TEMPFILE=$(mktemp -d)/
  python3 -m venv $TEMPFILE
  source $TEMPFILE/bin/activate
  pip install --upgrade setuptools >&2
  pip install ethos-u-vela >&2
  vela --accelerator-config=ethos-u55-256 ${DOWNLOADED_PERSON_MODEL_INT8_PATH}/person_detect.tflite \
       --output-dir ${DOWNLOADED_PERSON_MODEL_INT8_PATH} >&2
  deactivate

  # Convert .tflite back to C array.
  echo "// This file is generated by $0." > ${CONVERTED_PERSON_MODEL_INT8}
  echo '#include "tensorflow/lite/micro/examples/person_detection/person_detect_model_data.h"' >> \
       ${CONVERTED_PERSON_MODEL_INT8}
  echo -n "const " >> ${CONVERTED_PERSON_MODEL_INT8}
  xxd -i ${DOWNLOADED_PERSON_MODEL_INT8_PATH}/person_detect_vela.tflite >> \
      ${CONVERTED_PERSON_MODEL_INT8}
  sed -i 's/tensorflow_lite_micro_tools_make_downloads_person_model_int8_person_detect_vela_tflite/g_person_detect_model_data/' \
      ${CONVERTED_PERSON_MODEL_INT8}
  sed -i 's/^const unsigned char g_person_detect_model_data/alignas\(16\) &/'  ${CONVERTED_PERSON_MODEL_INT8}
  sed -i 's/unsigned int/const int/' ${CONVERTED_PERSON_MODEL_INT8}
fi

echo "SUCCESS"