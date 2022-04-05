#!/bin/bash

timestamp () {
    echo "$(date --utc +"%D %T") | $*"
}
function set-env-var {
    local ENV_VAR=$1
    local DEFAULT_VAL=$2
    if [[ -z "${DEFAULT_VAL}" ]]; then
        timestamp "ERROR: DEFAULT_VAL was not passed"
        exit 1
    fi
    if [[ -z "${!ENV_VAR}" ]]; then
        eval "${ENV_VAR}=\"$(echo \${DEFAULT_VAL})\""
    fi
}
function generate-uuid {
  cat /proc/sys/kernel/random/uuid || (log-error "Unable to generate UUID!" && exit 1)
}
function remove-empty-lines {
  if (( $# == 0 )) ; then
    grep -v -e '^[[:space:]]*$' < /dev/stdin
  else
    grep -v -e '^[[:space:]]*$' <<< "$@"
  fi
}
function remove-preceding-whitespace {
  if (( $# == 0 )) ; then
    awk '{$1=$1;print}' < /dev/stdin
  else
    awk '{$1=$1;print}' <<< "$@"
  fi
}
function remove-trailing-forwardslash {
  if (( $# == 0 )) ; then
    sed 's:/*$::' < /dev/stdin
  else
    sed 's:/*$::' <<< "$@"
  fi
}
function remove-html-tags {
  if (( $# == 0 )) ; then
    sed -r 's/<[^>]*>//g' < /dev/stdin
  else
    sed -r 's/<[^>]*>//g' <<< "$@"
  fi
}
function convert-html-entities {
  local sed_command='s/&nbsp;/ /g; s/&amp;/\&/g; s/&#36;/\$/g; s/&lt;/\</g; s/&gt;/\>/g; s/&quot;/\"/g; s/#&#39;/\'"'"'/g; s/&#8217;/\'"'"'/g; s/&ldquo;/\"/g; s/&rdquo;/\"/g;'
  if (( $# == 0 )) ; then
    sed "$sed_command" < /dev/stdin
  else
    sed "$sed_command" <<< "$@"
  fi
}
function print-array-newlines {
  local array_name=${1:?}
  eval 'printf "%s\n"' \""\${${array_name}[@]}\""
}

# loads config
function load-script-config {
  local filepath=${1:?}
  local varname=${2:?}
  unset "$varname"
  set-env-var "$varname" "$( cat "$filepath" || exit 1)"
}
function load-logging-level {
  local content=${1:?}
  local varname=${2:?}
  local log_level="$( echo "$content" | yq -rc '.logging.level' || exit 1)"
  unset "$varname"
  set-env-var "$varname" "${log_level}"
}
function load-logging-filepath {
  local content=${1:?}
  local level=${2:?}
  local varname=${3:?}
  unset "$varname"
  set-env-var "$varname" "${SOURCE_DIR}/$( echo "$content" | yq -rc ".logging.${level}.path" || exit 1)"
}
function set-suppress-alerts {
  # set-suppress-alerts "true"
  local content=${1:?}
  unset "SCRIPT_ALERTS_SUPPRESSED"
  set-env-var "SCRIPT_ALERTS_SUPPRESSED" "$content"
}
function get-suppress-alerts {
  # echo "$(get-suppress-alerts)"
  #  > true
  echo "$SCRIPT_ALERTS_SUPPRESSED"
}

function format-error {
  if (( $# == 0 )) ; then
    tr "\n" ' '         < /dev/stdin  | tr "\r" ' ' | head -c300
  else
    tr "\n" ' '         <<< "$@"      | tr "\r" ' ' | head -c300
  fi
}
function log-error {
  case $SCRIPT_LOGGING_LEVEL in
    error | warn | info | debug)
      timestamp "error: $*" >> "$SCRIPT_LOGGING_FILEPATH"
      ;;
    *)
      ;;
  esac
}
function log-warn {
  case $SCRIPT_LOGGING_LEVEL in
    warn | info | debug)
      timestamp "warn: $*" >> "$SCRIPT_LOGGING_FILEPATH"
      ;;
    *)
      ;;
  esac
}
function log-info {
  case $SCRIPT_LOGGING_LEVEL in
    info | debug)
      timestamp "info: $*" >> "$SCRIPT_LOGGING_FILEPATH"
      ;;
    *)
      ;;
  esac
}
function log-debug {
  case $SCRIPT_LOGGING_LEVEL in
    debug)
      timestamp "debug: $*" >> "$SCRIPT_LOGGING_FILEPATH"
      ;;
    *)
      ;;
  esac
}

function get-products-path {
  local content=${1:?}
  local varname=${2:?}
  log-info "getting products filepath from config"
  unset "$varname"
  set-env-var "$varname" "${SOURCE_DIR}/$( echo "$content" | yq -rc ".products.path" || log-error "Unable to get products data filepath from config." && exit 1)"
}

# loads previously obtained books details from file
function load-product-details {
  local filepath=${1:?}
  local varname=${2:?}
  local failed=0
  log-info "loading products data from file '$filepath'"
  local alerts_suppressed_filepath="/tmp/${SOURCE_NAME}-$(generate-uuid)"
  if [[ ! -f "$filepath" ]]; then
    touch "$filepath"
  fi 
  local product_details="$( yq -rc '.' -- "$filepath" \
    || ( log-warn "Unable load products from file '$filepath'. Alerts suppressed until baseline estabilished - normally next invocation/script execution." \
    && echo 'true' > "$alerts_suppressed_filepath" ) )"
  if [[ -f "$alerts_suppressed_filepath" ]]; then
    set-suppress-alerts "true"
    rm -f "$alerts_suppressed_filepath"
  else
    set-suppress-alerts "false"
  fi
  if [[ -z $product_details ]]; then
    log-warn "Products file appears empty '$filepath'"
    set-suppress-alerts "true"
    return 1
  fi
  unset "$varname"
  set-env-var "$varname" "$product_details"
}

# parses the product category into list of urls
function parse-productcategory-into-url {
  # local content=${1:?}
  # local varname=${2:?}
  # add default settings to all category items
  log-info "parsing products categories into list of urls"
  local categories="$( echo "$SCRIPT_CONFIG_CONTENT" | yq -rc '.productCategories.default_settings as $default | .productCategories.items[] | $default + . | select(. != null)' )"
  local urls=()
  while read -r category; do
    # set variable key=value for the current category
    for keyval in $(echo "$category" | jq -rc '. | to_entries|map("\(.key)=\(.value|tostring)") | .[]'); do eval $keyval; done
    # use the set variables to perform replacements to the url property with data from other properties
    urls+=( "$( eval echo "$(echo "$category" | jq -rc '.url')" )" )
    # unset all the set variables
    for keyval in $(echo "$category" | jq -rc '. | to_entries|map("\(.key)") | .[]'); do eval unset $keyval; done
  done < <( echo "$categories" )
  print-array-newlines "urls"
}

# fetches all from product list from website
function retrieve-latest-product-list {
  local i=0
  if (( $# == 0 )) ; then
    local stdin="$( cat < /dev/stdin )"
    local count="$( wc -l <<< "$stdin" )"
    while read -r url; do
      local html_raw="$(retrieve-single-product-list "$url" "$i" "$count")"
      [[ -n "$html_raw" ]] && parse-raw-product-list-urls "${html_raw}"
      i=$((i+1))
    done   <<< "$stdin"  \
      | remove-empty-lines | sort -u | uniq
  else
    local count="$( wc -l <<< "$@" )"
    while read -r url; do
      local html_raw="$(retrieve-single-product-list "$url" "$i" "$count")"
      [[ -n "$html_raw" ]] && parse-raw-product-list-urls "${html_raw}"
      i=$((i+1))
    done   <<< "$@"      \
      | remove-empty-lines | sort -u | uniq
  fi
}

# fetches single product list from website
function retrieve-single-product-list {
  local reqURL=${1:?}
  local current_index=${2}
  local max_indices=${3}
  local REQ_METHOD="GET"
  local RES_BODY=''
  local RES_CODE=0
  local RET=''
  log-info "retrieving product list[${current_index}/${max_indices}]: curl '$REQ_METHOD' on '$reqURL'"
  local curl_stderror_filepath="/tmp/${SOURCE_NAME}-retrieve-single-product-list-$(generate-uuid)"
  local RES="$( \
  curl -qSsw '\n%{http_code}' "$reqURL" \
    -X "$REQ_METHOD" \
    -H 'Connection: keep-alive' \
    -H 'Accept: text/html, */*; q=0.01' \
    -H 'sec-ch-ua-mobile: ?0' \
    -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.51 Safari/537.36' \
    -H 'sec-ch-ua: " Not A;Brand";v="99", "Chromium";v="99", "Google Chrome";v="99"' \
    -H 'sec-ch-ua-platform: "Windows"' \
    -H 'Sec-Fetch-Site: same-origin' \
    -H 'Sec-Fetch-Mode: cors' \
    -H 'Sec-Fetch-Dest: empty' \
    -H 'Accept-Language: en-US,en;q=0.9' \
    -H 'sec-gpc: 1' \
    --compressed \
    2>>"$curl_stderror_filepath" \
  )"
  if [[ -f "$curl_stderror_filepath" ]]; then
    local curl_error="$( cat "$curl_stderror_filepath" )"
    rm -f "$curl_stderror_filepath" || :
  fi
  if [[ -n "$curl_error" ]]; then
    log-error "curl-stderror: $( format-error "$curl_error" )"
  fi
  RET=$? && RES_BODY="$(echo "$RES" | grep -vE '^[0-9][0-9][0-9]$')" && RES_CODE="$(echo "$RES" | grep -E '^[0-9][0-9][0-9]$' | tail -1 |rev| cut -d$'\n' -f1 |rev)"
  if [[ -n "$( echo "${RES_CODE}" | grep -e '2[0-9][0-9]' )" ]]; then
    if [[ -z "$RES_BODY" ]]; then
      log-warn "curl '$REQ_METHOD' on '$reqURL' returned empty body!"
    else
      echo "$RES_BODY"
      return 0
    fi
  else
    log-warn "server returned http_code: $RES_CODE http_body: '$( format-error "$RES_BODY" )'"
    return 1
  fi
}

# parses the product list raw html into a list of urls
function parse-raw-product-list-urls {
  local html=${1:?}
  # get all products' url
  log-debug "extracting products urls from html list page"
  local urls="$( echo "$html" | grep -o -P '(?<=class="product-loop-title")[\S\s]*?href=".*?">' | remove-empty-lines | grep -o -P '(?<=href=").*?(?=">)' )"
  if [[ -z "$urls" ]]; then
    log-warn "failed to parse product page urls from product list page."
  else
    echo "$urls"
  fi
}

# fetches all product's details from url list
function retrieve-latest-product-details {
  local i=0
  if (( $# == 0 )) ; then
    local stdin="$( cat < /dev/stdin )"
    local count="$( wc -l <<< "$stdin" )"
    log-info "retrieving latest product details from store"
    while read -r url; do
      if [[ -n "$url" ]]; then
        local html_raw="$(retrieve-single-product-details "$url" "$i" "$count")"
      fi
      [[ -n "$html_raw" ]] && extract-product-details "${html_raw}" "$url"
      i=$((i+1))
    done   <<< "$stdin"
  else
    local count="$( wc -l <<< "$@" )"
    while read -r url; do
      if [[ -n "$url" ]]; then
        local html_raw="$(retrieve-single-product-details "$url" "$i" "$count")"
      fi
      [[ -n "$html_raw" ]] && extract-product-details "${html_raw}" "$url"
      i=$((i+1))
    done   <<< "$@"
  fi
}

# fetches a single product's details from website
function retrieve-single-product-details {
  local reqURL=${1:?}
  local current_index=${2}
  local max_indices=${3}
  local REQ_METHOD="GET"
  local RES_BODY=''
  local RES_CODE=0
  local RET=''
  log-info "fetching product details[${current_index}/${max_indices}]: curl '$REQ_METHOD' on '$reqURL'"
  local curl_stderror_filepath="/tmp/${SOURCE_NAME}-retrieve-single-product-details-$(generate-uuid)"
  local RES="$( \
  curl -qSsw '\n%{http_code}' "$reqURL" \
    -X "$REQ_METHOD" \
    -H 'Connection: keep-alive' \
    -H 'Accept: text/html, */*; q=0.01' \
    -H 'sec-ch-ua-mobile: ?0' \
    -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.51 Safari/537.36' \
    -H 'sec-ch-ua: " Not A;Brand";v="99", "Chromium";v="99", "Google Chrome";v="99"' \
    -H 'sec-ch-ua-platform: "Windows"' \
    -H 'Sec-Fetch-Site: same-origin' \
    -H 'Sec-Fetch-Mode: cors' \
    -H 'Sec-Fetch-Dest: empty' \
    -H 'Accept-Language: en-US,en;q=0.9' \
    -H 'sec-gpc: 1' \
    --compressed \
    2>>"$SCRIPT_LOGGING_FILEPATH" \
  )"
  if [[ -f "$curl_stderror_filepath" ]]; then
    local curl_error="$( cat "$curl_stderror_filepath" )"
    rm -f "$curl_stderror_filepath" || :
  fi
  if [[ -n "$curl_error" ]]; then
    log-error "curl-stderror: $( format-error "$curl_error" )"
  fi
  RET=$? && RES_BODY="$(echo "$RES" | grep -vE '^[0-9][0-9][0-9]$')" && RES_CODE="$(echo "$RES" | grep -E '^[0-9][0-9][0-9]$' | tail -1 |rev| cut -d$'\n' -f1 |rev)"
  if [[ -n "$( echo "${RES_CODE}" | grep -e '2[0-9][0-9]' )" ]]; then
    if [[ -z "$RES_BODY" ]]; then
      log-warn "curl '$REQ_METHOD' on '$reqURL' returned empty body!"
    else
      echo "$RES_BODY"
      return 0
    fi
  else
    log-warn "server returned http_code: $RES_CODE http_body: '$( format-error "$RES_BODY" )'"
    return 1
  fi
}

# save latest product defailt to temp file as nsjson
function store-latest-product-details {
  if (( $# == 0 )) ; then
    cat < /dev/stdin  | tee -a "${SCRIPT_LATEST_PRODUCT_DETAILS_TMP_FILEPATH}"
    log-info "storing latest product details to temp file '$SCRIPT_LATEST_PRODUCT_DETAILS_TMP_FILEPATH'"
  else
    cat <<< "$@"      | tee -a "${SCRIPT_LATEST_PRODUCT_DETAILS_TMP_FILEPATH}"
  fi
}
function store-latest-product-changes {
  if (( $# == 0 )) ; then
    cat < /dev/stdin  | tee -a "${SCRIPT_LATEST_PRODUCT_CHANGES_TMP_FILEPATH}"
    log-info "storing latest product changes to temp file '$SCRIPT_LATEST_PRODUCT_CHANGES_TMP_FILEPATH'"
  else
    cat <<< "$@"      | tee -a "${SCRIPT_LATEST_PRODUCT_CHANGES_TMP_FILEPATH}"
  fi
}

# extract out the 
function extract-product-details {
  local html=${1:?}
  local url=$( echo "${2:?}" | remove-trailing-forwardslash )
  log-debug "extract-product-details: extracting product details from raw html on page '$url'"
  # product id
  local id="$( echo "$html" | grep -Po '<link rel=['\''"]shortlink['\''"][\S\s]*?\/>' | grep -Po '(?<=href=['\''"]).*?(?=['\''"])' |rev|cut -d '/' -f 1|rev| grep -Po '(?<=[Pp]=).*?(?=&)|(?<=[Pp]=).*?$' | remove-empty-lines | remove-preceding-whitespace )"
    # local id="$( echo "$html" | grep -Pzo '<form class="cart"[\S\s]*?>[\S\s]*?<\/form>' | grep -Pao '<button[\S\s]*?>[\S\s]*?</button>' | grep -Po '(?<=value=").*?(?=")' | remove-empty-lines | remove-preceding-whitespace )"  # alt way to get id
  #   *
      # <form class="cart" action="https://arkhavencomics.com/product/brings-the-lightning-audiobook/" method="post" enctype='multipart/form-data'><div class="quantity"> <input
      # type="number"
      # id="quantity_6237615d90341"
      # class="input-text qty text"
      # step="1"
      # min="1"
      # max=""
      # name="quantity"
      # value="1"
      # title="Qty"
      # size="4"
      # placeholder=""                 inputmode="numeric" /></div> <button type="submit" name="add-to-cart" value="3443" class="single_add_to_cart_button button alt">Add to cart</button> <a href="https://arkhavencomics.com/cart/" tabindex="1" class="wc-action-btn view-cart-btn button wc-forward">View cart</a></form>
        
  # product title
  local title="$( echo "$html" | grep -o -P '(?<=<h2 class="product_title entry-title show-product-nav">).*?(?=</h2>)' | remove-empty-lines | convert-html-entities | remove-preceding-whitespace )"
  #   *  <h2 class="product_title entry-title show-product-nav"> A Throne of Bones Vol. I Libraria edition</h2>
  # product imageUrl
  local imageUrl="$( echo "$html" | grep -o -P '<div class="img-thumbnail">.*?<\/div>' | grep -o -P '(?<=src=").*?(?=")' | remove-empty-lines | remove-preceding-whitespace | remove-trailing-forwardslash )"
  #   * 
      # <div class="img-thumbnail">
      #   <div class="inner"><img width="600" height="960"
      #       src="https://arkhavencomics.com/wp-content/uploads/2022/01/ATOB1.jpg"
      #       class="woocommerce-main-image img-responsive" alt="" loading="lazy"
      #       href="https://arkhavencomics.com/wp-content/uploads/2022/01/ATOB1.jpg" title="ATOB1"
      #       srcset="https://arkhavencomics.com/wp-content/uploads/2022/01/ATOB1.jpg 600w, https://arkhavencomics.com/wp-content/uploads/2022/01/ATOB1-400x640.jpg 400w, https://arkhavencomics.com/wp-content/uploads/2022/01/ATOB1-367x587.jpg 367w, https://arkhavencomics.com/wp-content/uploads/2022/01/ATOB1-500x800.jpg 500w"
      #       sizes="(max-width: 600px) 100vw, 600px" /></div>
      # </div>

  # product description
  local description="$( echo "$html" | grep -o -P '<div class="resp-tabs-container">.*?<\/div>' | remove-empty-lines | remove-preceding-whitespace | pandoc -f html -t markdown_mmd )"
  #   *  <div class="tab-content resp-tab-content resp-tab-content-active" id="tab-description" aria-labelledby="tab_item-0" style="display: block;"><h2>Description</h2><p>This is to join the Castalia Library Book Club and receive a deluxe leatherbound book published by Castalia House every other month. Subscribers receive a $50 discount on the retail price of $150.</p><p><em><strong>FEATURES</strong></em></p><ul><li>Genuine leather bindings</li><li>Gilded cover and spine titling</li><li>Gilded page edges</li><li>Genuine offset printing</li><li>Original interior layouts and artwork.</li><li>Archival-quality paper</li><li>First-rate fiction</li><li>Timeless classics of history, science, and philosophy</li></ul><p>The current Library Book Club book (January-February, #14) is <i>The Jungle Books</i> by Rudyard Kipling. No <a href="https://arkhavencomics.com/product/castalia-library-catchup/">catchup payment</a> is necessary for new Library subscriptions started in January 2022.</p><p><em><strong>CASTALIA LIBRARY SERIES</strong></em></p><ol><li><em>The Missionaries</em> by Owen Stanley, limited edition of 500</li><li><em>The Meditations</em> by Marcus Aurelius, limited edition of 650</li><li><em>Awake in the Night Land</em> by John C. Wright, limited edition of 650</li><li><em>The Divine Comedy</em> by Dante Alighieri, limited edition of 750</li><li><em>Lives, Vol. I</em> by Plutarch, limited edition of 750</li><li><em>Lives, Vol. II</em> by Plutarch, limited edition of 750</li><li><em>Summa Elvetica</em> by Vox Day, (signed edition) limited edition of 750</li><li><em>Heidi</em> by Johanna Spryi, limited edition of 750</li><li><i>Rhetoric </i>by Aristotle, limited edition of 750</li><li><i>Discourses on Livy</i> by Niccolo Machiavelli, limited edition of 850</li><li><i>A Throne of Bones Vol. I</i> by Vox Day, limited edition of 850</li><li><i>A Throne of Bones Vol. II</i> by Vox Day, limited edition of 850</li><li><i>Ethics</i> by Aristotle, limited edition of 750</li><li><i>The Jungle Books</i> by Rudyard Kipling, limited edition of 750</li></ol><p>Castalia Library subscribers are given the first opportunity to purchase the remaining copies at the subscription price, and also receive a discounted price on non-subscription limited editions. Castalia reserves the right to not provide discounts on additional books to subscribers who subscribe for a period of less than 12 months.</p><p>&nbsp;</p></div>
  # product price
  local price="$( echo "$html" | grep -o -P '<p class="price">[\S\s]*?<span class="woocommerce-Price-amount amount">[\S\s]*?class="woocommerce-Price-currencySymbol">[\S\s]*?<\/p>' \
    | sed 's|<del.*</del>||' | remove-empty-lines | remove-html-tags | convert-html-entities | remove-preceding-whitespace  )"
  #   * <p class="price"><span class="woocommerce-Price-amount amount"><bdi><span class="woocommerce-Price-currencySymbol">$</span>500.00</bdi>
  #   * <p class="price"><del aria-hidden="true"><span class="woocommerce-Price-amount amount"><bdi><span class="woocommerce-Price-currencySymbol">&#36;</span>75.00</bdi></span></del> <ins><span class="woocommerce-Price-amount amount"><bdi><span class="woocommerce-Price-currencySymbol">&#36;</span>50.00</bdi></span></ins> <span class="subscription-details"> / month</span></p>
  # product availability
  local availability="$( echo "$html" | grep -o -P '(?<=class="product-stock in-stock">).*?(?=</span>)|(?<=class="product-stock out-of-stock">).*?(?=</span>)' | remove-empty-lines | remove-html-tags | convert-html-entities | sed -r 's/^[Aa]vailability://g' | remove-preceding-whitespace )"
  #   * <span class="product-stock in-stock">Availability: <span class="stock">40 in stock</span></span>
  #   * <span class="product-stock out-of-stock">Availability: <span class="stock">SOLD OUT</span></span>
  # product category
  local category="$( echo "$html" | grep -o -P '(?<=class="posted_in">).*?(?=</span>)' | remove-empty-lines | remove-html-tags | convert-html-entities | sed -r 's/^[Cc]ategories:|^[Cc]ategory://g' | tr ',' "\n" | remove-preceding-whitespace )"
  #   * <span class="posted_in">Category: <a href="https://arkhavencomics.com/product-category/leather/" rel="tag">Leather Books</a></span>
  #   * <span class="posted_in">Categories: <a href="https://arkhavencomics.com/product-category/leather/" rel="tag">Leather Books</a>, <a href="https://arkhavencomics.com/product-category/subscriptions/" rel="tag">Subscriptions</a></span>
  # product tags
  local tags="$( echo "$html" | grep -o -P '(?<=class="tagged_as">).*?(?=</span>)' | remove-empty-lines | remove-html-tags | convert-html-entities | sed -r 's/^[Tt]ags:|^[Tt]ag://g' | tr ',' "\n" | remove-preceding-whitespace )"
  #   * <span class="tagged_as">Tags: <a href="https://arkhavencomics.com/product-tag/deluxe/" rel="tag">Deluxe</a>, <a href="https://arkhavencomics.com/product-tag/libraria/" rel="tag">Libraria</a></span>

  local json="$( \
  jq -rcn \
    --arg id "$id" \
    --arg url "$url" \
    --arg imageUrl "$imageUrl" \
    --arg title "$title" \
    --arg description "$description" \
    --arg price "$price" \
    --arg availability "$availability" \
    --argjson category "$(jq -n --arg category "$category" '$category | split("\n")')" \
    --argjson tags "$(jq -n --arg tags "$tags" '$tags | split("\n")')" \
  '{"id": $id, "title": $title, "price": $price, "availability": $availability, "category": $category, "tags": $tags, "url": $url, "imageUrl": $imageUrl,"description": $description}' \
  )"
  log-debug "extracted product properties: '$json'"
  echo "$json"
}

# 
function compare-product-fields {
  local i=0
  if (( $# == 0 )) ; then
    local stdin="$( cat < /dev/stdin )"
    local count="$( wc -l <<< "$stdin" )"
    log-info "comparing latest product's fields with previous records"
    while read -r json; do
      [[ -n "$json" ]] && compare-single-product-field 'false' "$json" || log-warn "compare-product-fields: missing input json, unable to compare product changes."
      i=$((i+1))
    done   <<< "$stdin"
    [[ -n "$stdin" ]] && compare-single-product-field "true" "$stdin" || log-warn "compare-product-fields: missing input json, unable to get deleted products."
  else
    local count="$( wc -l <<< "$@" )"
    while read -r json; do
      [[ -n "$json" ]] && compare-single-product-field 'false' "$json" || log-warn "compare-product-fields: missing input json, unable to compare product changes."
      i=$((i+1))
    done   <<< "$@"
    [[ -n "$@" ]] && compare-single-product-field "true" "$@" || log-warn "compare-product-fields: missing input json, unable to get deleted products"
  fi
}

# compares a products fields from previous to current
function compare-single-product-field {
  local get_removed=${1:?} # One of ['true','false'] to get removed products
  local refreshed_product=${2:?} # single new product if ${get_removed} == 'false' or all new products as ndjson if 'true'
  # - local loaded_products=${SCRIPT_LOADED_PRODUCT_DETAILS}
  local added='false'
  local removed='false'
  if [[ "${get_removed}" == 'true' ]]; then
    # removed -- handled when param 1 == 'true' (only run this once per script execution!)
    local final="$( prepare-product-export "${refreshed_product}" | jq -Src '. | keys | sort' )"
    local initial="$( jq -rcS '. | keys | sort' -- <<< "${SCRIPT_LOADED_PRODUCT_DETAILS}" )"
    # new products
    # - jq -nrc --argjson final "${final}" --argjson initial "${initial}" '($final | sort) - ($initial | sort)'
    # removed products - subtract two sorted list if ids and then use the different ids to get actual matching object as ndjson
    local matched_products="$( \
      jq -nrc --argjson final "${final}" --argjson initial "${initial}" '($initial | sort) - ($final | sort) | .[]' \
      | while read -r line; do jq -rc ".[\"${line}\"]" -- <<< "${SCRIPT_LOADED_PRODUCT_DETAILS}" ; done \
    )"
    if [[ -n "$matched_products" ]]; then
      removed='true'
      refreshed_product='{}'
    fi
  else
    local refreshed_product_id="$( jq -rc '.id' -- <<< "${refreshed_product}" )"
    local refreshed_product_url="$( jq -rc '.url' -- <<< "${refreshed_product}" )"
    local matched_products="$( \
      jq -rc \
      ".[\"${refreshed_product_id}\"]? as \$id_match | .[\"${refreshed_product_url}\"]? as \$url_match | if \$id_match then \$id_match else \$url_match end | select(. != null)" \
      -- <<< "${SCRIPT_LOADED_PRODUCT_DETAILS}" \
    )"
    # added -- if no matching product then product was (likely) added to store
    if [[ -n "$refreshed_product" && -z "$matched_products" ]]; then
      added='true'
      matched_products='{}'
    fi
  fi
  echo "${matched_products}" | remove-empty-lines \
  | while read -r matched_product; do
  local price="$(       jq -rcn --argjson refreshed "${refreshed_product}" --argjson matched "${matched_product}" '$refreshed.price? != $matched.price?' )"
  local instock="$(     jq -rcn --argjson refreshed "${refreshed_product}" --argjson matched "${matched_product}" '$refreshed.availability? != $matched.availability? and (if $refreshed.availability? then $refreshed.availability? else "" end | contains("SOLD OUT") | not)' )"
  local outofstock="$(  jq -rcn --argjson refreshed "${refreshed_product}" --argjson matched "${matched_product}" '$refreshed.availability? != $matched.availability? and (if $refreshed.availability? then $refreshed.availability? else "" end | contains("SOLD OUT"))' )"
  local category="$(    jq -rcn --argjson refreshed "${refreshed_product}" --argjson matched "${matched_product}" '(if $refreshed.category? then $refreshed.category?|sort else null end) != (if $matched.category then $matched.category?|sort else null end)' )"
  local tag="$(         jq -rcn --argjson refreshed "${refreshed_product}" --argjson matched "${matched_product}" '(if $refreshed.tags? then $refreshed.tags?|sort else null end) != (if $matched.tags then $matched.tags?|sort else null end)' )"
  local description="$( jq -rcn --argjson refreshed "${refreshed_product}" --argjson matched "${matched_product}" '$refreshed.description? != $matched.description?' )"
  local imageUrl="$(    jq -rcn --argjson refreshed "${refreshed_product}" --argjson matched "${matched_product}" '$refreshed.imageUrl? != $matched.imageUrl?' )"
  if [[ "$removed" == 'true' ]]; then
    instock='false'
    outofstock='true'
  fi

  local json="$( \
  jq -rcn \
    --arg removed "$removed" \
    --arg added "$added" \
    --arg price "$price" \
    --arg instock "$instock" \
    --arg outofstock "$outofstock" \
    --arg category "$category" \
    --arg tag "$tag" \
    --arg description "$description" \
    --arg imageUrl "$imageUrl" \
    --argjson from "${matched_product}" \
    --argjson to "${refreshed_product}" \
  '{"removed": $removed, "added": $added, "price": $price, "instock": $instock, "outofstock": $outofstock, "category": $category, "tag": $tag, "imageUrl": $imageUrl, "description": $description, "from": $from, "to": $to}' \
  )"
  log-debug "compared field changes: '$json'"
  echo "$json"
  done
}

function resend-alert-dlq {
  local filepath="$( yq -rc '.["dead-letter-queue"].path' <<< "$SCRIPT_CONFIG_CONTENT" )"
  local expanded_config="$( echo "$SCRIPT_CONFIG_CONTENT" | yq -rc '( .alerts | to_entries | ( [.[] | .value.default_settings as $default | {"key": .key, "value": {"config": ( .value.config | to_entries | [ .[] | {"key": .key, "value": ($default + .value | select(. != null)) } ] | from_entries ) } } ] ) | from_entries ) as $expanded | {"alerts":$expanded}' )"
  local trigger=''
  local provider=''
  function load-trigger-config {
    trigger_config="$(  jq -rc ".alerts | .[\"${provider}\"] | .config | .[\"${trigger}\"]" -- <<< "$expanded_config" )"
  }
  if [[ -n "$filepath" ]]; then
    local filepath="${SOURCE_DIR}/${filepath}"
    local content="$( cat "$filepath" 2>/dev/null )"
    if [[ -n "$content" ]]; then
      echo "$content" \
      | while read -r event; do
        provider="$( jq -rc '.["alert-provider"]' <<< "$event" )"
        trigger="$( jq -rc '.["alert-trigger"]' <<< "$event" )"
        load-trigger-config
        slack-product-alert "${trigger_config}" "${event}" "${trigger}" || true
      done
    else
      log-error "resend-alert-dlq: no alerts in dlq '$filepath'"
    fi
  else
    log-error "resend-alert-dlq: unable to load alerts in dlq, filepath is empty."
  fi
}

# alerts when configured changes are triggered (fields changed, send message)
function alert-product-changes {
  local i=0
  if (( $# == 0 )) ; then
    local stdin="$( cat < /dev/stdin )"
    local count="$( wc -l <<< "$stdin" )"
    resend-alert-dlq
    log-info "sending alerts for product changes based on configured triggers"
    while read -r json; do
      [[ -n "$json" ]] && alert-single-product-changed "$json" || log-warn "alert-product-changes: missing input json, unable to process alerts"
      i=$((i+1))
    done   <<< "$stdin"
  else
    local count="$( wc -l <<< "$@" )"
    resend-alert-dlq
    while read -r json; do
      [[ -n "$json" ]] && alert-single-product-changed "$json" || log-warn "alert-product-changes: missing input json, unable to process alerts"
      i=$((i+1))
    done   <<< "$@"
  fi
}


# alerts when single 'alert' event matches configured triggers
function alert-single-product-changed {
  local alerts_suppressed="$( get-suppress-alerts )"
  if [[ "$alerts_suppressed" == 'true' && "$SCRIPT_ALERTS_SUPPRESSED_OVERRIDE" != "true" ]]; then
    return 1
  fi
  local alert_event="${1:?}"
  local alert_providers="$( echo "$SCRIPT_CONFIG_CONTENT" | yq -rc '.alerts | keys | .[]' )"
  local expanded_config="$( echo "$SCRIPT_CONFIG_CONTENT" | yq -rc '( .alerts | to_entries | ( [.[] | .value.default_settings as $default | {"key": .key, "value": {"config": ( .value.config | to_entries | [ .[] | {"key": .key, "value": ($default + .value | select(. != null)) } ] | from_entries ) } } ] ) | from_entries ) as $expanded | {"alerts":$expanded}' )"
  
  local removed_alert_event="$(     jq -rc '.removed? == "true"       or .removed? == true' -- <<< "$alert_event" )"
  local added_alert_event="$(       jq -rc '.added? == "true"         or .added? == true'  -- <<< "$alert_event" )"
  local price_alert_event="$(       jq -rc '.price? == "true"         or .price? == true' -- <<< "$alert_event" )"
  local instock_alert_event="$(     jq -rc '.instock? == "true"       or .instock? == true'  -- <<< "$alert_event" )"
  local outofstock_alert_event="$(  jq -rc '.outofstock? == "true"    or .outofstock? == true' -- <<< "$alert_event" )"
  local category_alert_event="$(    jq -rc '.category? == "true"      or .category? == true'  -- <<< "$alert_event" )"
  local tag_alert_event="$(         jq -rc '.tag? == "true"           or .tag? == true'  -- <<< "$alert_event" )"
  local description_alert_event="$( jq -rc '.description? == "true"   or .description? == true'  -- <<< "$alert_event" )"
  local imageUrl_alert_event="$(    jq -rc '.imageUrl? == "true"      or .imageUrl? == true'  -- <<< "$alert_event" )"

  function load-trigger-config {
    trigger_config="$(  jq -rc ".alerts | .[\"${provider}\"] | .config | .[\"${trigger}\"]" -- <<< "$expanded_config" )"
  }
  function is-trigger-enabled {
    trigger_enabled="$( jq -rc "if .enabled? then (.enabled | select(. != null)) else false end" -- <<< "$trigger_config" )"
  }

  echo "$alert_providers" \
  | while read -r provider; do
    ######events="$( jq -rc ".alerts | .[\"${provider}\"] | .config | keys | .[]" -- <<< "$expanded_config" )"
    if [[ "$removed_alert_event" == 'true' ]]; then
      # if the event is for a removed product, wait for the matching config and if true send alert
      trigger='removed'
      load-trigger-config; is-trigger-enabled;
      if [[ "$trigger_enabled" == 'true' ]]; then
        slack-product-alert "${trigger_config}" "${alert_event}" "${trigger}"
        break;
      fi
    elif [[ "$added_alert_event" == 'true' ]]; then
      # if the event is for a added product, wait for the matching config and if true send alert
      trigger='added'
      load-trigger-config; is-trigger-enabled;
      if [[ "$trigger_enabled" == 'true' ]]; then
        slack-product-alert "${trigger_config}" "${alert_event}" "${trigger}"
        break;
      fi
    else
      if [[ "$price_alert_event" == 'true' ]]; then
        trigger='price'
        load-trigger-config; is-trigger-enabled;
        if [[ "$trigger_enabled" == 'true' ]]; then
          slack-product-alert "${trigger_config}" "${alert_event}" "${trigger}"
        fi
      fi
      if [[ "$instock_alert_event" == 'true' ]]; then
        trigger='instock'
        load-trigger-config; is-trigger-enabled;
        if [[ "$trigger_enabled" == 'true' ]]; then
          slack-product-alert "${trigger_config}" "${alert_event}" "${trigger}"
        fi
      fi
      if [[ "$outofstock_alert_event" == 'true' ]]; then
        trigger='outofstock'
        load-trigger-config; is-trigger-enabled;
        if [[ "$trigger_enabled" == 'true' ]]; then
          slack-product-alert "${trigger_config}" "${alert_event}" "${trigger}"
        fi
      fi
      if [[ "$category_alert_event" == 'true' ]]; then
        trigger='category'
        load-trigger-config; is-trigger-enabled;
        if [[ "$trigger_enabled" == 'true' ]]; then
          slack-product-alert "${trigger_config}" "${alert_event}" "${trigger}"
        fi
      fi
      if [[ "$tag_alert_event" == 'true' ]]; then
        trigger='tag'
        load-trigger-config; is-trigger-enabled;
        if [[ "$trigger_enabled" == 'true' ]]; then
          slack-product-alert "${trigger_config}" "${alert_event}" "${trigger}"
        fi
      fi
      if [[ "$description_alert_event" == 'true' ]]; then
        trigger='description'
        load-trigger-config; is-trigger-enabled;
        if [[ "$trigger_enabled" == 'true' ]]; then
          slack-product-alert "${trigger_config}" "${alert_event}" "${trigger}"
        fi
      fi
      if [[ "$imageUrl_alert_event" == 'true' ]]; then
        trigger='imageUrl'
        load-trigger-config; is-trigger-enabled;
        if [[ "$trigger_enabled" == 'true' ]]; then
          slack-product-alert "${trigger_config}" "${alert_event}" "${trigger}"
        fi
      fi
    fi
  done
}

# slack message alerting implementation (vs. email, teams, twitter, ect,ect)
function slack-product-alert {
  local config="${1:?}"
  local event="${2:?}"
  local trigger="${3:?}"
  local alert_provider='slack'

  local reqURL="$( jq -rc '.url' <<< "$config" )"
  local channel="$( jq -rc '.channel' <<< "$config" )"
  local username="$( jq -rc '.username' <<< "$config" )"
  local icon_emoji="$( jq -rc '.icon_emoji' <<< "$config" )"
  
  local field="$( jq -rc ".[\"${trigger}\"]?" <<< "$event" )"
  local from_title="$( jq -rc ".from.title?" <<< "$event" )"
  local to_title="$( jq -rc ".to.title?" <<< "$event" )"

  function add-strikethrough-mrkdwn {
    if (( $# == 0 )) ; then
      local input="$( cat < /dev/stdin )"
    else
      local input="$( cat <<< "$@" )"
    fi
    local non_ws="$(echo "$input" | remove-empty-lines)"
    if [[ -n "$non_ws" ]]; then
      echo "~$non_ws~"
    fi
  }
  function remove-strikethrough-mrkdwn {
    if (( $# == 0 )) ; then
      local input="$( cat < /dev/stdin )"
    else
      local input="$( cat <<< "$@" )"
    fi
    echo "$input" | sed ':a;s/~\(.*\)~/\1/;ta;'
  }
  function remove-bold-mrkdwn {
    if (( $# == 0 )) ; then
      local input="$( cat < /dev/stdin )"
    else
      local input="$( cat <<< "$@" )"
    fi
    echo "$input" | sed ':a;s/\*\(.*\)\*/\1/;ta;'
  }
  function remove-italic-mrkdwn {
    if (( $# == 0 )) ; then
      local input="$( cat < /dev/stdin )"
    else
      local input="$( cat <<< "$@" )"
    fi
    echo "$input" | sed ':a;s/_\(.*\)_/\1/;ta;'
  }
  function remove-all-mrkdwn {
    if (( $# == 0 )) ; then
      local input="$( cat < /dev/stdin )"
    else
      local input="$( cat <<< "$@" )"
    fi
    echo "$input" | remove-italic-mrkdwn | remove-bold-mrkdwn | remove-strikethrough-mrkdwn
  }
  function strikethrough-matching-phrases {
    if (( $# == 0 )) ; then
      local input="$( cat < /dev/stdin )"
    else
      local input="$( cat <<< "$@" )"
    fi
    if [[ "$input" == 'SOLD OUT' ]]; then
      add-strikethrough-mrkdwn <<< "$input"
    else 
      echo "$input"
    fi
  }
  function convert-markdown-mrkdwn {
    if (( $# == 0 )) ; then
      local input="$( cat < /dev/stdin )"
    else
      local input="$( cat <<< "$@" )"
    fi
    echo "$input" \
    | sed ':a;s/\*\*\*\(.*\)\*\*\*/<<[bolditalic]>>\1<<[\\bolditalic]>>/;ta;' \
    | sed ':a;s/\*\*\(.*\)\*\*/<<[bold]>>\1<<[\\bold]>>/;ta;' \
    | sed ':a;s/\*\(.*\)\*/<<[italic]>>\1<<[\\italic]>>/;ta;' \
    | sed ':a;s/___\(.*\)___/<<[bolditalic]>>\1<<[\\bolditalic]>>/;ta;' \
    | sed ':a;s/__\(.*\)__/<<[bold]>>\1<<[\\bold]>>/;ta;' \
    | sed ':a;s/_\(.*\)_/<<[italic]>>\1<<[\\italic]>>/;ta;' \
    | sed ':a;s/<<\[bolditalic\]>>\(.*\)<<\[\\bolditalic\]>>/_\*\1\*_/;ta;' \
    | sed ':a;s/<<\[bold\]>>\(.*\)<<\[\\bold\]>>/\*\1\*/;ta;' \
    | sed ':a;s/<<\[italic\]>>\(.*\)<<\[\\italic\]>>/_\1_/;ta;' \
    | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g' \
    | sed -e ':a' -e 'N' -e '$!ba' -e 's/\r/\\r/g'
  }
  function format-description {
    if (( $# == 0 )) ; then
      local input="$( cat < /dev/stdin )"
    else
      local input="$( cat <<< "$@" )"
    fi
    # strip 'description' at top and then '----------' separator and then any preceding whitespace lines
    local stop_comsuming=0
    local i=0
    echo "$input" | grep -vie 'description' | grep -vE '^[\S]*[-]{3}' | while read -r line; do 
      [[ $i == 0 ]] && echo "**Description:**"
      if [[ "$stop_comsuming" == '0' ]]; then
        echo "$line" | grep -q -v -e '^[[:space:]]*$' || stop_comsuming=1
      else
        echo "$line"
      fi
      i=$((i+1))
    done | convert-markdown-mrkdwn
  }

  if [[ "${trigger}" == 'added' ]]; then
    local to_url="$( jq -rc ".to.url?" <<< "$event" )"
    local to_price="$( jq -rc ".to.price?" <<< "$event" )"
    local to_availability="$( jq -rc ".to.availability?" <<< "$event" | strikethrough-matching-phrases )"
    local to_category="$( jq -rc '.to.category? | join(", ")' <<< "$event" | remove-all-mrkdwn )"
    local to_tags="$( jq -rc '.to.tags? | join(", ")' <<< "$event" | remove-all-mrkdwn )"
    local to_imageUrl="$( jq -rc '.to.imageUrl?' <<< "$event" )"
    local to_description="$( jq -rc '.to.description?' <<< "$event" | format-description )"
data=$( cat << EOF
payload={
  "channel": "${channel}",
  "username": "${username}",
  "icon_emoji": "${icon_emoji}",
  "text": "Added: ${to_title}",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "<${to_url}|*${to_title}*>\n*Price*: ${to_price}\n*Availability:* ${to_availability}\n*Category:* ${to_category}\n*Tag:* ${to_tags}"
      },
      "accessory": {
        "type": "image",
        "image_url": "${to_imageUrl}",
        "alt_text": "${to_title} image"
      }
    },
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "${to_description}"
        }
      ]
    }
  ]
}
EOF
)
  elif [[ "${trigger}" == 'removed' ]]; then
    local from_url="$( jq -rc '.from.url?' <<< "$event" )"
    local from_imageUrl="$( jq -rc '.from.imageUrl?' <<< "$event" )"
    data=$( cat << EOF
payload={
  "channel": "${channel}",
  "username": "${username}",
  "icon_emoji": "${icon_emoji}",
  "text": "*Deleted:* ${from_title}",
  "blocks": [
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "*Deleted :x::* <${from_url}|*${from_title}*>"
        },
        {
          "type": "image",
          "image_url": "${from_imageUrl}",
          "alt_text": "${from_title} image"
        }
      ]
    }
  ]
}
EOF
)
  elif [[ "${trigger}" == 'price' ]]; then
    local event_from="$( jq -rc ".from.price?" <<< "$event" | remove-all-mrkdwn )"
    local event_to="$( jq -rc ".to.price?" <<< "$event" | remove-all-mrkdwn )"
    local to_url="$( jq -rc '.to.url?' <<< "$event" )"
    local to_imageUrl="$( jq -rc '.to.imageUrl?' <<< "$event" )"
    data=$( cat << EOF
payload={
  "channel": "${channel}",
  "username": "${username}",
  "icon_emoji": "${icon_emoji}",
  "text": "Price changed: ${to_title} ~${event_from}~ | ${event_to}",
  "blocks": [
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "*Price changed:* <${to_url}|*${to_title}*>\t~${event_from}~\t|\t${event_to}"
        },
        {
          "type": "image",
          "image_url": "${to_imageUrl}",
          "alt_text": "${to_title} image"
        }
      ]
    }
  ]
}
EOF
)
  elif [[ "${trigger}" == 'category' ]]; then
    local event_from="$( jq -rc '.from.category? | join(", ")' <<< "$event" | remove-all-mrkdwn )"
    local event_to="$( jq -rc '.to.category? | join(", ")' <<< "$event" | remove-all-mrkdwn )"
    local to_url="$( jq -rc '.to.url?' <<< "$event" )"
    local to_imageUrl="$( jq -rc '.to.imageUrl?' <<< "$event" )"
    data=$( cat << EOF
payload={
  "channel": "${channel}",
  "username": "${username}",
  "icon_emoji": "${icon_emoji}",
  "text": "Category changed: ${to_title} ~${event_from}~ | ${event_to}",
  "blocks": [
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "*Category changed:* <${to_url}|*${to_title}*>\t~${event_from}~\t|\t${event_to}"
        },
        {
          "type": "image",
          "image_url": "${to_imageUrl}",
          "alt_text": "${to_title} image"
        }
      ]
    }
  ]
}
EOF
)
  elif [[ "${trigger}" == 'tag' ]]; then
    local event_from="$( jq -rc '.from.tags? | join(", ")' <<< "$event" | remove-all-mrkdwn )"
    local event_to="$( jq -rc '.to.tags? | join(", ")' <<< "$event" | remove-all-mrkdwn )"
    local to_url="$( jq -rc '.to.url?' <<< "$event" )"
    local to_imageUrl="$( jq -rc '.to.imageUrl?' <<< "$event" )"
    data=$( cat << EOF
payload={
  "channel": "${channel}",
  "username": "${username}",
  "icon_emoji": "${icon_emoji}",
  "text": "Tags changed: ${to_title} ~${event_from}~ | ${event_to}",
  "blocks": [
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "*Tags changed:* <${to_url}|*${to_title}*>\t~${event_from}~\t|\t${event_to}"
        },
        {
          "type": "image",
          "image_url": "${to_imageUrl}",
          "alt_text": "${to_title} image"
        }
      ]
    }
  ]
}
EOF
)
  elif [[ "${trigger}" == 'description' ]]; then
    local to_url="$( jq -rc '.to.url?' <<< "$event" )"
    local to_imageUrl="$( jq -rc '.to.imageUrl?' <<< "$event" )"
    local description_diff="$(diff  -w -B -Z -E --suppress-common-lines \
    --old-line-format='~%l~
' \
    --new-line-format='%l
' \
    --unchanged-line-format='%l
' \
<(jq -rc ".from.description?" <<< "$event" | format-description | sed -e 's/\\n/\n/g') \
<(jq -rc ".to.description?" <<< "$event" | format-description | sed -e 's/\\n/\n/g') \
| sed ':a;s/~\(\S*\)~/\1/;ta;' \
| format-description)"
    data=$( cat << EOF
payload={
  "channel": "${channel}",
  "username": "${username}",
  "icon_emoji": "${icon_emoji}",
  "text": "Description changed: ${to_title}",
  "blocks": [
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "*Description changed:* <${to_url}|*${to_title}*>"
        },
        {
          "type": "image",
          "image_url": "${to_imageUrl}",
          "alt_text": "${to_title} image"
        }
      ]
    },
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "${description_diff}"
        }
      ]
    }
  ]
}
EOF
)
  elif [[ "${trigger}" == 'imageUrl' ]]; then
    local to_url="$( jq -rc '.to.url?' <<< "$event" | remove-all-mrkdwn )"
    local from_imageUrl="$( jq -rc '.from.imageUrl?' <<< "$event" )"
    local to_imageUrl="$( jq -rc '.to.imageUrl?' <<< "$event" )"
    data=$( cat << EOF
payload={
  "channel": "${channel}",
  "username": "${username}",
  "icon_emoji": "${icon_emoji}",
  "text": "ImageUrl changed: ${to_title} ~${from_imageUrl}~ | ${to_imageUrl}",
  "blocks": [
		{
			"type": "context",
			"elements": [
				{
					"type": "mrkdwn",
					"text": "*ImageUrl changed:* <${to_url}|*${to_title}*>\t<${from_imageUrl}|previous>\t*|*\t<${to_imageUrl}|new>"
				},
				{
					"type": "image",
					"image_url": "${from_imageUrl}",
					"alt_text": "Previous ${to_title} image"
				},
				{
					"type": "image",
					"image_url": "${to_imageUrl}",
					"alt_text": "New ${to_title} image"
				}
			]
		}
  ]
}
EOF
)
  elif [[ "${trigger}" == 'instock' ]]; then
    local event_from="$( jq -rc ".from.availability? | select(. != null)" <<< "$event" | add-strikethrough-mrkdwn )"
    local event_to="$( jq -rc ".to.availability? | select(. != null)" <<< "$event" )"
    local to_url="$( jq -rc '.to.url?' <<< "$event" )"
    local to_imageUrl="$( jq -rc '.to.imageUrl?' <<< "$event" )"
    data=$( cat << EOF
payload={
  "channel": "${channel}",
  "username": "${username}",
  "icon_emoji": "${icon_emoji}",
  "text": "In Stock: ${to_title} ${event_from} | ${event_to}",
  "blocks": [
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "*In Stock:* <${to_url}|*${to_title}*>\t${event_from}\t|\t${event_to}"
        },
        {
          "type": "image",
          "image_url": "${to_imageUrl}",
          "alt_text": "${to_title} image"
        }
      ]
    }
  ]
}
EOF
)
  elif [[ "${trigger}" == 'outofstock' ]]; then
    local event_from="$( jq -rc ".from.availability? | select(. != null)" <<< "$event" | add-strikethrough-mrkdwn )"
    local event_to="$( jq -rc ".to.availability? | select(. != null)" <<< "$event" )"
    local to_url="$( jq -rc '.to.url?' <<< "$event" )"
    local to_imageUrl="$( jq -rc '.to.imageUrl?' <<< "$event" )"
    data=$( cat << EOF
payload={
  "channel": "${channel}",
  "username": "${username}",
  "icon_emoji": "${icon_emoji}",
  "text": "Out of Stock: ${to_title} ${event_from} | ${event_to}",
  "blocks": [
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "*Out of Stock:* <${to_url}|*${to_title}*>\t${event_from}\t|\t${event_to}"
        },
        {
          "type": "image",
          "image_url": "${to_imageUrl}",
          "alt_text": "${to_title} image"
        }
      ]
    }
  ]
}
EOF
)
  fi
  local REQ_METHOD="POST"
  local RES_BODY=''
  local RES_CODE=0
  local RET=''
  log-info "slack alert: ${trigger} $( [[ -n "${to_title}" && "${to_title}" != 'null' ]] && echo "${to_title}" || echo "${from_title}" )"
  log-debug "slack-product-alert: $( echo "$data" | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g' )"
  echo "$data" | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g' >> "$SCRIPT_FAILED_SLACK_ALERTS_TMP_FILEPATH"
  local curl_stderror_filepath="/tmp/${SOURCE_NAME}-slack-product-alert-$(generate-uuid)"
  local RES="$( \
  curl -qSsw '\n%{http_code}' "$reqURL" \
    -X "$REQ_METHOD" \
    --data-urlencode "$data" \
    2>>"$SCRIPT_LOGGING_FILEPATH" \
  )"
  if [[ -f "$curl_stderror_filepath" ]]; then
    local curl_error="$( cat "$curl_stderror_filepath" )"
    rm -f "$curl_stderror_filepath" || :
  fi
  if [[ -n "$curl_error" ]]; then
    log-error "curl-stderror: $( format-error "$curl_error" )"
  fi
  RET=$? && RES_BODY="$(echo "$RES" | grep -vE '^[0-9][0-9][0-9]$')" && RES_CODE="$(echo "$RES" | grep -E '^[0-9][0-9][0-9]$' | tail -1 |rev| cut -d$'\n' -f1 |rev)"
  if [[ -n "$( echo "${RES_CODE}" | grep -e '2[0-9][0-9]' )" ]]; then
    if [[ -z "$RES_BODY" ]]; then
      log-warn "curl '$REQ_METHOD' on '$reqURL' returned empty body!"
    else
      return 0
    fi
  else
    log-warn "server returned http_code: $RES_CODE http_body: '$( format-error "$RES_BODY" )'"
    export-alert-dlq "${event}" "${trigger}" "${alert_provider}"
    return 1
  fi
}

# exports alerts to dlq file, where they can be re-processed later.
function export-alert-dlq {
  local event="${1:?}"
  local trigger="${2:?}"
  local provider="${3:?}"
  local filepath="$( yq -rc '.["dead-letter-queue"].path' <<< "$SCRIPT_CONFIG_CONTENT" )"
    if [[ -n "$filepath" ]]; then
      filepath="${SOURCE_DIR}/${filepath}"
      jq -rc ". | .[\"alert-provider\"] = \"${provider}\" | .[\"alert-trigger\"] = \"${trigger}\"" <<< "${event}" >> "${filepath}"
    else
      log-error "export-alert-dlq: unable to export alert to dlq, filepath is missing."
    fi
}

# prepares product details from ndjson to single json obj
function prepare-product-export {
  local ndjson="${1:?}"
  # convert ndjson into yaml where each line is a json and its id property is the key and the value is the object. 
  #  - All ndjson lines are combined into a single object this way
  #  - if id is missing or null, then use the url the key each ndjson
  # {"url":"https://arkhavencomics.com/product/4d-warfare","imageUrl":"https://arkhavencomics.com/wp-content/uploads/2018/11/4D_Warfare_960.jpg","title":"4D Warfare","price":"","availability":"SOLD OUT","category":["Books","Nonfiction","Politics","War"],"tags":["Jack Posobiec"]}
  # {"url":"https://arkhavencomics.com/product/4gw-handbook-audiobook","imageUrl":"https://arkhavencomics.com/wp-content/uploads/2019/01/4GW_512.jpg","title":"4th Generation Warfare Handbook (audiobook+)","price":"$11.99","availability":"","category":["Audiobooks","Books","History","Nonfiction","War"],"tags":["audiobook","William S. Lind"]}
  # {"url":"https://arkhavencomics.com/product/4th-generation-warfare-handbook","imageUrl":"https://arkhavencomics.com/wp-content/uploads/2018/11/4GW_960.jpg","title":"4th Generation Warfare Handbook","price":"$6.99","availability":"","category":["Books","Nonfiction","War"],"tags":["William S. Lind"]}
  echo "$ndjson" | jq -src 'map({(if .id? != null and .id? != "" then .id|tostring else .url|tostring end): .}) | add'
}

# [over]writes (saves) the latest product details to file
function export-product-details {
  local filepath="${1:?}"
  local details="${2}" # as ndjson
  if [[ -n "$details" ]]; then
    if [[ -f "$filepath" ]]; then
      log-info "overwriting previous products file '${filepath}'"
    else
      log-info "starting new products file '${filepath}'"
    fi
    prepare-product-export "$details" | yq -y '.' > "$filepath"
  else
    log-error "export-product-details: unable to export, no latest/up-to-date products found"
  fi
}
