#!/bin/bash

# get the path to the bash script itself
# - https://stackoverflow.com/questions/59895/how-can-i-get-the-source-directory-of-a-bash-script-from-within-the-script-itsel
SOURCE=${BASH_SOURCE[0]}
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SOURCE_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
SOURCE_NAME=track-products-arkhavencomics

source "${SOURCE_DIR}/common.sh"

set -e -o pipefail




# load script config data
SCRIPT_CONFIG_FILEPATH="${SOURCE_DIR}/../config/config.yml"
load-script-config "${SCRIPT_CONFIG_FILEPATH}"                          "SCRIPT_CONFIG_CONTENT"
load-logging-level "$SCRIPT_CONFIG_CONTENT"                             "SCRIPT_LOGGING_LEVEL"
load-logging-filepath "$SCRIPT_CONFIG_CONTENT" "$SCRIPT_LOGGING_LEVEL"  "SCRIPT_LOGGING_FILEPATH"

log-info "loading config from $SCRIPT_CONFIG_FILEPATH" # unable to use log-* functions until setting loaded...
log-info "logging level: $SCRIPT_LOGGING_LEVEL"

# load previously obtained product data
get-products-path "$SCRIPT_CONFIG_CONTENT" "SCRIPT_PRODUCTS_FILEPATH"
load-product-details "$SCRIPT_PRODUCTS_FILEPATH" "SCRIPT_LOADED_PRODUCT_DETAILS" || true
  # verify data structure



SCRIPT_ALERTS_SUPPRESSED_OVERRIDE='true'   # whether to override alert suppression. alerts can be suppressed if the script is run for the first time. true means ignore suppression, so send the alerts anyways.
SCRIPT_LATEST_PRODUCT_DETAILS_TMP_FILEPATH="/tmp/${SOURCE_NAME}-$(generate-uuid)"  # temporary details storage path
SCRIPT_LATEST_PRODUCT_CHANGES_TMP_FILEPATH="/tmp/${SOURCE_NAME}-$(generate-uuid)"
SCRIPT_FAILED_SLACK_ALERTS_TMP_FILEPATH="/tmp/${SOURCE_NAME}-failed-slack-alerts-$(generate-uuid)"

# main script
parse-productcategory-into-url "$SCRIPT_CONFIG_CONTENT" \
| retrieve-latest-product-list \
| retrieve-latest-product-details \
| store-latest-product-details \
| compare-product-fields \
| alert-product-changes \
|| log-error "${SOURCE_NAME}-main: pipeline returned failed..."


#| store-latest-product-changes \
####  && echo $? || echo $?



# write the latest products to file
export-product-details "$SCRIPT_PRODUCTS_FILEPATH" "$( cat "$SCRIPT_LATEST_PRODUCT_DETAILS_TMP_FILEPATH" 2>/dev/null )"
# remove temp product details, which are latest details
rm -f "$SCRIPT_LATEST_PRODUCT_DETAILS_TMP_FILEPATH" || true


# error trapping & handling
# output status to logs

